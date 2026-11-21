// MARK: – AudioCoreADSRStage
//
// S-02a (`.agent_handoff/latest_codex.md`, Runde 046): Huellkurven-
// Zustandsautomat des `HarmonyAudioCore`-Fundaments. Identische Fallmenge
// zu `ADSRStage` (`Sources/HarmonyEngine3D/SynthVoice.swift`).

public enum AudioCoreADSRStage: UInt8, Sendable {
    case idle    = 0
    case attack  = 1
    case decay   = 2
    case sustain = 3
    case release = 4
}
