import Combine
import CoreMIDI
import Foundation

// MARK: – MIDI-Eingang: CoreMIDI-Anbindung (Runde 073 / W-04)
//
// Zwei Wege fuehren herein, sie koexistieren:
//
//   1. Virtuelles Ziel "HarmonyEngine3D Input" (MIDIDestinationCreateWithProtocol)
//      — DAWs und andere Programme senden direkt an die App.
//   2. Eingangsport plus Verbindung zu einer externen Quelle
//      (MIDIInputPortCreateWithProtocol + MIDIPortConnectSource)
//      — Hardware-Controller.
//
// Der MIDI-AUSGANG (`MIDIManager`) bleibt unangetastet: eigener Client, eigene
// Endpunkte, kein gemeinsamer Zustand. Zwei CoreMIDI-Clients in einem Prozess
// sind zulaessig und halten die beiden Richtungen sauber getrennt.
//
// ── Threading ────────────────────────────────────────────────────────────────
//
// Die beiden Empfangsbloecke laufen auf CoreMIDI-eigenen Threads. Sie tun genau
// zwei Dinge: UMP-Wort dekodieren und `MIDIInputRouter.handle(_:)` aufrufen.
// Der Router ruft ausschliesslich das `AudioOutput`-Protokoll auf; bei
// `AudioEngine` legt dieses den Aufruf selbst auf `commandQueue`. Damit bleibt
// der SPSC-Vertrag der `NoteEventQueue` unveraendert: Producer ist weiterhin
// allein der commandQueue-Worker, nicht der CoreMIDI-Thread. Die Queue selbst
// wird nicht angefasst.
//
// Kosten dieses Weges: ein `DispatchQueue.async` pro Ereignis, also eine
// Closure-Allokation und ein Thread-Wechsel im MIDI-Callback. Das ist dort
// vertretbar — er ist nicht der Audio-Render-Thread, und die Latenz eines
// GCD-Hops liegt weit unter einem Audio-Block bei 48 kHz. Der direkte Weg in
// die Queue waere exakt der F-02-Fehler und ist bewusst nicht gegangen.
//
// Der eigene Zustand (Konfiguration, verbundene Quelle) ist per `NSLock`
// geschuetzt, weil er vom Main Thread geschrieben und vom CoreMIDI-Thread
// gelesen wird. Die `@Published`-Felder werden ausschliesslich auf dem Main
// Thread gesetzt.

//
// `MIDIInputManager` ist bewusst kein `@MainActor`-Typ: die beiden
// Empfangsbloecke muessen von CoreMIDI-Threads aus laufen duerfen. Alle
// uebrigen Methoden gehoeren auf den Main Thread (App Layer und UI rufen sie
// von dort), die `@Published`-Felder ohnehin.

// ── `@unchecked Sendable`: was hier behauptet wird (Nachtrag Runde 074) ──────
//
// Die Zusicherung gilt nicht global, sondern fuer genau die zwei Felder, die
// ein anderer Thread als der Main Thread ueberhaupt beruehrt:
//
//   – `isForwardingEnabled` wird vom Main Thread geschrieben (`apply`) und vom
//     CoreMIDI-Thread gelesen (`receive`), beides unter `stateLock`;
//   – `router` ist ein `let` auf eine Klasse, die ihren eigenen Zustand selbst
//     per `NSLock` schuetzt (siehe MIDIInputRouting.swift).
//
// Alles Uebrige — die drei `@Published`-Felder, die CoreMIDI-Handles
// (`client`, `virtualDestination`, `inputPort`, `connectedSource`,
// `connectedUniqueID`) und `currentConfig` — wird ausschliesslich vom Main
// Thread angefasst: `start`, `apply`, `refreshSources`, `handleSetupChanged`,
// `connect`, `disconnectCurrentSource`. Die beiden CoreMIDI-Callbacks lesen
// davon nichts.
//
// Das ist eine Behauptung ueber den aktuellen Code, kein Beweis: sie bricht,
// sobald ein CoreMIDI-Callback eines dieser Felder anfasst. Wer den
// Empfangspfad erweitert, prueft diese Liste mit.
//
// Die Annotation ist ausdruecklich NICHT dazu da, Warnungen wegzudruecken —
// sie beschreibt eine Invariante, die ohnehin schon galt und bisher nur
// nirgends stand.

final class MIDIInputManager: ObservableObject, @unchecked Sendable {

    // MARK: – Beobachtbarer Zustand (nur Main Thread)

    /// Auswaehlbare externe Quellen, ohne den eigenen virtuellen Ausgang.
    @Published private(set) var availableSources: [MIDIInputSourceDescriptor] = []

    /// Aufloesung der persistierten Auswahl gegen die reale Geraetelage.
    @Published private(set) var connectionState: MIDIInputConnectionState = .virtualOnly

    /// `true`, sobald Client und virtuelles Ziel stehen.
    @Published private(set) var isVirtualDestinationReady: Bool = false

    // MARK: – Routing

    let router: MIDIInputRouter

    // MARK: – CoreMIDI-Handles

    private var client:             MIDIClientRef   = 0
    private var virtualDestination: MIDIEndpointRef = 0
    private var inputPort:          MIDIPortRef     = 0
    private var connectedSource:    MIDIEndpointRef = 0
    private var connectedUniqueID:  Int32           = 0

    // MARK: – Vom CoreMIDI-Thread gelesener Zustand

    private let stateLock = NSLock()
    private var isForwardingEnabled = true

    /// Zuletzt angewandte Einstellung. Der Manager haelt sie selbst, statt
    /// `AppSettings` zu lesen — die Einstellungsquelle bleibt Sache des App
    /// Layers, hier zaehlt nur der zuletzt uebergebene Stand.
    private var currentConfig = MIDIInputConfig()

    init(output: (any AudioOutput)?) {
        self.router = MIDIInputRouter(output: output)
    }

    // MARK: – Start

    /// Erzeugt Client, virtuelles Ziel und Eingangsport und wendet die
    /// uebergebene Konfiguration an.
    ///
    /// Scheitert etwas davon, bleibt die App voll funktionsfaehig — der
    /// Eingang meldet sich dann nur als nicht bereit. Ein fehlender
    /// MIDI-Eingang ist kein Grund, das Instrument nicht zu starten.
    func start(config: MIDIInputConfig) {
        guard client == 0 else {
            apply(config: config)
            return
        }

        let notifyBlock: MIDINotifyBlock = { [weak self] notification in
            let messageID = notification.pointee.messageID
            // Jede Aenderung der Geraetelage: neu aufzaehlen und die Auswahl
            // neu aufloesen. Setup-Changed deckt An-/Abstecken mit ab, die
            // beiden Objekt-Nachrichten kommen bei einzelnen Endpunkten.
            guard messageID == .msgSetupChanged
                    || messageID == .msgObjectAdded
                    || messageID == .msgObjectRemoved else { return }
            DispatchQueue.main.async { self?.handleSetupChanged() }
        }

        var status = MIDIClientCreateWithBlock("HarmonyEngine3D Input Client" as CFString,
                                               &client,
                                               notifyBlock)
        guard status == noErr else {
            print("⚠️  MIDI-Eingang: Client konnte nicht erstellt werden (\(status))")
            client = 0
            return
        }

        // 1. Virtuelles Ziel — immer da, unabhaengig von der Quellenauswahl.
        status = MIDIDestinationCreateWithProtocol(
            client,
            MIDIEndpointNames.virtualDestination as CFString,
            ._1_0,
            &virtualDestination
        ) { [weak self] eventList, _ in
            self?.receive(eventList, from: .virtualDestination)
        }
        if status == noErr {
            isVirtualDestinationReady = true
            print("🎹 MIDI-Eingang bereit: virtuelles Ziel '\(MIDIEndpointNames.virtualDestination)'")
        } else {
            virtualDestination = 0
            print("⚠️  MIDI-Eingang: virtuelles Ziel konnte nicht erstellt werden (\(status))")
        }

        // 2. Eingangsport fuer externe Quellen.
        status = MIDIInputPortCreateWithProtocol(
            client,
            "HarmonyEngine3D Input Port" as CFString,
            ._1_0,
            &inputPort
        ) { [weak self] eventList, _ in
            self?.receive(eventList, from: .externalSource)
        }
        if status != noErr {
            inputPort = 0
            print("⚠️  MIDI-Eingang: Eingangsport konnte nicht erstellt werden (\(status))")
        }

        refreshSources()
        apply(config: config)
    }

    // MARK: – Konfiguration anwenden

    /// Uebernimmt eine geaenderte Einstellung: Quellenwechsel, Ein-/Ausschalten.
    /// Wird vom App Layer aus der `AppSettings`-Subscription gerufen.
    func apply(config: MIDIInputConfig) {
        currentConfig = config
        stateLock.lock()
        isForwardingEnabled = config.isEnabled
        stateLock.unlock()

        // Abgeschalteter Eingang darf keine klingende Note zuruecklassen.
        if !config.isEnabled {
            disconnectCurrentSource(releaseNotes: true)
            connectionState = .disabled
            return
        }

        let target = MIDIInputSourceResolver.resolve(config: config, available: availableSources)

        // Der gemeldete Zustand ist das ERGEBNIS des Verbindungsversuchs, nicht
        // die aufgeloeste Absicht: ein Geraet, das in der Liste steht, sich aber
        // nicht verbinden laesst, darf nicht als "verbunden" angezeigt werden.
        switch target {
        case .connected(let descriptor):
            if connectedUniqueID == descriptor.uniqueID {
                connectionState = .connected(descriptor)
            } else {
                disconnectCurrentSource(releaseNotes: true)
                connectionState = connect(to: descriptor)
                    ? .connected(descriptor)
                    : .unavailable(uniqueID: descriptor.uniqueID, name: descriptor.displayName)
            }
        case .virtualOnly, .unavailable, .disabled:
            disconnectCurrentSource(releaseNotes: true)
            connectionState = target
        }

        log(state: connectionState)
    }

    /// Zaehlt die real vorhandenen Quellen neu auf.
    func refreshSources() {
        var found: [MIDIInputSourceDescriptor] = []
        let count = MIDIGetNumberOfSources()
        for index in 0..<count {
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0 else { continue }
            found.append(MIDIInputSourceDescriptor(uniqueID: Self.uniqueID(of: endpoint),
                                                   displayName: Self.displayName(of: endpoint)))
        }
        availableSources = MIDIInputSourceFilter.selectable(from: found)
    }

    /// Beendet alle extern gestarteten Noten. Fuer den globalen Panic-Pfad:
    /// dort hat `AudioOutput.allNotesOff()` die Noten bereits beendet, hier
    /// wird nur die Buchfuehrung mitgezogen, damit keine Karteileiche bleibt.
    func forgetExternalNotesAfterGlobalPanic() {
        router.forgetAllExternalNotes()
    }

    // MARK: – Geraetelage geaendert

    private func handleSetupChanged() {
        let previousUniqueID = connectedUniqueID
        refreshSources()

        // Verbundene Quelle verschwunden (Kabel raus, DAW geschlossen):
        // Verbindung sauber loesen UND jede extern gestartete Note beenden.
        // Ohne das haengt die zuletzt gedrueckte Taste fuer immer.
        if previousUniqueID != 0,
           !availableSources.contains(where: { $0.uniqueID == previousUniqueID }) {
            print("🎹 MIDI-Eingang: Quelle \(previousUniqueID) ist verschwunden — Noten werden beendet")
            disconnectCurrentSource(releaseNotes: true)
        }

        apply(config: currentConfig)
    }

    // MARK: – Verbinden / Trennen

    /// - Returns: `true`, wenn die Verbindung wirklich steht.
    @discardableResult
    private func connect(to descriptor: MIDIInputSourceDescriptor) -> Bool {
        guard inputPort != 0 else {
            print("⚠️  MIDI-Eingang: kein Eingangsport — '\(descriptor.displayName)' bleibt unverbunden")
            return false
        }
        guard let endpoint = Self.endpoint(forUniqueID: descriptor.uniqueID) else {
            print("⚠️  MIDI-Eingang: Quelle '\(descriptor.displayName)' nicht mehr auffindbar")
            return false
        }

        let status = MIDIPortConnectSource(inputPort, endpoint, nil)
        guard status == noErr else {
            print("⚠️  MIDI-Eingang: Verbindung zu '\(descriptor.displayName)' fehlgeschlagen (\(status))")
            return false
        }

        connectedSource   = endpoint
        connectedUniqueID = descriptor.uniqueID
        router.unseal(.externalSource)
        return true
    }

    /// Loest die bestehende Verbindung zur externen Quelle.
    ///
    /// Reihenfolge ist hier die ganze Miete: **erst sperren und aufraeumen,
    /// dann trennen.** `releaseNotes(on:sealing:)` sperrt den Quellweg unter
    /// demselben Lock, unter dem der CoreMIDI-Thread bucht und ausgibt. Ab
    /// diesem Moment kann kein `noteOn` dieses Weges mehr klingen — auch kein
    /// Ereignis, das CoreMIDI gerade noch nebenlaeufig zustellt. Erst danach
    /// wird die Verbindung geloest. Umgekehrt (erst trennen, dann aufraeumen)
    /// bliebe ein Fenster, in dem ein zugestelltes `noteOn` nach dem
    /// Aufraeumen bucht und fuer immer klaenge.
    ///
    /// Das virtuelle Ziel bleibt unberuehrt: eine DAW, die gerade Noten haelt,
    /// verliert sie nicht, weil am Keyboard das Kabel gezogen wurde.
    private func disconnectCurrentSource(releaseNotes: Bool) {
        if releaseNotes {
            router.releaseNotes(on: .externalSource, sealing: true)
        }
        guard connectedSource != 0 else {
            connectedUniqueID = 0
            return
        }
        if inputPort != 0 {
            // Fehler bewusst ignoriert: ist der Endpunkt schon weg, ist das
            // Ziel (keine Verbindung mehr) bereits erreicht.
            MIDIPortDisconnectSource(inputPort, connectedSource)
        }
        connectedSource   = 0
        connectedUniqueID = 0
    }

    // MARK: – Empfang (CoreMIDI-Thread)

    private func receive(_ eventList: UnsafePointer<MIDIEventList>, from path: MIDIInputPath) {
        stateLock.lock()
        let enabled = isForwardingEnabled
        stateLock.unlock()
        guard enabled else { return }

        for packet in eventList.unsafeSequence() {
            for word in packet.words() {
                guard let message = MIDIInputDecoder.message(fromWord: word) else { continue }
                router.handle(message, from: path)
            }
        }
    }

    // MARK: – CoreMIDI-Eigenschaften

    private static func uniqueID(of endpoint: MIDIEndpointRef) -> Int32 {
        var value: Int32 = 0
        let status = MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &value)
        return status == noErr ? value : 0
    }

    private static func displayName(of endpoint: MIDIEndpointRef) -> String {
        var name: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name)
        guard status == noErr, let name else { return "MIDI-Quelle" }
        return name.takeRetainedValue() as String
    }

    private static func endpoint(forUniqueID uniqueID: Int32) -> MIDIEndpointRef? {
        let count = MIDIGetNumberOfSources()
        for index in 0..<count {
            let endpoint = MIDIGetSource(index)
            if endpoint != 0, Self.uniqueID(of: endpoint) == uniqueID { return endpoint }
        }
        return nil
    }

    private func log(state: MIDIInputConnectionState) {
        switch state {
        case .disabled:
            print("🎹 MIDI-Eingang: abgeschaltet")
        case .virtualOnly:
            print("🎹 MIDI-Eingang: nur virtuelles Ziel '\(MIDIEndpointNames.virtualDestination)'")
        case .connected(let descriptor):
            print("🎹 MIDI-Eingang: verbunden mit '\(descriptor.displayName)'")
        case .unavailable(let uniqueID, let name):
            let shown = name.isEmpty ? "\(uniqueID)" : name
            print("🎹 MIDI-Eingang: gewaehlte Quelle '\(shown)' ist nicht verfuegbar — Auswahl bleibt gespeichert")
        }
    }
}
