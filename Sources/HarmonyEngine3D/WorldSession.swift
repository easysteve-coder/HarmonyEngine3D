import Foundation
import HarmonyShared

// MARK: – WorldSession
//
// Einzige Ownership-Stelle für validierte HarmonyMap, aktiven Layer,
// HarmonyGraphEngine und RuntimeHarmonik im HarmonyWeb-/Map-Preview-Pfad
// (Runde 020 / E-01). App, HarmonyScene und Runtime lesen dieselbe Sicht auf
// die Welt statt drei separat konstruierter Kopien.
//
// Lebt im App-Target (`HarmonyEngine3D`), nicht in `HarmonyShared`, weil sie
// `RuntimeHarmonik` besitzt (App-Layer-Typ, kennt SceneKit-freie LocalNode-
// Brücke zu HarmonyScene). `HarmonyMap`/`HarmonyGraphEngine` bleiben
// SceneKit-/AppSettings-frei — WorldSession selbst importiert weder SceneKit
// noch SwiftUI noch AppSettings.
//
// Kein SceneKit, kein AppSettings, kein UI.

// MARK: – WorldSessionError

enum WorldSessionError: Error, CustomStringConvertible, Sendable {
    /// Die Map hat mindestens einen Validator-Error (siehe `HarmonyMapValidator`).
    /// Trägt bereits gerenderte Issue-Beschreibungen statt `[HarmonyMapValidator.Issue]`
    /// direkt — `Issue` ist (noch) nicht `Sendable`, und `Error`-Typen werden unter
    /// Strict Concurrency implizit als `Sendable` erwartet. Sauberer, lokal in
    /// `WorldSession.swift` gelöst statt `HarmonyShared` dafür anzufassen (außerhalb
    /// des E-01-Scopes).
    case invalidMap(errorDescriptions: [String])
    /// `activeLayer` existiert nicht in `map.layers`.
    case unknownLayer(String)
    /// `activeLayer` existiert, aber kein einziger Node ist in diesem Layer aktiv
    /// (siehe `HarmonyMap.activeNodeIDs(in:)`) — leere Layer-Sicht.
    case emptyLayerView(String)

    var description: String {
        switch self {
        case .invalidMap(let errorDescriptions):
            let details = errorDescriptions.joined(separator: "; ")
            return "WorldSession: Map hat \(errorDescriptions.count) Validierungsfehler — \(details)"
        case .unknownLayer(let layer):
            return "WorldSession: Layer '\(layer)' existiert nicht in der Map"
        case .emptyLayerView(let layer):
            return "WorldSession: Layer '\(layer)' hat keine aktiven Nodes (leere Sicht)"
        }
    }
}

// MARK: – WorldSession

final class WorldSession {

    // MARK: – Snapshot
    //
    // Deterministische, layer-gefilterte Sicht auf die Map — Basis für Tests,
    // die Scene- und Runtime-Sicht vergleichen wollen, sowie für den direkten
    // Map-Pfad (HarmonyScene liest daraus, nicht mehr über
    // `HarmonyMapLoader.toChordNetwork`). Reihenfolge entspricht der
    // Deklarationsreihenfolge in `map.nodes`/`map.edges` (JSON-Array-Ordnung,
    // bereits deterministisch) — kein zusätzliches Sortieren nötig.

    struct Snapshot {
        /// Aktive Node-IDs im Layer, in Map-Reihenfolge.
        let nodeIDs: [String]
        /// Aktive Nodes im Layer (siehe `HarmonyMap.activeNodeIDs(in:)`).
        let nodes:   [HarmonyNode]
        /// Kanten des Layers, deren source UND target beide aktiv sind.
        let edges:   [HarmonyEdge]
    }

    let map:             HarmonyMap
    let activeLayer:     String
    let graphEngine:      HarmonyGraphEngine
    let runtimeHarmonik:  RuntimeHarmonik
    let snapshot:         Snapshot
    /// Validator-Warnings der Map (nie Errors — die scheitern die Konstruktion).
    /// Dürfen vom Aufrufer geloggt/angezeigt werden, blockieren nichts.
    let warnings:         [HarmonyMapValidator.Issue]

    /// - Parameters:
    ///   - map: Bereits geparste HarmonyMap. Wird hier erneut validiert (günstig,
    ///     kein I/O) — WorldSession erzwingt ihre eigene Invariante unabhängig
    ///     davon, ob der Aufrufer schon validiert hat (u. a. für direkte Tests
    ///     mit handgebauten Maps ohne Umweg über den Loader).
    ///   - activeLayer: Layer-ID, muss in `map.layers` existieren und dort
    ///     mindestens einen aktiven Node ergeben.
    ///   - seed: Optionaler Seed für die GraphEngine (deterministischer Betrieb,
    ///     siehe `HarmonyGraphEngine`). `nil` = zeitbasiert.
    init(map: HarmonyMap, activeLayer: String, seed: UInt64? = nil) throws {
        let validation = HarmonyMapValidator.validate(map)
        guard validation.errors.isEmpty else {
            throw WorldSessionError.invalidMap(errorDescriptions: validation.errors.map(\.description))
        }
        guard map.layers.contains(where: { $0.id == activeLayer }) else {
            throw WorldSessionError.unknownLayer(activeLayer)
        }

        let activeIDs = map.activeNodeIDs(in: activeLayer)
        guard !activeIDs.isEmpty else {
            throw WorldSessionError.emptyLayerView(activeLayer)
        }

        let nodes = map.nodes.filter { activeIDs.contains($0.id) }
        let edges = map.edges.filter {
            $0.layers.contains(activeLayer) && activeIDs.contains($0.source) && activeIDs.contains($0.target)
        }

        self.map         = map
        self.activeLayer = activeLayer
        self.snapshot     = Snapshot(nodeIDs: nodes.map(\.id), nodes: nodes, edges: edges)
        self.warnings     = validation.warnings

        let engine = HarmonyGraphEngine(map: map, initialLayer: activeLayer, seed: seed)
        self.graphEngine     = engine
        self.runtimeHarmonik = RuntimeHarmonik(graphEngine: engine)
    }
}

// MARK: – Bundle-Factory

extension WorldSession {

    /// Lädt + validiert eine HarmonyMap aus dem `HarmonyShared`-Bundle und baut
    /// direkt eine WorldSession darauf auf. Nutzt `HarmonyMapCodec`/
    /// `HarmonyMapValidator` direkt statt `HarmonyMapLoader.load(named:)` —
    /// vermeidet doppelte Validierungslogik (der Loader validiert bereits
    /// intern, `WorldSession.init` validiert ebenfalls; über den Codec direkt
    /// gibt es nur einen Validierungsdurchlauf statt zwei).
    static func load(
        named filename: String,
        activeLayer: String,
        bundle: Bundle? = nil,
        seed: UInt64? = nil
    ) throws -> WorldSession {
        let map = try HarmonyMapCodec.decode(fromBundleResource: filename, bundle: bundle)
        return try WorldSession(map: map, activeLayer: activeLayer, seed: seed)
    }
}
