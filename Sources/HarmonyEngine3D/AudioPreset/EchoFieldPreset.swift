import Foundation

// MARK: – EchoFieldTap
//
// S-07b (`.agent_handoff/latest_codex.md`, Runde 056): ein einzelner Stereo-
// Delay-Tap fuer das kuenftige `EchoField` (`SYNTH_ARCHITECTURE_PLAN.md`,
// Abschnitt 7.2). Reine Daten-/Wertebereichs-Deklaration — kein DSP, keine
// Delayline, kein Feedback-Runaway-Schutz im Rendercallback (den gibt es in
// diesem Slice nicht, weil nichts rendert).
//
// Feldsemantik bewusst analog zu den heutigen `ChannelFXConfig.delayX*`-
// Feldern (`AppSettings.swift`), aber mit dem breiteren Zeitbereich aus dem
// Plan (0.001…4.0 s statt der heutigen AudioEngine-Laufzeitgrenze
// 0.001…2.0 s) — EchoField ist ein Zielmodell, kein Abbild der heutigen
// `AVAudioUnitDelay`-Grenzen.

struct EchoFieldTap: Codable, Equatable, Sendable {
    var time:     Float   // 0.001…4.0 s
    var feedback: Float   // 0.0…1.0 (siehe EchoFieldPresetValidator: >=1.0 blockiert als Runaway-Risiko)
    var mix:      Float   // 0.0…1.0 – Sendlevel dieses Taps
    var pan:      Float   // -1.0…+1.0
}

extension EchoFieldTap {
    /// Deterministisch stummer/neutraler Tap – Zeit auf der unteren
    /// gueltigen Grenze, kein Feedback, kein Mix, zentriert. Wird fuer
    /// Tap 4 verwendet, solange kein viertes Legacy-Tap existiert.
    static let neutral = EchoFieldTap(time: 0.001, feedback: 0.0, mix: 0.0, pan: 0.0)
}

// MARK: – EchoFieldPreset
//
// Versioniertes Presetmodell mit exakt vier benannten Tap-Slots in fester,
// stabiler Reihenfolge (`tap1`…`tap4`, gespiegelt in der Reihenfolge des
// `taps`-Arrays) – bewusst wie `ChannelFXConfig.delay1/2/3` als benannte
// Felder statt als dynamisches Array modelliert, damit "exakt vier Slots"
// ein Compile-Zeit-Fakt ist statt ein Laufzeit-Invariante.
//
// Rein Daten-/Presetinfrastruktur: wird in dieser Runde an keiner Stelle
// aktiv von `AudioEngine`, `AppSettings`, Preset-UI oder Runtime referenziert
// (siehe `.agent_handoff/latest_codex.md`, Runde 056, Nicht-Scope). Kein
// SceneKit, kein AppSettings-Zugriff, kein UI, keine AVFoundation-
// Abhaengigkeit.

struct EchoFieldPreset: Codable, Equatable, Sendable {

    /// Bekannte/unterstuetzte Schema-Version. Wie bei `AudioSynthPreset` ein
    /// String, kein Semver.
    static let currentSchemaVersion = "1.0"

    var schemaVersion: String
    /// Stabile, eindeutige ID – fuer Factory-Presets ein literales Konstante
    /// (siehe `EchoFieldPresetFactory`), fuer User-Presets frei waehlbar.
    var id:            String
    var name:          String
    var channelRole:   AudioPresetChannelRole
    /// Optionale Metadaten – keine fachliche Bedeutung fuer Validator/Runtime.
    var author:        String?
    var engineVersion: String?

    var tap1: EchoFieldTap
    var tap2: EchoFieldTap
    var tap3: EchoFieldTap
    var tap4: EchoFieldTap
}

extension EchoFieldPreset {
    /// Alle vier Taps in stabiler Reihenfolge – Convenience fuer Tests und
    /// spaetere generische Iteration (z. B. Validator).
    var taps: [EchoFieldTap] { [tap1, tap2, tap3, tap4] }
}
