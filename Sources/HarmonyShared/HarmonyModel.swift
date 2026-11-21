import Foundation

// MARK: – RelationType
//
// Kanonische Beziehungstypen zwischen Akkorden (v1, fix).
// 6 Typen — keine Erweiterung in v1.

public enum RelationType: String, Codable, Hashable, CaseIterable {
    case vToI           = "V-I"
    case iiToV          = "ii-V"
    case relMajMin      = "relMajMin"
    case parallelMajMin = "parallelMajMin"
    case commonTone     = "commonTone"
    case tritSubst      = "tritSubst"
}

// MARK: – ChordType

public enum ChordType: String, Codable, CaseIterable {
    case maj7, m7, dom7, m7b5, dim7, maj, min, sus4
}

// MARK: – HarmonicFunction

public enum HarmonicFunction: String, Codable, CaseIterable {
    case tonic, subdominant, dominant, ambiguous
}

// MARK: – Layout3D

public struct Layout3D: Codable {
    public let x: Float
    public let y: Float
    public let z: Float

    public init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }
}

// MARK: – MagnetProfile
//
// v1: 3 Presets, keine Overrides.
// Preset-Mapping (intern, wird in v2-Physikschicht ausgewertet):
//   strong: range 25, strength 1.0
//   medium: range 15, strength 0.6
//   weak:   range  8, strength 0.3

public struct MagnetProfile: Codable {
    public enum Preset: String, Codable, CaseIterable {
        case strong, medium, weak
    }
    public let preset: Preset

    public init(preset: Preset) {
        self.preset = preset
    }
}

// MARK: – HarmonyNode
//
// Akkord-Knoten im Harmonie-Netzwerk.
// `tags` ist in JSON optional (Default: leeres Array).
// `layout3D` ist optional (nil = Tonnetz-berechnet in v2).
// `layers` ist optional (nil = Mitgliedschaft wird aus HarmonyEdge.layers abgeleitet,
// siehe HarmonyMap.activeNodeIDs(in:) — Phase 3.9.3b). Ist `layers` gesetzt, gilt das
// als ausdrückliche Mitgliedschaftserklärung, unabhängig von vorhandenen Kanten.

public struct HarmonyNode: Identifiable {
    public let id:        String
    public let root:      Int
    public let type:      ChordType
    public let function:  HarmonicFunction
    public let midiNotes: [Int]
    public let tags:      [String]
    public let layout3D:  Layout3D?
    public let layers:    [String]?

    public init(
        id: String, root: Int, type: ChordType, function: HarmonicFunction, midiNotes: [Int],
        tags: [String] = [], layout3D: Layout3D? = nil, layers: [String]? = nil
    ) {
        self.id        = id
        self.root      = root
        self.type      = type
        self.function  = function
        self.midiNotes = midiNotes
        self.tags      = tags
        self.layout3D  = layout3D
        self.layers    = layers
    }
}

extension HarmonyNode: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, root, type, function, midiNotes, tags, layout3D, layers
    }

    public init(from decoder: Decoder) throws {
        let c     = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(String.self,           forKey: .id)
        root      = try c.decode(Int.self,              forKey: .root)
        type      = try c.decode(ChordType.self,        forKey: .type)
        function  = try c.decode(HarmonicFunction.self, forKey: .function)
        midiNotes = try c.decode([Int].self,            forKey: .midiNotes)
        // decodeIfPresent (statt try?, Runde 017 / F-03): fehlendes Feld → nil/Default,
        // vorhandenes Feld mit falschem Typ → Decode-Fehler statt stillem Verschlucken.
        tags      = (try c.decodeIfPresent([String].self, forKey: .tags))    ?? []
        layout3D  =  try c.decodeIfPresent(Layout3D.self, forKey: .layout3D)
        layers    =  try c.decodeIfPresent([String].self, forKey: .layers)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,        forKey: .id)
        try c.encode(root,      forKey: .root)
        try c.encode(type,      forKey: .type)
        try c.encode(function,  forKey: .function)
        try c.encode(midiNotes, forKey: .midiNotes)
        try c.encode(tags,      forKey: .tags)
        try c.encodeIfPresent(layout3D, forKey: .layout3D)
        try c.encodeIfPresent(layers,   forKey: .layers)
    }
}

// MARK: – HarmonyEdge
//
// Gerichtete oder ungerichtete Kante zwischen zwei Akkord-Knoten.
// `weight` ist optional (Default: 1.0).
// `magnetProfile` und `bridgesTo` sind optional.
// `bridgesTo` wird in v1 geparst aber ignoriert.

public struct HarmonyEdge: Identifiable {
    public let id:            String
    public let source:        String
    public let target:        String
    public let relationTypes: [RelationType]
    public let directed:      Bool
    public let layers:        [String]
    public let weight:        Float
    public let magnetProfile: MagnetProfile?
    public let bridgesTo:     String?

    public init(
        id: String, source: String, target: String, relationTypes: [RelationType], directed: Bool,
        layers: [String], weight: Float = 1.0, magnetProfile: MagnetProfile? = nil, bridgesTo: String? = nil
    ) {
        self.id            = id
        self.source        = source
        self.target        = target
        self.relationTypes = relationTypes
        self.directed      = directed
        self.layers        = layers
        self.weight        = weight
        self.magnetProfile = magnetProfile
        self.bridgesTo     = bridgesTo
    }
}

extension HarmonyEdge: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, source, target, relationTypes, directed, layers, weight, magnetProfile, bridgesTo
    }

    public init(from decoder: Decoder) throws {
        let c         = try decoder.container(keyedBy: CodingKeys.self)
        id            = try  c.decode(String.self,          forKey: .id)
        source        = try  c.decode(String.self,          forKey: .source)
        target        = try  c.decode(String.self,          forKey: .target)
        relationTypes = try  c.decode([RelationType].self,  forKey: .relationTypes)
        directed      = try  c.decode(Bool.self,            forKey: .directed)
        layers        = try  c.decode([String].self,        forKey: .layers)
        // decodeIfPresent (statt try?, Runde 017 / F-03): fehlendes weight → Default 1.0
        // bleibt erlaubt, ein vorhandenes falsch typisiertes weight wird Decode-Fehler.
        weight        = (try c.decodeIfPresent(Float.self,          forKey: .weight))        ?? 1.0
        magnetProfile =  try c.decodeIfPresent(MagnetProfile.self,  forKey: .magnetProfile)
        bridgesTo     =  try c.decodeIfPresent(String.self,         forKey: .bridgesTo)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,            forKey: .id)
        try c.encode(source,        forKey: .source)
        try c.encode(target,        forKey: .target)
        try c.encode(relationTypes, forKey: .relationTypes)
        try c.encode(directed,      forKey: .directed)
        try c.encode(layers,        forKey: .layers)
        try c.encode(weight,        forKey: .weight)
        try c.encodeIfPresent(magnetProfile, forKey: .magnetProfile)
        try c.encodeIfPresent(bridgesTo,     forKey: .bridgesTo)
    }
}

// MARK: – HarmonyLayer

public struct HarmonyLayer: Codable, Identifiable {
    public let id:            String
    public let name:          String
    public let relationTypes: [RelationType]

    public init(id: String, name: String, relationTypes: [RelationType]) {
        self.id            = id
        self.name          = name
        self.relationTypes = relationTypes
    }
}

// MARK: – MapLayout

public struct MapLayout: Codable {
    public let strategy: String   // "tonnetz" | "manual"

    public init(strategy: String) {
        self.strategy = strategy
    }
}

// MARK: – HarmonyMap
//
// Top-Level-Container: eine vollständige Harmonie-Karte.
// `layout` ist optional.

public struct HarmonyMap: Codable {
    public let schemaVersion: String
    public let id:            String
    public let name:          String
    public let layers:        [HarmonyLayer]
    public let nodes:         [HarmonyNode]
    public let edges:         [HarmonyEdge]
    public let layout:        MapLayout?

    public init(
        schemaVersion: String, id: String, name: String, layers: [HarmonyLayer],
        nodes: [HarmonyNode], edges: [HarmonyEdge], layout: MapLayout? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id            = id
        self.name          = name
        self.layers        = layers
        self.nodes         = nodes
        self.edges         = edges
        self.layout        = layout
    }
}

// MARK: – HarmonyMap Layer-Mitgliedschaft (Phase 3.9.3b)
//
// Ein Node gilt in einem Layer als aktiv, wenn er dort musikalisch erreichbar
// ist oder ausdrücklich als aktiv markiert wurde:
//   – node.layers gesetzt  → explizite Mitgliedschaft, unabhängig von Kanten.
//   – node.layers fehlt    → Mitgliedschaft aus HarmonyEdge.layers abgeleitet;
//                            source und target zählen unabhängig von `directed`.
// Bestehende Maps ohne node.layers bleiben dadurch vollständig kompatibel.

extension HarmonyMap {

    /// Aktive Node-IDs in `layerID`. Siehe Herleitungsregel oben.
    public func activeNodeIDs(in layerID: String) -> Set<String> {
        let edgeDerivedIDs = Set(
            edges.filter { $0.layers.contains(layerID) }
                 .flatMap { [$0.source, $0.target] }
        )
        var active = Set<String>()
        for node in nodes {
            if let explicitLayers = node.layers {
                if explicitLayers.contains(layerID) { active.insert(node.id) }
            } else if edgeDerivedIDs.contains(node.id) {
                active.insert(node.id)
            }
        }
        return active
    }

    /// Ist `nodeID` in `layerID` aktiv? Siehe `activeNodeIDs(in:)`.
    public func isNode(_ nodeID: String, activeIn layerID: String) -> Bool {
        activeNodeIDs(in: layerID).contains(nodeID)
    }
}
