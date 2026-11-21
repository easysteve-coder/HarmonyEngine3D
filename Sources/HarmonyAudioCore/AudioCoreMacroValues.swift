// MARK: – AudioCoreMacroValues
//
// S-05b (`.agent_handoff/latest_codex.md`, Runde 053), Scope A: aktueller
// Wertezustand der vier `AudioCoreMacroID`-Makros. Reiner Value-Typ, kein
// Singleton, kein globaler mutable State — dieselbe API kann sowohl per
// Preset/Instanz als auch als einzelner globaler Performance-Zustand
// gehalten werden.
//
// Alle vier Werte sind defensiv auf `0...1` geklemmt; nicht-endliche
// Eingaben (`.nan`/`.infinity`) fallen auf `0` zurueck.

public struct AudioCoreMacroValues: Sendable, Equatable {

    public var motion: Float
    public var color: Float
    public var space: Float
    public var focus: Float

    public init(motion: Float = 0, color: Float = 0, space: Float = 0, focus: Float = 0) {
        self.motion = AudioCoreMacroValues.clampUnit(motion)
        self.color = AudioCoreMacroValues.clampUnit(color)
        self.space = AudioCoreMacroValues.clampUnit(space)
        self.focus = AudioCoreMacroValues.clampUnit(focus)
    }

    public static let defaults = AudioCoreMacroValues()

    /// Liest oder setzt den Wert eines einzelnen Makros ueber seine
    /// `AudioCoreMacroID`. Der Setter klemmt identisch zum Initialisierer.
    public subscript(id: AudioCoreMacroID) -> Float {
        get {
            switch id {
            case .motion: return motion
            case .color:  return color
            case .space:  return space
            case .focus:  return focus
            }
        }
        set {
            let clamped = AudioCoreMacroValues.clampUnit(newValue)
            switch id {
            case .motion: motion = clamped
            case .color:  color = clamped
            case .space:  space = clamped
            case .focus:  focus = clamped
            }
        }
    }

    private static func clampUnit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return max(0.0, min(value, 1.0))
    }
}
