import XCTest
@testable import HarmonyEngine3D

// MARK: – DeepSpaceSendTests
//
// W-03c (`.agent_handoff/latest_codex.md`, Runde 072): der Space-Send und die
// gemeinsame `AudioCoreDeepSpace`-Kette am `sharedSpaceSendBus`.
//
// Die Datei deckt die Fragen ab, die der Slice offen laesst:
//   1. Bleibt der Trockenpfad bit-identisch zu `4278cf6`, wenn nichts
//      gesendet wird? (Gate 1, fuer BEIDE Stimmtypen)
//   2. Ist der Raum bei `spaceSend > 0` nachweisbar wirksam? (Gate 2)
//   3. Wirkt der Kanalfader auf den Send (Post-Fader, `postGain`)?
//   4. Klingt der Raum nach `allNotesOff` von selbst aus? (Gate 7)
//
// Alle Renderlaeufe gehen durch den echten `SynthNode`-Rendercallback und —
// wo verlangt — durch den echten `DeepSpaceReturnNode` (`OfflineSynthHarness`
// mit `withSpaceSend: true`).

final class DeepSpaceSendTests: XCTestCase {

    private let silenceThreshold: Float = 1e-4

    /// Bestandsdefaults mit ausdruecklich gewaehlter Atmospheric Voice.
    private var atmosphericParams: SynthParams {
        var params = SynthParams.defaults
        params.voiceEngine = .atmospheric
        return params
    }

    private var legacyParams: SynthParams {
        var params = SynthParams.defaults
        params.voiceEngine = .legacy
        return params
    }

    // MARK: – Gate 1a: der Trockenpfad selbst hat sich nicht bewegt

    // Kernnachweis des Slices. Die Referenz-Pruefsumme stammt aus dem Stand
    // `4278cf6`: die Szenariofolge unten wurde angelegt und ausgefuehrt, BEVOR
    // eine Zeile Produktcode dieses Slices geschrieben war, und zweimal
    // reproduziert.
    //
    // Abgesichert wird genau die Umbaustelle, die W-03c am Trockenpfad
    // vornimmt: die Atmospheric-Stimmen rendern jetzt ueber einen
    // Zwischenpuffer, damit ihr Ausgang pro Stimme mit `spaceSendLevel`
    // gewichtet in den Send-Bus gehen kann. Diese Umleitung darf am
    // Summensignal kein einziges Bit veraendern.
    //
    // Verglichen werden rohe `Float.bitPattern`-Werte, nicht Metriken —
    // dieselbe Begruendung wie in `SynthVoiceEngineTests`: eine Toleranz
    // wuerde genau die Klasse von Abweichung durchlassen, die dieses Gate
    // ausschliessen soll.
    func test_w03c_atmosphericDryRender_isBitIdenticalToPreSendBaseline() throws {
        let checksum = try DeepSpaceSendTests.atmosphericScenarioChecksum()
        print("[W-03c] Atmospheric-Trockenpfad-Pruefsumme: 0x\(String(checksum, radix: 16))")

        XCTAssertEqual(checksum, 0xd6fe_9a8b_9377_4ce7,
                       "Der Atmospheric-Trockenpfad muss bit-identisch zu `4278cf6` bleiben. Weicht dieser " +
                       "Wert ab, hat der Umweg ueber den Zwischenpuffer das Summensignal veraendert — " +
                       "melden, nicht anpassen.")
    }

    /// Szenariofolge des Bit-Identitaets-Nachweises fuer den Atmospheric-
    /// Trockenpfad. Bewusst ohne jede Referenz auf den Space-Send, damit
    /// derselbe Code unveraendert gegen den Stand `4278cf6` uebersetzt werden
    /// kann.
    ///
    /// Deckt alle Pfade ab, die W-03c am Renderpfad anfasst: einfache
    /// Stimmzuteilung, Unison, Voice-Stealing, Release, All-Off, den
    /// Live-Parameterpfad und alle drei Sample-Raten (44,1 / 48 / 96 kHz).
    static func atmosphericScenarioChecksum() throws -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325

        func absorb(_ render: OfflineRenderResult) {
            for value in render.left  { hash = DeepSpaceSendTests.fnv1a(hash, value.bitPattern) }
            for value in render.right { hash = DeepSpaceSendTests.fnv1a(hash, value.bitPattern) }
            hash = DeepSpaceSendTests.fnv1a(hash, UInt32(truncatingIfNeeded: render.frameCount))
        }

        func frames(_ ms: Double, _ sampleRate: Double) -> Int { Int((ms / 1000.0 * sampleRate).rounded()) }

        var base = SynthParams.defaults
        base.voiceEngine = .atmospheric

        for sampleRate in [44_100.0, 48_000.0, 96_000.0] {

            // A) Einzelne Note, gehalten und released.
            absorb(try OfflineSynthHarness.render(
                sampleRate: sampleRate,
                totalFrames: frames(800, sampleRate),
                params: base,
                events: [.noteOn(atFrame: 0, note: 60, velocity: 100),
                         .noteOff(atFrame: frames(300, sampleRate), note: 60)]))

            // B) Unison mit Spread — mehrere Stimmen gleichzeitig, jede mit
            //    eigener Pan-/Detune-Position und eigenem Texturseed.
            var unison = base
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
            //    Voice-Stealing, also den Fall, in dem eine Stimme mitten im
            //    Ton neu konfiguriert wird.
            var small = base
            small.maxVoices = 4
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
            //    mitten im gehaltenen Ton.
            var live = base
            live.filterCutoff = 0.8
            live.filterResonance = 0.2
            var swept = live
            swept.filterCutoff = 0.25
            swept.filterResonance = 0.75
            swept.sustain = 0.30
            absorb(try OfflineSynthHarness.render(
                sampleRate: sampleRate,
                totalFrames: frames(600, sampleRate),
                params: live,
                events: [.noteOn(atFrame: 0, note: 57, velocity: 110),
                         .paramUpdate(atFrame: frames(150, sampleRate), params: swept),
                         .noteOff(atFrame: frames(400, sampleRate), note: 57)]))
        }

        return hash
    }

    // MARK: – Gate 1b: angeschlossener Raum bei spaceSend = 0 ist bitgenau neutral

    /// Der haertere Teil von Gate 1: nicht nur der Trockenpfad allein, sondern
    /// der VOLLSTAENDIG verdrahtete Graph — Sammelbus, Raumkette und
    /// Return-Knoten am Mixer — muss bei `spaceSend = 0` dasselbe Signal
    /// liefern wie der Graph ohne Raum. Das ist der Beleg, dass der Raum rein
    /// additiv ist und am Trockensignal nichts verschiebt.
    func test_spaceSendZero_withRoomAttached_isBitIdenticalToRoomAbsent() throws {
        for (label, base) in [("atmospheric", atmosphericParams), ("legacy", legacyParams)] {
            for sampleRate in [44_100.0, 48_000.0, 96_000.0] {
                var params = base
                params.spaceSend = 0.0

                let totalFrames = frames(forMs: 700, sampleRate: sampleRate)
                let events: [OfflineSynthEvent] = [
                    .noteOn(atFrame: 0, note: 60, velocity: 100),
                    .noteOn(atFrame: frames(forMs: 40, sampleRate: sampleRate), note: 67, velocity: 110),
                    .noteOff(atFrame: frames(forMs: 300, sampleRate: sampleRate), note: 60),
                    .allNotesOff(atFrame: frames(forMs: 400, sampleRate: sampleRate))
                ]

                let withoutRoom = try OfflineSynthHarness.render(
                    sampleRate: sampleRate, totalFrames: totalFrames, params: params, events: events)
                let withRoom = try OfflineSynthHarness.render(
                    sampleRate: sampleRate, totalFrames: totalFrames, params: params, events: events,
                    withSpaceSend: true)

                assertBitIdentical(withRoom, withoutRoom,
                                   label: "\(label) @ \(Int(sampleRate)) Hz, spaceSend = 0")
            }
        }
    }

    /// Die Legacy-Stimme hat kein Space-Send-Ziel und speist den Raum deshalb
    /// auch dann nicht, wenn der Sendpegel voll aufgedreht ist. Kein
    /// Nebeneffekt, sondern die dokumentierte Eigenschaft des Pfads — dieser
    /// Test haelt sie fest, damit sie nicht unbemerkt kippt.
    func test_legacyVoice_neverFeedsTheRoom_evenAtFullSend() throws {
        let sampleRate = 48_000.0
        var params = legacyParams
        params.spaceSend = 1.0
        params.spaceSendChannelGain = 1.0

        let totalFrames = frames(forMs: 900, sampleRate: sampleRate)
        let events: [OfflineSynthEvent] = [
            .noteOn(atFrame: 0, note: 60, velocity: 120),
            .noteOff(atFrame: frames(forMs: 300, sampleRate: sampleRate), note: 60)
        ]

        let withoutRoom = try OfflineSynthHarness.render(
            sampleRate: sampleRate, totalFrames: totalFrames, params: params, events: events)
        let withRoom = try OfflineSynthHarness.render(
            sampleRate: sampleRate, totalFrames: totalFrames, params: params, events: events,
            withSpaceSend: true)

        assertBitIdentical(withRoom, withoutRoom, label: "legacy bei spaceSend = 1.0")
    }

    /// Post-Fader-Nachweis: steht der Kanalfader auf 0, geht auch nichts in
    /// den Raum. Das ist die Umsetzung von `AudioGraphSendTopology`
    /// `postGain` auf dem Software-Sendweg (siehe `SpaceSendBus`).
    func test_channelFaderAtZero_silencesTheSend() throws {
        let sampleRate = 48_000.0
        var params = atmosphericParams
        params.spaceSend = 1.0
        params.spaceSendChannelGain = 0.0

        let totalFrames = frames(forMs: 900, sampleRate: sampleRate)
        let events: [OfflineSynthEvent] = [
            .noteOn(atFrame: 0, note: 60, velocity: 120),
            .noteOff(atFrame: frames(forMs: 300, sampleRate: sampleRate), note: 60)
        ]

        let withoutRoom = try OfflineSynthHarness.render(
            sampleRate: sampleRate, totalFrames: totalFrames, params: params, events: events)
        let withRoom = try OfflineSynthHarness.render(
            sampleRate: sampleRate, totalFrames: totalFrames, params: params, events: events,
            withSpaceSend: true)

        assertBitIdentical(withRoom, withoutRoom, label: "Kanalfader 0 bei spaceSend = 1.0")
    }

    // MARK: – Gate 2: bei spaceSend > 0 ist der Raum nachweisbar wirksam

    /// Der Raum muss zweierlei belegen: dass er ueberhaupt Signal beitraegt,
    /// und dass er dort noch traegt, wo der Trockenpfad laengst verstummt ist.
    ///
    /// Gemessen wird der Raumanteil als DIFFERENZSIGNAL `wet − dry`. Das ist
    /// exakt der Beitrag der Kette und nicht durch das Trockensignal
    /// verwaessert — moeglich, weil beide Laeufe bitgenau denselben
    /// Trockenpfad haben (Gate 1).
    ///
    /// Die Schranken sind bewusst als VERHAELTNIS formuliert, nicht als
    /// absolute Pegel: sie sollen "der Raum ist wirksam und bleibt
    /// untergeordnet" pruefen und nicht den heutigen Sendpegel einfrieren.
    func test_spaceSendAtProductLevel_producesAudibleSubordinateRoom() throws {
        let sampleRate = 48_000.0
        var params = atmosphericParams
        params.spaceSend = AudioEngine.provisionalSpaceSendLevel

        // Note 300 ms halten, dann Release (300 ms) — ab ca. 700 ms ist der
        // Trockenpfad still. Der Tail der Kette (RT60 rund 4 s bei
        // decay = 0,5) traegt deutlich laenger.
        let totalFrames = frames(forMs: 1500, sampleRate: sampleRate)
        let events: [OfflineSynthEvent] = [
            .noteOn(atFrame: 0, note: 60, velocity: 110),
            .noteOff(atFrame: frames(forMs: 300, sampleRate: sampleRate), note: 60)
        ]

        let dry = try OfflineSynthHarness.render(
            sampleRate: sampleRate, totalFrames: totalFrames, params: params, events: events)
        let wet = try OfflineSynthHarness.render(
            sampleRate: sampleRate, totalFrames: totalFrames, params: params, events: events,
            withSpaceSend: true)

        XCTAssertEqual(nonFiniteCount(wet), 0)

        let roomRMS = differenceRMS(wet, dry, from: 0)
        let dryRMS  = rms(dry, from: 0)
        let ratioDb = 20.0 * log10(roomRMS / dryRMS)
        print(String(format: "[W-03c GATE2] Raumanteil %.1f dB unter dem Trockensignal (RMS %.3e gegen %.3e)",
                     ratioDb, roomRMS, dryRMS))

        XCTAssertGreaterThan(ratioDb, -40.0,
                             "Der Raum muss hoerbar sein — mehr als 40 dB unter dem Trockensignal waere er nicht")
        XCTAssertLessThan(ratioDb, -6.0,
                          "Der Raum muss dem Trockensignal untergeordnet bleiben")

        // Zweite Haelfte der Aussage: nach dem Verstummen der Stimme steht
        // noch eine Fahne.
        let windowStart = frames(forMs: 1000, sampleRate: sampleRate)
        let dryTail = rms(dry, from: windowStart)
        let wetTail = rms(wet, from: windowStart)
        print(String(format: "[W-03c GATE2] Fenster ab 1000 ms — trocken RMS %.3e, mit Raum RMS %.3e",
                     dryTail, wetTail))

        XCTAssertLessThan(dryTail, silenceThreshold,
                          "Ohne Raum muss der Trockenpfad in diesem Fenster praktisch still sein")
        XCTAssertGreaterThan(wetTail, dryTail * 100.0 + 1e-5,
                             "Mit Raum muss dort eine Hallfahne stehen, wo der Trockenpfad nichts mehr liefert")
    }

    /// Der Sendpegel wirkt monoton: mehr Send heisst mehr Raumenergie. Das
    /// belegt zugleich, dass der pro Stimme exponierte `spaceSendLevel`
    /// tatsaechlich der wirksame Faktor ist und nicht ein fester Wert
    /// irgendwo im Sendweg.
    func test_higherSpaceSend_producesMoreRoomEnergy() throws {
        let sampleRate = 48_000.0
        let totalFrames = frames(forMs: 1500, sampleRate: sampleRate)
        let events: [OfflineSynthEvent] = [
            .noteOn(atFrame: 0, note: 60, velocity: 110),
            .noteOff(atFrame: frames(forMs: 300, sampleRate: sampleRate), note: 60)
        ]
        let windowStart = frames(forMs: 1000, sampleRate: sampleRate)

        var quiet = atmosphericParams
        quiet.spaceSend = 0.1
        var loud = atmosphericParams
        loud.spaceSend = 0.8

        let quietRender = try OfflineSynthHarness.render(
            sampleRate: sampleRate, totalFrames: totalFrames, params: quiet, events: events,
            withSpaceSend: true)
        let loudRender = try OfflineSynthHarness.render(
            sampleRate: sampleRate, totalFrames: totalFrames, params: loud, events: events,
            withSpaceSend: true)

        let quietTail = rms(quietRender, from: windowStart)
        let loudTail = rms(loudRender, from: windowStart)
        print(String(format: "[W-03c GATE2] Tail-RMS bei send 0,1: %.3e — bei send 0,8: %.3e (Faktor %.2f)",
                     quietTail, loudTail, loudTail / max(quietTail, .leastNormalMagnitude)))

        XCTAssertGreaterThan(loudTail, quietTail * 4.0,
                             "Der achtfache Sendpegel muss sich in der Hallfahne deutlich niederschlagen")
    }

    // MARK: – Gate 7: On-Off-Symmetrie, der Raum klingt von selbst aus

    /// Nach `allNotesOff` darf nichts haengenbleiben — auch der Raum nicht.
    /// Er wird bewusst NICHT hart zurueckgesetzt (das waere ein hoerbarer
    /// Schnitt, siehe `DeepSpaceReturnNode`), sondern klingt aus. Dieser Test
    /// haelt fest, dass er das innerhalb seiner Abklingzeit auch wirklich tut.
    func test_roomDecaysToSilence_afterAllNotesOff() throws {
        let sampleRate = 48_000.0
        var params = atmosphericParams
        params.spaceSend = 1.0

        // RT60 rund 4,2 s bei `decay = 0,5`; 12 s Renderlaenge liegt weit
        // dahinter. Gemessen wird das letzte 200-ms-Fenster.
        let totalFrames = frames(forMs: 12_000, sampleRate: sampleRate)
        let events: [OfflineSynthEvent] = [
            .noteOn(atFrame: 0, note: 60, velocity: 127),
            .noteOn(atFrame: 0, note: 64, velocity: 127),
            .noteOn(atFrame: 0, note: 67, velocity: 127),
            .allNotesOff(atFrame: frames(forMs: 300, sampleRate: sampleRate))
        ]

        let render = try OfflineSynthHarness.render(
            sampleRate: sampleRate, totalFrames: totalFrames, params: params, events: events,
            withSpaceSend: true)

        let tailStart = totalFrames - frames(forMs: 200, sampleRate: sampleRate)
        let tailPeak = peak(render, from: tailStart)
        print(String(format: "[W-03c GATE7] Peak im letzten 200-ms-Fenster nach allNotesOff: %.3e", tailPeak))

        XCTAssertEqual(nonFiniteCount(render), 0)
        XCTAssertLessThan(tailPeak, silenceThreshold,
                          "Der Raum muss nach allNotesOff innerhalb seiner Abklingzeit unter die " +
                          "Stille-Schwelle fallen — sonst bliebe eine Fahne stehen")
    }

    // MARK: – Determinismus und Sample-Raten mit Raum

    func test_renderWithRoom_isDeterministic() throws {
        let sampleRate = 48_000.0
        var params = atmosphericParams
        params.spaceSend = 0.5
        let totalFrames = frames(forMs: 900, sampleRate: sampleRate)
        let events: [OfflineSynthEvent] = [
            .noteOn(atFrame: 0, note: 60, velocity: 100),
            .noteOff(atFrame: frames(forMs: 300, sampleRate: sampleRate), note: 60)
        ]

        let renderA = try OfflineSynthHarness.render(
            sampleRate: sampleRate, totalFrames: totalFrames, params: params, events: events,
            withSpaceSend: true)
        let renderB = try OfflineSynthHarness.render(
            sampleRate: sampleRate, totalFrames: totalFrames, params: params, events: events,
            withSpaceSend: true)

        assertBitIdentical(renderA, renderB, label: "zwei identische Renderlaeufe mit Raum")
    }

    /// Der Raum bei allen drei real vorkommenden Betriebspunkten — inklusive
    /// der 96 kHz, die die Maschine tatsaechlich faehrt.
    func test_allThreeSampleRates_withRoom_produceFiniteOutput() throws {
        for sampleRate in [44_100.0, 48_000.0, 96_000.0] {
            var params = atmosphericParams
            params.spaceSend = 0.5

            let totalFrames = frames(forMs: 1200, sampleRate: sampleRate)
            let events: [OfflineSynthEvent] = [
                .noteOn(atFrame: 0, note: 60, velocity: 110),
                .noteOff(atFrame: frames(forMs: 300, sampleRate: sampleRate), note: 60)
            ]

            let render = try OfflineSynthHarness.render(
                sampleRate: sampleRate, totalFrames: totalFrames, params: params, events: events,
                withSpaceSend: true)

            XCTAssertEqual(render.frameCount, totalFrames, "sampleRate=\(sampleRate)")
            XCTAssertEqual(nonFiniteCount(render), 0, "sampleRate=\(sampleRate)")

            let windowStart = frames(forMs: 900, sampleRate: sampleRate)
            XCTAssertGreaterThan(rms(render, from: windowStart), silenceThreshold,
                                 "sampleRate=\(sampleRate): der Raum muss auch hier tragen")
            XCTAssertLessThan(peak(render, from: 0), 1.0,
                              "sampleRate=\(sampleRate): Trocken plus Raum darf den Vollausschlag nicht erreichen")
        }
    }

    /// Parametergrenzen mit angeschlossenem Raum: der Sendweg darf auch bei
    /// vollem Pegel und dichtem Satz keine nicht-endlichen Samples erzeugen.
    func test_extremeSendAndDensity_produceNoNaNOrInfinity() throws {
        let sampleRate = 44_100.0
        var params = atmosphericParams
        params.spaceSend = 1.0
        params.unisonVoices = 4
        params.unisonDetune = 100.0
        params.unisonSpread = 1.0
        params.maxVoices = 8

        let totalFrames = frames(forMs: 2000, sampleRate: sampleRate)
        var events: [OfflineSynthEvent] = []
        for index in 0..<6 {
            events.append(.noteOn(atFrame: frames(forMs: Double(index) * 30.0, sampleRate: sampleRate),
                                  note: UInt8(48 + index * 5), velocity: 127))
        }
        events.append(.allNotesOff(atFrame: frames(forMs: 600, sampleRate: sampleRate)))

        let render = try OfflineSynthHarness.render(
            sampleRate: sampleRate, totalFrames: totalFrames, params: params, events: events,
            withSpaceSend: true)

        print(String(format: "[W-03c DICHTE] Peak trocken+Raum bei vollem Send: %.4f", peak(render, from: 0)))
        XCTAssertEqual(nonFiniteCount(render), 0)
    }

    // MARK: – Helfer

    private func frames(forMs ms: Double, sampleRate: Double) -> Int {
        Int((ms / 1000.0 * sampleRate).rounded())
    }

    private func assertBitIdentical(_ lhs: OfflineRenderResult, _ rhs: OfflineRenderResult,
                                     label: String,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.frameCount, rhs.frameCount, "\(label): Laenge", file: file, line: line)
        let count = min(lhs.frameCount, rhs.frameCount)
        var firstDifference = -1
        for i in 0..<count where lhs.left[i].bitPattern != rhs.left[i].bitPattern
                                  || lhs.right[i].bitPattern != rhs.right[i].bitPattern {
            firstDifference = i
            break
        }
        XCTAssertEqual(firstDifference, -1,
                       "\(label): erstes abweichendes Sample bei Index \(firstDifference) — " +
                       "der Raum muss rein additiv sein und das Trockensignal bitgenau unberuehrt lassen",
                       file: file, line: line)
    }

    private func rms(_ render: OfflineRenderResult, from startFrame: Int) -> Float {
        guard startFrame < render.frameCount else { return 0 }
        var sum: Double = 0
        for i in startFrame..<render.frameCount {
            sum += Double(render.left[i]) * Double(render.left[i])
            sum += Double(render.right[i]) * Double(render.right[i])
        }
        let count = Double((render.frameCount - startFrame) * 2)
        return Float((sum / count).squareRoot())
    }

    /// RMS des Differenzsignals zweier Renderlaeufe gleicher Laenge — bei
    /// bitgleichem Trockenpfad exakt der Beitrag des Raums.
    private func differenceRMS(_ lhs: OfflineRenderResult, _ rhs: OfflineRenderResult,
                                from startFrame: Int) -> Float {
        let count = min(lhs.frameCount, rhs.frameCount)
        guard startFrame < count else { return 0 }
        var sum: Double = 0
        for i in startFrame..<count {
            let dl = Double(lhs.left[i]  - rhs.left[i])
            let dr = Double(lhs.right[i] - rhs.right[i])
            sum += dl * dl + dr * dr
        }
        return Float((sum / Double((count - startFrame) * 2)).squareRoot())
    }

    private func peak(_ render: OfflineRenderResult, from startFrame: Int) -> Float {
        guard startFrame < render.frameCount else { return 0 }
        var result: Float = 0
        for i in startFrame..<render.frameCount {
            result = max(result, abs(render.left[i]), abs(render.right[i]))
        }
        return result
    }

    private func nonFiniteCount(_ render: OfflineRenderResult) -> Int {
        var count = 0
        for value in render.left  where !value.isFinite { count += 1 }
        for value in render.right where !value.isFinite { count += 1 }
        return count
    }

    private static func fnv1a(_ hash: UInt64, _ value: UInt32) -> UInt64 {
        var result = hash
        for shift in stride(from: 0, through: 24, by: 8) {
            result ^= UInt64(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
            result = result &* 0x1000_0000_01b3
        }
        return result
    }
}
