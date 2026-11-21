import HarmonyShared

// MARK: – HarmonyBuilderConfig
//
// V1-Konfiguration des diatonischen Builders (K-08, Abschluss-Slice von
// Milestone M2). Bewusst schmal: nur Tonart (Pitch-Class 0...11, Default
// C) und ein optionaler Ziel-Layer. Keine Skalen-Auswahl (V1 ist fest
// Dur/Ionian), keine Sekundaerdominanten-/Modal-Interchange-Parameter.
// Reiner Value-Typ, keine AppSettings-Abhaengigkeit.

public struct HarmonyBuilderConfig {
    /// Tonart als Pitch-Class (0 = C, 1 = C#, ... 11 = B).
    public let keyRoot: Int
    /// Prefix fuer generierte Node-/Edge-IDs. Default: Notenname von
    /// `keyRoot` (z. B. "C" fuer keyRoot 0).
    public let idPrefix: String
    /// Optionaler Ziel-Layer fuer die vorgeschlagenen Nodes/Edges. Existiert
    /// dieser Layer nicht im Ziel-Dokument, meldet `proposeDiff` eine
    /// Warnung und laesst Layer-Zuordnung weg, statt einen unbekannten
    /// Layer stillschweigend zu referenzieren.
    public let layerID: String?

    public init(keyRoot: Int = 0, idPrefix: String? = nil, layerID: String? = nil) {
        self.keyRoot = keyRoot
        self.idPrefix = idPrefix ?? HarmonyBuilderConfig.pitchClassName(keyRoot)
        self.layerID = layerID
    }

    /// Reine Namens-/Formatierungshilfe fuer IDs (keine neue musikalische
    /// Semantik) — Sharps-only-Notation, wie an anderen Stellen im Projekt
    /// ueblich.
    static func pitchClassName(_ pitchClass: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let normalized = ((pitchClass % 12) + 12) % 12
        return names[normalized]
    }
}

// MARK: – HarmonyBuilderDiff
//
// Vorschlags-Diff des Builders: hinzuzufuegende Nodes/Edges mit kurzer
// Begruendung, plus Konflikt-/Hinweis-Warnungen. Der Builder mutiert nie
// direkt einen Draft — Anwenden laeuft ausschliesslich ueber
// `ApplyHarmonyBuilderDiffCommand` (Scope B).

public struct HarmonyBuilderDiff {

    public struct ProposedNode {
        public let node: HarmonyNode
        public let rationale: String
    }

    public struct ProposedEdge {
        public let edge: HarmonyEdge
        public let rationale: String
    }

    public struct Warning: CustomStringConvertible {
        public let objectKind: String   // "node" | "edge" | "layer"
        public let id: String
        public let message: String

        public var description: String { "[\(objectKind) \(id)] \(message)" }
    }

    public let proposedNodes: [ProposedNode]
    public let proposedEdges: [ProposedEdge]
    public let warnings: [Warning]

    public init(proposedNodes: [ProposedNode], proposedEdges: [ProposedEdge], warnings: [Warning]) {
        self.proposedNodes = proposedNodes
        self.proposedEdges = proposedEdges
        self.warnings = warnings
    }

    /// `true`, wenn der Diff nichts Neues vorschlaegt (z. B. weil alle
    /// Stufen bereits existieren) — `ApplyHarmonyBuilderDiffCommand` lehnt
    /// einen leeren Diff ab.
    public var isEmpty: Bool { proposedNodes.isEmpty && proposedEdges.isEmpty }
}

// MARK: – DiatonicHarmonyBuilder
//
// Erster regelbasierter Builder (K-08). Erzeugt einen deterministischen
// Diff der sieben diatonischen Stufenakkorde einer Dur/Ionian-Tonart plus
// stufenweiser Nachbarschafts-Kanten — keine Sekundaerdominanten, keine
// Modal-Interchange-Automatik, keine Voice-Leading-Logik. Reine, seiteneffekt-
// freie Funktion: gleicher Input (Map + Config) liefert immer denselben
// Diff, keine Zufallswerte.
//
// Funktionsharmonik-Klassifikation (Piston, Standard-Lehrbuchmapping fuer
// Dur): Tonic = I/iii/vi, Subdominant = ii/IV, Dominant = V/vii°. Das ist
// die einfachste, unstrittigste V1-Zuordnung — keine eigene fachliche
// Entscheidung ueber "einfaches C-Dur/Ionian V1" hinaus.

public enum DiatonicHarmonyBuilder {

    private struct Degree {
        let roman: String
        let semitoneOffset: Int
        let chordType: ChordType
        let function: HarmonicFunction
    }

    /// Sieben diatonische Stufen in Dur/Ionian, feste Reihenfolge I...vii —
    /// zusammen mit `keyRoot` deterministisch fuer ID-Vergabe und Diff-
    /// Reihenfolge. Bewusst eine berechnete statt gespeicherte statische
    /// Property: `ChordType`/`HarmonicFunction` (HarmonyShared) sind nicht
    /// `Sendable`-annotiert, ein gespeichertes globales Array wäre unter
    /// Strict Concurrency ein `#MutableGlobalVariable`-Fund. Eine berechnete
    /// Property erzeugt bei jedem Zugriff ein frisches, rein lokales Array —
    /// kein geteilter globaler Zustand, keine neue Sendable-Anforderung an
    /// `HarmonyShared`.
    private static var degrees: [Degree] {
        [
            Degree(roman: "I",   semitoneOffset: 0,  chordType: .maj7, function: .tonic),
            Degree(roman: "ii",  semitoneOffset: 2,  chordType: .m7,   function: .subdominant),
            Degree(roman: "iii", semitoneOffset: 4,  chordType: .m7,   function: .tonic),
            Degree(roman: "IV",  semitoneOffset: 5,  chordType: .maj7, function: .subdominant),
            Degree(roman: "V",   semitoneOffset: 7,  chordType: .dom7, function: .dominant),
            Degree(roman: "vi",  semitoneOffset: 9,  chordType: .m7,   function: .tonic),
            Degree(roman: "vii", semitoneOffset: 11, chordType: .m7b5, function: .dominant),
        ]
    }

    /// Akkordton-Intervalle relativ zum Grundton (reine Werte-Zuordnung,
    /// keine neue musikalische Regel — Standard-Terz-Stapelung pro
    /// `ChordType`).
    private static func chordToneIntervals(for type: ChordType) -> [Int] {
        switch type {
        case .maj7: return [0, 4, 7, 11]
        case .m7:   return [0, 3, 7, 10]
        case .dom7: return [0, 4, 7, 10]
        case .m7b5: return [0, 3, 6, 10]
        case .dim7: return [0, 3, 6, 9]
        case .maj:  return [0, 4, 7]
        case .min:  return [0, 3, 7]
        case .sus4: return [0, 5, 7]
        }
    }

    private static func nodeID(prefix: String, roman: String) -> String { "\(prefix)-\(roman)" }

    /// Berechnet den Vorschlags-Diff fuer `map` mit `config`. Reine Funktion
    /// — keine Draft-Mutation, kein Zufall, stabile IDs/Reihenfolge.
    public static func proposeDiff(for map: HarmonyMap, config: HarmonyBuilderConfig = HarmonyBuilderConfig()) -> HarmonyBuilderDiff {
        var proposedNodes: [HarmonyBuilderDiff.ProposedNode] = []
        var proposedEdges: [HarmonyBuilderDiff.ProposedEdge] = []
        var warnings: [HarmonyBuilderDiff.Warning] = []

        let existingNodeIDs = Set(map.nodes.map { $0.id })
        var nodeIDsAfterDiff = existingNodeIDs

        let layerIsUsable: Bool
        if let layerID = config.layerID {
            layerIsUsable = map.layers.contains { $0.id == layerID }
            if !layerIsUsable {
                warnings.append(HarmonyBuilderDiff.Warning(
                    objectKind: "layer", id: layerID,
                    message: "Layer '\(layerID)' ist im Dokument nicht definiert — Vorschlaege werden ohne Layer-Zuordnung erzeugt"
                ))
            }
        } else {
            layerIsUsable = false
        }
        let edgeLayers = (layerIsUsable ? [config.layerID!] : [])

        for degree in degrees {
            let id = nodeID(prefix: config.idPrefix, roman: degree.roman)
            guard !existingNodeIDs.contains(id) else {
                warnings.append(HarmonyBuilderDiff.Warning(
                    objectKind: "node", id: id, message: "Node '\(id)' existiert bereits — übersprungen"
                ))
                continue
            }
            let root = ((config.keyRoot + degree.semitoneOffset) % 12 + 12) % 12
            let baseMidi = 60 + config.keyRoot + degree.semitoneOffset
            let midiNotes = chordToneIntervals(for: degree.chordType).map { baseMidi + $0 }
            let node = HarmonyNode(id: id, root: root, type: degree.chordType, function: degree.function, midiNotes: midiNotes)
            let rationale = "Diatonische Stufe \(degree.roman) in \(config.idPrefix)-Dur/Ionian (Funktion: \(degree.function.rawValue))."
            proposedNodes.append(HarmonyBuilderDiff.ProposedNode(node: node, rationale: rationale))
            nodeIDsAfterDiff.insert(id)
        }

        // Stufenweise Nachbarschaft im geschlossenen Ring I-ii-iii-IV-V-vi-vii-I
        // — ungerichtet, `commonTone` (benachbarte Dur-Stufenakkorde teilen
        // in der Regel gemeinsame Töne). Bewusst KEINE `.vToI`/`.iiToV`-
        // Kennzeichnung hier: das waere eine funktionale Progressions-
        // Aussage (Nicht-Scope "ii-V-I-Automatik"), nicht nur eine
        // strukturelle Stufennachbarschaft.
        let existingEdgeIDs = Set(map.edges.map { $0.id })
        for i in 0..<degrees.count {
            let a = degrees[i]
            let b = degrees[(i + 1) % degrees.count]
            let sourceID = nodeID(prefix: config.idPrefix, roman: a.roman)
            let targetID = nodeID(prefix: config.idPrefix, roman: b.roman)
            let edgeID = "\(sourceID)-\(targetID)"

            guard !existingEdgeIDs.contains(edgeID) else {
                warnings.append(HarmonyBuilderDiff.Warning(
                    objectKind: "edge", id: edgeID, message: "Edge '\(edgeID)' existiert bereits — übersprungen"
                ))
                continue
            }
            guard nodeIDsAfterDiff.contains(sourceID), nodeIDsAfterDiff.contains(targetID) else {
                warnings.append(HarmonyBuilderDiff.Warning(
                    objectKind: "edge", id: edgeID,
                    message: "Edge '\(edgeID)' übersprungen — Quelle oder Ziel fehlt im Diff"
                ))
                continue
            }
            let edge = HarmonyEdge(
                id: edgeID, source: sourceID, target: targetID, relationTypes: [.commonTone],
                directed: false, layers: edgeLayers
            )
            let rationale = "Stufenweise diatonische Nachbarschaft \(a.roman)–\(b.roman) (gemeinsame Töne)."
            proposedEdges.append(HarmonyBuilderDiff.ProposedEdge(edge: edge, rationale: rationale))
        }

        return HarmonyBuilderDiff(proposedNodes: proposedNodes, proposedEdges: proposedEdges, warnings: warnings)
    }
}

// MARK: – ApplyHarmonyBuilderDiffCommand
//
// Wendet einen `HarmonyBuilderDiff` als EINEN einzigen `HarmonyMapCommand`
// an (Scope B) — `HarmonyMapDocument.perform(_:)` macht daraus automatisch
// genau einen Undo-Schritt fuer den gesamten Apply, keine Node-fuer-Node-
// Historie. Referenzsicher wie Add-Commands: prueft erneut auf doppelte
// IDs/unbekannte Layer-Referenzen, unabhaengig davon, dass `proposeDiff`
// bereits konfliktfrei filtert (Verteidigung gegen einen zwischenzeitlich
// veraenderten Draft zwischen Preview und Apply).

public struct ApplyHarmonyBuilderDiffCommand: HarmonyMapCommand {
    public enum CommandError: Error, CustomStringConvertible {
        case emptyDiff
        case duplicateNodeID(String)
        case duplicateEdgeID(String)
        case unknownSource(String)
        case unknownTarget(String)
        case unknownLayer(String)
        public var description: String {
            switch self {
            case .emptyDiff: return "ApplyHarmonyBuilderDiffCommand: Diff enthält keine Vorschläge"
            case .duplicateNodeID(let id): return "ApplyHarmonyBuilderDiffCommand: Node-ID '\(id)' existiert bereits"
            case .duplicateEdgeID(let id): return "ApplyHarmonyBuilderDiffCommand: Edge-ID '\(id)' existiert bereits"
            case .unknownSource(let id): return "ApplyHarmonyBuilderDiffCommand: source '\(id)' nicht in Nodes"
            case .unknownTarget(let id): return "ApplyHarmonyBuilderDiffCommand: target '\(id)' nicht in Nodes"
            case .unknownLayer(let id): return "ApplyHarmonyBuilderDiffCommand: Layer '\(id)' nicht definiert"
            }
        }
    }

    public let diff: HarmonyBuilderDiff

    public init(diff: HarmonyBuilderDiff) {
        self.diff = diff
    }

    public func apply(to map: HarmonyMap) throws -> HarmonyMap {
        guard !diff.isEmpty else { throw CommandError.emptyDiff }

        var nodeIDs = Set(map.nodes.map { $0.id })
        for proposed in diff.proposedNodes {
            guard !nodeIDs.contains(proposed.node.id) else { throw CommandError.duplicateNodeID(proposed.node.id) }
            nodeIDs.insert(proposed.node.id)
        }

        var edgeIDs = Set(map.edges.map { $0.id })
        let layerIDs = Set(map.layers.map { $0.id })
        for proposed in diff.proposedEdges {
            let edge = proposed.edge
            guard !edgeIDs.contains(edge.id) else { throw CommandError.duplicateEdgeID(edge.id) }
            guard nodeIDs.contains(edge.source) else { throw CommandError.unknownSource(edge.source) }
            guard nodeIDs.contains(edge.target) else { throw CommandError.unknownTarget(edge.target) }
            for layerID in edge.layers where !layerIDs.contains(layerID) {
                throw CommandError.unknownLayer(layerID)
            }
            edgeIDs.insert(edge.id)
        }

        return HarmonyMap(
            schemaVersion: map.schemaVersion, id: map.id, name: map.name, layers: map.layers,
            nodes: map.nodes + diff.proposedNodes.map { $0.node },
            edges: map.edges + diff.proposedEdges.map { $0.edge },
            layout: map.layout
        )
    }
}
