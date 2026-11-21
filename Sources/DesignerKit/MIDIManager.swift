import CoreMIDI
import Foundation

// MARK: – Virtueller MIDI-Ausgang für Harmony 2D
//
//  chordChannel      Akkorde        – Nähe zum Knoten
//  CH2 (fest)        Bass           – reserviert
//  CH3 (fest)        Melodie        – reserviert
//  chordToneChannel  Chord-Tones    – linker Stick (konfigurierbar)
//  weitere CH        Button-Mappings (frei konfigurierbar)

final class MIDIManager {

    static let shared = MIDIManager()

    private var client: MIDIClientRef   = 0
    private var source: MIDIEndpointRef = 0

    var chordChannel:     Int = 0   // 0-indexed (CH1 in Mainstage)
    var chordToneChannel: Int = 3   // 0-indexed (CH4 in Mainstage)

    private var activeChordNotes: [UInt8] = []
    private var activeBassNote:   UInt8?  = nil

    private init() {
        let err = MIDIClientCreate("Harmony2D" as CFString, nil, nil, &client)
        if err == noErr {
            MIDISourceCreate(client, "Harmony 2D Output" as CFString, &source)
            print("🎵 MIDI Virtual Source bereit: 'Harmony 2D Output'")
        } else {
            print("⚠️  MIDI Client konnte nicht erstellt werden: \(err)")
        }
    }

    // MARK: – Akkorde (chordChannel)

    func playChord(_ notes: [Int], velocity: UInt8 = 88) {
        stopCurrentChord()
        let on = UInt8(0x90 | UInt8(chordChannel & 0x0F))
        notes.forEach { note in
            let n = UInt8(max(0, min(127, note)))
            send(on, n, velocity)
            activeChordNotes.append(n)
        }
        print("🎵 CH\(chordChannel+1) Chord ON: \(notes)")
    }

    func stopCurrentChord() {
        let off = UInt8(0x80 | UInt8(chordChannel & 0x0F))
        activeChordNotes.forEach { send(off, $0, 0) }
        if !activeChordNotes.isEmpty { print("🎵 CH\(chordChannel+1) Chord OFF") }
        activeChordNotes.removeAll()
    }

    // MARK: – Bass (CH2, fest)

    func playBassNote(_ note: Int, velocity: UInt8 = 80) {
        stopBassNote()
        let n = UInt8(max(0, min(127, note)))
        send(0x91, n, velocity)
        activeBassNote = n
    }

    func stopBassNote() {
        if let n = activeBassNote { send(0x81, n, 0); activeBassNote = nil }
    }

    // MARK: – Melodieton (CH3, auto-off)

    func playMelodyNote(_ note: Int, velocity: UInt8 = 72) {
        let n = UInt8(max(0, min(127, note)))
        send(0x92, n, velocity)
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.28) { [weak self] in
            self?.send(0x82, n, 0)
        }
    }

    // MARK: – Chord-Tone (chordToneChannel, auto-off)

    func playChordTone(_ note: Int, velocity: UInt8) {
        let n   = UInt8(max(0, min(127, note)))
        let on  = UInt8(0x90 | UInt8(chordToneChannel & 0x0F))
        let off = UInt8(0x80 | UInt8(chordToneChannel & 0x0F))
        send(on, n, velocity)
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.32) { [weak self] in
            self?.send(off, n, 0)
        }
    }

    // MARK: – CC

    func sendCC(channel: Int, cc: Int, value: Int) {
        let status = UInt8(0xB0 | UInt8(channel & 0x0F))
        send(status, UInt8(cc & 0x7F), UInt8(max(0, min(127, value))))
    }

    // MARK: – Rohe Nachricht (für Button-Mappings)

    func sendRaw(_ status: UInt8, _ d1: UInt8, _ d2: UInt8) {
        send(status, d1, d2)
    }

    // MARK: – MIDI Clock

    private var clockTimer: DispatchSourceTimer?

    func startClock(bpm: Double) {
        stopClock()
        sendByte(0xFA) // MIDI Start
        let interval = 60.0 / (bpm * 24.0)
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: interval, leeway: .microseconds(200))
        timer.setEventHandler { [weak self] in self?.sendByte(0xF8) }
        timer.resume()
        clockTimer = timer
        print("🕐 MIDI Clock gestartet: \(Int(bpm)) BPM")
    }

    func stopClock() {
        clockTimer?.cancel()
        clockTimer = nil
        sendByte(0xFC) // MIDI Stop
        print("🕐 MIDI Clock gestoppt")
    }

    // MARK: – Alles stoppen

    func stopAll() {
        stopCurrentChord()
        stopBassNote()
        for ch in 0..<16 {
            send(UInt8(0xB0 | UInt8(ch)), 123, 0)
        }
    }

    // MARK: – Intern

    private func sendByte(_ byte: UInt8) {
        guard source != 0 else { return }
        let bytes: [UInt8] = [byte]
        var buffer = [UInt8](repeating: 0, count: 256)
        buffer.withUnsafeMutableBytes { raw in
            let pktList = raw.baseAddress!.assumingMemoryBound(to: MIDIPacketList.self)
            var pkt = MIDIPacketListInit(pktList)
            pkt = MIDIPacketListAdd(pktList, 256, pkt, 0, 1, bytes)
            MIDIReceived(source, pktList)
        }
    }

    private func send(_ status: UInt8, _ d1: UInt8, _ d2: UInt8) {
        guard source != 0 else { return }
        let bytes: [UInt8] = [status, d1, d2]
        var buffer = [UInt8](repeating: 0, count: 256)
        buffer.withUnsafeMutableBytes { raw in
            let pktList = raw.baseAddress!.assumingMemoryBound(to: MIDIPacketList.self)
            var pkt = MIDIPacketListInit(pktList)
            pkt = MIDIPacketListAdd(pktList, 256, pkt, 0, 3, bytes)
            MIDIReceived(source, pktList)
        }
    }
}
