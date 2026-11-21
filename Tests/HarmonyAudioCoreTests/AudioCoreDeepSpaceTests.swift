import XCTest
@testable import HarmonyAudioCore

// MARK: – AudioCoreDeepSpaceTests
//
// S-08a (`.agent_handoff/latest_codex.md`, Runde 057), Scope D: Tests fuer
// `AudioCoreDeepSpaceEarlyReflections` und `AudioCoreDeepSpaceDiffuser`.
// Deckt die zehn geforderten Punkte ab: finite Impulsantwort (1), endliche/
// begrenzte Impulsantwort-Energie (2), Reset-Determinismus (3),
// nicht-endliche/extreme Parameter (4), Sample-Rate-Grenzen (5), Diffusor-
// Feedback unter Runaway-Grenze (6), deterministisches Pre-Delay-Verhalten
// (7), definierter/stabiler Stereo-Ausgang (8). Punkt 9 (keine Runtime-/
// AudioEngine-/AppSettings-Referenz) und Punkt 10 (`OfflineSynthBaseline
// Tests` unveraendert gruen) werden per Scope-Grep bzw. unveraendertem
// bestehenden Testtarget nachgewiesen, nicht hier.

final class AudioCoreDeepSpaceTests: XCTestCase {

    private let sampleRate: Double = 44_100

    private func impulse(count: Int) -> [Float] {
        var signal = Array(repeating: Float(0), count: count)
        signal[0] = 1.0
        return signal
    }

    private func energy(_ samples: [Float]) -> Float {
        samples.reduce(Float(0)) { $0 + $1 * $1 }
    }

    // Deterministischer FNV-1a-Bit-Checksum ueber die rohen Bitmuster aller
    // Output-Samples -- bewusst keine Swift-`Hasher`-Nutzung (randomisierter
    // Seed pro Prozess), sondern ein fest verdrahteter Algorithmus. Gleiches
    // Muster wie `AudioCoreDeepSpaceFDNTests.fnv1aChecksum(_:)`.
    private func fnv1aChecksum(_ values: [Float]) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        let prime: UInt64 = 0x0000_0100_0000_01b3
        for value in values {
            let bits = UInt64(value.bitPattern)
            for shift: UInt64 in stride(from: 0, to: 32, by: 8) {
                let byte = (bits >> shift) & 0xff
                hash ^= byte
                hash = hash &* prime
            }
        }
        return hash
    }

    // MARK: – 1. Impulsantwort bleibt finite fuer beide Bausteine

    func test_earlyReflections_impulseResponse_isFinite() {
        var er = AudioCoreDeepSpaceEarlyReflections(
            sampleRate: sampleRate,
            parameters: AudioCoreDeepSpaceParameters(preDelaySeconds: 0.02, size: 1.0, earlyReflectionMix: 1.0)
        )
        let response = impulse(count: 20_000).map { er.process($0) }

        for (left, right) in response {
            XCTAssertTrue(left.isFinite)
            XCTAssertTrue(right.isFinite)
        }
    }

    func test_diffuser_impulseResponse_isFinite() {
        var diffuser = AudioCoreDeepSpaceDiffuser(
            sampleRate: sampleRate,
            parameters: AudioCoreDeepSpaceParameters(diffusion: 1.0)
        )
        let response = impulse(count: 20_000).map { diffuser.process(left: $0, right: $0) }

        for (left, right) in response {
            XCTAssertTrue(left.isFinite)
            XCTAssertTrue(right.isFinite)
        }
    }

    // MARK: – 2. Impulsantwort-Energie ist endlich und begrenzt

    func test_earlyReflections_impulseEnergy_isFiniteAndBounded() {
        var er = AudioCoreDeepSpaceEarlyReflections(
            sampleRate: sampleRate,
            parameters: AudioCoreDeepSpaceParameters(preDelaySeconds: 0.1, size: 1.0, earlyReflectionMix: 1.0)
        )
        let response = impulse(count: 20_000).map { er.process($0) }
        let left = response.map { $0.left }
        let right = response.map { $0.right }

        let totalEnergy = energy(left) + energy(right)
        XCTAssertTrue(totalEnergy.isFinite)
        // Sieben Taps mit geometrisch fallendem Gain (Basis 0.28, Faktor 0.7)
        // -> Summe der Tap-Gains liegt deutlich unter 1; die Energie einer
        // Einheits-Impulsantwort bleibt konservativ klein. Runde 064: diese
        // Schranke (< 2.0, tatsaechlich << 0.2) galt nie durch die inzwischen
        // entfernte `±1`-Ausgangsklemmung -- bei Eingangsamplitude 1.0 liegt
        // jeder Einzelwert schon aus der Tap-Gain-Struktur weit unter 1
        // (siehe `test_earlyReflections_stereoOutput_isDefinedAndBounded`),
        // die Klemmung war fuer diesen Test immer inaktiv.
        XCTAssertLessThan(totalEnergy, 2.0)

        // Endliche Impulsantwort: nach dem letzten Tap (size=1 -> Room-Span
        // 150 ms + 100 ms Pre-Delay) darf keine weitere Energie mehr folgen.
        let tailStart = Int((0.1 + 0.15) * sampleRate) + 8
        let tail = Array(response[tailStart...])
        XCTAssertEqual(energy(tail.map { $0.left }) + energy(tail.map { $0.right }), 0.0)
    }

    func test_diffuser_impulseEnergy_isFiniteAndBounded() {
        var diffuser = AudioCoreDeepSpaceDiffuser(
            sampleRate: sampleRate,
            parameters: AudioCoreDeepSpaceParameters(diffusion: 1.0)
        )
        let response = impulse(count: 20_000).map { diffuser.process(left: $0, right: $0) }
        let left = response.map { $0.left }
        let right = response.map { $0.right }

        let totalEnergy = energy(left) + energy(right)
        XCTAssertTrue(totalEnergy.isFinite)
        // Eine Kette idealer Allpass-Stufen ist Unity-Gain und erhaelt die
        // Eingangsenergie exakt (Parseval), statt sie zu verstaerken.
        // Eingangsenergie hier ist 2 x 1.0 (Impuls auf beiden Kanaelen) —
        // enge Toleranz bestaetigt die Allpass-Eigenschaft, nicht nur
        // Abwesenheit einer groben Explosion.
        XCTAssertEqual(totalEnergy, 2.0, accuracy: 0.1)
    }

    // MARK: – 3. Reset reproduziert denselben Output

    func test_earlyReflections_reset_reproducesIdenticalOutput() {
        var er = AudioCoreDeepSpaceEarlyReflections(
            sampleRate: sampleRate,
            parameters: AudioCoreDeepSpaceParameters(preDelaySeconds: 0.03, size: 0.6, earlyReflectionMix: 0.8)
        )
        let input = impulse(count: 2_048)
        let firstRun = input.map { er.process($0) }

        er.reset()
        let secondRun = input.map { er.process($0) }

        XCTAssertEqual(firstRun.map { $0.left }, secondRun.map { $0.left })
        XCTAssertEqual(firstRun.map { $0.right }, secondRun.map { $0.right })
    }

    func test_diffuser_reset_reproducesIdenticalOutput() {
        var diffuser = AudioCoreDeepSpaceDiffuser(
            sampleRate: sampleRate,
            parameters: AudioCoreDeepSpaceParameters(diffusion: 0.9)
        )
        let input = impulse(count: 2_048)
        let firstRun = input.map { diffuser.process(left: $0, right: -$0) }

        diffuser.reset()
        let secondRun = input.map { diffuser.process(left: $0, right: -$0) }

        XCTAssertEqual(firstRun.map { $0.left }, secondRun.map { $0.left })
        XCTAssertEqual(firstRun.map { $0.right }, secondRun.map { $0.right })
    }

    // MARK: – Determinismus zweier identisch konfigurierter Instanzen

    func test_earlyReflections_isDeterministicAcrossInstances() {
        let parameters = AudioCoreDeepSpaceParameters(preDelaySeconds: 0.01, size: 0.4, earlyReflectionMix: 0.9)
        var erA = AudioCoreDeepSpaceEarlyReflections(sampleRate: sampleRate, parameters: parameters)
        var erB = AudioCoreDeepSpaceEarlyReflections(sampleRate: sampleRate, parameters: parameters)

        let input = impulse(count: 1_024)
        let outputA = input.map { erA.process($0) }
        let outputB = input.map { erB.process($0) }

        XCTAssertEqual(outputA.map { $0.left }, outputB.map { $0.left })
        XCTAssertEqual(outputA.map { $0.right }, outputB.map { $0.right })
    }

    // MARK: – 4. Nicht-endliche/extreme Parameter werden defensiv behandelt

    func test_earlyReflections_extremeParameters_stayFinite() {
        let extremeUnit: [Float] = [0.0, 0.5, 1.0, .nan, .infinity, -1.0, 2.0]
        let extremePreDelay: [Float] = [0.0, 0.05, .nan, .infinity, -1.0, 5.0]
        let extremeInputs: [Float] = [0.0, 1.0, -1.0, .nan, .infinity, -.infinity]

        for preDelay in extremePreDelay {
            for size in extremeUnit {
                for mix in extremeUnit {
                    var er = AudioCoreDeepSpaceEarlyReflections(
                        sampleRate: sampleRate,
                        parameters: AudioCoreDeepSpaceParameters(
                            preDelaySeconds: preDelay, size: size, earlyReflectionMix: mix
                        )
                    )
                    for input in extremeInputs {
                        let (left, right) = er.process(input)
                        XCTAssertTrue(left.isFinite,
                                      "ER left nicht-endlich bei preDelay=\(preDelay), size=\(size), mix=\(mix), input=\(input)")
                        XCTAssertTrue(right.isFinite,
                                      "ER right nicht-endlich bei preDelay=\(preDelay), size=\(size), mix=\(mix), input=\(input)")
                    }
                }
            }
        }
    }

    func test_diffuser_extremeParameters_stayFinite() {
        let extremeDiffusion: [Float] = [0.0, 0.5, 1.0, .nan, .infinity, -1.0, 2.0]
        let extremeInputs: [Float] = [0.0, 1.0, -1.0, .nan, .infinity, -.infinity]

        for diffusion in extremeDiffusion {
            var diffuser = AudioCoreDeepSpaceDiffuser(
                sampleRate: sampleRate,
                parameters: AudioCoreDeepSpaceParameters(diffusion: diffusion)
            )
            for left in extremeInputs {
                for right in extremeInputs {
                    let output = diffuser.process(left: left, right: right)
                    XCTAssertTrue(output.left.isFinite,
                                  "Diffuser left nicht-endlich bei diffusion=\(diffusion), left=\(left), right=\(right)")
                    XCTAssertTrue(output.right.isFinite,
                                  "Diffuser right nicht-endlich bei diffusion=\(diffusion), left=\(left), right=\(right)")
                }
            }
        }
    }

    func test_parameters_clampNonFiniteAndOutOfRangeValues() {
        let parameters = AudioCoreDeepSpaceParameters(
            preDelaySeconds: .nan, size: 5.0, earlyReflectionMix: .infinity, diffusion: -3.0
        )
        XCTAssertEqual(parameters.preDelaySeconds, 0.0)
        XCTAssertEqual(parameters.size, 1.0)
        XCTAssertEqual(parameters.earlyReflectionMix, 0.0)
        XCTAssertEqual(parameters.diffusion, 0.0)

        let outOfRange = AudioCoreDeepSpaceParameters(preDelaySeconds: 1.0)
        XCTAssertEqual(outOfRange.preDelaySeconds, AudioCoreDeepSpaceParameters.maxPreDelaySeconds)
    }

    // MARK: – 5. Sample-Rate-Grenzen erzeugen keine ungueltigen Pufferlaengen

    func test_earlyReflections_extremeSampleRates_stayFiniteAndStable() {
        let extremeSampleRates: [Double] = [1.0, 8_000, 44_100, 48_000, 96_000, 192_000, 0.0, -44_100, .nan, .infinity]

        for sr in extremeSampleRates {
            var er = AudioCoreDeepSpaceEarlyReflections(
                sampleRate: sr,
                parameters: AudioCoreDeepSpaceParameters(preDelaySeconds: 0.05, size: 1.0, earlyReflectionMix: 1.0)
            )
            for input: Float in [0.0, 1.0, -1.0, .nan, .infinity] {
                let (left, right) = er.process(input)
                XCTAssertTrue(left.isFinite, "ER left nicht-endlich bei sr=\(sr), input=\(input)")
                XCTAssertTrue(right.isFinite, "ER right nicht-endlich bei sr=\(sr), input=\(input)")
            }

            // prepare(sampleRate:) muss ebenfalls robust neu allozieren.
            er.prepare(sampleRate: sr == 44_100 ? 48_000 : 44_100)
            let (left, right) = er.process(1.0)
            XCTAssertTrue(left.isFinite)
            XCTAssertTrue(right.isFinite)
        }
    }

    func test_diffuser_extremeSampleRates_stayFiniteAndStable() {
        let extremeSampleRates: [Double] = [1.0, 8_000, 44_100, 48_000, 96_000, 192_000, 0.0, -44_100, .nan, .infinity]

        for sr in extremeSampleRates {
            var diffuser = AudioCoreDeepSpaceDiffuser(
                sampleRate: sr,
                parameters: AudioCoreDeepSpaceParameters(diffusion: 1.0)
            )
            for input: Float in [0.0, 1.0, -1.0, .nan, .infinity] {
                let output = diffuser.process(left: input, right: -input)
                XCTAssertTrue(output.left.isFinite, "Diffuser left nicht-endlich bei sr=\(sr), input=\(input)")
                XCTAssertTrue(output.right.isFinite, "Diffuser right nicht-endlich bei sr=\(sr), input=\(input)")
            }

            diffuser.prepare(sampleRate: sr == 44_100 ? 48_000 : 44_100)
            let output = diffuser.process(left: 1.0, right: -1.0)
            XCTAssertTrue(output.left.isFinite)
            XCTAssertTrue(output.right.isFinite)
        }
    }

    // MARK: – 6. Diffusor-Feedback bleibt unter der Runaway-Grenze

    func test_diffuser_maxDiffusion_staysBoundedOverLongRender() {
        var diffuser = AudioCoreDeepSpaceDiffuser(
            sampleRate: sampleRate,
            parameters: AudioCoreDeepSpaceParameters(diffusion: 1.0)
        )

        // Staerkstes plausibles Dauersignal: alternierende Vollausschlaege.
        var maxAbs: Float = 0
        for i in 0..<50_000 {
            let x: Float = (i % 2 == 0) ? 1.0 : -1.0
            let (left, right) = diffuser.process(left: x, right: -x)
            XCTAssertTrue(left.isFinite)
            XCTAssertTrue(right.isFinite)
            maxAbs = max(maxAbs, max(abs(left), abs(right)))
        }

        // Eine Kette stabiler Unity-Gain-Allpass-Stufen (|g| < 1) haelt den
        // Eingangspegel (hier |x| == 1.0) auch ueber sehr lange Renderzeit
        // annaehernd konstant statt anzuwachsen — enge Toleranz bestaetigt
        // die Allpass-Eigenschaft, nicht nur Abwesenheit einer groben
        // Explosion.
        XCTAssertEqual(maxAbs, 1.0, accuracy: 0.2)
    }

    // MARK: – 7. Early-Reflection-Latenzen/Pre-Delay verhalten sich deterministisch

    func test_earlyReflections_preDelay_shiftsFirstTapByExpectedSampleCount() {
        func firstNonZeroIndex(preDelaySeconds: Float) -> Int {
            var er = AudioCoreDeepSpaceEarlyReflections(
                sampleRate: sampleRate,
                parameters: AudioCoreDeepSpaceParameters(
                    preDelaySeconds: preDelaySeconds, size: 0.0, earlyReflectionMix: 1.0
                )
            )
            let response = impulse(count: 4_096).map { er.process($0) }
            return response.firstIndex { abs($0.left) > 0 || abs($0.right) > 0 } ?? -1
        }

        let indexNoPreDelay = firstNonZeroIndex(preDelaySeconds: 0.0)
        let indexWithPreDelay = firstNonZeroIndex(preDelaySeconds: 0.01)

        XCTAssertGreaterThanOrEqual(indexNoPreDelay, 0)
        XCTAssertGreaterThanOrEqual(indexWithPreDelay, 0)

        let expectedShift = Int((0.01 * sampleRate).rounded())
        XCTAssertEqual(indexWithPreDelay - indexNoPreDelay, expectedShift)
    }

    // MARK: – 8. Stereo-Ausgang ist definiert und stabil

    func test_earlyReflections_stereoOutput_isDefinedAndBounded() {
        var er = AudioCoreDeepSpaceEarlyReflections(
            sampleRate: sampleRate,
            parameters: AudioCoreDeepSpaceParameters(preDelaySeconds: 0.01, size: 0.8, earlyReflectionMix: 1.0)
        )
        let response = impulse(count: 4_096).map { er.process($0) }
        let left = response.map { $0.left }
        let right = response.map { $0.right }

        // Das Links-/Rechts-Gewichtungsmuster ist absichtlich asymmetrisch
        // -> die beiden Kanaele duerfen ueber die Impulsantwort nicht
        // identisch sein (definierter Stereo-Ausgang, keine reine Mono-Summe).
        XCTAssertNotEqual(left, right)

        // Runde 064: `process(_:)` klemmt den Ausgang nicht mehr auf `±1`
        // (siehe `AudioCoreDeepSpaceEarlyReflections.swift`-Dateikommentar).
        // Diese Schranke ist jetzt eine echte, aus der DSP-Struktur
        // begruendete Aussage, keine erzwungene Klemmung mehr: ein
        // Einheitsimpuls trifft pro Ausgabesample hoechstens einen einzelnen
        // Tap (die sieben Tap-Verzoegerungen sind bei diesen Parametern
        // paarweise verschieden -- ein Impuls kann sich nicht mit sich
        // selbst ueberlagern). Der staerkste Tap hat Gain `0.28 * mix(<=1)`,
        // das staerkste Links-/Rechts-Gewicht ist `0.85` -> analytisches
        // Maximum `0.28 * 0.85 = 0.238` pro Sample. `0.3` ist eine
        // dokumentierte Sicherheitsmarge oberhalb dieses Maximums, keine
        // aus der alten Klemmung uebernommene Beliebigkeitszahl.
        for value in left + right {
            XCTAssertTrue(value.isFinite)
            XCTAssertLessThanOrEqual(abs(value), 0.3)
        }
    }

    func test_diffuser_stereoOutput_isDefinedAndBounded() {
        var diffuser = AudioCoreDeepSpaceDiffuser(
            sampleRate: sampleRate,
            parameters: AudioCoreDeepSpaceParameters(diffusion: 0.7)
        )
        let response = impulse(count: 4_096).map { diffuser.process(left: $0, right: $0) }
        let left = response.map { $0.left }
        let right = response.map { $0.right }

        // Links/rechts nutzen unterschiedliche Stufen-Verzoegerungszeiten
        // -> trotz identischem Eingang duerfen die Kanaele nicht identisch
        // sein (Stereo-Dekorrelation).
        XCTAssertNotEqual(left, right)

        for value in left + right {
            XCTAssertTrue(value.isFinite)
        }
    }

    // MARK: – S-08a-fix (Finding S-08a-01): setParameters(_:) klemmt/schuetzt
    // auch bei direkter Post-Init-Feldmutation ("public var"-Felder).

    private func mutatedParameters(preDelaySeconds: Float, size: Float, earlyReflectionMix: Float, diffusion: Float) -> AudioCoreDeepSpaceParameters {
        // Baut ueber `init` (bereits geklemmt), mutiert die Felder danach
        // direkt — genau der Pfad, der vor S-08a-fix die Klemmung umging.
        var parameters = AudioCoreDeepSpaceParameters()
        parameters.preDelaySeconds = preDelaySeconds
        parameters.size = size
        parameters.earlyReflectionMix = earlyReflectionMix
        parameters.diffusion = diffusion
        return parameters
    }

    func test_earlyReflections_setParameters_postInitMutation_clampsAndStaysFinite() {
        let nonFiniteAndOutOfRange: [Float] = [.nan, .infinity, -.infinity, -1.0, 5.0]

        for preDelay in nonFiniteAndOutOfRange {
            for size in nonFiniteAndOutOfRange {
                for mix in nonFiniteAndOutOfRange {
                    for diffusion in nonFiniteAndOutOfRange {
                        var er = AudioCoreDeepSpaceEarlyReflections(sampleRate: sampleRate)
                        let mutated = mutatedParameters(
                            preDelaySeconds: preDelay, size: size, earlyReflectionMix: mix, diffusion: diffusion
                        )

                        er.setParameters(mutated) // darf nicht trappen

                        XCTAssertTrue(er.parameters.preDelaySeconds.isFinite)
                        XCTAssertTrue(er.parameters.size.isFinite)
                        XCTAssertTrue(er.parameters.earlyReflectionMix.isFinite)
                        XCTAssertTrue(er.parameters.diffusion.isFinite)
                        XCTAssertGreaterThanOrEqual(er.parameters.preDelaySeconds, 0.0)
                        XCTAssertLessThanOrEqual(er.parameters.preDelaySeconds, AudioCoreDeepSpaceParameters.maxPreDelaySeconds)
                        XCTAssertGreaterThanOrEqual(er.parameters.size, 0.0)
                        XCTAssertLessThanOrEqual(er.parameters.size, 1.0)
                        XCTAssertGreaterThanOrEqual(er.parameters.earlyReflectionMix, 0.0)
                        XCTAssertLessThanOrEqual(er.parameters.earlyReflectionMix, 1.0)
                        XCTAssertGreaterThanOrEqual(er.parameters.diffusion, 0.0)
                        XCTAssertLessThanOrEqual(er.parameters.diffusion, 1.0)

                        let (left, right) = er.process(1.0)
                        XCTAssertTrue(left.isFinite,
                                      "ER left nicht-endlich nach setParameters mit preDelay=\(preDelay), size=\(size), mix=\(mix), diffusion=\(diffusion)")
                        XCTAssertTrue(right.isFinite,
                                      "ER right nicht-endlich nach setParameters mit preDelay=\(preDelay), size=\(size), mix=\(mix), diffusion=\(diffusion)")
                    }
                }
            }
        }
    }

    func test_diffuser_setParameters_postInitMutation_clampsAndStaysFinite() {
        let nonFiniteAndOutOfRange: [Float] = [.nan, .infinity, -.infinity, -1.0, 5.0]

        for preDelay in nonFiniteAndOutOfRange {
            for size in nonFiniteAndOutOfRange {
                for mix in nonFiniteAndOutOfRange {
                    for diffusion in nonFiniteAndOutOfRange {
                        var diffuser = AudioCoreDeepSpaceDiffuser(sampleRate: sampleRate)
                        let mutated = mutatedParameters(
                            preDelaySeconds: preDelay, size: size, earlyReflectionMix: mix, diffusion: diffusion
                        )

                        diffuser.setParameters(mutated) // darf nicht trappen/ausbrechen

                        XCTAssertTrue(diffuser.parameters.diffusion.isFinite)
                        XCTAssertGreaterThanOrEqual(diffuser.parameters.diffusion, 0.0)
                        XCTAssertLessThanOrEqual(diffuser.parameters.diffusion, 1.0)

                        let output = diffuser.process(left: 1.0, right: -1.0)
                        XCTAssertTrue(output.left.isFinite,
                                      "Diffuser left nicht-endlich nach setParameters mit diffusion=\(diffusion)")
                        XCTAssertTrue(output.right.isFinite,
                                      "Diffuser right nicht-endlich nach setParameters mit diffusion=\(diffusion)")
                    }
                }
            }
        }
    }

    func test_earlyReflections_setParameters_verifiedTrapCase_doesNotTrap() {
        // Exakt der von Codex empirisch verifizierte Trap-Fall (Finding
        // S-08a-01): `size = .nan`, `preDelaySeconds = .infinity` ueber
        // `setParameters(_:)` fuehrte vor der Korrektur zu `exit 133`/SIGTRAP.
        var er = AudioCoreDeepSpaceEarlyReflections(sampleRate: sampleRate)
        let mutated = mutatedParameters(preDelaySeconds: .infinity, size: .nan, earlyReflectionMix: 1.0, diffusion: 0.5)

        er.setParameters(mutated)

        let (left, right) = er.process(1.0)
        XCTAssertTrue(left.isFinite)
        XCTAssertTrue(right.isFinite)
    }

    func test_diffuser_setParameters_runawayMutation_staysBoundedOverLongRender() {
        var diffuser = AudioCoreDeepSpaceDiffuser(sampleRate: sampleRate)
        let mutated = mutatedParameters(preDelaySeconds: 0.0, size: 0.5, earlyReflectionMix: 1.0, diffusion: 2.0)
        diffuser.setParameters(mutated)

        var maxAbs: Float = 0
        for i in 0..<50_000 {
            let x: Float = (i % 2 == 0) ? 1.0 : -1.0
            let (left, right) = diffuser.process(left: x, right: -x)
            XCTAssertTrue(left.isFinite)
            XCTAssertTrue(right.isFinite)
            maxAbs = max(maxAbs, max(abs(left), abs(right)))
        }

        XCTAssertEqual(maxAbs, 1.0, accuracy: 0.2)
    }

    func test_diffuser_setParameters_infiniteDiffusionMutation_staysBoundedOverLongRender() {
        var diffuser = AudioCoreDeepSpaceDiffuser(sampleRate: sampleRate)
        let mutated = mutatedParameters(preDelaySeconds: 0.0, size: 0.5, earlyReflectionMix: 1.0, diffusion: .infinity)
        diffuser.setParameters(mutated)

        var maxAbs: Float = 0
        for i in 0..<50_000 {
            let x: Float = (i % 2 == 0) ? 1.0 : -1.0
            let (left, right) = diffuser.process(left: x, right: -x)
            XCTAssertTrue(left.isFinite)
            XCTAssertTrue(right.isFinite)
            maxAbs = max(maxAbs, max(abs(left), abs(right)))
        }

        XCTAssertEqual(maxAbs, 1.0, accuracy: 0.2)
    }

    // MARK: – Nachweis: Verhalten im gueltigen Parameterbereich unveraendert

    func test_earlyReflections_setParameters_validRange_isBitIdenticalToInitOnly() {
        let parameters = AudioCoreDeepSpaceParameters(
            preDelaySeconds: 0.02, size: 0.6, earlyReflectionMix: 0.9, diffusion: 0.4
        )

        var erInitOnly = AudioCoreDeepSpaceEarlyReflections(sampleRate: sampleRate, parameters: parameters)
        var erWithSetParameters = AudioCoreDeepSpaceEarlyReflections(sampleRate: sampleRate)
        erWithSetParameters.setParameters(parameters)

        let input = impulse(count: 4_096)
        let outputInitOnly = input.map { erInitOnly.process($0) }
        let outputWithSetParameters = input.map { erWithSetParameters.process($0) }

        XCTAssertEqual(outputInitOnly.map { $0.left }, outputWithSetParameters.map { $0.left })
        XCTAssertEqual(outputInitOnly.map { $0.right }, outputWithSetParameters.map { $0.right })
    }

    func test_diffuser_setParameters_validRange_isBitIdenticalToInitOnly() {
        let parameters = AudioCoreDeepSpaceParameters(diffusion: 0.6)

        var diffuserInitOnly = AudioCoreDeepSpaceDiffuser(sampleRate: sampleRate, parameters: parameters)
        var diffuserWithSetParameters = AudioCoreDeepSpaceDiffuser(sampleRate: sampleRate)
        diffuserWithSetParameters.setParameters(parameters)

        let input = impulse(count: 4_096)
        let outputInitOnly = input.map { diffuserInitOnly.process(left: $0, right: -$0) }
        let outputWithSetParameters = input.map { diffuserWithSetParameters.process(left: $0, right: -$0) }

        XCTAssertEqual(outputInitOnly.map { $0.left }, outputWithSetParameters.map { $0.left })
        XCTAssertEqual(outputInitOnly.map { $0.right }, outputWithSetParameters.map { $0.right })
    }

    // MARK: – S-08b Teil 1 (Finding S-08a-02): safeSampleRate klemmt jetzt
    // auch nach oben. `AudioCoreDeepSpaceAllpassStage.init(delayMs:
    // sampleRate:)` und `AudioCoreDeepSpaceEarlyReflections.capacity(
    // forSampleRate:)` erhalten nie mehr eine rohe, unbegrenzte Sample Rate
    // -- beide Typen leiten ausschliesslich von der bereits geklemmten
    // `safeSampleRate` ab.

    func test_earlyReflections_extremeUpperSampleRates_stayFiniteAndBounded() {
        let extremeHighSampleRates: [Double] = [1e300, .greatestFiniteMagnitude]

        for sr in extremeHighSampleRates {
            var er = AudioCoreDeepSpaceEarlyReflections(
                sampleRate: sr,
                parameters: AudioCoreDeepSpaceParameters(preDelaySeconds: 0.05, size: 1.0, earlyReflectionMix: 1.0)
            )
            XCTAssertTrue(er.sampleRate.isFinite)
            XCTAssertLessThanOrEqual(er.sampleRate, AudioCoreDeepSpaceParameters.maxSampleRate)

            for input: Float in [0.0, 1.0, -1.0, .nan, .infinity] {
                let (left, right) = er.process(input)
                XCTAssertTrue(left.isFinite, "ER left nicht-endlich bei sr=\(sr), input=\(input)")
                XCTAssertTrue(right.isFinite, "ER right nicht-endlich bei sr=\(sr), input=\(input)")
            }

            er.prepare(sampleRate: sr)
            XCTAssertTrue(er.sampleRate.isFinite)
            let (left, right) = er.process(1.0)
            XCTAssertTrue(left.isFinite)
            XCTAssertTrue(right.isFinite)
        }
    }

    func test_diffuser_extremeUpperSampleRates_stayFiniteAndBounded() {
        let extremeHighSampleRates: [Double] = [1e300, .greatestFiniteMagnitude]

        for sr in extremeHighSampleRates {
            var diffuser = AudioCoreDeepSpaceDiffuser(
                sampleRate: sr,
                parameters: AudioCoreDeepSpaceParameters(diffusion: 1.0)
            )
            XCTAssertTrue(diffuser.sampleRate.isFinite)
            XCTAssertLessThanOrEqual(diffuser.sampleRate, AudioCoreDeepSpaceParameters.maxSampleRate)

            for input: Float in [0.0, 1.0, -1.0, .nan, .infinity] {
                let output = diffuser.process(left: input, right: -input)
                XCTAssertTrue(output.left.isFinite, "Diffuser left nicht-endlich bei sr=\(sr), input=\(input)")
                XCTAssertTrue(output.right.isFinite, "Diffuser right nicht-endlich bei sr=\(sr), input=\(input)")
            }

            diffuser.prepare(sampleRate: sr)
            XCTAssertTrue(diffuser.sampleRate.isFinite)
            let output = diffuser.process(left: 1.0, right: -1.0)
            XCTAssertTrue(output.left.isFinite)
            XCTAssertTrue(output.right.isFinite)
        }
    }

    func test_safeSampleRate_realisticRange_isUnchanged() {
        // Realistischer Bereich 8 kHz...192 kHz liegt weit unter der neuen
        // Obergrenze (1 MHz) -- die neue Klemmung darf hier keine Regression
        // erzeugen (bit-identisches Verhalten zu vor S-08b).
        let realisticSampleRates: [Double] = [8_000, 44_100, 48_000, 96_000, 192_000]

        for sr in realisticSampleRates {
            XCTAssertEqual(AudioCoreDeepSpaceParameters.safeSampleRate(sr), sr)
        }
    }

    func test_safeSampleRate_clampsAboveUpperBound() {
        XCTAssertEqual(AudioCoreDeepSpaceParameters.safeSampleRate(1e300), AudioCoreDeepSpaceParameters.maxSampleRate)
        XCTAssertEqual(AudioCoreDeepSpaceParameters.safeSampleRate(.greatestFiniteMagnitude), AudioCoreDeepSpaceParameters.maxSampleRate)
        XCTAssertEqual(AudioCoreDeepSpaceParameters.safeSampleRate(.infinity), 44_100.0)
        XCTAssertEqual(AudioCoreDeepSpaceParameters.safeSampleRate(.nan), 44_100.0)
        XCTAssertEqual(AudioCoreDeepSpaceParameters.safeSampleRate(0), 44_100.0)
        XCTAssertEqual(AudioCoreDeepSpaceParameters.safeSampleRate(-44_100), 44_100.0)
    }

    // MARK: – Runde 064, Teil 2 (S-08c-Review-Beobachtung): safeSampleRate
    // klemmt jetzt auch nach unten (`minSampleRate` = 100 Hz).

    func test_safeSampleRate_clampsBelowLowerBound() {
        // Genau an der Grenze bleibt der Wert unveraendert.
        XCTAssertEqual(AudioCoreDeepSpaceParameters.safeSampleRate(AudioCoreDeepSpaceParameters.minSampleRate),
                       AudioCoreDeepSpaceParameters.minSampleRate)

        // Darunter -- inklusive des vormals in Tests verwendeten Randfalls
        // `1.0` und des im S-08c-Review vermessenen Problembereichs
        // (< ca. 0,7 Hz) -- wird auf die Untergrenze angehoben.
        for sr: Double in [99.999, 50.0, 1.0, 0.7, 0.1, 0.001] {
            XCTAssertEqual(AudioCoreDeepSpaceParameters.safeSampleRate(sr), AudioCoreDeepSpaceParameters.minSampleRate,
                           "sr=\(sr) haette auf minSampleRate angehoben werden muessen")
        }

        // 0, negativ, NaN, Infinity bleiben unveraendert am bestehenden
        // Fallback (44.100 Hz) -- diese Faelle laufen nie durch den
        // `max(value, minSampleRate)`-Zweig, weil der `guard` sie vorher
        // abfaengt.
        XCTAssertEqual(AudioCoreDeepSpaceParameters.safeSampleRate(0), 44_100.0)
        XCTAssertEqual(AudioCoreDeepSpaceParameters.safeSampleRate(-1.0), 44_100.0)
    }

    func test_safeSampleRate_lowerBound_isBelowUpperBound() {
        // Triviale, aber wichtige Invariante: die beiden Grenzen duerfen sich
        // nie ueberschneiden, sonst waere `safeSampleRate` fuer keinen Wert
        // mehr definiert.
        XCTAssertLessThan(AudioCoreDeepSpaceParameters.minSampleRate, AudioCoreDeepSpaceParameters.maxSampleRate)
    }

    // MARK: – Runde 064, Teil 1 (Stephan-Entscheidung 1): `±1`-Ausgangsklemmung entfernt

    func test_earlyReflections_process_noLongerClampsAboveUnity() {
        var er = AudioCoreDeepSpaceEarlyReflections(
            sampleRate: sampleRate,
            parameters: AudioCoreDeepSpaceParameters(preDelaySeconds: 0.01, size: 0.8, earlyReflectionMix: 1.0)
        )
        // Faktor 5 ueber Vollausschlag -- Supervisor-Messung (Handoff Runde
        // 064): die alte Klemmung griff zwischen ca. +9,5 und +14 dBFS
        // Eingang. Der staerkste Tap (Tap 0, groesster Gain) haette bei
        // Eingang 5.0 einen Wert von 5.0 * 0.238 = 1.19 erzeugt -- vor diesem
        // Fix waere das hart auf 1.0 geklemmt worden. 4096 Samples Fenster,
        // damit Tap 0 (bei preDelay=0.01/size=0.8 ca. 16 ms ~= 712 Samples
        // bei 44,1 kHz) sicher erreicht wird.
        let input: [Float] = [5.0] + Array(repeating: Float(0), count: 4_095)
        let response = input.map { er.process($0) }
        let peak = response.map { max(abs($0.left), abs($0.right)) }.max() ?? 0

        XCTAssertGreaterThan(peak, 1.0, "Ausgang bleibt bei starkem Eingang faelschlich auf 1.0 begrenzt")
        // Erwartetes lineares Verhalten: Spitze = Eingang * analytisches
        // Ein-Tap-Maximum (0.28 * 0.85, siehe
        // `test_earlyReflections_stereoOutput_isDefinedAndBounded`).
        XCTAssertEqual(peak, 5.0 * 0.238, accuracy: 0.01)
    }

    // Referenz-Checksum wurde VOR dieser Aenderung (auf Commit `3c92919`,
    // mit noch aktiver `±1`-Klemmung) ueber exakt diese Konfiguration/
    // Eingabefolge erzeugt -- alle Eingabewerte liegen in `[-1, 1]`, dem
    // Bereich, in dem die alte Klemmung (`max(-1, min(x, 1))`) nachweislich
    // nie gegriffen hat (siehe `test_earlyReflections_stereoOutput_
    // isDefinedAndBounded`: Ausgang bleibt fuer diesen Amplitudenbereich
    // strukturell unter 0.3). Aendert das Entfernen der Klemmung den Output
    // fuer normale Eingaenge auch nur um ein einziges Bit, schlaegt dieser
    // Test fehl.
    private func normalRangeRegressionSamples() -> [Float] {
        let configs: [(preDelay: Float, size: Float, mix: Float, sampleRate: Double)] = [
            (0.0, 0.5, 1.0, 44_100),
            (0.02, 0.6, 0.9, 44_100),
            (0.1, 1.0, 1.0, 48_000),
            (0.05, 0.0, 0.3, 96_000),
        ]
        var allSamples: [Float] = []
        for config in configs {
            var er = AudioCoreDeepSpaceEarlyReflections(
                sampleRate: config.sampleRate,
                parameters: AudioCoreDeepSpaceParameters(
                    preDelaySeconds: config.preDelay, size: config.size, earlyReflectionMix: config.mix
                )
            )
            let input: [Float] = (0..<512).map { i in
                let t = Float(i)
                return sinf(t * 0.13) * (i % 7 == 0 ? 1.0 : 0.4) - (i % 11 == 0 ? 0.999 : 0)
            }
            for x in input {
                let (left, right) = er.process(x)
                allSamples.append(left)
                allSamples.append(right)
            }
        }
        return allSamples
    }

    func test_earlyReflections_normalRangeInput_matchesPreRemovalChecksum() {
        let checksum = fnv1aChecksum(normalRangeRegressionSamples())
        XCTAssertEqual(
            checksum, 0xb69f_219d_2b5a_ae36,
            "Output bei normalen Eingangspegeln weicht vom Pre-Removal-Checksum ab (erzeugt vor Runde 064 auf "
                + "Commit 3c92919, mit noch aktiver ±1-Klemmung) -- das Entfernen der Klemmung hat den Normalfall "
                + "veraendert"
        )
    }
}
