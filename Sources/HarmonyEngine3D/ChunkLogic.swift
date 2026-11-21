import simd

// MARK: – ChunkData
//
// SceneKit-freie Beschreibung des Inhalts eines Chunks.
// Enthält nur Daten (Namen, Positionen, Noten) — keine SCNNodes.
// Wird von computeChunkData() erzeugt und von HarmonyScene.buildNodes() konsumiert.

struct ChunkData {
    let coord: ChunkCoord

    /// Akkord: Name (z. B. "Cmaj7") + Weltposition des Knotens
    let chord: (name: String, position: simd_float3)?

    /// Bass-Portal: MIDI-Note + Weltposition des Rings
    let bass: (note: Int, position: simd_float3)?

    /// Melodie-Wolke: Root-MIDI-Note + Weltposition der Wolke
    let cloud: (root: Int, position: simd_float3)?

    /// Seed für den visuellen RNG (SeededRNG in buildNodes).
    /// Erfasst nach allen Daten-Entscheidungen → trennter RNG-Strom für Visuals.
    let visualSeed: UInt64
}

// MARK: – ChunkLogic
//
// Reine Berechnungslogik für das Chunk-System.
// Kein SceneKit, kein AppSettings, kein UI, kein MIDI.
//
// Alle Methoden sind deterministisch:
//   gleiche Eingabe → gleiche Ausgabe → reproduzierbare Welt.
//
// Die RNG-Sequenz der Daten-Entscheidungen ist identisch mit der früheren
// HarmonyScene-Implementierung bis zu dem Punkt, an dem make*Node-Funktionen
// eigene RNG-Calls machten. Ab dort verwendet buildNodes() einen separaten
// visualRNG (SeededRNG(seed: data.visualSeed)) — akzeptierter kosmetischer Bruch.
//
// Verwendet von: HarmonyScene (als private let chunkLogic)

struct ChunkLogic {

    let chunkSize:  Float   // Kantenlänge eines Chunks (Welteinheiten)
    let loadRadius: Int     // Lade-Radius in Chunks (lädt (2r+1)³ Chunks)

    // MARK: – Chunk-Koordinaten

    /// Berechnet den Chunk-Koordinaten-Tuple für eine Weltposition.
    /// Entspricht dem bisherigen cx/cy/cz-Block in updateChunks.
    func currentChunk(for cameraPosition: simd_float3) -> ChunkCoord {
        ChunkCoord(
            x: Int(floor(cameraPosition.x / chunkSize)),
            y: Int(floor(cameraPosition.y / chunkSize)),
            z: Int(floor(cameraPosition.z / chunkSize))
        )
    }

    /// Liefert alle ChunkCoords im kubischen Lade-Radius um ein Zentrum.
    /// Entspricht dem Triple-Loop in updateChunks.
    func neededChunkCoords(around center: ChunkCoord) -> Set<ChunkCoord> {
        var needed = Set<ChunkCoord>()
        for dx in -loadRadius...loadRadius {
            for dy in -loadRadius...loadRadius {
                for dz in -loadRadius...loadRadius {
                    needed.insert(ChunkCoord(
                        x: center.x + dx,
                        y: center.y + dy,
                        z: center.z + dz
                    ))
                }
            }
        }
        return needed
    }

    /// Sortiert ChunkCoords nach Manhattan-Distanz vom Zentrum (nächste zuerst).
    /// Entspricht dem newCoords.sorted-Block in updateChunks.
    func sortedByDistance(from center: ChunkCoord, coords: [ChunkCoord]) -> [ChunkCoord] {
        coords.sorted {
            abs($0.x - center.x) + abs($0.y - center.y) + abs($0.z - center.z) <
            abs($1.x - center.x) + abs($1.y - center.y) + abs($1.z - center.z)
        }
    }

    // MARK: – Deterministik

    /// Deterministischer Seed für einen Chunk (Xorshift-Hash über x/y/z).
    /// Gleicher ChunkCoord → identischer Seed → identische Welt.
    /// Entspricht exakt der bisherigen chunkSeed(_:)-Implementierung.
    func chunkSeed(for coord: ChunkCoord) -> UInt64 {
        var h = UInt64(bitPattern: Int64(coord.x &* 2654435761))
        h ^= UInt64(bitPattern: Int64(coord.y &* 2246822519))
        h ^= UInt64(bitPattern: Int64(coord.z &* 3266489917))
        h ^= (h >> 16)
        h  = h &* 0x45d9f3b37197344d
        h ^= (h >> 16)
        return h == 0 ? 1 : h
    }

    /// Berechnet eine zufällige, deterministische Position innerhalb eines Chunks.
    /// Rückgabe: simd_float3 (SceneKit-freier Typ).
    /// HarmonyScene konvertiert an der Übergabestelle auf SCNVector3.
    ///
    /// Der RNG-Verbrauch (3× rng.f) ist identisch mit dem früheren
    /// randomPosInChunk(_:rng:) – der RNG-Flow wird nicht verändert.
    func randomPosition(in coord: ChunkCoord, rng: inout SeededRNG) -> simd_float3 {
        let margin: Float = 18.0
        let half = chunkSize / 2.0 - margin
        return simd_float3(
            Float(coord.x) * chunkSize + rng.f(in: -half...half),
            Float(coord.y) * chunkSize + rng.f(in: -half...half),
            Float(coord.z) * chunkSize + rng.f(in: -half...half)
        )
    }

    // MARK: – computeChunkData

    /// Berechnet den deterministischen Inhalt eines Chunks (kein SceneKit, kein AppSettings).
    ///
    /// Übernimmt alle Daten-Entscheidungen aus dem früheren loadChunk:
    ///   - Existenz-Tests (Dichte-Checks) für Akkord, Bass-Portal, Melodie-Wolke
    ///   - Positionen via randomPosition (identischer RNG-Verbrauch wie zuvor)
    ///   - Gewichtete Akkord-Auswahl, Bass-Noten-Auswahl, Root-Auswahl
    ///
    /// Gibt einen visualSeed zurück, der nach allen Daten-Entscheidungen
    /// aus dem RNG-State erfasst wird. buildNodes() verwendet ihn für einen
    /// separaten visuellen RNG-Strom.
    ///
    /// Akzeptierter Nebeneffekt: visuelle Variation (Knoten-Erscheinung)
    /// ändert sich einmalig gegenüber der vorherigen Implementierung, da
    /// der visuelle RNG nun aus visualSeed statt aus dem geteilten RNG-Stream läuft.
    /// Positionen, Akkorde, Bass-Noten und Roots sind davon NICHT betroffen.
    ///
    /// - Parameters:
    ///   - coord:          Chunk-Koordinate
    ///   - chordDensity:   Wahrscheinlichkeit in % [0–100] für einen Akkord-Knoten
    ///   - portalDensity:  Wahrscheinlichkeit in % [0–100] für ein Bass-Portal
    ///   - cloudDensity:   Wahrscheinlichkeit in % [0–100] für eine Melodie-Wolke
    ///   - weightedChords: Gefilterter + gewichteter Akkord-Pool (Name + Gewicht).
    ///                     Filterung (Typ, Key-Center) und Gewichtung (Energy)
    ///                     erfolgen in HarmonyScene, wo AppSettings erlaubt ist.
    func computeChunkData(
        coord:          ChunkCoord,
        chordDensity:   Int,
        portalDensity:  Int,
        cloudDensity:   Int,
        weightedChords: [(name: String, weight: Float)]
    ) -> ChunkData {

        // Musikalische Konstanten – identisch mit loadChunk (deterministisch, nicht konfigurierbar)
        let bassPool: [Int] = [24, 31, 26, 33, 28, 35, 30, 25, 32, 27, 34, 29,
                               36, 43, 38, 45, 40, 47, 42, 37, 44, 39, 46, 41]
        let rootPool: [Int] = [60, 67, 62, 69, 64, 71, 66, 61, 68, 63, 70, 65]

        var rng = SeededRNG(seed: chunkSeed(for: coord))

        // ── Track 1: Akkord ──────────────────────────────────────────────────
        // RNG-Verbrauch: i(100) immer + [f×3 + i(10000)] wenn Akkord vorhanden
        var chordResult: (name: String, position: simd_float3)? = nil
        if rng.i(100) < chordDensity && !weightedChords.isEmpty {
            let pos    = randomPosition(in: coord, rng: &rng)
            let totalW = weightedChords.reduce(Float(0)) { $0 + $1.weight }
            let randV  = Float(rng.i(10000)) / 9999.0 * totalW
            var accumW: Float = 0
            var selected = weightedChords[0].name
            for wc in weightedChords {
                accumW += wc.weight
                if randV <= accumW { selected = wc.name; break }
            }
            chordResult = (name: selected, position: pos)
        }

        // ── Track 2: Bass-Portal ─────────────────────────────────────────────
        // RNG-Verbrauch: i(100) immer + [f×3 + i(24)] wenn Portal vorhanden
        var bassResult: (note: Int, position: simd_float3)? = nil
        if rng.i(100) < portalDensity {
            let pos  = randomPosition(in: coord, rng: &rng)
            let note = bassPool[rng.i(bassPool.count)]
            bassResult = (note: note, position: pos)
        }

        // ── Track 3: Melodie-Wolke ───────────────────────────────────────────
        // RNG-Verbrauch: i(100) immer + [f×3 + i(12)] wenn Wolke vorhanden
        var cloudResult: (root: Int, position: simd_float3)? = nil
        if rng.i(100) < cloudDensity {
            let pos  = randomPosition(in: coord, rng: &rng)
            let root = rootPool[rng.i(rootPool.count)]
            cloudResult = (root: root, position: pos)
        }

        // Visueller Seed: RNG-State nach allen Daten-Entscheidungen.
        // buildNodes() startet SeededRNG(seed: visualSeed) für make*Node-Funktionen.
        let visualSeed = rng.state

        return ChunkData(
            coord:      coord,
            chord:      chordResult,
            bass:       bassResult,
            cloud:      cloudResult,
            visualSeed: visualSeed
        )
    }
}
