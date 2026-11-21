import XCTest
import simd
import HarmonyShared
@testable import HarmonyEngine3D

// MARK: – RenderCommandQueueTests
//
// Runde 025 / E-05, Scope C: deckt die neue Render-Command-Queue ab, die
// lose Pending-Bool-/Tuple-Gruppen in HarmonyScene.swift ersetzt. Reine
// Value-/Queue-Tests, keine SceneKit-/HarmonyScene-Abhängigkeit.

final class RenderCommandQueueTests: XCTestCase {

    // MARK: – FIFO-Reihenfolge

    func test_drain_returnsCommandsInFIFOOrder() {
        let queue = RenderCommandQueue()
        queue.enqueue(.reload)
        queue.enqueue(.lightingUpdate)
        queue.enqueue(.edgeRebuild)

        let drained = queue.drain()

        XCTAssertEqual(drained.count, 3)
        guard case .reload         = drained[0] else { return XCTFail("erwartet .reload an Position 0") }
        guard case .lightingUpdate = drained[1] else { return XCTFail("erwartet .lightingUpdate an Position 1") }
        guard case .edgeRebuild    = drained[2] else { return XCTFail("erwartet .edgeRebuild an Position 2") }
    }

    // MARK: – Drain leert Queue atomar

    func test_drain_emptiesQueueAtomically() {
        let queue = RenderCommandQueue()
        queue.enqueue(.reload)
        _ = queue.drain()

        XCTAssertTrue(queue.drain().isEmpty)
    }

    func test_drain_onEmptyQueue_returnsEmptyArray() {
        let queue = RenderCommandQueue()
        XCTAssertTrue(queue.drain().isEmpty)
    }

    // MARK: – Netzwerk-Command traegt Network + Curated-Flag + Filename zusammen

    func test_switchNetworkCommand_carriesNetworkCuratedFlagAndFilenameTogether() {
        let network = ChordNetwork(
            chords: [ChordData(name: "Cmaj7", midiNotes: [60, 64, 67, 71])],
            edges:  [EdgeData(source: "Cmaj7", target: "Dm7", weight: 1.0)]
        )
        let queue = RenderCommandQueue()
        queue.enqueue(.switchNetwork(network, isCurated: true, filename: "network_harmony_codex"))

        let drained = queue.drain()
        guard case .switchNetwork(let drainedNetwork, let isCurated, let filename) = drained.first else {
            return XCTFail("erwartet .switchNetwork")
        }
        XCTAssertEqual(drainedNetwork.chords.count, 1)
        XCTAssertEqual(drainedNetwork.chords[0].name, "Cmaj7")
        XCTAssertEqual(drainedNetwork.edges.count, 1)
        XCTAssertTrue(isCurated)
        XCTAssertEqual(filename, "network_harmony_codex")
    }

    // MARK: – CameraReset-Command traegt Position als Value

    func test_cameraResetCommand_carriesPositionAsValue() {
        let queue = RenderCommandQueue()
        let position = simd_float3(10, 20, 30)
        queue.enqueue(.cameraReset(position))

        let drained = queue.drain()
        guard case .cameraReset(let drainedPosition) = drained.first else {
            return XCTFail("erwartet .cameraReset")
        }
        XCTAssertEqual(drainedPosition, position)
    }

    // MARK: – Thread-Sicherheit

    func test_enqueue_isThreadSafe_underConcurrentWriters() {
        let queue = RenderCommandQueue()
        let iterations = 500

        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            queue.enqueue(i % 2 == 0 ? .reload : .edgeRebuild)
        }

        // concurrentPerform blockiert bis alle Iterationen fertig sind -> ein
        // einzelner Drain danach muss exakt alle Commands liefern, keine
        // verlorenen/duplizierten Einträge durch fehlende Synchronisierung.
        XCTAssertEqual(queue.drain().count, iterations)
    }
}
