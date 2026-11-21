// MARK: – AudioCoreModulationTargetValues
//
// S-05b (`.agent_handoff/latest_codex.md`, Runde 053), Scope B: Ergebnis
// einer `AudioCoreModulationMatrix.evaluate(sources:)`-Auswertung — ein
// fester, allokationsfreier Wertespeicher mit genau einem `Float`-Feld pro
// `AudioCoreModulationTarget`-Fall. Bewusst kein `Dictionary`: der
// Subscript-Zugriff ist ein reiner `switch`, daher fuer den eigentlichen
// Sample-/Render-Schritt genauso geeignet wie fuer Tests/UI-nahe
// Auswertung — der Handoff verlangt ausdruecklich, dass eine
// Convenience-API einen spaeteren realtime-nahen Pfad nicht blockiert.
//
// Jedes Feld wird nach der Akkumulation mehrerer Routen auf `[-1, 1]`
// geklemmt und ist garantiert endlich — der Konsument (ein spaeterer
// Verdrahtungsslice) bildet diesen bipolaren Modulationsbeitrag auf den
// tatsaechlichen Parameterbereich ab.

public struct AudioCoreModulationTargetValues: Sendable, Equatable {

    public static let range: ClosedRange<Float> = -1...1

    public var morphPosition: Float = 0
    public var textureLevel: Float = 0
    public var filterCutoff: Float = 0
    public var mixDepth: Float = 0
    public var ampEnvelopeDepth: Float = 0
    public var modEnvelopeDepth: Float = 0
    public var spaceSend: Float = 0

    public init() {}

    public subscript(target: AudioCoreModulationTarget) -> Float {
        get {
            switch target {
            case .morphPosition:     return morphPosition
            case .textureLevel:      return textureLevel
            case .filterCutoff:      return filterCutoff
            case .mixDepth:          return mixDepth
            case .ampEnvelopeDepth:  return ampEnvelopeDepth
            case .modEnvelopeDepth:  return modEnvelopeDepth
            case .spaceSend:         return spaceSend
            }
        }
        set {
            switch target {
            case .morphPosition:     morphPosition = newValue
            case .textureLevel:      textureLevel = newValue
            case .filterCutoff:      filterCutoff = newValue
            case .mixDepth:          mixDepth = newValue
            case .ampEnvelopeDepth:  ampEnvelopeDepth = newValue
            case .modEnvelopeDepth:  modEnvelopeDepth = newValue
            case .spaceSend:         spaceSend = newValue
            }
        }
    }

    /// Klemmt alle sieben Felder auf `range` und faengt nicht-endliche
    /// Zwischenergebnisse (z. B. durch mehrfache Akkumulation) auf `0` ab.
    mutating func clampAndSanitize() {
        for target in AudioCoreModulationTarget.allCases {
            self[target] = AudioCoreModulationTargetValues.clamp(self[target])
        }
    }

    private static func clamp(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return max(range.lowerBound, min(value, range.upperBound))
    }
}
