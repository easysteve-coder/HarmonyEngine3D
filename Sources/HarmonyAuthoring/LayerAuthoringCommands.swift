import HarmonyShared

// MARK: – AddLayerCommand
//
// Fuegt genau einen neuen `HarmonyLayer` ein. Keine automatische Edge-/
// Node-Erzeugung oder -Zuordnung — ein neuer Layer ist zunaechst leer.

public struct AddLayerCommand: HarmonyMapCommand {
    public enum CommandError: Error, CustomStringConvertible {
        case emptyID
        case duplicateID(String)
        case emptyRelationTypes
        public var description: String {
            switch self {
            case .emptyID: return "AddLayerCommand: Layer-ID darf nicht leer sein"
            case .duplicateID(let id): return "AddLayerCommand: Layer-ID '\(id)' existiert bereits"
            case .emptyRelationTypes: return "AddLayerCommand: relationTypes darf nicht leer sein"
            }
        }
    }

    public let layer: HarmonyLayer

    public init(layer: HarmonyLayer) {
        self.layer = layer
    }

    public func apply(to map: HarmonyMap) throws -> HarmonyMap {
        guard !layer.id.isEmpty else { throw CommandError.emptyID }
        guard !map.layers.contains(where: { $0.id == layer.id }) else { throw CommandError.duplicateID(layer.id) }
        guard !layer.relationTypes.isEmpty else { throw CommandError.emptyRelationTypes }
        return HarmonyMap(
            schemaVersion: map.schemaVersion, id: map.id, name: map.name, layers: map.layers + [layer],
            nodes: map.nodes, edges: map.edges, layout: map.layout
        )
    }
}

// MARK: – UpdateLayerCommand
//
// Bearbeitet ID (Rename), Name und relationTypes-Katalog eines bestehenden
// Layers in einem Apply. Bei ID-Aenderung werden im selben Apply alle
// `HarmonyEdge.layers`- und alle expliziten `HarmonyNode.layers`-Eintraege
// atomar mitmigriert — dank `HarmonyMapDocument.perform(_:)`s Alles-oder-
// nichts-Uebernahme kann zu keinem Zeitpunkt eine Edge/Node auf eine nicht
// mehr existierende Layer-ID verweisen. No-op-Rename (`newID == layerID`)
// ist wie bei `RenameNodeCommand` deterministisch ein Erfolg (Name/
// relationTypes werden trotzdem aktualisiert, nur die ID bleibt gleich).

public struct UpdateLayerCommand: HarmonyMapCommand {
    public enum CommandError: Error, CustomStringConvertible {
        case layerNotFound(String)
        case emptyNewID
        case duplicateID(String)
        case emptyRelationTypes
        public var description: String {
            switch self {
            case .layerNotFound(let id): return "UpdateLayerCommand: Layer '\(id)' nicht gefunden"
            case .emptyNewID: return "UpdateLayerCommand: neue ID darf nicht leer sein"
            case .duplicateID(let id): return "UpdateLayerCommand: Layer-ID '\(id)' existiert bereits"
            case .emptyRelationTypes: return "UpdateLayerCommand: relationTypes darf nicht leer sein"
            }
        }
    }

    public let layerID: String
    public let newID: String
    public let name: String
    public let relationTypes: [RelationType]

    public init(layerID: String, newID: String, name: String, relationTypes: [RelationType]) {
        self.layerID = layerID
        self.newID = newID
        self.name = name
        self.relationTypes = relationTypes
    }

    public func apply(to map: HarmonyMap) throws -> HarmonyMap {
        guard map.layers.contains(where: { $0.id == layerID }) else { throw CommandError.layerNotFound(layerID) }
        guard !newID.isEmpty else { throw CommandError.emptyNewID }
        guard !relationTypes.isEmpty else { throw CommandError.emptyRelationTypes }
        if newID != layerID {
            guard !map.layers.contains(where: { $0.id == newID }) else { throw CommandError.duplicateID(newID) }
        }

        let updatedLayers = map.layers.map { layer -> HarmonyLayer in
            guard layer.id == layerID else { return layer }
            return HarmonyLayer(id: newID, name: name, relationTypes: relationTypes)
        }
        let updatedEdges = map.edges.map { edge -> HarmonyEdge in
            guard edge.layers.contains(layerID) else { return edge }
            let migratedLayers = edge.layers.map { $0 == layerID ? newID : $0 }
            return HarmonyEdge(
                id: edge.id, source: edge.source, target: edge.target, relationTypes: edge.relationTypes,
                directed: edge.directed, layers: migratedLayers, weight: edge.weight,
                magnetProfile: edge.magnetProfile, bridgesTo: edge.bridgesTo
            )
        }
        let updatedNodes = map.nodes.map { node -> HarmonyNode in
            guard let nodeLayers = node.layers, nodeLayers.contains(layerID) else { return node }
            let migratedLayers = nodeLayers.map { $0 == layerID ? newID : $0 }
            return HarmonyNode(
                id: node.id, root: node.root, type: node.type, function: node.function, midiNotes: node.midiNotes,
                tags: node.tags, layout3D: node.layout3D, layers: migratedLayers
            )
        }
        return HarmonyMap(
            schemaVersion: map.schemaVersion, id: map.id, name: map.name, layers: updatedLayers,
            nodes: updatedNodes, edges: updatedEdges, layout: map.layout
        )
    }
}

// MARK: – DeleteLayerCommand
//
// Entfernt den Layer UND die Layer-ID aus allen Edge-/Node-Layerlisten im
// selben Apply — referenzielle Cleanup-Semantik, analog zu
// `DeleteNodeCommand`s Edge-Cleanup. Entfernt keine Nodes/Edges selbst
// (Layer-Mitgliedschaft allein ist kein Loeschgrund). Kann dadurch
// Validator-Warnings/-Errors an anderer Stelle erzeugen (z. B. eine dann
// leere `HarmonyLayer`-Referenz in einer anderen Kante), aber nie eine
// dangling Layer-ID-Referenz.
//
// Node-Layer-Semantik (Runde 037 / V-00a, Fable-5-Review Finding A10):
// `HarmonyNode.layers` ist `[String]?` — `nil` bedeutet "keine explizite
// Layerbindung, Mitgliedschaft wird aus `HarmonyEdge.layers` abgeleitet"
// (siehe `HarmonyMap.activeNodeIDs(in:)`), waehrend ein leeres `[]` bedeutet
// "explizit in keinem Layer sichtbar". Bleibt nach dem Filtern der geloeschten
// Layer-ID keine explizite Layerzuordnung mehr uebrig, wird deshalb `nil`
// gesetzt statt `[]` — sonst wuerde das Loeschen eines Layers einen Node aus
// allen anderen Layern verschwinden lassen, in denen er ueber seine Kanten
// eigentlich weiterhin aktiv waere. `HarmonyEdge.layers` bleibt `[String]`
// (nicht optional) — dort ist `[]` bereits die korrekte "in keinem Layer"-
// Semantik und wird unveraendert weiter gefiltert.

public struct DeleteLayerCommand: HarmonyMapCommand {
    public enum CommandError: Error, CustomStringConvertible {
        case layerNotFound(String)
        public var description: String {
            switch self {
            case .layerNotFound(let id): return "DeleteLayerCommand: Layer '\(id)' nicht gefunden"
            }
        }
    }

    public let layerID: String

    public init(layerID: String) {
        self.layerID = layerID
    }

    public func apply(to map: HarmonyMap) throws -> HarmonyMap {
        guard map.layers.contains(where: { $0.id == layerID }) else { throw CommandError.layerNotFound(layerID) }

        let remainingLayers = map.layers.filter { $0.id != layerID }
        let updatedEdges = map.edges.map { edge -> HarmonyEdge in
            guard edge.layers.contains(layerID) else { return edge }
            return HarmonyEdge(
                id: edge.id, source: edge.source, target: edge.target, relationTypes: edge.relationTypes,
                directed: edge.directed, layers: edge.layers.filter { $0 != layerID }, weight: edge.weight,
                magnetProfile: edge.magnetProfile, bridgesTo: edge.bridgesTo
            )
        }
        let updatedNodes = map.nodes.map { node -> HarmonyNode in
            guard let nodeLayers = node.layers, nodeLayers.contains(layerID) else { return node }
            let filtered = nodeLayers.filter { $0 != layerID }
            return HarmonyNode(
                id: node.id, root: node.root, type: node.type, function: node.function, midiNotes: node.midiNotes,
                tags: node.tags, layout3D: node.layout3D, layers: filtered.isEmpty ? nil : filtered
            )
        }
        return HarmonyMap(
            schemaVersion: map.schemaVersion, id: map.id, name: map.name, layers: remainingLayers,
            nodes: updatedNodes, edges: updatedEdges, layout: map.layout
        )
    }
}
