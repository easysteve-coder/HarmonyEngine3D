import Foundation

// MARK: – ChunkCoord
//
// Diskrete 3D-Koordinate eines Welt-Chunks.
// Hashable: wird als Dictionary-Schlüssel in HarmonyScene.loadedChunks verwendet.
// Kein SceneKit, kein AppSettings.

struct ChunkCoord: Hashable {
    let x, y, z: Int
}

// SeededRNG wurde nach HarmonyShared/SeededRNG.swift verschoben (public).
// HarmonyEngine3D importiert HarmonyShared → SeededRNG steht hier unverändert zur Verfügung.
