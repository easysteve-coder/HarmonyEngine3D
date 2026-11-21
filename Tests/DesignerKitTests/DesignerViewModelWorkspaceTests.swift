import XCTest
@testable import DesignerKit
import HarmonyShared
import HarmonyAuthoring

// MARK: – Hinweis zu Nebeneffekten
//
// `DesignerViewModel`s Workspace-/Dokument-Store-Aufrufe nutzen den
// Default-Pfad (Application Support), es gibt aktuell keine Dependency
// Injection dafür (anders als bei `RecentDocumentsStore`s injizierbaren
// `UserDefaults` aus K-02). Tests, die `applyDocument(_:in:)` durchlaufen,
// hinterlassen daher kleine, harmlose Sidecar-Dateien unter Tempfile-Pfad-
// Hashes im echten Application-Support-Verzeichnis. Das ist bewusst in Kauf
// genommen (kein Produktionsrisiko, keine Kollision mit echten Dokumenten)
// statt für K-03 zusätzlich eine Directory-Injection-Kette durch die gesamte
// ViewModel-API zu ziehen — siehe Ruecklauf-Begründung in latest_claude.md.

@MainActor
final class DesignerViewModelWorkspaceTests: XCTestCase {

    private func writeTempMap(_ map: HarmonyMap) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("designerkit-test-\(UUID().uuidString).json")
        try HarmonyMapCodec.encode(map).write(to: url)
        return url
    }

    func test_newHarmonyWebDocument_entersHarmonyWebMode_notReadOnly() {
        let vm = DesignerViewModel()
        vm.newHarmonyWebDocument(in: CGSize(width: 800, height: 600))
        XCTAssertTrue(vm.harmonyWebMode)
        XCTAssertFalse(vm.documentIsReadOnly)
        XCTAssertFalse(vm.canSaveDocument)
    }

    func test_moveNode_inDocumentMode_pinsNodeAndUpdatesWorkspace_notDraft() throws {
        let node = HarmonyNode(id: "n1", root: 0, type: .maj7, function: .tonic, midiNotes: [60, 64, 67, 71])
        let map  = HarmonyMap(schemaVersion: "1.0", id: "m1", name: "Test", layers: [], nodes: [node], edges: [])
        let url  = try writeTempMap(map)
        defer { try? FileManager.default.removeItem(at: url) }

        let vm = DesignerViewModel()
        vm.openHarmonyWebDocument(at: url, in: CGSize(width: 800, height: 600))
        XCTAssertTrue(vm.harmonyWebMode)
        let draftNodeCountBefore = vm.document?.draft.nodes.count

        vm.moveNode(id: "n1", by: CGPoint(x: 10, y: 10))

        XCTAssertTrue(vm.isPinned("n1"))
        XCTAssertEqual(vm.document?.draft.nodes.count, draftNodeCountBefore, "moveNode darf document.draft nicht verändern")
        XCTAssertFalse(vm.document?.isDirty ?? true, "Workspace-Drag darf das Dokument nicht dirty machen")
    }

    func test_webDocumentMode_doesNotPopulateLegacyEdgeDataArray() throws {
        let nodeA = HarmonyNode(id: "n1", root: 0, type: .maj7, function: .tonic, midiNotes: [60, 64, 67, 71])
        let nodeB = HarmonyNode(id: "n2", root: 5, type: .dom7, function: .dominant, midiNotes: [65, 69, 72, 75])
        let edge  = HarmonyEdge(id: "e1", source: "n1", target: "n2", relationTypes: [.vToI], directed: true, layers: [])
        let map   = HarmonyMap(schemaVersion: "1.0", id: "m2", name: "Test", layers: [], nodes: [nodeA, nodeB], edges: [edge])
        let url   = try writeTempMap(map)
        defer { try? FileManager.default.removeItem(at: url) }

        let vm = DesignerViewModel()
        vm.openHarmonyWebDocument(at: url, in: CGSize(width: 800, height: 600))

        XCTAssertTrue(vm.edges.isEmpty, "Dokumentmodus darf keine EdgeData-Schattenkopie führen")
        XCTAssertEqual(vm.webEdgesForDisplay.count, 1)
    }

    func test_relayoutDocumentCanvas_preservesDocumentOrigin_doesNotReplaceWithTemplate() throws {
        let node = HarmonyNode(id: "n1", root: 0, type: .maj7, function: .tonic, midiNotes: [60, 64, 67, 71])
        let map  = HarmonyMap(schemaVersion: "1.0", id: "m3", name: "Test", layers: [], nodes: [node], edges: [])
        let url  = try writeTempMap(map)
        defer { try? FileManager.default.removeItem(at: url) }

        let vm = DesignerViewModel()
        vm.openHarmonyWebDocument(at: url, in: CGSize(width: 800, height: 600))
        XCTAssertEqual(vm.document?.documentURL, url)

        vm.relayoutDocumentCanvas(in: CGSize(width: 1000, height: 700))

        XCTAssertEqual(vm.document?.documentURL, url, "Resize darf das externe Dokument nicht durch ein Bundle-Template ersetzen")
    }
}
