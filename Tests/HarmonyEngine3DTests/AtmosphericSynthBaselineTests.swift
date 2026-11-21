import XCTest
@testable import HarmonyEngine3D

// MARK: – AtmosphericSynthBaselineTests
//
// W-03b2 (`.agent_handoff/latest_codex.md`, Runde 071): eigene Baseline fuer
// den Atmospheric-Pfad, nach demselben Muster wie die S-01-Baseline in
// `OfflineSynthBaselineTests.swift` — Determinismus, Note-On/Off, zwei
// Sample-Raten, Parameterextreme ohne NaN/Infinity, plus festgehaltene
// Referenzmetriken.
//
// ── Abgrenzung gegen SynthVoiceEngineTests ────────────────────────────────
//
// `SynthVoiceEngineTests` (W-03b1) prueft die MECHANIK: dass die gewaehlte
// Stimme wirklich rendert, dass ein Wechsel keine Note haengen laesst, dass
// Voice-Stealing begrenzt bleibt. Diese Datei prueft den KLANG: sie haelt
// den heutigen Ist-Zustand des Atmospheric-Pfads als Zahlen fest, damit eine
// spaetere DSP-Aenderung auffaellt, statt unbemerkt durchzurutschen. Das ist
// dieselbe Rolle, die `OfflineSynthBaselineTests` seit S-01 fuer den
// Legacy-Klang hat.
//
// Beide Baselines laufen ueber den echten `SynthNode`-Rendercallback
// (`OfflineSynthHarness`) und waehlen ihren Stimmtyp ausdruecklich, statt
// sich auf einen Default zu verlassen.

final class AtmosphericSynthBaselineTests: XCTestCase {

    // MARK: – Test-Szenario-Konstanten

    /// Parametersatz aller Szenarien dieser Datei: Bestandsdefaults mit
    /// ausdruecklich gewaehlter Atmospheric Voice.
    private var atmosphericParams: SynthParams {
        var params = SynthParams.defaults
        params.voiceEngine = .atmospheric
        return params
    }

    /// C4 = MIDI 60, die Referenznote fuer alle Szenarien in dieser Datei
    /// (identisch zur Legacy-Baseline, damit beide vergleichbar bleiben).
    private let referenceNote: UInt8 = 60
    private let referenceVelocity: UInt8 = 100

    /// Stille-Schwelle, identisch zur Legacy-Baseline: −80 dBFS.
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
                                                     params: atmosphericParams, events: events)
        let renderB = try OfflineSynthHarness.render(sampleRate: sampleRate, totalFrames: totalFrames,
                                                     params: atmosphericParams, events: events)

        XCTAssertEqual(renderA.frameCount, renderB.frameCount)
        XCTAssertEqual(renderA.left, renderB.left,
                       "Gleiches Szenario muss bitgenau identische Samples liefern — die Texturquelle ist " +
                       "seed-deterministisch (Seed haengt an activationOrder), es gibt keine Zeit-/RNG-Abhaengigkeit.")
        XCTAssertEqual(renderA.right, renderB.right)
    }

    /// Determinismus auch ueber getrennte Pool-Instanzen hinweg: zwei
    /// Renderlaeufe bauen je einen frischen `SynthNode` — der Zustand der
    /// Modulations-/Texturquellen darf nicht aus einem vorherigen Lauf
    /// nachwirken. Deckt einen Fehler ab, den Test 1 nicht sieht, wenn beide
    /// Laeufe zufaellig denselben Startzustand teilen wuerden.
    func test_deterministic_acrossVoiceStealingAndUnison() throws {
        let sampleRate = 48_000.0
        let totalFrames = frames(forMs: 900, sampleRate: sampleRate)
        var params = atmosphericParams
        params.maxVoices = 4
        params.unisonVoices = 2
        params.unisonDetune = 11.0
        params.unisonSpread = 0.7

        var events: [OfflineSynthEvent] = []
        for index in 0..<8 {
            events.append(.noteOn(atFrame: frames(forMs: Double(index) * 20.0, sampleRate: sampleRate),
                                  note: UInt8(55 + index * 2),
                                  velocity: UInt8(80 + index * 4)))
        }
        events.append(.allNotesOff(atFrame: frames(forMs: 400, sampleRate: sampleRate)))

        let renderA = try OfflineSynthHarness.render(sampleRate: sampleRate, totalFrames: totalFrames,
                                                     params: params, events: events)
        let renderB = try OfflineSynthHarness.render(sampleRate: sampleRate, totalFrames: totalFrames,
                                                     params: params, events: events)

        XCTAssertEqual(renderA.left, renderB.left,
                       "Auch mit Voice-Stealing und Unison muss der Atmospheric-Pfad bitgenau reproduzierbar sein")
        XCTAssertEqual(renderA.right, renderB.right)
    }

    // MARK: – 2. Note-On erzeugt endliche, nicht-stille Ausgabe

    func test_noteOn_producesFiniteNonSilentOutput() throws {
        let sampleRate = 44_100.0
        let totalFrames = frames(forMs: 600, sampleRate: sampleRate)
        let events: [OfflineSynthEvent] = [.noteOn(atFrame: 0, note: referenceNote, velocity: referenceVelocity)]

        let render = try OfflineSynthHarness.render(sampleRate: sampleRate, totalFrames: totalFrames,
                                                    params: atmosphericParams, events: events)
        let metrics = OfflineSynthMetricsCalculator.compute(render, silenceThreshold: silenceThreshold,
                                                            tailWindowFrames: frames(forMs: 50, sampleRate: sampleRate))

        XCTAssertEqual(metrics.nonFiniteSampleCount, 0)
        XCTAssertGreaterThan(metrics.peakAbsolute, 0.01, "Note-On sollte hoerbaren Pegel erzeugen")
        XCTAssertNotNil(metrics.firstAboveSilenceFrame)
        // Amp-Attack ist 20 ms Default (aus SynthParams gemappt) — das Signal
        // muss deutlich vor Renderende ueber der Schwelle liegen.
        XCTAssertLessThan(metrics.firstAboveSilenceFrame ?? Int.max, frames(forMs: 60, sampleRate: sampleRate))
    }

    // MARK: – 3. Note-Off/All-Off fuehrt nach Release + Sicherheitsfenster zu Stille

    func test_noteOff_afterReleasePlusSafetyWindow_resultsInSilence() throws {
        let sampleRate = 44_100.0
        // Gemappter Amp-Release: SynthParams.releaseMs = 300 ms Default.
        // 300 (hold) + 300 (release) + 600 (grosszuegiges Sicherheitsfenster).
        let totalFrames = frames(forMs: 1200, sampleRate: sampleRate)
        let events: [OfflineSynthEvent] = [
            .noteOn(atFrame: 0, note: referenceNote, velocity: referenceVelocity),
            .noteOff(atFrame: frames(forMs: 300, sampleRate: sampleRate), note: referenceNote)
        ]

        let render = try OfflineSynthHarness.render(sampleRate: sampleRate, totalFrames: totalFrames,
                                                    params: atmosphericParams, events: events)
        let metrics = OfflineSynthMetricsCalculator.compute(render, silenceThreshold: silenceThreshold,
                                                            tailWindowFrames: frames(forMs: 100, sampleRate: sampleRate))

        XCTAssertEqual(metrics.nonFiniteSampleCount, 0)
        XCTAssertNotNil(metrics.lastAboveSilenceFrame, "Note sollte ueberhaupt geklungen haben")
        XCTAssertLessThan(metrics.lastAboveSilenceFrame ?? Int.max, totalFrames - frames(forMs: 50, sampleRate: sampleRate),
                          "Nach Release + Sicherheitsfenster sollte das Signal unter die Stille-Schwelle gefallen sein")
        XCTAssertLessThan(metrics.tailEnergy, 1e-3, "Tail-Fenster am Renderende sollte praktisch stumm sein")
    }

    func test_allNotesOff_silencesAllActiveVoices() throws {
        let sampleRate = 44_100.0
        let allOffFrame = frames(forMs: 200, sampleRate: sampleRate)
        let totalFrames = frames(forMs: 1100, sampleRate: sampleRate)
        let events: [OfflineSynthEvent] = [
            .noteOn(atFrame: 0, note: 60, velocity: referenceVelocity),
            .noteOn(atFrame: 0, note: 64, velocity: referenceVelocity),
            .noteOn(atFrame: 0, note: 67, velocity: referenceVelocity),
            .allNotesOff(atFrame: allOffFrame)
        ]

        let render = try OfflineSynthHarness.render(sampleRate: sampleRate, totalFrames: totalFrames,
                                                    params: atmosphericParams, events: events)
        let metrics = OfflineSynthMetricsCalculator.compute(render, silenceThreshold: silenceThreshold,
                                                            tailWindowFrames: frames(forMs: 100, sampleRate: sampleRate))

        XCTAssertEqual(metrics.nonFiniteSampleCount, 0)
        XCTAssertLessThan(metrics.lastAboveSilenceFrame ?? Int.max, totalFrames - frames(forMs: 50, sampleRate: sampleRate),
                          "allNotesOff muss alle drei Stimmen in Release schicken, keine haengenbleibende Note")
        XCTAssertLessThan(metrics.tailEnergy, 1e-3)
    }

    // MARK: – 4. 44.1 kHz und 48 kHz funktionieren
    //
    // Der real gefahrene Betriebspunkt 96 kHz kommt in Test 4b dazu (W-03c/
    // Runde 072) — wie in der Legacy-Baseline bewusst als eigener Test, damit
    // dieser hier unangetastet bleibt.

    func test_bothSupportedSampleRates_produceFiniteOutputOfExpectedLength() throws {
        for sampleRate in [44_100.0, 48_000.0] {
            let totalFrames = frames(forMs: 400, sampleRate: sampleRate)
            let events: [OfflineSynthEvent] = [.noteOn(atFrame: 0, note: referenceNote, velocity: referenceVelocity)]

            let render = try OfflineSynthHarness.render(sampleRate: sampleRate, totalFrames: totalFrames,
                                                        params: atmosphericParams, events: events)
            let metrics = OfflineSynthMetricsCalculator.compute(render, silenceThreshold: silenceThreshold,
                                                                tailWindowFrames: frames(forMs: 50, sampleRate: sampleRate))

            XCTAssertEqual(render.frameCount, totalFrames, "sampleRate=\(sampleRate)")
            XCTAssertEqual(metrics.nonFiniteSampleCount, 0, "sampleRate=\(sampleRate)")
            XCTAssertGreaterThan(metrics.peakAbsolute, 0.01, "sampleRate=\(sampleRate)")
        }
    }

    // MARK: – 4b. 96 kHz: der real gefahrene Betriebspunkt (W-03c)
    //
    // Gegenstueck zum gleichnamigen Test in der Legacy-Baseline. Fuer die
    // Atmospheric Voice ist die Rate zusaetzlich relevant, weil ihre interne
    // Kontrollrate daran haengt (`controlRate = sampleRate /
    // controlBlockSize`, siehe `AudioCoreAtmosphericVoice`): LFOs und
    // Mod-Huelle laufen bei 96 kHz doppelt so oft pro Sekunde durch den
    // Kontrollschritt wie bei 48 kHz. Genau dort wuerde eine ratenabhaengige
    // Modulationsgeschwindigkeit auffallen — deshalb vergleicht der Test die
    // Klangfarbe gegen 44,1 kHz statt nur auf Endlichkeit zu pruefen.
    func test_hardwareSampleRate96kHz_behavesLikeTheOtherRates() throws {
        let sampleRate = 96_000.0
        let totalFrames = frames(forMs: 1200, sampleRate: sampleRate)
        let events: [OfflineSynthEvent] = [
            .noteOn(atFrame: 0, note: referenceNote, velocity: referenceVelocity),
            .noteOff(atFrame: frames(forMs: 300, sampleRate: sampleRate), note: referenceNote)
        ]

        let render = try OfflineSynthHarness.render(sampleRate: sampleRate, totalFrames: totalFrames,
                                                    params: atmosphericParams, events: events)
        let metrics = OfflineSynthMetricsCalculator.compute(render, silenceThreshold: silenceThreshold,
                                                            tailWindowFrames: frames(forMs: 100, sampleRate: sampleRate))

        print(String(format: "[W-03c 96k ATMO] peak=%.5f rms=%.5f dc=%.5f centroid=%.2f",
                     metrics.peakAbsolute, metrics.rms, metrics.dcOffset, metrics.spectralCentroidHz ?? -1))

        XCTAssertEqual(render.frameCount, totalFrames)
        XCTAssertEqual(metrics.nonFiniteSampleCount, 0)
        XCTAssertGreaterThan(metrics.peakAbsolute, 0.01, "Note-On muss auch bei 96 kHz hoerbaren Pegel erzeugen")
        XCTAssertLessThan(metrics.firstAboveSilenceFrame ?? Int.max, frames(forMs: 60, sampleRate: sampleRate))
        XCTAssertLessThan(metrics.lastAboveSilenceFrame ?? Int.max, totalFrames - frames(forMs: 50, sampleRate: sampleRate),
                          "Auch bei 96 kHz muss die Note nach Release + Sicherheitsfenster verstummt sein")
        XCTAssertLessThan(metrics.tailEnergy, 1e-3)

        let render441 = try OfflineSynthHarness.render(
            sampleRate: 44_100.0, totalFrames: frames(forMs: 1200, sampleRate: 44_100.0),
            params: atmosphericParams,
            events: [.noteOn(atFrame: 0, note: referenceNote, velocity: referenceVelocity),
                     .noteOff(atFrame: frames(forMs: 300, sampleRate: 44_100.0), note: referenceNote)])
        let metrics441 = OfflineSynthMetricsCalculator.compute(
            render441, silenceThreshold: silenceThreshold,
            tailWindowFrames: frames(forMs: 100, sampleRate: 44_100.0))

        let centroid96 = try XCTUnwrap(metrics.spectralCentroidHz)
        let centroid441 = try XCTUnwrap(metrics441.spectralCentroidHz)
        // Groessere Toleranz als bei Legacy: die Texturquelle der Atmospheric
        // Voice ist ein ratenabhaengig gefaerbtes Rauschen — ihr Beitrag zum
        // Schwerpunkt darf sich mit der Rate leicht verschieben, ohne dass
        // etwas falsch waere.
        assertApproximatelyEqual(centroid96, expected: centroid441, relativeTolerance: 0.25,
                                 label: "spectralCentroidHz 96 kHz gegen 44,1 kHz")
        assertApproximatelyEqual(metrics.peakAbsolute, expected: metrics441.peakAbsolute,
                                 relativeTolerance: 0.1, label: "peakAbsolute 96 kHz gegen 44,1 kHz")
    }

    // MARK: – 5. Unison-/Stereo-Szenario erzeugt sinnvoll getrennte Kanaele

    func test_unisonWithSpread_producesDistinctStereoChannels() throws {
        let sampleRate = 44_100.0
        let totalFrames = frames(forMs: 500, sampleRate: sampleRate)
        var params = atmosphericParams
        params.unisonVoices = 3
        params.unisonDetune = 12.0
        params.unisonSpread = 0.8
        let events: [OfflineSynthEvent] = [.noteOn(atFrame: 0, note: referenceNote, velocity: referenceVelocity)]

        let render = try OfflineSynthHarness.render(sampleRate: sampleRate, totalFrames: totalFrames,
                                                    params: params, events: events)
        let metrics = OfflineSynthMetricsCalculator.compute(render, silenceThreshold: silenceThreshold,
                                                            tailWindowFrames: frames(forMs: 50, sampleRate: sampleRate))

        XCTAssertEqual(metrics.nonFiniteSampleCount, 0)
        XCTAssertGreaterThan(metrics.peakAbsolute, 0.01)
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

    // MARK: – 6. Atmospheric-Referenzrender: festgehaltene Baseline-Metriken

    // Referenzszenario, absichtlich Zeichen fuer Zeichen wie in der
    // Legacy-Baseline: Default-`SynthParams` (ADSR 20/100/0.70/300 ms, kein
    // Unison, Filter voll offen) mit Stimmtyp `.atmospheric`, C4/Velocity 100,
    // 44.1 kHz, gehalten 300 ms, dann Release. Gesamtlaenge 1200 ms deckt
    // Attack+Sustain+Release+Sicherheitsfenster ab (laenger als bei Legacy,
    // weil die Atmospheric-Huelle langsamer ausklingt).
    //
    // Toleranzen wie in der Legacy-Baseline: der Pfad ist deterministisch
    // (Test 1 beweist Bit-Identitaet auf derselben Maschine), die relativen
    // 5 % bzw. 10 % decken Float-Rundungsunterschiede ueber Hardware-/
    // Compiler-Versionen ab.
    //
    // Dies ist eine Momentaufnahme des HEUTIGEN Atmospheric-Klangs, kein
    // Vertrag fuer die Zukunft: die Voicing-Runde nach W-05 wird diese Werte
    // bewusst neu kalibrieren. Bis dahin gilt — weicht ein Wert ab, ohne dass
    // eine Klangaenderung beauftragt war, ist das zu melden, nicht anzupassen.
    func test_atmosphericReferenceRender_matchesDocumentedBaselineMetrics() throws {
        let sampleRate = 44_100.0
        let totalFrames = frames(forMs: 1200, sampleRate: sampleRate)
        let noteOffFrame = frames(forMs: 300, sampleRate: sampleRate)
        let events: [OfflineSynthEvent] = [
            .noteOn(atFrame: 0, note: referenceNote, velocity: referenceVelocity),
            .noteOff(atFrame: noteOffFrame, note: referenceNote)
        ]

        let render = try OfflineSynthHarness.render(sampleRate: sampleRate, totalFrames: totalFrames,
                                                    params: atmosphericParams, events: events)
        let tailWindow = frames(forMs: 100, sampleRate: sampleRate)
        let metrics = OfflineSynthMetricsCalculator.compute(render, silenceThreshold: silenceThreshold, tailWindowFrames: tailWindow)

        print(String(format: "[W-03b2 BASELINE] peak=%.5f rms=%.5f dc=%.5f centroid=%.2f",
                     metrics.peakAbsolute, metrics.rms, metrics.dcOffset, metrics.spectralCentroidHz ?? -1))

        XCTAssertEqual(metrics.nonFiniteSampleCount, 0)

        // Baseline-Werte, empirisch mit genau diesem Harness gegen den
        // heutigen Atmospheric-Pfad ermittelt (Runde 071 / W-03b2). Kein
        // theoretischer Sollwert, sondern eine Momentaufnahme des IST-Zustands.
        assertApproximatelyEqual(metrics.peakAbsolute, expected: 0.10232, relativeTolerance: 0.05, label: "peakAbsolute")
        assertApproximatelyEqual(metrics.rms, expected: 0.02956, relativeTolerance: 0.05, label: "rms")
        XCTAssertLessThan(abs(metrics.dcOffset), 0.01, "Der Atmospheric-Pfad sollte keinen nennenswerten DC-Offset haben")

        let centroid = try XCTUnwrap(metrics.spectralCentroidHz, "Referenzton sollte einen bestimmbaren spektralen Schwerpunkt haben")
        assertApproximatelyEqual(centroid, expected: 2034.30, relativeTolerance: 0.1, label: "spectralCentroidHz")
    }

    /// Pegelgrenze des Referenzrenders — getrennt vom Metrikvergleich oben,
    /// weil diese Aussage haerter ist: sie darf sich auch bei einer bewussten
    /// Neukalibrierung nicht aufweichen. Ein Synth, der ueber 1.0 laeuft,
    /// uebersteuert die nachgeschaltete Kette.
    func test_atmosphericReferenceRender_staysBelowFullScale() throws {
        let sampleRate = 44_100.0
        let totalFrames = frames(forMs: 1200, sampleRate: sampleRate)
        var params = atmosphericParams
        params.unisonVoices = 3
        params.unisonDetune = 12.0

        let events: [OfflineSynthEvent] = [
            .noteOn(atFrame: 0, note: 60, velocity: 127),
            .noteOn(atFrame: 0, note: 64, velocity: 127),
            .noteOn(atFrame: 0, note: 67, velocity: 127),
            .allNotesOff(atFrame: frames(forMs: 500, sampleRate: sampleRate))
        ]

        let render = try OfflineSynthHarness.render(sampleRate: sampleRate, totalFrames: totalFrames,
                                                    params: params, events: events)
        let metrics = OfflineSynthMetricsCalculator.compute(render, silenceThreshold: silenceThreshold, tailWindowFrames: 0)

        print(String(format: "[W-03b2 FULLSCALE] peak=%.5f rms=%.5f", metrics.peakAbsolute, metrics.rms))
        XCTAssertEqual(metrics.nonFiniteSampleCount, 0)
        XCTAssertLessThan(metrics.peakAbsolute, 1.0,
                          "Drei Noten x 3 Unison bei Velocity 127 duerfen den Vollausschlag der Quelle nicht erreichen")
    }

    // MARK: – 7. Kein NaN/Infinity in den getesteten Parametergrenzen

    func test_extremeParameterBoundaries_produceNoNaNOrInfinity() throws {
        let sampleRate = 44_100.0
        let totalFrames = frames(forMs: 300, sampleRate: sampleRate)

        var extremeParams = atmosphericParams
        extremeParams.filterCutoff = 0.0
        extremeParams.filterResonance = 1.0
        extremeParams.attackMs = 0.0
        extremeParams.decayMs = 0.0
        extremeParams.releaseMs = 0.0
        extremeParams.sustain = 0.0
        extremeParams.unisonVoices = 16
        extremeParams.unisonDetune = 100.0
        extremeParams.unisonSpread = 1.0

        // `waveform` bildet auf die Atmospheric Voice bewusst nicht ab (siehe
        // AudioCoreMapping) — die Schleife bleibt trotzdem, damit dieselbe
        // Szenariomatrix wie in der Legacy-Baseline gefahren wird und ein
        // spaeteres Mapping hier automatisch mitgeprueft wird.
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
            XCTAssertLessThanOrEqual(metrics.peakAbsolute, 8.0,
                                     "waveform=\(waveform): Pegel sollte in einer plausiblen Bandbreite bleiben, kein DSP-Overflow")
        }

        // Gegenrichtung: hoechste Note, Velocity 1, Filter voll offen — der
        // Pfad, auf dem eine Division durch die Huellenzeit oder eine
        // Frequenz nahe Nyquist entgleisen wuerde.
        var edgeParams = atmosphericParams
        edgeParams.filterCutoff = 1.0
        edgeParams.attackMs = 0.0
        edgeParams.releaseMs = 0.0
        let render = try OfflineSynthHarness.render(
            sampleRate: sampleRate, totalFrames: totalFrames, params: edgeParams,
            events: [.noteOn(atFrame: 0, note: 127, velocity: 1),
                     .noteOff(atFrame: frames(forMs: 50, sampleRate: sampleRate), note: 127)])
        let metrics = OfflineSynthMetricsCalculator.compute(render, silenceThreshold: silenceThreshold, tailWindowFrames: 0)
        XCTAssertEqual(metrics.nonFiniteSampleCount, 0, "MIDI 127 / Velocity 1 darf keine nicht-endlichen Samples erzeugen")
        XCTAssertLessThanOrEqual(metrics.peakAbsolute, 8.0)
    }

    // MARK: – 8. Der Produkt-Default ist die Atmospheric Voice (Gate 1)

    /// Kernaussage des Slices: beim Start ist die Atmospheric Voice aktiv.
    /// Der Produkt-Default liegt in `AppSettings.AudioConfig` — das ist die
    /// Einstellung, die der App-Layer beim Start in die `AudioEngine` und von
    /// dort in jeden `SynthParams`-Snapshot traegt.
    func test_productDefaultVoiceEngine_isAtmospheric() {
        XCTAssertEqual(AudioConfig().voiceEngine, .atmospheric,
                       "W-03b2 kippt den Produkt-Default auf die Atmospheric Voice (Stephan-Entscheidung 2026-08-02)")
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
