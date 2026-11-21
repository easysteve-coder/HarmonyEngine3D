import XCTest
import simd
@testable import HarmonyShared

// MARK: – AutopilotEngineTests
//
// Runde 038 / V-00b, Fable-5-Review Finding A3: die gewichtete
// Kantenauswahl in `update(...)` nutzte bisher den globalen, unseeded
// System-RNG (`Float.random`). Diese Tests belegen, dass die Auswahl jetzt
// über `SeededRNG` deterministisch reproduzierbar ist.

final class AutopilotEngineTests: XCTestCase {

    // MARK: – Fixture: ein Knoten mit drei gleich gewichteten Nachbarn

    private func makeEdges() -> [EdgeData] {
        [
            EdgeData(source: "A", target: "B", weight: 1.0),
            EdgeData(source: "A", target: "C", weight: 1.0),
            EdgeData(source: "A", target: "D", weight: 1.0),
            EdgeData(source: "B", target: "A", weight: 1.0),
            EdgeData(source: "C", target: "A", weight: 1.0),
            EdgeData(source: "D", target: "A", weight: 1.0),
        ]
    }

    private func makePositions() -> [String: simd_float3] {
        [
            "A": simd_float3(0, 0, 0),
            "B": simd_float3(100, 0, 0),
            "C": simd_float3(0, 100, 0),
            "D": simd_float3(0, 0, 100),
        ]
    }

    /// Simuliert `count` Autopilot-Schritte: die Kamera "teleportiert" bei
    /// jedem Aufruf exakt auf das zuletzt gewählte Ziel, damit `update(...)`
    /// sofort als "angekommen" gilt und den nächsten Kandidaten wählt.
    private func targetSequence(seed: UInt64, count: Int) -> [String] {
        var engine = AutopilotEngine(seed: seed)
        let edges = makeEdges()
        let positions = makePositions()

        var names: [String] = []
        for _ in 0..<count {
            let camPos = engine.targetPosition ?? .zero
            _ = engine.update(cameraPos: camPos, passThruRadius: 5, maxReach: 500, edges: edges, positions: positions)
            names.append(engine.targetChordName)
        }
        return names
    }

    // MARK: – Determinismus

    func test_update_sameSeed_producesIdenticalTargetSequence() {
        let seqA = targetSequence(seed: 42, count: 20)
        let seqB = targetSequence(seed: 42, count: 20)

        XCTAssertFalse(seqA.isEmpty)
        XCTAssertEqual(seqA, seqB, "Gleicher Seed muss dieselbe Zielsequenz liefern")
    }

    func test_update_differentSeed_canProduceDifferentTargetSequence() {
        let seqA = targetSequence(seed: 1, count: 20)
        let seqB = targetSequence(seed: 2, count: 20)

        XCTAssertNotEqual(seqA, seqB, "Unterschiedliche Seeds sollten bei gleich gewichteten Kandidaten unterschiedliche Zielsequenzen liefern")
    }

    // MARK: – Default-Init bleibt deterministisch

    func test_defaultInit_isDeterministicAcrossInstances() {
        // AutopilotEngine() (Bestandsaufrufer, HarmonyScene.swift) nutzt den
        // Default-Seed — zwei unabhaengig konstruierte Instanzen ohne
        // expliziten Seed muessen trotzdem identisch reagieren.
        var a = AutopilotEngine()
        var b = AutopilotEngine()
        let edges = makeEdges()
        let positions = makePositions()

        var seqA: [String] = []
        var seqB: [String] = []
        for _ in 0..<15 {
            _ = a.update(cameraPos: a.targetPosition ?? .zero, passThruRadius: 5, maxReach: 500, edges: edges, positions: positions)
            _ = b.update(cameraPos: b.targetPosition ?? .zero, passThruRadius: 5, maxReach: 500, edges: edges, positions: positions)
            seqA.append(a.targetChordName)
            seqB.append(b.targetChordName)
        }
        XCTAssertEqual(seqA, seqB)
    }

    // MARK: – Bestehendes Verhalten bleibt unveraendert

    func test_update_emptyPositions_returnsFalse() {
        var engine = AutopilotEngine(seed: 1)
        let result = engine.update(cameraPos: .zero, passThruRadius: 5, maxReach: 500, edges: [], positions: [:])
        XCTAssertFalse(result)
    }

    func test_update_choosesOnlyAmongWeightedEdgeCandidates() {
        var engine = AutopilotEngine(seed: 3)
        let edges = makeEdges()
        let positions = makePositions()
        let validNames = Set(positions.keys)

        for _ in 0..<20 {
            _ = engine.update(cameraPos: engine.targetPosition ?? .zero, passThruRadius: 5, maxReach: 500, edges: edges, positions: positions)
            XCTAssertTrue(validNames.contains(engine.targetChordName))
        }
    }
}
