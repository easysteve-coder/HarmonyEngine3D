import XCTest
@testable import HarmonyAudioCore

// MARK: – AudioCoreMorphOscillatorTests
//
// S-04a (`.agent_handoff/latest_codex.md`, Runde 049), Scope E. Deckt den
// Morph-Oszillator ab: Pitch-Genauigkeit, Morph-Verhalten, Mip-Auswahl bei
// steigender Frequenz, Determinismus und finite Samples bei Extremwerten.
//
// Pitch-Genauigkeit wird bewusst gegen eine dedizierte, in diesem Testfile
// erzeugte reine Sinustabelle gemessen statt gegen die Factory-Spektren aus
// `AudioCoreWavetableBank`: Letztere enthalten bei den fuer 110/440/1760 Hz
// gewaehlten Mip-Stufen mehrere Harmonische, wodurch eine einfache
// Zero-Crossing-Zaehlung durch legitime zusaetzliche Nulldurchgaenge
// verfaelscht wuerde. Eine reine Sinustabelle isoliert die reine
// Phasenfortschritt-/Pitch-Eigenschaft des Oszillators von der
// Spektralform der Factory-Bank.
//
// Bewusst NICHT getestet hier (Nicht-Scope S-04a): Verwendung in
// `AudioCoreVoice`/`SynthNode`, Source B/Texture (S-04b).

final class AudioCoreMorphOscillatorTests: XCTestCase {

    // MARK: – 1. Pitch-Genauigkeit bei 110/440/1760 Hz

    func test_oscillator_pitchAccuracy_at110And440And1760Hz() {
        let sampleRate = 44_100.0
        let wavetable = makePureSineWavetable(id: "test.pureSine")

        for frequency in [110.0, 440.0, 1760.0] {
            guard let measuredPeriod = measuredPeriodInSamples(frequencyHz: frequency, sampleRate: sampleRate, wavetable: wavetable) else {
                XCTFail("keine Zero-Crossings gefunden bei \(frequency) Hz")
                continue
            }
            let expectedPeriod = sampleRate / frequency
            assertApproximatelyEqual(Float(measuredPeriod), expected: Float(expectedPeriod),
                                     tolerance: Float(expectedPeriod) * 0.01, label: "period@\(frequency)Hz")
        }
    }

    // MARK: – 2. Morph 0/0.5/1 entspricht Spektrum A / Mittelwert / Spektrum B

    func test_oscillator_morphSelectsCorrectSpectrum() {
        let sampleRate = 44_100.0
        let wavetableA = AudioCoreWavetableBank.warmOdd
        let wavetableB = AudioCoreWavetableBank.brightFull
        let testPhase = 0.137 // beliebige, aber feste Phase ungleich 0

        func sample(atMorph morph: Float) -> Float {
            var oscillator = AudioCoreMorphOscillator(sampleRate: sampleRate, wavetableA: wavetableA,
                                                        wavetableB: wavetableB, frequencyHz: 220, morph: morph)
            oscillator.resetPhase(to: testPhase)
            return oscillator.nextSample()
        }

        let mipIndexA = wavetableA.mipLevelIndex(frequencyHz: 220, sampleRate: sampleRate)
        let mipIndexB = wavetableB.mipLevelIndex(frequencyHz: 220, sampleRate: sampleRate)
        let expectedA = wavetableA.sample(phase: testPhase, mipLevelIndex: mipIndexA)
        let expectedB = wavetableB.sample(phase: testPhase, mipLevelIndex: mipIndexB)

        assertApproximatelyEqual(sample(atMorph: 0), expected: expectedA, tolerance: 0.0001, label: "morph=0 == wavetableA")
        assertApproximatelyEqual(sample(atMorph: 1), expected: expectedB, tolerance: 0.0001, label: "morph=1 == wavetableB")

        let expectedHalf = expectedA * 0.5 + expectedB * 0.5
        assertApproximatelyEqual(sample(atMorph: 0.5), expected: expectedHalf, tolerance: 0.0001, label: "morph=0.5 == Mittelwert")
    }

    // MARK: – 3. Mip-Auswahl wechselt bei hoeherer Frequenz in eine niedrigere Harmonischenstufe

    func test_mipSelection_dropsToLowerHarmonicStageAtHigherFrequency() {
        let sampleRate = 44_100.0
        let wavetable = AudioCoreWavetableBank.brightFull

        let lowIndex = wavetable.mipLevelIndex(frequencyHz: 110, sampleRate: sampleRate)
        let midIndex = wavetable.mipLevelIndex(frequencyHz: 440, sampleRate: sampleRate)
        let highIndex = wavetable.mipLevelIndex(frequencyHz: 1760, sampleRate: sampleRate)

        XCTAssertLessThan(lowIndex, midIndex, "hoehere Frequenz sollte eine staerker bandlimitierte (spaetere) Mip-Stufe waehlen")
        XCTAssertLessThan(midIndex, highIndex)

        for (frequency, index) in [(110.0, lowIndex), (440.0, midIndex), (1760.0, highIndex)] {
            let cap = wavetable.mipLevels[index].maxHarmonic
            XCTAssertLessThanOrEqual(Double(cap) * frequency, sampleRate * 0.5,
                                     "gewaehlte Mip-Stufe cap=\(cap) bei \(frequency) Hz ueberschreitet die Nyquist-Grenze")
        }

        // setFrequency() aktualisiert Frequenz UND zwischengespeicherte
        // Mip-Indizes sofort (nicht erst beim naechsten init):
        var oscillator = AudioCoreMorphOscillator(sampleRate: sampleRate, wavetableA: wavetable, wavetableB: wavetable, frequencyHz: 110)
        oscillator.setFrequency(1760)
        XCTAssertEqual(oscillator.frequencyHz, 1760)
    }

    // MARK: – 4. Extreme Parameter produzieren finite Samples

    func test_oscillator_extremeParameters_produceFiniteSamples() {
        let wavetableA = AudioCoreWavetableBank.warmOdd
        let wavetableB = AudioCoreWavetableBank.brightFull

        let extremeCases: [(sampleRate: Double, frequency: Double, morph: Float)] = [
            (44_100, 0, 0),
            (44_100, -100, 0.5),
            (44_100, .infinity, 1),
            (44_100, .nan, 0.5),
            (0, 440, 0.5),
            (-100, 440, 0.5),
            (8_000, 20_000, 2.0),
            (8_000, 20_000, -1.0)
        ]

        for testCase in extremeCases {
            var oscillator = AudioCoreMorphOscillator(sampleRate: testCase.sampleRate, wavetableA: wavetableA,
                                                        wavetableB: wavetableB, frequencyHz: testCase.frequency,
                                                        morph: testCase.morph)
            XCTAssertTrue(oscillator.frequencyHz.isFinite, "frequencyHz sollte trotz Extremwert endlich bleiben: \(testCase)")
            XCTAssertGreaterThanOrEqual(oscillator.morph, 0, "morph sollte auf 0...1 geklemmt sein: \(testCase)")
            XCTAssertLessThanOrEqual(oscillator.morph, 1, "morph sollte auf 0...1 geklemmt sein: \(testCase)")

            let frameCount = 256
            var buffer = [Float](repeating: 0, count: frameCount)
            buffer.withUnsafeMutableBufferPointer { buf in
                _ = oscillator.render(into: buf.baseAddress!, frameCount: frameCount)
            }
            XCTAssertTrue(buffer.allSatisfy { $0.isFinite }, "Extremfall \(testCase) erzeugte nicht-endliche Samples")
        }
    }

    // MARK: – 5. Regression S-04a-fix (Runde 050): resetPhase() mit nicht-endlicher Phase trappt nicht mehr
    //
    // Vor dem Fix haette `resetPhase(to: .nan)`/`resetPhase(to: .infinity)`
    // eine nicht-endliche interne Phase gesetzt, die der naechste
    // `nextSample()`-Aufruf an `AudioCoreWavetable.sample(phase:)`
    // weitergereicht haette — dort waere die `Double -> Int`-Konvertierung
    // fatal getrappt. Diese Tests fuehren genau diesen Pfad Ende-zu-Ende aus.

    func test_resetPhase_withNaN_thenNextSample_doesNotTrapAndReturnsFiniteValue() {
        var oscillator = AudioCoreMorphOscillator(sampleRate: 44_100, wavetableA: AudioCoreWavetableBank.warmOdd,
                                                    wavetableB: AudioCoreWavetableBank.brightFull, frequencyHz: 220)
        oscillator.resetPhase(to: .nan)
        let value = oscillator.nextSample()
        XCTAssertTrue(value.isFinite, "nextSample() nach resetPhase(to: .nan) sollte endlich sein, war \(value)")
    }

    func test_resetPhase_withInfinity_thenNextSample_doesNotTrapAndReturnsFiniteValue() {
        var oscillator = AudioCoreMorphOscillator(sampleRate: 44_100, wavetableA: AudioCoreWavetableBank.warmOdd,
                                                    wavetableB: AudioCoreWavetableBank.brightFull, frequencyHz: 220)
        oscillator.resetPhase(to: .infinity)
        let valuePositive = oscillator.nextSample()
        oscillator.resetPhase(to: -.infinity)
        let valueNegative = oscillator.nextSample()
        XCTAssertTrue(valuePositive.isFinite, "nextSample() nach resetPhase(to: .infinity) sollte endlich sein, war \(valuePositive)")
        XCTAssertTrue(valueNegative.isFinite, "nextSample() nach resetPhase(to: -.infinity) sollte endlich sein, war \(valueNegative)")
    }

    // MARK: – 6. Gleiche Parameter erzeugen deterministisch gleiche Samplefolge

    func test_oscillator_identicalParameters_produceIdenticalSampleSequence() {
        func renderScenario() -> [Float] {
            var oscillator = AudioCoreMorphOscillator(sampleRate: 44_100, wavetableA: AudioCoreWavetableBank.warmOdd,
                                                        wavetableB: AudioCoreWavetableBank.brightFull,
                                                        frequencyHz: 330, morph: 0.35)
            let frameCount = 4_000
            var buffer = [Float](repeating: 0, count: frameCount)
            buffer.withUnsafeMutableBufferPointer { buf in
                _ = oscillator.render(into: buf.baseAddress!, frameCount: frameCount)
            }
            return buffer
        }

        let a = renderScenario()
        let b = renderScenario()
        XCTAssertEqual(a, b, "gleiche Parameter muessen bitgenau identische Samplefolge liefern")
    }

    // MARK: – Helfer

    private func makePureSineWavetable(id: String) -> AudioCoreWavetable {
        let n = 2048
        var samples = [Float](repeating: 0, count: n)
        for i in 0..<n {
            samples[i] = Float(sin(2.0 * Double.pi * Double(i) / Double(n)))
        }
        return AudioCoreWavetable(id: id, tableLength: n,
                                  mipLevels: [AudioCoreWavetableMipLevel(maxHarmonic: 1, samples: samples)])
    }

    /// Rendert ~20 Perioden und misst den mittleren Abstand aufeinander-
    /// folgender positiver Nulldurchgaenge in Samples.
    private func measuredPeriodInSamples(frequencyHz: Double, sampleRate: Double, wavetable: AudioCoreWavetable) -> Double? {
        var oscillator = AudioCoreMorphOscillator(sampleRate: sampleRate, wavetableA: wavetable, wavetableB: wavetable,
                                                    frequencyHz: frequencyHz, morph: 0)
        let expectedPeriod = sampleRate / frequencyHz
        let totalFrames = Int(expectedPeriod * 20) + 100
        var samples = [Float](repeating: 0, count: totalFrames)
        samples.withUnsafeMutableBufferPointer { buf in
            _ = oscillator.render(into: buf.baseAddress!, frameCount: totalFrames)
        }

        var crossings: [Int] = []
        for i in 1..<samples.count {
            if samples[i - 1] <= 0 && samples[i] > 0 {
                crossings.append(i)
            }
        }
        guard crossings.count >= 2 else { return nil }
        let diffs = zip(crossings.dropFirst(), crossings).map { Double($0 - $1) }
        return diffs.reduce(0, +) / Double(diffs.count)
    }

    private func assertApproximatelyEqual(_ value: Float, expected: Float, tolerance: Float,
                                          label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(value, expected, accuracy: max(tolerance, 1e-4),
                       "\(label): \(value) weicht mehr als erwartet von \(expected) ab",
                       file: file, line: line)
    }
}
