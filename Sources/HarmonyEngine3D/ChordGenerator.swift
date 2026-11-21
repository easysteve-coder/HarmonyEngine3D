import Foundation
import HarmonyShared

// MARK: – Automatischer Jazz-Akkord-Generator
//
// Erzeugt 12 × 4 = 48 Akkorde aus Musiktheorie,
// verbunden nach Jazz-Harmonik:
//   • ii–V–I Ketten          (Gewicht 1.0)
//   • Tritonus-Substitution   (0.85)
//   • Relative Dur/Moll       (0.85)
//   • Parallele Dur/Moll      (0.70)
//   • Halbvermindert → Dom7   (0.80)
//   • ≥ 3 gemeinsame Töne     (0.65)

enum ChordGenerator {

    // Quintenkreis-Reihenfolge → schöne räumliche Verteilung
    private static let roots: [(name: String, chromatic: Int, midi: Int)] = [
        ("C",  0, 60), ("G",  7, 55), ("D",  2, 62), ("A",  9, 57),
        ("E",  4, 52), ("B", 11, 59), ("F#", 6, 54), ("Db", 1, 61),
        ("Ab", 8, 56), ("Eb", 3, 51), ("Bb",10, 58), ("F",  5, 53)
    ]

    // (Suffix, Intervalle ab Grundton in Halbtonschritten)
    // Die ersten 4 Typen sind immer aktiv; weitere per Settings zuschaltbar.
    private static let types: [(suffix: String, intervals: [Int])] = [
        ("maj7", [0, 4,  7, 11]),        // Große Septime
        ("m7",   [0, 3,  7, 10]),        // Kleine Septime
        ("7",    [0, 4,  7, 10]),        // Dominantseptime
        ("m7b5", [0, 3,  6, 10]),        // Halbvermindert
        ("dim7", [0, 3,  6,  9]),        // Vollvermindert (symmetrisch)
        ("maj9", [0, 4,  7, 11, 14]),    // Große None
        ("9",    [0, 4,  7, 10, 14]),    // Dominantnone
        ("sus4", [0, 5,  7, 10]),        // Suspended 4 (keine Terz)
        ("6",    [0, 4,  7,  9]),        // Sexte (statt Septime)
        ("m9",   [0, 3,  7, 10, 14]),   // Moll-None
    ]

    // Längere Präfixe zuerst (F# vor F, Db vor D …)
    private static let prefixTable: [(name: String, chromatic: Int)] = [
        ("F#", 6), ("Db", 1), ("Ab", 8), ("Eb", 3), ("Bb", 10),
        ("C", 0), ("D", 2), ("E", 4), ("F", 5), ("G", 7), ("A", 9), ("B", 11)
    ]

    // MARK: – Öffentliche API

    static func generate() -> ChordNetwork {
        // 48 Akkorde
        var chords: [ChordData] = []
        for root in roots {
            for type in types {
                let name  = root.name + type.suffix
                let notes = type.intervals.map { root.midi + $0 }
                chords.append(ChordData(name: name, midiNotes: notes))
            }
        }

        // Verbindungen aus Harmonielehre
        var seen  = Set<String>()
        var edges: [EdgeData] = []

        for i in 0..<chords.count {
            for j in (i+1)..<chords.count {
                let w = theoryWeight(chords[i], chords[j])
                guard w >= 0.45 else { continue }   // nur musikalisch relevante Kanten
                let key = "\(chords[i].name)||\(chords[j].name)"
                if seen.insert(key).inserted {
                    edges.append(EdgeData(source: chords[i].name,
                                          target: chords[j].name,
                                          weight: w))
                }
            }
        }

        print("🎼 Generiert: \(chords.count) Akkorde, \(edges.count) Verbindungen")
        return ChordNetwork(chords: chords, edges: edges)
    }

    // MARK: – Musiktheorie-Gewichtung

    private static func theoryWeight(_ a: ChordData, _ b: ChordData) -> Float {
        let aC  = chroma(a.name);  let bC  = chroma(b.name)
        let aSf = sfx(a.name);     let bSf = sfx(b.name)
        let ab  = (bC - aC + 12) % 12   // Intervall a → b
        let ba  = (aC - bC + 12) % 12   // Intervall b → a

        // ── ii–V: m7 → Dom7 eine reine Quarte höher (5 Halbtonschritte) ──
        if (aSf == "m7"   && bSf == "7"    && ab == 5) ||
           (bSf == "m7"   && aSf == "7"    && ba == 5) { return 1.0 }

        // ── V–I: Dom7 → maj7 eine reine Quarte höher ────────────────────
        if (aSf == "7"    && bSf == "maj7" && ab == 5) ||
           (bSf == "7"    && aSf == "maj7" && ba == 5) { return 1.0 }

        // ── Tritonus-Substitution: Dom7 ↔ Dom7 im Abstand Tritonus ──────
        if aSf == "7" && bSf == "7" && ab == 6        { return 0.85 }

        // ── Relative Dur/Moll: maj7 ↔ m7, Grundton-Abstand gr. Sexte ───
        if (aSf == "maj7" && bSf == "m7" && ab == 9) ||
           (bSf == "maj7" && aSf == "m7" && ba == 9)  { return 0.85 }

        // ── Halbvermindert → Dominante eine Quarte höher ────────────────
        if (aSf == "m7b5" && bSf == "7"    && ab == 5) ||
           (bSf == "m7b5" && aSf == "7"    && ba == 5) { return 0.80 }

        // ── Parallele Dur/Moll: gleicher Grundton, maj7 ↔ m7 ───────────
        if aC == bC &&
           ((aSf == "maj7" && bSf == "m7") ||
            (aSf == "m7"   && bSf == "maj7")) { return 0.70 }

        // ── Gemeinsame Töne (Pitchklassen) ───────────────────────────────
        let aPCs = Set(a.midiNotes.map { $0 % 12 })
        let bPCs = Set(b.midiNotes.map { $0 % 12 })
        let n    = aPCs.intersection(bPCs).count
        if n >= 3 { return 0.65 }
        if n == 2 { return 0.40 }   // unter Schwellwert → wird gefiltert

        return 0
    }

    // MARK: – Hilfsfunktionen

    private static func chroma(_ name: String) -> Int {
        for (pfx, idx) in prefixTable { if name.hasPrefix(pfx) { return idx } }
        return 0
    }

    private static func sfx(_ name: String) -> String {
        for (pfx, _) in prefixTable { if name.hasPrefix(pfx) { return String(name.dropFirst(pfx.count)) } }
        return ""
    }
}
