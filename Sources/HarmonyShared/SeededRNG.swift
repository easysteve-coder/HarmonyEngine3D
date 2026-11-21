// MARK: – SeededRNG
//
// Deterministischer Pseudozufallsgenerator (Xorshift64).
// Gleicher Seed → identische Sequenz → deterministisch reproduzierbare Welt.
// Diese Eigenschaft darf durch Refactoring nie gebrochen werden.
//
// In HarmonyShared weil sowohl HarmonyEngine3D (ChunkLogic, WorldGeneration)
// als auch HarmonyShared selbst (HarmonyGraphEngine) denselben RNG benötigen.
//
// Kein SceneKit, kein AppSettings, kein UI.

public struct SeededRNG {
    public var state: UInt64

    public init(seed: UInt64) {
        state = seed == 0 ? 0xDEAD_BEEF_1234_5678 : seed
    }

    /// Xorshift64 — nächster Rohwert
    public mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    /// Gleichverteilter Float 0…1
    public mutating func f() -> Float {
        Float(next() & 0xFFFFFF) / Float(0xFFFFFF)
    }

    /// Gleichverteilter Int 0..<mod
    public mutating func i(_ mod: Int) -> Int {
        Int(next() % UInt64(max(1, mod)))
    }

    /// Gleichverteilter Float im geschlossenen Bereich
    public mutating func f(in r: ClosedRange<Float>) -> Float {
        r.lowerBound + f() * (r.upperBound - r.lowerBound)
    }
}
