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
final class DesignerViewModelIssueExportTests: XCTestCase {

    private func makeDocumentViewModel() throws -> (vm: DesignerViewModel, tempURL: URL) {
        let nodeA = HarmonyNode(id: "n1", root: 0, type: .maj7, function: .tonic, midiNotes: [60, 64, 67, 71])
        let nodeB = HarmonyNode(id: "n2", root: 5, type: .dom7, function: .dominant, midiNotes: [65, 69, 72, 75])
        let edge  = HarmonyEdge(id: "e1", source: "n1", target: "n2", relationTypes: [.vToI], directed: true, layers: ["l1"])
        let layer = HarmonyLayer(id: "l1", name: "Layer 1", relationTypes: [.vToI])
        let map   = HarmonyMap(schemaVersion: "1.0", id: "m-issue-export", name: "Test", layers: [layer], nodes: [nodeA, nodeB], edges: [edge])
        let url   = FileManager.default.temporaryDirectory
            .appendingPathComponent("designerkit-issue-export-\(UUID().uuidString).json")
        try HarmonyMapCodec.encode(map).write(to: url)

        let vm = DesignerViewModel()
        vm.openHarmonyWebDocument(at: url, in: CGSize(width: 800, height: 600))
        return (vm, url)
    }

    // MARK: – Issue-Fokus

    func test_focusIssue_nodeTarget_selectsNodeAndClearsOtherSelections() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.selectedDocumentEdgeID = "e1"
        vm.showLayerManager = true
        vm.showIssueNavigator = true

        let issue = HarmonyMapValidator.Issue(severity: .error, code: "test", objectPath: "$.nodes[n1]", message: "test")
        vm.focusIssue(issue)

        XCTAssertEqual(vm.selectedId, "n1")
        XCTAssertNil(vm.selectedDocumentEdgeID)
        XCTAssertFalse(vm.showLayerManager)
        XCTAssertFalse(vm.showIssueNavigator)
    }

    func test_focusIssue_edgeTarget_selectsEdgeAndClearsOtherSelections() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.selectedId = "n1"

        let issue = HarmonyMapValidator.Issue(severity: .warning, code: "test", objectPath: "$.edges[e1]", message: "test")
        vm.focusIssue(issue)

        XCTAssertEqual(vm.selectedDocumentEdgeID, "e1")
        XCTAssertNil(vm.selectedId)
    }

    func test_focusIssue_layerTarget_selectsLayerAndOpensManager() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        let issue = HarmonyMapValidator.Issue(severity: .error, code: "test", objectPath: "$.layers[l1]", message: "test")
        vm.focusIssue(issue)

        XCTAssertEqual(vm.selectedLayerID, "l1")
        XCTAssertTrue(vm.showLayerManager)
    }

    func test_focusIssue_globalTarget_doesNotChangeSelection() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.selectedId = "n1"
        let issue = HarmonyMapValidator.Issue(severity: .error, code: "test", objectPath: "$.schemaVersion", message: "test")
        vm.focusIssue(issue)

        XCTAssertEqual(vm.selectedId, "n1", "Globale Issues dürfen die bestehende Selektion nicht verändern")
    }

    func test_focusIssue_targetingDeletedObject_isNoOp_doesNotCrash() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        let issue = HarmonyMapValidator.Issue(severity: .error, code: "test", objectPath: "$.nodes[does-not-exist]", message: "test")
        vm.focusIssue(issue)

        XCTAssertNil(vm.selectedId, "Fokus auf ein nicht (mehr) existierendes Objekt bleibt No-op")
    }

    // MARK: – Export-Gate

    func test_exportGate_blocksErrors_allowsWarnings() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(vm.canExportToRuntime)
        XCTAssertNotNil(vm.exportValidatedMap())

        vm.selectedId = "n1"
        vm.deleteSelectedNode()
        // n2 ist danach isoliert -> Validator-Error erwartet.
        XCTAssertFalse(vm.canExportToRuntime)
        XCTAssertNil(vm.exportValidatedMap())
    }

    func test_exportGate_statusChangesAfterUndoRedo() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.selectedId = "n1"
        vm.deleteSelectedNode()
        XCTAssertFalse(vm.canExportToRuntime)

        vm.undoDocument()
        XCTAssertTrue(vm.canExportToRuntime, "Export-Gate-Status muss nach Undo aktuell sein")

        vm.redoDocument()
        XCTAssertFalse(vm.canExportToRuntime, "Export-Gate-Status muss nach Redo aktuell sein")
    }

    func test_exportDocumentAs_writesCanonicalMapCodecContent_whenValid() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        let exportURL = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: exportURL) }

        vm.exportDocumentAs(to: exportURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
        let exported = try HarmonyMapCodec.decode(from: exportURL)
        XCTAssertEqual(exported.id, vm.document?.draft.id)
        XCTAssertEqual(exported.nodes.map(\.id), vm.document?.draft.nodes.map(\.id))
        XCTAssertNil(vm.documentErrorMessage)
    }

    func test_exportDocumentAs_blocksWithErrorMessage_whenInvalid() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.selectedId = "n1"
        vm.deleteSelectedNode()

        let exportURL = FileManager.default.temporaryDirectory.appendingPathComponent("blocked-\(UUID().uuidString).json")
        vm.exportDocumentAs(to: exportURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: exportURL.path), "Export darf bei Errors keine Datei schreiben")
        XCTAssertNotNil(vm.documentErrorMessage)
    }

    // MARK: – Draft-Save bleibt bei Errors erlaubt

    func test_saveDocument_isNotBlockedByValidatorErrors() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.selectedId = "n1"
        vm.deleteSelectedNode()
        XCTAssertFalse(vm.canExportToRuntime, "Vorbedingung: Draft ist jetzt invalide")

        vm.saveDocument()

        XCTAssertNil(vm.documentErrorMessage, "Draft-Save darf trotz Validator-Errors nicht fehlschlagen")
        let saved = try HarmonyMapCodec.decode(from: url)
        XCTAssertFalse(saved.nodes.contains { $0.id == "n1" })
    }
}
