import HarmonyShared

// MARK: – HarmonyGraphSimulation
//
// UI-freie, runtime-nahe 2D-Simulation für HarmonyWeb-Dokumente (K-07).
// Nutzt intern ausschließlich `HarmonyGraphEngine` — dieselbe Engine, die
// `RuntimeHarmonik` (3D-Runtime) verwendet — für Traversierung,
// Layerfilterung, History-Kontext und effektive Gewichte. Keine eigene
// Nachbarn-/Gewichts-/Layerlogik. Deterministisch bei festem Seed (über
// `HarmonyGraphEngine`s `SeededRNG`).
//
// Kein SceneKit, kein AppSettings, kein UI.

public struct HarmonyGraphSimulation {

    /// Ein Kandidat mit Preview-Feldern (K-07 Scope B) zusätzlich zur reinen
    /// `HarmonyGraphEngine.WeightedTransition` — RelationTypes/Gewicht kommen
    /// direkt aus der Transition, Feldkategorie/Range aus
    /// `HarmonicMagnetPreview` (derselbe Helper, den `RuntimeHarmonik`
    /// nutzt — keine zweite Kopie).
    public struct Candidate {
        public let transition:     HarmonyGraphEngine.WeightedTransition
        public let fieldKind:      HarmonicMagnetFieldKind
        public let magnetPreset:   MagnetProfile.Preset?
        public let effectiveRange: Float
    }

    private let map:          HarmonyMap
    private let startNodeID:  String
    private let initialLayer: String
    private let rangeScale:   Float

    public let seed: UInt64

    private var engine: HarmonyGraphEngine
    public private(set) var currentNodeID: String
    public private(set) var activeLayer:   String
    public private(set) var history:       [String]

    /// `rangeScale` ist ein reiner Value-Parameter (Default `1.0`) — bewusst
    /// kein `HarmonicMagnetConfig`/`AppSettings`-Import in `HarmonyAuthoring`
    /// (Handoff-Vorgabe K-07 Scope B).
    public init(map: HarmonyMap, startNodeID: String, layer: String, seed: UInt64, rangeScale: Float = 1.0) {
        self.map          = map
        self.startNodeID  = startNodeID
        self.initialLayer = layer
        self.rangeScale   = rangeScale
        self.seed         = seed
        self.engine       = HarmonyGraphEngine(map: map, initialLayer: layer, seed: seed)
        self.currentNodeID = startNodeID
        self.activeLayer    = layer
        self.history         = [startNodeID]
        self.engine.recordVisit(startNodeID)
    }

    /// Kandidaten vom aktuellen Node aus — Traversierung/effektive Gewichte
    /// kommen ausschließlich aus `HarmonyGraphEngine.weightedTransitions(from:)`.
    public var candidates: [Candidate] {
        engine.weightedTransitions(from: currentNodeID).map { wt in
            let preset = wt.edge.magnetProfile?.preset
            return Candidate(
                transition: wt,
                fieldKind: HarmonicMagnetPreview.fieldKind(for: wt.edge.relationTypes),
                magnetPreset: preset,
                effectiveRange: HarmonicMagnetPreview.effectiveRange(preset: preset, rangeScale: rangeScale)
            )
        }
    }

    /// Nächster Schritt über `HarmonyGraphEngine.weightedChoice(from:)`. Der
    /// neue Node gilt sofort als besucht (`recordVisit`), bevor die nächsten
    /// Kandidaten ausgewertet werden — passend zum Runtime-Vertrag
    /// (`RuntimeHarmonik.process()`: `recordVisit` vor `weightedTransitions`).
    /// `nil`, wenn keine Kanten vom aktuellen Node aus existieren.
    @discardableResult
    public mutating func step() -> HarmonyNode? {
        guard let next = engine.weightedChoice(from: currentNodeID) else { return nil }
        currentNodeID = next.id
        history.append(next.id)
        engine.recordVisit(next.id)
        return next
    }

    /// Wechselt den aktiven Layer über `HarmonyGraphEngine.setLayer(_:)` —
    /// keine eigene Layerfilterung. No-op bei unbekannter Layer-ID (wie
    /// `HarmonyGraphEngine.setLayer(_:)` selbst).
    public mutating func setLayer(_ layerID: String) {
        guard map.layers.contains(where: { $0.id == layerID }) else { return }
        engine.setLayer(layerID)
        activeLayer = layerID
    }

    /// Baut eine frische `HarmonyGraphEngine` mit demselben Seed/Start-Node/
    /// Layer auf — reproduziert exakt dieselbe deterministische
    /// Step-Sequenz wie beim ersten Durchlauf (K-07 Scope A: "Reset mit
    /// gleichem Seed reproduziert Sequenz").
    public mutating func reset() {
        engine = HarmonyGraphEngine(map: map, initialLayer: initialLayer, seed: seed)
        currentNodeID = startNodeID
        activeLayer = initialLayer
        history = [startNodeID]
        engine.recordVisit(startNodeID)
    }
}
