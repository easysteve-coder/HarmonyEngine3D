import XCTest
@testable import DesignerKit
import HarmonyShared
import HarmonyAuthoring

// MARK: – Hinweis zu Nebeneffekten
//
// Siehe `DesignerViewModelWorkspaceTests.swift` — dieselbe bekannte,
// bewusst in Kauf genommene Application-Support-Sidecar-Nebenwirkung gilt
// auch hier (kein Directory-Injection-Pfad im ViewModel).

@MainActor
final class DesignerViewModelNodeAuthoringTests: XCTestCase {

    private func makeDocumentViewModel() throws -> (vm: DesignerViewModel, tempURL: URL) {
        let nodeA = HarmonyNode(id: "n1", root: 0, type: .maj7, function: .tonic, midiNotes: [60, 64, 67, 71])
        let nodeB = HarmonyNode(id: "n2", root: 5, type: .dom7, function: .dominant, midiNotes: [65, 69, 72, 75])
        let edge  = HarmonyEdge(id: "e1", source: "n1", target: "n2", relationTypes: [.vToI], directed: true, layers: [])
        let map   = HarmonyMap(schemaVersion: "1.0", id: "m-node-auth", name: "Test", layers: [], nodes: [nodeA, nodeB], edges: [edge])
        let url   = FileManager.default.temporaryDirectory
            .appendingPathComponent("designerkit-node-authoring-\(UUID().uuidString).json")
        try HarmonyMapCodec.encode(map).write(to: url)

        let vm = DesignerViewModel()
        vm.openHarmonyWebDocument(at: url, in: CGSize(width: 800, height: 600))
        return (vm, url)
    }

    // MARK: – Add

    func test_addNode_appendsToDraftAndCanvas_andSelectsIt() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.addNode()

        XCTAssertEqual(vm.document?.draft.nodes.count, 3)
        XCTAssertEqual(vm.nodes.count, 3)
        XCTAssertNotNil(vm.selectedId)
        XCTAssertTrue(vm.document?.draft.nodes.contains { $0.id == vm.selectedId } ?? false)
        XCTAssertTrue(vm.document?.isDirty ?? false)
    }

    // MARK: – Duplicate

    func test_duplicateNode_appendsCopyToDraftAndCanvas_placedNearSource() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.selectedId = "n1"
        let sourcePosition = vm.nodes.first { $0.id == "n1" }!.position

        vm.duplicateSelectedNode()

        XCTAssertEqual(vm.selectedId, "n1-copy")
        XCTAssertTrue(vm.document?.draft.nodes.contains { $0.id == "n1-copy" } ?? false)
        guard let copyPosition = vm.nodes.first(where: { $0.id == "n1-copy" })?.position else {
            return XCTFail("Erwartete Canvas-Node für die Kopie")
        }
        XCTAssertNotEqual(copyPosition, sourcePosition, "Kopie soll versetzt platziert werden, nicht exakt auf dem Original")
    }

    // MARK: – Rename

    func test_renameNode_migratesWorkspacePositionPinAndSelection() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.selectedId = "n1"
        vm.togglePin("n1")
        let originalPosition = vm.nodes.first { $0.id == "n1" }!.position

        vm.renameSelectedNode(to: "renamed")

        XCTAssertEqual(vm.selectedId, "renamed")
        XCTAssertTrue(vm.isPinned("renamed"))
        XCTAssertFalse(vm.isPinned("n1"))
        XCTAssertEqual(vm.nodes.first { $0.id == "renamed" }?.position, originalPosition)
        XCTAssertFalse(vm.nodes.contains { $0.id == "n1" })
        XCTAssertEqual(vm.document?.draft.edges.first { $0.id == "e1" }?.source, "renamed",
                        "Edge-Referenz muss über die ViewModel-Aktion hinweg mitwandern")
    }

    // MARK: – Delete

    func test_deleteNode_removesFromCanvasAndWorkspace_clearsSelection_removesIncidentEdges() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.selectedId = "n1"
        vm.togglePin("n1")

        vm.deleteSelectedNode()

        XCTAssertFalse(vm.nodes.contains { $0.id == "n1" })
        XCTAssertNil(vm.selectedId)
        XCTAssertFalse(vm.isPinned("n1"))
        XCTAssertTrue(vm.document?.draft.edges.isEmpty ?? false, "Inzidente Edge muss mitentfernt werden")
    }

    // MARK: – Update / Inspector

    func test_updateSelectedNode_mutatesDraftViaCommand_setsDirty() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.selectedId = "n1"
        vm.updateSelectedNode(root: 7, type: .min, function: .subdominant, midiNotes: [67, 70, 74], tags: ["x"], layers: nil, layout3D: nil)

        let updated = vm.document?.draft.nodes.first { $0.id == "n1" }
        XCTAssertEqual(updated?.root, 7)
        XCTAssertEqual(updated?.type, .min)
        XCTAssertEqual(updated?.midiNotes, [67, 70, 74])
        XCTAssertTrue(vm.document?.isDirty ?? false)
    }

    // MARK: – Undo/Redo

    func test_undoRedoDocument_afterDelete_restoresCanvasAndDiagnostics() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.selectedId = "n1"
        vm.deleteSelectedNode()
        XCTAssertFalse(vm.document?.diagnostics.isAcceptable ?? true, "n2 ist nach dem Delete isoliert — Error erwartet")

        vm.undoDocument()

        XCTAssertTrue(vm.nodes.contains { $0.id == "n1" })
        XCTAssertTrue(vm.document?.diagnostics.isAcceptable ?? false)

        vm.redoDocument()

        XCTAssertFalse(vm.nodes.contains { $0.id == "n1" })
        XCTAssertFalse(vm.document?.diagnostics.isAcceptable ?? true)
    }
}
