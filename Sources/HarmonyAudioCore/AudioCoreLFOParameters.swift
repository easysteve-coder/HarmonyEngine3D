// MARK: – AudioCoreLFOParameters
//
// S-05a (`.agent_handoff/latest_codex.md`, Runde 052), Scope B: Parametermodell
// eines `AudioCoreLFO`-Bausteins. Frequenz ist bewusst auf einen niedrigen,
// LFO-typischen Bereich begrenzt (siehe `maxFrequencyHz`) statt frei bis zur
// Nyquist-Grenze zu erlauben — das haelt den LFO klar von einem
// Audio-Rate-Oszillator getrennt (Tempo-Sync/Audio-Rate-Modulation sind laut
// `SYNTH_ARCHITECTURE_PLAN.md` Abschnitt 6.4/6.1 explizit spaetere
// Ausbaustufen bzw. Nicht-Scope S-05a) und garantiert nebenbei, dass die
// einfache Phasenfortschreibung in `AudioCoreLFO` (ein Subtraktionsschritt
// pro Sample, identisch zum Muster in `AudioCoreMorphOscillator`/
// `AudioCoreVoice`) bei jeder erlaubten Frequenz/Samplerate-Kombination
// korrekt bleibt.

public struct AudioCoreLFOParameters: Sendable, Equatable {

    /// Obergrenze fuer `frequencyHz` — LFO-typischer Bereich, kein
    /// Audio-Rate-Oszillator.
    public static let maxFrequencyHz: Float = 200.0

    public var shape: AudioCoreLFOShape

    /// Frequenz in Hz, geklemmt auf `0...maxFrequencyHz`.
    public var frequencyHz: Float

    /// Glaettungsmenge fuer `.smoothedRandom`, geklemmt auf `0...1`. `0`
    /// ergibt eine sehr langsame/weiche Annaeherung an neue Zufallswerte,
    /// `1` eine schnellere Annaeherung. Wird intern immer auf einen
    /// sicheren, festen Filterkoeffizienten im offenen Intervall `(0, 1)`
    /// abgebildet (siehe `AudioCoreLFO`) — identisches Prinzip zu
    /// `AudioCoreTextureSource.brightness`.
    public var smoothingAmount: Float

    public init(shape: AudioCoreLFOShape = .sine,
                frequencyHz: Float = 1.0,
                smoothingAmount: Float = 0.3) {
        self.shape = shape
        self.frequencyHz = AudioCoreLFOParameters.clampFrequency(frequencyHz)
        self.smoothingAmount = AudioCoreLFOParameters.clampUnit(smoothingAmount, fallback: 0.3)
    }

    public static let defaults = AudioCoreLFOParameters()

    private static func clampFrequency(_ hz: Float) -> Float {
        guard hz.isFinite else { return 1.0 }
        return max(0.0, min(hz, maxFrequencyHz))
    }

    private static func clampUnit(_ value: Float, fallback: Float) -> Float {
        guard value.isFinite else { return fallback }
        return max(0.0, min(value, 1.0))
    }
}
