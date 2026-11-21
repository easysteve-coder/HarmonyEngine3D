import XCTest
@testable import HarmonyAudioCore

// MARK: – AudioCoreLFOTests
//
// S-05a (`.agent_handoff/latest_codex.md`, Runde 052), Scope B/E: Sine/
// Triangle liefern erwartete Werte/Perioden, Sample-and-Hold bleibt pro
// Zyklus konstant und wechselt deterministisch, geglaetteter Random bleibt
// endlich/begrenzt/deterministisch, Reset/Key-Sync reproduziert Phase- bzw.
// Zufallsfolge, Extremparameter bleiben finite.

final class AudioCoreLFOTests: XCTestCase {

    // MARK: – 6. Sine liefert erwartete Werte/Periode

    func test_sine_reachesExpectedValuesAndPeriod() {
        let sampleRate = 44_100.0
        let frequencyHz: Float = 20.0
        var lfo = AudioCoreLFO(sampleRate: sampleRate, parameters: AudioCoreLFOParameters(shape: .sine, frequencyHz: frequencyHz))

        let expectedPeriod = sampleRate / Double(frequencyHz)

        let first = lfo.nextValue()
        assertApproximatelyEqual(first, expected: 0, tolerance: 1e-4, label: "sine@phase0")
        let second = lfo.nextValue()
        XCTAssertGreaterThan(second, first, "Sine sollte ab Phase 0 zunaechst ansteigen")

        var samples: [Float] = [first, second]
        let renderCount = Int(expectedPeriod * 3.5)
        for _ in 0..<renderCount { samples.append(lfo.nextValue()) }

        var crossings: [Int] = []
        for i in 1..<samples.count where samples[i - 1] < 0 && samples[i] >= 0 {
            crossings.append(i)
        }
        XCTAssertGreaterThanOrEqual(crossings.count, 2, "sollte mindestens zwei aufsteigende Nulldurchgaenge in 3.5 Perioden liefern")
        if crossings.count >= 2 {
            let measuredPeriod = Double(crossings[1] - crossings[0])
            assertApproximatelyEqual(Float(measuredPeriod), expected: Float(expectedPeriod),
                                     tolerance: Float(expectedPeriod) * 0.02, label: "sine-period")
        }

        XCTAssertTrue(samples.allSatisfy { abs($0) <= 1.0001 }, "Sine sollte im Wertebereich [-1, 1] bleiben")
    }

    // MARK: – 6. Triangle liefert erwartete Werte/Periode

    func test_triangle_reachesExpectedPeaksAndPeriod() {
        let sampleRate = 44_100.0
        let frequencyHz: Float = 20.0
        var lfo = AudioCoreLFO(sampleRate: sampleRate, parameters: AudioCoreLFOParameters(shape: .triangle, frequencyHz: frequencyHz))

        let periodSamples = Int((sampleRate / Double(frequencyHz)).rounded())
        var samples: [Float] = []
        for _ in 0..<(periodSamples * 2) { samples.append(lfo.nextValue()) }

        XCTAssertTrue(samples.allSatisfy { $0 >= -1.0001 && $0 <= 1.0001 }, "Triangle sollte im Wertebereich [-1, 1] bleiben")
        assertApproximatelyEqual(samples[0], expected: -1.0, tolerance: 0.01, label: "triangle@phase0 (Minimum)")

        let peakIndex = periodSamples / 2
        assertApproximatelyEqual(samples[peakIndex], expected: 1.0, tolerance: 0.05, label: "triangle@halberPeriode (Maximum)")
    }

    // MARK: – 7. Sample-and-Hold bleibt innerhalb einer Hold-Periode konstant und wechselt deterministisch

    func test_sampleAndHold_staysConstantWithinPeriodAndChangesDeterministically() {
        let sampleRate = 44_100.0
        let frequencyHz: Float = 50.0
        var lfo = AudioCoreLFO(sampleRate: sampleRate, parameters: AudioCoreLFOParameters(shape: .sampleAndHold, frequencyHz: frequencyHz), seed: 42)

        let periodSamples = Int((sampleRate / Double(frequencyHz)).rounded())
        // Sicherheitsabstand gegen Gleitkomma-Rundung genau am Periodenrand.
        let safeWindow = periodSamples - 4

        let firstWindow = (0..<safeWindow).map { _ in lfo.nextValue() }
        XCTAssertTrue(firstWindow.allSatisfy { $0 == firstWindow[0] },
                      "Sample-and-Hold sollte innerhalb einer Hold-Periode konstant bleiben")

        let afterBoundary = (0..<8).map { _ in lfo.nextValue() }
        XCTAssertTrue(afterBoundary.contains { $0 != firstWindow[0] },
                      "nach einer Hold-Periode sollte sich der gehaltene Wert aendern")

        let secondWindow = (0..<safeWindow).map { _ in lfo.nextValue() }
        XCTAssertTrue(secondWindow.allSatisfy { $0 == secondWindow[0] },
                      "Sample-and-Hold sollte auch in der naechsten Hold-Periode konstant bleiben")

        // Determinismus: identischer Seed/identische Parameter erzeugen dieselbe Folge.
        var repeatLFO = AudioCoreLFO(sampleRate: sampleRate, parameters: AudioCoreLFOParameters(shape: .sampleAndHold, frequencyHz: frequencyHz), seed: 42)
        let repeatFirstWindow = (0..<safeWindow).map { _ in repeatLFO.nextValue() }
        XCTAssertEqual(firstWindow, repeatFirstWindow)
    }

    // MARK: – 8. Geglaetteter Random bleibt endlich, begrenzt, deterministisch

    func test_smoothedRandom_staysFiniteBoundedAndDeterministic() {
        let sampleRate = 44_100.0
        var lfoA = AudioCoreLFO(sampleRate: sampleRate,
                                parameters: AudioCoreLFOParameters(shape: .smoothedRandom, frequencyHz: 3.0, smoothingAmount: 0.5), seed: 7)
        var lfoB = AudioCoreLFO(sampleRate: sampleRate,
                                parameters: AudioCoreLFOParameters(shape: .smoothedRandom, frequencyHz: 3.0, smoothingAmount: 0.5), seed: 7)

        let frameCount = 8_000
        let samplesA = (0..<frameCount).map { _ in lfoA.nextValue() }
        let samplesB = (0..<frameCount).map { _ in lfoB.nextValue() }

        XCTAssertEqual(samplesA, samplesB, "gleicher Seed/Parameter muss bitgenau identische Wertfolge liefern")
        XCTAssertTrue(samplesA.allSatisfy { $0.isFinite }, "geglaetteter Random sollte immer endlich bleiben")
        XCTAssertTrue(samplesA.allSatisfy { abs($0) <= 1.0001 }, "geglaetteter Random sollte im Wertebereich [-1, 1] bleiben")

        // "geglaettet": aufeinanderfolgende Werte springen nicht abrupt wie
        // reines Sample-and-Hold, sondern aendern sich hoechstens moderat pro Sample.
        let maxStep = zip(samplesA, samplesA.dropFirst()).map { abs($1 - $0) }.max() ?? 0
        XCTAssertLessThan(maxStep, 0.5, "geglaetteter Random sollte keine abrupten Spruenge zwischen benachbarten Samples erzeugen")
    }

    // MARK: – 9. Reset/Key-Sync reproduziert Phase-/Zufallsfolge

    func test_resetPhase_reproducesSamePhaseDrivenSequenceAsFreshInstance() {
        let sampleRate = 44_100.0
        var fresh = AudioCoreLFO(sampleRate: sampleRate, parameters: AudioCoreLFOParameters(shape: .sine, frequencyHz: 4.0))
        let freshValues = (0..<500).map { _ in fresh.nextValue() }

        var reused = AudioCoreLFO(sampleRate: sampleRate, parameters: AudioCoreLFOParameters(shape: .sine, frequencyHz: 4.0))
        _ = (0..<123).map { _ in reused.nextValue() }
        reused.resetPhase(to: 0)
        let reusedValues = (0..<500).map { _ in reused.nextValue() }

        XCTAssertEqual(freshValues, reusedValues)
    }

    func test_resetRandomState_reproducesSameRandomDrivenSequenceAsFreshInstance() {
        let sampleRate = 44_100.0
        var fresh = AudioCoreLFO(sampleRate: sampleRate, parameters: AudioCoreLFOParameters(shape: .sampleAndHold, frequencyHz: 6.0), seed: 99)
        let freshValues = (0..<400).map { _ in fresh.nextValue() }

        var reused = AudioCoreLFO(sampleRate: sampleRate, parameters: AudioCoreLFOParameters(shape: .sampleAndHold, frequencyHz: 6.0), seed: 1234)
        _ = (0..<77).map { _ in reused.nextValue() }
        reused.resetRandomState(to: 99)
        reused.resetPhase(to: 0)
        let reusedValues = (0..<400).map { _ in reused.nextValue() }

        XCTAssertEqual(freshValues, reusedValues)
    }

    // MARK: – 10. Extremparameter liefern finite Werte

    func test_extremeParameters_produceFiniteValues() {
        let extremeCases: [(shape: AudioCoreLFOShape, frequencyHz: Float, smoothingAmount: Float, seed: UInt64)] = [
            (.sine, .nan, 0.5, 1),
            (.sine, .infinity, 0.5, 1),
            (.sine, -.infinity, 0.5, 1),
            (.triangle, -10, 0.5, 1),
            (.triangle, 1_000_000, 0.5, 1),
            (.sampleAndHold, 0, 0.5, 0),
            (.smoothedRandom, 5, .nan, 1),
            (.smoothedRandom, 5, .infinity, 1),
            (.smoothedRandom, 5, -1_000, 1)
        ]

        for testCase in extremeCases {
            let parameters = AudioCoreLFOParameters(shape: testCase.shape, frequencyHz: testCase.frequencyHz, smoothingAmount: testCase.smoothingAmount)
            var lfo = AudioCoreLFO(sampleRate: 44_100.0, parameters: parameters, seed: testCase.seed)

            XCTAssertGreaterThanOrEqual(lfo.parameters.frequencyHz, 0, "frequencyHz sollte nicht-negativ geklemmt sein: \(testCase)")
            XCTAssertLessThanOrEqual(lfo.parameters.frequencyHz, AudioCoreLFOParameters.maxFrequencyHz, "frequencyHz sollte auf maxFrequencyHz geklemmt sein: \(testCase)")

            let samples = (0..<1_000).map { _ in lfo.nextValue() }
            XCTAssertTrue(samples.allSatisfy { $0.isFinite }, "Extremfall \(testCase) erzeugte einen nicht-endlichen Wert")
            XCTAssertTrue(samples.allSatisfy { abs($0) <= 1.0001 }, "Extremfall \(testCase) verliess den erwarteten Wertebereich [-1, 1]")
        }
    }

    // MARK: – Helper

    private func assertApproximatelyEqual(_ value: Float, expected: Float, tolerance: Float,
                                          label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(value, expected, accuracy: max(tolerance, 1e-4),
                       "\(label): \(value) weicht mehr als erwartet von \(expected) ab",
                       file: file, line: line)
    }
}
