import Foundation
import simd

// MARK: – ProximityCandidate
//
// Platzhalterfrei-Datenstruktur für einen prüfbaren Raumkandidaten.
// Kein SceneKit, kein AppKit, kein MIDI.

struct ProximityCandidate {
    let key:      String        // interner Knoten-Schlüssel (z. B. Chunk-Key)
    let position: simd_float3   // Weltposition
}

// MARK: – ProximityResult
//
// Ergebnis einer einzelnen Proximity-Auswertung.
// approach:          nächster Kandidat innerhalb des Annäherungsradius + normierter Wert 0…1
// trigger:           nächster Kandidat innerhalb des Trigger-Radius (Key)
// triggerProximity:  normierter Wert 0…1 des Trigger-Kandidaten, bezogen auf triggerRadius
//                    (0 = Radius-Grenze, 1 = Zentrum; nil wenn kein Trigger)

struct ProximityResult {
    let approach:          (key: String, proximity: Float)?
    let trigger:           String?
    let triggerProximity:  Float?
}

// MARK: – ProximityTracker
//
// Zustandsloser Evaluator: keine gespeicherten Eigenschaften, kein AppSettings-Zugriff.
// HarmonyScene übergibt die Kandidaten-Liste, Kameraposition und Radien.
// Alle Radien werden von HarmonyScene aus AppSettings gelesen und hier nur genutzt.
//
// Approach-Radius ist üblicherweise 3× Trigger-Radius (entspricht bisherigem Verhalten).
//
// Trigger-Hysterese (Phase 3.9.1d): Entry- und Exit-Radius sind getrennt, um
// Flattern an der Radiusgrenze zu vermeiden. Ein bereits aktiver Kandidat bleibt
// gehalten, solange er innerhalb des (größeren) Exit-Radius liegt. Erst wenn kein
// aktiver Kandidat mehr gehalten wird, greift der (kleinere, konservativere)
// Entry-Radius für einen neuen Kandidaten.

struct ProximityTracker {

    static func evaluate(
        candidates:     [ProximityCandidate],
        cameraPos:      simd_float3,
        activeKey:      String?,
        entryRadius:    Float,
        exitRadius:     Float,
        approachRadius: Float
    ) -> ProximityResult {

        var nearApproach: (key: String, dist: Float)? = nil
        var nearEntry:    (key: String, dist: Float)? = nil
        var activeDist:   Float? = nil

        for c in candidates {
            let d = simd_distance(cameraPos, c.position)
            if d < approachRadius, nearApproach == nil || d < nearApproach!.dist {
                nearApproach = (c.key, d)
            }
            if d < entryRadius, nearEntry == nil || d < nearEntry!.dist {
                nearEntry = (c.key, d)
            }
            if c.key == activeKey {
                activeDist = d
            }
        }

        // Approach-Proximity: 0 an der Radiusgrenze, 1 im Zentrum
        let approach: (key: String, proximity: Float)?
        if let na = nearApproach {
            let prox = max(0.0, 1.0 - na.dist / approachRadius)
            approach = (na.key, prox)
        } else {
            approach = nil
        }

        // Trigger-Hysterese: aktiver Kandidat hält solange er im Exit-Radius bleibt,
        // sonst greift der Entry-Radius für einen (ggf. neuen) Kandidaten.
        let trigger:     String?
        let triggerDist: Float?
        if let active = activeKey, let d = activeDist, d < exitRadius {
            trigger     = active
            triggerDist = d
        } else if let ne = nearEntry {
            trigger     = ne.key
            triggerDist = ne.dist
        } else {
            trigger     = nil
            triggerDist = nil
        }

        // Trigger-Proximity: bezogen auf den Entry-Radius (bisheriges Verhalten
        // entsprach triggerRadius == entryRadius; ein gehaltener Kandidat jenseits
        // des Entry-Radius wird auf 0 geklemmt statt negativ zu werden).
        let triggerProximity: Float?
        if let td = triggerDist {
            triggerProximity = max(0.0, 1.0 - td / entryRadius)
        } else {
            triggerProximity = nil
        }

        return ProximityResult(
            approach:         approach,
            trigger:          trigger,
            triggerProximity: triggerProximity
        )
    }
}
