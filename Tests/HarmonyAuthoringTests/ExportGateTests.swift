import XCTest
@testable import HarmonyAuthoring
import HarmonyShared

// MARK: – ExportGateTests
//
// Kanonischer Save-Reopen-/Export-Vertrag (K-06, Scope D): Draft-Save bleibt
// bei Validator-Errors erlaubt, Runtime-Export (`validatedSnapshot()`)
// blockiert Errors und erlaubt Warnings, Export nutzt denselben
// `HarmonyMapCodec`-Inhalt wie jeder andere Save-Pfad.

final class ExportGateTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HarmonyAuthoringExportGateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeValidMap(extraLayer: Bool = false) -> HarmonyMap {
        let nodeA = HarmonyNode(id: "n1", root: 0, type: .maj7, function: .tonic, midiNotes: [60, 64, 67, 71])
        let nodeB = HarmonyNode(id: "n2", root: 5, type: .dom7, function: .dominant, midiNotes: [65, 69, 72, 75])
        let edge  = HarmonyEdge(id: "e1", source: "n1", target: "n2", relationTypes: [.vToI], directed: true, layers: ["l1"])
        var layers = [HarmonyLayer(id: "l1", name: "Layer 1", relationTypes: [.vToI])]
        if extraLayer {
            layers.append(HarmonyLayer(id: "l2", name: "Layer 2", relationTypes: [.commonTone]))
        }
        return HarmonyMap(schemaVersion: "1.0", id: "export-gate-map", name: "Test", layers: layers, nodes: [nodeA, nodeB], edges: [edge])
    }

    // MARK: – Invalid Draft: Save-Reopen erlaubt, Export blockiert

    func test_invalidDraft_canBeSavedAndReopened_diagnosticsVisible_exportBlocked() throws {
        var doc = HarmonyMapDocument(map: makeValidMap())
        try doc.perform(DraftTransformCommand(label: "make-invalid") { map in
            HarmonyMap(schemaVersion: "0.9", id: map.id, name: map.name, layers: map.layers, nodes: map.nodes, edges: map.edges)
        })
        XCTAssertFalse(doc.diagnostics.isAcceptable)
        XCTAssertNil(doc.validatedSnapshot(), "Export-Gate muss bei Errors blockieren")

        let url = tempDir.appendingPathComponent("invalid.json")
        try HarmonyMapDocumentStore.saveAs(&doc, to: url)

        let reopened = try HarmonyMapDocumentStore.openDocument(at: url)
        XCTAssertFalse(reopened.diagnostics.isAcceptable, "Diagnostics müssen nach Reopen weiterhin sichtbar sein")
        XCTAssertNil(reopened.validatedSnapshot(), "Export bleibt nach Reopen für denselben invaliden Draft blockiert")
    }

    // MARK: – Valid Draft: Export erzeugt denselben semantischen Inhalt

    func test_validDraft_exportProducesSameSemanticContent_afterReopen() throws {
        let map = makeValidMap()
        let doc = HarmonyMapDocument(map: map)
        guard let validated = doc.validatedSnapshot() else {
            return XCTFail("Erwartete validen Export")
        }

        let url = tempDir.appendingPathComponent("exported.json")
        try HarmonyMapCodec.encode(validated.map).write(to: url, options: .atomic)
        let reopened = try HarmonyMapCodec.decode(from: url)

        XCTAssertEqual(reopened.id, map.id)
        XCTAssertEqual(reopened.name, map.name)
        XCTAssertEqual(reopened.nodes.map(\.id), map.nodes.map(\.id))
        XCTAssertEqual(reopened.edges.map(\.id), map.edges.map(\.id))
        XCTAssertEqual(reopened.layers.map(\.id), map.layers.map(\.id))
    }

    // MARK: – Warnings blockieren Export nicht

    func test_warningsOnly_doesNotBlockExport() {
        let doc = HarmonyMapDocument(map: makeValidMap(extraLayer: true))
        XCTAssertTrue(doc.diagnostics.errors.isEmpty)
        XCTAssertFalse(doc.diagnostics.warnings.isEmpty)
        XCTAssertNotNil(doc.validatedSnapshot(), "Warnings dürfen den Export nicht blockieren")
    }

    // MARK: – Draft-Save bleibt bei Errors erlaubt (kein Export-Gate-Leck in Save)

    func test_draftSave_isNotGatedByValidator_evenWithErrors() throws {
        var doc = HarmonyMapDocument(map: makeValidMap())
        try doc.perform(DraftTransformCommand(label: "make-invalid") { map in
            HarmonyMap(schemaVersion: "0.9", id: map.id, name: map.name, layers: map.layers, nodes: map.nodes, edges: map.edges)
        })
        let url = tempDir.appendingPathComponent("still-saveable.json")
        // Wirft NICHT, obwohl diagnostics Errors enthält — Draft-Save ist vom Export-Gate getrennt.
        XCTAssertNoThrow(try HarmonyMapDocumentStore.saveAs(&doc, to: url))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
