import Foundation
import HarmonyShared

// MARK: – MelodyPreset

struct MelodyPreset {
    let name:      String
    let intervals: [Int]
}

// MARK: – MelodyTick

struct MelodyTick {
    let note:     Int
    let velocity: UInt8
}

// MARK: – MelodyEngine
//
// Zustandsbehafteter Automat für die Melodie-Logik einer Wolken-Sammlung.
// Kein SceneKit. Kein AppSettings-Zugriff. Kein MIDI.
//
// HarmonyScene besitzt eine Instanz, übergibt Parameter aus AppSettings
// und ruft tick() einmal pro Update-Frame auf.

struct MelodyEngine {

    // ── Presets ───────────────────────────────────────────────────────────

    let presets: [MelodyPreset] = [
        MelodyPreset(name: "Dorian Penta",  intervals: [0,2,3,7,10,12,14,15,19]),
        MelodyPreset(name: "Dur Penta",     intervals: [0,2,4,7,9,12,14,16,19]),
        MelodyPreset(name: "Moll Blues",    intervals: [0,3,5,6,7,10,12,15,17]),
        MelodyPreset(name: "Ganzton",       intervals: [0,2,4,6,8,10,12,14,16]),
        MelodyPreset(name: "Lydisch",       intervals: [0,2,4,6,7,9,11,12,14]),
        MelodyPreset(name: "Chromatisch",   intervals: [0,1,2,3,4,5,6,7,8])
    ]

    private(set) var presetIndex: Int = 0
    var currentPresetName: String { presets[presetIndex].name }

    // Schaltet zum nächsten Preset und baut alle Skalen neu. Gibt den neuen Namen zurück.
    mutating func nextPreset() -> String {
        presetIndex = (presetIndex + 1) % presets.count
        rebuildAllScales()
        return currentPresetName
    }

    // Schaltet zum vorherigen Preset und baut alle Skalen neu. Gibt den neuen Namen zurück.
    mutating func prevPreset() -> String {
        presetIndex = (presetIndex - 1 + presets.count) % presets.count
        rebuildAllScales()
        return currentPresetName
    }

    // ── Per-Cloud State ───────────────────────────────────────────────────

    private var cloudRoots:   [String: Int]   = [:]   // Wurzelton je Wolke
    private var cloudNotes:   [String: [Int]] = [:]   // Skalentöne je Wolke
    private var cloudNoteIdx: [String: Int]   = [:]   // Round-Robin-Index je Wolke

    // ── Voice-Leading State ───────────────────────────────────────────────

    private(set) var lastNote: Int         = -1
    private var lastTickTime: TimeInterval = 0

    // ── Deterministische Notenauswahl (Runde 038 / V-00b, Fable-5-Review
    // Finding A3) ─────────────────────────────────────────────────────────
    // `tick()` wählte den nächsten Ton bei mehreren gleich nahen Kandidaten
    // bisher über den globalen, unseeded System-RNG (`randomElement()`) —
    // damit war dieselbe Spielsituation über Prozessstarts hinweg nicht
    // reproduzierbar, obwohl `SeededRNG` (HarmonyShared) genau dafür
    // existiert und im Welt-/Visual-Pfad bereits konsequent genutzt wird.
    // Default-Seed ist fix, damit `MelodyEngine()` (Bestandsaufrufer)
    // weiterhin ohne Parameter konstruierbar bleibt, aber deterministisch.
    private var rng: SeededRNG

    init(seed: UInt64 = 0x4D45_4C4F_4459_5F31) {
        rng = SeededRNG(seed: seed)
    }

    // ── Scale Building ────────────────────────────────────────────────────

    func buildScale(root: Int) -> [Int] {
        presets[presetIndex].intervals.map { root + $0 }
    }

    private mutating func rebuildAllScales() {
        for (key, root) in cloudRoots {
            cloudNotes[key]   = buildScale(root: root)
            cloudNoteIdx[key] = 0
        }
    }

    // ── Cloud Management ──────────────────────────────────────────────────

    /// Registriert eine neue Wolke mit Wurzelton. Wird bei Chunk-Load aufgerufen.
    mutating func addCloud(key: String, root: Int) {
        cloudRoots[key]   = root
        cloudNotes[key]   = buildScale(root: root)
        cloudNoteIdx[key] = 0
    }

    /// Entfernt eine Wolke vollständig. Wird bei Chunk-Unload aufgerufen.
    mutating func removeCloud(_ key: String) {
        cloudRoots.removeValue(forKey: key)
        cloudNotes.removeValue(forKey: key)
        cloudNoteIdx.removeValue(forKey: key)
    }

    /// Setzt den Round-Robin-Index einer Wolke auf 0. Wird bei Trigger-Aktivierung aufgerufen.
    mutating func resetCloudIndex(_ key: String) {
        cloudNoteIdx[key] = 0
    }

    // ── Reset ─────────────────────────────────────────────────────────────

    /// Setzt Voice-Leading-Zustand zurück (z. B. bei Netzwerkwechsel / Chunk-Reload).
    /// Cloud-Registrierungen bleiben erhalten (werden separat über removeCloud bereinigt).
    mutating func reset() {
        lastNote     = -1
        lastTickTime = 0
    }

    /// Beendet die aktive Melodie-Note.
    ///
    /// Gibt lastNote zurück, wenn eine Note aktiv war (>= 0), andernfalls nil.
    /// Setzt lastNote auf -1 → idempotent: zweiter Aufruf gibt immer nil.
    ///
    /// Wird von HarmonyScene aufgerufen, bevor ein Cloud-Trigger-Wechsel oder
    /// ein Chunk-Unload den MelodyEngine-Zustand zurücksetzt. Nur stop() darf
    /// das Off-Event erzeugen — kein Tracking im OutputCoordinator.
    mutating func stop() -> Int? {
        guard lastNote >= 0 else { return nil }
        let note = lastNote
        lastNote = -1
        return note
    }

    // ── Melody Tick ───────────────────────────────────────────────────────
    //
    // Gibt einen neuen MelodyTick zurück, wenn das zeitliche Intervall abgelaufen ist.
    // Gibt nil zurück, wenn es noch zu früh ist oder die Proximity zu gering ist.
    //
    // Parameter (von HarmonyScene aus AppSettings gelesen):
    //   cloudKey    – aktiver Wolken-Key (aus cloudTriggerEngine.activeKey)
    //   proximity   – 0…1 (0 = Wolkenrand, 1 = Zentrum)
    //   tempo       – aus AppSettings.melodyTempo
    //   velMax      – aus AppSettings.melodyVelMax
    //   energyLevel – aus AppSettings.energyLevel
    //   now         – Date().timeIntervalSinceReferenceDate

    mutating func tick(
        cloudKey:    String,
        proximity:   Float,
        tempo:       Double,
        velMax:      Float,
        energyLevel: Float,
        now:         TimeInterval
    ) -> MelodyTick? {

        guard proximity > 0.08 else { lastTickTime = 0; return nil }

        // Intervall: 2.5 s (Rand) → 0.4 s (Zentrum), skaliert mit tempo
        let interval = TimeInterval(2.5 - Double(proximity) * 2.1) / max(0.1, tempo)
        // Velocity: 18 (Rand) → velMax (Zentrum)
        let velocity = UInt8(18 + Int(proximity * (velMax - 18)))

        if lastTickTime == 0 { lastTickTime = now }
        guard now - lastTickTime >= interval else { return nil }
        lastTickTime = now

        let notes = cloudNotes[cloudKey] ?? []
        guard !notes.isEmpty else { return nil }

        // Voice-Leading: energy steuert maximale Intervallgröße.
        // 0.0 → Sekundschritte (maxStep=1), 0.5 → Sexten (maxStep=6), 1.0 → beliebig
        let maxStep = max(1, Int(energyLevel * 11.0) + 1)
        let nextNote: Int

        if lastNote >= 0 && energyLevel < 0.95 {
            // Kandidaten: Töne innerhalb der erlaubten Schrittweite, nicht der exakt gleiche
            let close = notes.filter { $0 != lastNote && abs($0 - lastNote) <= maxStep }
            if !close.isEmpty {
                nextNote = close[rng.i(close.count)]
            } else {
                // Kein Ton in Reichweite: nächstliegenden nehmen
                nextNote = notes.min(by: { abs($0 - lastNote) < abs($1 - lastNote) }) ?? notes[0]
            }
        } else {
            // Kein Referenzton oder volle Energy: Round-Robin
            let idx = cloudNoteIdx[cloudKey] ?? 0
            nextNote = notes[idx % notes.count]
            cloudNoteIdx[cloudKey] = (idx + 1) % notes.count
        }

        lastNote = nextNote
        return MelodyTick(note: nextNote, velocity: velocity)
    }
}
