import Darwin

// MARK: – AudioCoreVoice
//
// S-02a (`.agent_handoff/latest_codex.md`, Runde 046): einzelne synthetisierte
// Stimme des `HarmonyAudioCore`-Fundaments — Wellenformgenerator + Biquad-
// Tiefpassfilter + ADSR-Huellkurve + Constant-Power-Pan.
//
// Bewusst behavior-nahe Portierung der frueheren `SynthVoice`
// (`Sources/HarmonyEngine3D/SynthVoice.swift`, entfernt in S-02b/Runde 047,
// nachdem `VoicePool` vollstaendig auf `AudioCoreVoice` umgestellt wurde) —
// identische Formeln fuer Frequenz, Wellenform-Synthese, Amp-Skalierung,
// ADSR-Raten, Biquad-Koeffizienten und Pan-Gains. Was bewusst NICHT im Core
// liegt:
//
//   – Voice-Pool/Voice-Stealing/Unison-Verteilung: sitzt weiterhin in
//     `VoicePool` (`Sources/HarmonyEngine3D/SynthNode.swift`), nicht im Core.
//   – Kopplung an eine konkrete Audio-Engine/Render-Closure: `AudioCoreVoice`
//     kennt weder `AVAudioSourceNode` noch `NoteEventQueue`. Der Aufrufer
//     liefert Sample-Rate, Parameter und Events selbst und ruft `render()`
//     auf vom Aufrufer bereitgestellten Puffern auf.
//
// Pure Value Type (struct) – kein Referenztyp enthalten, kein Heap-Zugriff
// im DSP-Pfad. `render()` alloziert nicht, sperrt nicht, nutzt keine
// Dispatch-/Task-/Actor-Ausfuehrung und schreibt nicht (kein `print`) —
// seit S-02b der aktive Echtzeit-Rendercallback-Pfad von `SynthNode`.
//
// Threading-Vertrag: wie die fruehere `SynthVoice` kein eigener —
// `AudioCoreVoice` synchronisiert nichts. Der Aufrufer (`VoicePool`,
// serialisiert ueber `AudioEngine.commandQueue`) traegt die Verantwortung.

public struct AudioCoreVoice: Sendable {

    // MARK: – Zustand (privat: fester, kleiner Render-API-Vertrag nach aussen)

    public private(set) var stage: AudioCoreADSRStage = .idle

    /// MIDI-Note dieser Stimme (read-only), damit ein Aufrufer (z. B. ein
    /// Voice-Pool, S-02b) NoteOff-Events auf die passende aktive Stimme
    /// matchen kann, ohne internen Zustand zu mutieren.
    public private(set) var note: UInt8 = 0
    private var velocity:        Float            = 0
    private var waveform:        AudioCoreWaveform = .sine

    private var phase:           Double = 0
    private var phaseIncrement:  Double = 0

    private var envelopeValue:   Float = 0
    private var attackRate:      Float = 0
    private var decayRate:       Float = 0
    private var sustainLevel:    Float = 0
    private var releaseRate:     Float = 0

    // Biquad-Tiefpassfilter (DF-II Transposed) – Koeffizienten (normiert auf a0):
    private var filterB0: Float = 1.0
    private var filterB1: Float = 0.0
    private var filterB2: Float = 0.0
    private var filterA1: Float = 0.0
    private var filterA2: Float = 0.0
    // Filter-Zustandsvariablen (zurueckgesetzt bei configure()):
    private var filterS1: Float = 0.0
    private var filterS2: Float = 0.0

    // Stereo-Pan-Gains (Constant-Power, berechnet bei configure()):
    private var panGainL: Float = 1.0
    private var panGainR: Float = 1.0

    public private(set) var activationOrder: UInt64 = 0

    /// true solange die Voice Audio produziert (alle Stages ausser .idle).
    public var isActive: Bool { stage != .idle }

    public init() {}

    // MARK: – Frequenzformel (oeffentlich testbar, ohne Voice-Instanz noetig)
    //
    // MIDI-Note → Hz (gleichstufig, A4 = 440 Hz) + optionaler Detune.
    // Detune in Cent: 1 Cent = 1/100 Halbton. pow(2, cent/1200): 10 Cent ≈ +0.58 % Frequenz.
    // Identisch zur Formel in `SynthVoice.configure()`.

    public static func frequency(forNote note: UInt8, detuneCents: Float = 0.0) -> Double {
        let baseFreq = 440.0 * pow(2.0, (Double(note) - 69.0) / 12.0)
        return baseFreq * pow(2.0, Double(detuneCents) / 1200.0)
    }

    // MARK: – NoteOn
    //
    // Initialisiert die Voice fuer eine neue Note. Uebernimmt vollstaendige
    // Klangkonfiguration aus `AudioCoreSynthParameters` (Snapshot-Semantik,
    // identisch zu `SynthVoice.configure()`). Kein Heap-Zugriff.
    //
    // - Parameters:
    //   - detuneCents: individuelle Verstimmung dieser Stimme (Cent). Fuer
    //     Unison-Verteilung ueber mehrere Stimmen ist ein Pool (S-02b)
    //     zustaendig — diese Voice kennt nur ihre eigene Verstimmung.
    //   - panPosition: Stereo-Position dieser Stimme, -1…+1 (Constant-Power).
    //   - gainScale: externe Amplitudenskalierung (z. B. 1/sqrt(n) bei
    //     Unison-Summierung durch einen kuenftigen Pool).

    public mutating func configure(note: UInt8,
                                    velocity: UInt8,
                                    sampleRate: Double,
                                    parameters: AudioCoreSynthParameters,
                                    activationOrder: UInt64 = 0,
                                    detuneCents: Float = 0.0,
                                    panPosition: Float = 0.0,
                                    gainScale: Float = 1.0) {
        self.note = note
        self.velocity = Float(velocity) / 127.0 * gainScale
        self.phase = 0
        self.envelopeValue = 0
        self.stage = .attack
        self.sustainLevel = max(0, min(parameters.sustain, 1))
        self.activationOrder = activationOrder
        self.waveform = parameters.waveform

        self.phaseIncrement = AudioCoreVoice.frequency(forNote: note, detuneCents: detuneCents) / sampleRate

        // Constant-Power-Panning, skaliert auf L=R=1.0 bei Pan=0 — identisch
        // zu `SynthVoice.configure()`.
        let panAngle = (panPosition + 1.0) * Float.pi * 0.25
        self.panGainL = sqrtf(2.0) * cosf(panAngle)
        self.panGainR = sqrtf(2.0) * sinf(panAngle)

        // ADSR-Rates: 1.0 / (Zeit_in_Samples) = Gain-Aenderung pro Sample.
        let sr = Float(sampleRate)
        self.attackRate  = parameters.attackMs  > 0 ? 1.0 / max(1.0, parameters.attackMs  * 0.001 * sr) : 1.0
        self.decayRate   = parameters.decayMs   > 0 ? 1.0 / max(1.0, parameters.decayMs   * 0.001 * sr) : 1.0
        self.releaseRate = parameters.releaseMs > 0 ? 1.0 / max(1.0, parameters.releaseMs * 0.001 * sr) : 1.0

        // Biquad-Tiefpassfilter: Koeffizienten aus Cutoff + Resonanz berechnen.
        // Filter-State bei neuer Note zuruecksetzen (verhindert Knack-Artefakte).
        let (fb0, fb1, fb2, fa1, fa2) = AudioCoreVoice.calcBiquadLowpassCoefficients(
            cutoff: parameters.filterCutoff,
            resonance: parameters.filterResonance,
            sampleRate: sampleRate
        )
        self.filterB0 = fb0; self.filterB1 = fb1; self.filterB2 = fb2
        self.filterA1 = fa1; self.filterA2 = fa2
        self.filterS1 = 0; self.filterS2 = 0
    }

    // MARK: – NoteOff

    public mutating func triggerRelease() {
        guard stage != .idle else { return }
        stage = .release
    }

    // MARK: – Live-Parameter (S-02b)
    //
    // Ergaenzt fuer die Voice-Pool-Migration (`VoicePool` in
    // `Sources/HarmonyEngine3D/SynthNode.swift`): Filter-Cutoff/-Resonanz und
    // Sustain-Level sind Live-Parameter, die auf laufende Stimmen wirken,
    // ohne die restliche Snapshot-Semantik (Attack/Decay/Release/Waveform)
    // zu beruehren. Interner Zustand bleibt `private` — der Aufrufer
    // aktualisiert ueber diese fachlich benannten Methoden statt ueber
    // direkten Feldzugriff.

    /// Uebertraegt neue Biquad-Tiefpasskoeffizienten auf diese Stimme, ohne
    /// den Filter-State (`filterS1`/`filterS2`) zurueckzusetzen — identisch
    /// zum bisherigen `VoicePool.applyParams()`-Verhalten (kein Knack-
    /// Artefakt bei einem glatten Sweep, State konvergiert innerhalb
    /// weniger Samples).
    public mutating func updateLowpassCoefficients(b0: Float, b1: Float, b2: Float, a1: Float, a2: Float) {
        filterB0 = b0; filterB1 = b1; filterB2 = b2
        filterA1 = a1; filterA2 = a2
    }

    /// Wendet ein neues Sustain-Level nur an, wenn sich die Stimme aktuell
    /// in der Sustain-Stage befindet — identisch zum bisherigen
    /// `VoicePool.applyParams()`-Verhalten. Wirkt sich nicht rueckwirkend
    /// auf Attack/Decay/Release oder eine andere Stage aus.
    public mutating func applySustainIfInSustain(level: Float) {
        guard stage == .sustain else { return }
        sustainLevel = level
        envelopeValue = level
    }

    // MARK: – PolyBLEP-Korrekturfunktion
    //
    // Bandlimitierung fuer diskontinuierliche Wellenformen (Saw, Square).
    // Identisch zu `SynthVoice.polyBLEP(phase:phaseIncrement:)`.

    private static func polyBLEP(phase: Double, phaseIncrement: Double) -> Float {
        if phase < phaseIncrement {
            let t = Float(phase / phaseIncrement)
            return t + t - t * t - 1.0
        } else if phase > 1.0 - phaseIncrement {
            let t = Float((phase - 1.0) / phaseIncrement)
            return t * t + t + t + 1.0
        }
        return 0.0
    }

    // MARK: – Biquad-LP-Koeffizienten
    //
    // Tiefpassfilter nach Robert Bristow-Johnsons Audio EQ Cookbook,
    // DF-II Transposed Topology. Identisch zu `SynthVoice.calcBiquadLP(...)`.
    //
    // Cutoff = 1.0 UND Resonance = 0.0 → Identity-Koeffizienten (Bypass).
    // Cutoff-Kurve: logarithmisch 20…20.000 Hz. Resonanz: Q 0.5…20.

    public static func calcBiquadLowpassCoefficients(cutoff: Float, resonance: Float, sampleRate: Double)
        -> (b0: Float, b1: Float, b2: Float, a1: Float, a2: Float) {

        if cutoff >= 1.0 && resonance <= 0.0 {
            return (1.0, 0.0, 0.0, 0.0, 0.0)
        }

        let freqMin: Float = 20.0
        let freqMax: Float = 20_000.0
        let c = max(0.0, min(cutoff, 1.0))
        let f0 = freqMin * pow(freqMax / freqMin, c)
        let f0safe = min(f0, Float(sampleRate) * 0.49)

        let q = 0.5 + max(0.0, min(resonance, 1.0)) * 19.5

        let w0    = 2.0 * Float.pi * f0safe / Float(sampleRate)
        let sinW0 = sin(w0)
        let cosW0 = cos(w0)
        let alpha = sinW0 / (2.0 * q)
        let a0    = 1.0 + alpha

        let b0 = ((1.0 - cosW0) * 0.5) / a0
        let b1 = (1.0 - cosW0) / a0
        let b2 = ((1.0 - cosW0) * 0.5) / a0
        let a1 = (-2.0 * cosW0) / a0
        let a2 = (1.0 - alpha) / a0

        return (b0, b1, b2, a1, a2)
    }

    // MARK: – DSP-Render
    //
    // Schreibt (additiv) in vom Aufrufer bereitgestellte L/R-Float-Puffer.
    // Reihenfolge: Wellenform → Filter → Huellkurve → Pan-Gewichtung →
    // Akkumulation. Kein Heap-Zugriff, kein Alloc, kein Lock, keine
    // Dispatch-/Task-/Actor-Nutzung, kein Dateizugriff, kein `print`.
    //
    // Amplitude pro Wellenform (identisch zu `SynthVoice.render()`):
    //   .sine: 0.15  .saw: 0.08  .square: 0.06  .triangle: 0.11

    @discardableResult
    public mutating func render(intoL outputL: UnsafeMutablePointer<Float>,
                                 intoR outputR: UnsafeMutablePointer<Float>,
                                 frameCount: Int) -> Bool {
        for f in 0..<frameCount {

            switch stage {

            case .idle:
                return false

            case .attack:
                envelopeValue += attackRate
                if envelopeValue >= 1.0 {
                    envelopeValue = 1.0
                    stage = .decay
                }

            case .decay:
                envelopeValue -= decayRate
                if envelopeValue <= sustainLevel {
                    envelopeValue = sustainLevel
                    stage = .sustain
                }

            case .sustain:
                break

            case .release:
                envelopeValue -= releaseRate
                if envelopeValue <= 0.0 {
                    envelopeValue = 0.0
                    stage = .idle
                    return false
                }
            }

            let rawSample: Float
            let ampScale: Float

            switch waveform {

            case .sine:
                let twoPiPhase  = phase * 2.0 * Double.pi
                let fundamental = Float(sin(twoPiPhase))
                let harmonic2   = Float(sin(twoPiPhase * 2.0))
                rawSample = fundamental * 0.85 + harmonic2 * 0.15
                ampScale  = 0.15

            case .saw:
                let sawBlep = AudioCoreVoice.polyBLEP(phase: phase, phaseIncrement: phaseIncrement)
                rawSample = Float(phase * 2.0 - 1.0) - sawBlep
                ampScale  = 0.08

            case .square:
                var sq: Float = phase < 0.5 ? 1.0 : -1.0
                sq += AudioCoreVoice.polyBLEP(phase: phase, phaseIncrement: phaseIncrement)
                let shiftedPhase = phase < 0.5 ? phase + 0.5 : phase - 0.5
                sq -= AudioCoreVoice.polyBLEP(phase: shiftedPhase, phaseIncrement: phaseIncrement)
                rawSample = sq
                ampScale  = 0.06

            case .triangle:
                let p = Float(phase)
                if      p < 0.25 { rawSample = p * 4.0 }
                else if p < 0.75 { rawSample = 2.0 - p * 4.0 }
                else             { rawSample = p * 4.0 - 4.0 }
                ampScale  = 0.11
            }

            phase += phaseIncrement
            if phase >= 1.0 { phase -= 1.0 }

            let filtered = filterB0 * rawSample + filterS1
            filterS1 = filterB1 * rawSample - filterA1 * filtered + filterS2
            filterS2 = filterB2 * rawSample - filterA2 * filtered

            let sample = filtered * envelopeValue * velocity * ampScale
            outputL[f] += sample * panGainL
            outputR[f] += sample * panGainR
        }
        return true
    }
}
