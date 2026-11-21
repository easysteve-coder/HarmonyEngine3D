// MARK: – AudioCoreSynthParameters
//
// S-02a (`.agent_handoff/latest_codex.md`, Runde 046): Value-Parametermodell
// des `HarmonyAudioCore`-Fundaments. Feldmenge und Defaults entsprechen
// bewusst `SynthParams` (`Sources/HarmonyEngine3D/SynthParams.swift`) —
// das ist der fachliche Vertrag von S-02a, kein Zufall.
//
// `maxVoices`/`unisonVoices`/`unisonDetune`/`unisonSpread` sind Teil des
// Value-Modells, weil sie zur Legacy-Parametermenge gehoeren, werden aber
// von `AudioCoreVoice` (einzelne Stimme, S-02a) NICHT ausgewertet — die
// Unison-Verteilung auf mehrere Stimmen (Detune-/Pan-Spread pro Voice,
// Voice-Stealing, Pool-Groesse) ist Aufgabe eines kuenftigen Voice-Pools
// (S-02b). `AudioCoreVoice.configure()` nimmt Detune/Pan/Gain-Skalierung
// pro Stimme stattdessen als eigene Parameter entgegen (siehe dort),
// symmetrisch zu `SynthVoice.configure()`.

public struct AudioCoreSynthParameters: Sendable, Equatable {

    /// Wellenform des Oszillators (Snapshot-Semantik, siehe `AudioCoreVoice`).
    public var waveform: AudioCoreWaveform

    /// ADSR Attack-Zeit in Millisekunden.
    public var attackMs: Float

    /// ADSR Decay-Zeit in Millisekunden.
    public var decayMs: Float

    /// ADSR Sustain-Pegel (0…1).
    public var sustain: Float

    /// ADSR Release-Zeit in Millisekunden.
    public var releaseMs: Float

    /// Maximale Stimmanzahl eines kuenftigen Voice-Pools (S-02b). Von
    /// `AudioCoreVoice` selbst nicht ausgewertet.
    public var maxVoices: Int

    /// Filter-Cutoff, normiert 0…1 → logarithmisch auf 20…20.000 Hz.
    /// 1.0 = voll geoeffnet (Bypass bei gleichzeitig `filterResonance == 0`).
    public var filterCutoff: Float

    /// Filter-Resonanz, normiert 0…1 → Q 0.5…20.
    public var filterResonance: Float

    /// Anzahl Unison-Stimmen eines kuenftigen Voice-Pools (S-02b). Von
    /// `AudioCoreVoice` selbst nicht ausgewertet.
    public var unisonVoices: Int

    /// Maximale Unison-Verstimmung in Cent (Pool-Verteilung, S-02b).
    public var unisonDetune: Float

    /// Stereo-Verteilung der Unison-Stimmen (Pool-Verteilung, S-02b).
    public var unisonSpread: Float

    public init(waveform: AudioCoreWaveform = .sine,
                attackMs: Float = 20.0,
                decayMs: Float = 100.0,
                sustain: Float = 0.70,
                releaseMs: Float = 300.0,
                maxVoices: Int = 16,
                filterCutoff: Float = 1.0,
                filterResonance: Float = 0.0,
                unisonVoices: Int = 1,
                unisonDetune: Float = 0.0,
                unisonSpread: Float = 0.0) {
        self.waveform = waveform
        self.attackMs = attackMs
        self.decayMs = decayMs
        self.sustain = sustain
        self.releaseMs = releaseMs
        self.maxVoices = maxVoices
        self.filterCutoff = filterCutoff
        self.filterResonance = filterResonance
        self.unisonVoices = unisonVoices
        self.unisonDetune = unisonDetune
        self.unisonSpread = unisonSpread
    }

    /// Standard-Werte — fachlich identisch zu `SynthParams.defaults`.
    public static let defaults = AudioCoreSynthParameters()
}
