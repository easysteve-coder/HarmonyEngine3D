import XCTest
@testable import HarmonyAuthoring
import HarmonyShared

final class NodeAuthoringCommandsTests: XCTestCase {

    // MARK: – Fixture

    private func makeMap() -> HarmonyMap {
        let nodeA = HarmonyNode(id: "n1", root: 0, type: .maj7, function: .tonic, midiNotes: [60, 64, 67, 71])
        let nodeB = HarmonyNode(id: "n2", root: 5, type: .dom7, function: .dominant, midiNotes: [65, 69, 72, 75])
        let edge  = HarmonyEdge(id: "e1", source: "n1", target: "n2", relationTypes: [.vToI], directed: true, layers: ["l1"])
        let layer = HarmonyLayer(id: "l1", name: "Layer 1", relationTypes: [.vToI])
        return HarmonyMap(
            schemaVersion: "1.0", id: "test-map", name: "Test", layers: [layer],
            nodes: [nodeA, nodeB], edges: [edge]
        )
    }

    // MARK: – AuthoringIDGenerator

    func test_nodeIDGenerator_returnsBase_whenFree() {
        XCTAssertEqual(AuthoringIDGenerator.freeID(base: "n3", existingIDs: ["n1", "n2"]), "n3")
    }

    func test_nodeIDGenerator_incrementsSuffix_untilFree() {
        XCTAssertEqual(AuthoringIDGenerator.freeID(base: "n1", existingIDs: ["n1", "n1-2"]), "n1-3")
    }

    // MARK: – AddNodeCommand

    func test_addNode_success_appendsNode() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        let newNode = HarmonyNode(id: "n3", root: 2, type: .min, function: .subdominant, midiNotes: [62])
        try doc.perform(AddNodeCommand(node: newNode))
        XCTAssertEqual(doc.draft.nodes.map(\.id), ["n1", "n2", "n3"])
        XCTAssertTrue(doc.isDirty)
    }

    func test_addNode_duplicateID_throwsAndLeavesDraftUnchanged() {
        var doc = HarmonyMapDocument(map: makeMap())
        let dup = HarmonyNode(id: "n1", root: 0, type: .maj, function: .tonic, midiNotes: [60])
        XCTAssertThrowsError(try doc.perform(AddNodeCommand(node: dup))) { error in
            guard case AddNodeCommand.CommandError.duplicateID("n1") = error else {
                return XCTFail("Erwartete .duplicateID, bekam \(error)")
            }
        }
        XCTAssertEqual(doc.draft.nodes.count, 2)
        XCTAssertFalse(doc.isDirty)
        XCTAssertEqual(doc.revision, 0)
    }

    func test_addNode_emptyID_throws() {
        var doc = HarmonyMapDocument(map: makeMap())
        let node = HarmonyNode(id: "", root: 0, type: .maj, function: .tonic, midiNotes: [60])
        XCTAssertThrowsError(try doc.perform(AddNodeCommand(node: node))) { error in
            guard case AddNodeCommand.CommandError.emptyID = error else {
                return XCTFail("Erwartete .emptyID, bekam \(error)")
            }
        }
    }

    // MARK: – DuplicateNodeCommand

    func test_duplicateNode_generatesFreeID_andCopiesFields() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(DuplicateNodeCommand(sourceNodeID: "n1"))
        guard let copy = doc.draft.nodes.first(where: { $0.id == "n1-copy" }) else {
            return XCTFail("Erwartete Kopie 'n1-copy'")
        }
        XCTAssertEqual(copy.root, 0)
        XCTAssertEqual(copy.type, .maj7)
        XCTAssertEqual(copy.function, .tonic)
        XCTAssertEqual(copy.midiNotes, [60, 64, 67, 71])
        XCTAssertEqual(doc.draft.edges.count, 1, "Duplicate darf keine Edges erzeugen")
    }

    func test_duplicateNode_secondDuplicate_getsCopy2Suffix() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(DuplicateNodeCommand(sourceNodeID: "n1"))
        try doc.perform(DuplicateNodeCommand(sourceNodeID: "n1"))
        XCTAssertTrue(doc.draft.nodes.contains { $0.id == "n1-copy" })
        XCTAssertTrue(doc.draft.nodes.contains { $0.id == "n1-copy-2" })
    }

    func test_duplicateNode_unknownSource_throws() {
        var doc = HarmonyMapDocument(map: makeMap())
        XCTAssertThrowsError(try doc.perform(DuplicateNodeCommand(sourceNodeID: "does-not-exist")))
    }

    // MARK: – RenameNodeCommand

    func test_renameNode_updatesAllEdgeReferencesAtomically() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(RenameNodeCommand(nodeID: "n1", newID: "renamed"))

        XCTAssertFalse(doc.draft.nodes.contains { $0.id == "n1" })
        XCTAssertTrue(doc.draft.nodes.contains { $0.id == "renamed" })
        let edge = doc.draft.edges.first { $0.id == "e1" }
        XCTAssertEqual(edge?.source, "renamed", "Edge-source-Referenz muss atomar mitaktualisiert werden")
        XCTAssertEqual(edge?.target, "n2")
    }

    func test_renameNode_targetSideReference_alsoUpdated() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(RenameNodeCommand(nodeID: "n2", newID: "renamed-target"))
        let edge = doc.draft.edges.first { $0.id == "e1" }
        XCTAssertEqual(edge?.source, "n1")
        XCTAssertEqual(edge?.target, "renamed-target")
    }

    func test_renameNode_toSameID_isDeterministicNoOpSuccess() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(RenameNodeCommand(nodeID: "n1", newID: "n1"))
        XCTAssertEqual(doc.draft.nodes.map(\.id), ["n1", "n2"])
    }

    func test_renameNode_unknownOldID_throwsAndLeavesDraftUnchanged() {
        var doc = HarmonyMapDocument(map: makeMap())
        XCTAssertThrowsError(try doc.perform(RenameNodeCommand(nodeID: "does-not-exist", newID: "x"))) { error in
            guard case RenameNodeCommand.CommandError.nodeNotFound = error else {
                return XCTFail("Erwartete .nodeNotFound, bekam \(error)")
            }
        }
        XCTAssertFalse(doc.isDirty)
        XCTAssertEqual(doc.revision, 0)
    }

    func test_renameNode_emptyNewID_throws() {
        var doc = HarmonyMapDocument(map: makeMap())
        XCTAssertThrowsError(try doc.perform(RenameNodeCommand(nodeID: "n1", newID: ""))) { error in
            guard case RenameNodeCommand.CommandError.emptyNewID = error else {
                return XCTFail("Erwartete .emptyNewID, bekam \(error)")
            }
        }
    }

    func test_renameNode_duplicateNewID_throws() {
        var doc = HarmonyMapDocument(map: makeMap())
        XCTAssertThrowsError(try doc.perform(RenameNodeCommand(nodeID: "n1", newID: "n2"))) { error in
            guard case RenameNodeCommand.CommandError.duplicateID("n2") = error else {
                return XCTFail("Erwartete .duplicateID, bekam \(error)")
            }
        }
    }

    // MARK: – DeleteNodeCommand

    func test_deleteNode_removesNodeAndIncidentEdges() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(DeleteNodeCommand(nodeID: "n1"))
        XCTAssertFalse(doc.draft.nodes.contains { $0.id == "n1" })
        XCTAssertTrue(doc.draft.edges.isEmpty, "Delete muss inzidente Edges mitentfernen — keine dangling Referenzen")
    }

    func test_deleteNode_leavesUnrelatedEdgesUntouched() throws {
        let nodeC = HarmonyNode(id: "n3", root: 2, type: .min, function: .subdominant, midiNotes: [62, 65, 69])
        let unrelatedEdge = HarmonyEdge(id: "e2", source: "n2", target: "n3", relationTypes: [.commonTone], directed: false, layers: [])
        var map = makeMap()
        map = HarmonyMap(
            schemaVersion: map.schemaVersion, id: map.id, name: map.name, layers: map.layers,
            nodes: map.nodes + [nodeC], edges: map.edges + [unrelatedEdge]
        )
        var doc = HarmonyMapDocument(map: map)

        try doc.perform(DeleteNodeCommand(nodeID: "n1"))

        XCTAssertTrue(doc.draft.edges.contains { $0.id == "e2" })
        XCTAssertFalse(doc.draft.edges.contains { $0.id == "e1" })
    }

    func test_deleteNode_unknownID_throws() {
        var doc = HarmonyMapDocument(map: makeMap())
        XCTAssertThrowsError(try doc.perform(DeleteNodeCommand(nodeID: "does-not-exist")))
    }

    // MARK: – UpdateNodeCommand

    func test_updateNode_setsAllFields() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(UpdateNodeCommand(
            nodeID: "n1", root: 7, type: .min, function: .subdominant, midiNotes: [67, 70, 74],
            tags: ["custom"], layers: ["l1"], layout3D: Layout3D(x: 1, y: 2, z: 3)
        ))
        let updated = doc.draft.nodes.first { $0.id == "n1" }
        XCTAssertEqual(updated?.root, 7)
        XCTAssertEqual(updated?.type, .min)
        XCTAssertEqual(updated?.function, .subdominant)
        XCTAssertEqual(updated?.midiNotes, [67, 70, 74])
        XCTAssertEqual(updated?.tags, ["custom"])
        XCTAssertEqual(updated?.layers, ["l1"])
        XCTAssertEqual(updated?.layout3D?.x, 1)
    }

    func test_updateNode_emptyMidiNotes_throws() {
        var doc = HarmonyMapDocument(map: makeMap())
        XCTAssertThrowsError(try doc.perform(UpdateNodeCommand(
            nodeID: "n1", root: 0, type: .maj7, function: .tonic, midiNotes: []
        ))) { error in
            guard case UpdateNodeCommand.CommandError.emptyMidiNotes = error else {
                return XCTFail("Erwartete .emptyMidiNotes, bekam \(error)")
            }
        }
    }

    func test_updateNode_midiNoteOutOfRange_throws() {
        var doc = HarmonyMapDocument(map: makeMap())
        XCTAssertThrowsError(try doc.perform(UpdateNodeCommand(
            nodeID: "n1", root: 0, type: .maj7, function: .tonic, midiNotes: [128]
        ))) { error in
            guard case UpdateNodeCommand.CommandError.midiNoteOutOfRange(128) = error else {
                return XCTFail("Erwartete .midiNoteOutOfRange(128), bekam \(error)")
            }
        }
    }

    func test_updateNode_unknownLayer_throws() {
        var doc = HarmonyMapDocument(map: makeMap())
        XCTAssertThrowsError(try doc.perform(UpdateNodeCommand(
            nodeID: "n1", root: 0, type: .maj7, function: .tonic, midiNotes: [60], layers: ["does-not-exist"]
        ))) { error in
            guard case UpdateNodeCommand.CommandError.unknownLayer("does-not-exist") = error else {
                return XCTFail("Erwartete .unknownLayer, bekam \(error)")
            }
        }
    }

    func test_updateNode_unknownNodeID_throws() {
        var doc = HarmonyMapDocument(map: makeMap())
        XCTAssertThrowsError(try doc.perform(UpdateNodeCommand(
            nodeID: "does-not-exist", root: 0, type: .maj7, function: .tonic, midiNotes: [60]
        )))
    }

    // MARK: – Undo/Redo

    func test_undoRedo_overRename_restoresDraftAndEdges() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(RenameNodeCommand(nodeID: "n1", newID: "renamed"))
        try doc.undo()

        XCTAssertTrue(doc.draft.nodes.contains { $0.id == "n1" })
        XCTAssertEqual(doc.draft.edges.first { $0.id == "e1" }?.source, "n1")

        try doc.redo()
        XCTAssertTrue(doc.draft.nodes.contains { $0.id == "renamed" })
        XCTAssertEqual(doc.draft.edges.first { $0.id == "e1" }?.source, "renamed")
    }

    func test_undoRedo_overDelete_restoresNodeAndIncidentEdges() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(DeleteNodeCommand(nodeID: "n1"))
        XCTAssertTrue(doc.draft.edges.isEmpty)

        try doc.undo()

        XCTAssertTrue(doc.draft.nodes.contains { $0.id == "n1" })
        XCTAssertEqual(doc.draft.edges.count, 1)
    }

    // MARK: – Live-Validation nach Mutation

    func test_deleteNode_leavesReferenceSafeState_diagnosticsAcceptable() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(DeleteNodeCommand(nodeID: "n1"))
        // n2 hat nach dem Delete keine Kante mehr -> globale Isolation -> Error erwartet,
        // das beweist, dass diagnostics nach der Mutation aktuell/aussagekraeftig bleibt.
        XCTAssertFalse(doc.diagnostics.isAcceptable)
        XCTAssertTrue(doc.diagnostics.errors.contains { $0.code == "nodeGloballyIsolated" })
    }

    func test_updateNode_toInvalidLayerReference_notPossible_butEmptyLayersAllowsDraftToStayValid() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(UpdateNodeCommand(
            nodeID: "n1", root: 0, type: .maj7, function: .tonic, midiNotes: [60], layers: nil
        ))
        XCTAssertTrue(doc.diagnostics.isAcceptable)
    }
}
