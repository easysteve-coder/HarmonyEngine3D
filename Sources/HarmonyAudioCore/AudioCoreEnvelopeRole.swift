// MARK: – AudioCoreEnvelopeRole
//
// S-05b (`.agent_handoff/latest_codex.md`, Runde 053), Scope A: typisierte
// Referenz auf die Amp- oder Mod-Rolle eines `AudioCoreEnvelope` aus S-05a,
// ohne dass die Modulationsmatrix selbst eine `AudioCoreEnvelope`-Instanz
// besitzt. Ein spaeterer Verdrahtungsslice liest die beiden laufenden
// Huellenwerte und schreibt sie in `AudioCoreModulationSourceValues`.

public enum AudioCoreEnvelopeRole: Sendable, Equatable, Hashable, CaseIterable {
    case amp
    case mod
}
