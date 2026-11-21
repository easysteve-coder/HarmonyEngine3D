import Foundation

// MARK: – WorkspacePoint
//
// UI-Framework-freier 2D-Punkt (kein CGPoint) — HarmonyAuthoring bleibt
// plattformfrei, DesignerKit konvertiert an der Grenze zu/von CGPoint.

public struct WorkspacePoint: Codable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

// MARK: – HarmonyMapWorkspaceState
//
// 2D-Editorzustand fuer ein HarmonyWeb-Dokument (K-03): Node-Positionen,
// Pin-Status, Zoom und optional aktiver Layer. Lebt vollstaendig getrennt
// von `HarmonyMap`/`HarmonyMapDocument` — wird NIE in die Map-JSON
// geschrieben, nur als eigener Sidecar (siehe `HarmonyMapWorkspaceStore`).
// `HarmonyMapDocument.isDirty` beschreibt ausschliesslich Map-Draft-
// Mutationen; Workspace-Aenderungen haben darauf keinen Einfluss.

public struct HarmonyMapWorkspaceState: Codable, Equatable {
    public static let currentVersion = 1

    public var version:        Int
    public var positions:      [String: WorkspacePoint]
    public var pinnedNodeIDs:  Set<String>
    public var zoom:           Double
    public var activeLayer:    String?

    public init(
        version: Int = HarmonyMapWorkspaceState.currentVersion,
        positions: [String: WorkspacePoint] = [:],
        pinnedNodeIDs: Set<String> = [],
        zoom: Double = 1.0,
        activeLayer: String? = nil
    ) {
        self.version = version
        self.positions = positions
        self.pinnedNodeIDs = pinnedNodeIDs
        self.zoom = zoom
        self.activeLayer = activeLayer
    }

    public func position(forNodeID id: String) -> WorkspacePoint? { positions[id] }
    public func isPinned(_ id: String) -> Bool { pinnedNodeIDs.contains(id) }

    public mutating func setPosition(_ point: WorkspacePoint, forNodeID id: String) {
        positions[id] = point
    }

    public mutating func togglePin(_ id: String) {
        if pinnedNodeIDs.contains(id) {
            pinnedNodeIDs.remove(id)
        } else {
            pinnedNodeIDs.insert(id)
        }
    }
}
