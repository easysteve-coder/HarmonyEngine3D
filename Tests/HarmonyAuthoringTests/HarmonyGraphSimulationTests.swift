import XCTest
@testable import HarmonyAuthoring
import HarmonyShared

final class HarmonyGraphSimulationTests: XCTestCase {

    // MARK: – Fixtures

    /// Verzweigung an "Start": zwei ausgehende Kanten mit unterschiedlichem
    /// Gewicht, damit `weightedChoice` tatsächlich eine RNG-Entscheidung
    /// trifft (nicht nur eine einzige mögliche Option durchreicht).
    private func makeBranchingMap() -> HarmonyMap {
        let start = HarmonyNode(id: "Start", root: 0, type: .maj7, function: .tonic, midiNotes: [60, 64, 67, 71])
        let x     = HarmonyNode(id: "X", root: 2, type: .m7, function: .subdominant, midiNotes: [62, 65, 69, 72])
        let y     = HarmonyNode(id: "Y", root: 7, type: .dom7, function: .dominant, midiNotes: [67, 71, 74, 77])
        let z     = HarmonyNode(id: "Z", root: 9, type: .min, function: .subdominant, midiNotes: [69, 72, 76])
        let layer = HarmonyLayer(id: "L1", name: "L1", relationTypes: [.vToI, .iiToV, .commonTone])
        let e1 = HarmonyEdge(id: "Start-X", source: "Start", target: "X", relationTypes: [.iiToV], directed: true, layers: ["L1"], weight: 0.5)
        let e2 = HarmonyEdge(id: "Start-Y", source: "Start", target: "Y", relationTypes: [.vToI], directed: true, layers: ["L1"], weight: 0.5)
        let e3 = HarmonyEdge(id: "X-Z", source: "X", target: "Z", relationTypes: [.commonTone], directed: true, layers: ["L1"], weight: 1.0, magnetProfile: MagnetProfile(preset: .strong))
        let e4 = HarmonyEdge(id: "Y-Z", source: "Y", target: "Z", relationTypes: [.commonTone], directed: true, layers: ["L1"], weight: 1.0)
        return HarmonyMap(schemaVersion: "1.0", id: "sim-map", name: "Sim", layers: [layer], nodes: [start, x, y, z], edges: [e1, e2, e3, e4])
    }

    /// ii-V→V-I-Kette (analog `HarmonyGraphEngineTests.test_iiVBoost...`).
    private func makeChainMap() -> HarmonyMap {
        let dm7   = HarmonyNode(id: "Dm7", root: 62, type: .m7, function: .subdominant, midiNotes: [62, 65, 69, 72])
        let g7    = HarmonyNode(id: "G7", root: 67, type: .dom7, function: .dominant, midiNotes: [67, 71, 74, 77])
        let cmaj7 = HarmonyNode(id: "Cmaj7", root: 60, type: .maj7, function: .tonic, midiNotes: [60, 64, 67, 71])
        let layer = HarmonyLayer(id: "L1", name: "L1", relationTypes: [.vToI, .iiToV])
        let e1 = HarmonyEdge(id: "Dm7-G7", source: "Dm7", target: "G7", relationTypes: [.iiToV], directed: true, layers: ["L1"], weight: 1.0)
        let e2 = HarmonyEdge(id: "G7-Cmaj7", source: "G7", target: "Cmaj7", relationTypes: [.vToI], directed: true, layers: ["L1"], weight: 1.0)
        return HarmonyMap(schemaVersion: "1.0", id: "chain-map", name: "Chain", layers: [layer], nodes: [dm7, g7, cmaj7], edges: [e1, e2])
    }

    /// Zwei Layer mit unterschiedlichen Kanten zwischen denselben Nodes.
    private func makeLayeredMap() -> HarmonyMap {
        let x = HarmonyNode(id: "X", root: 0, type: .maj7, function: .tonic, midiNotes: [60, 64, 67, 71])
        let y = HarmonyNode(id: "Y", root: 2, type: .m7, function: .subdominant, midiNotes: [62, 65, 69, 72])
        let z = HarmonyNode(id: "Z", root: 7, type: .dom7, function: .dominant, midiNotes: [67, 71, 74, 77])
        let l1 = HarmonyLayer(id: "L1", name: "L1", relationTypes: [.commonTone])
        let l2 = HarmonyLayer(id: "L2", name: "L2", relationTypes: [.vToI])
        let eL1 = HarmonyEdge(id: "X-Y-L1", source: "X", target: "Y", relationTypes: [.commonTone], directed: true, layers: ["L1"], weight: 1.0)
        let eL2 = HarmonyEdge(id: "X-Z-L2", source: "X", target: "Z", relationTypes: [.vToI], directed: true, layers: ["L2"], weight: 1.0)
        return HarmonyMap(schemaVersion: "1.0", id: "layer-map", name: "Layered", layers: [l1, l2], nodes: [x, y, z], edges: [eL1, eL2])
    }

    // MARK: – Determinismus

    func test_sameSeed_producesSameStepSequence_acrossTwoInstances() {
        let map = makeBranchingMap()
        var simA = HarmonyGraphSimulation(map: map, startNodeID: "Start", layer: "L1", seed: 42)
        var simB = HarmonyGraphSimulation(map: map, startNodeID: "Start", layer: "L1", seed: 42)

        // Beide Simulationen laufen X/Y/Z im Kreis nicht endlos, aber genug
        // Kanten fuer mehrere Schritte: Start->X|Y, dann X|Y->Z (nur 1 Option),
        // danach keine ausgehenden Kanten von Z -> step() liefert nil.
        let sequenceA = (0..<3).map { _ in simA.step()?.id }
        let sequenceB = (0..<3).map { _ in simB.step()?.id }

        XCTAssertEqual(sequenceA, sequenceB)
        XCTAssertTrue(sequenceA[0] == "X" || sequenceA[0] == "Y", "Erster Schritt muss eine der beiden Start-Kanten sein")
        XCTAssertEqual(sequenceA[1], "Z", "Zweiter Schritt hat nur eine mögliche Kante zu Z")
        XCTAssertNil(sequenceA[2], "Z hat keine ausgehenden Kanten")
    }

    func test_reset_sameSeed_reproducesSequence() {
        let map = makeBranchingMap()
        var sim = HarmonyGraphSimulation(map: map, startNodeID: "Start", layer: "L1", seed: 7)

        let firstRun = (0..<3).map { _ in sim.step()?.id }
        sim.reset()
        let secondRun = (0..<3).map { _ in sim.step()?.id }

        XCTAssertEqual(firstRun, secondRun)
    }

    func test_reset_restoresCurrentNodeLayerAndHistory() {
        let map = makeBranchingMap()
        var sim = HarmonyGraphSimulation(map: map, startNodeID: "Start", layer: "L1", seed: 1)
        sim.step()
        sim.step()
        XCTAssertNotEqual(sim.currentNodeID, "Start")
        XCTAssertGreaterThan(sim.history.count, 1)

        sim.reset()

        XCTAssertEqual(sim.currentNodeID, "Start")
        XCTAssertEqual(sim.history, ["Start"])
        XCTAssertEqual(sim.activeLayer, "L1")
    }

    // MARK: – Layerfilterung wie HarmonyGraphEngine

    func test_activeLayer_filtersCandidates_likeGraphEngine() {
        let map = makeLayeredMap()
        var sim = HarmonyGraphSimulation(map: map, startNodeID: "X", layer: "L1", seed: 1)

        XCTAssertEqual(sim.candidates.map { $0.transition.targetNode.id }, ["Y"], "L1 kennt nur X->Y")

        sim.setLayer("L2")
        XCTAssertEqual(sim.candidates.map { $0.transition.targetNode.id }, ["Z"], "L2 kennt nur X->Z")
    }

    func test_setLayer_unknownLayer_isNoOp() {
        let map = makeLayeredMap()
        var sim = HarmonyGraphSimulation(map: map, startNodeID: "X", layer: "L1", seed: 1)

        sim.setLayer("does-not-exist")

        XCTAssertEqual(sim.activeLayer, "L1")
        XCTAssertEqual(sim.candidates.map { $0.transition.targetNode.id }, ["Y"])
    }

    // MARK: – Effektive Gewichte stimmen mit HarmonyGraphEngine überein

    func test_candidateEffectiveWeights_matchRawGraphEngine() {
        let map = makeBranchingMap()
        let sim = HarmonyGraphSimulation(map: map, startNodeID: "Start", layer: "L1", seed: 99)

        // Referenz: eigene HarmonyGraphEngine-Instanz mit identischem
        // History-Zustand (Start bereits besucht, wie im Simulation-Init).
        let reference = HarmonyGraphEngine(map: map, initialLayer: "L1", seed: 99)
        reference.recordVisit("Start")

        let simWeights = sim.candidates.map { $0.transition.effectiveWeight }.sorted()
        let refWeights = reference.weightedTransitions(from: "Start").map { $0.effectiveWeight }.sorted()

        XCTAssertEqual(simWeights, refWeights)
    }

    // MARK: – History beeinflusst Gewichte (ii-V-Boost)

    func test_history_iiVBoost_appliesAfterStepThroughIiV() {
        let map = makeChainMap()

        // Baseline ohne Historie: frische Engine, kein vorheriger Kontext.
        let baselineEngine = HarmonyGraphEngine(map: map, initialLayer: "L1", seed: 1)
        let baseline = baselineEngine.weightedTransitions(from: "G7").first { $0.targetNode.id == "Cmaj7" }!.effectiveWeight

        var sim = HarmonyGraphSimulation(map: map, startNodeID: "Dm7", layer: "L1", seed: 1)
        sim.step() // Dm7 -> G7 (einzige Kante) — history: [Dm7, G7]

        let boosted = sim.candidates.first { $0.transition.targetNode.id == "Cmaj7" }!.transition.effectiveWeight

        XCTAssertEqual(boosted, baseline * 1.5, accuracy: 0.0001)
    }

    // MARK: – Preview-Felder (RelationTypes/Preset/FieldKind/Range) — keine Parallel-Logik

    func test_candidates_exposePreviewFields_derivedFromSharedHelper() {
        let map = makeBranchingMap()
        let sim = HarmonyGraphSimulation(map: map, startNodeID: "X", layer: "L1", seed: 1, rangeScale: 2.0)

        guard let candidate = sim.candidates.first(where: { $0.transition.targetNode.id == "Z" }) else {
            return XCTFail("Erwartete Kandidat X->Z")
        }
        XCTAssertEqual(candidate.transition.edge.relationTypes, [.commonTone])
        XCTAssertEqual(candidate.magnetPreset, .strong)
        XCTAssertEqual(candidate.fieldKind, HarmonicMagnetPreview.fieldKind(for: [.commonTone]))
        XCTAssertEqual(candidate.effectiveRange, HarmonicMagnetPreview.effectiveRange(preset: .strong, rangeScale: 2.0))
    }
}
