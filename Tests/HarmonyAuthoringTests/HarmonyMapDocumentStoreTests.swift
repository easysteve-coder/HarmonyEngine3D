import XCTest
@testable import HarmonyAuthoring
import HarmonyShared

final class HarmonyMapDocumentStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HarmonyAuthoringTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeValidMap(name: String = "Roundtrip Map") -> HarmonyMap {
        let nodeA = HarmonyNode(id: "n1", root: 0, type: .maj7, function: .tonic, midiNotes: [60, 64, 67, 71])
        let nodeB = HarmonyNode(id: "n2", root: 5, type: .dom7, function: .dominant, midiNotes: [65, 69, 72, 75])
        let edge = HarmonyEdge(
            id: "e1", source: "n1", target: "n2", relationTypes: [.vToI], directed: true, layers: ["l1"]
        )
        let layer = HarmonyLayer(id: "l1", name: "Layer 1", relationTypes: [.vToI])
        let layout = MapLayout(strategy: "manual")
        return HarmonyMap(
            schemaVersion: "1.0", id: "roundtrip-map", name: name, layers: [layer],
            nodes: [nodeA, nodeB], edges: [edge], layout: layout
        )
    }

    // MARK: – newDocument

    func test_newDocument_isUnsaved_notDirty_savableJSON() throws {
        let doc = HarmonyMapDocumentStore.newDocument()
        XCTAssertEqual(doc.origin, .unsaved)
        XCTAssertNil(doc.documentURL)
        XCTAssertFalse(doc.isDirty)
        XCTAssertFalse(doc.isReadOnly)
        XCTAssertNoThrow(try HarmonyMapCodec.encode(doc.draft))
    }

    func test_newDocument_generatesUniqueIDsPerCall() {
        let a = HarmonyMapDocumentStore.newDocument()
        let b = HarmonyMapDocumentStore.newDocument()
        XCTAssertNotEqual(a.draft.id, b.draft.id)
    }

    // MARK: – openDocument

    func test_openDocument_decodesExternalFile_setsFileOriginAndCleanDirty() throws {
        let url = tempDir.appendingPathComponent("external.json")
        let data = try HarmonyMapCodec.encode(makeValidMap())
        try data.write(to: url)

        let doc = try HarmonyMapDocumentStore.openDocument(at: url)

        XCTAssertEqual(doc.origin, .file(url))
        XCTAssertEqual(doc.documentURL, url)
        XCTAssertFalse(doc.isDirty)
        XCTAssertFalse(doc.isReadOnly)
    }

    // MARK: – save / saveAs

    func test_saveAs_writesAtomically_setsURLAndClearsDirty() throws {
        var doc = HarmonyMapDocumentStore.newDocument()
        try doc.perform(SetMapNameCommand(name: "Renamed"))
        XCTAssertTrue(doc.isDirty)

        let url = tempDir.appendingPathComponent("saved-as.json")
        try HarmonyMapDocumentStore.saveAs(&doc, to: url)

        XCTAssertEqual(doc.origin, .file(url))
        XCTAssertFalse(doc.isDirty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func test_save_onNormalFileDocument_writesChangesAndClearsDirty() throws {
        let url = tempDir.appendingPathComponent("normal.json")
        var doc = HarmonyMapDocumentStore.newDocument()
        try HarmonyMapDocumentStore.saveAs(&doc, to: url)

        try doc.perform(SetMapNameCommand(name: "Changed"))
        XCTAssertTrue(doc.isDirty)

        try HarmonyMapDocumentStore.save(&doc)

        XCTAssertFalse(doc.isDirty)
        let reloaded = try HarmonyMapCodec.decode(from: url)
        XCTAssertEqual(reloaded.name, "Changed")
    }

    func test_save_onUnsavedDocument_throwsNoSaveTarget() {
        var doc = HarmonyMapDocumentStore.newDocument()
        XCTAssertThrowsError(try HarmonyMapDocumentStore.save(&doc)) { error in
            guard case HarmonyMapDocumentStore.StoreError.noSaveTarget = error else {
                return XCTFail("Erwartete .noSaveTarget, bekam \(error)")
            }
        }
    }

    // MARK: – Save-Reopen-Roundtrip

    func test_saveReopenRoundtrip_preservesIDNameNodesEdgesLayersLayout() throws {
        let map = makeValidMap()
        var doc = HarmonyMapDocument(map: map)
        let url = tempDir.appendingPathComponent("roundtrip.json")

        try HarmonyMapDocumentStore.saveAs(&doc, to: url)
        let reopened = try HarmonyMapDocumentStore.openDocument(at: url)

        XCTAssertEqual(reopened.draft.id, map.id)
        XCTAssertEqual(reopened.draft.name, map.name)
        XCTAssertEqual(reopened.draft.nodes.map(\.id), map.nodes.map(\.id))
        XCTAssertEqual(reopened.draft.edges.map(\.id), map.edges.map(\.id))
        XCTAssertEqual(reopened.draft.layers.map(\.id), map.layers.map(\.id))
        XCTAssertEqual(reopened.draft.layout?.strategy, map.layout?.strategy)
    }

    // MARK: – Invalider Draft bleibt speicher-/oeffenbar

    func test_invalidDraft_canBeSavedAndReopened_diagnosticsRemainVisible() throws {
        var doc = HarmonyMapDocumentStore.newDocument()
        try doc.perform(DraftTransformCommand(label: "make-invalid") { map in
            HarmonyMap(
                schemaVersion: "0.9", id: map.id, name: map.name,
                layers: map.layers, nodes: map.nodes, edges: map.edges
            )
        })
        XCTAssertFalse(doc.diagnostics.isAcceptable)

        let url = tempDir.appendingPathComponent("invalid.json")
        try HarmonyMapDocumentStore.saveAs(&doc, to: url)

        let reopened = try HarmonyMapDocumentStore.openDocument(at: url)
        XCTAssertFalse(reopened.diagnostics.isAcceptable)
        XCTAssertTrue(reopened.diagnostics.errors.contains { $0.code == "schemaVersionUnsupported" })
    }

    // MARK: – Bundle-Template read-only

    func test_openBundledTemplate_loadsReadOnly_saveThrows_saveAsCreatesNormalFile() throws {
        var doc = try HarmonyMapDocumentStore.openBundledTemplate(named: "authoring-template-fixture", bundle: .module)

        XCTAssertTrue(doc.isReadOnly)
        XCTAssertNil(doc.documentURL)

        XCTAssertThrowsError(try HarmonyMapDocumentStore.save(&doc)) { error in
            guard case HarmonyMapDocumentStore.StoreError.readOnlyTemplate = error else {
                return XCTFail("Erwartete .readOnlyTemplate, bekam \(error)")
            }
        }

        let url = tempDir.appendingPathComponent("from-template.json")
        try HarmonyMapDocumentStore.saveAs(&doc, to: url)

        XCTAssertFalse(doc.isReadOnly)
        XCTAssertEqual(doc.documentURL, url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
