import XCTest
@testable import HarmonyAuthoring
import HarmonyShared

final class EdgeAuthoringCommandsTests: XCTestCase {

    private func makeMap() -> HarmonyMap {
        let nodeA = HarmonyNode(id: "n1", root: 0, type: .maj7, function: .tonic, midiNotes: [60, 64, 67, 71])
        let nodeB = HarmonyNode(id: "n2", root: 5, type: .dom7, function: .dominant, midiNotes: [65, 69, 72, 75])
        let nodeC = HarmonyNode(id: "n3", root: 2, type: .min, function: .subdominant, midiNotes: [62, 65, 69])
        let layer = HarmonyLayer(id: "l1", name: "Layer 1", relationTypes: [.vToI])
        return HarmonyMap(
            schemaVersion: "1.0", id: "test-map", name: "Test", layers: [layer],
            nodes: [nodeA, nodeB, nodeC], edges: []
        )
    }

    private func makeEdge(
        id: String = "e1", source: String = "n1", target: String = "n2",
        relationTypes: [RelationType] = [.vToI], directed: Bool = true,
        layers: [String] = [], weight: Float = 1.0
    ) -> HarmonyEdge {
        HarmonyEdge(id: id, source: source, target: target, relationTypes: relationTypes, directed: directed, layers: layers, weight: weight)
    }

    // MARK: – Add

    func test_addEdge_success() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(AddEdgeCommand(edge: makeEdge()))
        XCTAssertEqual(doc.draft.edges.map(\.id), ["e1"])
        XCTAssertTrue(doc.isDirty)
    }

    func test_addEdge_duplicateID_throwsAndLeavesDraftUnchanged() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(AddEdgeCommand(edge: makeEdge()))
        XCTAssertThrowsError(try doc.perform(AddEdgeCommand(edge: makeEdge(source: "n2", target: "n3")))) { error in
            guard case AddEdgeCommand.CommandError.duplicateID("e1") = error else {
                return XCTFail("Erwartete .duplicateID, bekam \(error)")
            }
        }
        XCTAssertEqual(doc.draft.edges.count, 1)
        XCTAssertEqual(doc.revision, 1)
    }

    func test_addEdge_emptyID_throws() {
        var doc = HarmonyMapDocument(map: makeMap())
        XCTAssertThrowsError(try doc.perform(AddEdgeCommand(edge: makeEdge(id: "")))) { error in
            guard case AddEdgeCommand.CommandError.emptyID = error else {
                return XCTFail("Erwartete .emptyID, bekam \(error)")
            }
        }
    }

    func test_addEdge_unknownSource_throws() {
        var doc = HarmonyMapDocument(map: makeMap())
        XCTAssertThrowsError(try doc.perform(AddEdgeCommand(edge: makeEdge(source: "does-not-exist")))) { error in
            guard case AddEdgeCommand.CommandError.unknownSource("does-not-exist") = error else {
                return XCTFail("Erwartete .unknownSource, bekam \(error)")
            }
        }
    }

    func test_addEdge_unknownTarget_throws() {
        var doc = HarmonyMapDocument(map: makeMap())
        XCTAssertThrowsError(try doc.perform(AddEdgeCommand(edge: makeEdge(target: "does-not-exist")))) { error in
            guard case AddEdgeCommand.CommandError.unknownTarget("does-not-exist") = error else {
                return XCTFail("Erwartete .unknownTarget, bekam \(error)")
            }
        }
    }

    func test_addEdge_emptyRelationTypes_throws() {
        var doc = HarmonyMapDocument(map: makeMap())
        XCTAssertThrowsError(try doc.perform(AddEdgeCommand(edge: makeEdge(relationTypes: [])))) { error in
            guard case AddEdgeCommand.CommandError.emptyRelationTypes = error else {
                return XCTFail("Erwartete .emptyRelationTypes, bekam \(error)")
            }
        }
    }

    func test_addEdge_nonFiniteWeight_throws() {
        var doc = HarmonyMapDocument(map: makeMap())
        XCTAssertThrowsError(try doc.perform(AddEdgeCommand(edge: makeEdge(weight: .nan)))) { error in
            guard case AddEdgeCommand.CommandError.invalidWeight = error else {
                return XCTFail("Erwartete .invalidWeight, bekam \(error)")
            }
        }
    }

    func test_addEdge_zeroWeight_throws() {
        var doc = HarmonyMapDocument(map: makeMap())
        XCTAssertThrowsError(try doc.perform(AddEdgeCommand(edge: makeEdge(weight: 0)))) { error in
            guard case AddEdgeCommand.CommandError.invalidWeight(0) = error else {
                return XCTFail("Erwartete .invalidWeight(0), bekam \(error)")
            }
        }
    }

    func test_addEdge_negativeWeight_throws() {
        var doc = HarmonyMapDocument(map: makeMap())
        XCTAssertThrowsError(try doc.perform(AddEdgeCommand(edge: makeEdge(weight: -1)))) { error in
            guard case AddEdgeCommand.CommandError.invalidWeight(-1) = error else {
                return XCTFail("Erwartete .invalidWeight(-1), bekam \(error)")
            }
        }
    }

    func test_addEdge_unknownLayer_throws() {
        var doc = HarmonyMapDocument(map: makeMap())
        XCTAssertThrowsError(try doc.perform(AddEdgeCommand(edge: makeEdge(layers: ["does-not-exist"])))) { error in
            guard case AddEdgeCommand.CommandError.unknownLayer("does-not-exist") = error else {
                return XCTFail("Erwartete .unknownLayer, bekam \(error)")
            }
        }
    }

    // MARK: – Delete

    func test_deleteEdge_success() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(AddEdgeCommand(edge: makeEdge()))
        try doc.perform(DeleteEdgeCommand(edgeID: "e1"))
        XCTAssertTrue(doc.draft.edges.isEmpty)
    }

    func test_deleteEdge_unknownID_throws() {
        var doc = HarmonyMapDocument(map: makeMap())
        XCTAssertThrowsError(try doc.perform(DeleteEdgeCommand(edgeID: "does-not-exist"))) { error in
            guard case DeleteEdgeCommand.CommandError.edgeNotFound("does-not-exist") = error else {
                return XCTFail("Erwartete .edgeNotFound, bekam \(error)")
            }
        }
    }

    // MARK: – Update

    func test_updateEdge_success() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(AddEdgeCommand(edge: makeEdge()))
        try doc.perform(UpdateEdgeCommand(
            edgeID: "e1", source: "n2", target: "n3", directed: false,
            relationTypes: [.commonTone], layers: ["l1"], weight: 0.5
        ))
        let updated = doc.draft.edges.first { $0.id == "e1" }
        XCTAssertEqual(updated?.source, "n2")
        XCTAssertEqual(updated?.target, "n3")
        XCTAssertEqual(updated?.directed, false)
        XCTAssertEqual(updated?.relationTypes, [.commonTone])
        XCTAssertEqual(updated?.layers, ["l1"])
        XCTAssertEqual(updated?.weight, 0.5)
    }

    func test_updateEdge_unknownID_throws() {
        var doc = HarmonyMapDocument(map: makeMap())
        XCTAssertThrowsError(try doc.perform(UpdateEdgeCommand(
            edgeID: "does-not-exist", source: "n1", target: "n2", directed: true, relationTypes: [.vToI]
        )))
    }

    func test_updateEdge_unknownSource_throws() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(AddEdgeCommand(edge: makeEdge()))
        XCTAssertThrowsError(try doc.perform(UpdateEdgeCommand(
            edgeID: "e1", source: "does-not-exist", target: "n2", directed: true, relationTypes: [.vToI]
        ))) { error in
            guard case UpdateEdgeCommand.CommandError.unknownSource("does-not-exist") = error else {
                return XCTFail("Erwartete .unknownSource, bekam \(error)")
            }
        }
    }

    func test_updateEdge_emptyRelationTypes_throws() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(AddEdgeCommand(edge: makeEdge()))
        XCTAssertThrowsError(try doc.perform(UpdateEdgeCommand(
            edgeID: "e1", source: "n1", target: "n2", directed: true, relationTypes: []
        ))) { error in
            guard case UpdateEdgeCommand.CommandError.emptyRelationTypes = error else {
                return XCTFail("Erwartete .emptyRelationTypes, bekam \(error)")
            }
        }
    }

    func test_updateEdge_invalidWeight_throws() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(AddEdgeCommand(edge: makeEdge()))
        XCTAssertThrowsError(try doc.perform(UpdateEdgeCommand(
            edgeID: "e1", source: "n1", target: "n2", directed: true, relationTypes: [.vToI], weight: -5
        ))) { error in
            guard case UpdateEdgeCommand.CommandError.invalidWeight(-5) = error else {
                return XCTFail("Erwartete .invalidWeight(-5), bekam \(error)")
            }
        }
    }

    func test_updateEdge_unknownLayer_throws() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(AddEdgeCommand(edge: makeEdge()))
        XCTAssertThrowsError(try doc.perform(UpdateEdgeCommand(
            edgeID: "e1", source: "n1", target: "n2", directed: true, relationTypes: [.vToI], layers: ["does-not-exist"]
        ))) { error in
            guard case UpdateEdgeCommand.CommandError.unknownLayer("does-not-exist") = error else {
                return XCTFail("Erwartete .unknownLayer, bekam \(error)")
            }
        }
    }

    // MARK: – Undo/Redo

    func test_undoRedo_overAddEdge() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(AddEdgeCommand(edge: makeEdge()))
        try doc.undo()
        XCTAssertTrue(doc.draft.edges.isEmpty)
        try doc.redo()
        XCTAssertEqual(doc.draft.edges.map(\.id), ["e1"])
    }

    func test_undoRedo_overDeleteEdge() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(AddEdgeCommand(edge: makeEdge()))
        try doc.perform(DeleteEdgeCommand(edgeID: "e1"))
        try doc.undo()
        XCTAssertEqual(doc.draft.edges.map(\.id), ["e1"])
        try doc.redo()
        XCTAssertTrue(doc.draft.edges.isEmpty)
    }

    func test_undoRedo_overUpdateEdge() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(AddEdgeCommand(edge: makeEdge(weight: 1.0)))
        try doc.perform(UpdateEdgeCommand(edgeID: "e1", source: "n1", target: "n2", directed: true, relationTypes: [.vToI], weight: 0.3))
        try doc.undo()
        XCTAssertEqual(doc.draft.edges.first { $0.id == "e1" }?.weight, 1.0)
        try doc.redo()
        XCTAssertEqual(doc.draft.edges.first { $0.id == "e1" }?.weight, 0.3)
    }
}
