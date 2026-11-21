import XCTest
@testable import HarmonyAudioCore

// MARK: – AudioCoreDeepSpaceFDNTests
//
// S-08b (`.agent_handoff/latest_codex.md`, Runde 059), Teil 2: Tests fuer
// `AudioCoreDeepSpaceFDNTail` und `AudioCoreDeepSpaceFDNMatrix`. Deckt die
// elf im Auftrag geforderten Stabilitaetsgates ab, plus die funktionale
// "teilerfremde Laengen"-Anforderung aus Abschnitt 7.3.

final class AudioCoreDeepSpaceFDNTests: XCTestCase {

    private let sampleRate: Double = 44_100

    private func impulse(count: Int) -> [Float] {
        var signal = Array(repeating: Float(0), count: count)
        signal[0] = 1.0
        return signal
    }

    private func energy(_ samples: ArraySlice<Float>) -> Float {
        samples.reduce(Float(0)) { $0 + $1 * $1 }
    }

    private func blockEnergies(_ samples: [Float], blockSize: Int) -> [Float] {
        stride(from: 0, to: samples.count, by: blockSize).map { start in
            let end = min(start + blockSize, samples.count)
            return energy(samples[start..<end])
        }
    }

    private func gcd(_ a: Int, _ b: Int) -> Int {
        var x = a, y = b
        while y != 0 { (x, y) = (y, x % y) }
        return x
    }

    // Deterministischer FNV-1a-Bit-Checksum ueber die rohen Bitmuster aller
    // Output-Samples -- bewusst keine Swift-`Hasher`-Nutzung (randomisierter
    // Seed pro Prozess), sondern ein fest verdrahteter Algorithmus. Jede
    // einzelne Bit-Abweichung in irgendeinem Sample aendert die Pruefsumme.
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

    // MARK: – 1. Impulsantwort bleibt finite ueber langen Offline-Render, auch bei maximalem decay

    func test_impulseResponse_isFiniteOverLongRender_atMaxDecay() {
        var tail = AudioCoreDeepSpaceFDNTail(
            sampleRate: sampleRate,
            parameters: AudioCoreDeepSpaceFDNParameters(size: 1.0, decay: 1.0, damping: 0.5)
        )
        let response = impulse(count: Int(sampleRate * 6)).map { tail.process(left: $0, right: $0) }
        for (left, right) in response {
            XCTAssertTrue(left.isFinite)
            XCTAssertTrue(right.isFinite)
        }
    }

    // MARK: – 2. Fensterenergie faellt monoton ab, kein Energiewachstum

    func test_windowedEnergy_decaysMonotonically_atMaxDecayAndSize() {
        var tail = AudioCoreDeepSpaceFDNTail(
            sampleRate: sampleRate,
            parameters: AudioCoreDeepSpaceFDNParameters(size: 1.0, decay: 1.0, damping: 0.0)
        )
        let renderLength = Int(sampleRate * 6)
        let response = impulse(count: renderLength).map { tail.process(left: $0, right: $0) }
        let mono = response.map { $0.left + $0.right }

        let blockSize = Int(sampleRate * 0.5) // 0.5 s -- grob genug, um
        // kurzzeitige Interferenz-("Flutter"-)Effekte zwischen den acht
        // Linien auszumitteln, fein genug fuer einen echten Zeittrend.
        let blocks = blockEnergies(mono, blockSize: blockSize)

        for i in 1..<(blocks.count - 1) {
            XCTAssertLessThanOrEqual(blocks[i + 1], blocks[i] * 1.03,
                                      "Energie waechst zwischen Block \(i) und \(i+1): \(blocks[i]) -> \(blocks[i+1])")
        }

        XCTAssertLessThan(blocks.last!, blocks[1] * 0.7,
                           "Spaete Blockenergie ist nicht deutlich kleiner als frueher -- kein messbarer Abfall")
    }

    // MARK: – 3. Feedback-Matrix ist energieerhaltend (isoliert getestet)

    func test_matrix_preservesEnergy_forDeterministicInputVectors() {
        func norm(_ v: [Float]) -> Float { v.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot() }

        let vectors: [[Float]] = [
            [1, 0, 0, 0, 0, 0, 0, 0],
            [1, 1, 1, 1, 1, 1, 1, 1],
            [1, -1, 2, -2, 0.5, -0.5, 3, -3],
            [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8],
            [-4, 2, -1, 7, -3, 0, 5, -6],
        ]

        for vector in vectors {
            let output = AudioCoreDeepSpaceFDNMatrix.apply(vector)
            XCTAssertEqual(output.count, vector.count)
            XCTAssertEqual(norm(output), norm(vector), accuracy: 0.001,
                            "Matrix nicht energieerhaltend fuer \(vector)")
        }
    }

    func test_matrix_isOrthonormal_columnsAreUnitAndOrthogonal() {
        // Direkter Konstruktionsnachweis: jeder Standardbasisvektor ergibt
        // durch die Matrix die entsprechende Spalte von M. Norm 1 je Spalte
        // und paarweise Orthogonalitaet zwischen allen Spalten ist die
        // eigentliche Aussage "orthonormal", staerker als Energieerhaltung
        // fuer einzelne Testvektoren.
        var columns: [[Float]] = []
        for i in 0..<AudioCoreDeepSpaceFDNMatrix.order {
            var basis = Array(repeating: Float(0), count: AudioCoreDeepSpaceFDNMatrix.order)
            basis[i] = 1
            columns.append(AudioCoreDeepSpaceFDNMatrix.apply(basis))
        }

        for i in 0..<columns.count {
            let normSquared = columns[i].reduce(Float(0)) { $0 + $1 * $1 }
            XCTAssertEqual(normSquared, 1.0, accuracy: 0.001, "Spalte \(i) nicht normiert")

            for j in 0..<columns.count where j != i {
                let dot = zip(columns[i], columns[j]).reduce(Float(0)) { $0 + $1.0 * $1.1 }
                XCTAssertEqual(dot, 0.0, accuracy: 0.001, "Spalten \(i)/\(j) nicht orthogonal")
            }
        }
    }

    func test_matrix_mismatchedSize_returnsInputUnchanged() {
        let malformed: [Float] = [1, 2, 3]
        XCTAssertEqual(AudioCoreDeepSpaceFDNMatrix.apply(malformed), malformed)
    }

    // MARK: – 4. Selbstoszillationsgrenze: klingt auch bei max decay/size nach Abschalten ab

    func test_selfOscillation_decaysAfterInputStops_atMaxParameters() {
        var tail = AudioCoreDeepSpaceFDNTail(
            sampleRate: sampleRate,
            parameters: AudioCoreDeepSpaceFDNParameters(size: 1.0, decay: 1.0, damping: 0.0)
        )
        var burst: [Float] = impulse(count: 2_000)
        burst.append(contentsOf: Array(repeating: Float(0), count: Int(sampleRate * 5)))
        let response = burst.map { tail.process(left: $0, right: $0) }
        let mono = response.map { $0.left + $0.right }

        let blockSize = Int(sampleRate * 0.5)
        let blocks = blockEnergies(mono, blockSize: blockSize)

        let earlyBlock = blocks[1] // nach Impulsaufbau, vor langem Abklingen
        let lateBlock = blocks.last!
        XCTAssertTrue(earlyBlock.isFinite)
        XCTAssertTrue(lateBlock.isFinite)
        XCTAssertLessThan(lateBlock, earlyBlock,
                           "Tail klingt bei maximalem decay/size nicht ab: frueh=\(earlyBlock), spaet=\(lateBlock)")
    }

    func test_selfOscillation_decaysAfterInputStops_atShortestLinesAndLongestDecay() {
        // Der rechnerisch ungruenstigste Fall fuer die Naehe zu 1 ist NICHT
        // size=1 (das Gate oben), sondern size=0: kuerzere Linien haben pro
        // Sekunde mehr Umlaeufe, also einen groesseren Rundlauf-Gain je
        // Umlauf fuer dasselbe RT60 (`g_i = 10^(-3 * L_i_seconds / RT60)`
        // naehert sich 1 fuer kleines `L_i_seconds`). Auch dieser
        // rechnerisch engste Fall muss nachweislich abklingen.
        var tail = AudioCoreDeepSpaceFDNTail(
            sampleRate: sampleRate,
            parameters: AudioCoreDeepSpaceFDNParameters(size: 0.0, decay: 1.0, damping: 0.0)
        )
        var burst: [Float] = impulse(count: 500)
        burst.append(contentsOf: Array(repeating: Float(0), count: Int(sampleRate * 5)))
        let response = burst.map { tail.process(left: $0, right: $0) }
        let mono = response.map { $0.left + $0.right }

        let blockSize = Int(sampleRate * 0.5)
        let blocks = blockEnergies(mono, blockSize: blockSize)

        let earlyBlock = blocks[1]
        let lateBlock = blocks.last!
        XCTAssertTrue(earlyBlock.isFinite)
        XCTAssertTrue(lateBlock.isFinite)
        XCTAssertLessThan(lateBlock, earlyBlock,
                           "Tail klingt bei kuerzesten Linien/max. decay nicht ab: frueh=\(earlyBlock), spaet=\(lateBlock)")
    }

    // MARK: – 5. Reset-Determinismus, bit-exakt

    func test_reset_reproducesIdenticalOutput_bitExact() {
        var tail = AudioCoreDeepSpaceFDNTail(
            sampleRate: sampleRate,
            parameters: AudioCoreDeepSpaceFDNParameters(size: 0.6, decay: 0.7, damping: 0.4)
        )
        let input = impulse(count: 8_192)
        let firstRun = input.map { tail.process(left: $0, right: -$0) }

        tail.reset()
        let secondRun = input.map { tail.process(left: $0, right: -$0) }

        XCTAssertEqual(firstRun.map { $0.left }, secondRun.map { $0.left })
        XCTAssertEqual(firstRun.map { $0.right }, secondRun.map { $0.right })
    }

    func test_isDeterministicAcrossInstances() {
        let parameters = AudioCoreDeepSpaceFDNParameters(size: 0.4, decay: 0.5, damping: 0.6)
        var tailA = AudioCoreDeepSpaceFDNTail(sampleRate: sampleRate, parameters: parameters)
        var tailB = AudioCoreDeepSpaceFDNTail(sampleRate: sampleRate, parameters: parameters)

        let input = impulse(count: 4_096)
        let outputA = input.map { tailA.process(left: $0, right: $0) }
        let outputB = input.map { tailB.process(left: $0, right: $0) }

        XCTAssertEqual(outputA.map { $0.left }, outputB.map { $0.left })
        XCTAssertEqual(outputA.map { $0.right }, outputB.map { $0.right })
    }

    // MARK: – 6. Nicht-endliche/extreme Parameter und Eingaben, inklusive Post-Init-Mutationspfad

    func test_extremeParameters_stayFinite() {
        let extremeUnit: [Float] = [0.0, 0.5, 1.0, .nan, .infinity, -1.0, 2.0]
        let extremeInputs: [Float] = [0.0, 1.0, -1.0, .nan, .infinity, -.infinity]

        for size in extremeUnit {
            for decay in extremeUnit {
                for damping in extremeUnit {
                    var tail = AudioCoreDeepSpaceFDNTail(
                        sampleRate: sampleRate,
                        parameters: AudioCoreDeepSpaceFDNParameters(size: size, decay: decay, damping: damping)
                    )
                    for input in extremeInputs {
                        let (left, right) = tail.process(left: input, right: input)
                        XCTAssertTrue(left.isFinite,
                                      "FDN left nicht-endlich bei size=\(size), decay=\(decay), damping=\(damping), input=\(input)")
                        XCTAssertTrue(right.isFinite,
                                      "FDN right nicht-endlich bei size=\(size), decay=\(decay), damping=\(damping), input=\(input)")
                    }
                }
            }
        }
    }

    func test_parameters_clampNonFiniteAndOutOfRangeValues() {
        let parameters = AudioCoreDeepSpaceFDNParameters(size: .nan, decay: 5.0, damping: .infinity)
        XCTAssertEqual(parameters.size, 0.0)
        XCTAssertEqual(parameters.decay, 1.0)
        XCTAssertEqual(parameters.damping, 0.0)
    }

    private func mutatedParameters(size: Float, decay: Float, damping: Float) -> AudioCoreDeepSpaceFDNParameters {
        // Baut ueber `init` (bereits geklemmt), mutiert die Felder danach
        // direkt -- genau der Pfad, der bei den anderen DeepSpace-Typen vor
        // S-08a-fix die Klemmung umging (Finding S-08a-01).
        var parameters = AudioCoreDeepSpaceFDNParameters()
        parameters.size = size
        parameters.decay = decay
        parameters.damping = damping
        return parameters
    }

    func test_setParameters_postInitMutation_clampsAndStaysFinite() {
        let nonFiniteAndOutOfRange: [Float] = [.nan, .infinity, -.infinity, -1.0, 5.0]

        for size in nonFiniteAndOutOfRange {
            for decay in nonFiniteAndOutOfRange {
                for damping in nonFiniteAndOutOfRange {
                    var tail = AudioCoreDeepSpaceFDNTail(sampleRate: sampleRate)
                    let mutated = mutatedParameters(size: size, decay: decay, damping: damping)

                    tail.setParameters(mutated) // darf nicht trappen

                    XCTAssertTrue(tail.parameters.size.isFinite)
                    XCTAssertTrue(tail.parameters.decay.isFinite)
                    XCTAssertTrue(tail.parameters.damping.isFinite)
                    XCTAssertGreaterThanOrEqual(tail.parameters.size, 0.0)
                    XCTAssertLessThanOrEqual(tail.parameters.size, 1.0)
                    XCTAssertGreaterThanOrEqual(tail.parameters.decay, 0.0)
                    XCTAssertLessThanOrEqual(tail.parameters.decay, 1.0)
                    XCTAssertGreaterThanOrEqual(tail.parameters.damping, 0.0)
                    XCTAssertLessThanOrEqual(tail.parameters.damping, 1.0)

                    let (left, right) = tail.process(left: 1.0, right: -1.0)
                    XCTAssertTrue(left.isFinite,
                                  "FDN left nicht-endlich nach setParameters mit size=\(size), decay=\(decay), damping=\(damping)")
                    XCTAssertTrue(right.isFinite,
                                  "FDN right nicht-endlich nach setParameters mit size=\(size), decay=\(decay), damping=\(damping)")
                }
            }
        }
    }

    // MARK: – 7. Sample-Rate-Grenzen inklusive der neuen Obergrenze (Finding S-08a-02)

    func test_extremeSampleRates_stayFiniteAndStable() {
        let extremeSampleRates: [Double] = [
            1.0, 8_000, 44_100, 48_000, 96_000, 192_000, 0.0, -44_100, .nan, .infinity, 1e300, .greatestFiniteMagnitude,
        ]

        for sr in extremeSampleRates {
            var tail = AudioCoreDeepSpaceFDNTail(
                sampleRate: sr,
                parameters: AudioCoreDeepSpaceFDNParameters(size: 1.0, decay: 1.0, damping: 0.5)
            )
            XCTAssertTrue(tail.sampleRate.isFinite)
            XCTAssertLessThanOrEqual(tail.sampleRate, AudioCoreDeepSpaceParameters.maxSampleRate)

            for input: Float in [0.0, 1.0, -1.0, .nan, .infinity] {
                let (left, right) = tail.process(left: input, right: input)
                XCTAssertTrue(left.isFinite, "FDN left nicht-endlich bei sr=\(sr), input=\(input)")
                XCTAssertTrue(right.isFinite, "FDN right nicht-endlich bei sr=\(sr), input=\(input)")
            }

            tail.prepare(sampleRate: sr == 44_100 ? 48_000 : 44_100)
            let (left, right) = tail.process(left: 1.0, right: 1.0)
            XCTAssertTrue(left.isFinite)
            XCTAssertTrue(right.isFinite)
        }
    }

    // MARK: – Runde 064 (S-08c-Review-Beobachtung, Handoff Teil 2, Gate 9):
    // Phasenzuwachs bleibt bei der neuen Sample-Rate-Untergrenze unauffaellig.

    func test_modulation_phaseIncrement_staysBelowOneAtNewSampleRateLowerBound() {
        // `modIncrement` selbst ist privater Zustand -- rechnet denselben
        // Ableitungspfad wie `AudioCoreDeepSpaceFDNTail.recomputeModulationState()`
        // fuer den Worst Case (maximale Rate, groesster Rate-Multiplikator)
        // anhand der oeffentlich/`internal` zugaenglichen Konstanten nach.
        // `modIncrement >= 1` wuerde den einfachen Einfach-Phasen-Wrap
        // (`if modPhase >= 1.0 { modPhase -= 1.0 }`) unterlaufen, weil er nur
        // eine Wrap-Subtraktion pro Sample durchfuehrt.
        let sampleRate = AudioCoreDeepSpaceParameters.minSampleRate
        let maxMultiplier = Double(AudioCoreDeepSpaceFDNTail.modulationRateMultipliers.max() ?? 2.0)
        let worstCaseRateHz = Double(AudioCoreDeepSpaceFDNTail.maxModulationRateHz) * maxMultiplier
        let worstCaseIncrement = worstCaseRateHz / sampleRate

        XCTAssertLessThan(worstCaseIncrement, 1.0,
                           "modIncrement waere bei minSampleRate=\(sampleRate) Hz degeneriert: \(worstCaseIncrement)")
        XCTAssertGreaterThan(sampleRate, worstCaseRateHz,
                             "minSampleRate liegt nicht mehr klar oberhalb des vormaligen ~0,7-Hz-Problembereichs")
    }

    func test_modulation_atSampleRateLowerBound_staysFiniteOverLongRender() {
        // Funktionaler Nachweis zusaetzlich zur analytischen Rechnung oben:
        // ein tatsaechlicher Render bei `minSampleRate` mit maximaler
        // Modulation ueber deutlich mehr Samples, als die bestehenden
        // Sample-Rate-Grenztests (die nur wenige Samples verarbeiten).
        var tail = AudioCoreDeepSpaceFDNTail(
            sampleRate: AudioCoreDeepSpaceParameters.minSampleRate,
            parameters: AudioCoreDeepSpaceFDNParameters(
                size: 1.0, decay: 1.0, damping: 0.5, modulationDepth: 1.0, modulationRate: 1.0
            )
        )
        for n in 0..<20_000 {
            let x = sinf(2.0 * Float.pi * 5.0 * Float(n) / Float(AudioCoreDeepSpaceParameters.minSampleRate))
            let (left, right) = tail.process(left: x, right: x)
            XCTAssertTrue(left.isFinite, "left nicht-endlich bei n=\(n)")
            XCTAssertTrue(right.isFinite, "right nicht-endlich bei n=\(n)")
        }
    }

    // MARK: – 8. Daempfung wirkt nachweislich frequenzabhaengig

    func test_damping_attenuatesHighFrequenciesFasterThanLowFrequencies() {
        func sustainedSine(frequency: Float, count: Int) -> [Float] {
            (0..<count).map { n in
                sinf(2.0 * Float.pi * frequency * Float(n) / Float(sampleRate))
            }
        }

        func decayRatio(frequency: Float) -> Float {
            var tail = AudioCoreDeepSpaceFDNTail(
                sampleRate: sampleRate,
                parameters: AudioCoreDeepSpaceFDNParameters(size: 0.6, decay: 0.6, damping: 1.0)
            )
            var burst = sustainedSine(frequency: frequency, count: 8_000)
            burst.append(contentsOf: Array(repeating: Float(0), count: 16_000))
            let response = burst.map { tail.process(left: $0, right: $0) }
            let mono = response.map { $0.left + $0.right }

            let blockSize = 4_000
            let blocks = blockEnergies(mono, blockSize: blockSize)
            // Burst = 8.000 Samples = 2 Bloecke (Index 0-1). Block 2 ist der
            // erste reine Abklingblock, Block 5 liegt deutlich spaeter im
            // Abklingbereich.
            let early = max(blocks[2], .leastNormalMagnitude)
            let late = blocks[5]
            return late / early
        }

        let lowFrequencyRatio = decayRatio(frequency: 55.0)      // tief
        let highFrequencyRatio = decayRatio(frequency: 16_000.0) // hoch, nahe Nyquist

        XCTAssertLessThan(highFrequencyRatio, lowFrequencyRatio,
                           "Hohe Frequenzen klingen nicht schneller ab: hoch=\(highFrequencyRatio), tief=\(lowFrequencyRatio)")
    }

    func test_damping_zero_stillStaysFiniteAndStable() {
        // damping = 0 ist ein gueltiger Parameterwert (kein zusaetzlicher
        // Hochtonverlust pro Umlauf) -- die Stabilitaet traegt allein der
        // Rundlauf-Gain < 1, unabhaengig von der Daempfung.
        var tail = AudioCoreDeepSpaceFDNTail(
            sampleRate: sampleRate,
            parameters: AudioCoreDeepSpaceFDNParameters(size: 1.0, decay: 1.0, damping: 0.0)
        )
        let response = impulse(count: Int(sampleRate * 3)).map { tail.process(left: $0, right: $0) }
        for (left, right) in response {
            XCTAssertTrue(left.isFinite)
            XCTAssertTrue(right.isFinite)
        }
    }

    // MARK: – 9. Stereo-Ausgang ist definiert, stabil und nicht identisch auf beiden Kanaelen

    func test_stereoOutput_isDefinedAndNotIdenticalOnBothChannels() {
        var tail = AudioCoreDeepSpaceFDNTail(
            sampleRate: sampleRate,
            parameters: AudioCoreDeepSpaceFDNParameters(size: 0.5, decay: 0.5, damping: 0.5)
        )
        let response = impulse(count: 8_192).map { tail.process(left: $0, right: $0) }
        let left = response.map { $0.left }
        let right = response.map { $0.right }

        XCTAssertNotEqual(left, right)
        for value in left + right {
            XCTAssertTrue(value.isFinite)
        }
    }

    // MARK: – Funktionale Anforderung (Abschnitt 7.3): Delaylinien-Laengen sind paarweise teilerfremd

    func test_lineLengths_arePairwiseCoprime_acrossSizeRange() {
        let sizes: [Float] = [0.0, 0.25, 0.5, 0.75, 1.0]

        for size in sizes {
            let tail = AudioCoreDeepSpaceFDNTail(
                sampleRate: sampleRate,
                parameters: AudioCoreDeepSpaceFDNParameters(size: size)
            )
            let lengths = tail.lineLengthSamples
            XCTAssertEqual(Set(lengths).count, lengths.count, "Laengen nicht paarweise verschieden bei size=\(size)")

            for i in 0..<lengths.count {
                for j in (i + 1)..<lengths.count {
                    XCTAssertEqual(gcd(lengths[i], lengths[j]), 1,
                                    "Laengen \(lengths[i])/\(lengths[j]) nicht teilerfremd bei size=\(size)")
                }
            }
        }
    }

    // MARK: – 10. CPU-/Speicherbudget bleibt konservativ begrenzt

    func test_bufferCapacity_atMaxSampleRateAndSize_isConservativelyBounded() {
        let tail = AudioCoreDeepSpaceFDNTail(
            sampleRate: AudioCoreDeepSpaceParameters.maxSampleRate,
            parameters: AudioCoreDeepSpaceFDNParameters(size: 1.0)
        )
        // Dokumentiertes Worst-Case-Speicherbudget (siehe Dateikommentar
        // `AudioCoreDeepSpaceFDNTail`/Ruecklauf): bei der technischen
        // Sample-Rate-Obergrenze (1 MHz) und maximalem `size` bleibt die
        // Gesamtpuffergroesse deutlich unter 16 MB -- bei jeder realen
        // Sample Rate (<= 192 kHz) entsprechend viel kleiner.
        let totalBytes = tail.lineCapacity.reduce(0, +) * MemoryLayout<Float>.size
        XCTAssertLessThan(totalBytes, 16 * 1_024 * 1_024)
    }

    // MARK: – 11. OfflineSynthBaselineTests bleiben unveraendert gruen -- kein neuer Test hier,
    // Nachweis per `swift test --filter OfflineSynthBaselineTests` im Ruecklauf.

    // MARK: – S-08b-fix: Bit-identischer Output vor/nach der Renderpfad-Umstellung
    //
    // Referenz-Checksum wurde vor dem Umbau (Commit `4c49ed9`, vor S-08b-fix)
    // ueber diese exakte Konfiguration/Eingabefolge erzeugt. Aendert der
    // Umbau (feste Scratch-Puffer, flacher Delay-Speicher statt `[[Float]]`,
    // puffer-schreibende Matrixform) auch nur ein einziges Bit im Output,
    // schlaegt dieser Test fehl.
    private func regressionBaselineSamples() -> [Float] {
        let configs: [(size: Float, decay: Float, damping: Float, sampleRate: Double)] = [
            (0.5, 0.5, 0.5, 44_100),
            (1.0, 1.0, 0.5, 48_000),
            (0.0, 1.0, 0.0, 44_100),
            (0.6, 0.7, 0.4, 96_000),
        ]
        var allSamples: [Float] = []
        for config in configs {
            var tail = AudioCoreDeepSpaceFDNTail(
                sampleRate: config.sampleRate,
                parameters: AudioCoreDeepSpaceFDNParameters(size: config.size, decay: config.decay, damping: config.damping)
            )
            let input = impulse(count: 256)
            for (i, x) in input.enumerated() {
                let rightInput: Float = i % 3 == 0 ? -x : x * 0.5
                let (left, right) = tail.process(left: x, right: rightInput)
                allSamples.append(left)
                allSamples.append(right)
            }
        }
        return allSamples
    }

    func test_bitIdenticalOutput_matchesS08bBaselineChecksum() {
        let checksum = fnv1aChecksum(regressionBaselineSamples())
        XCTAssertEqual(
            checksum, 0xb9d1_03fd_6854_a325,
            "Output weicht vom S-08b-Baseline-Checksum ab (erzeugt vor S-08b-fix auf Commit 4c49ed9) -- "
                + "der Renderpfad-Umbau hat das Klangverhalten veraendert"
        )
    }

    // MARK: – S-08c (`.agent_handoff/latest_codex.md`, Runde 061): dekorrelierte
    // Delaymodulation im Feedbackpfad. Deckt die neun im Auftrag geforderten
    // Gates ab: Stabilitaet bei maximaler Modulation, bit-exakter
    // Determinismus mit aktiver Modulation, Bit-Identitaet bei Tiefe 0,
    // Dekorrelation, Kapazitaetssicherheit, Artefaktarmut der Interpolation,
    // Post-Init-Mutationspfad. Allokationsfreiheit wird separat per SIL
    // nachgewiesen (kein Unit-Test dafuer, siehe Ruecklauf).

    // MARK: – Gate 1: Stabilitaet bleibt bei maximaler Modulation erhalten

    func test_modulation_impulseResponse_isFiniteOverLongRender_atMaxModulationAndDecay() {
        var tail = AudioCoreDeepSpaceFDNTail(
            sampleRate: sampleRate,
            parameters: AudioCoreDeepSpaceFDNParameters(
                size: 1.0, decay: 1.0, damping: 0.5, modulationDepth: 1.0, modulationRate: 1.0
            )
        )
        let response = impulse(count: Int(sampleRate * 6)).map { tail.process(left: $0, right: $0) }
        for (left, right) in response {
            XCTAssertTrue(left.isFinite)
            XCTAssertTrue(right.isFinite)
        }
    }

    func test_modulation_windowedEnergy_decaysMonotonically_atMaxModulationDecayAndSize() {
        var tail = AudioCoreDeepSpaceFDNTail(
            sampleRate: sampleRate,
            parameters: AudioCoreDeepSpaceFDNParameters(
                size: 1.0, decay: 1.0, damping: 0.0, modulationDepth: 1.0, modulationRate: 1.0
            )
        )
        let renderLength = Int(sampleRate * 6)
        let response = impulse(count: renderLength).map { tail.process(left: $0, right: $0) }
        let mono = response.map { $0.left + $0.right }

        let blockSize = Int(sampleRate * 0.5)
        let blocks = blockEnergies(mono, blockSize: blockSize)

        for i in 1..<(blocks.count - 1) {
            XCTAssertLessThanOrEqual(blocks[i + 1], blocks[i] * 1.03,
                                      "Energie waechst mit aktiver Modulation zwischen Block \(i) und \(i+1): \(blocks[i]) -> \(blocks[i+1])")
        }

        XCTAssertLessThan(blocks.last!, blocks[1] * 0.7,
                           "Spaete Blockenergie ist mit aktiver Modulation nicht deutlich kleiner als frueher")
    }

    func test_modulation_selfOscillation_decaysAfterInputStops_atMaxModulationAndParameters() {
        var tail = AudioCoreDeepSpaceFDNTail(
            sampleRate: sampleRate,
            parameters: AudioCoreDeepSpaceFDNParameters(
                size: 1.0, decay: 1.0, damping: 0.0, modulationDepth: 1.0, modulationRate: 1.0
            )
        )
        var burst: [Float] = impulse(count: 2_000)
        burst.append(contentsOf: Array(repeating: Float(0), count: Int(sampleRate * 5)))
        let response = burst.map { tail.process(left: $0, right: $0) }
        let mono = response.map { $0.left + $0.right }

        let blockSize = Int(sampleRate * 0.5)
        let blocks = blockEnergies(mono, blockSize: blockSize)

        let earlyBlock = blocks[1]
        let lateBlock = blocks.last!
        XCTAssertTrue(earlyBlock.isFinite)
        XCTAssertTrue(lateBlock.isFinite)
        XCTAssertLessThan(lateBlock, earlyBlock,
                           "Tail klingt bei maximaler Modulation/decay/size nicht ab: frueh=\(earlyBlock), spaet=\(lateBlock)")
    }

    // MARK: – Gate 2: Determinismus bit-exakt, auch mit aktiver Modulation

    func test_modulation_reset_reproducesIdenticalOutput_bitExact() {
        var tail = AudioCoreDeepSpaceFDNTail(
            sampleRate: sampleRate,
            parameters: AudioCoreDeepSpaceFDNParameters(
                size: 0.6, decay: 0.7, damping: 0.4, modulationDepth: 0.8, modulationRate: 0.9
            )
        )
        let input = impulse(count: 8_192)
        let firstRun = input.map { tail.process(left: $0, right: -$0) }

        tail.reset()
        let secondRun = input.map { tail.process(left: $0, right: -$0) }

        XCTAssertEqual(firstRun.map { $0.left }, secondRun.map { $0.left })
        XCTAssertEqual(firstRun.map { $0.right }, secondRun.map { $0.right })
    }

    func test_modulation_isDeterministicAcrossInstances() {
        let parameters = AudioCoreDeepSpaceFDNParameters(
            size: 0.4, decay: 0.5, damping: 0.6, modulationDepth: 0.7, modulationRate: 0.3
        )
        var tailA = AudioCoreDeepSpaceFDNTail(sampleRate: sampleRate, parameters: parameters)
        var tailB = AudioCoreDeepSpaceFDNTail(sampleRate: sampleRate, parameters: parameters)

        let input = impulse(count: 4_096)
        let outputA = input.map { tailA.process(left: $0, right: $0) }
        let outputB = input.map { tailB.process(left: $0, right: $0) }

        XCTAssertEqual(outputA.map { $0.left }, outputB.map { $0.left })
        XCTAssertEqual(outputA.map { $0.right }, outputB.map { $0.right })
    }

    // MARK: – Gate 3: Modulation ist nachweislich additiv/wirksam

    func test_modulation_depthZero_isExplicitlyBitIdenticalToBaselineChecksum() {
        // Wie `test_bitIdenticalOutput_matchesS08bBaselineChecksum`, aber mit
        // EXPLIZIT gesetztem `modulationDepth: 0.0`/`modulationRate` statt
        // dem impliziten Default -- belegt, dass nicht nur "Parameter nicht
        // gesetzt", sondern der tatsaechliche Tiefe-0-Codepfad greift.
        func explicitZeroDepthSamples() -> [Float] {
            let configs: [(size: Float, decay: Float, damping: Float, sampleRate: Double)] = [
                (0.5, 0.5, 0.5, 44_100),
                (1.0, 1.0, 0.5, 48_000),
                (0.0, 1.0, 0.0, 44_100),
                (0.6, 0.7, 0.4, 96_000),
            ]
            var allSamples: [Float] = []
            for config in configs {
                var tail = AudioCoreDeepSpaceFDNTail(
                    sampleRate: config.sampleRate,
                    parameters: AudioCoreDeepSpaceFDNParameters(
                        size: config.size, decay: config.decay, damping: config.damping,
                        modulationDepth: 0.0, modulationRate: 0.7
                    )
                )
                let input = impulse(count: 256)
                for (i, x) in input.enumerated() {
                    let rightInput: Float = i % 3 == 0 ? -x : x * 0.5
                    let (left, right) = tail.process(left: x, right: rightInput)
                    allSamples.append(left)
                    allSamples.append(right)
                }
            }
            return allSamples
        }

        let checksum = fnv1aChecksum(explicitZeroDepthSamples())
        XCTAssertEqual(checksum, 0xb9d1_03fd_6854_a325,
                        "Explizite modulationDepth=0 weicht vom S-08b-Baseline-Checksum ab")
    }

    func test_modulation_depthPositive_differsMeasurablyFromDepthZero() {
        func render(depth: Float) -> [Float] {
            // size=0.0 haelt die Linienlaengen kurz (kuerzeste Linie ~20ms
            // ~= 882 Samples bei 44,1kHz), damit der Impuls innerhalb des
            // Renderfensters tatsaechlich durch alle Linien gelaufen ist,
            // BEVOR verglichen wird -- sonst liest keine Linie ueberhaupt
            // einen Nicht-Null-Wert und beide Renders waeren trivial gleich
            // (beide Null), unabhaengig von der Modulation.
            var tail = AudioCoreDeepSpaceFDNTail(
                sampleRate: sampleRate,
                parameters: AudioCoreDeepSpaceFDNParameters(
                    size: 0.0, decay: 0.8, damping: 0.4, modulationDepth: depth, modulationRate: 0.8
                )
            )
            var output: [Float] = []
            for x in impulse(count: 20_000) {
                let (left, right) = tail.process(left: x, right: x * 0.5)
                output.append(left)
                output.append(right)
            }
            return output
        }

        let atZero = render(depth: 0.0)
        let atFull = render(depth: 1.0)

        XCTAssertNotEqual(atZero, atFull,
                           "modulationDepth = 1.0 aendert den Output gegenueber modulationDepth = 0 nicht messbar")

        var maxAbsoluteDifference: Float = 0
        for (a, b) in zip(atZero, atFull) {
            maxAbsoluteDifference = max(maxAbsoluteDifference, abs(a - b))
        }
        XCTAssertGreaterThan(maxAbsoluteDifference, 1e-6,
                              "Unterschied zwischen modulationDepth 0 und 1 ist kleiner als Gleitkomma-Rauschen")
    }

    // MARK: – Gate 4: Dekorrelation der acht Modulationsverlaeufe

    func test_modulation_rateMultipliersAndPhaseOffsets_arePairwiseDistinct() {
        let rates = AudioCoreDeepSpaceFDNTail.modulationRateMultipliers
        let phases = AudioCoreDeepSpaceFDNTail.modulationPhaseOffsets
        XCTAssertEqual(rates.count, 8)
        XCTAssertEqual(phases.count, 8)

        for i in 0..<rates.count {
            for j in (i + 1)..<rates.count {
                XCTAssertNotEqual(rates[i], rates[j], accuracy: 1e-6,
                                   "Ratenmultiplikatoren \(i)/\(j) nicht paarweise verschieden")
                XCTAssertNotEqual(phases[i], phases[j], accuracy: 1e-6,
                                   "Phasenversaetze \(i)/\(j) nicht paarweise verschieden")
            }
        }
    }

    func test_modulation_signals_areNotStronglyCorrelated_acrossLinePairs() {
        // Simuliert die acht theoretischen Modulationssignale rein aus den
        // oeffentlich (intern) testbaren Konstanten -- unabhaengig vom
        // FDN-Feedbackpfad, isoliert die Dekorrelationsaussage von der
        // restlichen DSP-Kette.
        //
        // Zeitfenster: zwei Sinusse mit knapp benachbarter Frequenz sehen
        // ueber ein KURZES Fenster (viel kuerzer als ihre Schwebungsperiode
        // 1/|f1-f2|) fast identisch aus -- hohe Korrelation dort ist ein
        // Artefakt der Fensterlaenge, keine Aussage ueber Dekorrelation.
        // Die engsten Ratenmultiplikatoren liegen ca. 0,09 auseinander, bei
        // maximaler Rate (0,35 Hz) also ca. 0,0315 Hz Differenz -> ca. 31,7 s
        // Schwebungsperiode im ungruenstigsten Fall. Das Fenster unten
        // deckt davon mehrere volle Perioden ab (400 s), nicht nur einen
        // Bruchteil. `testSampleRate` ist hier eine reine Zeitschritt-
        // Aufloesung fuer diese isolierte Simulation (kein Audio-Rendering),
        // 200 Hz genuegt fuer die hier vorkommenden Modulationsraten
        // (<= 1 Hz) bei Weitem (Nyquist).
        let testSampleRate = 200.0
        let coverageSeconds = 400.0
        let rateUnit: Float = 1.0 // maximale Rate -- staerkster Praxisfall
        let baseRateHz = AudioCoreDeepSpaceFDNTail.minModulationRateHz
            + rateUnit * (AudioCoreDeepSpaceFDNTail.maxModulationRateHz - AudioCoreDeepSpaceFDNTail.minModulationRateHz)

        let sampleCount = Int(testSampleRate * coverageSeconds)
        var signals: [[Float]] = []
        for i in 0..<8 {
            let rateHz = baseRateHz * AudioCoreDeepSpaceFDNTail.modulationRateMultipliers[i]
            let increment = Double(rateHz) / testSampleRate
            var phase = AudioCoreDeepSpaceFDNTail.modulationPhaseOffsets[i]
            var series: [Float] = []
            series.reserveCapacity(sampleCount)
            for _ in 0..<sampleCount {
                series.append(sinf(2.0 * Float.pi * Float(phase)))
                phase += increment
                if phase >= 1.0 { phase -= 1.0 }
            }
            signals.append(series)
        }

        func pearsonCorrelation(_ a: [Float], _ b: [Float]) -> Float {
            let n = Float(a.count)
            let meanA = a.reduce(0, +) / n
            let meanB = b.reduce(0, +) / n
            var covariance: Float = 0
            var varianceA: Float = 0
            var varianceB: Float = 0
            for k in 0..<a.count {
                let da = a[k] - meanA
                let db = b[k] - meanB
                covariance += da * db
                varianceA += da * da
                varianceB += db * db
            }
            let denominator = (varianceA * varianceB).squareRoot()
            return denominator > 0 ? covariance / denominator : 0
        }

        for i in 0..<signals.count {
            for j in (i + 1)..<signals.count {
                let correlation = abs(pearsonCorrelation(signals[i], signals[j]))
                XCTAssertLessThan(correlation, 0.9,
                                   "Modulationssignale der Linien \(i)/\(j) korrelieren zu stark: \(correlation)")
            }
        }
    }

    // MARK: – Gate 5: Leseposition bleibt in der Kapazitaet

    func test_modulation_readPosition_staysWithinCapacity_acrossExtremeModulationParameters() {
        let extremeUnit: [Float] = [0.0, 0.5, 1.0, .nan, .infinity, -1.0, 2.0]
        let extremeSampleRates: [Double] = [1.0, 8_000, 44_100, 192_000, AudioCoreDeepSpaceParameters.maxSampleRate, 1e300]
        let extremeInputs: [Float] = [0.0, 1.0, -1.0, .nan, .infinity]

        for sr in extremeSampleRates {
            for modDepth in extremeUnit {
                for modRate in extremeUnit {
                    var tail = AudioCoreDeepSpaceFDNTail(
                        sampleRate: sr,
                        parameters: AudioCoreDeepSpaceFDNParameters(
                            size: 1.0, decay: 1.0, damping: 0.5,
                            modulationDepth: modDepth, modulationRate: modRate
                        )
                    )
                    for input in extremeInputs {
                        let (left, right) = tail.process(left: input, right: input)
                        XCTAssertTrue(left.isFinite,
                                      "left nicht-endlich bei sr=\(sr), modDepth=\(modDepth), modRate=\(modRate), input=\(input)")
                        XCTAssertTrue(right.isFinite,
                                      "right nicht-endlich bei sr=\(sr), modDepth=\(modDepth), modRate=\(modRate), input=\(input)")
                    }
                }
            }
        }
    }

    func test_modulation_readPosition_staysWithinCapacity_acrossSizeExtremesAtMaxModulation() {
        // size=0 ergibt die kuerzesten Linien -- der rechnerisch engste Fall
        // fuer die per-Linie-Deckelung `modDepthSamples[i] <=
        // lineLengthSamples[i] - 1`.
        let sizes: [Float] = [0.0, 0.25, 0.5, 0.75, 1.0]
        for size in sizes {
            var tail = AudioCoreDeepSpaceFDNTail(
                sampleRate: sampleRate,
                parameters: AudioCoreDeepSpaceFDNParameters(
                    size: size, decay: 1.0, damping: 0.5, modulationDepth: 1.0, modulationRate: 1.0
                )
            )
            let response = impulse(count: 20_000).map { tail.process(left: $0, right: $0) }
            for (left, right) in response {
                XCTAssertTrue(left.isFinite, "left nicht-endlich bei size=\(size) unter maximaler Modulation")
                XCTAssertTrue(right.isFinite, "right nicht-endlich bei size=\(size) unter maximaler Modulation")
            }
        }
    }

    // MARK: – Gate 6: Interpolation ist artefaktarm

    func test_linearInterpolate_isBoundedConvexCombination() {
        XCTAssertEqual(AudioCoreDeepSpaceFDNTail.linearInterpolate(1.0, 3.0, fraction: 0.0), 1.0)
        XCTAssertEqual(AudioCoreDeepSpaceFDNTail.linearInterpolate(1.0, 3.0, fraction: 1.0), 3.0)
        XCTAssertEqual(AudioCoreDeepSpaceFDNTail.linearInterpolate(1.0, 3.0, fraction: 0.5), 2.0)

        // Konvexkombination: das Ergebnis darf die Werte der beiden Taps nie
        // ueberschreiten -- direkte Grundlage des Stabilitaetsarguments im
        // Dateikommentar (`AudioCoreDeepSpaceFDNTail.swift`, Abschnitt
        // "Interpolation").
        let taps: [(Float, Float)] = [(-1.0, 1.0), (0.7, -0.3), (-5.0, -2.0), (0.0, 0.0)]
        for (a, b) in taps {
            for fraction: Float in stride(from: 0.0, through: 1.0, by: 0.1) {
                let result = AudioCoreDeepSpaceFDNTail.linearInterpolate(a, b, fraction: fraction)
                XCTAssertLessThanOrEqual(result, max(a, b) + 1e-6)
                XCTAssertGreaterThanOrEqual(result, min(a, b) - 1e-6)
            }
        }

        // Nicht-endliche Eingaben bleiben endlich (defensiver Fallback,
        // konsistent mit dem uebrigen Codebase-Stil).
        XCTAssertTrue(AudioCoreDeepSpaceFDNTail.linearInterpolate(.nan, 1.0, fraction: 0.5).isFinite)
        XCTAssertTrue(AudioCoreDeepSpaceFDNTail.linearInterpolate(1.0, 2.0, fraction: .nan).isFinite)
    }

    func test_modulation_outputStaysContinuous_noLargeSampleJumps_duringFullModulationCycle() {
        // Ueberdeckt mindestens einen vollen Modulationszyklus der
        // schnellsten Linie bei maximaler Rate (~2,9 s Periode fuer den
        // langsamsten Multiplikator ~1,0 -- 3 s Render deckt das sicher ab).
        var tail = AudioCoreDeepSpaceFDNTail(
            sampleRate: sampleRate,
            parameters: AudioCoreDeepSpaceFDNParameters(
                size: 0.5, decay: 0.9, damping: 0.3, modulationDepth: 1.0, modulationRate: 1.0
            )
        )
        // Anhaltendes, bandbegrenztes Eingangssignal statt Impuls -- haelt
        // den Tail durchgehend im eingeschwungenen Zustand, damit
        // Sprungstellen nicht im Abklingrauschen untergehen.
        let sampleCountForCycle = Int(sampleRate * 3.0)
        var maxAbsoluteDelta: Float = 0
        var previousLeft: Float = 0
        var previousRight: Float = 0
        for n in 0..<sampleCountForCycle {
            let x = sinf(2.0 * Float.pi * 220.0 * Float(n) / Float(sampleRate)) * 0.2
            let (left, right) = tail.process(left: x, right: x)
            if n > 0 {
                maxAbsoluteDelta = max(maxAbsoluteDelta, abs(left - previousLeft))
                maxAbsoluteDelta = max(maxAbsoluteDelta, abs(right - previousRight))
            }
            previousLeft = left
            previousRight = right
        }

        // Konservative Schranke: das Eingangssignal selbst hat bei 220 Hz/
        // 44,1 kHz einen maximalen Sample-zu-Sample-Sprung von
        // `0.2 * 2 * pi * 220 / 44100 ~= 0.0063` pro Umlauf durch den Tail;
        // ueber acht gemischte Delaylinien mit Gain < 1 bleibt jeder
        // einzelne Ausgangssprung in derselben Groessenordnung. Eine
        // Integer-Delaysprung-Stelle (kein Interpolieren) wuerde dagegen bei
        // Modulationstiefe 8 Samples einen Sprung erzeugen, der der vollen
        // lokalen Signaldifferenz ueber 8 Samples entspricht -- deutlich
        // groesser als diese Schranke.
        XCTAssertLessThan(maxAbsoluteDelta, 0.05,
                           "Sample-zu-Sample-Sprung waehrend aktiver Modulation zu gross: \(maxAbsoluteDelta) -- "
                               + "deutet auf eine nicht interpolierte Sprungstelle in der Leseposition hin")
    }

    // MARK: – Gate 7: Post-Init-Mutationspfad fuer die neuen Modulationsparameter

    private func mutatedModulationParameters(depth: Float, rate: Float) -> AudioCoreDeepSpaceFDNParameters {
        var parameters = AudioCoreDeepSpaceFDNParameters()
        parameters.modulationDepth = depth
        parameters.modulationRate = rate
        return parameters
    }

    func test_modulation_setParameters_postInitMutation_clampsAndStaysFinite() {
        let nonFiniteAndOutOfRange: [Float] = [.nan, .infinity, -.infinity, -1.0, 5.0]

        for depth in nonFiniteAndOutOfRange {
            for rate in nonFiniteAndOutOfRange {
                var tail = AudioCoreDeepSpaceFDNTail(sampleRate: sampleRate)
                let mutated = mutatedModulationParameters(depth: depth, rate: rate)

                tail.setParameters(mutated) // darf nicht trappen

                XCTAssertTrue(tail.parameters.modulationDepth.isFinite)
                XCTAssertTrue(tail.parameters.modulationRate.isFinite)
                XCTAssertGreaterThanOrEqual(tail.parameters.modulationDepth, 0.0)
                XCTAssertLessThanOrEqual(tail.parameters.modulationDepth, 1.0)
                XCTAssertGreaterThanOrEqual(tail.parameters.modulationRate, 0.0)
                XCTAssertLessThanOrEqual(tail.parameters.modulationRate, 1.0)

                let (left, right) = tail.process(left: 1.0, right: -1.0)
                XCTAssertTrue(left.isFinite,
                              "left nicht-endlich nach setParameters mit modulationDepth=\(depth), modulationRate=\(rate)")
                XCTAssertTrue(right.isFinite,
                              "right nicht-endlich nach setParameters mit modulationDepth=\(depth), modulationRate=\(rate)")
            }
        }
    }

    func test_modulation_setParameters_preservesModulationAcrossCalls() {
        // Regressionsschutz fuer den in S-08c korrigierten `setParameters(_:)`
        // -- ohne die modulationDepth/-Rate-Weitergabe wuerde jeder Aufruf
        // die Modulation stillschweigend auf die Defaults zuruecksetzen.
        var tail = AudioCoreDeepSpaceFDNTail(
            sampleRate: sampleRate,
            parameters: AudioCoreDeepSpaceFDNParameters(modulationDepth: 1.0, modulationRate: 1.0)
        )
        tail.setParameters(AudioCoreDeepSpaceFDNParameters(
            size: 0.7, decay: 0.7, damping: 0.7, modulationDepth: 1.0, modulationRate: 1.0
        ))
        XCTAssertEqual(tail.parameters.modulationDepth, 1.0)
        XCTAssertEqual(tail.parameters.modulationRate, 1.0)
    }

    // MARK: – W-03a (`.agent_handoff/latest_codex.md`, Runde 068):
    // Renderthread-Sicherheit des ganzen Typs.
    //
    // Die Allokationsfreiheit selbst ist kein Unit-Test (Nachweis per SIL plus
    // Laufzeitmessung, siehe Ruecklauf). Was hier abgesichert wird, ist die
    // Bedingung, unter der der Umbau ueberhaupt zulaessig war: er darf den
    // Klang nicht anfassen.
    //
    // Der bestehende `test_bitIdenticalOutput_matchesS08bBaselineChecksum`
    // deckt den Umbau NICHT ab -- er baut je Konfiguration eine frische
    // Instanz und ruft `setParameters(_:)` nie. Genau dort sitzt aber die
    // geaenderte Stelle: die Ausschlussliste der Primzahlwahl. Dieser Test
    // faehrt deshalb Parameterwechsel MITTEN im laufenden Render und prueft
    // die gewaehlten Linienlaengen mit, nicht nur ihr Klangergebnis.

    private func w03aParameterSweepSamples() -> [Float] {
        let sweep: [(size: Float, decay: Float, damping: Float, depth: Float, rate: Float)] = [
            (0.0, 0.0, 0.0, 0.0, 0.0),
            (0.1, 0.9, 0.2, 0.3, 0.7),
            (0.25, 0.5, 0.8, 0.0, 0.1),
            (0.5, 0.25, 0.5, 0.9, 0.4),
            (0.75, 1.0, 0.1, 0.2, 0.9),
            (1.0, 0.6, 0.35, 0.55, 0.55),
        ]
        var all: [Float] = []
        for sampleRate in [8_000.0, 44_100.0, 48_000.0, 192_000.0] as [Double] {
            var tail = AudioCoreDeepSpaceFDNTail(sampleRate: sampleRate)
            var n = 0
            for step in sweep {
                tail.setParameters(
                    AudioCoreDeepSpaceFDNParameters(size: step.size, decay: step.decay, damping: step.damping,
                                                    modulationDepth: step.depth, modulationRate: step.rate)
                )
                for length in tail.lineLengthSamples { all.append(Float(length)) }
                for _ in 0..<128 {
                    let x = Float(n % 97) * 0.01 - 0.5
                    n += 1
                    let (left, right) = tail.process(left: x, right: x * 0.75)
                    all.append(left)
                    all.append(right)
                }
            }
            // `reset()` mitten im Render -- die zweite in W-03a geaenderte
            // Stelle, inklusive der Modulationsphasen-Ruecksetzung.
            tail.reset()
            for _ in 0..<128 {
                let x = Float(n % 97) * 0.01 - 0.5
                n += 1
                let (left, right) = tail.process(left: x, right: -x)
                all.append(left)
                all.append(right)
            }
        }
        return all
    }

    func test_w03a_bitIdenticalOutput_acrossSetParametersDuringRender_matchesBaselineChecksum() {
        // Referenzwert erzeugt gegen die Quellen aus Commit `b7f26d1` (Stand
        // vor W-03a), mit exakt diesem Ablauf. Aendert der Umbau die
        // Primzahlwahl, die Linienlaengen, die Gains, das Daempfungsmodell
        // oder die Modulationsphase auch nur in einem Bit, schlaegt der Test
        // fehl.
        let samples = w03aParameterSweepSamples()
        XCTAssertEqual(samples.count, 7_360)
        XCTAssertEqual(
            fnv1aChecksum(samples), 0x94b1_1591_b9ac_2155,
            "Output oder Linienlaengen weichen vom b7f26d1-Baseline-Checksum ab -- der "
                + "Renderthread-Umbau (usedPrimes-Array, In-Place-reset, Modulationsphase) hat das "
                + "Klangverhalten veraendert"
        )
    }

    func test_w03a_primeSelection_isUnaffectedByRepeatedSetParameters() {
        // Die Ausschlussliste ist seit W-03a ein wiederverwendeter Puffer statt
        // eines je Aufruf frisch gebauten `Set`. Dieser Test sichert die
        // Eigenschaft ab, die dabei kaputtgehen koennte: Reste eines
        // vorherigen Durchlaufs duerfen die naechste Wahl nicht beeinflussen.
        // Derselbe Parametersatz muss nach beliebigen Zwischenwechseln wieder
        // exakt dieselben Linienlaengen ergeben.
        var tail = AudioCoreDeepSpaceFDNTail(sampleRate: sampleRate)
        let target = AudioCoreDeepSpaceFDNParameters(size: 0.4, decay: 0.8, damping: 0.3)
        tail.setParameters(target)
        let reference = tail.lineLengthSamples

        for size in stride(from: Float(0), through: 1.0, by: 0.05) {
            tail.setParameters(AudioCoreDeepSpaceFDNParameters(size: size, decay: 0.2, damping: 0.9))
            tail.setParameters(target)
            XCTAssertEqual(tail.lineLengthSamples, reference,
                           "Linienlaengen haengen vom vorherigen Parametersatz ab (size = \(size))")
        }

        // Und weiterhin paarweise teilerfremd nach dem Hin und Her.
        for i in 0..<AudioCoreDeepSpaceFDNTail.lineCount {
            for j in (i + 1)..<AudioCoreDeepSpaceFDNTail.lineCount {
                XCTAssertEqual(gcd(tail.lineLengthSamples[i], tail.lineLengthSamples[j]), 1,
                               "Linien \(i)/\(j) nicht teilerfremd nach wiederholtem setParameters")
            }
        }
    }

    func test_w03a_reset_restoresModulationPhase_withoutSharingTheConstantBuffer() {
        // `reset()` setzt die Modulationsphase seit W-03a elementweise in den
        // eigenen Puffer zurueck statt per Zuweisung aus der Konstante (das
        // haette den Puffer geteilt und die Copy-on-Write-Kopie in den ersten
        // `process`-Aufruf verschoben). Fachlich muss das unveraendert
        // wirken: nach `reset()` verhaelt sich die Instanz wie eine frische.
        let parameters = AudioCoreDeepSpaceFDNParameters(
            size: 0.6, decay: 0.7, damping: 0.4, modulationDepth: 1.0, modulationRate: 0.9
        )
        var used = AudioCoreDeepSpaceFDNTail(sampleRate: sampleRate, parameters: parameters)
        for n in 0..<4_096 {
            _ = used.process(left: Float(n % 31) * 0.03 - 0.5, right: 0.2)
        }
        used.reset()

        var fresh = AudioCoreDeepSpaceFDNTail(sampleRate: sampleRate, parameters: parameters)

        for n in 0..<2_048 {
            let x = Float(n % 53) * 0.02 - 0.5
            let a = used.process(left: x, right: -x)
            let b = fresh.process(left: x, right: -x)
            XCTAssertEqual(a.left.bitPattern, b.left.bitPattern, "links weicht bei Sample \(n) ab")
            XCTAssertEqual(a.right.bitPattern, b.right.bitPattern, "rechts weicht bei Sample \(n) ab")
        }
    }
}
