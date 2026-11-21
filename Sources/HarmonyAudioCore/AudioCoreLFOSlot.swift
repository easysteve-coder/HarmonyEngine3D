// MARK: – AudioCoreLFOSlot
//
// S-05b (`.agent_handoff/latest_codex.md`, Runde 053), Scope A: typisierte
// Referenz auf einen der drei `AudioCoreLFO`-Instanzen aus S-05a, ohne dass
// die Modulationsmatrix selbst eine `AudioCoreLFO`-Instanz besitzt. Ein
// spaeterer Verdrahtungsslice liest die drei laufenden LFO-Werte und
// schreibt sie in `AudioCoreModulationSourceValues`.

public enum AudioCoreLFOSlot: Sendable, Equatable, Hashable, CaseIterable {
    case lfo1
    case lfo2
    case lfo3
}
