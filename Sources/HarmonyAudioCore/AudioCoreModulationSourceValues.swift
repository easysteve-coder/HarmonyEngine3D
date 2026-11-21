// MARK: – AudioCoreModulationSourceValues
//
// S-05b (`.agent_handoff/latest_codex.md`, Runde 053), Scope B: laufender
// Modulationszustand — ein reiner Wertesnapshot der vier Makros, der drei
// LFO-Ausgaben und der beiden Huellenausgaben zum Zeitpunkt einer
// `AudioCoreModulationMatrix.evaluate(sources:)`-Auswertung. Klare Trennung
// von der statischen Routenbeschreibung (`AudioCoreModulationRoute`): wer
// die eigentlichen `AudioCoreLFO`-/`AudioCoreEnvelope`-Instanzen haelt und
// pro Sample/Block rendert, bleibt bewusst ausserhalb dieses Typs (Nicht-
// Scope S-05b).
//
// Der Subscript-Zugriff ist ein reiner `switch`, keine Dictionary-
// Allokation — bleibt damit auch in einem spaeteren realtime-nahen Pfad
// verwendbar.

public struct AudioCoreModulationSourceValues: Sendable, Equatable {

    public var macros: AudioCoreMacroValues
    public var lfo1: Float
    public var lfo2: Float
    public var lfo3: Float
    public var ampEnvelope: Float
    public var modEnvelope: Float

    public init(macros: AudioCoreMacroValues = .defaults,
                lfo1: Float = 0,
                lfo2: Float = 0,
                lfo3: Float = 0,
                ampEnvelope: Float = 0,
                modEnvelope: Float = 0) {
        self.macros = macros
        self.lfo1 = lfo1.isFinite ? lfo1 : 0
        self.lfo2 = lfo2.isFinite ? lfo2 : 0
        self.lfo3 = lfo3.isFinite ? lfo3 : 0
        self.ampEnvelope = ampEnvelope.isFinite ? ampEnvelope : 0
        self.modEnvelope = modEnvelope.isFinite ? modEnvelope : 0
    }

    public static let silent = AudioCoreModulationSourceValues()

    /// Liest den aktuellen Wert einer `AudioCoreModulationSource`. Nicht-
    /// endliche gespeicherte Werte wurden bereits im Initialisierer
    /// abgefangen; ein zusaetzlicher Endlichkeits-Fallback hier schuetzt
    /// gegen direkte Feldmutation nach der Konstruktion.
    public subscript(source: AudioCoreModulationSource) -> Float {
        let raw: Float
        switch source {
        case .macro(let id):
            raw = macros[id]
        case .lfo(let slot):
            switch slot {
            case .lfo1: raw = lfo1
            case .lfo2: raw = lfo2
            case .lfo3: raw = lfo3
            }
        case .envelope(let role):
            switch role {
            case .amp: raw = ampEnvelope
            case .mod: raw = modEnvelope
            }
        }
        return raw.isFinite ? raw : 0
    }
}
