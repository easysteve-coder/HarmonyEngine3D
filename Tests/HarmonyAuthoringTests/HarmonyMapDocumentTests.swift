import XCTest
@testable import HarmonyAuthoring
import HarmonyShared

final class HarmonyMapDocumentTests: XCTestCase {

    // MARK: – Fixture

    /// Baut eine gueltige Minimal-Map ausschliesslich ueber die neuen public
    /// HarmonyShared-Factories (beweist Scope-E-Punkt: Factories sind aus
    /// HarmonyAuthoringTests nutzbar). `extraLayer: true` erzeugt eine
    /// zusaetzliche, ungenutzte Layer → Warning ohne Error (layerEmpty).
    private func makeValidMap(name: String = "Test Map", extraLayer: Bool = false) -> HarmonyMap {
        let nodeA = HarmonyNode(id: "n1", root: 0, type: .maj7, function: .tonic, midiNotes: [60, 64, 67, 71])
        let nodeB = HarmonyNode(id: "n2", root: 5, type: .dom7, function: .dominant, midiNotes: [65, 69, 72, 75])
        let edge = HarmonyEdge(
            id: "e1", source: "n1", target: "n2", relationTypes: [.vToI], directed: true, layers: ["l1"]
        )
        var layers = [HarmonyLayer(id: "l1", name: "Layer 1", relationTypes: [.vToI])]
        if extraLayer {
            layers.append(HarmonyLayer(id: "l2", name: "Layer 2", relationTypes: [.commonTone]))
        }
        return HarmonyMap(
            schemaVersion: "1.0", id: "test-map", name: name, layers: layers, nodes: [nodeA, nodeB], edges: [edge]
        )
    }

    // MARK: – Target-/Fixture-Smoke

    func test_harmonyAuthoringTarget_buildsAgainstHarmonyShared() {
        let map = makeValidMap()
        XCTAssertEqual(map.nodes.count, 2)
        XCTAssertTrue(HarmonyMapValidator.validate(map).isAcceptable)
    }

    // MARK: – Initialisierung

    func test_documentInit_fromValidMap_isNotDirty_revisionZero_noUndoRedo() {
        let doc = HarmonyMapDocument(map: makeValidMap())
        XCTAssertFalse(doc.isDirty)
        XCTAssertEqual(doc.revision, 0)
        XCTAssertFalse(doc.canUndo)
        XCTAssertFalse(doc.canRedo)
        XCTAssertTrue(doc.diagnostics.isAcceptable)
    }

    // MARK: – Commands

    func test_performCommand_mutatesDraft_setsDirty_incrementsRevision_updatesDiagnostics() throws {
        var doc = HarmonyMapDocument(map: makeValidMap())
        try doc.perform(SetMapNameCommand(name: "Renamed"))
        XCTAssertEqual(doc.draft.name, "Renamed")
        XCTAssertTrue(doc.isDirty)
        XCTAssertEqual(doc.revision, 1)
        XCTAssertTrue(doc.canUndo)
        XCTAssertFalse(doc.canRedo)
    }

    func test_draftTransformCommand_appliesGenericTransform() throws {
        var doc = HarmonyMapDocument(map: makeValidMap())
        try doc.perform(DraftTransformCommand(label: "rename-via-transform") { map in
            HarmonyMap(
                schemaVersion: map.schemaVersion, id: map.id, name: "Transformed",
                layers: map.layers, nodes: map.nodes, edges: map.edges
            )
        })
        XCTAssertEqual(doc.draft.name, "Transformed")
        XCTAssertEqual(doc.revision, 1)
        XCTAssertTrue(doc.isDirty)
    }

    func test_failedCommand_leavesDraftDirtyRevisionStacksUnchanged() {
        var doc = HarmonyMapDocument(map: makeValidMap())
        let nameBefore = doc.draft.name

        XCTAssertThrowsError(try doc.perform(SetMapNameCommand(name: "   "))) { error in
            XCTAssertTrue(error is SetMapNameCommand.CommandError)
        }

        XCTAssertEqual(doc.draft.name, nameBefore)
        XCTAssertFalse(doc.isDirty)
        XCTAssertEqual(doc.revision, 0)
        XCTAssertFalse(doc.canUndo)
        XCTAssertFalse(doc.canRedo)
    }

    // MARK: – Undo / Redo

    func test_undo_restoresPreviousDraft_makesRedoAvailable() throws {
        var doc = HarmonyMapDocument(map: makeValidMap(name: "Original"))
        try doc.perform(SetMapNameCommand(name: "Renamed"))

        try doc.undo()

        XCTAssertEqual(doc.draft.name, "Original")
        XCTAssertTrue(doc.canRedo)
        XCTAssertFalse(doc.canUndo)
        XCTAssertEqual(doc.revision, 2)
    }

    func test_redo_restoresCommandChange() throws {
        var doc = HarmonyMapDocument(map: makeValidMap(name: "Original"))
        try doc.perform(SetMapNameCommand(name: "Renamed"))
        try doc.undo()

        try doc.redo()

        XCTAssertEqual(doc.draft.name, "Renamed")
        XCTAssertTrue(doc.canUndo)
        XCTAssertFalse(doc.canRedo)
        XCTAssertEqual(doc.revision, 3)
    }

    func test_newCommandAfterUndo_clearsRedoStack() throws {
        var doc = HarmonyMapDocument(map: makeValidMap(name: "Original"))
        try doc.perform(SetMapNameCommand(name: "Renamed"))
        try doc.undo()
        XCTAssertTrue(doc.canRedo)

        try doc.perform(SetMapNameCommand(name: "Third"))

        XCTAssertFalse(doc.canRedo)
        XCTAssertEqual(doc.draft.name, "Third")
    }

    func test_undo_onEmptyStack_throwsNothingToUndo() {
        var doc = HarmonyMapDocument(map: makeValidMap())
        XCTAssertThrowsError(try doc.undo()) { error in
            XCTAssertEqual(error as? HarmonyMapDocument.UndoRedoError, .nothingToUndo)
        }
    }

    func test_redo_onEmptyStack_throwsNothingToRedo() {
        var doc = HarmonyMapDocument(map: makeValidMap())
        XCTAssertThrowsError(try doc.redo()) { error in
            XCTAssertEqual(error as? HarmonyMapDocument.UndoRedoError, .nothingToRedo)
        }
    }

    // MARK: – Validierter Snapshot

    func test_invalidDraft_canBeHeld_butValidatedSnapshotReturnsNil() throws {
        var doc = HarmonyMapDocument(map: makeValidMap())

        try doc.perform(DraftTransformCommand(label: "clear-nodes") { map in
            HarmonyMap(
                schemaVersion: map.schemaVersion, id: map.id, name: map.name,
                layers: map.layers, nodes: [], edges: map.edges
            )
        })

        XCTAssertFalse(doc.diagnostics.isAcceptable)
        XCTAssertFalse(doc.diagnostics.errors.isEmpty)
        XCTAssertNil(doc.validatedSnapshot())
    }

    func test_warningsDoNotBlockValidatedSnapshot() {
        let doc = HarmonyMapDocument(map: makeValidMap(extraLayer: true))
        XCTAssertTrue(doc.diagnostics.errors.isEmpty)
        XCTAssertFalse(doc.diagnostics.warnings.isEmpty)
        XCTAssertNotNil(doc.validatedSnapshot())
    }

    func test_validatedSnapshot_roundtripsThroughCodec() throws {
        let doc = HarmonyMapDocument(map: makeValidMap())
        guard let validated = doc.validatedSnapshot() else {
            return XCTFail("Erwartete gueltigen validierten Snapshot")
        }

        let data = try HarmonyMapCodec.encode(validated.map)
        let decoded = try HarmonyMapCodec.decode(from: data)

        XCTAssertEqual(decoded.id, validated.map.id)
        XCTAssertEqual(decoded.name, validated.map.name)
        XCTAssertEqual(decoded.nodes.map(\.id), validated.map.nodes.map(\.id))
        XCTAssertEqual(decoded.edges.map(\.id), validated.map.edges.map(\.id))
        XCTAssertEqual(decoded.layers.map(\.id), validated.map.layers.map(\.id))
    }
}
