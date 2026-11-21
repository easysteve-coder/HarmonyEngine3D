import Darwin

// MARK: – AudioCoreStateVariableFilter
//
// S-06 (`.agent_handoff/latest_codex.md`, Runde 054), Scope A: stabiler
// State-Variable-Filter (Lowpass/Bandpass/Highpass) fuer die Atmospheric
// Voice (`SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 6.3). Implementiert die
// oeffentlich dokumentierte Zero-Delay-Feedback-Topologie ("Topology-
// Preserving Transform") nach Andrew Simpers "Cytomic SVF"-Technical-Paper
// (frei verfuegbare Formelbeschreibung, kein proprietaerer Code/keine
// proprietaere Bibliothek) — dieselbe mathematische Familie wie in
// zahlreichen frei dokumentierten VA-Filterbeschreibungen, ohne Uebernahme
// von Fremdcode.
//
// Bewusst KEINE Ladder-Simulation und kein Oversampling (Scope-Vorgabe) —
// nur eine einfache, im gesamten Parameterbereich stabile 2-Pol-Topologie,
// die alle drei Modi aus einem gemeinsamen Zustandspaar (`ic1eq`/`ic2eq`)
// ableitet.
//
// Realtime-Vertrag: `process(_:mode:)` alloziiert nicht, sperrt nicht,
// nutzt keine Dispatch-/Task-/Actor-Ausfuehrung und schreibt nicht (kein
// `print`). Reine Gleitkomma-Arithmetik auf zwei Zustandsvariablen.

public enum AudioCoreSVFMode: Sendable, Equatable, CaseIterable {
    case lowpass
    case bandpass
    case highpass
}

public struct AudioCoreSVFParameters: Sendable, Equatable {

    /// Cutoff, 0...1, logarithmisch auf 20 Hz...20.000 Hz abgebildet
    /// (identische Kurve zu `AudioCoreVoice.calcBiquadLowpassCoefficients`).
    public var cutoff: Float
    /// Resonanz, 0...1, auf Q 0.5...20 abgebildet (identischer Bereich zu
    /// `AudioCoreVoice.calcBiquadLowpassCoefficients`).
    public var resonance: Float

    public init(cutoff: Float = 1.0, resonance: Float = 0.0) {
        self.cutoff = AudioCoreSVFParameters.clampUnit(cutoff)
        self.resonance = AudioCoreSVFParameters.clampUnit(resonance)
    }

    fileprivate static func clampUnit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return max(0.0, min(value, 1.0))
    }
}

public struct AudioCoreStateVariableFilter: Sendable, Equatable {

    public private(set) var sampleRate: Double
    public private(set) var parameters: AudioCoreSVFParameters

    // Koeffizienten aus Cutoff/Resonanz/SampleRate (bei Parameteraenderung neu berechnet).
    private var a1: Float = 1.0
    private var a2: Float = 0.0
    private var a3: Float = 0.0
    private var k: Float = 2.0

    // Zustandsvariablen ("Zero-Delay-Feedback"-Integratoren), zurueckgesetzt bei reset().
    private var ic1eq: Float = 0.0
    private var ic2eq: Float = 0.0

    public init(sampleRate: Double, parameters: AudioCoreSVFParameters = AudioCoreSVFParameters()) {
        self.sampleRate = AudioCoreStateVariableFilter.safeSampleRate(sampleRate)
        self.parameters = parameters
        recomputeCoefficients()
    }

    // MARK: – Parameter

    public mutating func setParameters(_ newParameters: AudioCoreSVFParameters) {
        parameters = newParameters
        recomputeCoefficients()
    }

    public mutating func setSampleRate(_ newSampleRate: Double) {
        sampleRate = AudioCoreStateVariableFilter.safeSampleRate(newSampleRate)
        recomputeCoefficients()
    }

    // MARK: – Reset
    //
    // Setzt ausschliesslich den internen Filterzustand zurueck (Koeffizienten
    // bleiben erhalten). Dieselbe Eingabefolge nach `reset()` reproduziert
    // denselben Ausgabeverlauf wie eine frische Instanz mit identischen
    // Parametern.
    public mutating func reset() {
        ic1eq = 0.0
        ic2eq = 0.0
    }

    // MARK: – Koeffizienten
    //
    // Cutoff-Kurve identisch zu `AudioCoreVoice.calcBiquadLowpassCoefficients`
    // (20...20.000 Hz logarithmisch), zusaetzlich defensiv auf einen sicheren
    // Abstand zur Nyquist-Grenze begrenzt: `tan(pi * f / sampleRate)` divergiert,
    // wenn `f` sich `sampleRate / 2` naehert.

    private mutating func recomputeCoefficients() {
        let freqMin: Float = 20.0
        let freqMax: Float = 20_000.0
        let f0 = freqMin * pow(freqMax / freqMin, parameters.cutoff)

        let nyquistSafe = max(1.0, Float(sampleRate) * 0.49)
        let f0safe = max(1.0, min(f0, nyquistSafe))

        let q = 0.5 + parameters.resonance * 19.5
        k = 1.0 / q

        let g = tanf(Float.pi * f0safe / Float(sampleRate))
        let denom = 1.0 + g * (g + k)
        a1 = denom.isFinite && denom != 0 ? 1.0 / denom : 1.0
        a2 = g * a1
        a3 = g * a2
    }

    private static func safeSampleRate(_ value: Double) -> Double {
        value.isFinite && value > 0 ? value : 44_100.0
    }

    // MARK: – DSP-Render
    //
    // Ein Sample-Schritt. Liefert Lowpass, Bandpass oder Highpass aus
    // demselben Zustandspaar, je nach `mode`. Kein Heap-Zugriff, kein Alloc,
    // kein Lock, keine Dispatch-/Task-/Actor-Nutzung, kein `print`.
    @discardableResult
    public mutating func process(_ input: Float, mode: AudioCoreSVFMode) -> Float {
        let x = input.isFinite ? input : 0

        let v3 = x - ic2eq
        let v1 = a1 * ic1eq + a2 * v3
        let v2 = ic2eq + a2 * ic1eq + a3 * v3

        var nextIc1eq = 2.0 * v1 - ic1eq
        var nextIc2eq = 2.0 * v2 - ic2eq
        if !nextIc1eq.isFinite { nextIc1eq = 0 }
        if !nextIc2eq.isFinite { nextIc2eq = 0 }
        ic1eq = nextIc1eq
        ic2eq = nextIc2eq

        let output: Float
        switch mode {
        case .lowpass:  output = v2
        case .bandpass: output = v1
        case .highpass: output = x - k * v1 - v2
        }
        return output.isFinite ? output : 0
    }
}
