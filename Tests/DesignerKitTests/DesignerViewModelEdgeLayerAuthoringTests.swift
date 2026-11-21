import XCTest
@testable import DesignerKit
import HarmonyShared
import HarmonyAuthoring

// MARK: – Hinweis zu Nebeneffekten
//
// Siehe `DesignerViewModelWorkspaceTests.swift` — dieselbe bekannte,
// bewusst in Kauf genommene Application-Support-Sidecar-Nebenwirkung gilt
// auch hier.

@MainActor
final class DesignerViewModelEdgeLayerAuthoringTests: XCTestCase {

    private func makeDocumentViewModel() throws -> (vm: DesignerViewModel, tempURL: URL) {
        let nodeA = HarmonyNode(id: "n1", root: 0, type: .maj7, function: .tonic, midiNotes: [60, 64, 67, 71])
        let nodeB = HarmonyNode(id: "n2", root: 5, type: .dom7, function: .dominant, midiNotes: [65, 69, 72, 75])
        let nodeC = HarmonyNode(id: "n3", root: 2, type: .min, function: .subdominant, midiNotes: [62, 65, 69])
        let edge  = HarmonyEdge(id: "e1", source: "n1", target: "n2", relationTypes: [.vToI], directed: true, layers: [])
        let layer = HarmonyLayer(id: "l1", name: "Layer 1", relationTypes: [.vToI])
        let map   = HarmonyMap(schemaVersion: "1.0", id: "m-edge-layer", name: "Test", layers: [layer], nodes: [nodeA, nodeB, nodeC], edges: [edge])
        let url   = FileManager.default.temporaryDirectory
            .appendingPathComponent("designerkit-edge-layer-\(UUID().uuidString).json")
        try HarmonyMapCodec.encode(map).write(to: url)

        let vm = DesignerViewModel()
        vm.openHarmonyWebDocument(at: url, in: CGSize(width: 800, height: 600))
        return (vm, url)
    }

    // MARK: – Edge

    func test_addEdge_updatesDraftAndWebEdgesForDisplay() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.addEdge(from: "n2", to: "n3")

        XCTAssertEqual(vm.document?.draft.edges.count, 2)
        XCTAssertTrue(vm.webEdgesForDisplay.contains { $0.source == "n2" && $0.target == "n3" })
        XCTAssertEqual(vm.selectedDocumentEdgeID, "n2-n3")
        XCTAssertTrue(vm.document?.isDirty ?? false)
    }

    func test_deleteSelectedEdge_updatesDraftAndWebEdgesForDisplay_clearsSelection() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.selectDocumentEdge("e1")
        vm.deleteSelectedEdge()

        XCTAssertTrue(vm.document?.draft.edges.isEmpty ?? false)
        XCTAssertTrue(vm.webEdgesForDisplay.isEmpty)
        XCTAssertNil(vm.selectedDocumentEdgeID)
    }

    func test_updateSelectedEdge_updatesDraftAndWebEdgesForDisplay() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.selectDocumentEdge("e1")
        vm.updateSelectedEdge(
            source: "n1", target: "n2", directed: false, relationTypes: [.commonTone],
            layers: ["l1"], weight: 0.4, magnetProfile: MagnetProfile(preset: .strong), bridgesTo: nil
        )

        let updated = vm.document?.draft.edges.first { $0.id == "e1" }
        XCTAssertEqual(updated?.directed, false)
        XCTAssertEqual(updated?.weight, 0.4)
        XCTAssertEqual(updated?.magnetProfile?.preset, .strong)
        XCTAssertEqual(vm.webEdgesForDisplay.first { $0.id == "e1" }?.weight, 0.4)
    }

    // MARK: – Layer

    func test_addLayer_updatesDraftAndSelectsIt() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.addLayer(id: "l2", name: "Layer 2", relationTypes: [.commonTone])

        XCTAssertEqual(vm.document?.draft.layers.map(\.id), ["l1", "l2"])
        XCTAssertEqual(vm.selectedLayerID, "l2")
    }

    func test_renameLayer_migratesDraftAndActiveLayerAndSelection() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.activeLayer = "l1"
        vm.selectedLayerID = "l1"

        vm.updateLayer(layerID: "l1", newID: "renamed", name: "Renamed", relationTypes: [.vToI])

        XCTAssertEqual(vm.document?.draft.layers.map(\.id), ["renamed"])
        XCTAssertEqual(vm.activeLayer, "renamed", "Aktiver Layer (Workspace/UI-Zustand) muss bei Rename mitwandern")
        XCTAssertEqual(vm.selectedLayerID, "renamed")
        XCTAssertEqual(vm.workspace.activeLayer, "renamed", "Persistierter Workspace-Zustand muss ebenfalls mitwandern")
    }

    func test_deleteLayer_updatesDraftAndClearsSelection_fallsBackActiveLayer() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.addLayer(id: "l2", name: "Layer 2", relationTypes: [.commonTone])
        vm.activeLayer = "l1"
        vm.selectedLayerID = "l1"

        vm.deleteLayer("l1")

        XCTAssertEqual(vm.document?.draft.layers.map(\.id), ["l2"])
        XCTAssertNil(vm.selectedLayerID)
        XCTAssertEqual(vm.activeLayer, "l2", "Aktiver Layer muss auf einen verbleibenden Layer zurückfallen")
    }

    // MARK: – Layer-Solo/Overlay ist Workspace/UI-Zustand, keine Map-JSON-Erweiterung

    func test_activeLayer_isWorkspaceState_notPersistedInMapJSON() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.activeLayer = "l1"
        vm.persistActiveLayerIfDocumentMode()

        let mapData = try HarmonyMapCodec.encode(vm.document!.draft)
        let json = String(data: mapData, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("\"activeLayer\""), "activeLayer darf nicht in der Map-JSON landen")
        XCTAssertEqual(vm.workspace.activeLayer, "l1", "activeLayer lebt stattdessen im Workspace-Sidecar")
    }

    // MARK: – Undo/Redo

    func test_undoRedoDocument_afterAddEdge_updatesCanvasAndStatus() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.addEdge(from: "n2", to: "n3")
        XCTAssertEqual(vm.document?.draft.edges.count, 2)

        vm.undoDocument()
        XCTAssertEqual(vm.document?.draft.edges.count, 1)
        XCTAssertTrue(vm.canRedoDocument)

        vm.redoDocument()
        XCTAssertEqual(vm.document?.draft.edges.count, 2)
    }

    func test_undoRedoDocument_afterDeleteLayer_updatesCanvasAndDiagnostics() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.deleteLayer("l1")
        XCTAssertTrue(vm.document?.draft.layers.isEmpty ?? false)

        vm.undoDocument()
        XCTAssertEqual(vm.document?.draft.layers.map(\.id), ["l1"])

        vm.redoDocument()
        XCTAssertTrue(vm.document?.draft.layers.isEmpty ?? false)
    }
}
