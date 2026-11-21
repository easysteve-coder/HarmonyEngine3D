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
final class DesignerViewModelBuilderTests: XCTestCase {

    private func makeDocumentViewModel() throws -> (vm: DesignerViewModel, tempURL: URL) {
        let nodeA = HarmonyNode(id: "n1", root: 0, type: .maj7, function: .tonic, midiNotes: [60, 64, 67, 71])
        let nodeB = HarmonyNode(id: "n2", root: 5, type: .dom7, function: .dominant, midiNotes: [65, 69, 72, 75])
        let edge  = HarmonyEdge(id: "e1", source: "n1", target: "n2", relationTypes: [.vToI], directed: true, layers: ["l1"])
        let layer = HarmonyLayer(id: "l1", name: "Layer 1", relationTypes: [.vToI])
        let map = HarmonyMap(schemaVersion: "1.0", id: "m-builder", name: "Test", layers: [layer], nodes: [nodeA, nodeB], edges: [edge])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("designerkit-builder-\(UUID().uuidString).json")
        try HarmonyMapCodec.encode(map).write(to: url)

        let vm = DesignerViewModel()
        vm.openHarmonyWebDocument(at: url, in: CGSize(width: 800, height: 600))
        vm.activeLayer = "l1"
        return (vm, url)
    }

    // MARK: – Diff kann erzeugt werden

    func test_previewBuilderDiff_generatesSevenNodesAndSevenEdges() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.previewBuilderDiff()

        XCTAssertEqual(vm.builderDiff?.proposedNodes.count, 7)
        XCTAssertEqual(vm.builderDiff?.proposedEdges.count, 7)
    }

    func test_previewBuilderDiff_usesActiveLayer_whenItExistsInDocument() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.previewBuilderDiff()

        XCTAssertTrue(vm.builderDiff?.proposedEdges.allSatisfy { $0.edge.layers == ["l1"] } ?? false)
        XCTAssertTrue(vm.builderDiff?.warnings.isEmpty ?? false)
    }

    // MARK: – Apply mutiert Draft und Canvas konsistent

    func test_applyBuilderDiff_mutatesDraftAndCanvas_closesPanel() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }
        vm.showBuilderPanel = true

        vm.previewBuilderDiff()
        vm.applyBuilderDiff()

        XCTAssertEqual(vm.harmonyMap?.nodes.count, 9, "2 bestehende + 7 neue diatonische Stufen")
        XCTAssertEqual(vm.harmonyMap?.edges.count, 8, "1 bestehende + 7 neue Nachbarschafts-Kanten")
        XCTAssertTrue(vm.harmonyMap?.nodes.contains { $0.id == "C-I" } ?? false)
        // Canvas-Sync (LayoutNode-Array) muss mit dem Draft übereinstimmen.
        XCTAssertEqual(Set(vm.nodes.map(\.id)), Set(vm.harmonyMap?.nodes.map(\.id) ?? []))
        XCTAssertNil(vm.builderDiff, "Diff wird nach erfolgreichem Apply verworfen")
        XCTAssertFalse(vm.showBuilderPanel, "Panel schließt sich nach erfolgreichem Apply")
    }

    // MARK: – Cancel lässt Draft/Dirty-State unverändert

    func test_cancelBuilderDiff_leavesDraftAndDirtyStateUnchanged() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }
        let nodesBefore = vm.harmonyMap?.nodes.count
        let dirtyBefore = vm.document?.isDirty
        let revisionBefore = vm.document?.revision

        vm.previewBuilderDiff()
        XCTAssertNotNil(vm.builderDiff)
        vm.cancelBuilderDiff()

        XCTAssertNil(vm.builderDiff)
        XCTAssertEqual(vm.harmonyMap?.nodes.count, nodesBefore)
        XCTAssertEqual(vm.document?.isDirty, dirtyBefore)
        XCTAssertEqual(vm.document?.revision, revisionBefore)
    }

    // MARK: – Undo/Redo über ViewModel

    func test_undoRedoDocument_removesAndRestoresEntireBuilderApply() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }
        vm.previewBuilderDiff()
        vm.applyBuilderDiff()
        XCTAssertEqual(vm.harmonyMap?.nodes.count, 9)
        XCTAssertTrue(vm.canUndoDocument)

        vm.undoDocument()

        XCTAssertEqual(vm.harmonyMap?.nodes.count, 2, "Ein Undo entfernt den gesamten Builder-Apply, nicht Node für Node")
        XCTAssertEqual(vm.harmonyMap?.edges.count, 1)
        XCTAssertTrue(vm.canRedoDocument)

        vm.redoDocument()

        XCTAssertEqual(vm.harmonyMap?.nodes.count, 9)
        XCTAssertEqual(vm.harmonyMap?.edges.count, 8)
    }

    // MARK: – Issue-/Export-/Simulation-Status nach Apply konsistent

    func test_exportAndSimulationGates_stayConsistentAfterApply() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(vm.canExportToRuntime)
        XCTAssertTrue(vm.canRunSimulation)

        vm.previewBuilderDiff()
        vm.applyBuilderDiff()

        XCTAssertTrue(vm.document?.diagnostics.errors.isEmpty ?? false, "Builder-Apply darf keine Validator-Errors erzeugen")
        XCTAssertTrue(vm.canExportToRuntime, "Export-Gate muss nach einem sauberen Builder-Apply weiterhin offen sein")
        XCTAssertTrue(vm.canRunSimulation, "Simulation-Gate muss nach einem sauberen Builder-Apply weiterhin offen sein")
    }

    // MARK: – Runde 037 / V-00a: Builder blockiert statt toten Diff zu erzeugen (Builder-A1)

    func test_previewBuilderDiff_blockedWhenDocumentHasNoLayers() throws {
        let node = HarmonyNode(id: "n1", root: 0, type: .maj, function: .tonic, midiNotes: [60, 64, 67])
        let map = HarmonyMap(schemaVersion: "1.0", id: "m-no-layer", name: "Test", layers: [], nodes: [node], edges: [])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("designerkit-builder-nolayer-\(UUID().uuidString).json")
        try HarmonyMapCodec.encode(map).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let vm = DesignerViewModel()
        vm.openHarmonyWebDocument(at: url, in: CGSize(width: 800, height: 600))

        XCTAssertFalse(vm.canRunBuilder, "Ein Dokument ohne Layer darf den Builder nicht zulassen")

        vm.previewBuilderDiff()

        XCTAssertNil(vm.builderDiff, "Builder darf ohne Layer keinen (für die Runtime toten) Diff erzeugen")
        XCTAssertNotNil(vm.builderBlockedReason)
    }

    func test_previewBuilderDiff_fallsBackToFirstLayer_whenActiveLayerIsStale() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }
        vm.activeLayer = "does-not-exist-anymore"

        vm.previewBuilderDiff()

        XCTAssertNotNil(vm.builderDiff)
        XCTAssertNil(vm.builderBlockedReason)
        XCTAssertTrue(vm.builderDiff?.proposedEdges.allSatisfy { $0.edge.layers == ["l1"] } ?? false,
                      "Ein ungültiger activeLayer darf keinen layerlosen Diff erzeugen, solange das Dokument einen Layer besitzt")
    }

    // MARK: – Runde 037 / V-00a: Stale State bei Dokumentwechsel (Finding A4)

    func test_openingNewDocument_invalidatesStaleBuilderDiffAndClosesPanel() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }
        vm.showBuilderPanel = true
        vm.previewBuilderDiff()
        XCTAssertNotNil(vm.builderDiff)

        let node2 = HarmonyNode(id: "other", root: 2, type: .m7, function: .subdominant, midiNotes: [62, 65, 69, 72])
        let layer2 = HarmonyLayer(id: "l2", name: "Layer 2", relationTypes: [.commonTone])
        let map2 = HarmonyMap(schemaVersion: "1.0", id: "m-second", name: "Second", layers: [layer2], nodes: [node2], edges: [])
        let url2 = FileManager.default.temporaryDirectory
            .appendingPathComponent("designerkit-builder-second-\(UUID().uuidString).json")
        try HarmonyMapCodec.encode(map2).write(to: url2)
        defer { try? FileManager.default.removeItem(at: url2) }

        vm.openHarmonyWebDocument(at: url2, in: vm.canvasSize)

        XCTAssertNil(vm.builderDiff, "Ein Diff aus dem ersten Dokument darf im zweiten nicht anwendbar bleiben")
        XCTAssertFalse(vm.showBuilderPanel, "Builder-Panel darf nach Dokumentwechsel nicht offen bleiben")
        XCTAssertEqual(vm.harmonyMap?.id, "m-second")
    }

    func test_anyDraftMutation_invalidatesPreviewedBuilderDiff() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }
        vm.previewBuilderDiff()
        XCTAssertNotNil(vm.builderDiff)

        // Eine andere Node-Authoring-Aktion mutiert den Draft, während der
        // Builder-Diff noch als Vorschlag offen ist — der Diff bezieht sich
        // auf den ALTEN Draft-Stand und darf danach nicht mehr stehen
        // bleiben (Finding A4, Fable-5-Review Runde 036).
        vm.addNode()

        XCTAssertNil(vm.builderDiff, "Jede Draft-Mutation muss einen offenen Builder-Vorschlag invalidieren")
    }
}
