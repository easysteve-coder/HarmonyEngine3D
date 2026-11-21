import Foundation

// MARK: – VoiceLeadingEngine
//
// Zustandsbehafteter Automat für die Oktav-Angleich-Logik von Akkorden.
// Kein SceneKit. Kein AppSettings-Zugriff. Kein MIDI.
//
// Aufgabe: Noten einer neuen Voicing in die Oktavlage verschieben,
// die dem Mittelpunkt der zuletzt gespielten Voicing am nächsten liegt.
// Verhindert Oktavsprünge zwischen aufeinanderfolgenden Akkordwechseln.
//
// HarmonyScene besitzt eine Instanz und übergibt `voiceLeadingEnabled`
// als Parameter aus AppSettings. Der Engine-Zustand (lastVoicing) wird
// hier gehalten; HarmonyScene verwaltet ihn nicht mehr selbst.

struct VoiceLeadingEngine {

    // Letzte gespielte Voicing als Referenz für den nächsten Angleich.
    private(set) var lastVoicing: [Int] = []

    // Wendet Voice-Leading an (wenn enabled) und speichert die neue Voicing.
    // Gibt immer eine gültige Note-Liste zurück – bei leerem Referenz-Zustand
    // werden die Noten unverändert zurückgegeben.
    mutating func apply(newNotes: [Int], enabled: Bool) -> [Int] {
        let result = enabled ? voiceLead(newNotes: newNotes, from: lastVoicing) : newNotes
        lastVoicing = result
        return result
    }

    // Zustand zurücksetzen (z. B. bei Netzwerkwechsel / Chunk-Reload).
    mutating func reset() {
        lastVoicing = []
    }

    // MARK: – Kern-Algorithmus (1:1 aus HarmonyScene übernommen)
    //
    // Verschiebt die Noten der neuen Voicing in die Oktavlage,
    // die dem Zentrum der Referenz-Voicing am nächsten liegt.
    //
    // Zulässiger MIDI-Bereich: 36–84 (C2–C6), Oktaven 2–7.
    // Jede Note wird unabhängig optimiert → sortiertes Ergebnis.

    private func voiceLead(newNotes: [Int], from reference: [Int]) -> [Int] {
        guard !reference.isEmpty else { return newNotes }
        // Mittelpunkt der Referenz-Voicing (z. B. 62 für eine tiefe Lage)
        let center = Float(reference.reduce(0, +)) / Float(reference.count)
        return newNotes.map { note in
            let pc = ((note % 12) + 12) % 12   // Pitch-Klasse 0…11, robust gegen negative MIDI
            var best     = note
            var bestDist = Float.infinity
            for oct in 2...7 {
                let candidate = pc + oct * 12
                guard candidate >= 36 && candidate <= 84 else { continue }
                let d = abs(Float(candidate) - center)
                if d < bestDist { bestDist = d; best = candidate }
            }
            return best
        }.sorted()
    }
}
