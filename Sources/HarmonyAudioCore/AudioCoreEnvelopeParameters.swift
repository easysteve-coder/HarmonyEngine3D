// MARK: – AudioCoreEnvelopeParameters
//
// S-05a (`.agent_handoff/latest_codex.md`, Runde 052), Scope A: Parametermodell
// eines eigenstaendigen `AudioCoreEnvelope`-Bausteins (Amp-/Mod-Huelle,
// `SYNTH_ARCHITECTURE_PLAN.md` Abschnitt 6.4). Bewusst getrennt von den
// ADSR-Feldern in `AudioCoreSynthParameters`: dort sind Attack/Decay/Sustain/
// Release Teil des Voice-Snapshots und werden intern in Voice-Raten
// umgerechnet (`AudioCoreVoice.configure()`); hier ist die Huellkurve ein
// eigenstaendiger, wiederverwendbarer Baustein, den Amp- UND Mod-Rolle als
// getrennte Instanzen/Parameterprofile nutzen koennen — noch ohne
// Verdrahtung zu `AudioCoreVoice`/`SynthNode` (Nicht-Scope S-05a).

public struct AudioCoreEnvelopeParameters: Sendable, Equatable {

    /// Attack-Zeit in Millisekunden: Zeit von 0 auf 1.0.
    public var attackMs: Float

    /// Decay-Zeit in Millisekunden: Zeit fuer den vollen Bereich 1.0 auf 0
    /// (die tatsaechliche Decay-Dauer bis `sustainLevel` skaliert linear mit
    /// `1 - sustainLevel`, identisch zur Ratenberechnung in `AudioCoreVoice`).
    public var decayMs: Float

    /// Sustain-Pegel, geklemmt auf `0...1`.
    public var sustainLevel: Float

    /// Release-Zeit in Millisekunden: Zeit fuer den vollen Bereich 1.0 auf 0
    /// (die tatsaechliche Release-Dauer skaliert linear mit dem Envelopewert
    /// bei `noteOff()`, identisch zum bestehenden `AudioCoreVoice`-Verhalten).
    public var releaseMs: Float

    public init(attackMs: Float = 5.0,
                decayMs: Float = 100.0,
                sustainLevel: Float = 0.7,
                releaseMs: Float = 200.0) {
        self.attackMs = AudioCoreEnvelopeParameters.clampPositive(attackMs, fallback: 5.0)
        self.decayMs = AudioCoreEnvelopeParameters.clampPositive(decayMs, fallback: 100.0)
        self.sustainLevel = AudioCoreEnvelopeParameters.clampUnit(sustainLevel, fallback: 0.7)
        self.releaseMs = AudioCoreEnvelopeParameters.clampPositive(releaseMs, fallback: 200.0)
    }

    /// Standard-Werte fuer ein Amp-Huellenprofil.
    public static let defaults = AudioCoreEnvelopeParameters()

    private static func clampPositive(_ value: Float, fallback: Float) -> Float {
        guard value.isFinite else { return fallback }
        return max(0.0, value)
    }

    private static func clampUnit(_ value: Float, fallback: Float) -> Float {
        guard value.isFinite else { return fallback }
        return max(0.0, min(value, 1.0))
    }
}
