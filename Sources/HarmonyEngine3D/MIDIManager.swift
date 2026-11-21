import CoreMIDI
import Foundation

// MARK: – Virtueller MIDI-Ausgang (4 Kanäle)
//
//  CH 0  Akkorde        → Chord-Kugeln    (MIDI-Byte: 0x90)
//  CH 1  Bass           → Portal-Ringe    (MIDI-Byte: 0x91)
//  CH 2  Melodie        → Nebel-Wolken    (MIDI-Byte: 0x92)
//  CH 3  Chord-Tones    → Linker Stick    (MIDI-Byte: 0x93)
//
// Alle vier erscheinen in Mainstage als dieselbe Source "HarmonyEngine3D Output".
// Dort einfach vier Instrument-Spuren mit je einem MIDI-Input-Filter anlegen.
//
// Interface: ausschließlich AudioOutput-Protokoll (noteOn/noteOff/allNotesOff/applyFXConfig).
// MIDIManager verwaltet keinen eigenen Noten-State — das ist Aufgabe des Aufrufers.

final class MIDIManager {

    static let shared = MIDIManager()

    private var client: MIDIClientRef   = 0
    private var source: MIDIEndpointRef = 0

    private init() {
        let err = MIDIClientCreate("HarmonyEngine3D" as CFString, nil, nil, &client)
        if err == noErr {
            MIDISourceCreate(client, "HarmonyEngine3D Output" as CFString, &source)
            print("🎵 MIDI Virtual Source bereit: 'HarmonyEngine3D Output'")
            print("   CH 0 = Akkorde  |  CH 1 = Bass  |  CH 2 = Melodie  |  CH 3 = Chord-Tones (Linker Stick)")
        } else {
            print("⚠️  MIDI Client konnte nicht erstellt werden: \(err)")
        }
    }

    // MARK: – CC: Sensor-Daten (Gyro / Touchpad, Kanal konfigurierbar)

    func sendCC(channel: Int, cc: Int, value: Int) {
        let status = UInt8(0xB0 | UInt8(channel & 0x0F))
        send(status, UInt8(cc & 0x7F), UInt8(max(0, min(127, value))))
    }

    // MARK: – MIDI senden (intern)

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

// MARK: – AudioOutput-Konformität (Rev. 5)
//
// Mappt das noteOn/noteOff/allNotesOff-Protokoll direkt auf MIDI-Byte-Ebene.
// channel-Parameter: 0-indexed (0–3), entspricht MIDI-Kanälen CH 0–3.
//
// MIDIManager hält keinen eigenen Noten-State:
//   – noteOn/noteOff sind zustandslos (reines Byte-Senden).
//   – allNotesOff() sendet CC 123 auf allen vier Kanälen — kein eigenes Tracking nötig.
//   – applyFXConfig ist No-Op (keine eigene Effektkette).

extension MIDIManager: AudioOutput {

    func noteOn(channel: Int, note: UInt8, velocity: UInt8) {
        let status = UInt8(0x90 | (channel & 0x0F))
        send(status, note, velocity)
    }

    func noteOff(channel: Int, note: UInt8) {
        let status = UInt8(0x80 | (channel & 0x0F))
        send(status, note, 0)
    }

    func allNotesOff(channel: Int) {
        // CC 123: All Notes Off auf diesem MIDI-Kanal.
        let status = UInt8(0xB0 | (channel & 0x0F))
        send(status, 123, 0)
    }

    func allNotesOff() {
        // CC 123 auf allen vier Kanälen — kein eigenes Noten-Tracking erforderlich.
        for ch in 0..<4 {
            send(UInt8(0xB0 | ch), 123, 0)
        }
    }

    func applyFXConfig(_ cfg: ChannelFXConfig, channel: Int) {
        // MIDIManager hat keine eigene Effektkette – No-Op.
    }
}
