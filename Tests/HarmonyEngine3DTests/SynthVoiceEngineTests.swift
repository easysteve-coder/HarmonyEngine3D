import XCTest
import HarmonyAudioCore
@testable import HarmonyEngine3D

// MARK: – SynthVoiceEngineTests
//
// W-03b1 (`.agent_handoff/latest_codex.md`, Runde 070): Umschaltmechanik
// zwischen Legacy- und Atmospheric-Stimme im echten `SynthNode`-Renderpfad,
// getrieben ueber `OfflineSynthHarness` (S-01).
//
// Die Tests decken die drei Fragen ab, die der Slice offen laesst:
//   1. Bleibt der Klang bei Default-Einstellung bit-identisch? (Gate 1)
//   2. Rendert die Atmospheric Voice tatsaechlich, wenn sie gewaehlt ist —
//      nicht nur "der Schalter steht um"? (Gate 2)
//   3. Laesst ein Wechsel im laufenden Betrieb eine Note haengen? (Gate 5/6)

final class SynthVoiceEngineTests: XCTestCase {

    private let referenceNote: UInt8 = 60
    private let referenceVelocity: UInt8 = 100
    private let silenceThreshold: Float = 1e-4

    // MARK: – 1. Bit-Identitaet bei Default-Einstellung (Gate 1)

    // Kernnachweis des Slices. Die Referenz-Pruefsumme ist NICHT aus dem
    // aktuellen Stand erzeugt, sondern aus einem separaten Klon von Commit
    // `13e5eaf` (Stand vor W-03b1) mit exakt derselben Szenariofolge — dort
    // uebersetzt ohne jede Kenntnis von `SynthVoiceEngine`.
    //
    // Verglichen werden rohe `Float.bitPattern`-Werte, nicht Metriken: eine
    // Toleranz wuerde genau die Klasse von Abweichung durchlassen, die dieses
    // Gate ausschliessen soll.
    //
    // Die Szenarien decken bewusst alle Pfade ab, die W-03b1 angefasst hat:
    // Voice-Zuteilung, Voice-Stealing (mehr Noten als Poolgroesse), Unison,
    // Release, All-Off, den Live-Parameterpfad (`applyParams` mit Cutoff-/
    // Resonanz-/Sustain-Aenderung mitten im Render) und beide Sample-Raten.
    func test_w03b1_legacyDefaultRender_isBitIdenticalToPreSwitchBaseline() throws {
        let checksum = try SynthVoiceEngineTests.legacyScenarioChecksum()
        print("[W-03b1] Legacy-Szenario-Pruefsumme: 0x\(String(checksum, radix: 16))")

        // Erzeugt am 2026-08-02 aus einem Klon von `13e5eaf` mit identischer
        // Szenariofolge (siehe Ruecklauf Runde 070), zweimal reproduziert.
        // Gilt fuer den Debug-Testlauf (`swift test`), wie alle
        // Pruefsummen-Baselines dieses Projekts.
        XCTAssertEqual(checksum, 0x86a4_b146_fd9f_13e9,
                       "Bei Default-Einstellung (.legacy) muss der Klang bit-identisch zu `13e5eaf` bleiben. " +
                       "Weicht dieser Wert ab, hat sich der Legacy-Renderpfad veraendert — melden, nicht anpassen.")
    }

    /// Szenariofolge des Bit-Identitaets-Nachweises. Bewusst ohne jede
    /// Referenz auf `SynthVoiceEngine`, damit derselbe Code unveraendert gegen
    /// den Stand `13e5eaf` uebersetzt werden kann.
    static func legacyScenarioChecksum() throws -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325

        func absorb(_ render: OfflineRenderResult) {
            for value in render.left  { hash = SynthVoiceEngineTests.fnv1a(hash, value.bitPattern) }
            for value in render.right { hash = SynthVoiceEngineTests.fnv1a(hash, value.bitPattern) }
            hash = SynthVoiceEngineTests.fnv1a(hash, UInt32(truncatingIfNeeded: render.frameCount))
        }

        func frames(_ ms: Double, _ sampleRate: Double) -> Int { Int((ms / 1000.0 * sampleRate).rounded()) }

        for sampleRate in [44_100.0, 48_000.0] {

            // A) Einzelne Note, gehalten und released.
            absorb(try OfflineSynthHarness.render(
                sampleRate: sampleRate,
                totalFrames: frames(800, sampleRate),
                events: [.noteOn(atFrame: 0, note: 60, velocity: 100),
                         .noteOff(atFrame: frames(300, sampleRate), note: 60)]))

            // B) Unison mit Spread — Detune-/Pan-Verteilung ueber mehrere Stimmen.
            var unison = SynthParams.defaults
            unison.unisonVoices = 3
            unison.unisonDetune = 12.0
            unison.unisonSpread = 0.8
            absorb(try OfflineSynthHarness.render(
                sampleRate: sampleRate,
                totalFrames: frames(500, sampleRate),
                params: unison,
                events: [.noteOn(atFrame: 0, note: 64, velocity: 90),
                         .noteOff(atFrame: frames(250, sampleRate), note: 64)]))

            // C) Mehr gleichzeitige Noten als Poolplaetze — erzwingt
            //    Voice-Stealing ueber `activationOrder`.
            var small = SynthParams.defaults
            small.maxVoices = 4
            small.waveform = .saw
            var stealingEvents: [OfflineSynthEvent] = []
            for index in 0..<10 {
                stealingEvents.append(.noteOn(atFrame: frames(Double(index) * 10.0, sampleRate),
                                              note: UInt8(48 + index * 3),
                                              velocity: UInt8(70 + index * 5)))
            }
            stealingEvents.append(.allNotesOff(atFrame: frames(300, sampleRate)))
            absorb(try OfflineSynthHarness.render(
                sampleRate: sampleRate,
                totalFrames: frames(700, sampleRate),
                params: small,
                events: stealingEvents))

            // D) Live-Parameterpfad: Cutoff, Resonanz und Sustain aendern sich
            //    mitten im gehaltenen Ton (genau der `applyParams`-Zweig, den
            //    W-03b1 umgebaut hat).
            var live = SynthParams.defaults
            live.waveform = .triangle
            live.filterCutoff = 0.8
            live.filterResonance = 0.2
            var swept = live
            swept.filterCutoff = 0.25
            swept.filterResonance = 0.75
            swept.sustain = 0.30
            var swept2 = swept
            swept2.filterCutoff = 0.95
            swept2.sustain = 0.90
            absorb(try OfflineSynthHarness.render(
                sampleRate: sampleRate,
                totalFrames: frames(900, sampleRate),
                params: live,
                events: [.noteOn(atFrame: 0, note: 55, velocity: 120),
                         .paramUpdate(atFrame: frames(100, sampleRate), params: swept),
                         .paramUpdate(atFrame: frames(200, sampleRate), params: swept2),
                         .noteOff(atFrame: frames(400, sampleRate), note: 55)]))

            // E) Parametergrenzen — kurze Huellen, volle Resonanz, 16 Unison.
            var extreme = SynthParams.defaults
            extreme.filterCutoff = 0.0
            extreme.filterResonance = 1.0
            extreme.attackMs = 0.0
            extreme.decayMs = 0.0
            extreme.releaseMs = 0.0
            extreme.sustain = 0.0
            extreme.unisonVoices = 16
            extreme.unisonDetune = 100.0
            extreme.unisonSpread = 1.0
            extreme.waveform = .square
            absorb(try OfflineSynthHarness.render(
                sampleRate: sampleRate,
                totalFrames: frames(300, sampleRate),
                params: extreme,
                events: [.noteOn(atFrame: 0, note: 0, velocity: 127),
                         .noteOff(atFrame: frames(50, sampleRate), note: 0)]))
        }

        return hash
    }

    private static func fnv1a(_ hash: UInt64, _ value: UInt32) -> UInt64 {
        var result = hash
        for shift in stride(from: 0, through: 24, by: 8) {
            result ^= UInt64(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
            result = result &* 0x1000_0000_01b3
        }
        return result
    }

    // MARK: – 2. Die Atmospheric Voice rendert tatsaechlich (Gate 2)

    func test_atmosphericEngine_producesFiniteNonSilentOutput() throws {
        let sampleRate = 44_100.0
        var params = SynthParams.defaults
        params.voiceEngine = .atmospheric

        let render = try OfflineSynthHarness.render(
            sampleRate: sampleRate,
            totalFrames: frames(forMs: 600, sampleRate: sampleRate),
            params: params,
            events: [.noteOn(atFrame: 0, note: referenceNote, velocity: referenceVelocity)])
        let metrics = OfflineSynthMetricsCalculator.compute(render, silenceThreshold: silenceThreshold,
                                                             tailWindowFrames: frames(forMs: 50, sampleRate: sampleRate))

        XCTAssertEqual(metrics.nonFiniteSampleCount, 0)
        XCTAssertGreaterThan(metrics.peakAbsolute, 0.01,
                             "Bei gewaehlter Atmospheric Voice muss der echte SynthNode-Renderpfad hoerbaren Pegel liefern")
        XCTAssertNotNil(metrics.firstAboveSilenceFrame)
    }

    func test_atmosphericEngine_producesDifferentSignalThanLegacy() throws {
        let sampleRate = 44_100.0
        let totalFrames = frames(forMs: 400, sampleRate: sampleRate)
        let events: [OfflineSynthEvent] = [.noteOn(atFrame: 0, note: referenceNote, velocity: referenceVelocity)]

        var atmospheric = SynthParams.defaults
        atmospheric.voiceEngine = .atmospheric

        let legacyRender = try OfflineSynthHarness.render(sampleRate: sampleRate, totalFrames: totalFrames,
                                                           params: .defaults, events: events)
        let atmosphericRender = try OfflineSynthHarness.render(sampleRate: sampleRate, totalFrames: totalFrames,
                                                                params: atmospheric, events: events)

        XCTAssertNotEqual(legacyRender.left, atmosphericRender.left,
                          "Die beiden Stimmtypen duerfen nicht dasselbe Signal liefern — sonst rendert " +
                          "in Wahrheit weiter die Legacy-Stimme")
    }

    func test_atmosphericEngine_isDeterministic() throws {
        let sampleRate = 44_100.0
        let totalFrames = frames(forMs: 400, sampleRate: sampleRate)
        var params = SynthParams.defaults
        params.voiceEngine = .atmospheric
        params.unisonVoices = 3
        params.unisonDetune = 9.0
        params.unisonSpread = 0.6
        let events: [OfflineSynthEvent] = [
            .noteOn(atFrame: 0, note: 60, velocity: 100),
            .noteOn(atFrame: 0, note: 64, velocity: 100),
            .noteOff(atFrame: frames(forMs: 200, sampleRate: sampleRate), note: 60)
        ]

        let renderA = try OfflineSynthHarness.render(sampleRate: sampleRate, totalFrames: totalFrames,
                                                      params: params, events: events)
        let renderB = try OfflineSynthHarness.render(sampleRate: sampleRate, totalFrames: totalFrames,
                                                      params: params, events: events)

        XCTAssertEqual(renderA.left, renderB.left,
                       "Auch die Atmospheric Voice muss bei identischem Szenario bitgenau identisch rendern " +
                       "(Texturseed haengt deterministisch an activationOrder)")
        XCTAssertEqual(renderA.right, renderB.right)
    }

    // MARK: – 3. On-Off-Symmetrie mit der Atmospheric Voice (Gate 5)

    func test_atmosphericEngine_noteOff_resultsInSilence() throws {
        let sampleRate = 44_100.0
        var params = SynthParams.defaults
        params.voiceEngine = .atmospheric
        // Mapped Amp-Release: SynthParams.releaseMs = 300 ms Default.
        let totalFrames = frames(forMs: 1200, sampleRate: sampleRate)

        let render = try OfflineSynthHarness.render(
            sampleRate: sampleRate,
            totalFrames: totalFrames,
            params: params,
            events: [.noteOn(atFrame: 0, note: referenceNote, velocity: referenceVelocity),
                     .noteOff(atFrame: frames(forMs: 300, sampleRate: sampleRate), note: referenceNote)])
        let metrics = OfflineSynthMetricsCalculator.compute(render, silenceThreshold: silenceThreshold,
                                                             tailWindowFrames: frames(forMs: 100, sampleRate: sampleRate))

        XCTAssertEqual(metrics.nonFiniteSampleCount, 0)
        XCTAssertNotNil(metrics.lastAboveSilenceFrame, "Note sollte ueberhaupt geklungen haben")
        XCTAssertLessThan(metrics.lastAboveSilenceFrame ?? Int.max,
                          totalFrames - frames(forMs: 50, sampleRate: sampleRate),
                          "Nach Release + Sicherheitsfenster darf keine Atmospheric-Stimme mehr klingen")
        XCTAssertLessThan(metrics.tailEnergy, 1e-3)
    }

    func test_atmosphericEngine_allNotesOff_silencesEveryVoice() throws {
        let sampleRate = 44_100.0
        var params = SynthParams.defaults
        params.voiceEngine = .atmospheric
        params.unisonVoices = 2
        params.unisonDetune = 7.0
        let totalFrames = frames(forMs: 1200, sampleRate: sampleRate)

        let render = try OfflineSynthHarness.render(
            sampleRate: sampleRate,
            totalFrames: totalFrames,
            params: params,
            events: [.noteOn(atFrame: 0, note: 60, velocity: 110),
                     .noteOn(atFrame: 0, note: 64, velocity: 110),
                     .noteOn(atFrame: 0, note: 67, velocity: 110),
                     .allNotesOff(atFrame: frames(forMs: 200, sampleRate: sampleRate))])
        let metrics = OfflineSynthMetricsCalculator.compute(render, silenceThreshold: silenceThreshold,
                                                             tailWindowFrames: frames(forMs: 100, sampleRate: sampleRate))

        XCTAssertEqual(metrics.nonFiniteSampleCount, 0)
        XCTAssertLessThan(metrics.lastAboveSilenceFrame ?? Int.max,
                          totalFrames - frames(forMs: 50, sampleRate: sampleRate),
                          "allNotesOff muss auch mit der Atmospheric Voice jede Stimme in Release schicken")
        XCTAssertLessThan(metrics.tailEnergy, 1e-3)
    }

    func test_atmosphericEngine_voiceStealing_staysBoundedAndSilencesAfterAllOff() throws {
        let sampleRate = 44_100.0
        var params = SynthParams.defaults
        params.voiceEngine = .atmospheric
        params.maxVoices = 4
        let totalFrames = frames(forMs: 1400, sampleRate: sampleRate)

        // 12 Noten auf 4 Poolplaetze — jede Zuteilung nach der vierten muss
        // eine bestehende Stimme stehlen.
        var events: [OfflineSynthEvent] = []
        for index in 0..<12 {
            events.append(.noteOn(atFrame: frames(forMs: Double(index) * 15.0, sampleRate: sampleRate),
                                  note: UInt8(50 + index * 2),
                                  velocity: 100))
        }
        events.append(.allNotesOff(atFrame: frames(forMs: 400, sampleRate: sampleRate)))

        let render = try OfflineSynthHarness.render(sampleRate: sampleRate, totalFrames: totalFrames,
                                                     params: params, events: events)
        let metrics = OfflineSynthMetricsCalculator.compute(render, silenceThreshold: silenceThreshold,
                                                             tailWindowFrames: frames(forMs: 100, sampleRate: sampleRate))

        XCTAssertEqual(metrics.nonFiniteSampleCount, 0)
        XCTAssertLessThanOrEqual(metrics.peakAbsolute, 8.0, "Voice-Stealing darf den Pegel nicht entgleisen lassen")
        XCTAssertLessThan(metrics.tailEnergy, 1e-3,
                          "Nach allNotesOff darf keine gestohlene Atmospheric-Stimme haengenbleiben")
    }

    // MARK: – 4. Stimmwechsel im laufenden Betrieb (Gate 6)

    func test_switchingEngineWhileSounding_leavesNoHangingNote() throws {
        for (from, to) in [(SynthVoiceEngine.legacy, SynthVoiceEngine.atmospheric),
                           (SynthVoiceEngine.atmospheric, SynthVoiceEngine.legacy)] {
            let sampleRate = 44_100.0
            let switchFrame = frames(forMs: 200, sampleRate: sampleRate)
            let totalFrames = frames(forMs: 900, sampleRate: sampleRate)

            var start = SynthParams.defaults
            start.voiceEngine = from
            // Langer Release: eine haengende Note wuerde ohne den harten
            // All-Off des Wechsels bis Renderende weiterklingen.
            start.releaseMs = 4000.0
            var switched = start
            switched.voiceEngine = to

            // Bewusst KEIN noteOff: nur der Wechsel selbst darf die drei
            // klingenden Noten beenden.
            let render = try OfflineSynthHarness.render(
                sampleRate: sampleRate,
                totalFrames: totalFrames,
                params: start,
                events: [.noteOn(atFrame: 0, note: 60, velocity: 110),
                         .noteOn(atFrame: 0, note: 64, velocity: 110),
                         .noteOn(atFrame: 0, note: 67, velocity: 110),
                         .paramUpdate(atFrame: switchFrame, params: switched)])
            let metrics = OfflineSynthMetricsCalculator.compute(render, silenceThreshold: silenceThreshold,
                                                                 tailWindowFrames: frames(forMs: 100, sampleRate: sampleRate))

            XCTAssertEqual(metrics.nonFiniteSampleCount, 0, "\(from) → \(to)")
            XCTAssertNotNil(metrics.firstAboveSilenceFrame, "\(from) → \(to): vor dem Wechsel muss es geklungen haben")
            XCTAssertLessThanOrEqual(metrics.lastAboveSilenceFrame ?? Int.max, switchFrame,
                                     "\(from) → \(to): ab dem Wechsel darf keine Stimme mehr klingen — " +
                                     "weder aus dem abgewaehlten noch aus dem neuen Pool")
            XCTAssertLessThan(metrics.tailEnergy, 1e-6, "\(from) → \(to)")
        }
    }

    func test_switchingEngineBackAndForth_doesNotResurrectOldVoices() throws {
        let sampleRate = 44_100.0
        let totalFrames = frames(forMs: 1200, sampleRate: sampleRate)

        var legacy = SynthParams.defaults
        legacy.releaseMs = 4000.0
        var atmospheric = legacy
        atmospheric.voiceEngine = .atmospheric

        // Note klingt in .legacy, Wechsel nach .atmospheric, Rueckwechsel nach
        // .legacy. Die urspruengliche Stimme darf beim Rueckwechsel NICHT
        // wieder auftauchen.
        let render = try OfflineSynthHarness.render(
            sampleRate: sampleRate,
            totalFrames: totalFrames,
            params: legacy,
            events: [.noteOn(atFrame: 0, note: 62, velocity: 120),
                     .paramUpdate(atFrame: frames(forMs: 200, sampleRate: sampleRate), params: atmospheric),
                     .paramUpdate(atFrame: frames(forMs: 400, sampleRate: sampleRate), params: legacy)])
        let metrics = OfflineSynthMetricsCalculator.compute(render, silenceThreshold: silenceThreshold,
                                                             tailWindowFrames: frames(forMs: 700, sampleRate: sampleRate))

        XCTAssertEqual(metrics.nonFiniteSampleCount, 0)
        XCTAssertLessThanOrEqual(metrics.lastAboveSilenceFrame ?? Int.max,
                                 frames(forMs: 200, sampleRate: sampleRate),
                                 "Nach dem Rueckwechsel darf die vor dem ersten Wechsel gestartete Stimme " +
                                 "nicht wieder auftauchen")
        XCTAssertLessThan(metrics.tailEnergy, 1e-6)
    }

    func test_afterSwitchingToAtmospheric_newNotesSoundOnTheNewEngine() throws {
        let sampleRate = 44_100.0
        let switchFrame = frames(forMs: 100, sampleRate: sampleRate)
        let totalFrames = frames(forMs: 800, sampleRate: sampleRate)

        var atmospheric = SynthParams.defaults
        atmospheric.voiceEngine = .atmospheric

        let render = try OfflineSynthHarness.render(
            sampleRate: sampleRate,
            totalFrames: totalFrames,
            params: .defaults,
            events: [.paramUpdate(atFrame: switchFrame, params: atmospheric),
                     .noteOn(atFrame: switchFrame, note: referenceNote, velocity: referenceVelocity)])
        let metrics = OfflineSynthMetricsCalculator.compute(render, silenceThreshold: silenceThreshold,
                                                             tailWindowFrames: 0)

        XCTAssertEqual(metrics.nonFiniteSampleCount, 0)
        XCTAssertGreaterThan(metrics.peakAbsolute, 0.01,
                             "Nach dem Wechsel muss eine neue Note auf der Atmospheric Voice klingen")

        // Gegenprobe: dasselbe Szenario auf der Legacy-Stimme liefert ein
        // anderes Signal — der Wechsel ist also wirklich wirksam geworden.
        let legacyRender = try OfflineSynthHarness.render(
            sampleRate: sampleRate,
            totalFrames: totalFrames,
            params: .defaults,
            events: [.noteOn(atFrame: switchFrame, note: referenceNote, velocity: referenceVelocity)])
        XCTAssertNotEqual(render.left, legacyRender.left)
    }

    // MARK: – 5. Parameter-Mapping

    func test_atmosphericVoiceParameterMapping_carriesAdsrAndFilter() {
        var params = SynthParams.defaults
        params.attackMs = 33.0
        params.decayMs = 222.0
        params.sustain = 0.42
        params.releaseMs = 777.0
        params.filterCutoff = 0.61
        params.filterResonance = 0.23

        let mapped = params.atmosphericVoiceParameters

        XCTAssertEqual(mapped.ampEnvelope.attackMs, 33.0)
        XCTAssertEqual(mapped.ampEnvelope.decayMs, 222.0)
        XCTAssertEqual(mapped.ampEnvelope.sustainLevel, 0.42)
        XCTAssertEqual(mapped.ampEnvelope.releaseMs, 777.0)
        XCTAssertEqual(mapped.filterCutoff, 0.61)
        XCTAssertEqual(mapped.filterResonance, 0.23)

        // Alles Uebrige bleibt bewusst auf den W-01-Defaults.
        XCTAssertEqual(mapped.morphPosition, AudioCoreAtmosphericVoiceParameters.defaults.morphPosition)
        XCTAssertEqual(mapped.outputLevel, AudioCoreAtmosphericVoiceParameters.defaults.outputLevel)
        XCTAssertEqual(mapped.spaceSend, AudioCoreAtmosphericVoiceParameters.defaults.spaceSend)
        XCTAssertEqual(mapped.modEnvelope, AudioCoreAtmosphericVoiceParameters.defaults.modEnvelope)
    }

    // W-03b2 (Runde 071) hat den Produkt-Default gekippt. Dieser Test haelt
    // seitdem die BEIDEN Haelften der Trennung fest, weil sie leicht
    // versehentlich zusammengezogen werden:
    //
    //   – `AppSettings.AudioConfig.voiceEngine` ist der Produkt-Default und
    //     beantwortet, welche Stimme beim Start klingt → `.atmospheric`.
    //   – `SynthParams.defaults.voiceEngine` ist der neutrale Vorkonfigu-
    //     rationswert eines Kanal-Snapshots → bleibt `.legacy`, weil die
    //     Bit-Identitaets-Pruefsumme oben und die Bestandstests daran
    //     haengen (ausfuehrliche Begruendung in `SynthParams.swift`).
    //
    // Kippt jemand die zweite Zeile mit, faellt die Pruefsumme in
    // `test_w03b1_legacyDefaultRender_isBitIdenticalToPreSwitchBaseline` —
    // dieser Test sagt dann, warum.
    func test_defaultVoiceEngine_productDefaultIsAtmospheric_snapshotDefaultStaysLegacy() {
        XCTAssertEqual(AudioConfig().voiceEngine, .atmospheric,
                       "W-03b2 kippt den Produkt-Default auf die Atmospheric Voice")
        XCTAssertEqual(SynthParams.defaults.voiceEngine, .legacy,
                       "Der Snapshot-Default bleibt bewusst `.legacy` — er ist der Anker des " +
                       "Bit-Identitaets-Nachweises, nicht der Produkt-Default")
    }

    // MARK: – Helfer

    private func frames(forMs ms: Double, sampleRate: Double) -> Int {
        Int((ms / 1000.0 * sampleRate).rounded())
    }
}
