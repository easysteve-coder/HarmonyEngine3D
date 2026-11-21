// MARK: – AudioCoreEnvelope
//
// S-05a (`.agent_handoff/latest_codex.md`, Runde 052), Scope A: eigenstaendiger
// ADSR-Huellkurven-Baustein des Atmospheric-Synth-Fundaments
// (`SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 6.4). Amp- UND Mod-Huelle sind
// derselbe Typ mit getrennten Instanzen/Parameterprofilen — der Plan erlaubt
// diese Verengung ausdruecklich, solange beide Rollen in den Tests getrennt
// belegt sind (siehe `AudioCoreEnvelopeTests`).
//
// Nutzt den bestehenden `AudioCoreADSRStage`-Zustandsautomaten (S-02a) weiter
// statt einen zweiten, redundanten Stage-Enum einzufuehren — die Fallmenge
// (idle/attack/decay/sustain/release) passt unveraendert.
//
// Kein Zugriff auf `AudioCoreVoice`-internen Zustand, keine aktive Nutzung
// durch `AudioCoreVoice`/`SynthNode` (Nicht-Scope S-05a).
//
// Realtime-Vertrag: `nextValue()`/`render(into:frameCount:)` alloziieren
// nicht, sperren nicht, nutzen keine Dispatch-/Task-/Actor-Ausfuehrung und
// schreiben nicht (kein `print`).

public struct AudioCoreEnvelope: Sendable, Equatable {

    public private(set) var stage: AudioCoreADSRStage = .idle
    public private(set) var value: Float = 0

    private var parameters: AudioCoreEnvelopeParameters

    private var attackRate:   Float = 0
    private var decayRate:    Float = 0
    private var releaseRate:  Float = 0
    private var sustainLevel: Float = 0

    /// true solange die Huellkurve einen Wert ungleich `idle` produziert.
    public var isActive: Bool { stage != .idle }

    public init(parameters: AudioCoreEnvelopeParameters = .defaults) {
        self.parameters = parameters
        self.sustainLevel = parameters.sustainLevel
    }

    // MARK: – Parameter

    public mutating func setParameters(_ newParameters: AudioCoreEnvelopeParameters) {
        parameters = newParameters
    }

    // MARK: – Events

    /// Startet einen neuen Huellkurvenlauf ab 0. Raten werden aus den
    /// aktuellen Parametern und der uebergebenen `sampleRate` neu berechnet
    /// (Snapshot-Semantik, identisch zur Ratenberechnung in
    /// `AudioCoreVoice.configure()`) — deterministisch, kein Restzustand aus
    /// einem vorherigen Lauf.
    public mutating func noteOn(sampleRate: Double) {
        stage = .attack
        value = 0
        sustainLevel = max(0.0, min(parameters.sustainLevel, 1.0))

        let sr = Float(sampleRate.isFinite && sampleRate > 0 ? sampleRate : 1.0)
        attackRate  = parameters.attackMs  > 0 ? 1.0 / max(1.0, parameters.attackMs  * 0.001 * sr) : 1.0
        decayRate   = parameters.decayMs   > 0 ? 1.0 / max(1.0, parameters.decayMs   * 0.001 * sr) : 1.0
        releaseRate = parameters.releaseMs > 0 ? 1.0 / max(1.0, parameters.releaseMs * 0.001 * sr) : 1.0
    }

    /// Startet eine kontrollierte Release-Phase vom aktuellen Envelopewert aus
    /// Attack, Decay ODER Sustain. Ohne Wirkung, wenn die Huellkurve bereits
    /// `idle` ist.
    public mutating func noteOff() {
        guard stage != .idle else { return }
        stage = .release
    }

    /// Setzt die Huellkurve auf `idle`/`0` zurueck (Key-Sync/Reset). Ein
    /// nachfolgendes `noteOn(sampleRate:)` reproduziert denselben Verlauf wie
    /// eine frische Instanz mit identischen Parametern, weil alle Raten
    /// deterministisch aus Parametern + `sampleRate` neu berechnet werden und
    /// kein Zustand ausserhalb von `stage`/`value` erhalten bleibt.
    public mutating func reset() {
        stage = .idle
        value = 0
    }

    // MARK: – DSP-Render

    /// Liefert genau einen Envelopewert und schreibt die Stage fort. Kein
    /// Heap-Zugriff, kein Lock, kein Dispatch, kein `print`.
    @discardableResult
    public mutating func nextValue() -> Float {
        switch stage {

        case .idle:
            break

        case .attack:
            value += attackRate
            if value >= 1.0 {
                value = 1.0
                stage = .decay
            }

        case .decay:
            value -= decayRate
            if value <= sustainLevel {
                value = sustainLevel
                stage = .sustain
            }

        case .sustain:
            break

        case .release:
            value -= releaseRate
            if value <= 0.0 {
                value = 0.0
                stage = .idle
            }
        }

        return value.isFinite ? value : 0
    }

    /// Schreibt `frameCount` Werte in den aufrufer-bereitgestellten Puffer.
    @discardableResult
    public mutating func render(into buffer: UnsafeMutablePointer<Float>, frameCount: Int) -> Bool {
        for i in 0..<frameCount {
            buffer[i] = nextValue()
        }
        return isActive
    }
}
