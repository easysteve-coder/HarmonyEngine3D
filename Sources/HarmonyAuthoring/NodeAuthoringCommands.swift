import HarmonyShared

// MARK: – AuthoringIDGenerator
//
// Gemeinsame deterministische ID-Vergabe fuer Add/Duplicate ueber Node-,
// Edge- und Layer-Commands hinweg (K-04/K-05). Kein Zufall — dieselbe Basis
// + dieselbe Menge existierender IDs liefert immer dasselbe Ergebnis,
// testbar und fuer `DesignerViewModel` vorhersagbar (kann die vom Command
// intern erzeugte ID vorab spiegeln, ohne die Draft-Antwort abwarten/diffen
// zu muessen).

public enum AuthoringIDGenerator {
    /// Liefert `base`, falls frei, sonst `base-2`, `base-3`, ... — die erste
    /// freie Variante in aufsteigender Reihenfolge.
    public static func freeID(base: String, existingIDs: Set<String>) -> String {
        guard existingIDs.contains(base) else { return base }
        var n = 2
        while existingIDs.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }
}

// MARK: – AddNodeCommand
//
// Fuegt genau eine neue `HarmonyNode` ein. Reine strukturelle Mutation der
// Node-Liste — keine Edges/Layers betroffen, Reihenfolge deterministisch
// (Anhaengen ans Ende). Der Node-Inhalt selbst ist Sache des Aufrufers; K-04
// verwendet dafuer einen rein technischen Platzhalter-Default (siehe
// `DesignerViewModel.addNode()`), keine musikalische Builder-Entscheidung.

public struct AddNodeCommand: HarmonyMapCommand {
    public enum CommandError: Error, CustomStringConvertible {
        case emptyID
        case duplicateID(String)
        public var description: String {
            switch self {
            case .emptyID: return "AddNodeCommand: Node-ID darf nicht leer sein"
            case .duplicateID(let id): return "AddNodeCommand: Node-ID '\(id)' existiert bereits"
            }
        }
    }

    public let node: HarmonyNode

    public init(node: HarmonyNode) {
        self.node = node
    }

    public func apply(to map: HarmonyMap) throws -> HarmonyMap {
        guard !node.id.isEmpty else { throw CommandError.emptyID }
        guard !map.nodes.contains(where: { $0.id == node.id }) else { throw CommandError.duplicateID(node.id) }
        return HarmonyMap(
            schemaVersion: map.schemaVersion, id: map.id, name: map.name, layers: map.layers,
            nodes: map.nodes + [node], edges: map.edges, layout: map.layout
        )
    }
}

// MARK: – DuplicateNodeCommand
//
// Kopiert eine existierende Node mit einer deterministisch freien ID
// (`<id>-copy`, `<id>-copy-2`, ... via `AuthoringIDGenerator`). Uebernimmt
// Root/Type/Function/MIDI/Tags/Layers/layout3D unveraendert. Keine Edges
// betroffen — die Kopie startet ohne eigene Kanten.

public struct DuplicateNodeCommand: HarmonyMapCommand {
    public enum CommandError: Error, CustomStringConvertible {
        case nodeNotFound(String)
        public var description: String {
            switch self {
            case .nodeNotFound(let id): return "DuplicateNodeCommand: Node '\(id)' nicht gefunden"
            }
        }
    }

    public let sourceNodeID: String

    public init(sourceNodeID: String) {
        self.sourceNodeID = sourceNodeID
    }

    public func apply(to map: HarmonyMap) throws -> HarmonyMap {
        guard let source = map.nodes.first(where: { $0.id == sourceNodeID }) else {
            throw CommandError.nodeNotFound(sourceNodeID)
        }
        let existingIDs = Set(map.nodes.map { $0.id })
        let newID = AuthoringIDGenerator.freeID(base: "\(sourceNodeID)-copy", existingIDs: existingIDs)
        let copy = HarmonyNode(
            id: newID, root: source.root, type: source.type, function: source.function,
            midiNotes: source.midiNotes, tags: source.tags, layout3D: source.layout3D, layers: source.layers
        )
        return HarmonyMap(
            schemaVersion: map.schemaVersion, id: map.id, name: map.name, layers: map.layers,
            nodes: map.nodes + [copy], edges: map.edges, layout: map.layout
        )
    }
}

// MARK: – RenameNodeCommand
//
// Benennt eine Node atomar um und aktualisiert im selben Command-Apply alle
// `HarmonyEdge.source`/`target`-Referenzen — es entsteht zu keinem
// Zwischenzeitpunkt eine dangling Referenz, weil `HarmonyMapDocument.
// perform(_:)` den neuen Draft ohnehin nur bei vollstaendigem Erfolg
// uebernimmt (kein Teil-Commit moeglich).
//
// No-op-Rename (`newID == nodeID`): bewusst deterministisch als Erfolg mit
// unveraendertem Draft behandelt (kein Fehler) — konsistent mit "Rename auf
// denselben Namen" in den meisten Rename-UIs.

public struct RenameNodeCommand: HarmonyMapCommand {
    public enum CommandError: Error, CustomStringConvertible {
        case nodeNotFound(String)
        case emptyNewID
        case duplicateID(String)
        public var description: String {
            switch self {
            case .nodeNotFound(let id): return "RenameNodeCommand: Node '\(id)' nicht gefunden"
            case .emptyNewID: return "RenameNodeCommand: neue ID darf nicht leer sein"
            case .duplicateID(let id): return "RenameNodeCommand: Node-ID '\(id)' existiert bereits"
            }
        }
    }

    public let nodeID: String
    public let newID: String

    public init(nodeID: String, newID: String) {
        self.nodeID = nodeID
        self.newID = newID
    }

    public func apply(to map: HarmonyMap) throws -> HarmonyMap {
        guard !newID.isEmpty else { throw CommandError.emptyNewID }
        guard map.nodes.contains(where: { $0.id == nodeID }) else { throw CommandError.nodeNotFound(nodeID) }
        guard newID != nodeID else { return map }
        guard !map.nodes.contains(where: { $0.id == newID }) else { throw CommandError.duplicateID(newID) }

        let renamedNodes = map.nodes.map { node -> HarmonyNode in
            guard node.id == nodeID else { return node }
            return HarmonyNode(
                id: newID, root: node.root, type: node.type, function: node.function,
                midiNotes: node.midiNotes, tags: node.tags, layout3D: node.layout3D, layers: node.layers
            )
        }
        let renamedEdges = map.edges.map { edge -> HarmonyEdge in
            let newSource = edge.source == nodeID ? newID : edge.source
            let newTarget = edge.target == nodeID ? newID : edge.target
            guard newSource != edge.source || newTarget != edge.target else { return edge }
            return HarmonyEdge(
                id: edge.id, source: newSource, target: newTarget, relationTypes: edge.relationTypes,
                directed: edge.directed, layers: edge.layers, weight: edge.weight,
                magnetProfile: edge.magnetProfile, bridgesTo: edge.bridgesTo
            )
        }
        return HarmonyMap(
            schemaVersion: map.schemaVersion, id: map.id, name: map.name, layers: map.layers,
            nodes: renamedNodes, edges: renamedEdges, layout: map.layout
        )
    }
}

// MARK: – DeleteNodeCommand
//
// Entfernt genau eine Node UND alle inzidenten Kanten im selben Apply —
// referenzielle Cleanup-Semantik (kein K-05-Edge-Authoring): eine Kante mit
// `source`/`target` auf die geloeschte Node kann sonst nicht mehr sinnvoll
// existieren, ihre Entfernung ist Teil der Delete-Operation, keine separate
// Edge-Bearbeitung.

public struct DeleteNodeCommand: HarmonyMapCommand {
    public enum CommandError: Error, CustomStringConvertible {
        case nodeNotFound(String)
        public var description: String {
            switch self {
            case .nodeNotFound(let id): return "DeleteNodeCommand: Node '\(id)' nicht gefunden"
            }
        }
    }

    public let nodeID: String

    public init(nodeID: String) {
        self.nodeID = nodeID
    }

    public func apply(to map: HarmonyMap) throws -> HarmonyMap {
        guard map.nodes.contains(where: { $0.id == nodeID }) else { throw CommandError.nodeNotFound(nodeID) }
        let remainingNodes = map.nodes.filter { $0.id != nodeID }
        let remainingEdges = map.edges.filter { $0.source != nodeID && $0.target != nodeID }
        return HarmonyMap(
            schemaVersion: map.schemaVersion, id: map.id, name: map.name, layers: map.layers,
            nodes: remainingNodes, edges: remainingEdges, layout: map.layout
        )
    }
}

// MARK: – UpdateNodeCommand
//
// Bearbeitet Root/Type/Function/MIDI/Tags/Layers/layout3D einer bestehenden
// Node (Inspector-Vertrag, K-04 Scope B). MIDI muss nicht-leer und
// 0...127 bleiben; Layers duerfen nur bestehende Layer-IDs referenzieren
// (oder `nil`/leer, falls die Node layer-unabhaengig bleiben soll).

public struct UpdateNodeCommand: HarmonyMapCommand {
    public enum CommandError: Error, CustomStringConvertible {
        case nodeNotFound(String)
        case emptyMidiNotes
        case midiNoteOutOfRange(Int)
        case unknownLayer(String)
        public var description: String {
            switch self {
            case .nodeNotFound(let id): return "UpdateNodeCommand: Node '\(id)' nicht gefunden"
            case .emptyMidiNotes: return "UpdateNodeCommand: midiNotes darf nicht leer sein"
            case .midiNoteOutOfRange(let n): return "UpdateNodeCommand: MIDI-Note \(n) außerhalb 0...127"
            case .unknownLayer(let id): return "UpdateNodeCommand: Layer '\(id)' nicht definiert"
            }
        }
    }

    public let nodeID: String
    public let root: Int
    public let type: ChordType
    public let function: HarmonicFunction
    public let midiNotes: [Int]
    public let tags: [String]
    public let layers: [String]?
    public let layout3D: Layout3D?

    public init(
        nodeID: String, root: Int, type: ChordType, function: HarmonicFunction, midiNotes: [Int],
        tags: [String] = [], layers: [String]? = nil, layout3D: Layout3D? = nil
    ) {
        self.nodeID = nodeID
        self.root = root
        self.type = type
        self.function = function
        self.midiNotes = midiNotes
        self.tags = tags
        self.layers = layers
        self.layout3D = layout3D
    }

    public func apply(to map: HarmonyMap) throws -> HarmonyMap {
        guard map.nodes.contains(where: { $0.id == nodeID }) else { throw CommandError.nodeNotFound(nodeID) }
        guard !midiNotes.isEmpty else { throw CommandError.emptyMidiNotes }
        for note in midiNotes where !(0...127).contains(note) {
            throw CommandError.midiNoteOutOfRange(note)
        }
        if let layers {
            let layerIDs = Set(map.layers.map { $0.id })
            for layerID in layers where !layerIDs.contains(layerID) {
                throw CommandError.unknownLayer(layerID)
            }
        }
        let updatedNodes = map.nodes.map { node -> HarmonyNode in
            guard node.id == nodeID else { return node }
            return HarmonyNode(
                id: node.id, root: root, type: type, function: function, midiNotes: midiNotes,
                tags: tags, layout3D: layout3D, layers: layers
            )
        }
        return HarmonyMap(
            schemaVersion: map.schemaVersion, id: map.id, name: map.name, layers: map.layers,
            nodes: updatedNodes, edges: map.edges, layout: map.layout
        )
    }
}
