import XCTest
@testable import HarmonyAudioCore

// MARK: – AudioCoreMixerTests
//
// S-04b (`.agent_handoff/latest_codex.md`, Runde 051), Scope E, Punkte 5-7:
// linearer A/B/C-Mix ist deterministisch und clamped Gains; Ringmodulation
// bleibt endlich und innerhalb definierter Pegelgrenze; die reduzierte
// Phasenmodulationsvariante bleibt begrenzt und finite.

final class AudioCoreMixerTests: XCTestCase {

    // MARK: – 5. Linearer Mix ist deterministisch und clamped Gains

    func test_linearMix_combinesThreeSourcesWithGivenGains() {
        let parameters = AudioCoreMixParameters(gainA: 0.5, gainB: 0.25, gainC: 0.1)
        let result = AudioCoreMixer.mix(a: 1.0, b: 1.0, c: 1.0, mode: .linear, parameters: parameters)
        XCTAssertEqual(result, 0.85, accuracy: 0.0001)
    }

    func test_linearMix_isDeterministicForIdenticalInputs() {
        let parameters = AudioCoreMixParameters(gainA: 0.7, gainB: 0.3, gainC: 0.5)
        let first = AudioCoreMixer.mix(a: 0.4, b: -0.2, c: 0.1, mode: .linear, parameters: parameters)
        let second = AudioCoreMixer.mix(a: 0.4, b: -0.2, c: 0.1, mode: .linear, parameters: parameters)
        XCTAssertEqual(first, second)
    }

    func test_mixParameters_gainsAreClampedToZeroToOne() {
        let parameters = AudioCoreMixParameters(gainA: 5.0, gainB: -5.0, gainC: .nan,
                                                  ringModDepth: 2.0, phaseModDepth: -1.0)
        XCTAssertEqual(parameters.gainA, 1.0)
        XCTAssertEqual(parameters.gainB, 0.0)
        XCTAssertEqual(parameters.gainC, 0.0)
        XCTAssertEqual(parameters.ringModDepth, 1.0)
        XCTAssertEqual(parameters.phaseModDepth, 0.0)
    }

    func test_linearMix_withMaximumGains_staysWithinOutputBounds() {
        let parameters = AudioCoreMixParameters(gainA: 1.0, gainB: 1.0, gainC: 1.0)
        let result = AudioCoreMixer.mix(a: 1.0, b: 1.0, c: 1.0, mode: .linear, parameters: parameters)
        XCTAssertTrue(result.isFinite)
        XCTAssertLessThanOrEqual(abs(result), 1.0, "Mixer-Output muss auf [-1, 1] geklemmt bleiben, auch bei Summe > 1")
    }

    // MARK: – 6. Ringmodulation bleibt endlich und innerhalb der Pegelgrenze

    func test_ringModulation_atFullDepth_multipliesAAndB() {
        let parameters = AudioCoreMixParameters(ringModDepth: 1.0)
        let result = AudioCoreMixer.mix(a: 0.5, b: 0.4, c: 0, mode: .ringModulation, parameters: parameters)
        XCTAssertEqual(result, 0.2, accuracy: 0.0001)
    }

    func test_ringModulation_atZeroDepth_passesThroughDryA() {
        let parameters = AudioCoreMixParameters(ringModDepth: 0.0)
        let result = AudioCoreMixer.mix(a: 0.5, b: 0.9, c: 0, mode: .ringModulation, parameters: parameters)
        XCTAssertEqual(result, 0.5, accuracy: 0.0001)
    }

    func test_ringModulation_extremeInputs_stayFiniteAndBounded() {
        let extremeCases: [(a: Float, b: Float, depth: Float)] = [
            (.nan, 1.0, 1.0),
            (1.0, .infinity, 1.0),
            (.infinity, .infinity, 1.0),
            (1.0, 1.0, .nan),
            (-1.0, -1.0, 0.5)
        ]

        for testCase in extremeCases {
            let parameters = AudioCoreMixParameters(ringModDepth: testCase.depth)
            let result = AudioCoreMixer.mix(a: testCase.a, b: testCase.b, c: 0, mode: .ringModulation, parameters: parameters)
            XCTAssertTrue(result.isFinite, "Ringmodulation lieferte nicht-endliches Ergebnis bei \(testCase)")
            XCTAssertLessThanOrEqual(abs(result), 1.0, "Ringmodulation ueberschritt die Pegelgrenze bei \(testCase)")
        }
    }

    // MARK: – 7. Reduzierte Phasenmodulation bleibt begrenzt und finite

    func test_softPhaseModulation_isBoundedByDepth() {
        let parameters = AudioCoreMixParameters(phaseModDepth: 0.3)
        for b: Float in [-1.0, -0.5, 0.0, 0.5, 1.0] {
            let result = AudioCoreMixer.mix(a: 0.0, b: b, c: 0, mode: .softPhaseModulation, parameters: parameters)
            XCTAssertLessThanOrEqual(abs(result), 0.3 + 0.0001, "Phasenmodulation ueberschritt die erwartete Tiefe bei b=\(b)")
        }
    }

    func test_softPhaseModulation_extremeInputs_stayFiniteAndBounded() {
        let extremeCases: [(a: Float, b: Float, depth: Float)] = [
            (.nan, 1.0, 1.0),
            (1.0, .infinity, 1.0),
            (.infinity, .nan, 1.0),
            (1.0, 1.0, .infinity),
            (-1.0, -1.0, 1.0)
        ]

        for testCase in extremeCases {
            let parameters = AudioCoreMixParameters(phaseModDepth: testCase.depth)
            let result = AudioCoreMixer.mix(a: testCase.a, b: testCase.b, c: 0, mode: .softPhaseModulation, parameters: parameters)
            XCTAssertTrue(result.isFinite, "Phasenmodulation lieferte nicht-endliches Ergebnis bei \(testCase)")
            XCTAssertLessThanOrEqual(abs(result), 1.0, "Phasenmodulation ueberschritt die Pegelgrenze bei \(testCase)")
        }
    }

    // MARK: – 9. Nicht-endliche Eingabesamples werden defensiv behandelt

    func test_allModes_withAllNonFiniteInputs_produceFiniteZero() {
        for mode: AudioCoreMixMode in [.linear, .ringModulation, .softPhaseModulation] {
            let parameters = AudioCoreMixParameters(gainA: 1, gainB: 1, gainC: 1, ringModDepth: 1, phaseModDepth: 1)
            let result = AudioCoreMixer.mix(a: .nan, b: .infinity, c: -.infinity, mode: mode, parameters: parameters)
            XCTAssertTrue(result.isFinite, "Modus \(mode) lieferte nicht-endliches Ergebnis bei komplett nicht-endlichen Eingaben")
        }
    }
}
