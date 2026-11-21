import XCTest
@testable import HarmonyAudioCore

// MARK: – AudioCoreStateVariableFilterTests
//
// S-06 (`.agent_handoff/latest_codex.md`, Runde 054), Scope E, Punkte 1-5:
// Lowpass/Highpass-Frequenzverhalten, Bandpass-Selektivitaet um den
// Cutoff, Stabilitaet bei Cutoff-/Resonanz-/SampleRate-Extremwerten und
// reproduzierbares Reset-Verhalten.

final class AudioCoreStateVariableFilterTests: XCTestCase {

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

    /// Rechnet eine Ziel-Cutoff-Frequenz in den normierten 0...1-Parameter
    /// um (Umkehrung der logarithmischen 20 Hz...20.000 Hz-Kurve, identisch
    /// zur internen Mappingformel des Filters).
    private func cutoffParameter(forHz hz: Float) -> Float {
        let freqMin: Float = 20.0
        let freqMax: Float = 20_000.0
        return logf(hz / freqMin) / logf(freqMax / freqMin)
    }

    // MARK: – 1. Lowpass laesst tiefe Frequenzen staerker durch als hohe

    func test_lowpass_passesLowFrequencyMoreThanHigh() {
        let parameters = AudioCoreSVFParameters(cutoff: cutoffParameter(forHz: 500), resonance: 0.0)
        var filter = AudioCoreStateVariableFilter(sampleRate: sampleRate, parameters: parameters)

        let low = sineWave(frequency: 100, sampleRate: sampleRate, count: 4096)
        let outputLow = low.map { filter.process($0, mode: .lowpass) }

        filter.reset()
        let high = sineWave(frequency: 8_000, sampleRate: sampleRate, count: 4096)
        let outputHigh = high.map { filter.process($0, mode: .lowpass) }

        XCTAssertGreaterThan(rms(outputLow), rms(outputHigh))
    }

    // MARK: – 2. Highpass laesst hohe Frequenzen staerker durch als tiefe

    func test_highpass_passesHighFrequencyMoreThanLow() {
        let parameters = AudioCoreSVFParameters(cutoff: cutoffParameter(forHz: 500), resonance: 0.0)
        var filter = AudioCoreStateVariableFilter(sampleRate: sampleRate, parameters: parameters)

        let low = sineWave(frequency: 100, sampleRate: sampleRate, count: 4096)
        let outputLow = low.map { filter.process($0, mode: .highpass) }

        filter.reset()
        let high = sineWave(frequency: 8_000, sampleRate: sampleRate, count: 4096)
        let outputHigh = high.map { filter.process($0, mode: .highpass) }

        XCTAssertGreaterThan(rms(outputHigh), rms(outputLow))
    }

    // MARK: – 3. Bandpass hat um Cutoff mehr Energie als deutlich darunter/darueber

    func test_bandpass_hasMoreEnergyNearCutoffThanFarAway() {
        let parameters = AudioCoreSVFParameters(cutoff: cutoffParameter(forHz: 1_000), resonance: 0.5)
        var filter = AudioCoreStateVariableFilter(sampleRate: sampleRate, parameters: parameters)

        let atCutoff = sineWave(frequency: 1_000, sampleRate: sampleRate, count: 4096)
        let outputAtCutoff = atCutoff.map { filter.process($0, mode: .bandpass) }

        filter.reset()
        let belowCutoff = sineWave(frequency: 100, sampleRate: sampleRate, count: 4096)
        let outputBelow = belowCutoff.map { filter.process($0, mode: .bandpass) }

        filter.reset()
        let aboveCutoff = sineWave(frequency: 10_000, sampleRate: sampleRate, count: 4096)
        let outputAbove = aboveCutoff.map { filter.process($0, mode: .bandpass) }

        XCTAssertGreaterThan(rms(outputAtCutoff), rms(outputBelow))
        XCTAssertGreaterThan(rms(outputAtCutoff), rms(outputAbove))
    }

    // MARK: – 4. Filter bleibt bei Cutoff-/Resonanz-/SampleRate-Extremwerten endlich

    func test_extremeParameters_stayFiniteAcrossAllModes() {
        let extremeCutoffs: [Float] = [0.0, 1.0, .nan, .infinity, -1.0, 2.0]
        let extremeResonances: [Float] = [0.0, 1.0, .nan, .infinity, -1.0, 2.0]
        let extremeSampleRates: [Double] = [1.0, 8_000, 44_100, 192_000, 0.0, -44_100, .nan, .infinity]

        for sr in extremeSampleRates {
            for cutoff in extremeCutoffs {
                for resonance in extremeResonances {
                    var filter = AudioCoreStateVariableFilter(
                        sampleRate: sr,
                        parameters: AudioCoreSVFParameters(cutoff: cutoff, resonance: resonance)
                    )
                    for mode: AudioCoreSVFMode in [.lowpass, .bandpass, .highpass] {
                        for input: Float in [0.0, 1.0, -1.0, .nan, .infinity, -.infinity] {
                            let output = filter.process(input, mode: mode)
                            XCTAssertTrue(output.isFinite,
                                          "SVF lieferte nicht-endlich bei sr=\(sr), cutoff=\(cutoff), resonance=\(resonance), mode=\(mode), input=\(input)")
                        }
                    }
                }
            }
        }
    }

    // MARK: – 5. Filter-Reset reproduziert denselben Verlauf

    func test_reset_reproducesIdenticalOutputSequence() {
        let parameters = AudioCoreSVFParameters(cutoff: 0.6, resonance: 0.4)
        var filter = AudioCoreStateVariableFilter(sampleRate: sampleRate, parameters: parameters)

        let input = sineWave(frequency: 300, sampleRate: sampleRate, count: 512)
        let firstRun = input.map { filter.process($0, mode: .bandpass) }

        filter.reset()
        let secondRun = input.map { filter.process($0, mode: .bandpass) }

        XCTAssertEqual(firstRun, secondRun)
    }

    // MARK: – 10. Determinismus gleicher Inputs/Parameter

    func test_process_isDeterministicForIdenticalInputsAndParameters() {
        let parameters = AudioCoreSVFParameters(cutoff: 0.35, resonance: 0.2)
        var filterA = AudioCoreStateVariableFilter(sampleRate: sampleRate, parameters: parameters)
        var filterB = AudioCoreStateVariableFilter(sampleRate: sampleRate, parameters: parameters)

        let input = sineWave(frequency: 220, sampleRate: sampleRate, count: 256)
        let outputA = input.map { filterA.process($0, mode: .lowpass) }
        let outputB = input.map { filterB.process($0, mode: .lowpass) }

        XCTAssertEqual(outputA, outputB)
    }

    // MARK: – 9. Parameter-Clamping fuer nicht-endliche und ausserhalb liegende Werte

    func test_parameters_clampNonFiniteAndOutOfRangeValues() {
        let parameters = AudioCoreSVFParameters(cutoff: .nan, resonance: 5.0)
        XCTAssertEqual(parameters.cutoff, 0.0)
        XCTAssertEqual(parameters.resonance, 1.0)

        // Nicht-endliche Eingaben (NaN/Infinity) fallen defensiv auf 0
        // zurueck, identisch zum bestehenden Clamping-Muster in
        // `AudioCoreMixParameters`/`AudioCoreParameterSmoother`.
        let parametersNegative = AudioCoreSVFParameters(cutoff: -3.0, resonance: .infinity)
        XCTAssertEqual(parametersNegative.cutoff, 0.0)
        XCTAssertEqual(parametersNegative.resonance, 0.0)
    }
}
