import XCTest
@testable import HarmonyAuthoring
import HarmonyShared

final class DiatonicHarmonyBuilderTests: XCTestCase {

    // MARK: – Fixtures

    private func makeEmptyMap() -> HarmonyMap {
        HarmonyMap(schemaVersion: "1.0", id: "builder-map", name: "Test", layers: [], nodes: [], edges: [])
    }

    private func makeMapWithLayer() -> HarmonyMap {
        let layer = HarmonyLayer(id: "functional", name: "Functional", relationTypes: [.commonTone])
        return HarmonyMap(schemaVersion: "1.0", id: "builder-map", name: "Test", layers: [layer], nodes: [], edges: [])
    }

    // MARK: – Deterministischer Diff für C-Dur/Ionian

    func test_proposeDiff_cMajor_producesSevenNodesAndSevenEdges_stableIDs() {
        let diff = DiatonicHarmonyBuilder.proposeDiff(for: makeEmptyMap(), config: HarmonyBuilderConfig(keyRoot: 0))

        XCTAssertEqual(diff.proposedNodes.map(\.node.id), ["C-I", "C-ii", "C-iii", "C-IV", "C-V", "C-vi", "C-vii"])
        XCTAssertEqual(diff.proposedEdges.map(\.edge.id), [
            "C-I-C-ii", "C-ii-C-iii", "C-iii-C-IV", "C-IV-C-V", "C-V-C-vi", "C-vi-C-vii", "C-vii-C-I",
        ])
        XCTAssertTrue(diff.warnings.isEmpty)
    }

    func test_proposeDiff_isDeterministic_acrossRepeatedCalls() {
        let map = makeEmptyMap()
        let diffA = DiatonicHarmonyBuilder.proposeDiff(for: map, config: HarmonyBuilderConfig(keyRoot: 0))
        let diffB = DiatonicHarmonyBuilder.proposeDiff(for: map, config: HarmonyBuilderConfig(keyRoot: 0))

        XCTAssertEqual(diffA.proposedNodes.map(\.node.id), diffB.proposedNodes.map(\.node.id))
        XCTAssertEqual(diffA.proposedNodes.map(\.node.midiNotes), diffB.proposedNodes.map(\.node.midiNotes))
        XCTAssertEqual(diffA.proposedEdges.map(\.edge.id), diffB.proposedEdges.map(\.edge.id))
    }

    func test_proposeDiff_functionMapping_matchesPistonTonicSubdominantDominant() {
        let diff = DiatonicHarmonyBuilder.proposeDiff(for: makeEmptyMap(), config: HarmonyBuilderConfig(keyRoot: 0))
        let functionByRoman = Dictionary(uniqueKeysWithValues: diff.proposedNodes.map { (String($0.node.id.dropFirst(2)), $0.node.function) })

        XCTAssertEqual(functionByRoman["I"], .tonic)
        XCTAssertEqual(functionByRoman["iii"], .tonic)
        XCTAssertEqual(functionByRoman["vi"], .tonic)
        XCTAssertEqual(functionByRoman["ii"], .subdominant)
        XCTAssertEqual(functionByRoman["IV"], .subdominant)
        XCTAssertEqual(functionByRoman["V"], .dominant)
        XCTAssertEqual(functionByRoman["vii"], .dominant)
    }

    func test_proposeDiff_differentKeyRoot_shiftsRootAndID() {
        let diff = DiatonicHarmonyBuilder.proposeDiff(for: makeEmptyMap(), config: HarmonyBuilderConfig(keyRoot: 7))

        XCTAssertEqual(diff.proposedNodes.first?.node.id, "G-I")
        XCTAssertEqual(diff.proposedNodes.first?.node.root, 7)
    }

    // MARK: – Keine stillen Überschreibungen bei Konflikten

    func test_proposeDiff_existingNodeID_isSkippedWithWarning_notOverwritten() {
        let existing = HarmonyNode(id: "C-I", root: 0, type: .maj, function: .ambiguous, midiNotes: [60])
        let map = HarmonyMap(schemaVersion: "1.0", id: "builder-map", name: "Test", layers: [], nodes: [existing], edges: [])

        let diff = DiatonicHarmonyBuilder.proposeDiff(for: map, config: HarmonyBuilderConfig(keyRoot: 0))

        XCTAssertFalse(diff.proposedNodes.contains { $0.node.id == "C-I" })
        XCTAssertTrue(diff.warnings.contains { $0.objectKind == "node" && $0.id == "C-I" })
        // Die übrigen sechs Stufen bleiben unbeeinträchtigt vorgeschlagen.
        XCTAssertEqual(diff.proposedNodes.count, 6)
    }

    func test_proposeDiff_missingLayer_warnsAndOmitsLayerAssignment() {
        let diff = DiatonicHarmonyBuilder.proposeDiff(
            for: makeEmptyMap(), config: HarmonyBuilderConfig(keyRoot: 0, layerID: "does-not-exist")
        )

        XCTAssertTrue(diff.warnings.contains { $0.objectKind == "layer" && $0.id == "does-not-exist" })
        XCTAssertTrue(diff.proposedEdges.allSatisfy { $0.edge.layers.isEmpty })
    }

    func test_proposeDiff_existingLayer_assignsLayerToEdges() {
        let diff = DiatonicHarmonyBuilder.proposeDiff(
            for: makeMapWithLayer(), config: HarmonyBuilderConfig(keyRoot: 0, layerID: "functional")
        )

        XCTAssertTrue(diff.warnings.isEmpty)
        XCTAssertTrue(diff.proposedEdges.allSatisfy { $0.edge.layers == ["functional"] })
    }

    // MARK: – ApplyHarmonyBuilderDiffCommand: referenzsicher, ein Undo-Schritt

    func test_apply_success_addsAllNodesAndEdges_referenceSafe() throws {
        var doc = HarmonyMapDocument(map: makeEmptyMap())
        let diff = DiatonicHarmonyBuilder.proposeDiff(for: doc.draft, config: HarmonyBuilderConfig(keyRoot: 0))

        try doc.perform(ApplyHarmonyBuilderDiffCommand(diff: diff))

        XCTAssertEqual(doc.draft.nodes.count, 7)
        XCTAssertEqual(doc.draft.edges.count, 7)
        let nodeIDs = Set(doc.draft.nodes.map(\.id))
        for edge in doc.draft.edges {
            XCTAssertTrue(nodeIDs.contains(edge.source))
            XCTAssertTrue(nodeIDs.contains(edge.target))
        }
        XCTAssertTrue(doc.isDirty)
    }

    func test_apply_emptyDiff_throwsAndLeavesDraftUnchanged() {
        var doc = HarmonyMapDocument(map: makeEmptyMap())
        let emptyDiff = HarmonyBuilderDiff(proposedNodes: [], proposedEdges: [], warnings: [])

        XCTAssertThrowsError(try doc.perform(ApplyHarmonyBuilderDiffCommand(diff: emptyDiff))) { error in
            guard case ApplyHarmonyBuilderDiffCommand.CommandError.emptyDiff = error else {
                return XCTFail("Erwartete .emptyDiff, bekam \(error)")
            }
        }
        XCTAssertEqual(doc.draft.nodes.count, 0)
        XCTAssertFalse(doc.isDirty)
        XCTAssertEqual(doc.revision, 0)
    }

    func test_apply_isExactlyOneUndoStep() throws {
        var doc = HarmonyMapDocument(map: makeEmptyMap())
        let diff = DiatonicHarmonyBuilder.proposeDiff(for: doc.draft, config: HarmonyBuilderConfig(keyRoot: 0))

        try doc.perform(ApplyHarmonyBuilderDiffCommand(diff: diff))
        XCTAssertEqual(doc.revision, 1)
        XCTAssertEqual(doc.draft.nodes.count, 7)

        try doc.undo()

        XCTAssertEqual(doc.draft.nodes.count, 0, "Ein Undo muss den gesamten Builder-Apply entfernen, nicht Node für Node")
        XCTAssertEqual(doc.draft.edges.count, 0)
    }

    func test_apply_redo_restoresSameDiff() throws {
        var doc = HarmonyMapDocument(map: makeEmptyMap())
        let diff = DiatonicHarmonyBuilder.proposeDiff(for: doc.draft, config: HarmonyBuilderConfig(keyRoot: 0))
        try doc.perform(ApplyHarmonyBuilderDiffCommand(diff: diff))
        let nodeIDsAfterApply = doc.draft.nodes.map(\.id)

        try doc.undo()
        try doc.redo()

        XCTAssertEqual(doc.draft.nodes.map(\.id), nodeIDsAfterApply)
        XCTAssertEqual(doc.draft.edges.count, 7)
    }

    func test_apply_conflictingDraft_throwsAndLeavesDraftUnchanged() throws {
        // Diff wird gegen eine leere Map berechnet, aber zwischenzeitlich
        // existiert "C-I" bereits im Draft (z. B. durch eine parallele
        // Node-Authoring-Aktion) — Apply muss trotzdem referenzsicher
        // bleiben und nicht still überschreiben.
        var doc = HarmonyMapDocument(map: makeEmptyMap())
        let diff = DiatonicHarmonyBuilder.proposeDiff(for: doc.draft, config: HarmonyBuilderConfig(keyRoot: 0))
        try doc.perform(AddNodeCommand(node: HarmonyNode(id: "C-I", root: 0, type: .maj, function: .ambiguous, midiNotes: [60])))

        XCTAssertThrowsError(try doc.perform(ApplyHarmonyBuilderDiffCommand(diff: diff))) { error in
            guard case ApplyHarmonyBuilderDiffCommand.CommandError.duplicateNodeID("C-I") = error else {
                return XCTFail("Erwartete .duplicateNodeID, bekam \(error)")
            }
        }
        XCTAssertEqual(doc.draft.nodes.count, 1, "Draft darf nach dem gescheiterten Apply unverändert bleiben")
    }

    // MARK: – Validator akzeptiert den angewendeten Diff

    func test_apply_validatorAcceptsResult_onlyDocumentedWarnings() throws {
        var doc = HarmonyMapDocument(map: makeEmptyMap())
        let diff = DiatonicHarmonyBuilder.proposeDiff(for: doc.draft, config: HarmonyBuilderConfig(keyRoot: 0))

        try doc.perform(ApplyHarmonyBuilderDiffCommand(diff: diff))

        XCTAssertTrue(doc.diagnostics.errors.isEmpty, "Validator darf nach einem sauberen Builder-Apply keine Errors melden")
        XCTAssertNotNil(doc.validatedSnapshot())
    }

    // MARK: – Runde 037 / V-00a: Default-Layer behebt Builder-A1
    // (Fable-5-Review Runde 036: ein Builder-Diff ohne Layer ist für
    // `HarmonyGraphEngine` untraversierbar — der Pfad "Neu -> Builder ->
    // Apply -> validierter Snapshot -> Graph traversiert" muss belastbar
    // grün sein.)

    func test_newDocument_hasDefaultFunctionalLayer() {
        let doc = HarmonyMapDocumentStore.newDocument()
        XCTAssertEqual(doc.draft.layers.map(\.id), ["functional"])
        XCTAssertEqual(doc.draft.layers.first?.relationTypes, [.commonTone])
    }

    func test_newDocument_builderDiff_usesDefaultLayer_noWarnings() {
        let doc = HarmonyMapDocumentStore.newDocument()
        let diff = DiatonicHarmonyBuilder.proposeDiff(
            for: doc.draft, config: HarmonyBuilderConfig(keyRoot: 0, layerID: "functional")
        )

        XCTAssertTrue(diff.warnings.isEmpty)
        XCTAssertTrue(diff.proposedEdges.allSatisfy { $0.edge.layers == ["functional"] },
                      "Kein Builder-Vorschlag darf für ein frisches Dokument layerlos sein")
    }

    func test_newDocument_builderApply_isTraversableByHarmonyGraphEngine() throws {
        var doc = HarmonyMapDocumentStore.newDocument()
        let diff = DiatonicHarmonyBuilder.proposeDiff(
            for: doc.draft, config: HarmonyBuilderConfig(keyRoot: 0, layerID: "functional")
        )

        try doc.perform(ApplyHarmonyBuilderDiffCommand(diff: diff))
        XCTAssertNotNil(doc.validatedSnapshot(), "Angewendeter Builder-Diff muss einen validen Runtime-Snapshot ergeben")

        // Belastbarer Traversierungsnachweis: dieselbe HarmonyGraphEngine,
        // die auch die 3D-Runtime nutzt, muss von einem Builder-Node aus
        // mindestens eine Kante im Layer "functional" finden.
        let engine = HarmonyGraphEngine(map: doc.draft, initialLayer: "functional", seed: 1)
        let transitions = engine.transitions(from: "C-I")
        XCTAssertFalse(transitions.isEmpty, "Builder-Kanten müssen im Ziel-Layer traversierbar sein — nicht nur im Diff vorhanden")
        XCTAssertTrue(transitions.contains { $0.source == "C-ii" || $0.target == "C-ii" })

        let neighbors = engine.neighbors(of: "C-I").map(\.id)
        XCTAssertTrue(neighbors.contains("C-ii") || neighbors.contains("C-vii"),
                      "C-I muss über den Ring mindestens einen Nachbarn erreichen")
    }

    func test_previewBuilderDiff_missingLayerID_fallsBackToLayerlessWarning_evenWhenDocumentHasLayers() {
        // Dokumentiert die Rest-Verantwortung des Aufrufers (DesignerViewModel):
        // proposeDiff() selbst erzwingt keinen Layer — wer keinen layerID
        // übergibt, obwohl das Dokument einen hat, bekommt weiterhin
        // layerlose Kanten. Der DesignerViewModel-Aufrufer muss daher immer
        // einen vorhandenen Layer explizit übergeben (siehe
        // DesignerViewModelBuilderTests, previewBuilderDiff()).
        let doc = HarmonyMapDocumentStore.newDocument()
        let diff = DiatonicHarmonyBuilder.proposeDiff(for: doc.draft, config: HarmonyBuilderConfig(keyRoot: 0))

        XCTAssertTrue(diff.proposedEdges.allSatisfy { $0.edge.layers.isEmpty })
    }
}
