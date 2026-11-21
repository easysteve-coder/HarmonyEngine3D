import Foundation

// MARK: – EchoFieldPresetFactory
//
// S-07b: die vier heutigen Legacy-Kanalrollen als Factory-`EchoFieldPreset`,
// deterministisch aus den bestehenden `ChannelFXConfig.*Defaults`
// (`AppSettings.swift`) erzeugt – analog `AudioPresetFactory` (S-03).
// Stellt die aktuellen Drei-Tap-Delay-Einstellungen reproduzierbar als
// EchoField-Migrationspreset dar, aktiviert aber keinen Produktdefault
// (siehe Nicht-Scope, `.agent_handoff/latest_codex.md`, Runde 056).

enum EchoFieldPresetFactory {

    /// Stabile IDs – duerfen sich nach Veroeffentlichung nicht mehr aendern.
    /// Bewusst eigener Namensraum (`legacy.echo.*`), getrennt von
    /// `AudioPresetFactory.LegacyID` (`legacy.*`), weil ein
    /// `AudioSynthPreset` und sein `EchoFieldPreset`-Migrationsgegenstueck
    /// unabhaengige IDs/Lebenszyklen haben.
    enum LegacyID {
        static let chord     = "legacy.echo.chord"
        static let bass      = "legacy.echo.bass"
        static let melody    = "legacy.echo.melody"
        static let chordTone = "legacy.echo.chordTone"
    }

    /// Die vier Legacy-Factory-Presets, in fester Reihenfolge
    /// (Chord, Bass, Melody, ChordTone – wie `AudioConfig`).
    static var legacyPresets: [EchoFieldPreset] {
        [
            ChannelFXConfig.chordDefaults.echoFieldPreset(
                id: LegacyID.chord, name: "Legacy Chord Echo", channelRole: .chord
            ),
            ChannelFXConfig.bassDefaults.echoFieldPreset(
                id: LegacyID.bass, name: "Legacy Bass Echo", channelRole: .bass
            ),
            ChannelFXConfig.melodyDefaults.echoFieldPreset(
                id: LegacyID.melody, name: "Legacy Melody Echo", channelRole: .melody
            ),
            ChannelFXConfig.chordToneDefaults.echoFieldPreset(
                id: LegacyID.chordTone, name: "Legacy Chord Tone Echo", channelRole: .chordTone
            )
        ]
    }
}
