import Darwin

// MARK: – AudioCoreSendHighpass
//
// S-06 (`.agent_handoff/latest_codex.md`, Runde 054), Scope B: einfacher,
// eigenstaendiger Highpass-Baustein fuer spaetere Echo-/Hall-Sends
// (`SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 6.3: "optionaler zweiter
// einfacher Highpass vor dem Raum-Send, besonders fuer Bass"). Bewusst KEIN
// zweiter `AudioCoreStateVariableFilter` — ein klassischer Ein-Pol-Highpass
// (Differenzierer-Topologie) reicht fuer den Zweck "tiefe Anteile vor
// Echo/Hall kontrolliert reduzieren" und bleibt bei jedem Cutoff-Wert
// unbedingt stabil (kein Resonanz-/Q-Parameter, kein Ueberschwingen).
//
// Noch KEIN Send-Routing im Produkt (Nicht-Scope S-06) — reiner,
// eigenstaendiger DSP-Baustein.
//
// Realtime-Vertrag: `process(_:)` alloziiert nicht, sperrt nicht, nutzt
// keine Dispatch-/Task-/Actor-Ausfuehrung und schreibt nicht (kein `print`).

public struct AudioCoreSendHighpassParameters: Sendable, Equatable {

    /// Cutoff, 0...1, logarithmisch auf 5 Hz...2.000 Hz abgebildet — bewusst
    /// ein engerer, tieferer Bereich als der Voice-SVF (Scope A), weil
    /// dieser Baustein gezielt Bassanteile vor einem Raum-Send abschneidet,
    /// nicht als musikalisches Klangfilter dient.
    public var cutoff: Float

    public init(cutoff: Float = 0.0) {
        self.cutoff = AudioCoreSendHighpassParameters.clampUnit(cutoff)
    }

    fileprivate static func clampUnit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return max(0.0, min(value, 1.0))
    }
}

public struct AudioCoreSendHighpass: Sendable, Equatable {

    public private(set) var sampleRate: Double
    public private(set) var parameters: AudioCoreSendHighpassParameters

    // Ein-Pol-Highpass-Koeffizient (0...1), aus Cutoff/SampleRate abgeleitet.
    private var alpha: Float = 0.0

    // Zustand: letzter Eingabewert und letzter Ausgabewert.
    private var previousInput: Float = 0.0
    private var previousOutput: Float = 0.0

    public init(sampleRate: Double, parameters: AudioCoreSendHighpassParameters = AudioCoreSendHighpassParameters()) {
        self.sampleRate = AudioCoreSendHighpass.safeSampleRate(sampleRate)
        self.parameters = parameters
        recomputeCoefficient()
    }

    // MARK: – Parameter

    public mutating func setParameters(_ newParameters: AudioCoreSendHighpassParameters) {
        parameters = newParameters
        recomputeCoefficient()
    }

    public mutating func setSampleRate(_ newSampleRate: Double) {
        sampleRate = AudioCoreSendHighpass.safeSampleRate(newSampleRate)
        recomputeCoefficient()
    }

    // MARK: – Reset
    //
    // Setzt Eingabe-/Ausgabezustand zurueck. Dieselbe Eingabefolge nach
    // `reset()` reproduziert denselben Ausgabeverlauf wie eine frische
    // Instanz mit identischen Parametern.
    public mutating func reset() {
        previousInput = 0.0
        previousOutput = 0.0
    }

    // MARK: – Koeffizient
    //
    // Klassischer Ein-Pol-Highpass (RC-Differenzierer):
    // alpha = sampleRate / (sampleRate + 2*pi*cutoffHz).
    // Fuer jede endliche, positive Cutoff-/SampleRate-Kombination liegt
    // alpha immer im halboffenen Intervall (0, 1] — kein Einfrieren, keine
    // Divergenz.

    private mutating func recomputeCoefficient() {
        let freqMin: Float = 5.0
        let freqMax: Float = 2_000.0
        let cutoffHz = freqMin * pow(freqMax / freqMin, parameters.cutoff)

        let sr = Float(sampleRate)
        let raw = sr / (sr + 2.0 * Float.pi * cutoffHz)
        alpha = raw.isFinite ? max(0.0001, min(raw, 1.0)) : 1.0
    }

    private static func safeSampleRate(_ value: Double) -> Double {
        value.isFinite && value > 0 ? value : 44_100.0
    }

    // MARK: – DSP-Render
    //
    // Ein Sample-Schritt. Kein Heap-Zugriff, kein Alloc, kein Lock, keine
    // Dispatch-/Task-/Actor-Nutzung, kein `print`.
    @discardableResult
    public mutating func process(_ input: Float) -> Float {
        let x = input.isFinite ? input : 0

        var output = alpha * (previousOutput + x - previousInput)
        if !output.isFinite { output = 0 }

        previousInput = x
        previousOutput = output
        return output
    }
}
