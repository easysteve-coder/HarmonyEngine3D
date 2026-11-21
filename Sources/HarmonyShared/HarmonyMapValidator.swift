import Foundation

// MARK: – HarmonyMapValidator
//
// Öffentlicher, strukturierter Validierungsvertrag für HarmonyMap (Runde 017 /
// F-03). Portiert die bisher private Validierung aus `HarmonyMapLoader`
// (print-basiert, Bool-Flag) in strukturierte `Issue`-Werte, die Engine und
// DesignerKit (später) gleichermaßen konsumieren können.
//
// Regeln unverändert gegenüber der bisherigen `HarmonyMapLoader`-Validierung
// (siehe dortige Kommentare zur Historie), plus eine neue Regel (Scope C):
// Layer-Katalog (`HarmonyLayer.relationTypes`) gegen tatsächlich über
// `HarmonyEdge.layers` zugeordnete `relationTypes` — die Kante bleibt
// operative Quelle, eine Abweichung ist Warning, kein Error.
//
// Kein SceneKit, kein AppSettings, kein UI.

public enum HarmonyMapValidator {

    public enum Severity: String {
        case error
        case warning
    }

    public struct Issue: CustomStringConvertible {
        public let severity:   Severity
        public let code:       String
        public let objectPath: String
        public let message:    String

        /// Additiver public Initializer (K-06) — reine Value-Konstruktion,
        /// keine Regel-/Code-/Severity-Semantik geändert. Erlaubt
        /// `DesignerKit`/`HarmonyAuthoring`, Test-Issues außerhalb von
        /// `HarmonyShared` zu konstruieren (z. B. für Issue-Navigator-
        /// Fokus-Tests), ohne einen echten Validator-Lauf zu benötigen.
        public init(severity: Severity, code: String, objectPath: String, message: String) {
            self.severity = severity
            self.code = code
            self.objectPath = objectPath
            self.message = message
        }

        public var description: String { "[\(severity.rawValue)] \(code) @ \(objectPath): \(message)" }
    }

    public struct Result {
        public let issues: [Issue]

        public var errors:    [Issue] { issues.filter { $0.severity == .error } }
        public var warnings:  [Issue] { issues.filter { $0.severity == .warning } }
        /// Runtime-Akzeptanz: true nur wenn keine Errors vorliegen. Warnings
        /// blockieren die Runtime-Akzeptanz nicht.
        public var isAcceptable: Bool { errors.isEmpty }
    }

    // MARK: – Validate

    public static func validate(_ map: HarmonyMap) -> Result {
        var issues: [Issue] = []

        // ── schemaVersion — Hard Check ────────────────────────────────────
        if map.schemaVersion != "1.0" {
            issues.append(Issue(
                severity: .error, code: "schemaVersionUnsupported", objectPath: "$.schemaVersion",
                message: "schemaVersion '\(map.schemaVersion)' nicht unterstützt (erwartet: \"1.0\")"
            ))
        }

        let nodeIDs  = Set(map.nodes.map { $0.id })
        let layerIDs = Set(map.layers.map { $0.id })

        // ── Doppelte IDs ───────────────────────────────────────────────────
        if map.nodes.count != nodeIDs.count {
            issues.append(Issue(severity: .error, code: "duplicateNodeID", objectPath: "$.nodes",
                                 message: "doppelte Node-IDs"))
        }
        let edgeIDs = map.edges.map { $0.id }
        if edgeIDs.count != Set(edgeIDs).count {
            issues.append(Issue(severity: .error, code: "duplicateEdgeID", objectPath: "$.edges",
                                 message: "doppelte Edge-IDs"))
        }
        if map.layers.count != layerIDs.count {
            issues.append(Issue(severity: .error, code: "duplicateLayerID", objectPath: "$.layers",
                                 message: "doppelte Layer-IDs"))
        }

        // ── Nodes ──────────────────────────────────────────────────────────
        for node in map.nodes {
            let path = "$.nodes[\(node.id)]"
            if node.midiNotes.isEmpty {
                issues.append(Issue(severity: .error, code: "nodeMidiNotesEmpty", objectPath: path,
                                     message: "midiNotes ist leer"))
            }
            for note in node.midiNotes where !(0...127).contains(note) {
                issues.append(Issue(severity: .error, code: "nodeMidiNoteOutOfRange", objectPath: path,
                                     message: "MIDI-Note \(note) außerhalb 0...127"))
            }
            if let explicitLayers = node.layers {
                for l in explicitLayers where !layerIDs.contains(l) {
                    issues.append(Issue(severity: .error, code: "nodeLayerUndefined", objectPath: path,
                                         message: "Layer '\(l)' nicht definiert"))
                }
            }
            if let layout = node.layout3D,
               !(layout.x.isFinite && layout.y.isFinite && layout.z.isFinite) {
                issues.append(Issue(severity: .error, code: "nodeLayout3DNonFinite", objectPath: path,
                                     message: "layout3D enthält nicht-endliche Koordinate"))
            }
        }

        // ── Edges ──────────────────────────────────────────────────────────
        for edge in map.edges {
            let path = "$.edges[\(edge.id)]"
            if !nodeIDs.contains(edge.source) {
                issues.append(Issue(severity: .error, code: "edgeSourceUnknown", objectPath: path,
                                     message: "source '\(edge.source)' nicht in Nodes"))
            }
            if !nodeIDs.contains(edge.target) {
                issues.append(Issue(severity: .error, code: "edgeTargetUnknown", objectPath: path,
                                     message: "target '\(edge.target)' nicht in Nodes"))
            }
            for l in edge.layers where !layerIDs.contains(l) {
                issues.append(Issue(severity: .error, code: "edgeLayerUndefined", objectPath: path,
                                     message: "Layer '\(l)' nicht definiert"))
            }
            if edge.relationTypes.isEmpty {
                issues.append(Issue(severity: .error, code: "edgeRelationTypesEmpty", objectPath: path,
                                     message: "relationTypes ist leer"))
            }
            if !edge.weight.isFinite || edge.weight <= 0 {
                issues.append(Issue(severity: .error, code: "edgeWeightInvalid", objectPath: path,
                                     message: "weight \(edge.weight) ist nicht endlich/positiv"))
            }
        }

        // ── Layers: relationTypes nicht leer (hart), leerer Layer (Warning) ─
        for layer in map.layers {
            let path = "$.layers[\(layer.id)]"
            if layer.relationTypes.isEmpty {
                issues.append(Issue(severity: .error, code: "layerRelationTypesEmpty", objectPath: path,
                                     message: "relationTypes ist leer"))
            }
            let hasEdges  = map.edges.contains { $0.layers.contains(layer.id) }
            let hasActive = !map.activeNodeIDs(in: layer.id).isEmpty
            if !hasEdges && !hasActive {
                issues.append(Issue(severity: .warning, code: "layerEmpty", objectPath: path,
                                     message: "Layer ist leer (keine aktiven Nodes, keine Kanten)"))
            }
        }

        // ── Layer-Katalog vs. operative Edge-Zuordnung (neu, Scope C) ───────
        //
        // Die Kante bleibt operative Quelle: relationTypes, die auf Kanten
        // eines Layers tatsächlich vorkommen, aber nicht im deklarierten
        // `HarmonyLayer.relationTypes`-Katalog stehen, sind eine Abweichung —
        // Warning, kein Error (kein hartes Schema, keine neue musikalische
        // Semantik erfunden).
        for layer in map.layers {
            let declared = Set(layer.relationTypes)
            let used = map.edges
                .filter { $0.layers.contains(layer.id) }
                .reduce(into: Set<RelationType>()) { $0.formUnion($1.relationTypes) }
            let undeclared = used.subtracting(declared)
            if !undeclared.isEmpty {
                let names = undeclared.map { $0.rawValue }.sorted().joined(separator: ", ")
                issues.append(Issue(
                    severity: .warning, code: "layerRelationTypeCatalogMismatch",
                    objectPath: "$.layers[\(layer.id)]",
                    message: "Kanten in diesem Layer nutzen relationTypes, die nicht im Layer-Katalog"
                        + " stehen: \(names)"
                ))
            }
        }

        // ── Isolation ──────────────────────────────────────────────────────
        //
        // Harter Fehler nur bei global isolierten Nodes (keine einzige Kante
        // im gesamten Graph). Ein nur innerhalb eines Layers isolierter, aber
        // dort explizit als aktiv markierter Node ist ein bewusster
        // Sonderfall → nur Warning.
        let nodesWithAnyEdge = Set(map.edges.flatMap { [$0.source, $0.target] })
        for node in map.nodes where !nodesWithAnyEdge.contains(node.id) {
            issues.append(Issue(severity: .error, code: "nodeGloballyIsolated", objectPath: "$.nodes[\(node.id)]",
                                 message: "keine einzige Kante im gesamten Graph (isoliert)"))
        }
        for layer in map.layers {
            let activeInLayer = map.activeNodeIDs(in: layer.id)
            let nodesWithEdgeInLayer = Set(
                map.edges.filter { $0.layers.contains(layer.id) }.flatMap { [$0.source, $0.target] }
            )
            for nodeID in activeInLayer.subtracting(nodesWithEdgeInLayer).sorted() {
                issues.append(Issue(
                    severity: .warning, code: "nodeIsolatedInExplicitLayer",
                    objectPath: "$.nodes[\(nodeID)]",
                    message: "explizit aktiv in Layer '\(layer.id)', hat dort aber keine Kante"
                ))
            }
        }

        return Result(issues: issues)
    }
}
