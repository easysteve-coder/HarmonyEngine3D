import XCTest
@testable import HarmonyEngine3D

// MARK: – Tests: MIDI-Eingang, reine Routing-Schicht (Runde 073 / W-04)
//
// Deckt ab: UMP-Dekodierung inkl. Velocity-0-Konvention, Kanal-Politik,
// Quellenfilter und -aufloesung, getrennte Notenbuchfuehrung je Eingangsweg,
// On-Off-Symmetrie extern gestarteter Noten (auch bei Quellenverlust und
// Panic), die Nebenlaeufigkeit des Anti-Haenger-Pfads sowie die
// CC-Bereitstellung fuer W-05.
//
// Bewusst ohne CoreMIDI: die gesamte Entscheidungslogik ist geraetefrei
// pruefbar; die CoreMIDI-Anbindung selbst bleibt dem manuellen Test vorbehalten.

// MARK: – Test-Output

/// Protokolliert alle AudioOutput-Aufrufe in Reihenfolge.
private final class RecordingAudioOutput: AudioOutput {

    enum Call: Equatable {
        case noteOn(channel: Int, note: UInt8, velocity: UInt8)
        case noteOff(channel: Int, note: UInt8)
        case allNotesOffChannel(Int)
        case allNotesOffGlobal
    }

    private(set) var calls: [Call] = []

    func noteOn(channel: Int, note: UInt8, velocity: UInt8) {
        calls.append(.noteOn(channel: channel, note: note, velocity: velocity))
    }

    func noteOff(channel: Int, note: UInt8) {
        calls.append(.noteOff(channel: channel, note: note))
    }

    func allNotesOff(channel: Int) {
        calls.append(.allNotesOffChannel(channel))
    }

    func allNotesOff() {
        calls.append(.allNotesOffGlobal)
    }

    func applyFXConfig(_ cfg: ChannelFXConfig, channel: Int) {}
}

// MARK: – Dekoder

final class MIDIInputDecoderTests: XCTestCase {

    /// Baut ein UMP-Wort vom Message Type 2 (MIDI 1.0 Channel Voice), genau so
    /// wie CoreMIDI es an einen `MIDIProtocolID._1_0`-Empfaenger liefert.
    private func channelVoiceWord(_ status: UInt8, _ data1: UInt8, _ data2: UInt8,
                                  group: UInt8 = 0) -> UInt32 {
        (UInt32(0x2) << 28)
            | (UInt32(group)  << 24)
            | (UInt32(status) << 16)
            | (UInt32(data1)  << 8)
            |  UInt32(data2)
    }

    func testNoteOnAndNoteOffAreDecodedWithChannelAndVelocity() {
        XCTAssertEqual(MIDIInputDecoder.message(fromWord: channelVoiceWord(0x92, 60, 100)),
                       .noteOn(channel: 2, note: 60, velocity: 100))
        XCTAssertEqual(MIDIInputDecoder.message(fromWord: channelVoiceWord(0x82, 60, 64)),
                       .noteOff(channel: 2, note: 60))
    }

    func testNoteOnWithVelocityZeroIsDecodedAsNoteOff() {
        XCTAssertEqual(MIDIInputDecoder.message(fromWord: channelVoiceWord(0x90, 64, 0)),
                       .noteOff(channel: 0, note: 64))
    }

    func testControlChangeIsDecodedWithRawChannel() {
        XCTAssertEqual(MIDIInputDecoder.message(fromWord: channelVoiceWord(0xB3, 74, 42)),
                       .controlChange(channel: 3, controller: 74, value: 42))
    }

    func testChannelModeMessagesWithNoteEffectDecodeAsAllNotesOff() {
        for controller: UInt8 in [120, 123, 124, 125, 126, 127] {
            XCTAssertEqual(MIDIInputDecoder.message(fromWord: channelVoiceWord(0xB1, controller, 0)),
                           .allNotesOff(channel: 1),
                           "CC \(controller) muss Notenwirkung haben")
        }
    }

    func testResetAllControllersAndLocalControlAreIgnored() {
        XCTAssertNil(MIDIInputDecoder.message(fromWord: channelVoiceWord(0xB0, 121, 0)))
        XCTAssertNil(MIDIInputDecoder.message(fromWord: channelVoiceWord(0xB0, 122, 0)))
    }

    func testMessagesOutsideTheW04ScopeAreIgnoredInsteadOfMisread() {
        // Polyphoner Aftertouch, Program Change, Channel Pressure, Pitch Bend.
        for status: UInt8 in [0xA0, 0xC0, 0xD0, 0xE0] {
            XCTAssertNil(MIDIInputDecoder.message(fromWord: channelVoiceWord(status, 60, 100)),
                         "Status 0x\(String(status, radix: 16)) darf keine Note erzeugen")
        }
    }

    func testNonChannelVoiceMessageTypesAreIgnored() {
        // Utility (0x0), System Realtime/Common (0x1), SysEx-Daten (0x3),
        // MIDI-2.0-Channel-Voice (0x4): kein Wort davon darf als Note gelten.
        for messageType: UInt32 in [0x0, 0x1, 0x3, 0x4, 0x5] {
            let word = (messageType << 28) | (0x90 << 16) | (60 << 8) | 100
            XCTAssertNil(MIDIInputDecoder.message(fromWord: word),
                         "Message Type \(messageType) darf nicht als Channel Voice gelten")
        }
    }

    func testGroupIsIgnored() {
        // Eine klassische MIDI-Verbindung erzeugt Group 0; andere Groups
        // duerfen trotzdem nicht verloren gehen.
        for group: UInt8 in [0, 1, 7, 15] {
            XCTAssertEqual(MIDIInputDecoder.message(fromWord: channelVoiceWord(0x90, 60, 100, group: group)),
                           .noteOn(channel: 0, note: 60, velocity: 100))
        }
    }

    func testStatusTripleDecodingMatchesTheWordPath() {
        XCTAssertEqual(MIDIInputDecoder.message(status: 0x91, data1: 62, data2: 80),
                       MIDIInputDecoder.message(fromWord: channelVoiceWord(0x91, 62, 80)))
    }
}

// MARK: – Quellenfilter

final class MIDIInputSourceFilterTests: XCTestCase {

    func testOwnVirtualOutputIsNotSelectableAsInputSource() {
        let sources = [
            MIDIInputSourceDescriptor(uniqueID: 1, displayName: MIDIEndpointNames.virtualSource),
            MIDIInputSourceDescriptor(uniqueID: 2, displayName: "Launchkey 49")
        ]
        // Sonst schickte sich der Eingang im MIDI-Ausgabemodus seine eigenen
        // Ereignisse endlos wieder zu.
        XCTAssertEqual(MIDIInputSourceFilter.selectable(from: sources).map(\.displayName),
                       ["Launchkey 49"])
    }

    func testEndpointsWithoutUniqueIDAreDropped() {
        let sources = [
            MIDIInputSourceDescriptor(uniqueID: 0, displayName: "Namenlos"),
            MIDIInputSourceDescriptor(uniqueID: 2, displayName: "KeyStep")
        ]
        XCTAssertEqual(MIDIInputSourceFilter.selectable(from: sources).map(\.uniqueID), [2])
    }

    func testEmptyListStaysEmpty() {
        XCTAssertTrue(MIDIInputSourceFilter.selectable(from: []).isEmpty)
    }
}

// MARK: – Kanal-Politik

final class MIDIInputChannelPolicyTests: XCTestCase {

    func testChannelsOneToFourMapToTheFourAppChannels() {
        XCTAssertEqual(MIDIInputChannelPolicy.appChannel(forInputChannel: 0), 0)
        XCTAssertEqual(MIDIInputChannelPolicy.appChannel(forInputChannel: 1), 1)
        XCTAssertEqual(MIDIInputChannelPolicy.appChannel(forInputChannel: 2), 2)
        XCTAssertEqual(MIDIInputChannelPolicy.appChannel(forInputChannel: 3), 3)
    }

    func testRemainingChannelsFallBackInsteadOfBeingDroppedSilently() {
        for channel in 4...15 {
            XCTAssertEqual(MIDIInputChannelPolicy.appChannel(forInputChannel: channel),
                           MIDIInputChannelPolicy.fallbackChannel)
        }
    }
}

// MARK: – Quellenauswahl

final class MIDIInputSourceResolverTests: XCTestCase {

    private let launchkey = MIDIInputSourceDescriptor(uniqueID: 4711, displayName: "Launchkey 49")
    private let keystep   = MIDIInputSourceDescriptor(uniqueID: 1234, displayName: "KeyStep")

    func testDisabledInputWins() {
        var cfg = MIDIInputConfig()
        cfg.isEnabled = false
        cfg.selectedSourceUniqueID = 4711
        XCTAssertEqual(MIDIInputSourceResolver.resolve(config: cfg, available: [launchkey]), .disabled)
    }

    func testNoSelectionMeansVirtualDestinationOnly() {
        let cfg = MIDIInputConfig()
        XCTAssertEqual(MIDIInputSourceResolver.resolve(config: cfg, available: [launchkey]), .virtualOnly)
    }

    func testSelectedSourcePresentResolvesToConnected() {
        var cfg = MIDIInputConfig()
        cfg.selectedSourceUniqueID = 4711
        cfg.selectedSourceName     = "Launchkey 49"
        XCTAssertEqual(MIDIInputSourceResolver.resolve(config: cfg, available: [keystep, launchkey]),
                       .connected(launchkey))
    }

    func testMissingDeviceResolvesToUnavailableAndKeepsTheSelection() {
        var cfg = MIDIInputConfig()
        cfg.selectedSourceUniqueID = 4711
        cfg.selectedSourceName     = "Launchkey 49"
        XCTAssertEqual(MIDIInputSourceResolver.resolve(config: cfg, available: [keystep]),
                       .unavailable(uniqueID: 4711, name: "Launchkey 49"))
        // Die Auswahl selbst bleibt unangetastet — ein abgezogenes Geraet
        // loescht die Einstellung nicht.
        XCTAssertEqual(cfg.selectedSourceUniqueID, 4711)
    }

    func testEmptySourceListDoesNotCrashAndStaysUnavailable() {
        var cfg = MIDIInputConfig()
        cfg.selectedSourceUniqueID = 4711
        XCTAssertEqual(MIDIInputSourceResolver.resolve(config: cfg, available: []),
                       .unavailable(uniqueID: 4711, name: ""))
    }

    func testUniqueIDZeroIsTreatedAsNoSelection() {
        var cfg = MIDIInputConfig()
        cfg.selectedSourceUniqueID = 0   // kMIDIInvalidUniqueID
        XCTAssertEqual(MIDIInputSourceResolver.resolve(config: cfg, available: [launchkey]), .virtualOnly)
    }
}

// MARK: – Notenbuch

final class MIDIInputNoteBookTests: XCTestCase {

    func testNoteOnAndNoteOffBalance() {
        var book = MIDIInputNoteBook()
        book.noteOn(channel: 0, note: 60)
        book.noteOn(channel: 0, note: 64)
        XCTAssertEqual(book.count, 2)
        XCTAssertTrue(book.noteOff(channel: 0, note: 60))
        XCTAssertEqual(book.count, 1)
        XCTAssertFalse(book.noteOff(channel: 0, note: 99), "Off ohne On ist keine Buchung")
    }

    func testSameNoteOnDifferentChannelsIsTrackedSeparately() {
        var book = MIDIInputNoteBook()
        book.noteOn(channel: 0, note: 60)
        book.noteOn(channel: 3, note: 60)
        XCTAssertEqual(book.count, 2)
        XCTAssertTrue(book.noteOff(channel: 0, note: 60))
        XCTAssertEqual(book.count, 1)
    }

    func testRetriggerOfTheSameNoteStaysOneBooking() {
        var book = MIDIInputNoteBook()
        book.noteOn(channel: 0, note: 60)
        book.noteOn(channel: 0, note: 60)
        XCTAssertEqual(book.count, 1)
        XCTAssertTrue(book.noteOff(channel: 0, note: 60))
        XCTAssertTrue(book.isEmpty)
    }

    func testRemoveAllOnChannelLeavesOtherChannelsUntouched() {
        var book = MIDIInputNoteBook()
        book.noteOn(channel: 0, note: 60)
        book.noteOn(channel: 1, note: 40)
        let removed = book.removeAll(channel: 0)
        XCTAssertEqual(removed, [MIDIInputNoteBook.Key(channel: 0, note: 60)])
        XCTAssertEqual(book.count, 1)
    }

    func testRemoveAllReturnsEverythingAndEmptiesTheBook() {
        var book = MIDIInputNoteBook()
        book.noteOn(channel: 0, note: 60)
        book.noteOn(channel: 2, note: 72)
        XCTAssertEqual(Set(book.removeAll()), [
            MIDIInputNoteBook.Key(channel: 0, note: 60),
            MIDIInputNoteBook.Key(channel: 2, note: 72)
        ])
        XCTAssertTrue(book.isEmpty)
    }
}

// MARK: – Router: On-Off-Symmetrie

final class MIDIInputRouterTests: XCTestCase {

    func testNoteOnReachesTheOutputWithVelocityAndMappedChannel() {
        let output = RecordingAudioOutput()
        let router = MIDIInputRouter(output: output)

        router.handle(.noteOn(channel: 2, note: 60, velocity: 96), from: .externalSource)

        XCTAssertEqual(output.calls, [.noteOn(channel: 2, note: 60, velocity: 96)])
        XCTAssertEqual(router.activeExternalNoteCount, 1)
    }

    func testChannelAboveFourIsFoldedOntoTheFallbackChannel() {
        let output = RecordingAudioOutput()
        let router = MIDIInputRouter(output: output)

        router.handle(.noteOn(channel: 9, note: 60, velocity: 96), from: .externalSource)
        router.handle(.noteOff(channel: 9, note: 60), from: .externalSource)

        XCTAssertEqual(output.calls, [
            .noteOn(channel: MIDIInputChannelPolicy.fallbackChannel, note: 60, velocity: 96),
            .noteOff(channel: MIDIInputChannelPolicy.fallbackChannel, note: 60)
        ])
        XCTAssertEqual(router.activeExternalNoteCount, 0)
    }

    func testNoteOffClearsTheBooking() {
        let output = RecordingAudioOutput()
        let router = MIDIInputRouter(output: output)

        router.handle(.noteOn(channel: 0, note: 60, velocity: 96), from: .externalSource)
        router.handle(.noteOff(channel: 0, note: 60), from: .externalSource)

        XCTAssertEqual(router.activeExternalNoteCount, 0)
        XCTAssertEqual(output.calls, [
            .noteOn(channel: 0, note: 60, velocity: 96),
            .noteOff(channel: 0, note: 60)
        ])
    }

    func testNoteOffWithoutMatchingNoteOnIsStillForwarded() {
        let output = RecordingAudioOutput()
        let router = MIDIInputRouter(output: output)

        router.handle(.noteOff(channel: 0, note: 60), from: .externalSource)

        XCTAssertEqual(output.calls, [.noteOff(channel: 0, note: 60)])
    }

    func testReleaseAllExternalNotesEndsEveryHeldNoteExactlyOnce() {
        let output = RecordingAudioOutput()
        let router = MIDIInputRouter(output: output)

        router.handle(.noteOn(channel: 0, note: 60, velocity: 96), from: .externalSource)
        router.handle(.noteOn(channel: 0, note: 64, velocity: 96), from: .externalSource)
        router.handle(.noteOn(channel: 1, note: 40, velocity: 96), from: .externalSource)

        // Entspricht dem Abziehen der Quelle bzw. dem Quellenwechsel.
        router.releaseNotes(on: .externalSource)

        XCTAssertEqual(router.activeExternalNoteCount, 0)
        XCTAssertEqual(output.calls.suffix(3), [
            .noteOff(channel: 0, note: 60),
            .noteOff(channel: 0, note: 64),
            .noteOff(channel: 1, note: 40)
        ])

        // Zweiter Aufruf darf nichts mehr senden — kein doppeltes Off.
        let countAfterFirstRelease = output.calls.count
        router.releaseNotes(on: .externalSource)
        XCTAssertEqual(output.calls.count, countAfterFirstRelease)
    }

    func testReleaseAllUsesTargetedNoteOffsAndNeverGlobalPanic() {
        let output = RecordingAudioOutput()
        let router = MIDIInputRouter(output: output)

        router.handle(.noteOn(channel: 0, note: 60, velocity: 96), from: .externalSource)
        router.releaseNotes(on: .externalSource)

        // Die vom Spiel selbst gehaltenen Noten duerfen dabei nicht sterben.
        XCTAssertFalse(output.calls.contains(.allNotesOffGlobal))
    }

    func testIncomingAllNotesOffClearsOnlyThatChannel() {
        let output = RecordingAudioOutput()
        let router = MIDIInputRouter(output: output)

        router.handle(.noteOn(channel: 0, note: 60, velocity: 96), from: .externalSource)
        router.handle(.noteOn(channel: 1, note: 40, velocity: 96), from: .externalSource)
        router.handle(.allNotesOff(channel: 0), from: .externalSource)

        XCTAssertEqual(router.activeExternalNoteCount, 1)
        XCTAssertEqual(output.calls.last, .allNotesOffChannel(0))
    }

    func testForgetAllExternalNotesDropsBookkeepingWithoutSendingOffs() {
        let output = RecordingAudioOutput()
        let router = MIDIInputRouter(output: output)

        router.handle(.noteOn(channel: 0, note: 60, velocity: 96), from: .externalSource)
        let callCount = output.calls.count

        // Globales Panic hat die Noten bereits beendet — hier darf kein
        // zusaetzliches Off mehr rausgehen, aber auch keine Karteileiche bleiben.
        router.forgetAllExternalNotes()

        XCTAssertEqual(router.activeExternalNoteCount, 0)
        XCTAssertEqual(output.calls.count, callCount)
    }

    func testMessagesAreCountedAsDroppedWhenNoOutputIsAttached() {
        let router = MIDIInputRouter(output: nil)
        router.handle(.noteOn(channel: 0, note: 60, velocity: 96), from: .externalSource)
        XCTAssertEqual(router.droppedMessageCount, 1)
        XCTAssertEqual(router.activeExternalNoteCount, 0)
    }

    /// Ende-zu-Ende ueber den Dekoder: eine gedrueckte und wieder losgelassene
    /// Taste darf keine klingende Note zuruecklassen.
    func testDecodedInputStreamLeavesNoHangingNote() {
        let output = RecordingAudioOutput()
        let router = MIDIInputRouter(output: output)

        func word(_ status: UInt8, _ d1: UInt8, _ d2: UInt8) -> UInt32 {
            (UInt32(0x2) << 28) | (UInt32(status) << 16) | (UInt32(d1) << 8) | UInt32(d2)
        }

        // Taste an (MIDI-Kanal 1), Taste aus per Velocity-0-Konvention.
        for w in [word(0x90, 60, 100), word(0x90, 60, 0)] {
            if let message = MIDIInputDecoder.message(fromWord: w) {
                router.handle(message, from: .externalSource)
            }
        }

        XCTAssertEqual(output.calls, [
            .noteOn(channel: 0, note: 60, velocity: 100),
            .noteOff(channel: 0, note: 60)
        ])
        XCTAssertEqual(router.activeExternalNoteCount, 0)
    }
}

// MARK: – Control Changes fuer W-05

final class MIDIControlChangeRegistryTests: XCTestCase {

    func testControlChangesAreStoredButNotMappedToAnyParameter() {
        let output = RecordingAudioOutput()
        let router = MIDIInputRouter(output: output)

        router.handle(.controlChange(channel: 0, controller: 74, value: 100), from: .externalSource)

        XCTAssertEqual(router.controlChanges.latestValue(channel: 0, controller: 74), 100)
        // W-04 bildet ausdruecklich nichts ab: kein Ton, kein Output-Aufruf.
        XCTAssertTrue(output.calls.isEmpty)
    }

    func testLatestValueWins() {
        let registry = MIDIControlChangeRegistry()
        registry.record(MIDIInputControlChange(channel: 0, controller: 1, value: 10))
        registry.record(MIDIInputControlChange(channel: 0, controller: 1, value: 90))
        XCTAssertEqual(registry.latestValue(channel: 0, controller: 1), 90)
    }

    func testChannelAndControllerAreKeyedSeparately() {
        let registry = MIDIControlChangeRegistry()
        registry.record(MIDIInputControlChange(channel: 0, controller: 1, value: 10))
        registry.record(MIDIInputControlChange(channel: 5, controller: 1, value: 20))
        registry.record(MIDIInputControlChange(channel: 0, controller: 2, value: 30))
        XCTAssertEqual(registry.latestValue(channel: 0, controller: 1), 10)
        XCTAssertEqual(registry.latestValue(channel: 5, controller: 1), 20)
        XCTAssertEqual(registry.latestValue(channel: 0, controller: 2), 30)
        XCTAssertNil(registry.latestValue(channel: 1, controller: 1))
    }

    func testObserverReceivesEveryChangeInOrder() {
        let registry = MIDIControlChangeRegistry()
        var seen: [MIDIInputControlChange] = []
        registry.setObserver { seen.append($0) }

        registry.record(MIDIInputControlChange(channel: 0, controller: 74, value: 1))
        registry.record(MIDIInputControlChange(channel: 0, controller: 74, value: 2))

        XCTAssertEqual(seen, [
            MIDIInputControlChange(channel: 0, controller: 74, value: 1),
            MIDIInputControlChange(channel: 0, controller: 74, value: 2)
        ])
    }

    func testSnapshotIsStablySorted() {
        let registry = MIDIControlChangeRegistry()
        registry.record(MIDIInputControlChange(channel: 1, controller: 5, value: 1))
        registry.record(MIDIInputControlChange(channel: 0, controller: 9, value: 2))
        registry.record(MIDIInputControlChange(channel: 0, controller: 3, value: 3))

        XCTAssertEqual(registry.snapshot(), [
            MIDIInputControlChange(channel: 0, controller: 3, value: 3),
            MIDIInputControlChange(channel: 0, controller: 9, value: 2),
            MIDIInputControlChange(channel: 1, controller: 5, value: 1)
        ])
    }
}

// MARK: – Nebenlaeufigkeit des Anti-Haenger-Pfads

/// Output, der beim `noteOn` eine Gegenprobe von einem anderen Thread ausloest.
private final class ReentrantProbeOutput: AudioOutput {

    var onNoteOn: (() -> Void)?

    private let lock = NSLock()
    private var recorded: [String] = []

    var calls: [String] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    func noteOn(channel: Int, note: UInt8, velocity: UInt8) {
        lock.lock(); recorded.append("on \(channel)/\(note)"); lock.unlock()
        onNoteOn?()
    }

    func noteOff(channel: Int, note: UInt8) {
        lock.lock(); recorded.append("off \(channel)/\(note)"); lock.unlock()
    }

    func allNotesOff(channel: Int) {
        lock.lock(); recorded.append("allOff \(channel)"); lock.unlock()
    }

    func allNotesOff() {
        lock.lock(); recorded.append("allOff"); lock.unlock()
    }

    func applyFXConfig(_ cfg: ChannelFXConfig, channel: Int) {}
}

final class MIDIInputRouterConcurrencyTests: XCTestCase {

    /// Der Kern der Absicherung: Buchung und Ausgabe eines `noteOn` liegen in
    /// derselben kritischen Sektion.
    ///
    /// Nachweis ohne Zeitfenster-Raten: waehrend `output.noteOn` laeuft, wird
    /// von einem zweiten Thread `releaseNotes(on:sealing:)` gestartet. Steht
    /// die Ausgabe unter demselben Lock wie die Buchung, kann der Release nicht
    /// durchlaufen, solange wir hier stehen — er muss in den Timeout laufen.
    /// Laege die Ausgabe ausserhalb des Locks, liefe er sofort durch, raeumte
    /// das Buch und sendete sein `noteOff` VOR dem noch ausstehenden `noteOn`.
    /// Genau diese Inversion haengt die Note fuer immer.
    func testNoteOnIsEmittedWhileTheBookkeepingLockIsHeld() {
        let output = ReentrantProbeOutput()
        let router = MIDIInputRouter(output: output)

        let releaseFinished = DispatchSemaphore(value: 0)
        var releaseCompletedDuringNoteOn = true

        output.onNoteOn = {
            DispatchQueue.global().async {
                router.releaseNotes(on: .externalSource, sealing: true)
                releaseFinished.signal()
            }
            releaseCompletedDuringNoteOn = releaseFinished.wait(timeout: .now() + 0.4) == .success
        }

        router.handle(.noteOn(channel: 0, note: 60, velocity: 100), from: .externalSource)

        XCTAssertFalse(releaseCompletedDuringNoteOn,
                       "Der Release darf nicht zwischen Buchung und Ausgabe schluepfen koennen")

        // Der Release laeuft nach dem Verlassen der kritischen Sektion durch und
        // beendet die Note ordnungsgemaess.
        XCTAssertEqual(releaseFinished.wait(timeout: .now() + 2.0), .success)
        XCTAssertEqual(output.calls, ["on 0/60", "off 0/60"])
        XCTAssertEqual(router.activeExternalNoteCount, 0)
    }

    /// Lastprobe ueber den echten Ablauf: ein Thread spielt Noten, ein zweiter
    /// zieht mittendrin das Kabel. Danach darf keine einzige Note klingen
    /// bleiben — nachgerechnet ueber die tatsaechliche Aufrufreihenfolge.
    func testNoNoteSurvivesAConcurrentSourceRemoval() {
        for round in 0..<12 {
            let output = ReentrantProbeOutput()
            let router = MIDIInputRouter(output: output)
            let started = DispatchSemaphore(value: 0)

            let player = Thread {
                started.signal()
                for i in 0..<600 {
                    router.handle(.noteOn(channel: 0, note: UInt8(60 + i % 8), velocity: 100),
                                  from: .externalSource)
                }
            }
            player.start()
            started.wait()
            // Zeitpunkt des Kabelzugs ueber die Runden variieren.
            Thread.sleep(forTimeInterval: Double(round) * 0.0004)
            router.releaseNotes(on: .externalSource, sealing: true)
            while !player.isFinished { Thread.sleep(forTimeInterval: 0.002) }

            // Aufrufliste nachspielen: was am Ende noch "on" ist, haengt.
            var sounding = Set<String>()
            for call in output.calls {
                if call.hasPrefix("on ")  { sounding.insert(String(call.dropFirst(3))) }
                if call.hasPrefix("off ") { sounding.remove(String(call.dropFirst(4))) }
            }
            XCTAssertTrue(sounding.isEmpty,
                          "Runde \(round): haengende Noten nach Quellenverlust: \(sounding.sorted())")
            XCTAssertEqual(router.activeExternalNoteCount, 0)
        }
    }
}

// MARK: – Getrennte Eingangswege

final class MIDIInputPathSeparationTests: XCTestCase {

    func testSealedSourcePathDropsNoteOnBeforeItSounds() {
        let output = RecordingAudioOutput()
        let router = MIDIInputRouter(output: output)

        router.releaseNotes(on: .externalSource, sealing: true)
        router.handle(.noteOn(channel: 0, note: 60, velocity: 100), from: .externalSource)

        XCTAssertTrue(output.calls.isEmpty, "Eine gesperrte Note darf nie klingen")
        XCTAssertEqual(router.activeExternalNoteCount, 0)
        XCTAssertTrue(router.isExternalSourcePathSealed)
    }

    func testSealNeverSwallowsANoteOff() {
        let output = RecordingAudioOutput()
        let router = MIDIInputRouter(output: output)

        router.releaseNotes(on: .externalSource, sealing: true)
        router.handle(.noteOff(channel: 0, note: 60), from: .externalSource)

        XCTAssertEqual(output.calls, [.noteOff(channel: 0, note: 60)])
    }

    func testVirtualDestinationIsNeverSealed() {
        let output = RecordingAudioOutput()
        let router = MIDIInputRouter(output: output)

        router.releaseNotes(on: .externalSource, sealing: true)
        router.handle(.noteOn(channel: 0, note: 60, velocity: 100), from: .virtualDestination)

        XCTAssertEqual(output.calls, [.noteOn(channel: 0, note: 60, velocity: 100)])
    }

    func testUnsealRestoresTheSourcePath() {
        let output = RecordingAudioOutput()
        let router = MIDIInputRouter(output: output)

        router.releaseNotes(on: .externalSource, sealing: true)
        router.unseal(.externalSource)
        router.handle(.noteOn(channel: 0, note: 60, velocity: 100), from: .externalSource)

        XCTAssertEqual(output.calls, [.noteOn(channel: 0, note: 60, velocity: 100)])
        XCTAssertFalse(router.isExternalSourcePathSealed)
    }

    /// Kabel am Keyboard raus darf die Noten einer DAW nicht mitreissen.
    func testRemovingTheExternalSourceLeavesVirtualDestinationNotesAlone() {
        let output = RecordingAudioOutput()
        let router = MIDIInputRouter(output: output)

        router.handle(.noteOn(channel: 0, note: 72, velocity: 100), from: .virtualDestination)
        router.handle(.noteOn(channel: 0, note: 60, velocity: 100), from: .externalSource)

        router.releaseNotes(on: .externalSource, sealing: true)

        XCTAssertEqual(output.calls, [
            .noteOn(channel: 0, note: 72, velocity: 100),
            .noteOn(channel: 0, note: 60, velocity: 100),
            .noteOff(channel: 0, note: 60)
        ])
        XCTAssertEqual(router.activeExternalNoteCount(on: .virtualDestination), 1)
        XCTAssertEqual(router.activeExternalNoteCount(on: .externalSource), 0)
    }

    func testGlobalPanicForgetsBothPaths() {
        let output = RecordingAudioOutput()
        let router = MIDIInputRouter(output: output)

        router.handle(.noteOn(channel: 0, note: 72, velocity: 100), from: .virtualDestination)
        router.handle(.noteOn(channel: 0, note: 60, velocity: 100), from: .externalSource)
        let callCount = output.calls.count

        router.forgetAllExternalNotes()

        XCTAssertEqual(router.activeExternalNoteCount, 0)
        XCTAssertEqual(output.calls.count, callCount)
    }
}
