import HarmonyShared

// MARK: – AddEdgeCommand
//
// Fuegt genau eine neue `HarmonyEdge` ein. Reine strukturelle Mutation der
// Edge-Liste — keine Nodes/Layers betroffen. Der Aufrufer (`DesignerViewModel`)
// vergibt die ID vorab deterministisch ueber `AuthoringIDGenerator`, analog
// zu `AddNodeCommand`.

public struct AddEdgeCommand: HarmonyMapCommand {
    public enum CommandError: Error, CustomStringConvertible {
        case emptyID
        case duplicateID(String)
        case unknownSource(String)
        case unknownTarget(String)
        case emptyRelationTypes
        case invalidWeight(Float)
        case unknownLayer(String)
        public var description: String {
            switch self {
            case .emptyID: return "AddEdgeCommand: Edge-ID darf nicht leer sein"
            case .duplicateID(let id): return "AddEdgeCommand: Edge-ID '\(id)' existiert bereits"
            case .unknownSource(let id): return "AddEdgeCommand: source '\(id)' nicht in Nodes"
            case .unknownTarget(let id): return "AddEdgeCommand: target '\(id)' nicht in Nodes"
            case .emptyRelationTypes: return "AddEdgeCommand: relationTypes darf nicht leer sein"
            case .invalidWeight(let w): return "AddEdgeCommand: weight \(w) muss endlich und > 0 sein"
            case .unknownLayer(let id): return "AddEdgeCommand: Layer '\(id)' nicht definiert"
            }
        }
    }

    public let edge: HarmonyEdge

    public init(edge: HarmonyEdge) {
        self.edge = edge
    }

    public func apply(to map: HarmonyMap) throws -> HarmonyMap {
        guard !edge.id.isEmpty else { throw CommandError.emptyID }
        guard !map.edges.contains(where: { $0.id == edge.id }) else { throw CommandError.duplicateID(edge.id) }
        let nodeIDs = Set(map.nodes.map { $0.id })
        guard nodeIDs.contains(edge.source) else { throw CommandError.unknownSource(edge.source) }
        guard nodeIDs.contains(edge.target) else { throw CommandError.unknownTarget(edge.target) }
        guard !edge.relationTypes.isEmpty else { throw CommandError.emptyRelationTypes }
        guard edge.weight.isFinite && edge.weight > 0 else { throw CommandError.invalidWeight(edge.weight) }
        let layerIDs = Set(map.layers.map { $0.id })
        for layerID in edge.layers where !layerIDs.contains(layerID) {
            throw CommandError.unknownLayer(layerID)
        }
        return HarmonyMap(
            schemaVersion: map.schemaVersion, id: map.id, name: map.name, layers: map.layers,
            nodes: map.nodes, edges: map.edges + [edge], layout: map.layout
        )
    }
}

// MARK: – DeleteEdgeCommand
//
// Entfernt genau eine Edge. Veraendert keine Nodes/Layers.

public struct DeleteEdgeCommand: HarmonyMapCommand {
    public enum CommandError: Error, CustomStringConvertible {
        case edgeNotFound(String)
        public var description: String {
            switch self {
            case .edgeNotFound(let id): return "DeleteEdgeCommand: Edge '\(id)' nicht gefunden"
            }
        }
    }

    public let edgeID: String

    public init(edgeID: String) {
        self.edgeID = edgeID
    }

    public func apply(to map: HarmonyMap) throws -> HarmonyMap {
        guard map.edges.contains(where: { $0.id == edgeID }) else { throw CommandError.edgeNotFound(edgeID) }
        return HarmonyMap(
            schemaVersion: map.schemaVersion, id: map.id, name: map.name, layers: map.layers,
            nodes: map.nodes, edges: map.edges.filter { $0.id != edgeID }, layout: map.layout
        )
    }
}

// MARK: – UpdateEdgeCommand
//
// Bearbeitet source/target/directed/relationTypes/layers/weight/
// magnetProfile/bridgesTo einer bestehenden Edge — die Edge-ID bleibt
// erhalten (kein Edge-Rename-Konzept, anders als bei Nodes/Layern). Nutzt
// dieselben Referenz-/Gewichts-/RelationType-/Layer-Checks wie
// `AddEdgeCommand`.

public struct UpdateEdgeCommand: HarmonyMapCommand {
    public enum CommandError: Error, CustomStringConvertible {
        case edgeNotFound(String)
        case unknownSource(String)
        case unknownTarget(String)
        case emptyRelationTypes
        case invalidWeight(Float)
        case unknownLayer(String)
        public var description: String {
            switch self {
            case .edgeNotFound(let id): return "UpdateEdgeCommand: Edge '\(id)' nicht gefunden"
            case .unknownSource(let id): return "UpdateEdgeCommand: source '\(id)' nicht in Nodes"
            case .unknownTarget(let id): return "UpdateEdgeCommand: target '\(id)' nicht in Nodes"
            case .emptyRelationTypes: return "UpdateEdgeCommand: relationTypes darf nicht leer sein"
            case .invalidWeight(let w): return "UpdateEdgeCommand: weight \(w) muss endlich und > 0 sein"
            case .unknownLayer(let id): return "UpdateEdgeCommand: Layer '\(id)' nicht definiert"
            }
        }
    }

    public let edgeID: String
    public let source: String
    public let target: String
    public let directed: Bool
    public let relationTypes: [RelationType]
    public let layers: [String]
    public let weight: Float
    public let magnetProfile: MagnetProfile?
    public let bridgesTo: String?

    public init(
        edgeID: String, source: String, target: String, directed: Bool, relationTypes: [RelationType],
        layers: [String] = [], weight: Float = 1.0, magnetProfile: MagnetProfile? = nil, bridgesTo: String? = nil
    ) {
        self.edgeID = edgeID
        self.source = source
        self.target = target
        self.directed = directed
        self.relationTypes = relationTypes
        self.layers = layers
        self.weight = weight
        self.magnetProfile = magnetProfile
        self.bridgesTo = bridgesTo
    }

    public func apply(to map: HarmonyMap) throws -> HarmonyMap {
        guard map.edges.contains(where: { $0.id == edgeID }) else { throw CommandError.edgeNotFound(edgeID) }
        let nodeIDs = Set(map.nodes.map { $0.id })
        guard nodeIDs.contains(source) else { throw CommandError.unknownSource(source) }
        guard nodeIDs.contains(target) else { throw CommandError.unknownTarget(target) }
        guard !relationTypes.isEmpty else { throw CommandError.emptyRelationTypes }
        guard weight.isFinite && weight > 0 else { throw CommandError.invalidWeight(weight) }
        let layerIDs = Set(map.layers.map { $0.id })
        for layerID in layers where !layerIDs.contains(layerID) {
            throw CommandError.unknownLayer(layerID)
        }
        let updatedEdges = map.edges.map { edge -> HarmonyEdge in
            guard edge.id == edgeID else { return edge }
            return HarmonyEdge(
                id: edgeID, source: source, target: target, relationTypes: relationTypes, directed: directed,
                layers: layers, weight: weight, magnetProfile: magnetProfile, bridgesTo: bridgesTo
            )
        }
        return HarmonyMap(
            schemaVersion: map.schemaVersion, id: map.id, name: map.name, layers: map.layers,
            nodes: map.nodes, edges: updatedEdges, layout: map.layout
        )
    }
}
