// MARK: – AudioCoreWaveform
//
// S-02a (`.agent_handoff/latest_codex.md`, Runde 046): Wellenform-Enum des
// `HarmonyAudioCore`-Fundaments. Identische Fallmenge zu `Waveform`
// (`Sources/HarmonyEngine3D/SynthParams.swift`) — bewusst separat gehalten,
// damit der Core keine Abhaengigkeit zu `HarmonyEngine3D` bekommt.

public enum AudioCoreWaveform: UInt8, Sendable, CaseIterable {
    case sine     = 0   // Grundton + 2. Harmonische (85 % / 15 %) — warm, rund
    case saw      = 1   // Saegezahn (PolyBLEP-bandlimitiert) — brillant, obertonreich
    case square   = 2   // Rechteck 50 % Duty Cycle (PolyBLEP-bandlimitiert) — hohl
    case triangle = 3   // Dreieck — weich, sinusaehnlich
}
