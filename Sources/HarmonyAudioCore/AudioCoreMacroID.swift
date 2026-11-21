// MARK: – AudioCoreMacroID
//
// S-05b (`.agent_handoff/latest_codex.md`, Runde 053), Scope A: die vier
// stabilen Performance-Makros des Atmospheric-Synth-Fundaments
// (`SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 6.5). Die Makromenge ist bewusst
// fest und klein — sie bleibt in UI und Controller-Mappings stabil, waehrend
// ein Preset frei definiert, welche internen Ziele ein Makro bewegt.
//
// Keine aktive Nutzung durch `AudioCoreVoice`/`SynthNode`/`AppSettings`/UI
// (Nicht-Scope S-05b).

public enum AudioCoreMacroID: Sendable, Equatable, Hashable, CaseIterable {
    /// LFO-/Huellen-Tiefe, Morphbewegung.
    case motion
    /// Spektrum, Filter, Shaping.
    case color
    /// Echo-/Hall-Sends, Decay innerhalb sicherer Grenzen.
    case space
    /// Stereo-Breite, Transienten, Dry/Wet-Balance.
    case focus
}
