// MARK: – AudioCoreModulationSource
//
// S-05b (`.agent_handoff/latest_codex.md`, Runde 053), Scope A: statische
// Beschreibung, woher eine Modulationsroute ihren Eingabewert liest. Bewusst
// ein geschlossenes Enum ueber die drei bekannten Quellklassen (Makro,
// LFO-Slot, Huellenrolle) statt eines freien Bezeichners — verhindert
// Tippfehler-Routen und haelt die Matrix vollstaendig typsicher.
//
// Referenziert `AudioCoreLFO`/`AudioCoreEnvelope` aus S-05a nur ueber die
// typisierten Slot-/Rollen-Enums, nicht ueber die Instanzen selbst — die
// Matrix bleibt dadurch unabhaengig davon, wer die LFO-/Huellen-Instanzen
// haelt und rendert (Nicht-Scope S-05b: keine aktive Verdrahtung).

public enum AudioCoreModulationSource: Sendable, Equatable, Hashable {
    case macro(AudioCoreMacroID)
    case lfo(AudioCoreLFOSlot)
    case envelope(AudioCoreEnvelopeRole)
}
