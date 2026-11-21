import Foundation

// MARK: – MIDI-Eingang: reine Routing-Schicht (Runde 073 / W-04)
//
// Diese Datei ist bewusst CoreMIDI-frei. Dekodierung, Kanal-Politik,
// Notenbuchfuehrung und die Abbildung auf `AudioOutput` liegen hier und sind
// ohne Geraetezugriff testbar. Die CoreMIDI-Anbindung (virtuelles Ziel,
// Eingangsport, Quellenliste, Geraetewechsel) liegt getrennt in
// `MIDIInputManager.swift`.
//
// ── Der Thread-Vertrag, der diese Runde traegt ────────────────────────────────
//
// `NoteEventQueue` ist ein SPSC-Ringpuffer: genau EIN Thread darf `push()`
// aufrufen (siehe NoteEventQueue.swift; der Vertrag stammt aus F-02, wo er
// verletzt war). Eingehaltet wird er heute allein durch
// `AudioEngine.commandQueue` — eine serielle DispatchQueue, ueber die
// ausnahmslos alle vier `AudioOutput`-Methoden und `SynthNode.updateParams()`
// laufen.
//
// MIDI-Callbacks kommen von einem CoreMIDI-eigenen Thread und waeren damit ein
// NEUER Producer — wenn sie in die Queue schreiben wuerden. Sie tun es nicht:
// `MIDIInputRouter` ruft ausschliesslich das `AudioOutput`-Protokoll auf, also
// exakt denselben Weg wie HarmonyScene, GamepadController und der Main Thread.
// `AudioEngine.noteOn/noteOff/allNotesOff` legen den Aufruf selbst auf
// `commandQueue`; erst deren Worker-Thread ruft `push()`. Der CoreMIDI-Thread
// ist deshalb kein Producer der NoteEventQueue, sondern nur ein weiterer
// Einreicher an derselben Serialisierungsgrenze. Am SPSC-Vertrag und an der
// Queue selbst aendert W-04 nichts.
//
// Der eigene Zustand dieser Schicht (Notenbuch, CC-Register) wird dagegen
// wirklich von mehreren Threads beruehrt — CoreMIDI-Thread beim Empfang, Main
// Thread bei Quellenwechsel/Panic — und ist deshalb hier lokal per `NSLock`
// geschuetzt. Das ist zulaessig, weil diese Schicht nicht im
// Audio-Render-Thread laeuft. Der Render-Thread (Consumer in
// `SynthNode.prepare()`) bleibt unveraendert lock-, dispatch- und
// allokationsfrei.
//
// ── Allokationen im MIDI-Callback ────────────────────────────────────────────
//
// Das Notenbuch ist ein `Set`, das CC-Register ein `Dictionary`; beide
// allozieren beim Wachsen. Das ist im MIDI-Callback vertretbar (er ist nicht
// der Audio-Render-Thread), waere im Renderpfad verboten. Die Trennlinie
// verlaeuft an `AudioOutput`: alles hier ist Steuerpfad, alles hinter der
// NoteEventQueue ist Renderpfad.

// MARK: – Endpunkt-Namen

/// Die beiden Namen, unter denen die App in der MIDI-Geraeteliste erscheint.
/// `virtualSource` ist der seit Rev. 5 unveraenderte Ausgang — der Wert wird
/// hier nur zentral benannt, nicht geaendert.
enum MIDIEndpointNames {
    static let virtualSource      = "HarmonyEngine3D Output"
    static let virtualDestination = "HarmonyEngine3D Input"
}

// MARK: – Quellenbeschreibung

/// Eine auswaehlbare externe MIDI-Quelle. `uniqueID` ist die stabile
/// CoreMIDI-Kennung (`kMIDIPropertyUniqueID`) und ueberlebt Umbenennungen und
/// Neustarts; `displayName` dient nur der Anzeige.
struct MIDIInputSourceDescriptor: Identifiable, Equatable, Hashable {
    let uniqueID:    Int32
    let displayName: String

    var id: Int32 { uniqueID }
}

// MARK: – Persistierte Auswahl

/// Persistierte Eingangs-Einstellung (`AppSettings.midiInput`).
///
/// `selectedSourceUniqueID == nil` heisst ausdruecklich NICHT "kein Eingang":
/// das virtuelle Ziel "HarmonyEngine3D Input" existiert unabhaengig davon und
/// bleibt fuer DAWs erreichbar. Die Auswahl betrifft nur die zusaetzliche
/// Verbindung zu einer externen Hardware-/Software-Quelle.
struct MIDIInputConfig: Equatable {
    /// Schaltet den gesamten Eingang ab (virtuelles Ziel bleibt bestehen,
    /// eingehende Ereignisse werden aber nicht mehr weitergereicht).
    var isEnabled: Bool = true

    /// Gewaehlte externe Quelle. `nil` = keine, nur das virtuelle Ziel.
    var selectedSourceUniqueID: Int32? = nil

    /// Zuletzt gesehener Anzeigename der gewaehlten Quelle. Wird nur gebraucht,
    /// um ein fehlendes Geraet nachvollziehbar benennen zu koennen
    /// ("Launchkey 49 – nicht verbunden") statt nur eine nackte Zahl zu zeigen.
    var selectedSourceName: String = ""

    /// Zuordnung CC-Nummer -> Performance-Makro (Runde 074 / W-05).
    ///
    /// Bewusst hier und nicht in `AppSettings.AudioConfig`: die Zuordnung
    /// beschreibt den EINGANG, nicht den Klang. Sie teilt damit auch die
    /// Abo-Kette des Eingangs (`AppSettings.$midiInput`) und braucht keine
    /// zweite Subscription. Siehe MIDIMacroMapping.swift.
    var macroCCMapping: MIDIMacroCCMapping = .defaults
}

// MARK: – Verbindungszustand

/// Auswertung der persistierten Auswahl gegen die real vorhandenen Quellen.
/// Ein fehlendes Geraet ist ein eigener, benannter Zustand — kein Fehler, kein
/// stiller Totalausfall.
enum MIDIInputConnectionState: Equatable {
    /// Eingang per Einstellung abgeschaltet.
    case disabled
    /// Kein externes Geraet gewaehlt; nur das virtuelle Ziel ist aktiv.
    case virtualOnly
    /// Gewaehltes Geraet ist vorhanden und verbunden.
    case connected(MIDIInputSourceDescriptor)
    /// Gewaehltes Geraet ist aktuell nicht vorhanden (abgezogen, DAW zu).
    /// Die Auswahl bleibt gespeichert und greift wieder, sobald es zurueckkommt.
    case unavailable(uniqueID: Int32, name: String)
}

/// Aussortieren nicht anbietbarer Quellen. Ohne CoreMIDI, damit die Regel
/// testbar bleibt.
enum MIDIInputSourceFilter {

    /// Entfernt den eigenen virtuellen Ausgang aus der Auswahlliste.
    ///
    /// Grund: der Eingang reicht empfangene Ereignisse an den aktiven
    /// `AudioOutput` weiter. Bei `outputMode == .midi` ist das der virtuelle
    /// Ausgang — waere er zugleich als Eingangsquelle waehlbar, entstuende eine
    /// echte MIDI-Endlosschleife (jedes Ereignis erzeugt sich selbst neu).
    /// Eine von aussen gepatchte Schleife (DAW verbindet unseren Ausgang mit
    /// unserem Eingang) kann die App nicht verhindern; die selbst gebaute
    /// verhindert sie hier.
    ///
    /// Zusaetzlich fliegen Endpunkte mit `uniqueID == 0` raus
    /// (`kMIDIInvalidUniqueID`) — sie waeren nicht wiederfindbar.
    static func selectable(from sources: [MIDIInputSourceDescriptor]) -> [MIDIInputSourceDescriptor] {
        sources.filter { $0.uniqueID != 0 && $0.displayName != MIDIEndpointNames.virtualSource }
    }
}

/// Reine Aufloesung Auswahl x vorhandene Geraete. Ohne CoreMIDI, damit die
/// Robustheit gegen fehlende Geraete testbar ist.
enum MIDIInputSourceResolver {

    static func resolve(config: MIDIInputConfig,
                        available: [MIDIInputSourceDescriptor]) -> MIDIInputConnectionState {
        guard config.isEnabled else { return .disabled }
        guard let uniqueID = config.selectedSourceUniqueID, uniqueID != 0 else { return .virtualOnly }
        if let match = available.first(where: { $0.uniqueID == uniqueID }) {
            return .connected(match)
        }
        return .unavailable(uniqueID: uniqueID, name: config.selectedSourceName)
    }
}

// MARK: – Kanal-Politik (VORLAEUFIG, Stephan-Entscheidung offen)

/// Abbildung des eingehenden MIDI-Kanals auf die vier App-Kanaele.
///
/// **Vorlaeufig gewaehlt, nicht entschieden.** Der Eingang hoert auf ALLEN 16
/// MIDI-Kanaelen — ein stiller Kanalfilter waere der undankbarste Fehlermodus
/// ("Tasten gedrueckt, nichts passiert"). Die Abbildung spiegelt die bereits
/// festgeschriebene Ausgangsbelegung:
///
///   MIDI-Kanal 1-4  →  App-Kanal CH0-CH3 (Akkorde / Bass / Melodie / Chord-Tones)
///   MIDI-Kanal 5-16 →  CH0
///
/// Ein einfaches Keyboard sendet ab Werk auf Kanal 1 und landet damit auf CH0,
/// dem polyphonen Akkordkanal — das ist der erwartete Normalfall. Alternative
/// fuer Stephan, falls das Uebersprechen mit den vom Spiel selbst gespielten
/// Noten stoert: ein fester, eigener Eingangskanal.
enum MIDIInputChannelPolicy {

    /// App-Kanal fuer MIDI-Kanaele ausserhalb 1-4.
    static let fallbackChannel = 0

    /// - Parameter inputChannel: roher MIDI-Kanal, 0-basiert (0 = MIDI-Kanal 1).
    static func appChannel(forInputChannel inputChannel: Int) -> Int {
        (0...3).contains(inputChannel) ? inputChannel : fallbackChannel
    }
}

// MARK: – Eingangsweg

/// Die beiden Wege, auf denen Ereignisse hereinkommen. Sie werden getrennt
/// gefuehrt, weil sie unterschiedliche Lebensdauern haben: das virtuelle Ziel
/// existiert, solange die App laeuft; die externe Quelle kann jederzeit
/// verschwinden. Ein gemeinsames Notenbuch wuerde beim Abziehen eines Keyboards
/// auch die Noten beenden, die eine DAW gerade haelt.
enum MIDIInputPath: Hashable {
    case virtualDestination
    case externalSource
}

// MARK: – Dekodierte Eingangsnachricht

/// Bereits interpretierte Eingangsnachricht. `channel` ist durchgehend der rohe
/// MIDI-Kanal (0-15); die Abbildung auf App-Kanaele passiert erst im Router,
/// damit die CC-Seite den Originalkanal behaelt (W-05 braucht ihn).
enum MIDIInputMessage: Equatable {
    case noteOn(channel: Int, note: UInt8, velocity: UInt8)
    case noteOff(channel: Int, note: UInt8)
    case controlChange(channel: Int, controller: UInt8, value: UInt8)
    /// Channel-Mode-Nachricht mit Notenwirkung (CC 120, 123-127).
    case allNotesOff(channel: Int)
}

// MARK: – Dekoder

/// Uebersetzt einen empfangenen MIDI-Datensatz in eine `MIDIInputMessage`.
///
/// Der Eingang haengt an `MIDIInputPortCreateWithProtocol`/
/// `MIDIDestinationCreateWithProtocol` mit `MIDIProtocolID._1_0`. CoreMIDI
/// liefert dort Universal MIDI Packets (UMP) und uebernimmt die Uebersetzung
/// aus dem klassischen Bytestrom — inklusive Aufloesung des Running Status.
/// Jedes UMP-Wort traegt deshalb immer ein vollstaendiges Statusbyte; ein
/// eigener Running-Status-Automat waere toter Code und ist bewusst nicht da.
///
/// Bewusst nicht die aeltere `...WithBlock`-Variante: die ist seit macOS 11
/// als deprecated markiert (`API_DEPRECATED_WITH_REPLACEMENT`) und haette eine
/// neue Warnkategorie in den Build gebracht.
enum MIDIInputDecoder {

    /// UMP-Message-Type 0x2: MIDI 1.0 Channel Voice, genau ein 32-Bit-Wort.
    private static let channelVoiceMessageType: UInt32 = 0x2

    /// Dekodiert ein einzelnes UMP-Wort.
    ///
    /// Wortaufbau (Message Type 2):
    ///   Bits 31-28 Message Type | 27-24 Group | 23-16 Status | 15-8 Data 1 | 7-0 Data 2
    ///
    /// Die Group wird bewusst ignoriert: eine klassische MIDI-Verbindung
    /// erzeugt genau eine Group, und eine Group-Politik waere eine
    /// musikalische Entscheidung, die W-04 nicht trifft.
    static func message(fromWord word: UInt32) -> MIDIInputMessage? {
        guard (word >> 28) == channelVoiceMessageType else { return nil }
        let status = UInt8((word >> 16) & 0xFF)
        let data1  = UInt8((word >> 8)  & 0xFF)
        let data2  = UInt8(word         & 0xFF)
        return message(status: status, data1: data1, data2: data2)
    }

    /// Interpretation eines klassischen Status-/Datenbyte-Tripels. Getrennt
    /// vom Wort-Zerlegen, damit die musikalisch relevanten Regeln
    /// (Velocity-0-Konvention, Channel-Mode-Nachrichten) ohne UMP-Bitschieben
    /// testbar sind.
    static func message(status: UInt8, data1: UInt8, data2: UInt8) -> MIDIInputMessage? {
        let channel = Int(status & 0x0F)
        let note    = data1 & 0x7F
        let value   = data2 & 0x7F

        switch status & 0xF0 {
        case 0x80:
            return .noteOff(channel: channel, note: note)

        case 0x90:
            // MIDI-Konvention: Note-On mit Velocity 0 ist ein Note-Off.
            return value == 0
                ? .noteOff(channel: channel, note: note)
                : .noteOn(channel: channel, note: note, velocity: value)

        case 0xB0:
            switch note {
            case 120, 123, 124, 125, 126, 127:
                // All Sound Off, All Notes Off, Omni/Mono/Poly — alle mit
                // Notenwirkung laut MIDI-Spezifikation.
                return .allNotesOff(channel: channel)
            case 121, 122:
                // Reset All Controllers / Local Control: keine Notenwirkung,
                // kein Parameterziel fuer W-05.
                return nil
            default:
                return .controlChange(channel: channel, controller: note, value: value)
            }

        default:
            // Polyphoner Aftertouch, Program Change, Channel Pressure, Pitch
            // Bend: bewusst nicht Teil von W-04.
            return nil
        }
    }
}

// MARK: – Notenbuch

/// Buchfuehrung ueber extern gestartete Noten. Reiner Wertetyp, damit die
/// On-Off-Symmetrie ohne Geraet und ohne Threading testbar ist; die
/// Thread-Sicherheit liegt beim Halter (`MIDIInputRouter`).
struct MIDIInputNoteBook: Equatable {

    struct Key: Hashable {
        let channel: Int    // App-Kanal 0-3
        let note:    UInt8
    }

    private(set) var activeNotes: Set<Key> = []

    var isEmpty: Bool { activeNotes.isEmpty }
    var count:   Int  { activeNotes.count }

    mutating func noteOn(channel: Int, note: UInt8) {
        activeNotes.insert(Key(channel: channel, note: note))
    }

    /// - Returns: `true`, wenn die Note wirklich als aktiv gefuehrt wurde.
    ///   Ein Note-Off ohne passendes Note-On wird trotzdem durchgereicht (der
    ///   Synth ignoriert es), zaehlt hier aber nicht als Buchung.
    @discardableResult
    mutating func noteOff(channel: Int, note: UInt8) -> Bool {
        activeNotes.remove(Key(channel: channel, note: note)) != nil
    }

    /// Entfernt und liefert alle Noten eines App-Kanals.
    mutating func removeAll(channel: Int) -> [Key] {
        let removed = activeNotes.filter { $0.channel == channel }
        activeNotes.subtract(removed)
        return Array(removed)
    }

    /// Entfernt und liefert alle Noten.
    mutating func removeAll() -> [Key] {
        let removed = Array(activeNotes)
        activeNotes.removeAll(keepingCapacity: true)
        return removed
    }
}

// MARK: – Control Changes fuer W-05

/// Ein empfangener Control Change. `channel` ist der rohe MIDI-Kanal (0-15) —
/// nicht die App-Kanal-Abbildung: welche Rolle der Kanal beim Parameter-Mapping
/// spielt, entscheidet W-05.
struct MIDIInputControlChange: Equatable {
    let channel:    Int
    let controller: UInt8
    let value:      UInt8
}

/// Abholpunkt fuer Control Changes. W-04 bildet ausdruecklich nichts ab: hier
/// steht nur der jeweils letzte Wert je (Kanal, Controller) plus ein
/// Beobachter-Haken. W-05 haengt sich an `onControlChange` oder liest
/// `latestValue(...)`.
///
/// Thread-sicher per Lock, weil geschrieben wird vom CoreMIDI-Thread und
/// gelesen (spaeter) vom Main Thread.
final class MIDIControlChangeRegistry {

    private let lock = NSLock()
    private var values: [Int: UInt8] = [:]
    private var observer: ((MIDIInputControlChange) -> Void)?

    /// Wird synchron auf dem CoreMIDI-Thread aufgerufen. Wer hier UI anfasst,
    /// muss selbst auf den Main Thread wechseln.
    func setObserver(_ observer: ((MIDIInputControlChange) -> Void)?) {
        lock.lock()
        self.observer = observer
        lock.unlock()
    }

    func record(_ change: MIDIInputControlChange) {
        lock.lock()
        values[Self.key(channel: change.channel, controller: change.controller)] = change.value
        let observer = self.observer
        lock.unlock()
        observer?(change)
    }

    func latestValue(channel: Int, controller: UInt8) -> UInt8? {
        lock.lock()
        defer { lock.unlock() }
        return values[Self.key(channel: channel, controller: controller)]
    }

    /// Alle bisher gesehenen Controller, aufsteigend nach Kanal und Nummer —
    /// stabile Reihenfolge fuer Anzeige und Tests.
    func snapshot() -> [MIDIInputControlChange] {
        lock.lock()
        let copy = values
        lock.unlock()
        return copy
            .map { MIDIInputControlChange(channel: $0.key >> 8,
                                          controller: UInt8($0.key & 0xFF),
                                          value: $0.value) }
            .sorted { ($0.channel, $0.controller) < ($1.channel, $1.controller) }
    }

    func removeAll() {
        lock.lock()
        values.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    private static func key(channel: Int, controller: UInt8) -> Int {
        (channel << 8) | Int(controller)
    }
}

// MARK: – Router

/// Uebersetzt dekodierte Eingangsnachrichten in `AudioOutput`-Aufrufe und haelt
/// dabei die On-Off-Symmetrie fuer extern gestartete Noten.
///
/// Der Router kennt weder CoreMIDI noch AVFoundation und ist deshalb mit einem
/// Test-Output vollstaendig pruefbar.
///
/// Zielsenke ist bewusst der aktive `AudioOutput` — derselbe, den das Spiel
/// selbst bedient. Bei `outputMode == .internalAudio` spielt der Eingang den
/// internen Synth; bei `.midi` geht er als MIDI-Thru an den virtuellen Ausgang.
/// Kein Sonderweg, keine zweite Serialisierungsgrenze.
final class MIDIInputRouter {

    private weak var output: (any AudioOutput)?

    // ── Ein Lock, das Buchung UND Ausgabe umschliesst ────────────────────────
    //
    // Die Buchfuehrung und der zugehoerige `AudioOutput`-Aufruf liegen
    // ausdruecklich INNERHALB derselben kritischen Sektion. Waeren sie
    // getrennt — Buchung unter Lock, Ausgabe danach —, koennten sich
    // CoreMIDI-Thread und Main Thread so verschraenken, dass die Reihenfolge
    // kippt:
    //
    //   CoreMIDI: bucht Note 60, gibt das Lock frei
    //   Main:     raeumt das Buch (findet 60), sendet noteOff(60)
    //   CoreMIDI: sendet erst jetzt noteOn(60)
    //
    // Beide reichen in dieser Reihenfolge bei `AudioEngine.commandQueue` ein,
    // die Queue behaelt sie — das Off kaeme vor dem On an und die Note haenge
    // fuer immer. Genau der Fehler, den dieser Pfad verhindern soll. Mit
    // Buchung und Ausgabe unter einem Lock sind je Note nur noch zwei
    // Reihenfolgen moeglich, und beide sind korrekt.
    //
    // Kein Deadlock-Risiko: die aufgerufenen `AudioOutput`-Methoden rufen
    // nicht in den Router zurueck. `AudioEngine` macht ein `dbg()` plus
    // `commandQueue.async` (beschraenktes Einreihen, kein Warten),
    // `MIDIManager` ein `MIDIReceived`. Das Registrieren von Control Changes
    // laeuft bewusst ausserhalb dieses Locks, damit die beiden Locks nie
    // geschachtelt werden.
    private let lock = NSLock()

    // ── Getrennte Buchfuehrung je Eingangsweg ───────────────────────────────
    //
    // Ein gemeinsames Buch waere auch ohne Race falsch: das Abziehen eines
    // Keyboards wuerde die Noten beenden, die eine DAW ueber das virtuelle
    // Ziel gerade haelt. Die beiden Wege haben unterschiedliche Lebensdauern
    // und werden deshalb getrennt gefuehrt.
    private var destinationBook = MIDIInputNoteBook()
    private var sourceBook      = MIDIInputNoteBook()

    /// Gesperrter Weg: `noteOn` wird verworfen, bevor es klingt. Wird beim
    /// Trennen einer externen Quelle gesetzt — siehe `releaseNotes(on:sealing:)`.
    private var isSourcePathSealed = false

    let controlChanges = MIDIControlChangeRegistry()

    /// Zaehlt verworfene Nachrichten, solange kein Output haengt — sichtbar
    /// statt still (dieselbe Haltung wie `NoteEventQueue.droppedEventCount`).
    private var droppedMessages: Int = 0

    init(output: (any AudioOutput)?) {
        self.output = output
    }

    // MARK: – Zustand

    /// Anzahl aktuell als klingend gefuehrter externer Noten, ueber beide Wege.
    var activeExternalNoteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return destinationBook.count + sourceBook.count
    }

    func activeExternalNoteCount(on path: MIDIInputPath) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return book(on: path).count
    }

    var droppedMessageCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return droppedMessages
    }

    var isExternalSourcePathSealed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isSourcePathSealed
    }

    // MARK: – Empfang

    /// Verarbeitet eine Nachricht. Aufruf erfolgt real vom CoreMIDI-Thread.
    func handle(_ message: MIDIInputMessage, from path: MIDIInputPath) {
        // Control Changes beruehren keine Note und kein Buch — bewusst vor dem
        // Lock, damit Router- und Registry-Lock nie geschachtelt werden.
        if case let .controlChange(channel, controller, value) = message {
            controlChanges.record(MIDIInputControlChange(channel: channel,
                                                         controller: controller,
                                                         value: value))
            return
        }

        lock.lock()
        defer { lock.unlock() }

        guard let output else {
            droppedMessages += 1
            return
        }

        switch message {
        case let .noteOn(channel, note, velocity):
            // Gesperrter Weg: die Note wird verworfen, BEVOR sie klingt. Damit
            // kann kein noteOn mehr nach dem Aufraeumen durchrutschen und
            // haengen bleiben.
            guard !isSealed(path) else {
                droppedMessages += 1
                return
            }
            withBook(on: path) { $0.noteOn(channel: MIDIInputChannelPolicy.appChannel(forInputChannel: channel),
                                           note: note) }
            output.noteOn(channel: MIDIInputChannelPolicy.appChannel(forInputChannel: channel),
                          note: note,
                          velocity: velocity)

        case let .noteOff(channel, note):
            let appChannel = MIDIInputChannelPolicy.appChannel(forInputChannel: channel)
            _ = withBook(on: path) { $0.noteOff(channel: appChannel, note: note) }
            // Auch ohne passende Buchung und auch bei gesperrtem Weg
            // durchreichen: ein Off darf nie geschluckt werden.
            output.noteOff(channel: appChannel, note: note)

        case let .allNotesOff(channel):
            let appChannel = MIDIInputChannelPolicy.appChannel(forInputChannel: channel)
            withBook(on: path) { _ = $0.removeAll(channel: appChannel) }
            output.allNotesOff(channel: appChannel)

        case .controlChange:
            break   // oben behandelt
        }
    }

    // MARK: – Anti-Haenger-Pfad

    /// Beendet alle ueber `path` gestarteten Noten einzeln und leert dessen Buch.
    ///
    /// Quellenwechsel, abgezogenes Kabel, abgeschalteter Eingang. Bewusst
    /// gezielte `noteOff`-Aufrufe statt `allNotesOff()` — die vom Spiel selbst
    /// und die ueber den anderen Weg gehaltenen Noten bleiben unberuehrt.
    ///
    /// ── Das Lock wird ueber ALLE Note-Offs gehalten — bewusst (Runde 074) ──
    ///
    /// Diese Schleife haelt `lock` ueber N `output.noteOff()`-Aufrufe, jeder
    /// davon ein `commandQueue.async`. Der aufrufende Thread — real der
    /// CoreMIDI-Thread oder der Main Thread — blockiert solange, und ein
    /// gleichzeitig eintreffendes MIDI-Ereignis wartet an derselben Tuer.
    ///
    /// Das ist der bewusst gewaehlte Tausch, nicht ein uebersehener Fall:
    ///
    ///   – Der Preis ist beschraenkt und liegt nicht im Audio-Render-Thread.
    ///     N ist die Zahl der real gehaltenen externen Noten, praktisch
    ///     einstellig bis niedrig zweistellig; `commandQueue.async` reiht nur
    ///     ein und wartet nicht.
    ///   – Der Gegenwert ist die Invariante des Anti-Haenger-Pfads. Wuerde das
    ///     Lock zwischen "Buch geleert" und "Note-Offs gesendet" fallen,
    ///     entstuende genau das dritte Zeitfenster, das dieser Pfad
    ///     ausschliessen soll: ein `noteOn`, das die Sperre noch nicht sieht,
    ///     bucht und klingt — und wird von keinem Off mehr erreicht.
    ///   – Eine haengende Note ist ein Produktfehler, den nur ein Panic
    ///     beendet. Ein paar Mikrosekunden Blockade auf einem Nicht-Audio-
    ///     Thread ist keiner. Die Prioritaetenreihenfolge aus `CLAUDE.md`
    ///     (Korrektheit vor Komfort) entscheidet diesen Fall eindeutig.
    ///
    /// - Parameter sealing: sperrt den Weg im selben Atemzug. Der Aufrufer
    ///   trennt anschliessend die CoreMIDI-Verbindung. Weil Sperren und
    ///   Aufraeumen unter demselben Lock stehen wie das Buchen, gilt fuer jedes
    ///   `noteOn` genau eines von beiden: es wurde vollstaendig gebucht UND
    ///   ausgegeben, bevor gesperrt wurde — dann steht es im Buch und wird hier
    ///   beendet —, oder es sieht die Sperre und klingt nie. Ein drittes
    ///   Zeitfenster gibt es nicht.
    func releaseNotes(on path: MIDIInputPath, sealing: Bool = false) {
        lock.lock()
        defer { lock.unlock() }

        if sealing, path == .externalSource { isSourcePathSealed = true }

        let released = withBook(on: path) { $0.removeAll() }
        guard let output else { return }
        for key in released.sorted(by: { ($0.channel, $0.note) < ($1.channel, $1.note) }) {
            output.noteOff(channel: key.channel, note: key.note)
        }
    }

    /// Gibt einen gesperrten Weg wieder frei — nach erfolgreichem Verbinden
    /// einer Quelle.
    func unseal(_ path: MIDIInputPath) {
        guard path == .externalSource else { return }
        lock.lock()
        isSourcePathSealed = false
        lock.unlock()
    }

    /// Verwirft die Buchfuehrung beider Wege ohne eigene Note-Offs. Fuer den
    /// Fall, dass ein globales Panic (`AudioOutput.allNotesOff()`) die Noten
    /// bereits beendet hat — sonst blieben Karteileichen zurueck.
    func forgetAllExternalNotes() {
        lock.lock()
        _ = destinationBook.removeAll()
        _ = sourceBook.removeAll()
        lock.unlock()
    }

    // MARK: – Buchzugriff (immer mit gehaltenem Lock)

    private func isSealed(_ path: MIDIInputPath) -> Bool {
        path == .externalSource && isSourcePathSealed
    }

    private func book(on path: MIDIInputPath) -> MIDIInputNoteBook {
        switch path {
        case .virtualDestination: return destinationBook
        case .externalSource:     return sourceBook
        }
    }

    private func withBook<R>(on path: MIDIInputPath, _ body: (inout MIDIInputNoteBook) -> R) -> R {
        switch path {
        case .virtualDestination: return body(&destinationBook)
        case .externalSource:     return body(&sourceBook)
        }
    }
}
