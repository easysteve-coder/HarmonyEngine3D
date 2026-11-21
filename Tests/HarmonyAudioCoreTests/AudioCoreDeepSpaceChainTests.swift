import XCTest
@testable import HarmonyAudioCore

// MARK: – AudioCoreDeepSpaceChainTests
//
// W-02 (`.agent_handoff/latest_codex.md`, Runde 067): Tests fuer
// `AudioCoreDeepSpace`, die Zusammenschaltung von Early Reflections,
// Diffusor und FDN-Tail.
//
// Zwei Gruppen:
//
// 1. TOPOLOGIE — beweist, dass die Kette wirklich so verdrahtet ist, wie der
//    Handoff sie vorgibt (parallel statt seriell, Diffusor vor dem Tail und
//    nicht vor den Reflexionen, Pre-Delay vor der Aufteilung). Ohne diese
//    Tests waere "richtig verdrahtet" eine Behauptung.
// 2. STABILITAET — alle Gates aus S-08a bis S-08c, erneut fuer die KETTE
//    statt fuer die Einzelteile. Die Zusammenschaltung ist der Moment, in dem
//    sich Fehler der Einzelteile gegenseitig verstaerken koennen.

final class AudioCoreDeepSpaceChainTests: XCTestCase {

    private let sampleRate: Double = 44_100

    // MARK: – Hilfen

    private func impulse(count: Int) -> [Float] {
        var signal = Array(repeating: Float(0), count: count)
        signal[0] = 1.0
        return signal
    }

    /// Deterministisches, bipolares Testsignal ohne `Hasher`/`random` —
    /// fester LCG, damit jeder Lauf und jede Maschine dieselbe Folge sieht.
    private func deterministicSignal(count: Int, seed: UInt64 = 0x2545_F491_4F6C_DD1D) -> [Float] {
        var state = seed
        var signal = [Float](repeating: 0, count: count)
        for i in 0..<count {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let unit = Float(Double(state >> 40) / Double(1 << 24))
            signal[i] = (unit * 2.0 - 1.0) * 0.5
        }
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

    /// Deterministischer FNV-1a-Bit-Checksum ueber die rohen Bitmuster —
    /// bewusst kein Swift-`Hasher` (randomisierter Seed pro Prozess).
    /// Identische Implementierung wie in `AudioCoreDeepSpaceFDNTests`.
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

    private func render(_ chain: inout AudioCoreDeepSpace, input: [Float]) -> (left: [Float], right: [Float]) {
        var left = [Float](repeating: 0, count: input.count)
        var right = [Float](repeating: 0, count: input.count)
        for i in 0..<input.count {
            let stereo = chain.process(input[i])
            left[i] = stereo.left
            right[i] = stereo.right
        }
        return (left, right)
    }

    private func chainParameters(preDelaySeconds: Float = 0.0,
                                  earlySize: Float = 0.5,
                                  earlyReflectionMix: Float = 1.0,
                                  diffusion: Float = 0.5,
                                  tailSize: Float = 0.5,
                                  decay: Float = 0.5,
                                  damping: Float = 0.5,
                                  modulationDepth: Float = 0.0,
                                  modulationRate: Float = 0.5,
                                  earlyLevel: Float = AudioCoreDeepSpaceChainParameters.defaultEarlyLevel,
                                  tailLevel: Float = AudioCoreDeepSpaceChainParameters.defaultTailLevel)
    -> AudioCoreDeepSpaceChainParameters {
        AudioCoreDeepSpaceChainParameters(
            early: AudioCoreDeepSpaceParameters(preDelaySeconds: preDelaySeconds,
                                                 size: earlySize,
                                                 earlyReflectionMix: earlyReflectionMix,
                                                 diffusion: diffusion),
            tail: AudioCoreDeepSpaceFDNParameters(size: tailSize,
                                                   decay: decay,
                                                   damping: damping,
                                                   modulationDepth: modulationDepth,
                                                   modulationRate: modulationRate),
            earlyLevel: earlyLevel,
            tailLevel: tailLevel
        )
    }

    // ========================================================================
    // MARK: – Gruppe 1: Topologie
    // ========================================================================

    // MARK: – Die beiden Zweige laufen PARALLEL: die Summe ist exakt die
    //         Summe der beiden einzeln gemessenen Zweige.
    //
    // Ein serielles Hintereinander (Reflexionen -> Diffusor -> Tail) koennte
    // diesen Test nicht bestehen: dort haenge der Tail-Ausgang vom
    // Reflexions-Ausgang ab, und die beiden Einzelmessungen wuerden sich nicht
    // zur Gesamtmessung addieren.

    func test_topology_branchesAreParallel_sumEqualsSumOfBranchesMeasuredAlone() {
        // 16.384 Samples: die kuerzeste FDN-Linie ist bei `tailSize` 0,5 rund
        // 4.410 Samples lang, davor ist der Tail-Zweig exakt still. Ein zu
        // kurzer Render wuerde diesen Test lautlos gegen zwei Nullreihen
        // laufen lassen -- deshalb unten zusaetzlich die Energiepruefung.
        let input = deterministicSignal(count: 16_384)

        var both = AudioCoreDeepSpace(sampleRate: sampleRate,
                                       parameters: chainParameters(earlyLevel: 1.0, tailLevel: 1.0))
        var earlyOnly = AudioCoreDeepSpace(sampleRate: sampleRate,
                                            parameters: chainParameters(earlyLevel: 1.0, tailLevel: 0.0))
        var tailOnly = AudioCoreDeepSpace(sampleRate: sampleRate,
                                           parameters: chainParameters(earlyLevel: 0.0, tailLevel: 1.0))

        let sum = render(&both, input: input)
        let early = render(&earlyOnly, input: input)
        let tail = render(&tailOnly, input: input)

        XCTAssertGreaterThan(energy(early.left[0...]), 0, "Reflexionszweig liefert nichts")
        XCTAssertGreaterThan(energy(tail.left[0...]), 0, "Tail-Zweig liefert nichts -- Render zu kurz?")

        for i in 0..<input.count {
            XCTAssertEqual(sum.left[i], early.left[i] + tail.left[i], accuracy: 1e-6,
                            "Summe != Zweigsumme bei Sample \(i) (links)")
            XCTAssertEqual(sum.right[i], early.right[i] + tail.right[i], accuracy: 1e-6,
                            "Summe != Zweigsumme bei Sample \(i) (rechts)")
        }
    }

    // MARK: – Der Diffusor sitzt VOR dem Tail und NICHT vor den Reflexionen.
    //
    // Direkter Nachweis statt Behauptung: `diffusion` von 0 auf 1 zu drehen
    // muss den Reflexionszweig BIT-IDENTISCH lassen und den Tail-Zweig
    // messbar veraendern. Ein Diffusor vor den Reflexionen (oder vor dem
    // Split) wuerde die erste Haelfte sofort brechen.

    func test_topology_diffuserFeedsTailOnly_notTheEarlyReflections() {
        // Laenger als die kuerzeste FDN-Linie (~4.410 Samples bei `tailSize`
        // 0,5), sonst ist der Tail-Zweig noch still und die zweite Haelfte des
        // Tests vergliche zwei Nullreihen.
        let input = deterministicSignal(count: 16_384)

        var earlyNoDiffusion = AudioCoreDeepSpace(
            sampleRate: sampleRate,
            parameters: chainParameters(diffusion: 0.0, earlyLevel: 1.0, tailLevel: 0.0))
        var earlyFullDiffusion = AudioCoreDeepSpace(
            sampleRate: sampleRate,
            parameters: chainParameters(diffusion: 1.0, earlyLevel: 1.0, tailLevel: 0.0))

        let a = render(&earlyNoDiffusion, input: input)
        let b = render(&earlyFullDiffusion, input: input)

        XCTAssertEqual(fnv1aChecksum(a.left), fnv1aChecksum(b.left),
                        "Diffusion veraendert den Reflexionszweig -- der Diffusor sitzt falsch")
        XCTAssertEqual(fnv1aChecksum(a.right), fnv1aChecksum(b.right),
                        "Diffusion veraendert den Reflexionszweig -- der Diffusor sitzt falsch")

        var tailNoDiffusion = AudioCoreDeepSpace(
            sampleRate: sampleRate,
            parameters: chainParameters(diffusion: 0.0, earlyLevel: 0.0, tailLevel: 1.0))
        var tailFullDiffusion = AudioCoreDeepSpace(
            sampleRate: sampleRate,
            parameters: chainParameters(diffusion: 1.0, earlyLevel: 0.0, tailLevel: 1.0))

        let c = render(&tailNoDiffusion, input: input)
        let d = render(&tailFullDiffusion, input: input)

        XCTAssertGreaterThan(energy(c.left[0...]), 0, "Tail-Zweig liefert nichts -- Render zu kurz?")

        let differenceRMS = (zip(c.left, d.left).reduce(Float(0)) { accumulator, pair in
            accumulator + (pair.0 - pair.1) * (pair.0 - pair.1)
        } / Float(input.count)).squareRoot()
        XCTAssertGreaterThan(differenceRMS, 1e-4,
                              "Diffusion wirkt nicht auf den Tail-Zweig -- der Diffusor ist nicht angeschlossen")
    }

    // MARK: – Das Pre-Delay sitzt VOR der Aufteilung und verzoegert beide
    //         Zweige exakt gleich.
    //
    // Bei Modulationstiefe 0 ist die gesamte Kette linear und zeitinvariant.
    // Eine Eingangsverzoegerung um N Samples muss dann eine Ausgangs-
    // verzoegerung um exakt dieselben N Samples ergeben -- und zwar
    // bit-identisch, auf BEIDEN Zweigen. Laege das Pre-Delay nur im
    // Reflexionszweig (der Zustand vor diesem Slice), waere der Tail-Zweig
    // unverschoben und der Test schluege fehl.

    func test_topology_preDelayShiftsBothBranchesEqually_bitExact() {
        let preDelaySeconds: Float = 0.01
        let expectedShift = Int((Double(preDelaySeconds) * sampleRate).rounded()) // 441
        let length = 8_192

        var withoutPreDelay = AudioCoreDeepSpace(
            sampleRate: sampleRate,
            parameters: chainParameters(preDelaySeconds: 0.0, earlyLevel: 1.0, tailLevel: 1.0))
        var withPreDelay = AudioCoreDeepSpace(
            sampleRate: sampleRate,
            parameters: chainParameters(preDelaySeconds: preDelaySeconds, earlyLevel: 1.0, tailLevel: 1.0))

        let reference = render(&withoutPreDelay, input: impulse(count: length))
        let delayed = render(&withPreDelay, input: impulse(count: length))

        XCTAssertEqual(fnv1aChecksum(Array(reference.left[0..<(length - expectedShift)])),
                        fnv1aChecksum(Array(delayed.left[expectedShift..<length])),
                        "Pre-Delay verschiebt den linken Ausgang nicht um exakt \(expectedShift) Samples")
        XCTAssertEqual(fnv1aChecksum(Array(reference.right[0..<(length - expectedShift)])),
                        fnv1aChecksum(Array(delayed.right[expectedShift..<length])),
                        "Pre-Delay verschiebt den rechten Ausgang nicht um exakt \(expectedShift) Samples")

        for i in 0..<expectedShift {
            XCTAssertEqual(delayed.left[i], 0.0, "Vor dem Pre-Delay darf links noch nichts anliegen")
            XCTAssertEqual(delayed.right[i], 0.0, "Vor dem Pre-Delay darf rechts noch nichts anliegen")
        }
    }

    func test_topology_defaultPreDelayIsZero_andPassesThroughWithoutLatency() {
        var chain = AudioCoreDeepSpace(sampleRate: sampleRate,
                                        parameters: chainParameters(preDelaySeconds: 0.0,
                                                                     earlySize: 0.0,
                                                                     earlyLevel: 1.0,
                                                                     tailLevel: 0.0))
        // Tap 0 liegt bei size = 0 bei 15 ms * 0.05 = 0.75 ms (33 Samples).
        // Ohne zusaetzliches Pre-Delay muss die erste Reflexion genau dort
        // stehen, nicht spaeter.
        let response = render(&chain, input: impulse(count: 512))
        let firstNonZero = response.left.firstIndex { $0 != 0 }
        XCTAssertEqual(firstNonZero, 33,
                        "Default-Pre-Delay ist nicht 0 -- erste Reflexion bei \(String(describing: firstNonZero))")
    }

    // MARK: – Gate 8: bei Modulationstiefe 0 ist der Tail-Anteil der Kette
    //         bit-identisch zum einzeln betriebenen Baustein.
    //
    // Beweist, dass die Zusammenschaltung nichts verschiebt: derselbe
    // Diffusor, derselbe Tail, dieselben Werte -- Bit fuer Bit.

    func test_gate8_tailBranch_isBitIdenticalToStandaloneBuildingBlocks_atZeroModulation() {
        let parameters = chainParameters(diffusion: 0.7,
                                          tailSize: 0.6,
                                          decay: 0.8,
                                          damping: 0.3,
                                          modulationDepth: 0.0,
                                          earlyLevel: 0.0,
                                          tailLevel: 1.0)
        var chain = AudioCoreDeepSpace(sampleRate: sampleRate, parameters: parameters)

        // Referenz: dieselben zwei Bausteine, von Hand hintereinander
        // geschaltet, mit exakt den Parametern, die die Kette ihnen uebergibt
        // (Pre-Delay 0, weil die Kette es selbst vor der Aufteilung anwendet).
        let branch = AudioCoreDeepSpaceParameters(preDelaySeconds: 0,
                                                   size: parameters.early.size,
                                                   earlyReflectionMix: parameters.early.earlyReflectionMix,
                                                   diffusion: parameters.early.diffusion)
        var referenceDiffuser = AudioCoreDeepSpaceDiffuser(sampleRate: sampleRate, parameters: branch)
        var referenceTail = AudioCoreDeepSpaceFDNTail(sampleRate: sampleRate, parameters: parameters.tail)

        let input = impulse(count: 8_192)
        let chainOutput = render(&chain, input: input)

        var referenceLeft = [Float](repeating: 0, count: input.count)
        var referenceRight = [Float](repeating: 0, count: input.count)
        for i in 0..<input.count {
            let diffused = referenceDiffuser.process(left: input[i], right: input[i])
            let stereo = referenceTail.process(left: diffused.left, right: diffused.right)
            referenceLeft[i] = stereo.left
            referenceRight[i] = stereo.right
        }

        XCTAssertEqual(fnv1aChecksum(chainOutput.left), fnv1aChecksum(referenceLeft),
                        "Tail-Zweig der Kette weicht vom Einzelbaustein ab (links)")
        XCTAssertEqual(fnv1aChecksum(chainOutput.right), fnv1aChecksum(referenceRight),
                        "Tail-Zweig der Kette weicht vom Einzelbaustein ab (rechts)")
    }

    // MARK: – Gegenstueck: der Reflexionszweig ist ebenfalls bit-identisch
    //         zum Einzelbaustein.

    func test_earlyBranch_isBitIdenticalToStandaloneBuildingBlock() {
        let parameters = chainParameters(earlySize: 0.8,
                                          earlyReflectionMix: 0.6,
                                          earlyLevel: 1.0,
                                          tailLevel: 0.0)
        var chain = AudioCoreDeepSpace(sampleRate: sampleRate, parameters: parameters)

        var reference = AudioCoreDeepSpaceEarlyReflections(
            sampleRate: sampleRate,
            parameters: AudioCoreDeepSpaceParameters(preDelaySeconds: 0,
                                                      size: parameters.early.size,
                                                      earlyReflectionMix: parameters.early.earlyReflectionMix,
                                                      diffusion: parameters.early.diffusion))

        let input = deterministicSignal(count: 4_096)
        let chainOutput = render(&chain, input: input)
        let referenceOutput = input.map { reference.process($0) }

        XCTAssertEqual(fnv1aChecksum(chainOutput.left), fnv1aChecksum(referenceOutput.map { $0.left }))
        XCTAssertEqual(fnv1aChecksum(chainOutput.right), fnv1aChecksum(referenceOutput.map { $0.right }))
    }

    // MARK: – Die vorlaeufigen Zweigpegel wirken linear und unabhaengig.

    func test_branchLevels_scaleTheirBranchLinearly() {
        let input = deterministicSignal(count: 2_048)

        var full = AudioCoreDeepSpace(sampleRate: sampleRate,
                                       parameters: chainParameters(earlyLevel: 1.0, tailLevel: 0.0))
        var half = AudioCoreDeepSpace(sampleRate: sampleRate,
                                       parameters: chainParameters(earlyLevel: 0.5, tailLevel: 0.0))

        let a = render(&full, input: input)
        let b = render(&half, input: input)

        for i in 0..<input.count {
            XCTAssertEqual(b.left[i], a.left[i] * 0.5, accuracy: 1e-7)
            XCTAssertEqual(b.right[i], a.right[i] * 0.5, accuracy: 1e-7)
        }
    }

    func test_defaultBranchLevels_areEqualAndConservative() {
        // Dokumentiert den vorlaeufigen Startwert explizit im Test, damit ein
        // spaeteres, bewusstes Aendern durch Stephan als Testaenderung
        // sichtbar wird und nicht unbemerkt durchrutscht.
        XCTAssertEqual(AudioCoreDeepSpaceChainParameters.defaultEarlyLevel, 0.5)
        XCTAssertEqual(AudioCoreDeepSpaceChainParameters.defaultTailLevel, 0.5)

        let defaults = AudioCoreDeepSpaceChainParameters()
        XCTAssertEqual(defaults.earlyLevel, defaults.tailLevel,
                        "Ungleiche Default-Zweigpegel waeren bereits eine Klangentscheidung")
    }

    func test_stereoOutput_isDefinedAndNotIdenticalOnBothChannels() {
        var chain = AudioCoreDeepSpace(sampleRate: sampleRate, parameters: chainParameters())
        let output = render(&chain, input: impulse(count: 8_192))

        XCTAssertTrue(output.left.allSatisfy { $0.isFinite })
        XCTAssertTrue(output.right.allSatisfy { $0.isFinite })
        XCTAssertNotEqual(fnv1aChecksum(output.left), fnv1aChecksum(output.right),
                           "Links und rechts sind identisch -- kein definierter Stereo-Ausgang")
    }

    // ========================================================================
    // MARK: – Gruppe 2: Stabilitaet (S-08a bis S-08c, erneut fuer die Kette)
    // ========================================================================

    // MARK: – Gate 1: Determinismus, bit-exakt

    func test_gate1_reset_reproducesIdenticalOutput_bitExact() {
        var chain = AudioCoreDeepSpace(
            sampleRate: sampleRate,
            parameters: chainParameters(preDelaySeconds: 0.03, earlySize: 0.6, diffusion: 0.7,
                                         tailSize: 0.6, decay: 0.7, damping: 0.4,
                                         modulationDepth: 0.8, modulationRate: 0.6))
        let input = deterministicSignal(count: 8_192)

        let first = render(&chain, input: input)
        chain.reset()
        let second = render(&chain, input: input)

        XCTAssertEqual(first.left, second.left)
        XCTAssertEqual(first.right, second.right)
    }

    func test_gate1_isDeterministicAcrossIndependentlyConstructedInstances() {
        let parameters = chainParameters(preDelaySeconds: 0.02, earlySize: 0.4, diffusion: 0.3,
                                          tailSize: 0.4, decay: 0.5, damping: 0.6,
                                          modulationDepth: 0.5, modulationRate: 0.4)
        var a = AudioCoreDeepSpace(sampleRate: sampleRate, parameters: parameters)
        var b = AudioCoreDeepSpace(sampleRate: sampleRate, parameters: parameters)

        let input = deterministicSignal(count: 4_096)
        let outputA = render(&a, input: input)
        let outputB = render(&b, input: input)

        XCTAssertEqual(outputA.left, outputB.left)
        XCTAssertEqual(outputA.right, outputB.right)
    }

    // MARK: – Gate 2: alle Ausgaben finite, ueber lange Renders und an allen
    //         Parametergrenzen

    func test_gate2_impulseResponse_isFiniteOverLongRender_atMaximumEverything() {
        var chain = AudioCoreDeepSpace(
            sampleRate: sampleRate,
            parameters: chainParameters(preDelaySeconds: 1.0,   // wird auf 0.1 geklemmt
                                         earlySize: 1.0, earlyReflectionMix: 1.0, diffusion: 1.0,
                                         tailSize: 1.0, decay: 1.0, damping: 0.0,
                                         modulationDepth: 1.0, modulationRate: 1.0,
                                         earlyLevel: 1.0, tailLevel: 1.0))
        let output = render(&chain, input: impulse(count: Int(sampleRate * 10)))

        XCTAssertTrue(output.left.allSatisfy { $0.isFinite })
        XCTAssertTrue(output.right.allSatisfy { $0.isFinite })
    }

    func test_gate2_extremeParameterGrid_staysFinite() {
        let extremeUnit: [Float] = [0.0, 1.0, .nan, .infinity, -1.0, 2.0]
        let extremeInputs: [Float] = [0.0, 1.0, -1.0, .nan, .infinity, -.infinity, 1e30]

        for size in extremeUnit {
            for decay in extremeUnit {
                for diffusion in extremeUnit {
                    for level in extremeUnit {
                        var chain = AudioCoreDeepSpace(
                            sampleRate: sampleRate,
                            parameters: chainParameters(preDelaySeconds: size,
                                                         earlySize: size,
                                                         earlyReflectionMix: level,
                                                         diffusion: diffusion,
                                                         tailSize: size,
                                                         decay: decay,
                                                         damping: diffusion,
                                                         modulationDepth: level,
                                                         modulationRate: decay,
                                                         earlyLevel: level,
                                                         tailLevel: level))
                        for input in extremeInputs {
                            let stereo = chain.process(input)
                            XCTAssertTrue(stereo.left.isFinite,
                                          "links nicht-endlich bei size=\(size), decay=\(decay), diffusion=\(diffusion), level=\(level), input=\(input)")
                            XCTAssertTrue(stereo.right.isFinite,
                                          "rechts nicht-endlich bei size=\(size), decay=\(decay), diffusion=\(diffusion), level=\(level), input=\(input)")
                        }
                    }
                }
            }
        }
    }

    // MARK: – Gate 3: Stabilitaetsgates der Einzelteile gelten fuer die Kette
    //
    // Monoton fallende Fensterenergie ohne Plateau, im strengsten Fall:
    // maximales `decay`, maximale `size`, maximale Diffusion, maximale
    // Modulation, keine Daempfung.

    func test_gate3_windowedEnergy_decaysMonotonically_atStrictestParameters() {
        var chain = AudioCoreDeepSpace(
            sampleRate: sampleRate,
            parameters: chainParameters(earlySize: 1.0, diffusion: 1.0,
                                         tailSize: 1.0, decay: 1.0, damping: 0.0,
                                         modulationDepth: 1.0, modulationRate: 1.0,
                                         earlyLevel: 1.0, tailLevel: 1.0))
        let output = render(&chain, input: impulse(count: Int(sampleRate * 6)))
        let mono = zip(output.left, output.right).map { $0 + $1 }

        let blockSize = Int(sampleRate * 0.5)
        let blocks = blockEnergies(mono, blockSize: blockSize)

        for i in 1..<(blocks.count - 1) {
            XCTAssertLessThanOrEqual(blocks[i + 1], blocks[i] * 1.03,
                                      "Energie waechst zwischen Block \(i) und \(i+1): \(blocks[i]) -> \(blocks[i+1])")
        }
        XCTAssertLessThan(blocks.last!, blocks[1] * 0.7,
                           "Kein messbarer Abfall -- Plateau statt Abklingen")
    }

    func test_gate3_decaysAfterInputStops_atStrictestParameters() {
        var chain = AudioCoreDeepSpace(
            sampleRate: sampleRate,
            parameters: chainParameters(earlySize: 1.0, diffusion: 1.0,
                                         tailSize: 1.0, decay: 1.0, damping: 0.0,
                                         modulationDepth: 1.0, modulationRate: 1.0,
                                         earlyLevel: 1.0, tailLevel: 1.0))
        var burst = impulse(count: 2_000)
        burst.append(contentsOf: Array(repeating: Float(0), count: Int(sampleRate * 5)))

        let output = render(&chain, input: burst)
        let mono = zip(output.left, output.right).map { $0 + $1 }
        let blocks = blockEnergies(mono, blockSize: Int(sampleRate * 0.5))

        XCTAssertLessThan(blocks.last!, blocks[1],
                           "Kette klingt nach Eingangsstopp nicht ab: frueh=\(blocks[1]), spaet=\(blocks.last!)")
    }

    func test_gate3_decaysAfterInputStops_atShortestLinesAndLongestDecay() {
        // Rechnerisch engster Fall aus S-08b: kurze Linien (size = 0) haben
        // pro Sekunde mehr Umlaeufe und damit einen groesseren Rundlauf-Gain
        // je Umlauf fuer dasselbe RT60.
        var chain = AudioCoreDeepSpace(
            sampleRate: sampleRate,
            parameters: chainParameters(earlySize: 0.0, diffusion: 1.0,
                                         tailSize: 0.0, decay: 1.0, damping: 0.0,
                                         modulationDepth: 1.0, modulationRate: 1.0,
                                         earlyLevel: 1.0, tailLevel: 1.0))
        var burst = impulse(count: 500)
        burst.append(contentsOf: Array(repeating: Float(0), count: Int(sampleRate * 5)))

        let output = render(&chain, input: burst)
        let mono = zip(output.left, output.right).map { $0 + $1 }
        let blocks = blockEnergies(mono, blockSize: Int(sampleRate * 0.5))

        XCTAssertLessThan(blocks.last!, blocks[1],
                           "Kette klingt bei kuerzesten Linien nicht ab: frueh=\(blocks[1]), spaet=\(blocks.last!)")
    }

    // MARK: – Gate 5: Blockgroessen-Unabhaengigkeit
    //
    // 37 ist bewusst kein Teiler von 8192 und teilt auch keine der internen
    // Perioden (Tap-Verzoegerungen, Allpass-Laengen, Primzahl-Linienlaengen).

    func test_gate5_render_isInvariantToBlockSegmentation() {
        let parameters = chainParameters(preDelaySeconds: 0.02, diffusion: 0.6,
                                          decay: 0.7, modulationDepth: 0.6)
        let input = deterministicSignal(count: 8_192)

        func renderInBlocks(_ blockSize: Int) -> (left: [Float], right: [Float]) {
            var chain = AudioCoreDeepSpace(sampleRate: sampleRate, parameters: parameters)
            var left = [Float](repeating: 0, count: input.count)
            var right = [Float](repeating: 0, count: input.count)

            var offset = 0
            while offset < input.count {
                let frames = min(blockSize, input.count - offset)
                input.withUnsafeBufferPointer { inputPointer in
                    left.withUnsafeMutableBufferPointer { leftPointer in
                        right.withUnsafeMutableBufferPointer { rightPointer in
                            chain.render(input: inputPointer.baseAddress! + offset,
                                          intoL: leftPointer.baseAddress! + offset,
                                          intoR: rightPointer.baseAddress! + offset,
                                          frameCount: frames)
                        }
                    }
                }
                offset += frames
            }
            return (left, right)
        }

        let reference = renderInBlocks(input.count)
        for blockSize in [1_024, 256, 37, 1] {
            let segmented = renderInBlocks(blockSize)
            XCTAssertEqual(fnv1aChecksum(reference.left), fnv1aChecksum(segmented.left),
                            "Blockgroesse \(blockSize) veraendert den linken Ausgang")
            XCTAssertEqual(fnv1aChecksum(reference.right), fnv1aChecksum(segmented.right),
                            "Blockgroesse \(blockSize) veraendert den rechten Ausgang")
        }
    }

    func test_gate5_render_writesAdditively() {
        let input = deterministicSignal(count: 512)
        var chain = AudioCoreDeepSpace(sampleRate: sampleRate, parameters: chainParameters())

        var left = [Float](repeating: 1.0, count: input.count)
        var right = [Float](repeating: -2.0, count: input.count)
        input.withUnsafeBufferPointer { inputPointer in
            left.withUnsafeMutableBufferPointer { leftPointer in
                right.withUnsafeMutableBufferPointer { rightPointer in
                    chain.render(input: inputPointer.baseAddress!,
                                  intoL: leftPointer.baseAddress!,
                                  intoR: rightPointer.baseAddress!,
                                  frameCount: input.count)
                }
            }
        }

        var direct = AudioCoreDeepSpace(sampleRate: sampleRate, parameters: chainParameters())
        let expected = render(&direct, input: input)
        for i in 0..<input.count {
            XCTAssertEqual(left[i], 1.0 + expected.left[i], accuracy: 1e-7)
            XCTAssertEqual(right[i], -2.0 + expected.right[i], accuracy: 1e-7)
        }
    }

    // MARK: – Gate 6: Post-Init-Mutationspfad ueber `setParameters(_:)`

    func test_gate6_parameters_clampNonFiniteAndOutOfRangeValues() {
        let parameters = AudioCoreDeepSpaceChainParameters(
            early: AudioCoreDeepSpaceParameters(preDelaySeconds: 5.0, size: -1.0,
                                                 earlyReflectionMix: 2.0, diffusion: .nan),
            tail: AudioCoreDeepSpaceFDNParameters(size: .infinity, decay: -3.0, damping: 7.0,
                                                   modulationDepth: .nan, modulationRate: 2.0),
            earlyLevel: .infinity,
            tailLevel: -4.0)

        XCTAssertEqual(parameters.early.preDelaySeconds, AudioCoreDeepSpaceParameters.maxPreDelaySeconds)
        XCTAssertEqual(parameters.early.size, 0.0)
        XCTAssertEqual(parameters.early.earlyReflectionMix, 1.0)
        XCTAssertEqual(parameters.early.diffusion, 0.0)
        XCTAssertEqual(parameters.tail.decay, 0.0)
        XCTAssertEqual(parameters.tail.damping, 1.0)
        XCTAssertEqual(parameters.tail.modulationDepth, 0.0)
        XCTAssertEqual(parameters.tail.modulationRate, 1.0)
        XCTAssertEqual(parameters.tailLevel, 0.0)

        // Nicht-endliche Werte fallen NICHT auf die naechste Bereichsgrenze,
        // sondern auf den Fallback des Feldes (`clampUnit` -> 0). Das ist das
        // Verhalten aller bestehenden `HarmonyAudioCore`-Parametertypen; eine
        // eigene Sonderregel nur fuer diesen Typ waere eine Inkonsistenz.
        // `.infinity` ergibt deshalb 0, nicht 1.
        XCTAssertEqual(parameters.tail.size, 0.0)
        XCTAssertEqual(parameters.earlyLevel, 0.0)
    }

    /// Baut einen Parametersatz ueber DIREKTE Feldmutation nach `init` — genau
    /// der Pfad, der die Klemmung im `init` umgehen wuerde (Finding S-08a-01).
    private func mutatedChainParameters(_ value: Float) -> AudioCoreDeepSpaceChainParameters {
        var parameters = AudioCoreDeepSpaceChainParameters()
        parameters.early.preDelaySeconds = value
        parameters.early.size = value
        parameters.early.earlyReflectionMix = value
        parameters.early.diffusion = value
        parameters.tail.size = value
        parameters.tail.decay = value
        parameters.tail.damping = value
        parameters.tail.modulationDepth = value
        parameters.tail.modulationRate = value
        parameters.earlyLevel = value
        parameters.tailLevel = value
        return parameters
    }

    func test_gate6_setParameters_postInitMutation_clampsAndStaysFinite() {
        let hostileValues: [Float] = [.nan, .infinity, -.infinity, -5.0, 42.0, 1e30]

        for value in hostileValues {
            var chain = AudioCoreDeepSpace(sampleRate: sampleRate, parameters: chainParameters())
            chain.setParameters(mutatedChainParameters(value))

            XCTAssertTrue(chain.parameters.early.preDelaySeconds.isFinite, "preDelaySeconds bei \(value)")
            XCTAssertTrue((0.0...1.0).contains(chain.parameters.early.size), "size bei \(value)")
            XCTAssertTrue((0.0...1.0).contains(chain.parameters.tail.decay), "decay bei \(value)")
            XCTAssertTrue((0.0...1.0).contains(chain.parameters.earlyLevel), "earlyLevel bei \(value)")
            XCTAssertTrue((0.0...1.0).contains(chain.parameters.tailLevel), "tailLevel bei \(value)")

            for input in [Float(0.0), 1.0, -1.0, .nan, .infinity] {
                let stereo = chain.process(input)
                XCTAssertTrue(stereo.left.isFinite, "links nicht-endlich nach Mutation \(value), input=\(input)")
                XCTAssertTrue(stereo.right.isFinite, "rechts nicht-endlich nach Mutation \(value), input=\(input)")
            }
        }
    }

    func test_gate6_constructorAlsoClampsMutatedParameters() {
        // Der `init` muss denselben Schutz bieten wie `setParameters(_:)` —
        // sonst haette der Mutationspfad zwei unterschiedlich sichere Tueren.
        var chain = AudioCoreDeepSpace(sampleRate: sampleRate,
                                        parameters: mutatedChainParameters(.nan))
        XCTAssertTrue((0.0...1.0).contains(chain.parameters.early.size))
        XCTAssertTrue((0.0...1.0).contains(chain.parameters.tailLevel))
        for _ in 0..<128 {
            let stereo = chain.process(1.0)
            XCTAssertTrue(stereo.left.isFinite)
            XCTAssertTrue(stereo.right.isFinite)
        }
    }

    func test_gate6_setParameters_doesNotResetRunningState() {
        // Eine Parameteraenderung an einem klingenden Raum darf den Hallfahnen-
        // Zustand nicht loeschen — sonst waere jede Bedienbewegung in W-03 ein
        // hoerbarer Abriss.
        var chain = AudioCoreDeepSpace(sampleRate: sampleRate, parameters: chainParameters())
        _ = render(&chain, input: impulse(count: 4_096))

        chain.setParameters(chainParameters(decay: 0.9))
        let afterChange = render(&chain, input: Array(repeating: Float(0), count: 512))

        XCTAssertGreaterThan(energy(afterChange.left[0..<512]), 0,
                              "setParameters(_:) hat den laufenden Hallfahnen-Zustand geloescht")
    }

    // MARK: – Gate 7: Sample-Rate-Grenzen, Ober- UND Untergrenze

    func test_gate7_extremeSampleRates_stayFiniteAndStable() {
        let rates: [Double] = [
            AudioCoreDeepSpaceParameters.minSampleRate,
            AudioCoreDeepSpaceParameters.maxSampleRate,
            0.001, 0.0, -1.0, 1.0, 100.0, 8_000.0, 44_100.0, 48_000.0, 96_000.0, 192_000.0,
            1e300, .greatestFiniteMagnitude, .nan, .infinity
        ]

        for rate in rates {
            var chain = AudioCoreDeepSpace(
                sampleRate: rate,
                parameters: chainParameters(preDelaySeconds: 0.1, earlySize: 1.0, diffusion: 1.0,
                                             tailSize: 1.0, decay: 1.0, damping: 0.0,
                                             modulationDepth: 1.0, modulationRate: 1.0,
                                             earlyLevel: 1.0, tailLevel: 1.0))

            XCTAssertGreaterThanOrEqual(chain.sampleRate, AudioCoreDeepSpaceParameters.minSampleRate,
                                         "Sample Rate \(rate) nicht nach unten geklemmt")
            XCTAssertLessThanOrEqual(chain.sampleRate, AudioCoreDeepSpaceParameters.maxSampleRate,
                                      "Sample Rate \(rate) nicht nach oben geklemmt")

            let output = render(&chain, input: impulse(count: 4_096))
            XCTAssertTrue(output.left.allSatisfy { $0.isFinite }, "links nicht-endlich bei Sample Rate \(rate)")
            XCTAssertTrue(output.right.allSatisfy { $0.isFinite }, "rechts nicht-endlich bei Sample Rate \(rate)")
        }
    }

    func test_gate7_prepare_atNewSampleRate_staysFiniteAndDeterministic() {
        let parameters = chainParameters(preDelaySeconds: 0.05, diffusion: 0.6, decay: 0.7,
                                          modulationDepth: 0.5)
        var prepared = AudioCoreDeepSpace(sampleRate: 44_100, parameters: parameters)
        prepared.prepare(sampleRate: 96_000)

        var fresh = AudioCoreDeepSpace(sampleRate: 96_000, parameters: parameters)

        let input = deterministicSignal(count: 4_096)
        let a = render(&prepared, input: input)
        let b = render(&fresh, input: input)

        XCTAssertEqual(prepared.sampleRate, 96_000)
        XCTAssertEqual(a.left, b.left, "prepare(sampleRate:) erzeugt nicht denselben Zustand wie ein frischer Bau")
        XCTAssertEqual(a.right, b.right)
    }

    // MARK: – Speicherbudget der Pre-Delay-Linie an der Sample-Rate-Obergrenze

    func test_preDelayBuffer_atMaxSampleRate_isConservativelyBounded() {
        // 100 ms bei 1 MHz = 100.000 Samples = 400 KB. Ein Bruchteil dessen,
        // was die acht FDN-Linien dort belegen (~9,3 MB, S-08b).
        let capacity = Int((Double(AudioCoreDeepSpaceParameters.maxPreDelaySeconds)
                             * AudioCoreDeepSpaceParameters.maxSampleRate).rounded(.up)) + 4
        XCTAssertLessThan(capacity * MemoryLayout<Float>.size, 1_000_000)
    }
}
