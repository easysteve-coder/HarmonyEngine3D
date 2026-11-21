import XCTest
import HarmonyAudioCore
@testable import HarmonyEngine3D

// MARK: – MIDIMacroMappingTests
//
// W-05 (`.agent_handoff/latest_codex.md`, Runde 074), Teile 2 und 3.
//
//  A. Zuordnung: Defaults, Eindeutigkeit, unbelegte Nummern, Grenzen
//  B. Drossel: Koaleszieren, Mindestpause, Deduplizierung
//  C. DIE MESSUNG: wie viele paramUpdates entstehen bei 127 CC-Werten in
//     einer Sekunde, mit und ohne Drossel — die Zahl, die Teil 3 des
//     Handoffs verlangt
//
// Die Zeit ist durchgehend simuliert, nicht gemessen: der Scheduler der
// Drossel ist injizierbar, und die Tests fahren eine virtuelle Uhr. Kein
// `sleep`, kein Timing-Flake, und die Zahlen sind exakt reproduzierbar
// statt maschinenabhaengig.

final class MIDIMacroMappingTests: XCTestCase {

    // MARK: – Virtuelle Uhr
    //
    // Nimmt die vom Coalescer eingeplanten Arbeiten entgegen und fuehrt sie
    // aus, sobald die simulierte Zeit ihre Faelligkeit erreicht.
    private final class VirtualClock: @unchecked Sendable {
        private let lock = NSLock()
        private var nowMs = 0
        private var scheduled: [(dueMs: Int, work: () -> Void)] = []

        var schedule: MIDIMacroCoalescer.Scheduler {
            { [self] milliseconds, work in
                lock.lock()
                scheduled.append((nowMs + milliseconds, work))
                lock.unlock()
            }
        }

        /// Schiebt die Uhr auf `targetMs` und fuehrt alles aus, was dabei
        /// faellig wird — in Faelligkeitsreihenfolge.
        func advance(to targetMs: Int) {
            while true {
                lock.lock()
                guard let index = scheduled.indices
                    .filter({ scheduled[$0].dueMs <= targetMs })
                    .min(by: { scheduled[$0].dueMs < scheduled[$1].dueMs })
                else {
                    nowMs = targetMs
                    lock.unlock()
                    return
                }
                let entry = scheduled.remove(at: index)
                nowMs = entry.dueMs
                lock.unlock()
                entry.work()
            }
        }
    }

    private func makeCoalescer(mapping: MIDIMacroCCMapping = .defaults,
                               clock: VirtualClock,
                               sink: @escaping @Sendable (AudioCoreMacroValues) -> Void)
        -> MIDIMacroCoalescer {
        MIDIMacroCoalescer(mapping: mapping, schedule: clock.schedule, sink: sink)
    }

    /// Sammelt die weitergereichten Staende threadsicher ein.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [AudioCoreMacroValues] = []
        func record(_ value: AudioCoreMacroValues) {
            lock.lock(); values.append(value); lock.unlock()
        }
        var all: [AudioCoreMacroValues] {
            lock.lock(); defer { lock.unlock() }
            return values
        }
        var count: Int { all.count }
    }

    // MARK: – A. Zuordnung

    func test_defaultMapping_usesConventionalControllerNumbers() {
        let mapping = MIDIMacroCCMapping.defaults
        XCTAssertEqual(mapping[.motion], 77)
        XCTAssertEqual(mapping[.color],  74)
        XCTAssertEqual(mapping[.space],  91)
        XCTAssertEqual(mapping[.focus],  71)
    }

    func test_reverseLookup_findsTheAssignedMacro() {
        let mapping = MIDIMacroCCMapping.defaults
        XCTAssertEqual(mapping.macro(forController: 74), .color)
        XCTAssertEqual(mapping.macro(forController: 91), .space)
        XCTAssertNil(mapping.macro(forController: 1), "Modulationsrad darf kein Makro treffen")
    }

    /// Doppelbelegung ist ausgeschlossen: die Nummer wechselt den Besitzer,
    /// das andere Makro steht danach auf "nicht zugeordnet".
    func test_assigningAnAlreadyUsedController_clearsTheOtherMacro() {
        var mapping = MIDIMacroCCMapping.defaults
        mapping.assign(controller: 74, to: .motion)

        XCTAssertEqual(mapping[.motion], 74)
        XCTAssertNil(mapping[.color], "die Nummer darf nicht zwei Makros gehoeren")
        XCTAssertEqual(mapping.macro(forController: 74), .motion)
    }

    func test_assigningNil_clearsTheMacroOnly() {
        var mapping = MIDIMacroCCMapping.defaults
        mapping.assign(controller: nil, to: .space)

        XCTAssertNil(mapping[.space])
        XCTAssertEqual(mapping[.color], 74, "die uebrigen Zuordnungen bleiben")
        XCTAssertNil(mapping.macro(forController: 91))
    }

    /// Channel-Mode-Nummern kommen im Router nie als `.controlChange` an; eine
    /// Zuweisung dorthin waere ein garantiert toter Regler.
    func test_channelModeControllerNumbers_cannotBeAssigned() {
        var mapping = MIDIMacroCCMapping.none
        for controller in UInt8(120)...127 {
            mapping.assign(controller: controller, to: .motion)
            XCTAssertNil(mapping[.motion], "CC \(controller) darf nicht zuweisbar sein")
        }
        mapping.assign(controller: MIDIMacroCCMapping.maxAssignableController, to: .motion)
        XCTAssertEqual(mapping[.motion], 119, "119 ist die letzte gueltige Nummer")
    }

    /// Ein von Hand veraenderter Persistenzstand koennte zwei gleiche Nummern
    /// enthalten. Der Initialisierer loest das deterministisch auf.
    func test_initWithDuplicateNumbers_resolvesDeterministically() {
        let mapping = MIDIMacroCCMapping(motion: 74, color: 74, space: 91, focus: 74)
        XCTAssertEqual(mapping[.motion], 74, "die erste in fester Reihenfolge gewinnt")
        XCTAssertNil(mapping[.color])
        XCTAssertEqual(mapping[.space], 91)
        XCTAssertNil(mapping[.focus])
    }

    // MARK: – A2. Persistenz (Gate 4)
    //
    // Geprueft wird die Kodierungsregel, nicht der `UserDefaults`-Zugriff:
    // `AppSettings.shared` haengt an `UserDefaults.standard` und wird in
    // diesem Projekt aus Tests bewusst nicht mutiert (Debounce-Save wuerde
    // reale Nutzerdaten schreiben). Der Zugriff selbst laeuft ueber dieselben
    // `i(...)`/`ud.set`-Helfer wie jede andere Einstellung; dass die Zuordnung
    // einen echten Neustart ueberlebt, gehoert damit in den manuellen Test.

    func test_persistenceEncoding_roundTripsEveryValidNumberAndUnassigned() {
        for controller in UInt8(0)...MIDIMacroCCMapping.maxAssignableController {
            let stored = MIDIMacroCCMapping.storedValue(for: controller)
            XCTAssertEqual(MIDIMacroCCMapping.controller(fromStored: stored), controller)
        }
        XCTAssertEqual(MIDIMacroCCMapping.storedValue(for: nil),
                       MIDIMacroCCMapping.unassignedStoredValue)
        XCTAssertNil(MIDIMacroCCMapping.controller(
            fromStored: MIDIMacroCCMapping.unassignedStoredValue))
    }

    func test_persistenceEncoding_rejectsOutOfRangeStoredValues() {
        for stored in [-999, -2, 120, 127, 128, 9_999] {
            XCTAssertNil(MIDIMacroCCMapping.controller(fromStored: stored),
                         "gespeicherter Wert \(stored) darf keine Zuordnung ergeben")
        }
    }

    /// Der vollstaendige Weg Wert -> Persistenzform -> Wert, so wie
    /// `AppSettings.load()`/`save()` ihn fahren.
    func test_persistence_mappingSurvivesAStoreAndLoadCycle() {
        var original = MIDIMacroCCMapping.defaults
        original.assign(controller: 20, to: .motion)
        original.assign(controller: nil, to: .focus)

        let ids: [AudioCoreMacroID] = [.motion, .color, .space, .focus]
        let stored = ids.map { MIDIMacroCCMapping.storedValue(for: original[$0]) }
        let restored = MIDIMacroCCMapping(
            motion: MIDIMacroCCMapping.controller(fromStored: stored[0]),
            color:  MIDIMacroCCMapping.controller(fromStored: stored[1]),
            space:  MIDIMacroCCMapping.controller(fromStored: stored[2]),
            focus:  MIDIMacroCCMapping.controller(fromStored: stored[3])
        )

        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored[.motion], 20)
        XCTAssertNil(restored[.focus])
    }

    // MARK: – B. Drossel

    func test_unmappedController_doesNothingAndIsNoError() {
        let clock = VirtualClock()
        let recorder = Recorder()
        let coalescer = makeCoalescer(clock: clock) { recorder.record($0) }

        // CC 1 (Modulationsrad) und CC 64 (Sustain) sind nicht zugeordnet.
        coalescer.handle(MIDIInputControlChange(channel: 0, controller: 1, value: 100))
        coalescer.handle(MIDIInputControlChange(channel: 0, controller: 64, value: 127))
        clock.advance(to: 1_000)

        XCTAssertEqual(recorder.count, 0, "eine unbelegte Nummer darf nichts ausloesen")
        XCTAssertEqual(coalescer.emittedUpdateCount, 0)
        XCTAssertEqual(coalescer.ignoredChangeCount, 2)
        XCTAssertEqual(coalescer.currentValues, .defaults, "und keinen Wert veraendern")
    }

    func test_sevenBitValue_isMappedToUnitRange() {
        let clock = VirtualClock()
        let recorder = Recorder()
        let coalescer = makeCoalescer(clock: clock) { recorder.record($0) }

        coalescer.handle(MIDIInputControlChange(channel: 0, controller: 74, value: 127))
        clock.advance(to: 100)
        XCTAssertEqual(recorder.all.last?.color, 1.0)

        coalescer.handle(MIDIInputControlChange(channel: 0, controller: 74, value: 0))
        clock.advance(to: 200)
        XCTAssertEqual(recorder.all.last?.color, 0.0)
    }

    /// Der Kanal wird bewusst ignoriert — die Makros sind global.
    func test_controlChangeOnAnyChannel_reachesTheMacro() {
        let clock = VirtualClock()
        let recorder = Recorder()
        let coalescer = makeCoalescer(clock: clock) { recorder.record($0) }

        coalescer.handle(MIDIInputControlChange(channel: 11, controller: 91, value: 64))
        clock.advance(to: 100)

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(recorder.all.last?.space ?? 0, 64.0 / 127.0, accuracy: 1e-6)
    }

    /// Mehrere Werte innerhalb einer Pause ergeben genau eine Ausgabe, und
    /// zwar mit dem LETZTEN Wert.
    func test_manyValuesWithinOneInterval_produceOneUpdateWithTheLastValue() {
        let clock = VirtualClock()
        let recorder = Recorder()
        let coalescer = makeCoalescer(clock: clock) { recorder.record($0) }

        for value in UInt8(0)...50 {
            coalescer.handle(MIDIInputControlChange(channel: 0, controller: 74, value: value))
        }
        clock.advance(to: MIDIMacroCoalescer.flushIntervalMs)

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(recorder.all.last?.color ?? 0, 50.0 / 127.0, accuracy: 1e-6)
    }

    /// Vier gleichzeitig bewegte Regler landen in EINER Ausgabe, nicht in vier.
    func test_fourKnobsWithinOneInterval_produceASingleCombinedUpdate() {
        let clock = VirtualClock()
        let recorder = Recorder()
        let coalescer = makeCoalescer(clock: clock) { recorder.record($0) }

        coalescer.handle(MIDIInputControlChange(channel: 0, controller: 77, value: 127))
        coalescer.handle(MIDIInputControlChange(channel: 0, controller: 74, value: 127))
        coalescer.handle(MIDIInputControlChange(channel: 0, controller: 91, value: 127))
        coalescer.handle(MIDIInputControlChange(channel: 0, controller: 71, value: 127))
        clock.advance(to: MIDIMacroCoalescer.flushIntervalMs)

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(recorder.all.last, AudioCoreMacroValues(motion: 1, color: 1, space: 1, focus: 1))
    }

    /// Ein zitterndes Poti, das denselben Wert wiederholt: keine Ausgabe.
    func test_repeatedIdenticalValue_producesNoFurtherUpdate() {
        let clock = VirtualClock()
        let recorder = Recorder()
        let coalescer = makeCoalescer(clock: clock) { recorder.record($0) }

        for tick in 0..<50 {
            coalescer.handle(MIDIInputControlChange(channel: 0, controller: 74, value: 64))
            clock.advance(to: (tick + 1) * MIDIMacroCoalescer.flushIntervalMs)
        }

        XCTAssertEqual(recorder.count, 1, "nur der erste Stand ist neu")
        XCTAssertEqual(coalescer.receivedChangeCount, 50)
    }

    /// Im Leerlauf laeuft kein Takt: ohne CC gibt es keine eingeplante Arbeit
    /// und keine Ausgabe.
    func test_withoutAnyControlChange_nothingIsScheduledAndNothingIsEmitted() {
        let clock = VirtualClock()
        let recorder = Recorder()
        let coalescer = makeCoalescer(clock: clock) { recorder.record($0) }

        clock.advance(to: 10_000)

        XCTAssertEqual(recorder.count, 0)
        XCTAssertEqual(coalescer.emittedUpdateCount, 0)
    }

    /// Eine geaenderte Zuordnung darf keinen Makrowert zuruecksetzen — das
    /// waere eine hoerbare Klangaenderung als Nebenwirkung einer Einstellung.
    func test_changingTheMapping_keepsReachedMacroValues() {
        let clock = VirtualClock()
        let recorder = Recorder()
        let coalescer = makeCoalescer(clock: clock) { recorder.record($0) }

        coalescer.handle(MIDIInputControlChange(channel: 0, controller: 74, value: 127))
        clock.advance(to: 100)
        XCTAssertEqual(coalescer.currentValues.color, 1.0)

        coalescer.setMapping(.none)
        coalescer.handle(MIDIInputControlChange(channel: 0, controller: 74, value: 0))
        clock.advance(to: 200)

        XCTAssertEqual(coalescer.currentValues.color, 1.0,
                       "der erreichte Wert bleibt stehen, der CC wirkt nur nicht mehr")
        XCTAssertEqual(recorder.count, 1)
    }

    // MARK: – C. DIE MESSUNG (Teil 3 des Handoffs)

    /// Simuliert einen Reglerschwenk von 127 Werten, gleichmaessig ueber eine
    /// Sekunde verteilt, und zaehlt die entstehenden Ausgaben.
    ///
    /// - Parameter knobs: wie viele Regler gleichzeitig bewegt werden.
    /// - Returns: Anzahl der Makro-Ausgaben. Jede davon erzeugt in
    ///   `AudioEngine.applyMacroValues` genau vier `paramUpdate`-Ereignisse,
    ///   eines je `SynthNode`.
    private func measureSweep(knobs: [UInt8], throttled: Bool) -> Int {
        let recorder = Recorder()

        if !throttled {
            // Vergleichsfall OHNE Massnahme: jeder CC geht direkt durch. Genau
            // das waere die naheliegende Implementierung — Registry-Beobachter
            // ruft applyMacroValues.
            let mapping = MIDIMacroCCMapping.defaults
            var values = AudioCoreMacroValues.defaults
            for step in 0...126 {
                for controller in knobs {
                    guard let id = mapping.macro(forController: controller) else { continue }
                    values[id] = Float(step) / 127.0
                    recorder.record(values)
                }
            }
            return recorder.count
        }

        let clock = VirtualClock()
        let coalescer = makeCoalescer(clock: clock) { recorder.record($0) }

        // 127 Werte in 1.000 ms: alle 7,87 ms einer. Die virtuelle Uhr wird
        // auf den Zeitpunkt jedes Ereignisses vorgezogen, wodurch faellige
        // Flushes exakt dann laufen, wann sie es real taeten.
        for step in 0...126 {
            let timeMs = Int((Double(step) * 1_000.0) / 127.0)
            clock.advance(to: timeMs)
            for controller in knobs {
                coalescer.handle(MIDIInputControlChange(channel: 0, controller: controller,
                                                        value: UInt8(step)))
            }
        }
        clock.advance(to: 1_000)
        return recorder.count
    }

    /// Ein Regler, 127 Werte in einer Sekunde.
    func test_measurement_singleKnobSweep() {
        let without = measureSweep(knobs: [74], throttled: false)
        let with = measureSweep(knobs: [74], throttled: true)

        XCTAssertEqual(without, 127, "ohne Massnahme geht jeder CC einzeln durch")
        // 1.000 ms / 20 ms = 50 moegliche Ausgaben. Mehr darf es nicht werden.
        XCTAssertLessThanOrEqual(with, 1_000 / MIDIMacroCoalescer.flushIntervalMs)
        XCTAssertGreaterThan(with, 0, "der Regler muss trotzdem wirken")

        print("MESSUNG W-05 · 1 Regler, 127 CC in 1 s:"
              + " ohne Drossel \(without) Makro-Ausgaben = \(without * 4) paramUpdates;"
              + " mit Drossel \(with) = \(with * 4) paramUpdates")
    }

    /// Vier Regler gleichzeitig — der Fall, den der Handoff als kritisch
    /// benennt. Hier zahlt sich das Koaleszieren richtig aus, weil alle vier
    /// Makros in derselben Ausgabe landen.
    func test_measurement_fourKnobSweep() {
        let without = measureSweep(knobs: [77, 74, 91, 71], throttled: false)
        let with = measureSweep(knobs: [77, 74, 91, 71], throttled: true)

        XCTAssertEqual(without, 4 * 127)
        XCTAssertLessThanOrEqual(with, 1_000 / MIDIMacroCoalescer.flushIntervalMs)
        XCTAssertGreaterThan(with, 0)

        // Die Drossel muss den Fall um mindestens eine Groessenordnung
        // entschaerfen, sonst traegt sie ihren Namen nicht.
        XCTAssertLessThanOrEqual(with * 10, without,
                                 "vier gleichzeitige Regler: \(without) gegen \(with) Ausgaben")

        print("MESSUNG W-05 · 4 Regler, je 127 CC in 1 s:"
              + " ohne Drossel \(without) Makro-Ausgaben = \(without * 4) paramUpdates;"
              + " mit Drossel \(with) = \(with * 4) paramUpdates")
    }

    /// Die harte Grenze: zwei Ausgaben liegen nie naeher beieinander als
    /// `flushIntervalMs`. Auch nicht bei einer Ereignisflut.
    func test_burstOfEvents_neverExceedsTheConfiguredUpdateRate() {
        let clock = VirtualClock()
        let recorder = Recorder()
        let coalescer = makeCoalescer(clock: clock) { recorder.record($0) }

        // 2.000 CC in einer Sekunde — deutlich mehr als jeder reale
        // Controller sendet, und der Fall "DAW schuettet Automation aus".
        for step in 0..<2_000 {
            clock.advance(to: step / 2)
            coalescer.handle(MIDIInputControlChange(channel: 0, controller: 74,
                                                    value: UInt8(step % 128)))
        }
        clock.advance(to: 1_000)

        XCTAssertLessThanOrEqual(recorder.count, 1_000 / MIDIMacroCoalescer.flushIntervalMs + 1,
                                 "die Rate haelt auch unter Flut: \(recorder.count) Ausgaben")
        print("MESSUNG W-05 · Flut 2.000 CC in 1 s: \(recorder.count) Makro-Ausgaben"
              + " = \(recorder.count * 4) paramUpdates")
    }
}
