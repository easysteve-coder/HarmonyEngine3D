import Foundation

// MARK: – HarmonyMapLoader
//
// Dünner Bundle-/Kompatibilitätsadapter über `HarmonyMapCodec` +
// `HarmonyMapValidator` (Runde 017 / F-03). Konvertiert HarmonyMap →
// ChordNetwork für Kompatibilität mit dem bestehenden System.
//
// Kein SceneKit, kein AppSettings, kein UI.
// Bei jedem Fehler: nil zurückgeben + Log — kein Crash. Runtime-Verhalten
// unverändert gegenüber vor F-03: Decode-/Validation-Errors → nil + sichtbare
// Diagnose; Warnings ohne Errors → Map wird zurückgegeben, Diagnose bleibt
// sichtbar.

public enum HarmonyMapLoader {

    // MARK: – Laden

    /// Lädt eine HarmonyMap aus dem Bundle.
    /// Datei: `Sources/HarmonyShared/Resources/maps/<filename>.json`
    ///
    /// Gibt nil zurück wenn:
    ///   - Datei nicht gefunden
    ///   - JSON nicht dekodierbar (inkl. falsch typisierter vorhandener
    ///     optionaler Felder, striktes Decoding seit F-03)
    ///   - Validierung liefert mindestens einen Error (schemaVersion,
    ///     doppelte IDs, ungültige Referenzen, …)
    public static func load(named filename: String) -> HarmonyMap? {
        let map: HarmonyMap
        do {
            map = try HarmonyMapCodec.decode(fromBundleResource: filename)
        } catch {
            print("⚠️  HarmonyMapLoader: \(filename).json nicht ladbar — \(error)")
            return nil
        }

        let result = HarmonyMapValidator.validate(map)
        for issue in result.issues {
            let prefix = issue.severity == .error ? "⚠️ " : "ℹ️ "
            print("\(prefix) HarmonyMapLoader [\(filename).json]: \(issue.objectPath) — \(issue.message)"
                + " [\(issue.code)]")
        }
        guard result.isAcceptable else { return nil }

        print("✅  HarmonyMapLoader: '\(map.name)' geladen"
            + " (\(map.nodes.count) Nodes, \(map.edges.count) Edges,"
            + " \(map.layers.count) Layer)")
        return map
    }

    // MARK: – Konvertierung

    /// Konvertiert HarmonyMap → ChordNetwork (Kompatibilität mit bestehendem System).
    /// Optional: auf einen Layer filtern (Nodes + Kanten). nil = keine Layer-Filterung,
    /// alle Nodes/Kanten der Map werden ausgewählt.
    ///
    /// Bei gesetztem Layer exportiert diese Funktion nicht mehr "alle Nodes + gefilterte
    /// Kanten" (das hätte eine andere Welt exportiert als HarmonyMap/HarmonyGraphEngine
    /// tatsächlich sehen), sondern ausschließlich die im Layer aktiven Nodes und die
    /// Kanten zwischen ihnen (Phase 3.9.3c).
    ///
    /// Unabhängig von `layer`: ungerichtete Kanten werden für den Legacy-Export generell
    /// symmetrisch als zwei `EdgeData`-Einträge dupliziert (Phase 3.9.3c, siehe unten) —
    /// die Node-/Kanten-*Auswahl* ist bei `layer == nil` unverändert, die Anzahl der
    /// exportierten `EdgeData`-Einträge kann dennoch größer sein als `map.edges.count`.
    public static func toChordNetwork(_ map: HarmonyMap, layer: String? = nil) -> ChordNetwork {
        let activeIDs: Set<String>? = layer.map { map.activeNodeIDs(in: $0) }

        let filteredNodes = map.nodes.filter { activeIDs?.contains($0.id) ?? true }
        let chords = filteredNodes.map { ChordData(name: $0.id, midiNotes: $0.midiNotes) }

        let layerEdges = map.edges.filter { layer == nil || $0.layers.contains(layer!) }
        let scopedEdges: [HarmonyEdge]
        if let ids = activeIDs {
            scopedEdges = layerEdges.filter { ids.contains($0.source) && ids.contains($0.target) }
        } else {
            scopedEdges = layerEdges
        }

        warnAboutSemanticLoss(map: map, layer: layer, edges: scopedEdges)

        // EdgeData kennt kein `directed` — downstream (Autopilot) traversiert
        // ausschließlich source → target. Eine ungerichtete Kante würde ohne
        // Duplikat nur in einer Richtung navigierbar sein; symmetrischer Export
        // hält den Legacy-Pfad hier verlustärmer (Phase 3.9.3c).
        var edges: [EdgeData] = []
        edges.reserveCapacity(scopedEdges.count * 2)
        for e in scopedEdges {
            edges.append(EdgeData(source: e.source, target: e.target, weight: e.weight))
            if !e.directed {
                edges.append(EdgeData(source: e.target, target: e.source, weight: e.weight))
            }
        }

        return ChordNetwork(chords: chords, edges: edges)
    }

    /// Warnt einmalig (aggregiert, nicht pro Kante) wenn das Legacy-ChordNetwork-Format
    /// (nur source/target/weight) Informationen aus der HarmonyMap nicht ausdrücken kann.
    private static func warnAboutSemanticLoss(map: HarmonyMap, layer: String?, edges: [HarmonyEdge]) {
        guard !edges.isEmpty else { return }
        var lost: [String] = []
        if edges.contains(where: { !$0.relationTypes.isEmpty })  { lost.append("relationTypes") }
        if edges.contains(where: { $0.layers.count > 1 })        { lost.append("layers (Mehrfachzugehörigkeit)") }
        if edges.contains(where: { $0.magnetProfile != nil })    { lost.append("magnetProfile") }
        guard !lost.isEmpty else { return }

        let layerDesc = layer.map { "Layer '\($0)'" } ?? "alle Layer"
        print("⚠️  HarmonyMapLoader: toChordNetwork('\(map.id)', \(layerDesc))"
            + " verliert beim Export: \(lost.joined(separator: ", "))"
            + " (\(edges.count) betroffene Kante(n), Legacy-EdgeData kennt nur source/target/weight)")
    }

}
