import XCTest
import HarmonyShared

// MARK: – HarmonyGraphEngineTests
//
// Deckt deterministische weightedChoice-Sequenzen sowie die drei
// Kontext-Modulationsregeln in HarmonyGraphEngine.effectiveWeight ab:
//   Regel 1 — ii-V-Boost
//   Regel 2 — Rückkehr-Dämpfung
//   Regel 3 — Spannungserhalt (2 aufeinanderfolgende starke Kanten)
//
// Der Regressionsfall in test_twoStrongTransitions_singleRealTransition_doesNotDoubleCount
// wäre vor der Runde-015-Korrektur rot: history hielt nur 2 Einträge, wodurch
// lastEdge()/prevEdge() auf denselben Übergang zurückfielen und Regel 3 bereits nach
// einer einzigen starken Kante griff.
//
// Alle Fixtures sind Inline-JSON — kein Bezug auf Bundle-/App-Maps.

final class HarmonyGraphEngineTests: XCTestCase {

    private func decode(_ json: String) throws -> HarmonyMap {
        try JSONDecoder().decode(HarmonyMap.self, from: Data(json.utf8))
    }

    private func node(_ id: String, root: Int = 60, type: String = "maj7", function: String = "tonic") -> String {
        """
        { "id": "\(id)", "root": \(root), "type": "\(type)", "function": "\(function)", "midiNotes": [60, 64, 67, 71] }
        """
    }

    // MARK: – Determinismus

    func test_weightedChoice_deterministicSequence_withFixedSeed() throws {
        let json = """
        {
          "schemaVersion": "1.0", "id": "det-map", "name": "Determinism",
          "layers": [{ "id": "L1", "name": "L1", "relationTypes": ["V-I", "ii-V", "commonTone"] }],
          "nodes": [
            \(node("Start")), \(node("X")), \(node("Y")), \(node("Z"))
          ],
          "edges": [
            { "id": "Start-X", "source": "Start", "target": "X", "relationTypes": ["V-I"],      "directed": true, "layers": ["L1"], "weight": 1.0 },
            { "id": "Start-Y", "source": "Start", "target": "Y", "relationTypes": ["ii-V"],     "directed": true, "layers": ["L1"], "weight": 0.8 },
            { "id": "Start-Z", "source": "Start", "target": "Z", "relationTypes": ["commonTone"],"directed": true, "layers": ["L1"], "weight": 0.6 }
          ]
        }
        """
        let map = try decode(json)
        let engineA = HarmonyGraphEngine(map: map, initialLayer: "L1", seed: 42)
        let engineB = HarmonyGraphEngine(map: map, initialLayer: "L1", seed: 42)

        let sequenceA = (0..<20).map { _ in engineA.weightedChoice(from: "Start")?.id }
        let sequenceB = (0..<20).map { _ in engineB.weightedChoice(from: "Start")?.id }

        XCTAssertEqual(sequenceA, sequenceB)
        XCTAssertTrue(sequenceA.allSatisfy { $0 != nil })
    }

    // MARK: – Regel 2: Rückkehr-Dämpfung

    func test_returnDamping_targetVisitedInLastTwoSteps_isDampened() throws {
        let json = """
        {
          "schemaVersion": "1.0", "id": "damp-map", "name": "Damping",
          "layers": [{ "id": "L1", "name": "L1", "relationTypes": ["commonTone"] }],
          "nodes": [\(node("Start")), \(node("Target")), \(node("Other"))],
          "edges": [
            { "id": "Start-Target", "source": "Start", "target": "Target", "relationTypes": ["commonTone"], "directed": true, "layers": ["L1"], "weight": 1.0 }
          ]
        }
        """
        let map = try decode(json)
        let engine = HarmonyGraphEngine(map: map, initialLayer: "L1")

        let baseline = try XCTUnwrap(engine.weightedTransitions(from: "Start").first { $0.targetNode.id == "Target" }).effectiveWeight

        engine.recordVisit("Other")
        engine.recordVisit("Target")
        let dampened = try XCTUnwrap(engine.weightedTransitions(from: "Start").first { $0.targetNode.id == "Target" }).effectiveWeight

        XCTAssertEqual(dampened, baseline * 0.4, accuracy: 0.0001)
    }

    // MARK: – Regel 1: ii-V → V-I-Boost

    func test_iiVBoost_appliesToVToIEdgeAfterIiVTransition() throws {
        let json = """
        {
          "schemaVersion": "1.0", "id": "boost-map", "name": "Boost",
          "layers": [{ "id": "L1", "name": "L1", "relationTypes": ["V-I", "ii-V"] }],
          "nodes": [\(node("Dm7")), \(node("G7")), \(node("Cmaj7"))],
          "edges": [
            { "id": "Dm7-G7", "source": "Dm7", "target": "G7",    "relationTypes": ["ii-V"], "directed": true, "layers": ["L1"], "weight": 1.0 },
            { "id": "G7-Cmaj7", "source": "G7", "target": "Cmaj7","relationTypes": ["V-I"],  "directed": true, "layers": ["L1"], "weight": 1.0 }
          ]
        }
        """
        let map = try decode(json)
        let engine = HarmonyGraphEngine(map: map, initialLayer: "L1")

        let baseline = try XCTUnwrap(engine.weightedTransitions(from: "G7").first { $0.targetNode.id == "Cmaj7" }).effectiveWeight

        engine.recordVisit("Dm7")
        engine.recordVisit("G7")
        let boosted = try XCTUnwrap(engine.weightedTransitions(from: "G7").first { $0.targetNode.id == "Cmaj7" }).effectiveWeight

        XCTAssertEqual(boosted, baseline * 1.5, accuracy: 0.0001)
    }

    // MARK: – Regel 3: Spannungserhalt (Regressionsfall Runde 015)

    private let chainJSON = """
    {
      "schemaVersion": "1.0", "id": "chain-map", "name": "Chain",
      "layers": [{ "id": "L1", "name": "L1", "relationTypes": ["V-I", "ii-V", "commonTone"] }],
      "nodes": [{ "id": "A", "root": 60, "type": "maj7", "function": "tonic", "midiNotes": [60, 64, 67, 71] },
                { "id": "B", "root": 62, "type": "m7",   "function": "subdominant", "midiNotes": [62, 65, 69, 72] },
                { "id": "C", "root": 67, "type": "dom7", "function": "dominant", "midiNotes": [67, 71, 74, 77] },
                { "id": "D", "root": 65, "type": "maj7", "function": "subdominant", "midiNotes": [65, 69, 72, 76] }],
      "edges": [
        { "id": "A-B", "source": "A", "target": "B", "relationTypes": ["V-I"],       "directed": true, "layers": ["L1"], "weight": 1.0 },
        { "id": "B-C", "source": "B", "target": "C", "relationTypes": ["ii-V"],      "directed": true, "layers": ["L1"], "weight": 1.0 },
        { "id": "C-D", "source": "C", "target": "D", "relationTypes": ["commonTone"],"directed": true, "layers": ["L1"], "weight": 1.0 }
      ]
    }
    """

    /// Regression: nur EIN realer vorheriger Übergang (B→C) wurde besucht. Vor der
    /// Korrektur hielt `history` nur 2 Einträge, wodurch `lastEdge()`/`prevEdge()` auf
    /// denselben Übergang B→C zurückfielen und Regel 3 fälschlich bereits hier griff.
    func test_twoStrongTransitions_singleRealTransition_doesNotDoubleCount() throws {
        let map = try decode(chainJSON)
        let engine = HarmonyGraphEngine(map: map, initialLayer: "L1")

        let baseline = try XCTUnwrap(engine.weightedTransitions(from: "C").first { $0.targetNode.id == "D" }).effectiveWeight

        engine.recordVisit("B")
        engine.recordVisit("C")
        let afterSingleTransition = try XCTUnwrap(engine.weightedTransitions(from: "C").first { $0.targetNode.id == "D" }).effectiveWeight

        XCTAssertEqual(afterSingleTransition, baseline, accuracy: 0.0001)
    }

    /// Positivfall: zwei echte, verschiedene starke Übergänge (A→B, B→C) liegen vor →
    /// Regel 3 boostet die anschließende schwache Kante C→D.
    func test_twoStrongTransitions_boostsWeakEdge() throws {
        let map = try decode(chainJSON)
        let engine = HarmonyGraphEngine(map: map, initialLayer: "L1")

        let baseline = try XCTUnwrap(engine.weightedTransitions(from: "C").first { $0.targetNode.id == "D" }).effectiveWeight

        engine.recordVisit("A")
        engine.recordVisit("B")
        engine.recordVisit("C")
        let afterTwoTransitions = try XCTUnwrap(engine.weightedTransitions(from: "C").first { $0.targetNode.id == "D" }).effectiveWeight

        XCTAssertEqual(afterTwoTransitions, baseline * 1.3, accuracy: 0.0001)
    }

    // MARK: – Parallele Kanten / mehrere Layer zwischen demselben Node-Paar

    private func parallelJSON(iiVFirst: Bool) -> String {
        let iiV = """
        { "id": "X-Y-iiV", "source": "X", "target": "Y", "relationTypes": ["ii-V"], "directed": true, "layers": ["L1"], "weight": 0.5 }
        """
        let commonTone = """
        { "id": "X-Y-commonTone", "source": "X", "target": "Y", "relationTypes": ["commonTone"], "directed": true, "layers": ["L1"], "weight": 0.5 }
        """
        let parallelEdges = iiVFirst ? "\(iiV),\n\(commonTone)" : "\(commonTone),\n\(iiV)"
        return """
        {
          "schemaVersion": "1.0", "id": "parallel-map", "name": "Parallel",
          "layers": [{ "id": "L1", "name": "L1", "relationTypes": ["V-I", "ii-V", "commonTone"] }],
          "nodes": [\(node("X")), \(node("Y")), \(node("Z"))],
          "edges": [
            \(parallelEdges),
            { "id": "Y-Z", "source": "Y", "target": "Z", "relationTypes": ["V-I"], "directed": true, "layers": ["L1"], "weight": 1.0 }
          ]
        }
        """
    }

    /// Zwei parallele Kanten zwischen X und Y im selben aktiven Layer (ii-V und
    /// commonTone) müssen unabhängig von ihrer Reihenfolge in `map.edges` zum selben
    /// Ergebnis führen — die Vereinigung ihrer relationTypes enthält ii-V so oder so,
    /// eine ordnungsabhängige `first`-Kante könnte je nach Reihenfolge die falsche
    /// (commonTone) treffen und den Boost verpassen.
    func test_transitionContext_aggregatesParallelEdges_orderIndependent() throws {
        for iiVFirst in [true, false] {
            let map = try decode(parallelJSON(iiVFirst: iiVFirst))
            let engine = HarmonyGraphEngine(map: map, initialLayer: "L1")

            let baseline = try XCTUnwrap(engine.weightedTransitions(from: "Y").first { $0.targetNode.id == "Z" }).effectiveWeight

            engine.recordVisit("X")
            engine.recordVisit("Y")
            let boosted = try XCTUnwrap(engine.weightedTransitions(from: "Y").first { $0.targetNode.id == "Z" }).effectiveWeight

            XCTAssertEqual(boosted, baseline * 1.5, accuracy: 0.0001, "Reihenfolge iiVFirst=\(iiVFirst) muss dasselbe Ergebnis liefern")
        }
    }

    /// X-Y trägt ii-V nur in L2, in L1 nur commonTone. Y-Z (V-I) ist in beiden Layern
    /// aktiv. Der Boost darf nur greifen, wenn der aktive Layer tatsächlich die ii-V-
    /// Kante enthält — Kanten aus anderen Layern dürfen den Kontext nicht verfälschen.
    func test_transitionContext_respectsActiveLayer_ignoresOtherLayerEdges() throws {
        let json = """
        {
          "schemaVersion": "1.0", "id": "cross-layer-map", "name": "CrossLayer",
          "layers": [
            { "id": "L1", "name": "L1", "relationTypes": ["V-I", "commonTone"] },
            { "id": "L2", "name": "L2", "relationTypes": ["V-I", "ii-V"] }
          ],
          "nodes": [\(node("X")), \(node("Y")), \(node("Z"))],
          "edges": [
            { "id": "X-Y-L1", "source": "X", "target": "Y", "relationTypes": ["commonTone"], "directed": true, "layers": ["L1"], "weight": 0.5 },
            { "id": "X-Y-L2", "source": "X", "target": "Y", "relationTypes": ["ii-V"],       "directed": true, "layers": ["L2"], "weight": 0.5 },
            { "id": "Y-Z",    "source": "Y", "target": "Z", "relationTypes": ["V-I"],        "directed": true, "layers": ["L1", "L2"], "weight": 1.0 }
          ]
        }
        """
        let map = try decode(json)

        let engineL1 = HarmonyGraphEngine(map: map, initialLayer: "L1")
        let baselineL1 = try XCTUnwrap(engineL1.weightedTransitions(from: "Y").first { $0.targetNode.id == "Z" }).effectiveWeight
        engineL1.recordVisit("X")
        engineL1.recordVisit("Y")
        let afterL1 = try XCTUnwrap(engineL1.weightedTransitions(from: "Y").first { $0.targetNode.id == "Z" }).effectiveWeight
        XCTAssertEqual(afterL1, baselineL1, accuracy: 0.0001, "L1 hat kein ii-V zwischen X/Y — kein Boost erwartet")

        let engineL2 = HarmonyGraphEngine(map: map, initialLayer: "L2")
        let baselineL2 = try XCTUnwrap(engineL2.weightedTransitions(from: "Y").first { $0.targetNode.id == "Z" }).effectiveWeight
        engineL2.recordVisit("X")
        engineL2.recordVisit("Y")
        let afterL2 = try XCTUnwrap(engineL2.weightedTransitions(from: "Y").first { $0.targetNode.id == "Z" }).effectiveWeight
        XCTAssertEqual(afterL2, baselineL2 * 1.5, accuracy: 0.0001, "L2 hat ii-V zwischen X/Y — Boost erwartet")
    }
}
