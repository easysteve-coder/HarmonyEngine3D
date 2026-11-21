import XCTest
@testable import HarmonyAudioCore

// MARK: – AudioCoreSourceBTests
//
// S-04b (`.agent_handoff/latest_codex.md`, Runde 051), Scope E, Punkte 1-2:
// Transposition/Cent-Skalierung liefert erwartete Frequenzfaktoren; Source B
// hat eine eigene, von Source A unabhaengige Phase und ist deterministisch.

final class AudioCoreSourceBTests: XCTestCase {

    private let sampleRate = 44_100.0
    private var wavetableA: AudioCoreWavetable { AudioCoreWavetableBank.warmOdd }
    private var wavetableB: AudioCoreWavetable { AudioCoreWavetableBank.brightFull }

    // MARK: – 1. Transposition/Cent-Skalierung liefert erwartete Frequenzfaktoren

    func test_transposition_plusOneOctave_doublesFrequency() {
        var source = makeSourceB(baseFrequencyHz: 440.0)
        source.setTransposition(semitones: 12)
        XCTAssertEqual(source.frequencyHz, 880.0, accuracy: 0.01)
    }

    func test_transposition_minusOneOctave_halvesFrequency() {
        var source = makeSourceB(baseFrequencyHz: 440.0)
        source.setTransposition(semitones: -12)
        XCTAssertEqual(source.frequencyHz, 220.0, accuracy: 0.01)
    }

    func test_fineTune_oneHundredCents_equalsOneSemitoneTransposition() {
        var byCents = makeSourceB(baseFrequencyHz: 440.0)
        byCents.setFineTune(cents: 100)

        var bySemitone = makeSourceB(baseFrequencyHz: 440.0)
        bySemitone.setTransposition(semitones: 1)

        XCTAssertEqual(byCents.frequencyHz, bySemitone.frequencyHz, accuracy: 0.01)
    }

    func test_transposition_isClampedToPlusMinusTwentyFourSemitones() {
        var source = makeSourceB(baseFrequencyHz: 440.0)
        source.setTransposition(semitones: 1000)
        XCTAssertEqual(source.transpositionSemitones, 24.0)

        source.setTransposition(semitones: -1000)
        XCTAssertEqual(source.transpositionSemitones, -24.0)
    }

    func test_fineTune_isClampedToPlusMinusOneHundredCents() {
        var source = makeSourceB(baseFrequencyHz: 440.0)
        source.setFineTune(cents: 5_000)
        XCTAssertEqual(source.fineTuneCents, 100.0)

        source.setFineTune(cents: -5_000)
        XCTAssertEqual(source.fineTuneCents, -100.0)
    }

    func test_nonFiniteTranspositionOrFineTune_fallsBackToZero() {
        var source = makeSourceB(baseFrequencyHz: 440.0)
        source.setTransposition(semitones: .nan)
        XCTAssertEqual(source.transpositionSemitones, 0)

        source.setFineTune(cents: .infinity)
        XCTAssertEqual(source.fineTuneCents, 0)
    }

    // MARK: – 2. Eigene Phase, unabhaengig von Source A, deterministisch

    func test_sourceB_hasOwnPhase_independentFromAnotherInstance() {
        var sourceB = makeSourceB(baseFrequencyHz: 220.0)
        sourceB.resetPhase(to: 0.25)

        // Eine zweite, unabhaengige Instanz mit anderer Phase darf die erste
        // nicht beeinflussen (Value-Semantik + eigener gekapselter Oszillator).
        var otherInstance = makeSourceB(baseFrequencyHz: 220.0)
        otherInstance.resetPhase(to: 0.75)
        _ = otherInstance.nextSample()

        let expectedWavetableIndexA = wavetableA.mipLevelIndex(frequencyHz: 220.0, sampleRate: sampleRate)
        let expectedSample = wavetableA.sample(phase: 0.25, mipLevelIndex: expectedWavetableIndexA)
        XCTAssertEqual(sourceB.nextSample(), expectedSample, accuracy: 0.0001)
    }

    func test_sourceB_identicalParameters_produceIdenticalSampleSequence() {
        func renderScenario() -> [Float] {
            var source = makeSourceB(baseFrequencyHz: 330.0)
            source.setTransposition(semitones: 3)
            source.setFineTune(cents: -20)
            source.setMorph(0.6)

            let frameCount = 2_000
            var buffer = [Float](repeating: 0, count: frameCount)
            buffer.withUnsafeMutableBufferPointer { buf in
                _ = source.render(into: buf.baseAddress!, frameCount: frameCount)
            }
            return buffer
        }

        XCTAssertEqual(renderScenario(), renderScenario(),
                        "gleiche Parameter muessen bitgenau identische Samplefolge liefern")
    }

    // MARK: – Extreme Parameter bleiben finite

    func test_sourceB_extremeParameters_produceFiniteSamples() {
        let extremeCases: [(base: Double, semitones: Double, cents: Double)] = [
            (440, .nan, 0),
            (440, 0, .infinity),
            (.infinity, 12, 50),
            (.nan, 0, 0),
            (0, 24, 100),
            (-100, -24, -100)
        ]

        for testCase in extremeCases {
            var source = makeSourceB(baseFrequencyHz: testCase.base)
            source.setTransposition(semitones: testCase.semitones)
            source.setFineTune(cents: testCase.cents)

            XCTAssertTrue(source.frequencyHz.isFinite, "frequencyHz sollte endlich bleiben: \(testCase)")

            let frameCount = 256
            var buffer = [Float](repeating: 0, count: frameCount)
            buffer.withUnsafeMutableBufferPointer { buf in
                _ = source.render(into: buf.baseAddress!, frameCount: frameCount)
            }
            XCTAssertTrue(buffer.allSatisfy { $0.isFinite }, "Extremfall \(testCase) erzeugte nicht-endliche Samples")
        }
    }

    // MARK: – Helfer

    private func makeSourceB(baseFrequencyHz: Double) -> AudioCoreSourceB {
        AudioCoreSourceB(sampleRate: sampleRate, wavetableA: wavetableA, wavetableB: wavetableB,
                          baseFrequencyHz: baseFrequencyHz)
    }
}
