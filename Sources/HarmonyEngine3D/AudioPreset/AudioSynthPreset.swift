import Foundation

// MARK: – AudioPresetChannelRole
//
// S-03 (`.agent_handoff/latest_codex.md`, Runde 048): die vier heutigen
// Legacy-Kanalrollen, denen ein Preset zugeordnet sein kann. Identisch zur
// bestehenden Kanalaufteilung (`ChannelFXConfig.chordDefaults` etc.,
// `AppSettings.swift`) — keine neue musikalische Rolle erfunden.

enum AudioPresetChannelRole: String, Codable, CaseIterable, Sendable {
    case chord
    case bass
    case melody
    case chordTone
}

// MARK: – AudioPresetSynthSection
//
// Oszillator-/ADSR-/Filter-/Unison-Anteil eines Presets. Feldsemantik und
// Werteeinheiten sind bewusst identisch zu `ChannelFXConfig`
// (`AppSettings.swift`) — nicht zu `AudioCoreSynthParameters` (Millisekunden-
// basiert): `ChannelFXConfig` ist die heute tatsächlich persistierte/
// bearbeitete Werteform, ein verlustfreier Roundtrip dorthin ist damit ohne
// Formel-Rundung möglich. Die Übersetzung nach `AudioCoreSynthParameters`
// (identische Formel zu `AudioEngine.synthParams(from:)`) lebt als reine,
// abgeleitete Funktion in `AudioPresetLegacyMigration.swift`.
//
// `maxVoices` existiert heute nur als AudioEngine-interne Konstante (16,
// nicht Teil von `ChannelFXConfig`) — hier trotzdem als Feld aufgenommen,
// damit das Modell den vollständigen `AudioCoreSynthParameters`-Feldsatz
// abdeckt (Handoff-Vorgabe). Default `16` entspricht dem heutigen Wert und
// wird von der Legacy-Migration so gesetzt — keine neue Laufzeitwirkung.

struct AudioPresetSynthSection: Codable, Equatable, Sendable {
    var waveform:        Waveform
    var attack:           Float   // 0…1 normiert (quadratische Attack-Kurve, siehe AudioEngine)
    var decay:            Float   // Sekunden
    var sustain:          Float   // 0…1
    var release:          Float   // Sekunden
    var filterCutoff:     Float   // 0…1 normiert → log. 20…20.000 Hz
    var filterResonance:  Float   // 0…1 → Q 0.5…20
    var unisonVoices:     Int     // 1 = kein Unison
    var unisonDetune:     Float   // Cent
    var unisonSpread:     Float   // 0…1
    var maxVoices:        Int     // Voice-Pool-Größe (heute AudioEngine-Konstante 16)
}

// MARK: – AudioPresetFXSection
//
// Delay-/Reverb-/Mixer-Anteil eines Presets. Feldsemantik identisch zu den
// übrigen (nicht-synth) Feldern von `ChannelFXConfig`.

struct AudioPresetFXSection: Codable, Equatable, Sendable {
    var delay1Time:      Float
    var delay1Feedback:  Float
    var delay1Mix:       Float
    var delay1Pan:       Float
    var delay2Time:      Float
    var delay2Feedback:  Float
    var delay2Mix:       Float
    var delay2Pan:       Float
    var delay3Time:      Float
    var delay3Feedback:  Float
    var delay3Mix:       Float
    var delay3Pan:       Float
    var reverbPreset:    Int     // AVAudioUnitReverbPreset.rawValue
    var reverbMix:       Float   // 0…1
    var channelVolume:   Float   // 0…1 → gainX.outputVolume
    var pan:             Float   // -1…+1 → gainX.pan (Mixer-Layer)
}

// MARK: – AudioSynthPreset
//
// Versioniertes, Codable Presetmodell für den heutigen Legacy-Synth-/FX-
// Stand (S-03). Rein Daten-/Persistenzinfrastruktur: wird in dieser Runde
// weder in der App aktiv ausgewählt noch mit Runtime-Defaults verdrahtet
// (siehe `.agent_handoff/latest_codex.md`, Runde 048, Nicht-Scope).
//
// Kein SceneKit, kein AppSettings-Zugriff, kein UI, keine AVFoundation-
// Abhängigkeit — reiner Value-Typ, testbar ohne App-Kontext.

struct AudioSynthPreset: Codable, Equatable, Sendable {

    /// Bekannte/unterstützte Schema-Version. Wie bei `HarmonyMap` ein
    /// String, kein Semver — siehe `AudioPresetValidator`.
    static let currentSchemaVersion = "1.0"

    var schemaVersion: String
    /// Stabile, eindeutige ID — für Factory-Presets ein literales Konstante
    /// (siehe `AudioPresetFactory`), für User-Presets frei wählbar/UUID.
    var id:            String
    var name:          String
    var channelRole:   AudioPresetChannelRole
    /// Optionale Metadaten — keine fachliche Bedeutung für Validator/Runtime.
    var author:        String?
    var engineVersion: String?

    var synth: AudioPresetSynthSection
    var fx:    AudioPresetFXSection
}
