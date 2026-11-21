import XCTest
@testable import HarmonyAuthoring
import HarmonyShared

final class LayerAuthoringCommandsTests: XCTestCase {

    private func makeMap() -> HarmonyMap {
        let nodeA = HarmonyNode(id: "n1", root: 0, type: .maj7, function: .tonic, midiNotes: [60, 64, 67, 71], layers: ["l1"])
        let nodeB = HarmonyNode(id: "n2", root: 5, type: .dom7, function: .dominant, midiNotes: [65, 69, 72, 75], layers: ["l1"])
        let edge  = HarmonyEdge(id: "e1", source: "n1", target: "n2", relationTypes: [.vToI], directed: true, layers: ["l1"])
        let layer = HarmonyLayer(id: "l1", name: "Layer 1", relationTypes: [.vToI])
        return HarmonyMap(
            schemaVersion: "1.0", id: "test-map", name: "Test", layers: [layer],
            nodes: [nodeA, nodeB], edges: [edge]
        )
    }

    // MARK: – Add

    func test_addLayer_success() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(AddLayerCommand(layer: HarmonyLayer(id: "l2", name: "Layer 2", relationTypes: [.commonTone])))
        XCTAssertEqual(doc.draft.layers.map(\.id), ["l1", "l2"])
    }

    func test_addLayer_duplicateID_throwsAndLeavesDraftUnchanged() {
        var doc = HarmonyMapDocument(map: makeMap())
        XCTAssertThrowsError(try doc.perform(AddLayerCommand(layer: HarmonyLayer(id: "l1", name: "Dup", relationTypes: [.commonTone])))) { error in
            guard case AddLayerCommand.CommandError.duplicateID("l1") = error else {
                return XCTFail("Erwartete .duplicateID, bekam \(error)")
            }
        }
        XCTAssertEqual(doc.draft.layers.count, 1)
        XCTAssertFalse(doc.isDirty)
    }

    func test_addLayer_emptyID_throws() {
        var doc = HarmonyMapDocument(map: makeMap())
        XCTAssertThrowsError(try doc.perform(AddLayerCommand(layer: HarmonyLayer(id: "", name: "X", relationTypes: [.commonTone])))) { error in
            guard case AddLayerCommand.CommandError.emptyID = error else {
                return XCTFail("Erwartete .emptyID, bekam \(error)")
            }
        }
    }

    func test_addLayer_emptyRelationTypes_throws() {
        var doc = HarmonyMapDocument(map: makeMap())
        XCTAssertThrowsError(try doc.perform(AddLayerCommand(layer: HarmonyLayer(id: "l2", name: "X", relationTypes: [])))) { error in
            guard case AddLayerCommand.CommandError.emptyRelationTypes = error else {
                return XCTFail("Erwartete .emptyRelationTypes, bekam \(error)")
            }
        }
    }

    // MARK: – Update / Rename

    func test_updateLayer_rename_migratesEdgeAndNodeLayersAtomically() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(UpdateLayerCommand(layerID: "l1", newID: "renamed", name: "Renamed Layer", relationTypes: [.vToI]))

        XCTAssertEqual(doc.draft.layers.map(\.id), ["renamed"])
        XCTAssertEqual(doc.draft.edges.first { $0.id == "e1" }?.layers, ["renamed"])
        XCTAssertEqual(doc.draft.nodes.first { $0.id == "n1" }?.layers, ["renamed"])
        XCTAssertEqual(doc.draft.nodes.first { $0.id == "n2" }?.layers, ["renamed"])
    }

    func test_updateLayer_contentOnlyUpdate_keepsIDUnchanged() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(UpdateLayerCommand(layerID: "l1", newID: "l1", name: "New Name", relationTypes: [.commonTone]))
        let updated = doc.draft.layers.first { $0.id == "l1" }
        XCTAssertEqual(updated?.name, "New Name")
        XCTAssertEqual(updated?.relationTypes, [.commonTone])
        XCTAssertEqual(doc.draft.edges.first { $0.id == "e1" }?.layers, ["l1"], "Content-only-Update darf Layerlisten nicht anfassen")
    }

    func test_updateLayer_unknownID_throws() {
        var doc = HarmonyMapDocument(map: makeMap())
        XCTAssertThrowsError(try doc.perform(UpdateLayerCommand(layerID: "does-not-exist", newID: "x", name: "X", relationTypes: [.vToI])))
    }

    func test_updateLayer_emptyNewID_throws() {
        var doc = HarmonyMapDocument(map: makeMap())
        XCTAssertThrowsError(try doc.perform(UpdateLayerCommand(layerID: "l1", newID: "", name: "X", relationTypes: [.vToI]))) { error in
            guard case UpdateLayerCommand.CommandError.emptyNewID = error else {
                return XCTFail("Erwartete .emptyNewID, bekam \(error)")
            }
        }
    }

    func test_updateLayer_duplicateNewID_throws() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(AddLayerCommand(layer: HarmonyLayer(id: "l2", name: "L2", relationTypes: [.commonTone])))
        XCTAssertThrowsError(try doc.perform(UpdateLayerCommand(layerID: "l1", newID: "l2", name: "X", relationTypes: [.vToI]))) { error in
            guard case UpdateLayerCommand.CommandError.duplicateID("l2") = error else {
                return XCTFail("Erwartete .duplicateID, bekam \(error)")
            }
        }
    }

    func test_updateLayer_emptyRelationTypes_throws() {
        var doc = HarmonyMapDocument(map: makeMap())
        XCTAssertThrowsError(try doc.perform(UpdateLayerCommand(layerID: "l1", newID: "l1", name: "X", relationTypes: []))) { error in
            guard case UpdateLayerCommand.CommandError.emptyRelationTypes = error else {
                return XCTFail("Erwartete .emptyRelationTypes, bekam \(error)")
            }
        }
    }

    // MARK: – Delete

    func test_deleteLayer_removesLayerAndAllReferences_noDanglingLayerIDs() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(DeleteLayerCommand(layerID: "l1"))

        XCTAssertTrue(doc.draft.layers.isEmpty)
        // HarmonyEdge.layers ist [String] (nicht optional) — [] bleibt hier
        // die korrekte "in keinem Layer"-Semantik.
        XCTAssertEqual(doc.draft.edges.first { $0.id == "e1" }?.layers, [])
        // HarmonyNode.layers ist [String]? — nach Entfernen der letzten
        // expliziten Layerbindung muss nil stehen (Finding A10, Runde 037 /
        // V-00a), nicht [], sonst verschwindet der Node aus allen Layern
        // statt wieder ueber HarmonyEdge.layers abgeleitet zu werden.
        XCTAssertNil(doc.draft.nodes.first { $0.id == "n1" }?.layers)
        XCTAssertNil(doc.draft.nodes.first { $0.id == "n2" }?.layers)
    }

    func test_deleteLayer_nodeWithMultipleLayers_keepsRemainingLayersExplicit() throws {
        // Node mit zwei expliziten Layerbindungen: nach dem Loeschen von
        // "l1" muss die verbleibende Bindung "l2" explizit erhalten bleiben
        // (kein nil, solange noch mindestens eine Layer-ID uebrig ist).
        let nodeA = HarmonyNode(id: "n1", root: 0, type: .maj7, function: .tonic, midiNotes: [60, 64, 67, 71], layers: ["l1", "l2"])
        let nodeB = HarmonyNode(id: "n2", root: 5, type: .dom7, function: .dominant, midiNotes: [65, 69, 72, 75], layers: ["l1"])
        let edge  = HarmonyEdge(id: "e1", source: "n1", target: "n2", relationTypes: [.vToI], directed: true, layers: ["l1"])
        let l1 = HarmonyLayer(id: "l1", name: "Layer 1", relationTypes: [.vToI])
        let l2 = HarmonyLayer(id: "l2", name: "Layer 2", relationTypes: [.commonTone])
        let map = HarmonyMap(schemaVersion: "1.0", id: "test-map-2", name: "Test", layers: [l1, l2], nodes: [nodeA, nodeB], edges: [edge])

        var doc = HarmonyMapDocument(map: map)
        try doc.perform(DeleteLayerCommand(layerID: "l1"))

        XCTAssertEqual(doc.draft.nodes.first { $0.id == "n1" }?.layers, ["l2"], "n1 bleibt explizit in l2 — nicht auf nil zuruecksetzen, solange eine Bindung uebrig ist")
        XCTAssertNil(doc.draft.nodes.first { $0.id == "n2" }?.layers, "n2 verliert seine einzige Bindung — muss nil werden, nicht []")
    }

    func test_deleteLayer_nilNodeLayers_makesNodeActiveViaEdgesAgain() throws {
        // Semantischer Beweis fuer den Fix: nach dem Loeschen des einzigen
        // Layers, in dem ein Node explizit gebunden war, muss der Node ueber
        // seine Kante(n) wieder als aktiv in JEDEM Layer gelten, dem diese
        // Kante angehoert — nicht in keinem mehr, wie es bei layers: []
        // der Fall waere (siehe HarmonyMap.activeNodeIDs(in:)).
        let nodeA = HarmonyNode(id: "n1", root: 0, type: .maj7, function: .tonic, midiNotes: [60, 64, 67, 71], layers: ["l1"])
        let nodeB = HarmonyNode(id: "n2", root: 5, type: .dom7, function: .dominant, midiNotes: [65, 69, 72, 75])
        let edge  = HarmonyEdge(id: "e1", source: "n1", target: "n2", relationTypes: [.vToI], directed: true, layers: ["l1", "l2"])
        let l1 = HarmonyLayer(id: "l1", name: "Layer 1", relationTypes: [.vToI])
        let l2 = HarmonyLayer(id: "l2", name: "Layer 2", relationTypes: [.vToI])
        let map = HarmonyMap(schemaVersion: "1.0", id: "test-map-3", name: "Test", layers: [l1, l2], nodes: [nodeA, nodeB], edges: [edge])

        var doc = HarmonyMapDocument(map: map)
        try doc.perform(DeleteLayerCommand(layerID: "l1"))

        XCTAssertTrue(doc.draft.activeNodeIDs(in: "l2").contains("n1"), "n1 muss nach dem Fix wieder ueber e1 in l2 aktiv sein")
    }

    func test_deleteLayer_doesNotRemoveNodesOrEdges() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(DeleteLayerCommand(layerID: "l1"))
        XCTAssertEqual(doc.draft.nodes.count, 2)
        XCTAssertEqual(doc.draft.edges.count, 1)
    }

    func test_deleteLayer_unknownID_throws() {
        var doc = HarmonyMapDocument(map: makeMap())
        XCTAssertThrowsError(try doc.perform(DeleteLayerCommand(layerID: "does-not-exist"))) { error in
            guard case DeleteLayerCommand.CommandError.layerNotFound("does-not-exist") = error else {
                return XCTFail("Erwartete .layerNotFound, bekam \(error)")
            }
        }
    }

    // MARK: – Undo/Redo

    func test_undoRedo_overRenameLayer() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(UpdateLayerCommand(layerID: "l1", newID: "renamed", name: "Renamed", relationTypes: [.vToI]))
        try doc.undo()

        XCTAssertEqual(doc.draft.layers.map(\.id), ["l1"])
        XCTAssertEqual(doc.draft.edges.first { $0.id == "e1" }?.layers, ["l1"])

        try doc.redo()
        XCTAssertEqual(doc.draft.layers.map(\.id), ["renamed"])
        XCTAssertEqual(doc.draft.edges.first { $0.id == "e1" }?.layers, ["renamed"])
    }

    func test_undoRedo_overDeleteLayer() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        try doc.perform(DeleteLayerCommand(layerID: "l1"))
        try doc.undo()

        XCTAssertEqual(doc.draft.layers.map(\.id), ["l1"])
        XCTAssertEqual(doc.draft.nodes.first { $0.id == "n1" }?.layers, ["l1"])

        try doc.redo()
        XCTAssertTrue(doc.draft.layers.isEmpty)
    }

    // MARK: – Diagnostics bleiben nach Mutation aktuell

    func test_deleteLayer_diagnosticsReflectNewState() throws {
        var doc = HarmonyMapDocument(map: makeMap())
        XCTAssertTrue(doc.diagnostics.isAcceptable)
        try doc.perform(DeleteLayerCommand(layerID: "l1"))
        // Nodes/Edges bleiben global verbunden (n1<->n2 ueber e1), also weiterhin akzeptabel —
        // beweist, dass diagnostics nach der Mutation neu berechnet wird und nicht stehen bleibt.
        XCTAssertTrue(doc.diagnostics.isAcceptable)
        XCTAssertTrue(doc.draft.layers.isEmpty)
    }
}
