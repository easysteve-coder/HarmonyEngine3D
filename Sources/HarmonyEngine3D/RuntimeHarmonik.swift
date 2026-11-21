import Foundation
import simd
import HarmonyShared

// MARK: – LocalNode
//
// Minimale, SceneKit-freie Darstellung eines existierenden Akkord-Nodes im 3D-Raum.
// Wird von HarmonyScene befüllt (SCNNode-Zugriff dort erlaubt) und von RuntimeHarmonik
// für die Kandidatenauswahl gelesen.
//
// Kein SceneKit. Kein AppSettings. Kein Audio.
// Dient ausschließlich als Daten-Brücke zwischen HarmonyScene und RuntimeHarmonik.

struct LocalNode {
    let id:        String       // Szenen-eindeutiger Key (z. B. "chord_0_0_1")
    let chordName: String       // Akkordname (z. B. "Cmaj7")
    let position:  simd_float3  // Weltposition im 3D-Raum
    let distance:  Float        // Distanz zum Spieler (von HarmonyScene vorberechnet)
}

// MARK: – HarmonicStrategy
//
// Klassifiziert die Art der Entscheidung, die RuntimeHarmonik trifft.
//
// Aktuelle Fälle:
//   .magnetismCandidate — passender Node im Raum gefunden; bereit für Phase-4.3-Magnetismus
//   .noCandidate        — GraphEngine hat Vorschlag, aber kein passender Node lokal vorhanden
//   .noSuggestion       — GraphEngine hat keinen Folgeakkord geliefert
//
// Phase 4.3 kann .identitySwap als weiteren case ergänzen ohne Änderung bestehender Logik.

enum HarmonicStrategy: String {
    case magnetismCandidate  // Vorschlag + passender lokaler Node vorhanden
    case noCandidate         // Vorschlag vorhanden, aber kein passender Node im Raum
    case noSuggestion        // kein Folgeakkord aus GraphEngine verfügbar
}

// MARK: – HarmonicMagnetFieldKind
//
// Seit K-07 in `HarmonyShared/HarmonicMagnetPreview.swift` (DesignerKit kann
// `RuntimeHarmonik` nicht importieren, braucht aber dieselbe Feld-
// klassifikation für die Construction-Kit-Simulation-Preview). `import
// HarmonyShared` oben macht `HarmonicMagnetFieldKind` hier weiterhin ohne
// Qualifikation nutzbar — keine Verhaltensänderung, reine Verschiebung.

// MARK: – HarmonicMagnetConfig
//
// Reiner Value-Typ für die harmonische Magnet-Konfiguration (Runde 021 / E-02).
// Getrennt vom proximity-basierten Magnet (FlightController.magnetTarget,
// AppSettings.flight.magnetStrength/magnetRadius) — intensity/rangeScale
// wirken ausschließlich auf die harmonische Richtungskorrektur.
//
// Wird vom App-Layer aus AppSettings.harmonicMagnet gebaut und pro
// RuntimeHarmonik.process()-Aufruf als Wert übergeben. RuntimeHarmonik selbst
// liest niemals AppSettings.
//
// Alle Felder sind bei der Konstruktion geklammert, damit UI-/UserDefaults-
// Ausreißer keine harten Sprünge im Flugverhalten erzeugen können.
//
// SceneKit-frei, AppSettings-frei, Foundation-frei (nur Float-Arithmetik).

struct HarmonicMagnetConfig {
    let isEnabled:  Bool
    /// 0…1 — skaliert ausschließlich die harmonische Magnetwirkung (Alpha-Multiplikator
    /// in FlightController), nicht den proximity-Magnet.
    let intensity:  Float
    /// 0.25…4.0 — Multiplikator auf die Preset-Basis-Reichweite (siehe `effectiveRange(preset:config:)`).
    let rangeScale: Float

    static let defaults = HarmonicMagnetConfig(isEnabled: true, intensity: 1.0, rangeScale: 1.0)

    init(isEnabled: Bool, intensity: Float, rangeScale: Float) {
        self.isEnabled  = isEnabled
        self.intensity  = max(0.0, min(intensity, 1.0))
        self.rangeScale = max(0.25, min(rangeScale, 4.0))
    }

    /// Effektive Reichweite für einen Kandidaten: Preset-Basis × rangeScale.
    /// Seit K-07 Delegation auf `HarmonicMagnetPreview.effectiveRange`
    /// (`HarmonyShared`) — dieselbe Preset→Range-Zuordnung (strong 25,
    /// medium 15, weak 8), keine zweite Kopie mehr hier.
    static func effectiveRange(preset: MagnetProfile.Preset?, config: HarmonicMagnetConfig) -> Float {
        HarmonicMagnetPreview.effectiveRange(preset: preset, rangeScale: config.rangeScale)
    }

    /// Weicher, geklammerter Falloff: 1.0 bei `distance == 0`, 0.0 an/außerhalb
    /// `range`, quadratisch dazwischen — kein harter Kraftrand (Auftrag Runde 021).
    /// Konsistent mit dem `t²`-Muster des bestehenden proximity-Magnet-Falloffs
    /// (FlightController.applyMagneticForce).
    static func falloff(distance: Float, range: Float) -> Float {
        guard range > 0, distance.isFinite, distance >= 0 else { return 0 }
        let t = 1 - min(max(distance / range, 0), 1)
        return t * t
    }
}

// MARK: – HarmonicCandidate
//
// Ein einzelner gewichteter Kandidat für das harmonische Magnetziel (Phase 3.9.4b).
//
// Felder:
//   nodeID          — Szenen-eindeutiger Key des lokalen Nodes (siehe LocalNode.id)
//   chordName       — Akkordname des Kandidaten
//   distance        — Distanz zum Spieler
//   harmonicWeight  — Anteil des effektiven Graph-Gewichts an der Summe aller
//                     Übergänge von currentChord aus (0...1, GraphEngine-Kontext-Modulation
//                     inklusive: ii-V-Boost, Rückkehr-Dämpfung, Spannungserhalt)
//   distanceWeight  — Nähe-Faktor 1 / (1 + distance), 1.0 bei distance 0, monoton fallend
//   score           — harmonicWeight × distanceWeight, bestimmt die Sortierung
//   relationTypes                — RelationType-Liste der Kante, die zu diesem Kandidaten führte
//                                   (Map-Validierung garantiert nicht-leer, siehe HarmonyMapLoader)
//   magnetFieldKind               — deterministische Klassifikation aus relationTypes
//                                   (magnetFieldKind(for:), Prioritätsreihenfolge siehe dort)
//   magnetPreset                 — MagnetProfile.Preset der Kante, die zu diesem Kandidaten
//                                   führte (nil = keine magnetProfile-Angabe in der Map, Phase 4.2a)
//   magnetRateMultiplier         — Preset-Basis × Feld-Basis × scoreBoost (siehe magnetMultipliers/
//                                   fieldMultipliers/scoreBoost in RuntimeHarmonik.process) —
//                                   Faktor auf FlightController-Basisrate
//   magnetAngularSpeedMultiplier — analog für die Winkelgeschwindigkeits-Obergrenze
//   effectiveRange                — Preset-Basis-Reichweite × HarmonicMagnetConfig.rangeScale
//                                   (Runde 021 / E-02); FlightController wendet die harmonische
//                                   Richtungskorrektur nur innerhalb dieser Reichweite an
//
// Rein wertbasiert, SceneKit-frei. Wird von HarmonyScene für Morphing/Kandidaten-Glow/
// harmonischen Magnet gelesen.

struct HarmonicCandidate {
    let nodeID:         String
    let chordName:      String
    let distance:        Float
    let harmonicWeight:  Float
    let distanceWeight:  Float
    let score:           Float
    let relationTypes:                [RelationType]
    let magnetFieldKind:               HarmonicMagnetFieldKind
    let magnetPreset:                 MagnetProfile.Preset?
    let magnetRateMultiplier:         Float
    let magnetAngularSpeedMultiplier: Float
    let effectiveRange:               Float
}

// MARK: – HarmonicMagnetInfluence
//
// Ein einzelner, in sich konsistenter Wert aus Position + Magnet-Stärke (Phase 4.2a).
// Ersetzt die frühere lose Kombination aus Zielposition (FlightController.harmonicMagnetTarget)
// und impliziten, konstanten Raten (harmonicMagnetRate/-MaxAngularSpeed). Position und Einfluss
// bewusst in einem Wert gebündelt, damit beide nie auseinanderlaufen können (siehe Auftrag Runde 013).
//
// Felder:
//   target                     — Weltposition des Magnetziels (aus chordAnchorPositions, live)
//   rateMultiplier             — Faktor auf FlightController.harmonicMagnetRateBase
//   maxAngularSpeedMultiplier  — Faktor auf FlightController.harmonicMagnetMaxAngularSpeedBase
//   score                      — HarmonicCandidate.score des zugrundeliegenden Kandidaten (Debug/HUD)
//   preset                     — MagnetProfile.Preset der zugrundeliegenden Kante (nil = neutral)
//   fieldKind                  — HarmonicMagnetFieldKind der zugrundeliegenden Kante (Phase 4.2b,
//                                 Debug/HUD)
//   relationTypes              — RelationType-Liste der zugrundeliegenden Kante (Phase 4.2b,
//                                 Debug/HUD-Weitergabe, nicht für FlightController-Logik gedacht)
//   effectiveRange              — Reichweite in Metern (Runde 021 / E-02); FlightController
//                                 wendet die Richtungskorrektur nur innerhalb dieser Distanz an
//   intensity                  — 0…1-Multiplikator aus HarmonicMagnetConfig (Runde 021 / E-02),
//                                 wird in FlightController als finaler Alpha-Faktor angewendet
//   isEnabled                  — aus HarmonicMagnetConfig (Runde 021 / E-02); false schaltet die
//                                 harmonische Richtungskorrektur komplett ab, ohne die
//                                 Kandidaten-/Entscheidungsermittlung zu beeinflussen
//
// SceneKit-frei (nur simd + MagnetProfile/RelationType aus HarmonyShared). Wird von HarmonyScene
// aus der aktuellen HarmonicDecision + der live Anker-Position gebaut, nie persistent gespeichert.

struct HarmonicMagnetInfluence {
    let target:                    simd_float3
    let rateMultiplier:            Float
    let maxAngularSpeedMultiplier: Float
    let score:                     Float
    let preset:                    MagnetProfile.Preset?
    let fieldKind:                 HarmonicMagnetFieldKind
    let relationTypes:             [RelationType]
    let effectiveRange:            Float
    let intensity:                 Float
    let isEnabled:                 Bool
}

// MARK: – HarmonicDecision
//
// Strukturiertes Ergebnis einer RuntimeHarmonik-Auswertung.
//
// Felder:
//   currentChord          — aktiver Akkord (Auslöser)
//   suggestedChord        — Akkordname des besten Kandidaten (nil wenn keine Kandidaten)
//   selectedNodeID        — ausgewählter Kandidat im Raum (nil wenn keiner) — candidates.first
//   selectedNodeDistance  — Distanz des ausgewählten Nodes zum Spieler (nil wenn keiner)
//   strategy              — Klassifizierung der Entscheidung
//   candidates            — gewichtete Kandidatenliste, deterministisch sortiert
//                           (score absteigend, bei Gleichstand distance aufsteigend,
//                           dann nodeID aufsteigend), hart begrenzt auf maxCandidates
//   magnetConfig          — die HarmonicMagnetConfig, mit der diese Entscheidung berechnet
//                           wurde (Runde 021 / E-02) — einzige Quelle für isEnabled/intensity,
//                           damit HarmonyScene.applyHarmonicDecision() nicht separat auf
//                           AppSettings zugreifen muss
//
// Keine Physikparameter. Keine UI-Daten. Keine SceneKit-Referenzen.
// Unveränderlich (let) — wird pro Akkord-Aktivierung neu erzeugt.

struct HarmonicDecision {
    let currentChord:         String            // Name des gerade aktivierten Akkords
    let suggestedChord:       String?           // Akkordname des besten Kandidaten
    let selectedNodeID:       String?           // ausgewählter Node-Key im Raum
    let selectedNodeDistance: Float?            // Distanz des ausgewählten Nodes
    let strategy:             HarmonicStrategy  // Klassifizierung der Entscheidung
    let candidates:           [HarmonicCandidate] // gewichtete Kandidatenliste (Phase 3.9.4b)
    let magnetConfig:         HarmonicMagnetConfig // Runde 021 / E-02
}

// MARK: – RuntimeHarmonik
//
// Mittelschicht zwischen HarmonyGraphEngine und HarmonyScene.
//
// Verantwortung (aktuell):
//   - Empfängt Akkord-Aktivierungs-Events vom OutputCoordinator
//   - Pflegt den GraphEngine-Verlauf (recordVisit → ii-V-Boost, Rückkehr-Dämpfung)
//   - Holt strukturierten Vorschlag von der GraphEngine
//   - Filtert lokale Nodes nach Akkordname (candidates)
//   - Wählt nächstgelegenen Kandidaten (kleinste Distanz, kein Zufall, keine Physik)
//   - Wertet MagnetProfile der gewählten Kante aus (Preset + moderater Score-Boost,
//     Phase 4.2a) und die RelationTypes (Feldklassifikation, Phase 4.2b) und liefert
//     die kombinierten Multiplikatoren pro Kandidat mit
//   - Gibt HarmonicDecision zurück + loggt strukturiert
//
// Noch NICHT:
//   - Magnetfelder direkt auf HarmonyScene anwenden (das bleibt HarmonyScenes Aufgabe —
//     RuntimeHarmonik liefert nur die Werte, siehe HarmonicCandidate.magnetRateMultiplier)
//   - Identitätswechsel auslösen
//
// Kein SceneKit. Kein AppSettings. Kein Audio. Kein SwiftUI.
// HarmonyScene konsumiert HarmonicDecision für Magnetismus (Phase 4.2a), ohne diese Klasse zu ändern.

final class RuntimeHarmonik {

    // Harte Obergrenze der Kandidatenliste (Phase 3.9.4b).
    // 4, nicht mehr — konsistent mit `impulseMaxNeighbors` (HarmonyScene, Runde 010):
    // dieselbe Größenordnung sorgt dafür, dass Kandidaten-Glow und Nachbarschafts-Impuls
    // im Raum visuell zusammenpassen, statt gegeneinander zu konkurrieren.
    private let maxCandidates = 4

    // Preset → (rate, angularSpeed)-Basismultiplikatoren (Phase 4.2a, Auftrag Runde 013).
    // medium/nil bewusst neutral (1.0/1.0), damit Kanten ohne magnetProfile den Magnet
    // nahezu wie zuvor verhalten lassen (Akzeptanzkriterium).
    private static func magnetMultipliers(for preset: MagnetProfile.Preset?) -> (rate: Float, angular: Float) {
        switch preset {
        case .weak:          return (0.70, 0.75)
        case .strong:        return (1.30, 1.20)
        case .medium, .none: return (1.00, 1.00)
        }
    }

    // relationTypes → HarmonicMagnetFieldKind: seit K-07 Delegation auf
    // `HarmonicMagnetPreview.fieldKind(for:)` (`HarmonyShared`) — dieselbe
    // deterministische Prioritätsreihenfolge (Dominant-/Prädominant-
    // Bewegungen vor Substitution vor relativ vor commonTone vor generic),
    // keine zweite Kopie mehr hier.

    // FieldKind → (rate, angularSpeed)-Basismultiplikatoren (Phase 4.2b, Auftrag Runde 014).
    // Modulieren die MagnetProfile-Preset-Basis zusätzlich, nicht anstelle davon — Preset
    // bleibt die primäre Stärke der Kante, RelationType beschreibt den Feldcharakter.
    private static func fieldMultipliers(for kind: HarmonicMagnetFieldKind) -> (rate: Float, angular: Float) {
        switch kind {
        case .dominantResolution: return (1.15, 1.10)
        case .preDominantMotion:  return (1.08, 1.05)
        case .substitution:       return (1.00, 1.15)
        case .relative:           return (0.90, 0.85)
        case .commonTone:         return (0.78, 0.75)
        case .generic:            return (0.85, 0.80)
        }
    }

    // scoreBoost moduliert die Preset-/Feld-Basis moderat (0.85...1.15), abgeleitet aus
    // harmonicWeight statt dem rohen `score` — score wird von distanceWeight dominiert,
    // das bei realistischen Distanzen (>> 1) sehr klein ist und daher als Multiplikator
    // ungeeignet wäre (Auftrag Runde 013). harmonicWeight ist bereits 0...1-normalisiert
    // und spiegelt wider, wie stark die GraphEngine diesen Übergang relativ zu den
    // anderen Optionen von currentChord aus favorisiert — ein deterministisches, in sich
    // beschränktes Maß ohne zusätzliche Normalisierung.
    private static func scoreBoost(harmonicWeight: Float) -> Float {
        0.85 + min(max(harmonicWeight, 0), 1) * 0.30
    }

    private let graphEngine: HarmonyGraphEngine

    init(graphEngine: HarmonyGraphEngine) {
        self.graphEngine = graphEngine
    }

    // MARK: – Kern-API

    /// Verarbeitet einen Akkord-Aktivierungs-Event mit optionaler lokaler Node-Liste.
    ///
    /// - Parameter currentChord: Name des soeben aktivierten Akkords
    /// - Parameter localNodes:   Alle aktuell geladenen Akkord-Nodes mit Distanz (von HarmonyScene)
    /// - Returns: HarmonicDecision — Kandidatenliste + ausgewähltes Ziel + Strategie
    @discardableResult
    /// - Parameter magnetConfig: Wert-Snapshot der harmonischen Magnet-Einstellungen
    ///   (Runde 021 / E-02). Default `.defaults` hält bestehende Aufrufer/Tests ohne
    ///   Änderung lauffähig; der App-Layer übergibt den echten, aus `AppSettings.
    ///   harmonicMagnet` gebauten Snapshot (siehe HarmonyEngine3DApp.onGraphHook).
    ///   RuntimeHarmonik liest AppSettings dabei nie selbst.
    func process(
        currentChord: String,
        localNodes: [LocalNode] = [],
        magnetConfig: HarmonicMagnetConfig = .defaults
    ) -> HarmonicDecision {

        // Kontext pflegen: Verlauf für ii-V-Boost, Rückkehr-Dämpfung, Spannungserhalt
        graphEngine.recordVisit(currentChord)

        // Alle aktiven Graph-Übergänge von currentChord aus, deterministisch (keine RNG-Beteiligung).
        // Ersetzt den früheren Einzelvorschlag aus weightedChoice(from:) — dessen RNG-Zufallszug
        // lieferte nur eine von mehreren plausiblen Optionen. weightedChoice(from:) bleibt als
        // API in HarmonyGraphEngine unverändert nutzbar, wird hier aber nicht mehr aufgerufen.
        let weightedTransitions = graphEngine.weightedTransitions(from: currentChord)
        let totalWeight = weightedTransitions.reduce(Float(0)) { $0 + $1.effectiveWeight }

        // Pro Zielakkord den nächstgelegenen lokalen Node auswählen (kleinste Distanz,
        // Tie-Break über die ID — localNodes stammt aus einem Dictionary mit instabiler
        // Iterationsreihenfolge, Phase 3.9.1b). Liefern mehrere Kanten denselben lokalen
        // Node (z. B. mehrere Graph-Knoten mit identischem Akkordnamen), gewinnt die
        // Kante mit dem höheren effektiven Gewicht.
        var bestByNode: [String: (transition: HarmonyGraphEngine.WeightedTransition, local: LocalNode)] = [:]
        for wt in weightedTransitions {
            let nearest = localNodes
                .filter { $0.chordName == wt.targetNode.id }
                .sorted { lhs, rhs in
                    if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
                    return lhs.id < rhs.id
                }
                .first
            guard let nearest else { continue }
            if let existing = bestByNode[nearest.id], existing.transition.effectiveWeight >= wt.effectiveWeight {
                continue
            }
            bestByNode[nearest.id] = (wt, nearest)
        }

        // Score = harmonicWeight (Anteil am Graph-Gesamtgewicht) × distanceWeight (Nähe-Faktor).
        var candidates: [HarmonicCandidate] = bestByNode.values.map { entry in
            let harmonicWeight = totalWeight > 0 ? entry.transition.effectiveWeight / totalWeight : 0
            let distanceWeight = 1 / (1 + entry.local.distance)
            let relationTypes = entry.transition.edge.relationTypes
            let fieldKind     = HarmonicMagnetPreview.fieldKind(for: relationTypes)
            let preset        = entry.transition.edge.magnetProfile?.preset
            let presetBase    = Self.magnetMultipliers(for: preset)
            let fieldBase     = Self.fieldMultipliers(for: fieldKind)
            let boost         = Self.scoreBoost(harmonicWeight: harmonicWeight)
            return HarmonicCandidate(
                nodeID:        entry.local.id,
                chordName:     entry.local.chordName,
                distance:      entry.local.distance,
                harmonicWeight: harmonicWeight,
                distanceWeight: distanceWeight,
                score:          harmonicWeight * distanceWeight,
                relationTypes:  relationTypes,
                magnetFieldKind: fieldKind,
                magnetPreset:                 preset,
                magnetRateMultiplier:         presetBase.rate    * fieldBase.rate    * boost,
                magnetAngularSpeedMultiplier: presetBase.angular * fieldBase.angular * boost,
                effectiveRange:               HarmonicMagnetConfig.effectiveRange(preset: preset, config: magnetConfig)
            )
        }

        // Deterministische Sortierung: score absteigend, dann distance aufsteigend,
        // dann nodeID aufsteigend (Gleichstand-Tie-Break, reproduzierbar).
        candidates.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
            return lhs.nodeID < rhs.nodeID
        }
        if candidates.count > maxCandidates {
            candidates = Array(candidates.prefix(maxCandidates))
        }

        // RuntimeHarmonik decides harmonic strategy.
        // HarmonyScene applies runtime decisions but does not decide harmonic strategy.
        let best = candidates.first

        // Strategie bestimmen
        let strategy: HarmonicStrategy
        if weightedTransitions.isEmpty {
            strategy = .noSuggestion
        } else if best == nil {
            strategy = .noCandidate
        } else {
            strategy = .magnetismCandidate
        }

        let decision = HarmonicDecision(
            currentChord:         currentChord,
            suggestedChord:       best?.chordName,
            selectedNodeID:       best?.nodeID,
            selectedNodeDistance: best?.distance,
            strategy:             strategy,
            candidates:           candidates,
            magnetConfig:         magnetConfig
        )

        // Strukturiertes Logging
        let selectedStr: String
        if let sel = best {
            let relStr = sel.relationTypes.map { $0.rawValue }.joined(separator: "+")
            selectedStr = "\(sel.nodeID) (distance: \(String(format: "%.1f", sel.distance)), score: \(String(format: "%.5f", sel.score))"
                + ", magnet: \(sel.magnetPreset?.rawValue ?? "–")"
                + ", field: \(sel.magnetFieldKind.rawValue) [\(relStr)]"
                + " rate×\(String(format: "%.2f", sel.magnetRateMultiplier))"
                + " angular×\(String(format: "%.2f", sel.magnetAngularSpeedMultiplier))"
                + " range=\(String(format: "%.1f", sel.effectiveRange)))"
        } else {
            selectedStr = "none"
        }
        let candidateStr = candidates
            .map { "\($0.chordName)@\(String(format: "%.5f", $0.score))" }
            .joined(separator: ", ")
        print("[RuntimeHarmonik]"
            + " current: \(decision.currentChord)"
            + " | suggested: \(decision.suggestedChord ?? "–")"
            + " | candidates: [\(candidateStr)]"
            + " | selected: \(selectedStr)"
            + " | strategy: \(decision.strategy.rawValue)"
            + " | magnet: enabled=\(magnetConfig.isEnabled) intensity=\(String(format: "%.2f", magnetConfig.intensity))"
            + " rangeScale=\(String(format: "%.2f", magnetConfig.rangeScale))")

        return decision
    }
}
