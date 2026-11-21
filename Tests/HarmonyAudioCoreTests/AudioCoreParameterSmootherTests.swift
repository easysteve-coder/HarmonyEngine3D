import XCTest
@testable import HarmonyAudioCore

// MARK: – AudioCoreParameterSmootherTests
//
// S-05b (`.agent_handoff/latest_codex.md`, Runde 053), Scope C/D:
// reproduzierbares Reset/Start, monotone Annaeherung an ein konstantes
// Ziel und finite Ausgabe bei Extremparametern fuer den wiederverwendbaren
// Glaettungsbaustein.

final class AudioCoreParameterSmootherTests: XCTestCase {

    // MARK: – 9. Smoothing startet/resetet reproduzierbar und naehert sich monoton dem Ziel

    func test_setTarget_approachesConstantTargetMonotonically() {
        var smoother = AudioCoreParameterSmoother(sampleRate: 44_100.0, timeMs: 20.0, initialValue: 0)

        var previous: Float = smoother.currentValue
        var reachedCloseToTarget = false
        for _ in 0..<10_000 {
            let next = smoother.setTarget(1.0)
            XCTAssertGreaterThanOrEqual(next, previous, "Annaeherung an ein konstantes Ziel muss monoton sein")
            previous = next
            if abs(next - 1.0) < 1e-2 { reachedCloseToTarget = true }
        }
        XCTAssertTrue(reachedCloseToTarget, "Smoother sollte sich nach ausreichend vielen Schritten dem Ziel annaehern")
    }

    func test_reset_reproducesIdenticalSequenceAsFreshInstance() {
        var fresh = AudioCoreParameterSmoother(sampleRate: 44_100.0, timeMs: 15.0, initialValue: 0)
        let freshValues = (0..<500).map { _ in fresh.setTarget(0.8) }

        var reused = AudioCoreParameterSmoother(sampleRate: 44_100.0, timeMs: 15.0, initialValue: 0)
        _ = (0..<123).map { _ in reused.setTarget(-0.4) }
        reused.reset(to: 0)
        let reusedValues = (0..<500).map { _ in reused.setTarget(0.8) }

        XCTAssertEqual(freshValues, reusedValues)
    }

    func test_reset_setsCurrentValueImmediatelyWithoutRamp() {
        var smoother = AudioCoreParameterSmoother(sampleRate: 44_100.0, timeMs: 50.0, initialValue: 0)
        smoother.reset(to: 0.42)
        XCTAssertEqual(smoother.currentValue, 0.42)
    }

    // MARK: – Zeitkonstante 0 wirkt als sofortiger Sprung

    func test_zeroTimeMs_jumpsImmediatelyToTarget() {
        var smoother = AudioCoreParameterSmoother(sampleRate: 44_100.0, timeMs: 0, initialValue: 0)
        let result = smoother.setTarget(0.75)
        XCTAssertEqual(result, 0.75)
    }

    // MARK: – 10. Extremparameter liefern keine NaN/Infinity

    func test_extremeParameters_produceFiniteValues() {
        let extremeCases: [(sampleRate: Double, timeMs: Float, initial: Float, target: Float)] = [
            (44_100.0, .nan, 0, 1.0),
            (44_100.0, .infinity, 0, 1.0),
            (44_100.0, -10.0, 0, 1.0),
            (44_100.0, 20.0, .nan, 1.0),
            (44_100.0, 20.0, 0, .nan),
            (44_100.0, 20.0, 0, .infinity),
            (44_100.0, 20.0, 0, -.infinity),
            (.nan, 20.0, 0, 1.0),
            (-1.0, 20.0, 0, 1.0),
            (0.0, 20.0, 0, 1.0)
        ]

        for testCase in extremeCases {
            var smoother = AudioCoreParameterSmoother(sampleRate: testCase.sampleRate, timeMs: testCase.timeMs, initialValue: testCase.initial)
            XCTAssertTrue(smoother.currentValue.isFinite, "Extremfall \(testCase) erzeugte einen nicht-endlichen Initialwert")

            for _ in 0..<100 {
                let value = smoother.setTarget(testCase.target)
                XCTAssertTrue(value.isFinite, "Extremfall \(testCase) erzeugte einen nicht-endlichen Wert")
            }
        }
    }
}
