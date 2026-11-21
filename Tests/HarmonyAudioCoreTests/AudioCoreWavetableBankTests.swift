import XCTest
@testable import HarmonyAudioCore

// MARK: – AudioCoreWavetableBankTests
//
// S-04a (`.agent_handoff/latest_codex.md`, Runde 049), Scope E. Deckt die
// Factory-Wellenform-Bank ab: stabile IDs, power-of-two Tabellenlaenge,
// mehrere Mip-Stufen, Bandlimitierung oberhalb der dokumentierten
// Harmonischen-Grenze und Reproduzierbarkeit der reinen additiven
// Sinus-Synthese.
//
// Bewusst NICHT getestet hier (Nicht-Scope S-04a): Nutzung durch
// `AudioCoreVoice`/`SynthNode`, Source B/Texture-Mixmodi (S-04b).

final class AudioCoreWavetableBankTests: XCTestCase {

    // MARK: – 1. Stabile IDs, power-of-two Tabellenlaenge, mehrere Mip-Stufen

    func test_factoryBank_hasStableIDsPowerOfTwoLengthAndMultipleMipLevels() {
        XCTAssertEqual(AudioCoreWavetableBank.warmOdd.id, "factory.warmOdd")
        XCTAssertEqual(AudioCoreWavetableBank.brightFull.id, "factory.brightFull")
        XCTAssertEqual(AudioCoreWavetableBank.factoryPresets.map { $0.id },
                       ["factory.warmOdd", "factory.brightFull"])

        for wavetable in AudioCoreWavetableBank.factoryPresets {
            XCTAssertGreaterThan(wavetable.tableLength, 0)
            XCTAssertEqual(wavetable.tableLength & (wavetable.tableLength - 1), 0,
                           "\(wavetable.id): tableLength muss power-of-two sein, war \(wavetable.tableLength)")
            XCTAssertGreaterThan(wavetable.mipLevels.count, 1,
                                 "\(wavetable.id): sollte mehrere bandlimitierte Mip-Stufen besitzen")

            for level in wavetable.mipLevels {
                XCTAssertEqual(level.samples.count, wavetable.tableLength,
                               "\(wavetable.id): Mip-Stufe cap=\(level.maxHarmonic) hat falsche Sample-Anzahl")
            }

            let caps = wavetable.mipLevels.map { $0.maxHarmonic }
            XCTAssertEqual(caps, caps.sorted(by: >),
                           "\(wavetable.id): Mip-Stufen sollten absteigend nach maxHarmonic sortiert sein")
            XCTAssertEqual(caps.last, 1, "\(wavetable.id): am staerksten bandlimitierte Stufe sollte nur den Grundton enthalten")
        }
    }

    // MARK: – 2. Mip-Stufen entfernen Harmonische oberhalb der dokumentierten Grenze

    func test_mipLevel_doesNotContainHarmonicsAboveDocumentedMaxHarmonic() {
        for wavetable in AudioCoreWavetableBank.factoryPresets {
            guard let level = wavetable.mipLevels.first(where: { $0.maxHarmonic == 8 }) else {
                XCTFail("\(wavetable.id): Mip-Stufe cap=8 fehlt")
                continue
            }

            // Grundton ist in beiden Factory-Spektren immer Teil der Summe
            // (ungerade Harmonische bei warmOdd, alle bei brightFull) und
            // sollte deutlich messbare Energie zeigen.
            let fundamentalEnergy = abs(sineProjection(level.samples, harmonic: 1))
            XCTAssertGreaterThan(fundamentalEnergy, 0.05,
                                 "\(wavetable.id) cap=8: Grundton sollte deutlich vorhanden sein")

            // Harmonische klar oberhalb der dokumentierten Mip-Grenze duerfen
            // keine messbare Energie besitzen — genau das verhindert
            // Aliasing bei hohen Tonhoehen.
            for harmonic in [9, 10, 16, 32, 64] {
                let projection = abs(sineProjection(level.samples, harmonic: harmonic))
                XCTAssertLessThan(projection, 0.01,
                                  "\(wavetable.id) cap=8: Harmonische \(harmonic) sollte nicht enthalten sein (Bandlimit verletzt), war \(projection)")
            }
        }
    }

    // MARK: – 3. Cap=1 ist in beiden Spektren eine reine, auf Peak 1.0 normierte Sinuswelle
    //
    // Sowohl `warmOdd` (ungerade Harmonische) als auch `brightFull` (alle
    // Harmonische) enthalten bei cap=1 ausschliesslich die Grundharmonische —
    // ein direkter, unabhaengig berechneter Vergleich ist daher moeglich.

    func test_mipLevel_capOne_isPureNormalizedSineWave() {
        for wavetable in AudioCoreWavetableBank.factoryPresets {
            guard let level = wavetable.mipLevels.last else {
                XCTFail("\(wavetable.id): keine Mip-Stufen vorhanden")
                continue
            }
            XCTAssertEqual(level.maxHarmonic, 1)
            let n = wavetable.tableLength
            for i in stride(from: 0, to: n, by: 137) {
                let expected = Float(sin(2.0 * Double.pi * Double(i) / Double(n)))
                assertApproximatelyEqual(level.samples[i], expected: expected, tolerance: 0.01,
                                         label: "\(wavetable.id) cap=1 sample[\(i)]")
            }
        }
    }

    // MARK: – 4. Reproduzierbarkeit: warmOdd cap=8 stimmt mit unabhaengig berechneter Summe ungerader Harmonischer ueberein
    //
    // Beweist Determinismus/Korrektheit gemeinsam: eine unabhaengig (nicht
    // aus Produktcode abgeleitete) berechnete additive Summe muss nach
    // identischer Peak-Normierung exakt denselben Werten entsprechen wie die
    // produktive Tabelle — nur moeglich, wenn die Erzeugung rein
    // mathematisch und ohne Zufall ablaeuft.

    func test_warmOddCapEight_matchesIndependentlyComputedOddHarmonicSum() {
        guard let level = AudioCoreWavetableBank.warmOdd.mipLevels.first(where: { $0.maxHarmonic == 8 }) else {
            XCTFail("cap=8 Mip-Stufe fehlt")
            return
        }
        let n = AudioCoreWavetableBank.tableLength
        var expected = [Double](repeating: 0, count: n)
        for harmonic in [1, 3, 5, 7] {
            let amp = 1.0 / pow(Double(harmonic), 1.5)
            for i in 0..<n {
                expected[i] += amp * sin(2.0 * Double.pi * Double(harmonic) * Double(i) / Double(n))
            }
        }
        let peak = expected.map { abs($0) }.max() ?? 1
        XCTAssertGreaterThan(peak, 0)

        for i in stride(from: 0, to: n, by: 173) {
            let normalizedExpected = Float(expected[i] / peak)
            assertApproximatelyEqual(level.samples[i], expected: normalizedExpected, tolerance: 0.01,
                                     label: "warmOdd cap=8 sample[\(i)]")
        }
    }

    // MARK: – 5. Regression S-04a-fix (Runde 050): nicht-endliche Phase trappt nicht mehr
    //
    // Vor dem Fix lief `phase.truncatingRemainder(dividingBy: 1.0)` bei
    // `.nan`/`.infinity` selbst auf ein nicht-endliches Ergebnis (IEEE 754),
    // wodurch die anschliessende `Double -> Int`-Konvertierung in Swift
    // fatal getrappt haette. Diese Tests fuehren genau diesen Pfad aus —
    // vor dem Fix waere der Testprozess an dieser Stelle abgestuerzt statt
    // fehlzuschlagen.

    func test_sample_withNaNPhase_doesNotTrapAndReturnsFiniteValue() {
        let wavetable = AudioCoreWavetableBank.warmOdd
        let value = wavetable.sample(phase: .nan, mipLevelIndex: 0)
        XCTAssertTrue(value.isFinite, "sample(phase: .nan) sollte einen endlichen Wert liefern, war \(value)")
    }

    func test_sample_withInfinitePhase_doesNotTrapAndReturnsFiniteValue() {
        let wavetable = AudioCoreWavetableBank.brightFull
        let valuePositiveInfinity = wavetable.sample(phase: .infinity, mipLevelIndex: 0)
        let valueNegativeInfinity = wavetable.sample(phase: -.infinity, mipLevelIndex: 0)
        XCTAssertTrue(valuePositiveInfinity.isFinite, "sample(phase: .infinity) sollte einen endlichen Wert liefern, war \(valuePositiveInfinity)")
        XCTAssertTrue(valueNegativeInfinity.isFinite, "sample(phase: -.infinity) sollte einen endlichen Wert liefern, war \(valueNegativeInfinity)")
    }

    // MARK: – Helfer

    /// Diskrete Sinus-Projektion (Amplitudenschaetzung einer Harmonischen)
    /// fuer eine reine additive Sinus-Reihe ohne Cosinus-/DC-Anteil — exakt
    /// die Struktur, die `AudioCoreWavetableBank` erzeugt. Unabhaengig von
    /// Produktcode berechnet, nur ueber das oeffentliche `samples`-Array.
    private func sineProjection(_ samples: [Float], harmonic: Int) -> Double {
        let n = samples.count
        guard n > 0 else { return 0 }
        var sum = 0.0
        let angleStep = 2.0 * Double.pi * Double(harmonic) / Double(n)
        for i in 0..<n {
            sum += Double(samples[i]) * sin(angleStep * Double(i))
        }
        return sum * 2.0 / Double(n)
    }

    private func assertApproximatelyEqual(_ value: Float, expected: Float, tolerance: Float,
                                          label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(value, expected, accuracy: max(tolerance, 1e-4),
                       "\(label): \(value) weicht mehr als erwartet von \(expected) ab",
                       file: file, line: line)
    }
}
