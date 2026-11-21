import XCTest
@testable import HarmonyEngine3D

// MARK: – OfflineSynthBaselineTests
//
// S-01 (`.agent_handoff/latest_codex.md`, Runde 045): Sicherheitsnetz fuer
// S-02a/S-02b, keine Synth-Weiterentwicklung. Deckt den echten
// `SynthNode`-Rendercallback via `OfflineSynthHarness` ab.
//
// Bewusst NICHT getestet: der Multi-Producer-Fall (SceneKit-/GameController-/
// Main-Thread parallel ueber `AudioEngine.commandQueue`, siehe F-02) — der
// Testtreiber ist hier absichtlich single-threaded (siehe
// `OfflineSynthHarness`-Dokumentation).
//
// ── W-03b2 (Runde 071): diese Datei bewacht ab jetzt AUSDRUECKLICH Legacy ──
//
// Der Produkt-Default ist seit W-03b2 die Atmospheric Voice. Die Baseline
// hier pinnt weiterhin den LEGACY-Klang — sie ist das Regressionsnetz dafuer,
// dass sich der alte Pfad nicht bewegt, waehrend daneben ein neuer entsteht.
// Deshalb waehlt jeder Render in dieser Datei den Stimmtyp jetzt explizit
// (`legacyParams`) statt sich auf einen Default zu verlassen.
//
// Kein einziger Erwartungswert dieser Datei wurde dabei angefasst. Muesste
// einer angefasst werden, haette sich am Legacy-Pfad etwas veraendert, das
// sich nicht haette veraendern duerfen — dann ist das zu melden, nicht
// anzupassen.
//
// Das Gegenstueck fuer den neuen Pfad ist
// `AtmosphericSynthBaselineTests.swift`.

final class OfflineSynthBaselineTests: XCTestCase {

    // MARK: – Test-Szenario-Konstanten

    /// Parametersatz aller Szenarien dieser Datei: Bestandsdefaults mit
    /// explizit gewaehltem Legacy-Stimmtyp (siehe Typ-Dokumentation).
    /// Numerisch identisch zu `SynthParams.defaults` — dieser Default ist
    /// weiterhin `.legacy` (Begruendung in `SynthParams.swift`); die
    /// Explizitheit macht die Baseline unabhaengig davon.
    private var legacyParams: SynthParams {
        var params = SynthParams.defaults
        params.voiceEngine = .legacy
        return params
    }

    /// C4 = MIDI 60, die Referenznote fuer alle Szenarien in dieser Datei.
    private let referenceNote: UInt8 = 60
    private let referenceVelocity: UInt8 = 100

    /// Stille-Schwelle fuer erster/letzter-Frame-oberhalb-Metriken (siehe
    /// `OfflineSynthMetrics.silenceThreshold`). −80 dBFS — deutlich unter
    /// Nutzsignal, deutlich ueber Float-Rundungsrauschen.
    private let silenceThreshold: Float = 1e-4

    // MARK: – 1. Determinismus: identisches Szenario zweimal gerendert

    func test_identicalScenario_renderedTwice_producesIdenticalSamples() throws {
        let sampleRate = 44_100.0
        let totalFrames = frames(forMs: 800, sampleRate: sampleRate)
        let events: [OfflineSynthEvent] = [
            .noteOn(atFrame: 0, note: referenceNote, velocity: referenceVelocity),
            .noteOff(atFrame: frames(forMs: 300, sampleRate: sampleRate), note: referenceNote)
        ]

        let renderA = try OfflineSynthHarness.render(sampleRate: sampleRate, totalFrames: totalFrames,
                                                     params: legacyParams, events: events)
        let renderB = try OfflineSynthHarness.render(sampleRate: sampleRate, totalFrames: totalFrames,
                                                     params: legacyParams, events: events)

        XCTAssertEqual(renderA.frameCount, renderB.frameCount)
        XCTAssertEqual(renderA.left, renderB.left,
                       "Gleiches Szenario muss bitgenau identische Samples liefern — " +
                       "single-threaded Testtreiber, deterministischer DSP-Pfad (keine Zeit-/RNG-Abhaengigkeit).")
        XCTAssertEqual(renderA.right, renderB.right)
    }

    // MARK: – 2. Note-On erzeugt endliche, nicht-stille Ausgabe

    func test_noteOn_producesFiniteNonSilentOutput() throws {
        let sampleRate = 44_100.0
        let totalFrames = frames(forMs: 400, sampleRate: sampleRate)
        let events: [OfflineSynthEvent] = [.noteOn(atFrame: 0, note: referenceNote, velocity: referenceVelocity)]

        let render = try OfflineSynthHarness.render(sampleRate: sampleRate, totalFrames: totalFrames,
                                                    params: legacyParams, events: events)
        let metrics = OfflineSynthMetricsCalculator.compute(render, silenceThreshold: silenceThreshold,
                                                             tailWindowFrames: frames(forMs: 50, sampleRate: sampleRate))

        XCTAssertEqual(metrics.nonFiniteSampleCount, 0)
        XCTAssertGreaterThan(metrics.peakAbsolute, 0.01, "Note-On sollte hoerbaren Pegel erzeugen")
        XCTAssertNotNil(metrics.firstAboveSilenceFrame)
        // Attack ist 20 ms Default — Signal muss deutlich vor Renderende ueber der Schwelle liegen.
        XCTAssertLessThan(metrics.firstAboveSilenceFrame ?? Int.max, frames(forMs: 60, sampleRate: sampleRate))
    }

    // MARK: – 3. Note-Off/All-Off fuehrt nach Release + Sicherheitsfenster zu Stille

    func test_noteOff_afterReleasePlusSafetyWindow_resultsInSilence() throws {
        let sampleRate = 44_100.0
        let noteOffFrame = frames(forMs: 300, sampleRate: sampleRate)
        // Default releaseMs = 300 → 300 (hold) + 300 (release) + 200 (Sicherheitsfenster).
        let totalFrames = frames(forMs: 800, sampleRate: sampleRate)
        let events: [OfflineSynthEvent] = [
            .noteOn(atFrame: 0, note: referenceNote, velocity: referenceVelocity),
            .noteOff(atFrame: noteOffFrame, note: referenceNote)
        ]

        let render = try OfflineSynthHarness.render(sampleRate: sampleRate, totalFrames: totalFrames,
                                                    params: legacyParams, events: events)
        let tailWindow = frames(forMs: 100, sampleRate: sampleRate)
        let metrics = OfflineSynthMetricsCalculator.compute(render, silenceThreshold: silenceThreshold, tailWindowFrames: tailWindow)

        XCTAssertEqual(metrics.nonFiniteSampleCount, 0)
        XCTAssertNotNil(metrics.lastAboveSilenceFrame, "Note sollte ueberhaupt geklungen haben")
        XCTAssertLessThan(metrics.lastAboveSilenceFrame ?? Int.max, totalFrames - frames(forMs: 50, sampleRate: sampleRate),
                          "Nach Release + Sicherheitsfenster sollte das Signal unter die Stille-Schwelle gefallen sein")
        XCTAssertLessThan(metrics.tailEnergy, 1e-3, "Tail-Fenster am Renderende sollte praktisch stumm sein")
    }

    func test_allNotesOff_silencesAllActiveVoices() throws {
        let sampleRate = 44_100.0
        let allOffFrame = frames(forMs: 200, sampleRate: sampleRate)
        let totalFrames = frames(forMs: 700, sampleRate: sampleRate)
        let events: [OfflineSynthEvent] = [
            .noteOn(atFrame: 0, note: 60, velocity: referenceVelocity),
            .noteOn(atFrame: 0, note: 64, velocity: referenceVelocity),
            .noteOn(atFrame: 0, note: 67, velocity: referenceVelocity),
            .allNotesOff(atFrame: allOffFrame)
        ]

        let render = try OfflineSynthHarness.render(sampleRate: sampleRate, totalFrames: totalFrames,
                                                    params: legacyParams, events: events)
        let tailWindow = frames(forMs: 100, sampleRate: sampleRate)
        let metrics = OfflineSynthMetricsCalculator.compute(render, silenceThreshold: silenceThreshold, tailWindowFrames: tailWindow)

        XCTAssertEqual(metrics.nonFiniteSampleCount, 0)
        XCTAssertLessThan(metrics.lastAboveSilenceFrame ?? Int.max, totalFrames - frames(forMs: 50, sampleRate: sampleRate),
                          "allNotesOff muss alle drei Stimmen in Release schicken, keine haengenbleibende Note")
        XCTAssertLessThan(metrics.tailEnergy, 1e-3)
    }

    // MARK: – 4. 44.1 kHz und 48 kHz funktionieren
    //
    // Der real gefahrene Betriebspunkt 96 kHz kommt in Test 4b dazu (W-03c/
    // Runde 072) — bewusst als EIGENER Test, damit dieser hier mitsamt seinem
    // Namen und seiner Ratenliste unangetastet bleibt.

    func test_bothSupportedSampleRates_produceFiniteOutputOfExpectedLength() throws {
        for sampleRate in [44_100.0, 48_000.0] {
            let totalFrames = frames(forMs: 400, sampleRate: sampleRate)
            let events: [OfflineSynthEvent] = [.noteOn(atFrame: 0, note: referenceNote, velocity: referenceVelocity)]

            let render = try OfflineSynthHarness.render(sampleRate: sampleRate, totalFrames: totalFrames,
                                                        params: legacyParams, events: events)
            let metrics = OfflineSynthMetricsCalculator.compute(render, silenceThreshold: silenceThreshold,
                                                                 tailWindowFrames: frames(forMs: 50, sampleRate: sampleRate))

            XCTAssertEqual(render.frameCount, totalFrames, "sampleRate=\(sampleRate)")
            XCTAssertEqual(metrics.nonFiniteSampleCount, 0, "sampleRate=\(sampleRate)")
            XCTAssertGreaterThan(metrics.peakAbsolute, 0.01, "sampleRate=\(sampleRate)")
        }
    }

    // MARK: – 4b. 96 kHz: der real gefahrene Betriebspunkt (W-03c)
    //
    // Die Baselines deckten bis Runde 071 nur 44,1 und 48 kHz ab, waehrend
    // `AudioEngine` die Rate der Hardware uebernimmt
    // (`engine.outputNode.outputFormat(forBus: 0).sampleRate`) — auf der
    // Entwicklungsmaschine 96 kHz. Zwischen dem, was getestet wurde, und dem,
    // was lief, klaffte eine Luecke; dieser Test schliesst sie.
    //
    // Bewusst ein eigener Test statt einer erweiterten Ratenliste in Test 4:
    // so wird kein bestehender Erwartungswert und kein bestehender Testname
    // angefasst. Geprueft werden dieselben Aussagen wie dort, zusaetzlich
    // Note-Off und Ausklingen — der Pfad, auf dem eine ratenabhaengige
    // Huellkurvenrate auffallen wuerde.
    func test_hardwareSampleRate96kHz_behavesLikeTheOtherRates() throws {
        let sampleRate = 96_000.0
        let totalFrames = frames(forMs: 800, sampleRate: sampleRate)
        let noteOffFrame = frames(forMs: 300, sampleRate: sampleRate)
        let events: [OfflineSynthEvent] = [
            .noteOn(atFrame: 0, note: referenceNote, velocity: referenceVelocity),
            .noteOff(atFrame: noteOffFrame, note: referenceNote)
        ]

        let render = try OfflineSynthHarness.render(sampleRate: sampleRate, totalFrames: totalFrames,
                                                    params: legacyParams, events: events)
        let metrics = OfflineSynthMetricsCalculator.compute(render, silenceThreshold: silenceThreshold,
                                                             tailWindowFrames: frames(forMs: 100, sampleRate: sampleRate))

        print(String(format: "[W-03c 96k LEGACY] peak=%.5f rms=%.5f dc=%.5f centroid=%.2f",
                     metrics.peakAbsolute, metrics.rms, metrics.dcOffset, metrics.spectralCentroidHz ?? -1))

        XCTAssertEqual(render.frameCount, totalFrames)
        XCTAssertEqual(metrics.nonFiniteSampleCount, 0)
        XCTAssertGreaterThan(metrics.peakAbsolute, 0.01, "Note-On muss auch bei 96 kHz hoerbaren Pegel erzeugen")
        XCTAssertLessThan(metrics.firstAboveSilenceFrame ?? Int.max, frames(forMs: 60, sampleRate: sampleRate))
        XCTAssertLessThan(metrics.lastAboveSilenceFrame ?? Int.max, totalFrames - frames(forMs: 50, sampleRate: sampleRate),
                          "Auch bei 96 kHz muss die Note nach Release + Sicherheitsfenster verstummt sein")
        XCTAssertLessThan(metrics.tailEnergy, 1e-3)

        // Ratenunabhaengigkeit der Klangfarbe: derselbe Ton bei 96 kHz muss
        // denselben spektralen Schwerpunkt haben wie bei 44,1 kHz. Waere die
        // Oszillator- oder Filterrechnung ratenabhaengig falsch, faende sich
        // die Abweichung genau hier. 10 % Toleranz wie beim
        // Referenzrender-Test.
        let render441 = try OfflineSynthHarness.render(
            sampleRate: 44_100.0, totalFrames: frames(forMs: 800, sampleRate: 44_100.0),
            params: legacyParams,
            events: [.noteOn(atFrame: 0, note: referenceNote, velocity: referenceVelocity),
                     .noteOff(atFrame: frames(forMs: 300, sampleRate: 44_100.0), note: referenceNote)])
        let metrics441 = OfflineSynthMetricsCalculator.compute(
            render441, silenceThreshold: silenceThreshold,
            tailWindowFrames: frames(forMs: 100, sampleRate: 44_100.0))

        let centroid96 = try XCTUnwrap(metrics.spectralCentroidHz)
        let centroid441 = try XCTUnwrap(metrics441.spectralCentroidHz)
        assertApproximatelyEqual(centroid96, expected: centroid441, relativeTolerance: 0.1,
                                 label: "spectralCentroidHz 96 kHz gegen 44,1 kHz")
        assertApproximatelyEqual(metrics.peakAbsolute, expected: metrics441.peakAbsolute,
                                 relativeTolerance: 0.05, label: "peakAbsolute 96 kHz gegen 44,1 kHz")
    }

    // MARK: – 5. Unison-/Stereo-Szenario erzeugt sinnvoll getrennte Kanaele

    func test_unisonWithSpread_producesDistinctStereoChannels() throws {
        let sampleRate = 44_100.0
        let totalFrames = frames(forMs: 500, sampleRate: sampleRate)
        var params = legacyParams
        params.unisonVoices = 3
        params.unisonDetune = 12.0
        params.unisonSpread = 0.8
        let events: [OfflineSynthEvent] = [.noteOn(atFrame: 0, note: referenceNote, velocity: referenceVelocity)]

        let render = try OfflineSynthHarness.render(sampleRate: sampleRate, totalFrames: totalFrames, params: params, events: events)
        let metrics = OfflineSynthMetricsCalculator.compute(render, silenceThreshold: silenceThreshold,
                                                             tailWindowFrames: frames(forMs: 50, sampleRate: sampleRate))

        XCTAssertEqual(metrics.nonFiniteSampleCount, 0)
        XCTAssertGreaterThan(metrics.peakAbsolute, 0.01)
        // L und R sollten sich unterscheiden (Pan-Spread), aber nicht komplett
        // unkorreliert sein (gleiche Quellwellenform, nur Detune/Pan-Offset) —
        // ein plausibler mittlerer Korrelationsbereich statt exakter Gleichheit.
        let correlation = try XCTUnwrap(metrics.stereoCorrelation, "beide Kanaele sollten Signalvarianz haben")
        XCTAssertLessThan(correlation, 0.999, "Stereo-Spread sollte L/R hoerbar unterscheiden, nicht mono-identisch")
        XCTAssertGreaterThan(correlation, -1.0)

        var channelDifferenceSumSquares: Float = 0
        for i in 0..<render.frameCount {
            let diff = render.left[i] - render.right[i]
            channelDifferenceSumSquares += diff * diff
        }
        XCTAssertGreaterThan(channelDifferenceSumSquares, 0, "L und R duerfen bei Stereo-Spread nicht sample-identisch sein")
    }

    // MARK: – 6. Legacy-Referenzrender: festgehaltene Baseline-Metriken

    // Referenzszenario: Default-`SynthParams` (Sinus, ADSR 20/100/0.70/300 ms,
    // kein Unison, Filter voll offen), C4/Velocity 100, 44.1 kHz, gehalten
    // 300 ms, dann Release. Gesamtlaenge 800 ms deckt Attack+Sustain+Release+
    // Sicherheitsfenster ab.
    //
    // Toleranzen: Der DSP-Pfad ist deterministisch (Test 1 beweist Bit-
    // Identitaet bei wiederholtem Render auf derselben Maschine) — die
    // Toleranzen hier sind trotzdem bewusst grosszuegig (relative 5 % bzw.
    // dokumentierte absolute Bandbreiten), weil dieselben Werte ueber
    // unterschiedliche Hardware/OS-/Compiler-Versionen hinweg minimal
    // divergieren koennen (Float-Rundung in trigonometrischen Funktionen).
    // Dieser Test ist eine Baseline-Momentaufnahme des HEUTIGEN Legacy-
    // Synths, kein Vertrag fuer zukuenftige DSP-Aenderungen (S-02+ darf
    // diese Werte nach bewusster Neu-Kalibrierung aktualisieren).
    func test_legacyReferenceRender_matchesDocumentedBaselineMetrics() throws {
        let sampleRate = 44_100.0
        let totalFrames = frames(forMs: 800, sampleRate: sampleRate)
        let noteOffFrame = frames(forMs: 300, sampleRate: sampleRate)
        let events: [OfflineSynthEvent] = [
            .noteOn(atFrame: 0, note: referenceNote, velocity: referenceVelocity),
            .noteOff(atFrame: noteOffFrame, note: referenceNote)
        ]

        let render = try OfflineSynthHarness.render(sampleRate: sampleRate, totalFrames: totalFrames,
                                                    params: legacyParams, events: events)
        let tailWindow = frames(forMs: 100, sampleRate: sampleRate)
        let metrics = OfflineSynthMetricsCalculator.compute(render, silenceThreshold: silenceThreshold, tailWindowFrames: tailWindow)

        XCTAssertEqual(metrics.nonFiniteSampleCount, 0)

        // Baseline-Werte, empirisch mit genau diesem Harness gegen den heutigen
        // Legacy-Synth ermittelt (`swift test --filter
        // test_legacyReferenceRender_matchesDocumentedBaselineMetrics`,
        // Runde 045 / S-01). Kein theoretischer Sollwert, sondern eine
        // Momentaufnahme des IST-Zustands als Regressionsnetz fuer S-02+.
        assertApproximatelyEqual(metrics.peakAbsolute, expected: 0.10546, relativeTolerance: 0.05, label: "peakAbsolute")
        assertApproximatelyEqual(metrics.rms, expected: 0.03470, relativeTolerance: 0.05, label: "rms")
        XCTAssertLessThan(abs(metrics.dcOffset), 0.01, "Sinus-Oszillator sollte keinen nennenswerten DC-Offset haben")

        let centroid = try XCTUnwrap(metrics.spectralCentroidHz, "Referenzton sollte einen bestimmbaren spektralen Schwerpunkt haben")
        // C4-Grundton ≈ 261.63 Hz. Sinus + 15 % 2. Harmonische (523.25 Hz, siehe
        // Waveform.sine-Doku) verschiebt den energiegewichteten Schwerpunkt nach
        // oben; 305 Hz ist der gemessene IST-Wert dieser Kombination.
        assertApproximatelyEqual(centroid, expected: 305.02, relativeTolerance: 0.1, label: "spectralCentroidHz")
    }

    // MARK: – 7. Kein NaN/Infinity in den getesteten Parametergrenzen

    func test_extremeParameterBoundaries_produceNoNaNOrInfinity() throws {
        let sampleRate = 44_100.0
        let totalFrames = frames(forMs: 300, sampleRate: sampleRate)

        var extremeParams = legacyParams
        extremeParams.filterCutoff = 0.0
        extremeParams.filterResonance = 1.0
        extremeParams.attackMs = 0.0
        extremeParams.decayMs = 0.0
        extremeParams.releaseMs = 0.0
        extremeParams.sustain = 0.0
        extremeParams.unisonVoices = 16
        extremeParams.unisonDetune = 100.0
        extremeParams.unisonSpread = 1.0

        for waveform in [Waveform.sine, .saw, .square, .triangle] {
            extremeParams.waveform = waveform
            let events: [OfflineSynthEvent] = [
                .noteOn(atFrame: 0, note: 0, velocity: 127),
                .noteOff(atFrame: frames(forMs: 50, sampleRate: sampleRate), note: 0)
            ]
            let render = try OfflineSynthHarness.render(sampleRate: sampleRate, totalFrames: totalFrames,
                                                         params: extremeParams, events: events)
            let metrics = OfflineSynthMetricsCalculator.compute(render, silenceThreshold: silenceThreshold, tailWindowFrames: 0)
            XCTAssertEqual(metrics.nonFiniteSampleCount, 0, "waveform=\(waveform)")
            XCTAssertLessThanOrEqual(metrics.peakAbsolute, 8.0, "waveform=\(waveform): Pegel sollte in einer plausiblen Bandbreite bleiben, kein DSP-Overflow")
        }
    }

    // MARK: – Helfer

    private func frames(forMs ms: Double, sampleRate: Double) -> Int {
        Int((ms / 1000.0 * sampleRate).rounded())
    }

    private func assertApproximatelyEqual(_ value: Float, expected: Float, relativeTolerance: Float,
                                          label: String, file: StaticString = #filePath, line: UInt = #line) {
        let tolerance = max(abs(expected) * relativeTolerance, 1e-4)
        XCTAssertEqual(value, expected, accuracy: tolerance,
                       "\(label): \(value) weicht mehr als \(relativeTolerance * 100)% von Baseline \(expected) ab",
                       file: file, line: line)
    }
}
