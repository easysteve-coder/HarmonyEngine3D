import HarmonyShared

// MARK: – HarmonyMapCommand
//
// Minimaler Command-Vertrag fuer Authoring-Mutationen (K-01 / M2). Ein
// Command transformiert einen `HarmonyMap`-Draft in einen neuen Draft oder
// wirft, wenn die Mutation nicht anwendbar ist. `HarmonyMapDocument.perform(_:)`
// uebernimmt den neuen Draft nur bei Erfolg — ein fehlgeschlagener Command
// laesst Draft/Dirty-State/Revision/Undo-Redo-Stacks unveraendert.
//
// Kein SceneKit, kein AppSettings, kein UI.

public protocol HarmonyMapCommand {
    /// Wendet die Mutation auf `map` an und liefert den neuen Draft.
    /// Wirft, wenn die Mutation nicht anwendbar ist — der Aufrufer darf den
    /// Draft in diesem Fall nicht uebernehmen.
    func apply(to map: HarmonyMap) throws -> HarmonyMap
}

// MARK: – SetMapNameCommand
//
// Minimal-Command zum Setzen des Karten-Namens. Dient als risikoarmer Beweis
// des Command-Vertrags (siehe Handoff Scope C) — keine Node-/Edge-/Layer-
// Semantik.

public struct SetMapNameCommand: HarmonyMapCommand {
    public enum CommandError: Error, CustomStringConvertible {
        case emptyName
        public var description: String { "SetMapNameCommand: Name darf nicht leer sein" }
    }

    public let name: String

    public init(name: String) {
        self.name = name
    }

    public func apply(to map: HarmonyMap) throws -> HarmonyMap {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CommandError.emptyName }
        return HarmonyMap(
            schemaVersion: map.schemaVersion, id: map.id, name: trimmed, layers: map.layers,
            nodes: map.nodes, edges: map.edges, layout: map.layout
        )
    }
}

// MARK: – DraftTransformCommand
//
// Generischer Draft-Transform-Command (siehe Handoff Scope C: "generisches
// ReplaceMapCommand/Draft-Transform-Command mit Validierungs- und Undo-
// Snapshot-Vertrag"). Er definiert selbst KEINE Node-/Edge-/Layer-CRUD-
// Semantik — er ist reine Plumbing, um den Command-/Undo-Redo-Vertrag von
// `HarmonyMapDocument` zu beweisen. Die konkrete Transformation kommt vom
// Aufrufer (z. B. Tests). Nimmt K-04/K-05 (Node-/Edge-/Layer-Authoring-API,
// ID-Vergabe, Layer-Verdrahtung, domänenspezifische Validierung) NICHT
// vorweg, weil hier keinerlei Authoring-Domänenlogik entsteht.

public struct DraftTransformCommand: HarmonyMapCommand {
    public let label: String
    private let transform: (HarmonyMap) throws -> HarmonyMap

    public init(label: String, transform: @escaping (HarmonyMap) throws -> HarmonyMap) {
        self.label = label
        self.transform = transform
    }

    public func apply(to map: HarmonyMap) throws -> HarmonyMap {
        try transform(map)
    }
}
