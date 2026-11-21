import XCTest
@testable import HarmonyAudioCore

// MARK: – AudioCoreAtmosphericVoiceTests
//
// W-01 (`.agent_handoff/latest_codex.md`, Runde 066): Gates 1-5 und 7-9 des
// Handoffs.
//
//  1. Determinismus (Reset UND zwei unabhaengig konstruierte Instanzen)
//  2. finite Ausgaben ueber lange Renders und an den Parametergrenzen
//  3. jedes der sieben Modulationsziele hat eine nachweisbare Wirkung
//     (ein Test pro Ziel)
//  4. `spaceSend` ist lesbar und wird in der Stimme NICHT angewendet
//  5. Huellkurven-Zeitverhalten bei zwei Sample-Raten
//  7. Post-Init-Mutationspfad ueber `setParameters(_:)` klemmt
//  8. Sample-Rate-Grenzen inkl. Ober- und Untergrenze
//  9. Kontrollraten-Modulation erzeugt keine hoerbaren Stufen
//
// Gate 6 (Allokationsfreiheit) ist per SIL belegt, nicht per Test — siehe
// Ruecklauf Runde 066.

final class AudioCoreAtmosphericVoiceTests: XCTestCase {

    // MARK: – Render-Hilfen

    /// Rendert `frames` Samples in einem Stueck und liefert beide Kanaele.
    private func render(_ voice: inout AudioCoreAtmosphericVoice, frames: Int) -> (l: [Float], r: [Float]) {
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        _ = left.withUnsafeMutableBufferPointer { lb in
            _ = right.withUnsafeMutableBufferPointer { rb in
                voice.render(intoL: lb.baseAddress!, intoR: rb.baseAddress!, frameCount: frames)
            }
        }
        return (left, right)
    }

    /// Rendert `frames` Samples in Bloecken von `chunk` Samples.
    private func renderChunked(_ voice: inout AudioCoreAtmosphericVoice,
                                frames: Int,
                                chunk: Int) -> (l: [Float], r: [Float]) {
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        var offset = 0
        while offset < frames {
            let count = min(chunk, frames - offset)
            _ = left.withUnsafeMutableBufferPointer { lb in
                _ = right.withUnsafeMutableBufferPointer { rb in
                    voice.render(intoL: lb.baseAddress! + offset,
                                 intoR: rb.baseAddress! + offset,
                                 frameCount: count)
                }
            }
            offset += count
        }
        return (left, right)
    }

    /// Bit-exakter Vergleich zweier Renders (kein Toleranzvergleich —
    /// Determinismus heisst hier bitgenau, nicht "aehnlich").
    private func assertBitIdentical(_ lhs: [Float], _ rhs: [Float],
                                     _ message: String,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.count, rhs.count, message, file: file, line: line)
        for index in 0..<min(lhs.count, rhs.count) where lhs[index].bitPattern != rhs[index].bitPattern {
            XCTFail("\(message) — erste Abweichung bei Index \(index): \(lhs[index]) vs \(rhs[index])",
                    file: file, line: line)
            return
        }
    }

    private func rms(_ samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Double = 0
        for value in samples { sum += Double(value) * Double(value) }
        return Float((sum / Double(samples.count)).squareRoot())
    }

    private func allFinite(_ samples: [Float]) -> Bool {
        for value in samples where !value.isFinite { return false }
        return true
    }

    /// Standardstimme mit dem Default-Patch, bereits auf Note 60 konfiguriert.
    private func makeVoice(sampleRate: Double = 48_000,
                            parameters: AudioCoreAtmosphericVoiceParameters = .defaults,
                            note: UInt8 = 60,
                            velocity: UInt8 = 100,
                            activationOrder: UInt64 = 7) -> AudioCoreAtmosphericVoice {
        var voice = AudioCoreAtmosphericVoice(sampleRate: sampleRate)
        voice.configure(note: note,
                        velocity: velocity,
                        sampleRate: sampleRate,
                        parameters: parameters,
                        activationOrder: activationOrder)
        return voice
    }

    /// Patch mit genau einer Route `motion -> target` und gesetztem Makro.
    /// Die Felder werden bewusst per Post-Init-Mutation gesetzt — die Stimme
    /// klemmt sie in `setParameters(_:)` ohnehin neu (Gate 7).
    private func makeRoutedParameters(target: AudioCoreModulationTarget,
                                       amount: Float,
                                       motion: Float,
                                       base: AudioCoreAtmosphericVoiceParameters = .defaults)
        -> AudioCoreAtmosphericVoiceParameters {
        var parameters = base
        parameters.modulationMatrix = AudioCoreModulationMatrix(routes: [
            AudioCoreModulationRoute(source: .macro(.motion), target: target, amount: amount)
        ])
        parameters.macros = AudioCoreMacroValues(motion: motion)
        return parameters
    }

    // MARK: – 0. Grundfunktion: die Stimme erzeugt ueberhaupt einen Ton

    func test_defaultPatch_producesAudibleSignal() {
        var voice = makeVoice()
        let output = render(&voice, frames: 4_800)

        XCTAssertTrue(voice.isActive)
        XCTAssertGreaterThan(rms(output.l[2_400...]), 0.01, "Default-Patch muss hoerbar sein")
        XCTAssertTrue(allFinite(output.l) && allFinite(output.r))
    }

    func test_render_accumulatesAdditivelyIntoCallerBuffers() {
        var voice = makeVoice()
        var left = [Float](repeating: 0.5, count: 512)
        var right = [Float](repeating: 0.5, count: 512)
        _ = left.withUnsafeMutableBufferPointer { lb in
            _ = right.withUnsafeMutableBufferPointer { rb in
                voice.render(intoL: lb.baseAddress!, intoR: rb.baseAddress!, frameCount: 512)
            }
        }
        // Additiver Vertrag wie bei der Legacy-Voice: der Vorbelegungswert
        // bleibt erhalten, die Stimme addiert nur.
        XCTAssertNotEqual(left[400], 0.5)
        XCTAssertGreaterThan(left[400], 0.0)
    }

    // MARK: – Gate 1: Determinismus

    func test_twoIndependentlyConstructedVoices_produceBitIdenticalOutput() {
        var first = makeVoice()
        var second = makeVoice()

        let a = render(&first, frames: 8_192)
        let b = render(&second, frames: 8_192)

        assertBitIdentical(a.l, b.l, "Zwei unabhaengig konstruierte Stimmen muessen bit-identisch rendern (L)")
        assertBitIdentical(a.r, b.r, "Zwei unabhaengig konstruierte Stimmen muessen bit-identisch rendern (R)")
    }

    func test_reconfigure_reproducesIdenticalOutput() {
        var voice = makeVoice()
        let first = render(&voice, frames: 4_096)

        voice.configure(note: 60, velocity: 100, sampleRate: 48_000,
                        parameters: .defaults, activationOrder: 7)
        let second = render(&voice, frames: 4_096)

        assertBitIdentical(first.l, second.l, "Erneutes configure() muss denselben Verlauf reproduzieren")
    }

    func test_render_isInvariantToBlockSegmentation() {
        var whole = makeVoice()
        var inChunks = makeVoice()
        var tiny = makeVoice()

        let a = render(&whole, frames: 4_096)
        let b = renderChunked(&inChunks, frames: 4_096, chunk: 256)
        let c = renderChunked(&tiny, frames: 4_096, chunk: 7)

        assertBitIdentical(a.l, b.l, "256er-Bloecke muessen bit-identisch zum Render am Stueck sein")
        assertBitIdentical(a.l, c.l, "7er-Bloecke muessen bit-identisch zum Render am Stueck sein — "
                            + "die Kontrollperiode darf nicht an frameCount haengen")
    }

    // MARK: – Gate 2: finite Ausgaben

    func test_longRender_staysFinite() {
        var voice = makeVoice()
        // 10 Sekunden bei 48 kHz, in Bloecken.
        for _ in 0..<120 {
            let output = render(&voice, frames: 4_000)
            XCTAssertTrue(allFinite(output.l) && allFinite(output.r))
        }
    }

    func test_extremeParameters_stayFinite() {
        let extremes: [AudioCoreAtmosphericVoiceParameters] = [
            AudioCoreAtmosphericVoiceParameters(gainA: 1, mixDepth: 1, morphPosition: 1,
                                                 textureLevel: 1, textureBrightness: 1,
                                                 filterCutoff: 1, filterResonance: 1,
                                                 drive: 1, waveshaperOutputGain: 4, outputLevel: 1,
                                                 smoothingTimeMs: 0),
            AudioCoreAtmosphericVoiceParameters(gainA: 0, mixDepth: 0, morphPosition: 0,
                                                 textureLevel: 0, textureBrightness: 0,
                                                 filterCutoff: 0, filterResonance: 0,
                                                 drive: 0, waveshaperOutputGain: 0, outputLevel: 0,
                                                 smoothingTimeMs: 10_000),
            AudioCoreAtmosphericVoiceParameters(mixMode: .ringModulation, filterMode: .highpass,
                                                 filterCutoff: 0, filterResonance: 1, drive: 1),
            AudioCoreAtmosphericVoiceParameters(mixMode: .softPhaseModulation, filterMode: .bandpass,
                                                 filterResonance: 1, drive: 1, waveshaperOutputGain: 4)
        ]

        for (index, parameters) in extremes.enumerated() {
            for note in [UInt8(0), UInt8(60), UInt8(127)] {
                var voice = makeVoice(parameters: parameters, note: note, velocity: 127)
                let output = render(&voice, frames: 12_000)
                XCTAssertTrue(allFinite(output.l) && allFinite(output.r),
                              "Extremsatz \(index), Note \(note): nicht-endliche Ausgabe")
                for value in output.l {
                    XCTAssertLessThanOrEqual(abs(value), 4.0,
                                             "Extremsatz \(index), Note \(note): Ausgabe unplausibel gross")
                }
            }
        }
    }

    // MARK: – Gate 3: die sieben Modulationsziele wirken nachweisbar
    //
    // Muster fuer alle sieben: identischer Patch, identische Route, nur das
    // Makro unterscheidet sich (0 gegen 1). Ein Ziel, das die Matrix zwar
    // berechnet, die Stimme aber ignoriert, liefert damit zwei bit-identische
    // Renders und faellt sofort auf.

    private func renderPair(target: AudioCoreModulationTarget,
                             amount: Float,
                             base: AudioCoreAtmosphericVoiceParameters = .defaults,
                             frames: Int = 12_000) -> (off: [Float], on: [Float]) {
        var withoutModulation = makeVoice(parameters: makeRoutedParameters(target: target, amount: amount,
                                                                           motion: 0, base: base))
        var withModulation = makeVoice(parameters: makeRoutedParameters(target: target, amount: amount,
                                                                         motion: 1, base: base))
        return (render(&withoutModulation, frames: frames).l,
                render(&withModulation, frames: frames).l)
    }

    func test_target_morphPosition_hasEffect() {
        let pair = renderPair(target: .morphPosition, amount: 0.6)
        XCTAssertGreaterThan(differenceRMS(pair, from: 6_000), 0.001,
                             "morphPosition muss den Klang messbar veraendern")
    }

    func test_target_textureLevel_hasEffect() {
        let pair = renderPair(target: .textureLevel, amount: 0.9)
        XCTAssertGreaterThan(differenceRMS(pair, from: 6_000), 0.001, "textureLevel muss wirken")
    }

    func test_target_filterCutoff_hasEffect() {
        let pair = renderPair(target: .filterCutoff, amount: -0.7)
        XCTAssertGreaterThan(differenceRMS(pair, from: 6_000), 0.005, "filterCutoff muss wirken")
    }

    func test_target_mixDepth_hasEffect() {
        let pair = renderPair(target: .mixDepth, amount: 0.7)
        XCTAssertGreaterThan(differenceRMS(pair, from: 6_000), 0.005, "mixDepth muss wirken")
    }

    func test_target_ampEnvelopeDepth_hasEffect() {
        // Basiswert 1.0, Amount -1.0 -> Tiefe 0: die Stimme muss verstummen,
        // sobald die Glaettung durchgelaufen ist.
        let pair = renderPair(target: .ampEnvelopeDepth, amount: -1.0)
        let quiet = rms(pair.on[10_000...])
        let loud = rms(pair.off[10_000...])
        XCTAssertGreaterThan(loud, 0.01)
        XCTAssertLessThan(quiet, loud * 0.02, "ampEnvelopeDepth = 0 muss die Amplitude praktisch aufheben")
    }

    func test_target_modEnvelopeDepth_hasEffect() {
        // Die Mod-Huelle steuert den Cutoff; das Makro faehrt ihre Tiefe auf 0.
        var base = AudioCoreAtmosphericVoiceParameters(textureLevel: 0,
                                                        filterCutoff: 0.9,
                                                        modEnvelope: AudioCoreEnvelopeParameters(attackMs: 5,
                                                                                                  decayMs: 50,
                                                                                                  sustainLevel: 1.0,
                                                                                                  releaseMs: 100))
        base.modulationMatrix = AudioCoreModulationMatrix(routes: [
            AudioCoreModulationRoute(source: .envelope(.mod), target: .filterCutoff, amount: -0.8),
            AudioCoreModulationRoute(source: .macro(.motion), target: .modEnvelopeDepth, amount: -1.0)
        ])

        var fullDepth = AudioCoreAtmosphericVoice(sampleRate: 48_000)
        var zeroDepth = AudioCoreAtmosphericVoice(sampleRate: 48_000)

        var withMacro = base
        withMacro.macros = AudioCoreMacroValues(motion: 1.0)

        fullDepth.configure(note: 60, velocity: 100, sampleRate: 48_000, parameters: base, activationOrder: 7)
        zeroDepth.configure(note: 60, velocity: 100, sampleRate: 48_000, parameters: withMacro, activationOrder: 7)

        let a = render(&fullDepth, frames: 12_000).l
        let b = render(&zeroDepth, frames: 12_000).l

        XCTAssertGreaterThan(differenceRMS((off: a, on: b), from: 6_000), 0.005,
                             "modEnvelopeDepth muss die Wirkung der Mod-Huelle messbar skalieren")
    }

    // MARK: – Gate 3 + Gate 4: spaceSend

    func test_spaceSend_isExposedButNotAppliedInsideTheVoice() {
        let withoutSend = makeRoutedParameters(target: .spaceSend, amount: 1.0, motion: 0)
        let withSend = makeRoutedParameters(target: .spaceSend, amount: 1.0, motion: 1)

        var quiet = makeVoice(parameters: withoutSend)
        var loud = makeVoice(parameters: withSend)

        let a = render(&quiet, frames: 24_000)
        let b = render(&loud, frames: 24_000)

        // Ziel wirkt: der nach aussen sichtbare Wert folgt der Modulation.
        XCTAssertLessThan(quiet.spaceSendLevel, 0.01, "ohne Modulation bleibt der Send auf dem Basiswert")
        XCTAssertGreaterThan(loud.spaceSendLevel, 0.95, "mit Modulation muss der Send sichtbar ansteigen")

        // Und wird NICHT angewendet: der Klang ist bit-identisch.
        assertBitIdentical(a.l, b.l, "spaceSend darf den Voice-Ausgang nicht veraendern (L)")
        assertBitIdentical(a.r, b.r, "spaceSend darf den Voice-Ausgang nicht veraendern (R)")
    }

    // MARK: – Gate 5: Huellkurven-Zeitverhalten bei zwei Sample-Raten

    func test_envelopeTiming_isCorrectAtTwoSampleRates() {
        for sampleRate in [48_000.0, 96_000.0] {
            let envelope = AudioCoreEnvelopeParameters(attackMs: 10, decayMs: 20,
                                                        sustainLevel: 0.5, releaseMs: 30)
            let parameters = AudioCoreAtmosphericVoiceParameters(ampEnvelope: envelope)
            var voice = makeVoice(sampleRate: sampleRate, parameters: parameters)

            let attackSamples = Int(0.010 * sampleRate)
            let decaySamples = Int(0.020 * sampleRate)   // volle Spanne 1.0 -> 0
            let toSustain = attackSamples + decaySamples / 2

            XCTAssertEqual(voice.stage, .attack, "SR \(sampleRate): direkt nach Note-On muss Attack laufen")

            _ = render(&voice, frames: Int(Double(toSustain) * 0.85))
            XCTAssertNotEqual(voice.stage, .sustain, "SR \(sampleRate): Sustain darf nicht zu frueh erreicht sein")
            XCTAssertTrue(voice.isActive)

            _ = render(&voice, frames: Int(Double(toSustain) * 0.35) + 8)
            XCTAssertEqual(voice.stage, .sustain, "SR \(sampleRate): Sustain muss nach Attack+Decay erreicht sein")

            // Sustain haelt: kein selbstaendiger Uebergang nach idle.
            _ = render(&voice, frames: Int(sampleRate))
            XCTAssertEqual(voice.stage, .sustain, "SR \(sampleRate): Sustain muss ohne Note-Off halten")

            voice.triggerRelease()
            XCTAssertEqual(voice.stage, .release)

            let releaseSamples = Int(0.030 * sampleRate) / 2   // von Pegel 0.5 aus
            _ = render(&voice, frames: Int(Double(releaseSamples) * 0.8))
            XCTAssertTrue(voice.isActive, "SR \(sampleRate): Release darf nicht zu frueh enden")

            _ = render(&voice, frames: Int(Double(releaseSamples) * 0.5) + 8)
            XCTAssertFalse(voice.isActive, "SR \(sampleRate): Release muss rechtzeitig auf idle laufen")
            XCTAssertEqual(voice.stage, .idle)
        }
    }

    func test_triggerRelease_onIdleVoice_isIgnored() {
        var voice = AudioCoreAtmosphericVoice(sampleRate: 48_000)
        XCTAssertFalse(voice.isActive)
        voice.triggerRelease()
        XCTAssertEqual(voice.stage, .idle)

        let output = render(&voice, frames: 256)
        XCTAssertEqual(output.l, [Float](repeating: 0, count: 256),
                       "Eine idle Stimme darf nichts in die Puffer schreiben")
    }

    // MARK: – Gate 7: Post-Init-Mutationspfad ueber setParameters(_:)

    func test_setParameters_clampsPostInitMutation() {
        var parameters = AudioCoreAtmosphericVoiceParameters.defaults
        parameters.gainA = 5.0
        parameters.mixDepth = -3.0
        parameters.morphPosition = .nan
        parameters.textureLevel = .infinity
        parameters.textureBrightness = -1.0
        parameters.filterCutoff = .nan
        parameters.filterResonance = 9.0
        parameters.drive = .infinity
        parameters.waveshaperOutputGain = 100.0
        parameters.outputLevel = 7.0
        parameters.ampEnvelopeDepth = 42.0
        parameters.modEnvelopeDepth = -.infinity
        parameters.spaceSend = 3.0
        parameters.smoothingTimeMs = -5.0
        parameters.sourceBTranspositionSemitones = 999.0
        parameters.sourceBFineTuneCents = -999.0
        parameters.sourceBPhaseOffset = .nan
        parameters.ampEnvelope.attackMs = -100.0
        parameters.ampEnvelope.sustainLevel = 9.0
        parameters.modEnvelope.releaseMs = .nan
        parameters.lfo1.frequencyHz = 1_000_000.0
        parameters.lfo2.smoothingAmount = -4.0
        parameters.macros.motion = 8.0
        parameters.macros.color = .nan

        var voice = AudioCoreAtmosphericVoice(sampleRate: 48_000)
        voice.setParameters(parameters)
        let applied = voice.parameters

        // Endliche Werte ausserhalb des Bereichs werden auf die Bereichsgrenze
        // geklemmt ...
        XCTAssertEqual(applied.gainA, 1.0)
        XCTAssertEqual(applied.mixDepth, 0.0)
        XCTAssertEqual(applied.filterResonance, 1.0)
        XCTAssertEqual(applied.waveshaperOutputGain, 4.0)
        XCTAssertEqual(applied.outputLevel, 1.0)
        XCTAssertEqual(applied.ampEnvelopeDepth, 1.0)
        XCTAssertEqual(applied.spaceSend, 1.0)
        XCTAssertEqual(applied.smoothingTimeMs, 0.0)
        XCTAssertEqual(applied.textureBrightness, 0.0)

        // ... nicht-endliche Werte dagegen auf den dokumentierten Fallback des
        // jeweiligen Feldes, nicht auf eine Bereichsgrenze. Identisches
        // Verhalten wie in allen bestehenden Bausteinen (`AudioCoreMacroValues`,
        // `AudioCoreMixParameters`, `AudioCoreEnvelopeParameters`, ...) — eine
        // eigene Sonderregel nur fuer diesen Typ waere eine Inkonsistenz.
        XCTAssertEqual(applied.morphPosition, 0.0, ".nan -> Fallback 0")
        XCTAssertEqual(applied.textureLevel, 0.0, ".infinity -> Fallback 0")
        XCTAssertEqual(applied.filterCutoff, 1.0, ".nan -> Fallback 1 (offener Filter)")
        XCTAssertEqual(applied.drive, 0.0, ".infinity -> Fallback 0 (kein Drive)")
        XCTAssertEqual(applied.modEnvelopeDepth, 1.0, "-.infinity -> Fallback 1 (volle Tiefe)")
        XCTAssertEqual(applied.sourceBTranspositionSemitones, 24.0)
        XCTAssertEqual(applied.sourceBFineTuneCents, -100.0)
        XCTAssertEqual(applied.sourceBPhaseOffset, 0.0)
        XCTAssertEqual(applied.ampEnvelope.attackMs, 0.0)
        XCTAssertEqual(applied.ampEnvelope.sustainLevel, 1.0)
        XCTAssertEqual(applied.modEnvelope.releaseMs, 200.0)   // Fallback bei .nan
        XCTAssertEqual(applied.lfo1.frequencyHz, AudioCoreLFOParameters.maxFrequencyHz)
        XCTAssertEqual(applied.lfo2.smoothingAmount, 0.0)
        XCTAssertEqual(applied.macros.motion, 1.0)
        XCTAssertEqual(applied.macros.color, 0.0)

        // Und der Renderpfad bleibt nach der Mutation gesund.
        voice.configure(note: 72, velocity: 127, sampleRate: 48_000, parameters: parameters)
        let output = render(&voice, frames: 8_000)
        XCTAssertTrue(allFinite(output.l) && allFinite(output.r))
    }

    func test_setParameters_onSoundingVoice_doesNotResetPlaybackState() {
        var voice = makeVoice()
        _ = render(&voice, frames: 6_000)
        XCTAssertEqual(voice.stage, .sustain)

        var changed = AudioCoreAtmosphericVoiceParameters.defaults
        changed.filterCutoff = 0.2
        voice.setParameters(changed)

        // Live-Parameteraenderung: Stage bleibt, der Klang gleitet.
        XCTAssertEqual(voice.stage, .sustain, "setParameters darf die Huellkurve nicht neu starten")
        let output = render(&voice, frames: 6_000)
        XCTAssertTrue(allFinite(output.l))
        XCTAssertGreaterThan(rms(output.l[0...]), 0.0)
    }

    // MARK: – Gate 8: Sample-Rate-Grenzen

    func test_sampleRate_isClampedToTechnicalBounds() {
        XCTAssertEqual(AudioCoreAtmosphericVoiceParameters.safeSampleRate(1e300),
                       AudioCoreAtmosphericVoiceParameters.maxSampleRate)
        XCTAssertEqual(AudioCoreAtmosphericVoiceParameters.safeSampleRate(0.001),
                       AudioCoreAtmosphericVoiceParameters.minSampleRate)
        XCTAssertEqual(AudioCoreAtmosphericVoiceParameters.safeSampleRate(.nan), 44_100.0)
        XCTAssertEqual(AudioCoreAtmosphericVoiceParameters.safeSampleRate(-1), 44_100.0)
        XCTAssertEqual(AudioCoreAtmosphericVoiceParameters.safeSampleRate(48_000), 48_000)
    }

    func test_extremeSampleRates_produceFiniteOutput() {
        let rates: [Double] = [0.001, 1.0, 100.0, 8_000.0, 44_100.0, 192_000.0,
                               1e6, 1e300, .greatestFiniteMagnitude, .nan, -1.0]
        for rate in rates {
            var voice = AudioCoreAtmosphericVoice(sampleRate: rate)
            voice.configure(note: 60, velocity: 127, sampleRate: rate,
                            parameters: .defaults, activationOrder: 1)

            XCTAssertGreaterThanOrEqual(voice.sampleRate, AudioCoreAtmosphericVoiceParameters.minSampleRate,
                                        "Sample Rate \(rate) muss nach oben auf die Untergrenze geklemmt sein")
            XCTAssertLessThanOrEqual(voice.sampleRate, AudioCoreAtmosphericVoiceParameters.maxSampleRate,
                                     "Sample Rate \(rate) muss auf die Obergrenze geklemmt sein")

            let output = render(&voice, frames: 4_000)
            XCTAssertTrue(allFinite(output.l) && allFinite(output.r),
                          "Sample Rate \(rate): nicht-endliche Ausgabe")
            for value in output.l {
                XCTAssertLessThanOrEqual(abs(value), 4.0, "Sample Rate \(rate): Ausgabe unplausibel gross")
            }
        }
    }

    func test_prepare_rebuildsForNewSampleRateAndStaysDeterministic() {
        var voice = AudioCoreAtmosphericVoice(sampleRate: 44_100)
        voice.prepare(sampleRate: 96_000)
        XCTAssertEqual(voice.sampleRate, 96_000)
        voice.configure(note: 60, velocity: 100, sampleRate: 96_000, parameters: .defaults, activationOrder: 7)
        let a = render(&voice, frames: 4_096)

        var reference = AudioCoreAtmosphericVoice(sampleRate: 96_000)
        reference.configure(note: 60, velocity: 100, sampleRate: 96_000, parameters: .defaults, activationOrder: 7)
        let b = render(&reference, frames: 4_096)

        assertBitIdentical(a.l, b.l, "Eine per prepare() umgestellte Stimme muss wie eine frisch gebaute klingen")
    }

    // MARK: – Gate 9: Kontrollratenmodulation ohne hoerbare Stufen
    //
    // Messprinzip wie in S-08c: nicht "klingt gut", sondern Sprunggroesse.
    // Der Filter-Cutoff ist der einzige Wert, der nur auf Kontrollrate
    // ANGEWENDET wird — wenn dabei Stufen entstehen, muessen die
    // Sample-zu-Sample-Spruenge exakt an den Kontrollblockgrenzen
    // systematisch groesser sein als dazwischen.

    func test_controlRateModulation_producesNoAudibleSteps() {
        // Tiefe Note ohne Textur: die Wellenform selbst hat dann sehr kleine
        // Sample-zu-Sample-Deltas, eine Filterstufe waere deutlich sichtbar.
        var parameters = AudioCoreAtmosphericVoiceParameters(textureLevel: 0,
                                                              filterCutoff: 0.5,
                                                              filterResonance: 0.6)
        parameters.lfo1 = AudioCoreLFOParameters(shape: .sine, frequencyHz: 8.0)
        parameters.modulationMatrix = AudioCoreModulationMatrix(routes: [
            AudioCoreModulationRoute(source: .lfo(.lfo1), target: .filterCutoff, amount: 1.0)
        ])

        var voice = makeVoice(parameters: parameters, note: 36, velocity: 127)
        let output = render(&voice, frames: 96_000).l

        var maxAtBoundary: Float = 0
        var maxInside: Float = 0
        // Erste 4.800 Samples (Attack/Einschwingen) auslassen.
        for index in 4_800..<output.count {
            let delta = abs(output[index] - output[index - 1])
            if index % AudioCoreAtmosphericVoice.controlBlockSize == 0 {
                maxAtBoundary = max(maxAtBoundary, delta)
            } else {
                maxInside = max(maxInside, delta)
            }
        }

        XCTAssertGreaterThan(maxInside, 0, "Testaufbau muss ein Signal liefern")
        XCTAssertLessThanOrEqual(maxAtBoundary, maxInside * 1.5,
                                 "An den Kontrollblockgrenzen entstehen systematisch groessere Spruenge "
                                 + "als im Block — die Kontrollratenmodulation ist hoerbar gestuft "
                                 + "(Grenze \(maxAtBoundary), innen \(maxInside))")
    }

    func test_smoothing_limitsPerSampleJumpOnHardParameterChange() {
        // Harter Cutoff-Sprung an einer klingenden Stimme: der Glaetter muss
        // ihn zu einer Rampe machen, nicht zu einer Kante.
        var parameters = AudioCoreAtmosphericVoiceParameters(textureLevel: 0, filterCutoff: 0.95)
        parameters.modulationMatrix = .empty
        var voice = makeVoice(parameters: parameters, note: 36, velocity: 127)
        _ = render(&voice, frames: 24_000)

        var changed = parameters
        changed.filterCutoff = 0.05
        voice.setParameters(changed)

        let output = render(&voice, frames: 24_000).l
        var maxDelta: Float = 0
        for index in 1..<output.count {
            maxDelta = max(maxDelta, abs(output[index] - output[index - 1]))
        }
        XCTAssertTrue(allFinite(output))
        XCTAssertLessThan(maxDelta, 0.02,
                          "Ein harter Cutoff-Sprung darf am Ausgang keine Kante erzeugen (max Delta \(maxDelta))")
    }

    // MARK: – Hilfe fuer die Zielwirkungs-Tests

    private func differenceRMS(_ pair: (off: [Float], on: [Float]), from index: Int) -> Float {
        var sum: Double = 0
        var count = 0
        for i in index..<min(pair.off.count, pair.on.count) {
            let delta = Double(pair.off[i] - pair.on[i])
            sum += delta * delta
            count += 1
        }
        guard count > 0 else { return 0 }
        return Float((sum / Double(count)).squareRoot())
    }
}
