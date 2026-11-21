// MARK: – AudioCoreModulationRoute
//
// S-05b (`.agent_handoff/latest_codex.md`, Runde 053), Scope B: eine
// einzelne, statische Modulationsroute (Source -> Target, bipolarer
// Amount, an/aus). Reiner Wertetyp — die Matrix selbst haelt eine feste
// Liste dieser Routen, deaktivierte Routen werden bei der Auswertung
// uebersprungen.

public struct AudioCoreModulationRoute: Sendable, Equatable {

    /// Bipolare Amount-Grenze — Handoff-Vorgabe.
    public static let amountRange: ClosedRange<Float> = -1...1

    public var source: AudioCoreModulationSource
    public var target: AudioCoreModulationTarget
    public var amount: Float
    public var isEnabled: Bool

    public init(source: AudioCoreModulationSource,
                target: AudioCoreModulationTarget,
                amount: Float,
                isEnabled: Bool = true) {
        self.source = source
        self.target = target
        self.amount = AudioCoreModulationRoute.clampAmount(amount)
        self.isEnabled = isEnabled
    }

    private static func clampAmount(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return max(amountRange.lowerBound, min(value, amountRange.upperBound))
    }
}
