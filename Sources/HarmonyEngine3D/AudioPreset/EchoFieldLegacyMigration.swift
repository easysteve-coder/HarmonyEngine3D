import Foundation

// MARK: – EchoFieldLegacyMigration
//
// S-07b (`.agent_handoff/latest_codex.md`, Runde 056): explizite, testbare
// Migration der heutigen Drei-Tap-Delay-Felder (`ChannelFXConfig` in
// `AppSettings.swift`, sowie `AudioPresetFXSection` aus dem S-03-Presetpfad)
// in die ersten drei `EchoFieldPreset`-Tap-Slots. Bewusst eine eigene
// Funktion je Quelle, keine stille Default-Fuellung – jedes Feld wird 1:1
// uebernommen, keine Formel-Rundung, damit der Roundtrip verlustfrei bleibt.
// Tap 4 ist in beiden Migrationspfaden deterministisch `.neutral`
// (stumm/deaktiviert), weil es kein viertes Legacy-Tap gibt.
//
// Getrennt von `AudioPresetLegacyMigration.swift` gehalten (eigene Datei),
// damit die bestehende, bereits deep-reviewte S-03-Migration unveraendert
// bleibt – diese Datei liest `ChannelFXConfig`/`AudioPresetFXSection` nur,
// aendert sie nicht.

extension ChannelFXConfig {

    /// Erzeugt ein `EchoFieldPreset`, dessen erste drei Taps diese
    /// `ChannelFXConfig`-Delaytaps 1:1 abbilden. Tap 4 ist `.neutral`.
    func echoFieldPreset(id: String, name: String, channelRole: AudioPresetChannelRole,
                          author: String? = nil, engineVersion: String? = nil) -> EchoFieldPreset {
        EchoFieldPreset(
            schemaVersion: EchoFieldPreset.currentSchemaVersion,
            id: id,
            name: name,
            channelRole: channelRole,
            author: author,
            engineVersion: engineVersion,
            tap1: EchoFieldTap(time: delay1Time, feedback: delay1Feedback, mix: delay1Mix, pan: delay1Pan),
            tap2: EchoFieldTap(time: delay2Time, feedback: delay2Feedback, mix: delay2Mix, pan: delay2Pan),
            tap3: EchoFieldTap(time: delay3Time, feedback: delay3Feedback, mix: delay3Mix, pan: delay3Pan),
            tap4: .neutral
        )
    }
}

extension AudioPresetFXSection {

    /// Die drei Legacy-Delaytaps dieser FX-Sektion, uebersetzt in
    /// `EchoFieldTap`-Werte – ohne Tap 4, das haengt vom Aufrufer ab (siehe
    /// `AudioSynthPreset.echoFieldPreset`).
    var legacyEchoFieldTaps: (tap1: EchoFieldTap, tap2: EchoFieldTap, tap3: EchoFieldTap) {
        (
            EchoFieldTap(time: delay1Time, feedback: delay1Feedback, mix: delay1Mix, pan: delay1Pan),
            EchoFieldTap(time: delay2Time, feedback: delay2Feedback, mix: delay2Mix, pan: delay2Pan),
            EchoFieldTap(time: delay3Time, feedback: delay3Feedback, mix: delay3Mix, pan: delay3Pan)
        )
    }
}

extension AudioSynthPreset {

    /// Erzeugt ein `EchoFieldPreset` aus den drei Legacy-Delaytaps dieses
    /// (S-03-)Presets – haelt den bestehenden `AudioSynthPreset`-Migrations-
    /// pfad unveraendert und leitet nur zusaetzlich davon ab. Tap 4 ist
    /// `.neutral`. `id`/`name` werden separat uebergeben, weil ein und
    /// dasselbe `AudioSynthPreset` mehrere `EchoFieldPreset`-Ableitungen
    /// haben kann (kein 1:1-ID-Zwang).
    func echoFieldPreset(id: String, name: String) -> EchoFieldPreset {
        let taps = fx.legacyEchoFieldTaps
        return EchoFieldPreset(
            schemaVersion: EchoFieldPreset.currentSchemaVersion,
            id: id,
            name: name,
            channelRole: channelRole,
            author: author,
            engineVersion: engineVersion,
            tap1: taps.tap1,
            tap2: taps.tap2,
            tap3: taps.tap3,
            tap4: .neutral
        )
    }
}
