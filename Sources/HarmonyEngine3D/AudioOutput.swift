import Foundation

// MARK: – AudioOutput
//
// Minimales Protokoll für alle Audio-Ausgabepfade (AudioEngine, MIDIManager).
//
// Grundprinzip: Die Engine ist ausschließlich ein Note-Event-Generator.
// Sie entscheidet nicht über Polyphonie, Legato, Voice-Stealing oder ADSR.
// Diese Entscheidungen trifft der Synth (SynthNode) bzw. das externe MIDI-Instrument.
//
// Kanalkonventionen:
//   CH 0 = Akkorde     CH 1 = Bass     CH 2 = Melodie     CH 3 = Chord-Tones
//
// ── Eventmodell: alle vier Kanäle verwenden noteOn/noteOff mit Notennummer ─────────
//
// CH0–CH3 senden noteOn(channel:note:velocity:) und noteOff(channel:note:) mit
// vollständiger Notennummer. allNotesOff(channel:) bleibt im Protokoll für
// außerordentliche Resets (z. B. △-Taste, App-Pause), nicht für reguläre Off-Events.

protocol AudioOutput: AnyObject {

    /// Startet eine Note auf dem angegebenen Kanal.
    /// Polyphonie, Legato und Voice-Stealing sind Entscheidungen des Implementierers
    /// (SynthNode, AVAudioUnitSampler oder MIDI-Instrument) – nicht des Aufrufers.
    func noteOn(channel: Int, note: UInt8, velocity: UInt8)

    /// Stoppt eine bestimmte Note auf dem angegebenen Kanal.
    /// Verwendung: CH0 – chord.midiNotes liefert die konkrete Notennummer.
    /// Für CH1/CH2 ist derzeit allNotesOff(channel:) erforderlich – siehe Kopfkommentar.
    func noteOff(channel: Int, note: UInt8)

    /// Stoppt alle laufenden Noten auf einem bestimmten Kanal.
    /// Eingesetzt wenn das Off-Event keine spezifische Notennummer trägt (CH1, CH2).
    func allNotesOff(channel: Int)

    /// Stoppt alle Noten auf allen Kanälen (z. B. △-Taste, App-Pause).
    func allNotesOff()

    /// Überträgt eine FX-Konfiguration auf den angegebenen Kanal (Delay, Reverb, Volume).
    /// Bei Implementierungen ohne eigene Effektkette (MIDIManager) ist dies ein No-Op.
    func applyFXConfig(_ cfg: ChannelFXConfig, channel: Int)
}
