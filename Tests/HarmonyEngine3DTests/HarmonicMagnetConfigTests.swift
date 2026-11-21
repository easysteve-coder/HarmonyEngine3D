import XCTest
import HarmonyShared
@testable import HarmonyEngine3D

// MARK: – HarmonicMagnetConfigTests
//
// Deckt den Harmonic-Magnet-Vertrag ab (Runde 021 / E-02): Preset-Range-
// Mapping, geklammerte intensity/rangeScale, weicher Falloff, isEnabled
// deaktiviert den Magnet-Einfluss ohne die Kandidaten-/Entscheidungs-
// ermittlung zu brechen, RuntimeHarmonik bleibt deterministisch. Reine
// Value-Typ-/RuntimeHarmonik-Tests, keine SceneKit-/FlightController-
// Abhängigkeit — HarmonicMagnetConfig.effectiveRange/falloff sind pure
// statische Funktionen, genau dafür aus der Empfehlung in Scope A extrahiert.

final class HarmonicMagnetConfigTests: XCTestCase {

    // MARK: – Preset-Range-Mapping

    func test_effectiveRange_presetMapping() {
        let config = HarmonicMagnetConfig.defaults
        XCTAssertEqual(HarmonicMagnetConfig.effectiveRange(preset: .strong, config: config), 25)
        XCTAssertEqual(HarmonicMagnetConfig.effectiveRange(preset: .medium, config: config), 15)
        XCTAssertEqual(HarmonicMagnetConfig.effectiveRange(preset: .weak,   config: config), 8)
        // Kein magnetProfile auf der Kante -> wie "medium" behandelt.
        XCTAssertEqual(HarmonicMagnetConfig.effectiveRange(preset: nil, config: config), 15)
    }

    func test_effectiveRange_rangeScale_multipliesAndIsClamped() {
        let doubled = HarmonicMagnetConfig(isEnabled: true, intensity: 1.0, rangeScale: 2.0)
        XCTAssertEqual(HarmonicMagnetConfig.effectiveRange(preset: .medium, config: doubled), 30)

        // rangeScale wird bei der Konstruktion auf 0.25...4.0 geklammert.
        let tooLow  = HarmonicMagnetConfig(isEnabled: true, intensity: 1.0, rangeScale: -5.0)
        let tooHigh = HarmonicMagnetConfig(isEnabled: true, intensity: 1.0, rangeScale: 999.0)
        XCTAssertEqual(tooLow.rangeScale, 0.25)
        XCTAssertEqual(tooHigh.rangeScale, 4.0)
    }

    func test_intensity_isClamped() {
        let tooLow  = HarmonicMagnetConfig(isEnabled: true, intensity: -1.0, rangeScale: 1.0)
        let tooHigh = HarmonicMagnetConfig(isEnabled: true, intensity: 5.0,  rangeScale: 1.0)
        XCTAssertEqual(tooLow.intensity, 0.0)
        XCTAssertEqual(tooHigh.intensity, 1.0)
    }

    // MARK: – Falloff

    func test_falloff_maxAtZeroDistance() {
        XCTAssertEqual(HarmonicMagnetConfig.falloff(distance: 0, range: 15), 1.0)
    }

    func test_falloff_zeroAtRangeBoundaryAndBeyond() {
        XCTAssertEqual(HarmonicMagnetConfig.falloff(distance: 15, range: 15), 0.0)
        XCTAssertEqual(HarmonicMagnetConfig.falloff(distance: 30, range: 15), 0.0)
    }

    func test_falloff_positiveInsideRange() {
        let value = HarmonicMagnetConfig.falloff(distance: 7.5, range: 15)
        XCTAssertGreaterThan(value, 0)
        XCTAssertLessThan(value, 1)
    }

    func test_falloff_neverOutsideZeroToOne() {
        for distance in stride(from: Float(-10), through: Float(50), by: Float(2.5)) {
            let value = HarmonicMagnetConfig.falloff(distance: distance, range: 15)
            XCTAssertGreaterThanOrEqual(value, 0, "distance=\(distance)")
            XCTAssertLessThanOrEqual(value, 1, "distance=\(distance)")
        }
    }

    func test_falloff_zeroRange_returnsZero() {
        XCTAssertEqual(HarmonicMagnetConfig.falloff(distance: 0, range: 0), 0.0)
    }

    // MARK: – RuntimeHarmonik-Integration

    private let magnetMapJSON = """
    {
      "schemaVersion": "1.0", "id": "magnet-map", "name": "Magnet",
      "layers": [{ "id": "L1", "name": "L1", "relationTypes": ["V-I"] }],
      "nodes": [
        { "id": "G7",    "root": 67, "type": "dom7", "function": "dominant", "midiNotes": [67] },
        { "id": "Cmaj7", "root": 60, "type": "maj7", "function": "tonic",    "midiNotes": [60] }
      ],
      "edges": [
        { "id": "G7-Cmaj7", "source": "G7", "target": "Cmaj7", "relationTypes": ["V-I"], "directed": true, "layers": ["L1"], "weight": 1.0, "magnetProfile": { "preset": "strong" } }
      ]
    }
    """

    private func makeSession() throws -> WorldSession {
        let map = try HarmonyMapCodec.decode(from: Data(magnetMapJSON.utf8))
        return try WorldSession(map: map, activeLayer: "L1", seed: 7)
    }

    func test_process_candidateCarriesConfigDerivedEffectiveRange() throws {
        let session = try makeSession()
        let config  = HarmonicMagnetConfig(isEnabled: true, intensity: 1.0, rangeScale: 2.0)
        let decision = session.runtimeHarmonik.process(
            currentChord: "G7",
            localNodes: [LocalNode(id: "n1", chordName: "Cmaj7", position: .zero, distance: 5)],
            magnetConfig: config
        )
        let best = try XCTUnwrap(decision.candidates.first)
        // strong=25 × rangeScale=2.0 = 50
        XCTAssertEqual(best.effectiveRange, 50)
        XCTAssertEqual(decision.magnetConfig.intensity, 1.0)
        XCTAssertTrue(decision.magnetConfig.isEnabled)
    }

    func test_process_disabledConfig_doesNotBreakCandidateOrDecision() throws {
        let session = try makeSession()
        let disabled = HarmonicMagnetConfig(isEnabled: false, intensity: 1.0, rangeScale: 1.0)
        let decision = session.runtimeHarmonik.process(
            currentChord: "G7",
            localNodes: [LocalNode(id: "n1", chordName: "Cmaj7", position: .zero, distance: 5)],
            magnetConfig: disabled
        )
        // Kandidaten-/Entscheidungsermittlung bleibt vollständig intakt — nur die
        // spätere Anwendung in FlightController wird über magnetConfig.isEnabled
        // gegatet, nicht die Ermittlung selbst.
        XCTAssertEqual(decision.strategy, .magnetismCandidate)
        XCTAssertEqual(decision.suggestedChord, "Cmaj7")
        XCTAssertFalse(decision.candidates.isEmpty)
        XCTAssertFalse(decision.magnetConfig.isEnabled)
    }

    func test_process_defaultMagnetConfig_matchesPriorBehavior() throws {
        // Default-Parameter (kein magnetConfig übergeben) verhält sich wie
        // HarmonicMagnetConfig.defaults — Rückwärtskompatibilität für bestehende
        // Aufrufer/Tests aus früheren Runden (z. B. WorldSessionTests aus E-01).
        let session = try makeSession()
        let decision = session.runtimeHarmonik.process(
            currentChord: "G7",
            localNodes: [LocalNode(id: "n1", chordName: "Cmaj7", position: .zero, distance: 5)]
        )
        XCTAssertTrue(decision.magnetConfig.isEnabled)
        XCTAssertEqual(decision.magnetConfig.intensity, 1.0)
        XCTAssertEqual(decision.magnetConfig.rangeScale, 1.0)
    }

    // MARK: – Determinismus

    func test_process_isDeterministic_acrossIdenticalSessions() throws {
        let mapA = try HarmonyMapCodec.decode(from: Data(magnetMapJSON.utf8))
        let mapB = try HarmonyMapCodec.decode(from: Data(magnetMapJSON.utf8))
        let sessionA = try WorldSession(map: mapA, activeLayer: "L1", seed: 99)
        let sessionB = try WorldSession(map: mapB, activeLayer: "L1", seed: 99)
        let config = HarmonicMagnetConfig(isEnabled: true, intensity: 0.5, rangeScale: 1.5)
        let localNodes = [LocalNode(id: "n1", chordName: "Cmaj7", position: .zero, distance: 5)]

        let decisionA = sessionA.runtimeHarmonik.process(currentChord: "G7", localNodes: localNodes, magnetConfig: config)
        let decisionB = sessionB.runtimeHarmonik.process(currentChord: "G7", localNodes: localNodes, magnetConfig: config)

        XCTAssertEqual(decisionA.suggestedChord, decisionB.suggestedChord)
        XCTAssertEqual(decisionA.candidates.map(\.effectiveRange), decisionB.candidates.map(\.effectiveRange))
        XCTAssertEqual(decisionA.candidates.map(\.score), decisionB.candidates.map(\.score))
    }
}
