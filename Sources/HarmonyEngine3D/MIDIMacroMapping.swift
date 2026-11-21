import Foundation
import HarmonyAudioCore

// MARK: – CC auf die vier Performance-Makros (Runde 074 / W-05)
//
// Zwei Dinge liegen in dieser Datei, und sie haengen zusammen:
//
//   1. `MIDIMacroCCMapping` — welche CC-Nummer welches Makro bewegt,
//      persistiert und einstellbar.
//   2. `MIDIMacroCoalescer` — die Drossel dazwischen. Sie ist der Grund,
//      warum diese Verdrahtung ueberhaupt tragfaehig ist.
//
// ── Warum eine Drossel noetig ist ────────────────────────────────────────────
//
// Ein einziger Reglerschwenk erzeugt Dutzende CC-Ereignisse pro Sekunde. Ohne
// Drossel wuerde jedes davon ueber `AudioEngine.applyMacroValues` VIER
// `paramUpdate`-Ereignisse erzeugen — eines je `SynthNode`, weil jeder Kanal
// seine eigene `NoteEventQueue` hat. Bei den 127 Werten, die ein voller
// 7-Bit-Schwenk in einer Sekunde erzeugt, sind das 508 paramUpdates pro
// Sekunde; bei vier gleichzeitig bewegten Reglern 2.032.
//
// Das ist aus drei Gruenden schaedlich, in aufsteigender Schwere:
//
//   – jedes Ereignis kostet ein `commandQueue.async`, also eine
//     Closure-Allokation und eine Thread-Aufweckung;
//   – die `NoteEventQueue` fasst 64 Eintraege. Sie wird zwar in jedem
//     Renderblock vollstaendig geleert (~187 Bloecke/s bei 256 Frames und
//     48 kHz), aber MIDI wird in Paketen zugestellt: ein Automations-Dump
//     einer DAW kann in einem Block mehr als 64 Ereignisse einreichen, und
//     dann werden Ereignisse verworfen — inklusive Noten;
//   – der teuerste Posten liegt im Audio-Callback: jedes `paramUpdate` laesst
//     `VoicePool.applyParams` laufen, und das baut den Parametersatz JEDER
//     aktiven Stimme neu auf. 2.032 paramUpdates x bis zu 16 Stimmen sind
//     rund 32.000 `setParameters`-Aufrufe pro Sekunde im Rendercallback.
//
// ── Warum Zusammenfassen und nicht Debouncen ─────────────────────────────────
//
// Das Projekt hat mit den Audio-Einstellungen bereits einen Praezedenzfall:
// 30 ms `.debounce`, ausdruecklich "kein AU-Parameterflut"
// (`HarmonyEngine3DApp`). Der Fall ist hier aber ein anderer, und die
// Uebernahme waere ein Fehler: Combines `.debounce` ist rein nachlaufend. Es
// gibt waehrend einer laufenden Bewegung GAR NICHTS aus, sondern erst, wenn
// der Regler stillsteht. Fuer einen Einstellungs-Schieberegler ist das
// richtig; fuer einen Performance-Regler waere es das Gegenteil von spielbar
// — man hoerte waehrend des Drehens nichts und am Ende einen Sprung.
//
// Gewaehlt ist deshalb Koaleszieren mit fester Mindestpause: jeder CC
// ueberschreibt den anstehenden Wert seines Makros (letzter Wert gewinnt),
// und hoechstens alle `flushIntervalMs` verlaesst ein zusammengefasster
// Stand die Drossel. Wirkung mit Zahlen in `MIDIMacroMappingTests`.
//
// Der Takt ist selbstloeschend: im Leerlauf laeuft kein Timer. Der erste CC
// einer Geste plant genau einen Flush ein, weitere CCs derselben Pause planen
// nichts nach. Zwei aufeinanderfolgende Ausgaben liegen damit immer
// mindestens `flushIntervalMs` auseinander.
//
// ── SPSC-Vertrag ─────────────────────────────────────────────────────────────
//
// Unveraendert gegenueber W-04, und die Drossel macht ihn eher sicherer: der
// CoreMIDI-Thread schreibt ausschliesslich in `pending` (lokales `NSLock`),
// nie in die `NoteEventQueue` und nie in `AudioEngine`. Der Flush laeuft auf
// dem Main Thread und ruft von dort `AudioEngine.applyMacroValues`, das den
// Aufruf wie jeder andere App-Layer-Aufruf auf `commandQueue` legt. Producer
// der Queue bleibt allein der commandQueue-Worker.

// MARK: – Zuordnung CC-Nummer -> Makro

/// Welche CC-Nummer welches Performance-Makro bewegt.
///
/// **Die vier Default-Nummern sind VORLAEUFIG — Stephan entscheidet nach dem
/// Drehen.** Gewaehlt sind konventionelle Nummern aus dem MMA-Block der Sound
/// Controller (CC 70-79) plus der GM-Standard fuer den Hallanteil, damit ein
/// beliebiger Controller ab Werk sinnvoll trifft:
///
///   | Makro  | CC | Uebliche Beschriftung                    |
///   |--------|----|------------------------------------------|
///   | Motion | 77 | Vibrato Depth / Sound Controller 8       |
///   | Color  | 74 | Brightness — de-facto-Standard, MPE-Timbre |
///   | Space  | 91 | Reverb Send Level (GM)                   |
///   | Focus  | 71 | Timbre / Harmonic Intensity              |
///
/// CC 74 ist die einzige wirklich universelle Zuordnung; die drei anderen
/// sind konventionsnah gewaehlt, nicht standardisiert.
struct MIDIMacroCCMapping: Equatable {

    /// Groesste zuweisbare CC-Nummer.
    ///
    /// 120-127 sind Channel-Mode-Nachrichten und 121/122 Reset All
    /// Controllers / Local Control. Alle acht kommen im Router gar nicht als
    /// `.controlChange` an (`MIDIInputDecoder` macht daraus `.allNotesOff`
    /// oder `nil`). Eine Zuweisung dorthin waere ein Regler, der garantiert
    /// nichts tut — deshalb ist die Grenze hier hart und nicht erst in der UI.
    static let maxAssignableController: UInt8 = 119

    /// `nil` heisst "diesem Makro ist keine CC-Nummer zugeordnet". Das ist ein
    /// gueltiger Zustand, kein Fehler.
    private(set) var motion: UInt8?
    private(set) var color:  UInt8?
    private(set) var space:  UInt8?
    private(set) var focus:  UInt8?

    init(motion: UInt8? = nil, color: UInt8? = nil, space: UInt8? = nil, focus: UInt8? = nil) {
        self.motion = MIDIMacroCCMapping.sanitize(motion)
        self.color  = MIDIMacroCCMapping.sanitize(color)
        self.space  = MIDIMacroCCMapping.sanitize(space)
        self.focus  = MIDIMacroCCMapping.sanitize(focus)
        removeDuplicatesKeepingFirst()
    }

    /// Vorlaeufige Werksbelegung, siehe Tabelle oben.
    static let defaults = MIDIMacroCCMapping(motion: 77, color: 74, space: 91, focus: 71)

    /// Keine Zuordnung — jeder CC laeuft ins Leere.
    static let none = MIDIMacroCCMapping()

    subscript(id: AudioCoreMacroID) -> UInt8? {
        switch id {
        case .motion: return motion
        case .color:  return color
        case .space:  return space
        case .focus:  return focus
        }
    }

    /// Umkehrsuche fuer den Empfangspfad. Eindeutig per Konstruktion: eine
    /// CC-Nummer kann nie zwei Makros gehoeren (siehe `assign`).
    ///
    /// Eine unbelegte Nummer liefert `nil` — das ist der Normalfall, kein
    /// Fehler: ein Controller sendet nebenher Modulationsrad, Pedal und
    /// Aftertouch, und nichts davon soll etwas bewegen.
    func macro(forController controller: UInt8) -> AudioCoreMacroID? {
        if controller == motion { return .motion }
        if controller == color  { return .color }
        if controller == space  { return .space }
        if controller == focus  { return .focus }
        return nil
    }

    /// Weist `controller` dem Makro `id` zu. `nil` loest die Zuordnung.
    ///
    /// ── Doppelt belegte CC-Nummern sind AUSGESCHLOSSEN ──────────────────
    ///
    /// Wird eine Nummer vergeben, die schon einem anderen Makro gehoert,
    /// verliert das andere Makro seine Zuordnung. Drei Gruende:
    ///
    ///   1. Ein Regler, der zwei Makros gleichzeitig bewegt, ist am
    ///      Instrument nicht diagnostizierbar. Wer eine unerwartete
    ///      Klangaenderung hoert, sucht sie beim gedrehten Makro — nicht bei
    ///      einem zweiten, das er nie zugewiesen zu haben glaubt.
    ///   2. Der Effekt, den man dabei will ("ein Regler, zwei Wirkungen"),
    ///      existiert bereits sauber und an der richtigen Stelle: als zweite
    ///      Route desselben Makros in der Modulationsmatrix. Ein zweiter,
    ///      schwaecherer Mechanismus daneben waere Doppelarbeit mit
    ///      schlechterer Semantik.
    ///   3. Die Umkehrsuche bleibt eindeutig und ohne Sonderfall.
    ///
    /// Die Verdraengung ist sichtbar, nicht still: das andere Makro steht
    /// danach in der UI auf "—".
    mutating func assign(controller: UInt8?, to id: AudioCoreMacroID) {
        let value = MIDIMacroCCMapping.sanitize(controller)

        if let value {
            if motion == value { motion = nil }
            if color  == value { color  = nil }
            if space  == value { space  = nil }
            if focus  == value { focus  = nil }
        }

        switch id {
        case .motion: motion = value
        case .color:  color  = value
        case .space:  space  = value
        case .focus:  focus  = value
        }
    }

    // MARK: – Persistenzform
    //
    // `UserDefaults` hat kein natives Pendant fuer `Optional<UInt8>`; gespeichert
    // wird ein `Int` mit `-1` fuer "nicht zugeordnet". Dasselbe Sentinel-Muster
    // wie bei `midiInput.selectedSourceUniqueID` (0) und
    // `worldExternalMapFileName` (leerer String).
    //
    // Die beiden Funktionen liegen bewusst hier und nicht in `AppSettings`:
    // dort waeren sie in privaten Methoden vergraben und nicht pruefbar. Der
    // Zugriff auf `UserDefaults` selbst bleibt in `AppSettings` und laeuft
    // ueber dieselben Helfer wie jede andere Einstellung.

    /// Nicht zugeordnet.
    static let unassignedStoredValue = -1

    static func storedValue(for controller: UInt8?) -> Int {
        controller.map(Int.init) ?? unassignedStoredValue
    }

    /// Nimmt auch einen unsinnigen gespeicherten Wert entgegen (von Hand
    /// veraenderte plist, alte Version) und liefert dann "nicht zugeordnet".
    static func controller(fromStored stored: Int) -> UInt8? {
        guard stored >= 0, stored <= Int(maxAssignableController) else { return nil }
        return UInt8(stored)
    }

    private static func sanitize(_ controller: UInt8?) -> UInt8? {
        guard let controller, controller <= maxAssignableController else { return nil }
        return controller
    }

    /// Sichert die Eindeutigkeit auch fuer einen direkt konstruierten Wert —
    /// etwa aus `UserDefaults`, wo eine von Hand veraenderte Datei zwei
    /// gleiche Nummern enthalten koennte. Es gewinnt die erste in der festen
    /// Reihenfolge Motion, Color, Space, Focus.
    private mutating func removeDuplicatesKeepingFirst() {
        var seen = Set<UInt8>()
        for id in [AudioCoreMacroID.motion, .color, .space, .focus] {
            guard let value = self[id] else { continue }
            if seen.contains(value) {
                switch id {
                case .motion: motion = nil
                case .color:  color  = nil
                case .space:  space  = nil
                case .focus:  focus  = nil
                }
            } else {
                seen.insert(value)
            }
        }
    }
}

// MARK: – Drossel

/// Fasst eingehende Control Changes zu hoechstens einer Makro-Ausgabe je
/// `flushIntervalMs` zusammen.
///
/// `@unchecked Sendable`: aller veraenderlicher Zustand liegt hinter `lock`,
/// die beiden Closures sind `@Sendable`. Die Klasse quert bewusst
/// Threadgrenzen — `handle(_:)` kommt vom CoreMIDI-Thread, `flush()` vom
/// Main Thread.
final class MIDIMacroCoalescer: @unchecked Sendable {

    /// Mindestabstand zwischen zwei Ausgaben.
    ///
    /// 20 ms sind 50 Ausgaben pro Sekunde. Bewusst kuerzer als der 30-ms-
    /// Debounce der Audio-Einstellungen: dort geht es um einen
    /// Einstellungs-Schieberegler, hier um einen Performance-Regler, der sich
    /// unmittelbar anfuehlen muss. 50 Hz liegen oberhalb der Schwelle, ab der
    /// eine Regleraenderung als verzoegert wahrgenommen wird, und zugleich
    /// nahe genug an der Glaettungszeit der Stimme (12 ms), dass jede Stufe
    /// innerhalb ihrer Pause weitgehend ausgeglichen ist. Dass daraus keine
    /// hoerbaren Stufen entstehen, ist in
    /// `AudioCoreMacroRoutingTests.test_coalescedTwentyMillisecondJumps_...`
    /// mit Positivkontrolle belegt.
    static let flushIntervalMs = 20

    /// Plant `work` nach `afterMilliseconds` ein. Injizierbar, damit die
    /// Drossel ohne echte Zeit und ohne `sleep` deterministisch testbar ist.
    typealias Scheduler = @Sendable (_ afterMilliseconds: Int, _ work: @escaping @Sendable () -> Void) -> Void

    static let mainQueueScheduler: Scheduler = { milliseconds, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds), execute: work)
    }

    private let lock = NSLock()
    private var mapping: MIDIMacroCCMapping
    private var pending: AudioCoreMacroValues
    private var lastEmitted: AudioCoreMacroValues
    private var isFlushScheduled = false

    // Zaehler wie `NoteEventQueue.droppedEventCount`: sichtbar statt still.
    private var emittedUpdates = 0
    private var receivedChanges = 0
    private var ignoredChanges = 0

    private let schedule: Scheduler
    private let sink: @Sendable (AudioCoreMacroValues) -> Void

    init(mapping: MIDIMacroCCMapping,
         initialValues: AudioCoreMacroValues = .defaults,
         schedule: @escaping Scheduler = MIDIMacroCoalescer.mainQueueScheduler,
         sink: @escaping @Sendable (AudioCoreMacroValues) -> Void) {
        self.mapping = mapping
        self.pending = initialValues
        self.lastEmitted = initialValues
        self.schedule = schedule
        self.sink = sink
    }

    // MARK: – Zustand

    var currentValues: AudioCoreMacroValues {
        lock.lock(); defer { lock.unlock() }
        return pending
    }

    /// Anzahl tatsaechlich weitergereichter Makro-Staende. Die Messgroesse
    /// aus Teil 3 des Handoffs.
    var emittedUpdateCount: Int {
        lock.lock(); defer { lock.unlock() }
        return emittedUpdates
    }

    var receivedChangeCount: Int {
        lock.lock(); defer { lock.unlock() }
        return receivedChanges
    }

    /// Control Changes, die keinem Makro zugeordnet sind. Sie tun nichts und
    /// sind kein Fehler — der Zaehler macht nur sichtbar, dass sie ankamen.
    var ignoredChangeCount: Int {
        lock.lock(); defer { lock.unlock() }
        return ignoredChanges
    }

    // MARK: – Zuordnung wechseln (Main Thread)

    /// Uebernimmt eine geaenderte Zuordnung.
    ///
    /// Bereits erreichte Makrowerte bleiben ausdruecklich stehen. Ein Makro,
    /// das seine CC-Nummer verliert, faellt NICHT auf 0 zurueck — das waere
    /// eine hoerbare Klangaenderung als Nebenwirkung einer Einstellung.
    func setMapping(_ newMapping: MIDIMacroCCMapping) {
        lock.lock()
        mapping = newMapping
        lock.unlock()
    }

    // MARK: – Empfang (CoreMIDI-Thread)

    /// Nimmt einen Control Change entgegen. Der Kanal wird bewusst ignoriert:
    /// die Makros sind global, und ein Kanalfilter waere hier derselbe stille
    /// Fehlermodus, den die Kanal-Politik des Noteneingangs vermeidet
    /// ("Regler gedreht, nichts passiert"). Vorlaeufig, wie jene.
    func handle(_ change: MIDIInputControlChange) {
        lock.lock()
        receivedChanges += 1
        guard let id = mapping.macro(forController: change.controller) else {
            ignoredChanges += 1
            lock.unlock()
            return
        }

        // 7 Bit -> 0...1. Der Wert ist bereits auf 0...127 maskiert
        // (MIDIInputDecoder), die Division kann nicht ueber 1 laufen.
        pending[id] = Float(change.value) / 127.0

        let needsScheduling = !isFlushScheduled
        isFlushScheduled = true
        lock.unlock()

        // Ausserhalb des Locks: der Scheduler darf blockieren duerfen, ohne
        // den CoreMIDI-Thread und den Main Thread zu verschraenken.
        if needsScheduling {
            schedule(MIDIMacroCoalescer.flushIntervalMs) { [weak self] in self?.flush() }
        }
    }

    // MARK: – Ausgabe (Main Thread)

    /// Gibt den zusammengefassten Stand weiter, wenn er sich seit der letzten
    /// Ausgabe geaendert hat.
    ///
    /// Der Gleichheitsvergleich ist kein Luxus: ein Controller mit
    /// zitterndem Poti sendet denselben Wert immer wieder, und ohne diesen
    /// Vergleich erzeugte jeder davon vier paramUpdates.
    func flush() {
        lock.lock()
        let value = pending
        isFlushScheduled = false
        let changed = value != lastEmitted
        if changed {
            lastEmitted = value
            emittedUpdates += 1
        }
        lock.unlock()

        if changed { sink(value) }
    }
}
