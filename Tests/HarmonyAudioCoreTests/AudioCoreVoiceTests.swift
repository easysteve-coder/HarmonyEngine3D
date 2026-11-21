import XCTest
@testable import HarmonyAudioCore

// MARK: – AudioCoreVoiceTests
//
// S-02a (`.agent_handoff/latest_codex.md`, Runde 046), Scope D. Deckt die
// zehn im Handoff geforderten Nachweise ab: Defaults, Frequenzformel,
// ADSR-Timing bei 44.1/48 kHz, NoteOff/Release/Idle, alle vier
// Wellenformen, Filter-Bypass/-Extremwerte, Stereo-Pan, Determinismus und
// eine baseline-nahe Metrik gegen den S-01-Legacy-Referenzrender.
//
// Bewusst NICHT getestet (S-02b): Voice-Pool, Voice-Stealing,
// Unison-Verteilung ueber mehrere Stimmen, jegliche Kopplung an eine
// konkrete Audio-Engine/App.

final class AudioCoreVoiceTests: XCTestCase {

    // MARK: – 1. Defaults entsprechen fachlich den heutigen Legacy-Defaults

    // Referenz: `Sources/HarmonyEngine3D/SynthParams.swift` (`SynthParams.defaults`).
    // `HarmonyAudioCore` darf `HarmonyEngine3D` nicht importieren (Scope A) —
    // deshalb Vergleich gegen die dort dokumentierten literalen Werte.
    func test_defaultParameters_matchLegacySynthParamsDefaults() {
        let defaults = AudioCoreSynthParameters.defaults
        XCTAssertEqual(defaults.waveform, .sine)
        XCTAssertEqual(defaults.attackMs, 20.0)
        XCTAssertEqual(defaults.decayMs, 100.0)
        XCTAssertEqual(defaults.sustain, 0.70)
        XCTAssertEqual(defaults.releaseMs, 300.0)
        XCTAssertEqual(defaults.maxVoices, 16)
        XCTAssertEqual(defaults.filterCutoff, 1.0)
        XCTAssertEqual(defaults.filterResonance, 0.0)
        XCTAssertEqual(defaults.unisonVoices, 1)
        XCTAssertEqual(defaults.unisonDetune, 0.0)
        XCTAssertEqual(defaults.unisonSpread, 0.0)
    }

    // MARK: – 2. MIDI-Noten 60/69/72 ergeben die erwarteten Frequenzen

    func test_frequencyFormula_matchesEqualTemperamentAtReferenceNotes() {
        assertApproximatelyEqual(Float(AudioCoreVoice.frequency(forNote: 60)), expected: 261.63, tolerance: 0.01, label: "MIDI60/C4")
        assertApproximatelyEqual(Float(AudioCoreVoice.frequency(forNote: 69)), expected: 440.00, tolerance: 0.01, label: "MIDI69/A4")
        assertApproximatelyEqual(Float(AudioCoreVoice.frequency(forNote: 72)), expected: 523.25, tolerance: 0.01, label: "MIDI72/C5")
    }

    func test_frequencyFormula_detuneCentsShiftsFrequency() {
        // 10 Cent ≈ +0.578 % Frequenz (2^(10/1200) − 1), siehe SynthVoice-Doku.
        let base = AudioCoreVoice.frequency(forNote: 69, detuneCents: 0)
        let detuned = AudioCoreVoice.frequency(forNote: 69, detuneCents: 10)
        let expectedRatio = pow(2.0, 10.0 / 1200.0)
        assertApproximatelyEqual(Float(detuned / base), expected: Float(expectedRatio), tolerance: 0.0005, label: "detune-ratio")
    }

    // MARK: – 3. ADSR erreicht erwartete Stages innerhalb enger samplebasierter Grenzen (44.1/48 kHz)

    func test_adsrStageTransitions_matchExpectedSampleCountsAtBothSampleRates() {
        for sampleRate in [44_100.0, 48_000.0] {
            var parameters = AudioCoreSynthParameters.defaults // attack 20ms, decay 100ms, sustain 0.70
            parameters.waveform = .sine

            var voice = AudioCoreVoice()
            voice.configure(note: 60, velocity: 100, sampleRate: sampleRate, parameters: parameters)

            // Grosszuegig ueber Attack+Decay hinaus rendern, um beide Uebergaenge sicher einzufangen.
            let attackMs: Double = Double(parameters.attackMs)
            let decayMs: Double = Double(parameters.decayMs)
            let sustain: Double = Double(parameters.sustain)
            let expectedAttackSamples = Int((attackMs * 0.001 * sampleRate).rounded())
            let expectedDecaySamples  = Int(((1.0 - sustain) * decayMs * 0.001 * sampleRate).rounded())
            let totalFrames = expectedAttackSamples + expectedDecaySamples + 500

            let stages = renderFrameByFrame(&voice, frameCount: totalFrames)

            let attackFrameCount = stages.prefix(while: { $0 == .attack }).count
            assertApproximatelyEqual(Float(attackFrameCount), expected: Float(expectedAttackSamples),
                                     tolerance: max(2, Float(expectedAttackSamples) * 0.01),
                                     label: "attack-samples@\(sampleRate)")

            let decayFrameCount = stages.dropFirst(attackFrameCount).prefix(while: { $0 == .decay }).count
            assertApproximatelyEqual(Float(decayFrameCount), expected: Float(expectedDecaySamples),
                                     tolerance: max(2, Float(expectedDecaySamples) * 0.01),
                                     label: "decay-samples@\(sampleRate)")

            XCTAssertEqual(stages.last, .sustain, "nach Attack+Decay sollte die Stimme im Sustain stehen (sampleRate=\(sampleRate))")
        }
    }

    // MARK: – 4. NoteOff fuehrt nach Release zu idle/Stille

    func test_noteOff_reachesIdleAfterReleaseAtBothSampleRates() {
        for sampleRate in [44_100.0, 48_000.0] {
            let parameters = AudioCoreSynthParameters.defaults // release 300ms
            var voice = AudioCoreVoice()
            voice.configure(note: 60, velocity: 100, sampleRate: sampleRate, parameters: parameters)

            // Erst wirklich bis in den Sustain rendern (Attack+Decay+Puffer),
            // sonst startet Release von einem Zwischen-Envelopewert statt von
            // `sustain` — releaseRate ist auf "Zeit von 1.0 auf 0" kalibriert
            // (siehe `AudioCoreVoice.configure()`), die tatsaechliche
            // Release-Dauer skaliert linear mit dem Envelopewert bei NoteOff.
            let attackMs = Double(parameters.attackMs)
            let decayMs = Double(parameters.decayMs)
            let attackSamples = Int((attackMs * 0.001 * sampleRate).rounded())
            let decaySamples = Int((decayMs * 0.001 * sampleRate).rounded())
            _ = renderFrameByFrame(&voice, frameCount: attackSamples + decaySamples + 200)
            XCTAssertEqual(voice.stage, .sustain, "Vorbedingung: Stimme sollte vor Release im Sustain stehen (sampleRate=\(sampleRate))")

            voice.triggerRelease()
            // Release startet vom aktuellen Envelopewert (hier: `sustain`), nicht
            // von 1.0 — tatsaechliche Release-Dauer = sustain * releaseMs.
            let expectedReleaseSamples = Int((Double(parameters.sustain) * Double(parameters.releaseMs) * 0.001 * sampleRate).rounded())
            let stages = renderFrameByFrame(&voice, frameCount: expectedReleaseSamples + 500)

            guard let idleIndex = stages.firstIndex(of: .idle) else {
                XCTFail("Stimme sollte nach Release idle werden (sampleRate=\(sampleRate))")
                return
            }
            assertApproximatelyEqual(Float(idleIndex + 1), expected: Float(expectedReleaseSamples),
                                     tolerance: max(2, Float(expectedReleaseSamples) * 0.01),
                                     label: "release-samples@\(sampleRate)")
            XCTAssertFalse(voice.isActive)
        }
    }

    // MARK: – 5. Alle vier Wellenformen erzeugen endliche Samples

    func test_allWaveforms_produceFiniteSamples() {
        for waveform in [AudioCoreWaveform.sine, .saw, .square, .triangle] {
            var parameters = AudioCoreSynthParameters.defaults
            parameters.waveform = waveform
            var voice = AudioCoreVoice()
            voice.configure(note: 60, velocity: 100, sampleRate: 44_100.0, parameters: parameters)

            let frameCount = 4_000
            var left = [Float](repeating: 0, count: frameCount)
            var right = [Float](repeating: 0, count: frameCount)
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    _ = voice.render(intoL: l.baseAddress!, intoR: r.baseAddress!, frameCount: frameCount)
                }
            }
            XCTAssertTrue(left.allSatisfy { $0.isFinite }, "waveform=\(waveform): linker Kanal enthaelt nicht-endliche Samples")
            XCTAssertTrue(right.allSatisfy { $0.isFinite }, "waveform=\(waveform): rechter Kanal enthaelt nicht-endliche Samples")
            XCTAssertGreaterThan(left.map { abs($0) }.max() ?? 0, 0.001, "waveform=\(waveform): sollte hoerbaren Pegel erzeugen")
        }
    }

    // MARK: – 6. Filter-Bypass liefert Identitaetskoeffizienten

    func test_filterBypass_atFullyOpenCutoffAndZeroResonance_returnsIdentityCoefficients() {
        let coefficients = AudioCoreVoice.calcBiquadLowpassCoefficients(cutoff: 1.0, resonance: 0.0, sampleRate: 44_100.0)
        XCTAssertEqual(coefficients.b0, 1.0)
        XCTAssertEqual(coefficients.b1, 0.0)
        XCTAssertEqual(coefficients.b2, 0.0)
        XCTAssertEqual(coefficients.a1, 0.0)
        XCTAssertEqual(coefficients.a2, 0.0)
    }

    // MARK: – 7. Filter-Extremwerte bleiben finite/stabil

    func test_filterExtremeValues_remainFiniteAcrossParameterGrid() {
        let sampleRate = 44_100.0
        for cutoff: Float in [0.0, 0.001, 0.5, 0.999, 1.0] {
            for resonance: Float in [0.0, 0.5, 1.0] {
                let coefficients = AudioCoreVoice.calcBiquadLowpassCoefficients(cutoff: cutoff, resonance: resonance, sampleRate: sampleRate)
                XCTAssertTrue(coefficients.b0.isFinite && coefficients.b1.isFinite && coefficients.b2.isFinite
                              && coefficients.a1.isFinite && coefficients.a2.isFinite,
                              "cutoff=\(cutoff) resonance=\(resonance): Koeffizienten nicht endlich")
            }
        }

        // Stabilitaet auch im tatsaechlichen Renderpfad (max. Resonanz, geschlossener Cutoff):
        var parameters = AudioCoreSynthParameters.defaults
        parameters.filterCutoff = 0.0
        parameters.filterResonance = 1.0
        var voice = AudioCoreVoice()
        voice.configure(note: 60, velocity: 127, sampleRate: sampleRate, parameters: parameters)
        let frameCount = 4_000
        var left = [Float](repeating: 0, count: frameCount)
        var right = [Float](repeating: 0, count: frameCount)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                _ = voice.render(intoL: l.baseAddress!, intoR: r.baseAddress!, frameCount: frameCount)
            }
        }
        XCTAssertTrue(left.allSatisfy { $0.isFinite && abs($0) < 100 }, "Resonanz-Extremwert sollte nicht divergieren")
        XCTAssertTrue(right.allSatisfy { $0.isFinite && abs($0) < 100 })
    }

    // MARK: – 8. Stereo-Pan Mitte/links/rechts liefert erwartete Gain-Verhaeltnisse

    func test_stereoPan_centerLeftRight_producesExpectedGainRatios() {
        func tailRMS(pan: Float) -> (left: Float, right: Float) {
            var parameters = AudioCoreSynthParameters.defaults
            parameters.attackMs = 0
            parameters.decayMs = 0
            parameters.sustain = 1.0
            var voice = AudioCoreVoice()
            voice.configure(note: 69, velocity: 127, sampleRate: 44_100.0, parameters: parameters, panPosition: pan)

            let frameCount = 300
            var left = [Float](repeating: 0, count: frameCount)
            var right = [Float](repeating: 0, count: frameCount)
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    _ = voice.render(intoL: l.baseAddress!, intoR: r.baseAddress!, frameCount: frameCount)
                }
            }
            // Erste 50 Samples ueberspringen (Attack/Decay-Ramp trotz 0ms noch ueber
            // ein bis zwei Samples verteilt), Rest ist stabiler Sustain-Pegel.
            let tailL = left.suffix(200)
            let tailR = right.suffix(200)
            let rmsL = sqrtf(tailL.reduce(Float(0)) { $0 + $1 * $1 } / Float(tailL.count))
            let rmsR = sqrtf(tailR.reduce(Float(0)) { $0 + $1 * $1 } / Float(tailR.count))
            return (rmsL, rmsR)
        }

        let center = tailRMS(pan: 0.0)
        XCTAssertGreaterThan(center.left, 0.001)
        assertApproximatelyEqual(center.right, expected: center.left, tolerance: center.left * 0.02, label: "center L≈R")

        let hardLeft = tailRMS(pan: -1.0)
        XCTAssertLessThan(hardLeft.right, hardLeft.left * 0.05, "hart links: rechter Kanal sollte praktisch stumm sein")
        XCTAssertGreaterThan(hardLeft.left, center.left, "hart links: linker Kanal lauter als Center (√2-Gain)")

        let hardRight = tailRMS(pan: 1.0)
        XCTAssertLessThan(hardRight.left, hardRight.right * 0.05, "hart rechts: linker Kanal sollte praktisch stumm sein")
        XCTAssertGreaterThan(hardRight.right, center.right, "hart rechts: rechter Kanal lauter als Center (√2-Gain)")
    }

    // MARK: – 9. Identisches Szenario zweimal gerendert ist deterministisch

    func test_identicalScenario_renderedTwice_producesIdenticalSamples() {
        func renderScenario() -> (left: [Float], right: [Float]) {
            var voice = AudioCoreVoice()
            voice.configure(note: 60, velocity: 100, sampleRate: 44_100.0, parameters: .defaults)
            let frameCount = 8_000
            var left = [Float](repeating: 0, count: frameCount)
            var right = [Float](repeating: 0, count: frameCount)
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    _ = voice.render(intoL: l.baseAddress!, intoR: r.baseAddress!, frameCount: frameCount)
                }
            }
            return (left, right)
        }

        let a = renderScenario()
        let b = renderScenario()
        XCTAssertEqual(a.left, b.left, "gleiches Szenario muss bitgenau identische Samples liefern")
        XCTAssertEqual(a.right, b.right)
    }

    // MARK: – 10. Default-C4-Render liegt baseline-nah zu den S-01-Metriken
    //
    // S-01 (`Tests/HarmonyEngine3DTests/OfflineSynthBaselineTests.swift`,
    // `test_legacyReferenceRender_matchesDocumentedBaselineMetrics`) misst
    // denselben Szenario (C4/Velocity 100, Default-`SynthParams`, 44.1 kHz,
    // 300 ms gehalten + Release) durch den echten `SynthNode`-Rendercallback
    // direkt an `mainMixerNode` — ohne Unison, ohne Fader/Delay/Reverb. Das
    // ist fachlich dieselbe Grundformel wie eine einzelne `AudioCoreVoice`
    // mit `gainScale=1`/`detuneCents=0`/`panPosition=0`, daher ist ein enger
    // Vergleich sinnvoll (S-01-Baseline: peakAbsolute ≈0.10546, rms ≈0.03470).
    // `HarmonyAudioCoreTests` darf `HarmonyEngine3D` nicht importieren
    // (Scope A) — deshalb literale Referenzwerte statt eines Imports.
    func test_defaultC4Render_isBaselineNearToS01LegacyReference() {
        let sampleRate = 44_100.0
        var voice = AudioCoreVoice()
        voice.configure(note: 60, velocity: 100, sampleRate: sampleRate, parameters: .defaults)

        let noteOffFrame = Int(0.300 * sampleRate)
        let totalFrames = Int(0.800 * sampleRate)

        var left = [Float](repeating: 0, count: totalFrames)
        var right = [Float](repeating: 0, count: totalFrames)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                _ = voice.render(intoL: l.baseAddress!, intoR: r.baseAddress!, frameCount: noteOffFrame)
                voice.triggerRelease()
                _ = voice.render(intoL: l.baseAddress! + noteOffFrame, intoR: r.baseAddress! + noteOffFrame,
                                 frameCount: totalFrames - noteOffFrame)
            }
        }

        XCTAssertTrue(left.allSatisfy { $0.isFinite } && right.allSatisfy { $0.isFinite })

        let peak = max(left.map { abs($0) }.max() ?? 0, right.map { abs($0) }.max() ?? 0)
        let rmsL = sqrtf(left.reduce(Float(0)) { $0 + $1 * $1 } / Float(left.count))
        let rmsR = sqrtf(right.reduce(Float(0)) { $0 + $1 * $1 } / Float(right.count))
        let rms = sqrtf((rmsL * rmsL + rmsR * rmsR) / 2)

        assertApproximatelyEqual(peak, expected: 0.10546, tolerance: 0.10546 * 0.1, label: "peakAbsolute vs. S-01")
        assertApproximatelyEqual(rms, expected: 0.03470, tolerance: 0.03470 * 0.1, label: "rms vs. S-01")
    }

    // MARK: – Helfer

    /// Rendert `frameCount` Frames einzeln (1 Sample pro Aufruf) und gibt die
    /// Stage nach jedem gerenderten Sample zurueck — erlaubt exakte
    /// Uebergangs-Zaehlung ohne Kenntnis interner Zustandsfelder.
    private func renderFrameByFrame(_ voice: inout AudioCoreVoice, frameCount: Int) -> [AudioCoreADSRStage] {
        var stages: [AudioCoreADSRStage] = []
        stages.reserveCapacity(frameCount)
        var l: Float = 0
        var r: Float = 0
        for _ in 0..<frameCount {
            let stillActive = withUnsafeMutablePointer(to: &l) { lp in
                withUnsafeMutablePointer(to: &r) { rp in
                    voice.render(intoL: lp, intoR: rp, frameCount: 1)
                }
            }
            stages.append(voice.stage)
            if !stillActive { break }
        }
        return stages
    }

    private func assertApproximatelyEqual(_ value: Float, expected: Float, tolerance: Float,
                                          label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(value, expected, accuracy: max(tolerance, 1e-4),
                       "\(label): \(value) weicht mehr als erwartet von \(expected) ab",
                       file: file, line: line)
    }
}
