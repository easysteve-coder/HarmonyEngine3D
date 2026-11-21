import XCTest
@testable import HarmonyEngine3D

// MARK: – LiveParameterUpdateTests
//
// S-02b (`.agent_handoff/latest_codex.md`, Runde 047): sichert die
// Live-Parameter-Semantik von `VoicePool.applyParams()` ab, nachdem der
// Renderpfad auf `AudioCoreVoice` (`HarmonyAudioCore`) umgestellt wurde —
// insbesondere die neuen `AudioCoreVoice.updateLowpassCoefficients(...)`/
// `applySustainIfInSustain(...)`-Methoden. Treibt den echten `SynthNode`-Pfad
// ueber `OfflineSynthHarness`, wie `OfflineSynthBaselineTests` (S-01).
//
// Default-ADSR: Attack 20 ms, Decay 100 ms, Sustain 0.70, Release 300 ms.
// Wichtig (siehe `AudioCoreVoiceTests`): die Decay-Rate ist auf "Zeit von
// 1.0 auf 0.0" kalibriert, decayMs ist also NICHT die Zeit bis Sustain
// erreicht ist — die Stimme erreicht Sustain nach
// `attackMs + (1 - sustain) * decayMs` = 20 ms + 0.3 × 100 ms = 50 ms.
// Eine Stimme ist damit ab ca. 50 ms sicher in der Sustain-Stage.

final class LiveParameterUpdateTests: XCTestCase {

    private let referenceNote: UInt8 = 60
    private let referenceVelocity: UInt8 = 100

    // MARK: – 1. Live-Filter: wirkt sofort, ohne Voice-Neustart

    func test_liveFilterUpdate_appliesToActiveVoiceWithoutRestart() throws {
        let sampleRate = 44_100.0
        let totalFrames = frames(forMs: 500, sampleRate: sampleRate)
        let updateFrame = frames(forMs: 200, sampleRate: sampleRate)   // sicher in Sustain

        // Beide Filtereinstellungen sind bewusst "echte" (nicht bypassende)
        // Tiefpaesse: Bypass (cutoff=1, resonance=0) haelt filterS1/S2 immer
        // bei 0 (siehe `calcBiquadLowpassCoefficients`-Identitaetsfall) — ein
        // Wechsel WEG von Bypass wuerde die Stimme daher unabhaengig von
        // einem etwaigen Neustart-Bug fuer 1-2 Sample instantan stark
        // daempfen (keine uebernommene Filter-Historie), was den Test wertlos
        // machen wuerde. Start- und Zielfilter haben hier beide echten,
        // von 0 verschiedenen internen Zustand.
        var openishFilter = SynthParams.defaults
        openishFilter.filterCutoff = 0.6
        openishFilter.filterResonance = 0.2

        var closedFilter = openishFilter
        closedFilter.filterCutoff = 0.15

        let baseline = try OfflineSynthHarness.render(
            sampleRate: sampleRate, totalFrames: totalFrames,
            params: openishFilter,
            events: [.noteOn(atFrame: 0, note: referenceNote, velocity: referenceVelocity)])

        let liveUpdated = try OfflineSynthHarness.render(
            sampleRate: sampleRate, totalFrames: totalFrames,
            params: openishFilter,
            events: [
                .noteOn(atFrame: 0, note: referenceNote, velocity: referenceVelocity),
                .paramUpdate(atFrame: updateFrame, params: closedFilter)
            ])

        for sample in liveUpdated.left where !sample.isFinite {
            XCTFail("nicht-finites Sample nach Live-Filter-Update")
            break
        }

        // Vor dem Update: bitgenau identisch — keine Vorwirkung eines erst
        // spaeter eintreffenden paramUpdate-Events.
        XCTAssertEqual(Array(baseline.left[0..<updateFrame]), Array(liveUpdated.left[0..<updateFrame]))
        XCTAssertEqual(Array(baseline.right[0..<updateFrame]), Array(liveUpdated.right[0..<updateFrame]))

        // Kein Envelope-/Voice-Neustart am Update-Frame: Ein Neustart wuerde
        // `envelopeValue` auf 0 zuruecksetzen und ab dort mit `attackRate`
        // (hier 1/882 pro Sample) neu hochrampen — die ersten 2 ms nach dem
        // Update haetten dann nur einen winzigen Bruchteil der Amplitude
        // unmittelbar VOR dem Update. Ein reiner Koeffizientenwechsel
        // zwischen zwei echten Filtereinstellungen (kein Reset, State
        // bleibt erhalten) behaelt einen Grossteil der Amplitude.
        let preUpdateWindow = frames(forMs: 20, sampleRate: sampleRate)
        let preUpdateRMS = rms(of: liveUpdated.left[(updateFrame - preUpdateWindow)..<updateFrame])
        let immediatePostWindow = frames(forMs: 2, sampleRate: sampleRate)
        let immediatePostRMS = rms(of: liveUpdated.left[updateFrame..<(updateFrame + immediatePostWindow)])
        XCTAssertGreaterThan(immediatePostRMS, preUpdateRMS * 0.3,
                             "Live-Filter-Update darf die Stimme nicht neu starten (kein Envelope-Reset auf Attack-Rampe)")

        // Nach kurzer Filter-Konvergenzzeit: der staerker geschlossene
        // Tiefpass (cutoff 0.15 statt 0.6) reduziert den Pegel gegenueber dem
        // unveraenderten Referenzrender im selben Fenster.
        let postWindowStart = updateFrame + frames(forMs: 30, sampleRate: sampleRate)
        let postWindowEnd = postWindowStart + frames(forMs: 50, sampleRate: sampleRate)
        let baselineRMS = rms(of: baseline.left[postWindowStart..<postWindowEnd])
        let updatedRMS = rms(of: liveUpdated.left[postWindowStart..<postWindowEnd])
        XCTAssertLessThan(updatedRMS, baselineRMS * 0.8,
                          "Staerker geschlossener Tiefpass sollte den Pegel unter das Referenzsignal senken")
    }

    // MARK: – 2. Live-Sustain: nur wirksam waehrend Sustain-Stage

    func test_liveSustainUpdate_onlyAffectsVoiceAlreadyInSustainStage() throws {
        let sampleRate = 44_100.0
        let totalFrames = frames(forMs: 500, sampleRate: sampleRate)

        var lowerSustain = SynthParams.defaults
        lowerSustain.sustain = 0.3   // Default ist 0.7

        let baseline = try OfflineSynthHarness.render(
            sampleRate: sampleRate, totalFrames: totalFrames,
            events: [.noteOn(atFrame: 0, note: referenceNote, velocity: referenceVelocity)])

        let settledWindowStart = frames(forMs: 250, sampleRate: sampleRate)
        let settledWindowEnd = settledWindowStart + frames(forMs: 50, sampleRate: sampleRate)
        let baselineSettledRMS = rms(of: baseline.left[settledWindowStart..<settledWindowEnd])

        // Szenario A: Update trifft die Stimme WAEHREND Decay (35 ms liegt
        // zwischen Attack-Ende bei 20 ms und Sustain-Erreichen bei 50 ms,
        // Stimme ist also noch nicht in Sustain). Dieses Update darf das
        // laufende Decay-Ziel NICHT rueckwirkend aendern.
        let midDecayFrame = frames(forMs: 35, sampleRate: sampleRate)
        let updatedDuringDecay = try OfflineSynthHarness.render(
            sampleRate: sampleRate, totalFrames: totalFrames,
            events: [
                .noteOn(atFrame: 0, note: referenceNote, velocity: referenceVelocity),
                .paramUpdate(atFrame: midDecayFrame, params: lowerSustain)
            ])
        let updatedDuringDecayRMS = rms(of: updatedDuringDecay.left[settledWindowStart..<settledWindowEnd])
        assertApproximatelyEqual(updatedDuringDecayRMS, expected: baselineSettledRMS, relativeTolerance: 0.05,
                                  label: "Sustain-Update waehrend Decay darf das Decay-Ziel nicht rueckwirkend aendern")

        // Szenario B: Update trifft die Stimme, NACHDEM sie bereits sicher in
        // Sustain ist (250 ms) — muss sofort proportional wirken.
        let midSustainFrame = settledWindowStart
        let updatedDuringSustain = try OfflineSynthHarness.render(
            sampleRate: sampleRate, totalFrames: totalFrames,
            events: [
                .noteOn(atFrame: 0, note: referenceNote, velocity: referenceVelocity),
                .paramUpdate(atFrame: midSustainFrame, params: lowerSustain)
            ])
        let postUpdateStart = midSustainFrame + frames(forMs: 20, sampleRate: sampleRate)
        let postUpdateEnd = postUpdateStart + frames(forMs: 50, sampleRate: sampleRate)
        let updatedDuringSustainRMS = rms(of: updatedDuringSustain.left[postUpdateStart..<postUpdateEnd])

        // Envelope skaliert linear -> RMS-Verhaeltnis entspricht dem
        // Sustain-Pegel-Verhaeltnis (0.3 / 0.7).
        let expectedRatio: Float = 0.3 / 0.7
        let observedRatio = updatedDuringSustainRMS / baselineSettledRMS
        XCTAssertEqual(observedRatio, expectedRatio, accuracy: 0.1,
                      "Sustain-Update waehrend Sustain-Stage sollte sofort proportional zum neuen Pegel wirken")
    }

    // MARK: – Helfer

    private func frames(forMs ms: Double, sampleRate: Double) -> Int {
        Int((ms / 1000.0 * sampleRate).rounded())
    }

    private func rms(of samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return sqrtf(sumSquares / Float(samples.count))
    }

    private func assertApproximatelyEqual(_ value: Float, expected: Float, relativeTolerance: Float,
                                          label: String, file: StaticString = #filePath, line: UInt = #line) {
        let tolerance = max(abs(expected) * relativeTolerance, 1e-4)
        XCTAssertEqual(value, expected, accuracy: tolerance,
                       "\(label): \(value) weicht mehr als \(relativeTolerance * 100)% von \(expected) ab",
                       file: file, line: line)
    }
}
