import XCTest
import simd
@testable import HarmonyEngine3D

// MARK: – ChordPositionResolutionTests
//
// Runde 038 / V-00b, Fable-5-Review Finding A8: `buildChordPositionMap()`
// (HarmonyScene) entschied bei mehreren sichtbaren Instanzen desselben
// Akkordnamens bisher per Dictionary-Iterationsreihenfolge (prozesszufällig),
// welche Position gewinnt. `resolveChordPositionMap(entries:)` ist die dafür
// extrahierte, SceneKit-freie Kernlogik — direkt ohne HarmonyScene-Instanz
// testbar (siehe InteractionRuntimeTests.swift zur Begründung, warum eine
// direkte HarmonyScene-Instanziierung in Tests vermieden wird).

final class ChordPositionResolutionTests: XCTestCase {

    func test_duplicateNames_resolveDeterministically_byHighestKey() {
        let entries = [
            ChordPositionEntry(key: "chord_0_0_0", name: "Cmaj7", position: simd_float3(1, 0, 0), visible: true),
            ChordPositionEntry(key: "chord_9_9_9", name: "Cmaj7", position: simd_float3(2, 0, 0), visible: true),
            ChordPositionEntry(key: "chord_5_5_5", name: "Cmaj7", position: simd_float3(3, 0, 0), visible: true),
        ]

        let result = resolveChordPositionMap(entries: entries)

        XCTAssertEqual(result["Cmaj7"], simd_float3(2, 0, 0), "Bei mehreren gleichnamigen Instanzen muss die nach key sortiert letzte gewinnen")
    }

    func test_result_isIndependentOfInputArrayOrder() {
        let forward = [
            ChordPositionEntry(key: "a", name: "X", position: simd_float3(1, 0, 0), visible: true),
            ChordPositionEntry(key: "b", name: "X", position: simd_float3(2, 0, 0), visible: true),
            ChordPositionEntry(key: "c", name: "X", position: simd_float3(3, 0, 0), visible: true),
        ]
        let shuffled = [forward[2], forward[0], forward[1]]

        XCTAssertEqual(resolveChordPositionMap(entries: forward)["X"], resolveChordPositionMap(entries: shuffled)["X"],
                        "Das Ergebnis darf nicht von der Eingabe-Array-Reihenfolge abhängen — nur vom sortierten key")
    }

    func test_invisibleEntries_areExcluded() {
        let entries = [
            ChordPositionEntry(key: "a", name: "X", position: simd_float3(1, 0, 0), visible: false),
        ]
        XCTAssertNil(resolveChordPositionMap(entries: entries)["X"])
    }

    func test_distinctNames_allPresentInResult() {
        let entries = [
            ChordPositionEntry(key: "a", name: "Cmaj7", position: simd_float3(1, 0, 0), visible: true),
            ChordPositionEntry(key: "b", name: "G7",    position: simd_float3(2, 0, 0), visible: true),
        ]
        let result = resolveChordPositionMap(entries: entries)

        XCTAssertEqual(result["Cmaj7"], simd_float3(1, 0, 0))
        XCTAssertEqual(result["G7"], simd_float3(2, 0, 0))
    }
}
