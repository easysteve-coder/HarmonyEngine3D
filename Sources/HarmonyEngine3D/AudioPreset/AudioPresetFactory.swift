// MARK: – AudioPresetFactory
//
// S-03: die vier heutigen Legacy-Kanalrollen als Factory-`AudioSynthPreset`,
// deterministisch aus den bestehenden `ChannelFXConfig.*Defaults`
// (`AppSettings.swift`) erzeugt — keine JSON-Bundle-Resource nötig, weil
// die Quelle bereits eine deterministische Swift-Konstante ist. Stellt die
// aktuellen Klangeinstellungen reproduzierbar dar, aktiviert aber keinen
// Produktdefault (siehe Nicht-Scope, `.agent_handoff/latest_codex.md`
// Runde 048).

enum AudioPresetFactory {

    /// Stabile IDs — dürfen sich nach Veröffentlichung nicht mehr ändern
    /// (User-seitige Referenzen/Zuweisungen würden sonst brechen, sobald
    /// ein späterer Slice sie tatsächlich nutzt).
    enum LegacyID {
        static let chord     = "legacy.chord"
        static let bass      = "legacy.bass"
        static let melody    = "legacy.melody"
        static let chordTone = "legacy.chordTone"
    }

    /// Die vier Legacy-Factory-Presets, in fester Reihenfolge
    /// (Chord, Bass, Melody, ChordTone — wie `AudioConfig`).
    static var legacyPresets: [AudioSynthPreset] {
        [
            ChannelFXConfig.chordDefaults.audioSynthPreset(
                id: LegacyID.chord, name: "Legacy Chord", channelRole: .chord
            ),
            ChannelFXConfig.bassDefaults.audioSynthPreset(
                id: LegacyID.bass, name: "Legacy Bass", channelRole: .bass
            ),
            ChannelFXConfig.melodyDefaults.audioSynthPreset(
                id: LegacyID.melody, name: "Legacy Melody", channelRole: .melody
            ),
            ChannelFXConfig.chordToneDefaults.audioSynthPreset(
                id: LegacyID.chordTone, name: "Legacy Chord Tone", channelRole: .chordTone
            )
        ]
    }
}
