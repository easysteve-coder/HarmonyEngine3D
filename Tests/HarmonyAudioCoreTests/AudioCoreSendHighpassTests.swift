import XCTest
@testable import HarmonyAudioCore

// MARK: – AudioCoreSendHighpassTests
//
// S-06 (`.agent_handoff/latest_codex.md`, Runde 054), Scope E, Punkt 6 (plus
// 4/5/9/10 fuer diesen Baustein): reduziert tieffrequente Energie deutlich
// staerker als hochfrequente, bleibt bei Extremwerten endlich, Reset
// reproduziert denselben Verlauf, Parameter werden geklemmt, Determinismus.

final class AudioCoreSendHighpassTests: XCTestCase {

    private let sampleRate: Double = 44_100

    private func sineWave(frequency: Float, sampleRate: Double, count: Int) -> [Float] {
        (0..<count).map { i in
            Float(sin(2.0 * Double.pi * Double(frequency) * Double(i) / sampleRate))
        }
    }

    private func rms(_ samples: [Float]) -> Float {
        let sumSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return sqrtf(sumSquares / Float(samples.count))
    }

    // MARK: – 6. Reduziert tieffrequente Energie deutlich staerker als hochfrequente

    func test_process_attenuatesLowFrequencyMoreThanHighFrequency() {
        let parameters = AudioCoreSendHighpassParameters(cutoff: 0.5)
        var filter = AudioCoreSendHighpass(sampleRate: sampleRate, parameters: parameters)

        let low = sineWave(frequency: 40, sampleRate: sampleRate, count: 4096)
        let outputLow = low.map { filter.process($0) }

        filter.reset()
        let high = sineWave(frequency: 5_000, sampleRate: sampleRate, count: 4096)
        let outputHigh = high.map { filter.process($0) }

        XCTAssertLessThan(rms(outputLow), rms(outputHigh))
        // Hochfrequenter Anteil soll nahezu unveraendert durchgelassen werden.
        XCTAssertEqual(rms(outputHigh), rms(high), accuracy: 0.05)
    }

    // MARK: – 4. Filter bleibt bei Cutoff-/SampleRate-Extremwerten endlich

    func test_extremeParameters_stayFinite() {
        let extremeCutoffs: [Float] = [0.0, 1.0, .nan, .infinity, -1.0, 2.0]
        let extremeSampleRates: [Double] = [1.0, 8_000, 44_100, 192_000, 0.0, -44_100, .nan, .infinity]

        for sr in extremeSampleRates {
            for cutoff in extremeCutoffs {
                var filter = AudioCoreSendHighpass(
                    sampleRate: sr,
                    parameters: AudioCoreSendHighpassParameters(cutoff: cutoff)
                )
                for input: Float in [0.0, 1.0, -1.0, .nan, .infinity, -.infinity] {
                    let output = filter.process(input)
                    XCTAssertTrue(output.isFinite,
                                  "Send-Highpass lieferte nicht-endlich bei sr=\(sr), cutoff=\(cutoff), input=\(input)")
                }
            }
        }
    }

    // MARK: – 5. Reset reproduziert denselben Verlauf

    func test_reset_reproducesIdenticalOutputSequence() {
        let parameters = AudioCoreSendHighpassParameters(cutoff: 0.3)
        var filter = AudioCoreSendHighpass(sampleRate: sampleRate, parameters: parameters)

        let input = sineWave(frequency: 60, sampleRate: sampleRate, count: 512)
        let firstRun = input.map { filter.process($0) }

        filter.reset()
        let secondRun = input.map { filter.process($0) }

        XCTAssertEqual(firstRun, secondRun)
    }

    // MARK: – 9. Parameter-Clamping fuer nicht-endliche und ausserhalb liegende Werte

    func test_parameters_clampNonFiniteAndOutOfRangeValues() {
        let parameters = AudioCoreSendHighpassParameters(cutoff: .nan)
        XCTAssertEqual(parameters.cutoff, 0.0)

        let parametersOutOfRange = AudioCoreSendHighpassParameters(cutoff: 5.0)
        XCTAssertEqual(parametersOutOfRange.cutoff, 1.0)
    }

    // MARK: – 10. Determinismus gleicher Inputs/Parameter

    func test_process_isDeterministicForIdenticalInputsAndParameters() {
        let parameters = AudioCoreSendHighpassParameters(cutoff: 0.4)
        var filterA = AudioCoreSendHighpass(sampleRate: sampleRate, parameters: parameters)
        var filterB = AudioCoreSendHighpass(sampleRate: sampleRate, parameters: parameters)

        let input = sineWave(frequency: 150, sampleRate: sampleRate, count: 256)
        let outputA = input.map { filterA.process($0) }
        let outputB = input.map { filterB.process($0) }

        XCTAssertEqual(outputA, outputB)
    }
}
