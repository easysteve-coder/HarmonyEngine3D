import HarmonyShared

// MARK: – IssueFocusTarget
//
// Ordnet `HarmonyMapValidator.Issue.objectPath` einem fokussierbaren Ziel
// zu (K-06, Scope A). UI-frei — `DesignerViewModel` nutzt das Ergebnis, um
// den passenden Node/Edge/Layer zu selektieren. Keine Änderung an
// `HarmonyMapValidator`-Semantik oder Issue-Codes.

public enum IssueFocusTarget: Equatable {
    case node(id: String)
    case edge(id: String)
    case layer(id: String)
    /// Schema-/Sammlungsfehler ohne einzelnes Objekt (z. B. `$.schemaVersion`,
    /// `$.nodes` bei doppelten IDs) sowie jeder unbekannte/unerwartete Pfad —
    /// robuster Fallback statt Crash.
    case global

    /// Erkennt die heutigen Validator-Pfadformen: `$.nodes[id]`,
    /// `$.edges[id]`, `$.layers[id]`. Alles andere (inkl. `$.schemaVersion`,
    /// `$.nodes`, `$.edges`, `$.layers` ohne Klammer-Suffix) wird `.global`.
    public static func parse(objectPath: String) -> IssueFocusTarget {
        if let id = extractID(from: objectPath, prefix: "$.nodes[") { return .node(id: id) }
        if let id = extractID(from: objectPath, prefix: "$.edges[") { return .edge(id: id) }
        if let id = extractID(from: objectPath, prefix: "$.layers[") { return .layer(id: id) }
        return .global
    }

    private static func extractID(from path: String, prefix: String) -> String? {
        guard path.hasPrefix(prefix), path.hasSuffix("]") else { return nil }
        let start = path.index(path.startIndex, offsetBy: prefix.count)
        let end = path.index(before: path.endIndex)
        guard start < end else { return nil }
        return String(path[start..<end])
    }
}
