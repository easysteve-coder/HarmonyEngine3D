// MARK: – AudioCoreLFOShape
//
// S-05a (`.agent_handoff/latest_codex.md`, Runde 052), Scope B: Wellenform
// eines `AudioCoreLFO`-Bausteins (`SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 6.4).

public enum AudioCoreLFOShape: UInt8, Sendable {
    case sine           = 0
    case triangle       = 1
    case sampleAndHold  = 2
    case smoothedRandom = 3
}
