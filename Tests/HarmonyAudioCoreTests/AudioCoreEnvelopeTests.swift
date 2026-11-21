import XCTest
@testable import HarmonyAudioCore

// MARK: – AudioCoreEnvelopeTests
//
// S-05a (`.agent_handoff/latest_codex.md`, Runde 052), Scope A/E: der
// eigenstaendige Envelope-Baustein erreicht samplegenaue Stage-Uebergaenge
// bei 44.1/48 kHz, startet eine kontrollierte Release-Phase aus jeder
// aktiven Stage, reproduziert nach `reset()` denselben Verlauf, traegt
// Amp-/Mod-Rolle als getrennte Instanzen/Parameterprofile und bleibt bei
// Extremparametern finite.

final class AudioCoreEnvelopeTests: XCTestCase {

    // MARK: – 1./2. Samplegenaue Stage-Uebergaenge bei 44.1 und 48 kHz

    func test_attackDecayRelease_reachesExpectedStageBoundariesAtBothSampleRates() {
        for sampleRate in [44_100.0, 48_000.0] {
            let parameters = AudioCoreEnvelopeParameters(attackMs: 10, decayMs: 40, sustainLevel: 0.5, releaseMs: 60)
            var envelope = AudioCoreEnvelope(parameters: parameters)
            envelope.noteOn(sampleRate: sampleRate)

            let expectedAttackSamples = Int((Double(parameters.attackMs) * 0.001 * sampleRate).rounded())
            let expectedDecaySamples = Int((Double(1.0 - parameters.sustainLevel) * Double(parameters.decayMs) * 0.001 * sampleRate).rounded())

            let stages = renderStages(&envelope, frameCount: expectedAttackSamples + expectedDecaySamples + 200)

            let attackFrameCount = stages.prefix(while: { $0 == .attack }).count
            assertApproximatelyEqual(Float(attackFrameCount), expected: Float(expectedAttackSamples),
                                     tolerance: max(2, Float(expectedAttackSamples) * 0.01),
                                     label: "attack-samples@\(sampleRate)")

            let decayFrameCount = stages.dropFirst(attackFrameCount).prefix(while: { $0 == .decay }).count
            assertApproximatelyEqual(Float(decayFrameCount), expected: Float(expectedDecaySamples),
                                     tolerance: max(2, Float(expectedDecaySamples) * 0.01),
                                     label: "decay-samples@\(sampleRate)")

            XCTAssertEqual(stages.last, .sustain, "nach Attack+Decay sollte die Huellkurve im Sustain stehen (sampleRate=\(sampleRate))")
        }
    }

    // MARK: – 3. NoteOff startet aus jeder aktiven Stage eine kontrollierte Release-Phase

    func test_noteOff_duringAttackDecayOrSustain_startsControlledRelease() {
        let parameters = AudioCoreEnvelopeParameters(attackMs: 20, decayMs: 40, sustainLevel: 0.5, releaseMs: 100)
        let sampleRate = 44_100.0

        // waehrend Attack: Release senkt den Wert kontrolliert ab, statt abrupt auf 0 zu springen.
        var duringAttack = AudioCoreEnvelope(parameters: parameters)
        duringAttack.noteOn(sampleRate: sampleRate)
        _ = duringAttack.nextValue()
        _ = duringAttack.nextValue()
        XCTAssertEqual(duringAttack.stage, .attack, "Vorbedingung: Huellkurve sollte hier noch in Attack stehen")
        duringAttack.noteOff()
        XCTAssertEqual(duringAttack.stage, .release)
        let valueAtReleaseStart = duringAttack.value
        let nextAfterRelease = duringAttack.nextValue()
        XCTAssertLessThan(nextAfterRelease, valueAtReleaseStart,
                           "Release sollte den Wert kontrolliert absenken, nicht abrupt auf 0 springen")
        XCTAssertGreaterThan(nextAfterRelease, 0, "ein einzelner Release-Schritt sollte den Wert noch nicht auf 0 bringen")

        // waehrend Decay
        var duringDecay = AudioCoreEnvelope(parameters: parameters)
        duringDecay.noteOn(sampleRate: sampleRate)
        _ = renderStages(&duringDecay, frameCount: Int((Double(parameters.attackMs) * 0.001 * sampleRate).rounded()) + 5)
        XCTAssertEqual(duringDecay.stage, .decay, "Vorbedingung: Huellkurve sollte hier in Decay stehen")
        duringDecay.noteOff()
        XCTAssertEqual(duringDecay.stage, .release)

        // waehrend Sustain, plus Nachweis, dass Release letztlich zu idle/Stille fuehrt.
        var duringSustain = AudioCoreEnvelope(parameters: parameters)
        duringSustain.noteOn(sampleRate: sampleRate)
        let attackSamples = Int((Double(parameters.attackMs) * 0.001 * sampleRate).rounded())
        let decaySamples = Int((Double(parameters.decayMs) * 0.001 * sampleRate).rounded())
        _ = renderStages(&duringSustain, frameCount: attackSamples + decaySamples + 50)
        XCTAssertEqual(duringSustain.stage, .sustain, "Vorbedingung: Huellkurve sollte hier im Sustain stehen")
        duringSustain.noteOff()
        XCTAssertEqual(duringSustain.stage, .release)

        let releaseStages = renderStages(&duringSustain, frameCount: Int((Double(parameters.releaseMs) * 0.001 * sampleRate).rounded()) + 500)
        XCTAssertEqual(releaseStages.last, .idle)
        XCTAssertFalse(duringSustain.isActive)
    }

    func test_noteOff_whenIdle_hasNoEffect() {
        var envelope = AudioCoreEnvelope(parameters: .defaults)
        XCTAssertEqual(envelope.stage, .idle)
        envelope.noteOff()
        XCTAssertEqual(envelope.stage, .idle, "noteOff() sollte auf eine idle Huellkurve keine Wirkung haben")
    }

    // MARK: – 4. reset() reproduziert denselben Verlauf wie eine frische Instanz

    func test_reset_thenNoteOn_reproducesSameTrajectoryAsFreshInstance() {
        let parameters = AudioCoreEnvelopeParameters(attackMs: 15, decayMs: 30, sustainLevel: 0.6, releaseMs: 80)
        let sampleRate = 44_100.0

        var fresh = AudioCoreEnvelope(parameters: parameters)
        fresh.noteOn(sampleRate: sampleRate)
        let freshValues = (0..<300).map { _ in fresh.nextValue() }

        var reused = AudioCoreEnvelope(parameters: parameters)
        reused.noteOn(sampleRate: sampleRate)
        _ = (0..<50).map { _ in reused.nextValue() }
        reused.reset()
        reused.noteOn(sampleRate: sampleRate)
        let reusedValues = (0..<300).map { _ in reused.nextValue() }

        XCTAssertEqual(freshValues, reusedValues)
    }

    // MARK: – 5. Amp- und Mod-Huelle als getrennte Instanzen/Parameterprofile

    func test_ampAndModEnvelope_canHaveIndependentInstancesAndParameterProfiles() {
        // Amp: kurze Zeiten, erreicht innerhalb des Testfensters sicher Sustain.
        let ampParameters = AudioCoreEnvelopeParameters(attackMs: 1, decayMs: 2, sustainLevel: 0.8, releaseMs: 50)
        // Mod: deutlich laengere Attack-Zeit, bleibt im selben Testfenster sicher in Attack.
        let modParameters = AudioCoreEnvelopeParameters(attackMs: 50, decayMs: 100, sustainLevel: 0.3, releaseMs: 300)

        var ampEnvelope = AudioCoreEnvelope(parameters: ampParameters)
        var modEnvelope = AudioCoreEnvelope(parameters: modParameters)

        ampEnvelope.noteOn(sampleRate: 44_100.0)
        modEnvelope.noteOn(sampleRate: 44_100.0)

        let ampValues = (0..<200).map { _ in ampEnvelope.nextValue() }
        let modValues = (0..<200).map { _ in modEnvelope.nextValue() }

        XCTAssertNotEqual(ampValues, modValues, "unterschiedliche Parameterprofile sollten unterschiedliche Verlaeufe erzeugen")
        XCTAssertEqual(ampEnvelope.stage, .sustain, "Amp-Profil sollte mit kurzen Zeiten laengst im Sustain stehen")
        XCTAssertEqual(modEnvelope.stage, .attack, "Mod-Profil sollte mit seiner viel laengeren Attack-Zeit noch nicht dort angekommen sein")
    }

    // MARK: – 10. Extremparameter bleiben finite

    func test_extremeParameters_produceFiniteValues() {
        let extremeCases: [(attackMs: Float, decayMs: Float, sustain: Float, releaseMs: Float)] = [
            (.nan, 10, 0.5, 10),
            (.infinity, 10, 0.5, 10),
            (0, .nan, 0.5, 10),
            (0, 0, .nan, 10),
            (0, 0, .infinity, 10),
            (0, 0, 0.5, .nan),
            (-10, -10, -1, -10),
            (0, 0, 0, 0)
        ]

        for testCase in extremeCases {
            let parameters = AudioCoreEnvelopeParameters(attackMs: testCase.attackMs, decayMs: testCase.decayMs,
                                                          sustainLevel: testCase.sustain, releaseMs: testCase.releaseMs)
            var envelope = AudioCoreEnvelope(parameters: parameters)
            envelope.noteOn(sampleRate: 44_100.0)
            let values = (0..<2_000).map { _ in envelope.nextValue() }
            XCTAssertTrue(values.allSatisfy { $0.isFinite }, "Extremfall \(testCase) erzeugte einen nicht-endlichen Wert")

            envelope.noteOff()
            let releaseValues = (0..<2_000).map { _ in envelope.nextValue() }
            XCTAssertTrue(releaseValues.allSatisfy { $0.isFinite }, "Extremfall \(testCase) erzeugte in Release einen nicht-endlichen Wert")
        }
    }

    // MARK: – Helper

    private func renderStages(_ envelope: inout AudioCoreEnvelope, frameCount: Int) -> [AudioCoreADSRStage] {
        var stages: [AudioCoreADSRStage] = []
        stages.reserveCapacity(frameCount)
        for _ in 0..<frameCount {
            _ = envelope.nextValue()
            stages.append(envelope.stage)
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
