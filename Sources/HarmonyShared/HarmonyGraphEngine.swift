import Foundation

// MARK: – HarmonyGraphEngine
//
// Traversiert ein HarmonyMap-Netzwerk mit gewichteter Zufallsauswahl und Kontext-Modulation.
//
// API:
//   neighbors(of:)          — erreichbare Knoten vom gegebenen Node aus (aktiver Layer)
//   transitions(from:)      — aktive Kanten vom gegebenen Node aus
//   weightedTransitions(from:) — aktive Kanten + Zielknoten + effektives Gewicht (Phase 3.9.4b)
//   weightedChoice(from:)   — nächster Knoten, gewichtet + kontextmoduliert, deterministisch (RNG)
//   setLayer(_:)            — Layer wechseln (muss in map.layers existieren)
//   recordVisit(_:)         — Besuch eines Nodes festhalten (max. 3 Einträge im Verlauf)
//
// Kontext-Modulation (effectiveWeight):
//   Regel 1 — ii-V-Boost:      letzter Schritt war ii-V → V-I-Kante × 1.5
//   Regel 2 — Rückkehr-Dämpfung: Zielknoten in letzten 2 Schritten → × 0.4
//   Regel 3 — Spannungserhalt:  2 aufeinanderfolgende starke Kanten → schwache × 1.3
//
// Graph-Kontext (Runde 015 / F-01):
//   `history` hält bis zu 3 besuchte Nodes, damit zwei aufeinanderfolgende
//   Übergänge (history[n-3]→history[n-2] und history[n-2]→history[n-1]) als zwei
//   getrennte Kontexte auflösbar sind. Zuvor hielt `history` nur 2 Einträge; dadurch
//   fielen `lastEdge()` und `prevEdge()` auf denselben Übergang zurück und Regel 3
//   prüfte de facto eine einzelne starke Kante zweimal statt zwei verschiedener.
//   Regel 2 (Rückkehr-Dämpfung) bleibt bewusst auf die letzten 2 Schritte begrenzt
//   (`history.suffix(2)`) — die Erweiterung des Puffers auf 3 ändert dieses Verhalten
//   nicht.
//   Kantenauflösung für einen historischen Übergang berücksichtigt den aktiven Layer
//   und aggregiert bei mehreren passenden Kanten (parallele Kanten oder mehrere Layer
//   zwischen demselben Node-Paar) deren `relationTypes` als Vereinigung — keine
//   zufällige `first`-Kante mehr.
//
// Kein SceneKit, kein AppSettings, kein UI.

public final class HarmonyGraphEngine {

    private let map:         HarmonyMap
    private var activeLayer: String
    private var history:     [String] = []   // max. 3 Einträge (zuletzt besuchte Nodes)
    private var rng:         SeededRNG

    /// - Parameters:
    ///   - map:          Vollständig geladene und validierte HarmonyMap
    ///   - initialLayer: Layer-ID beim Start (muss in map.layers existieren)
    ///   - seed:         Optionaler Seed für deterministischen Betrieb.
    ///                   nil = zeitbasierter Seed (probabilistisch, nicht reproduzierbar)
    public init(map: HarmonyMap, initialLayer: String = "functional", seed: UInt64? = nil) {
        self.map         = map
        self.activeLayer = initialLayer
        self.rng         = SeededRNG(seed: seed ?? UInt64(Date().timeIntervalSince1970))
    }

    // MARK: – Öffentliche API

    /// Alle erreichbaren Knoten vom gegebenen Node aus (aktiver Layer).
    /// Berücksichtigt gerichtete und ungerichtete Kanten.
    public func neighbors(of nodeID: String) -> [HarmonyNode] {
        activeEdges(from: nodeID).compactMap { edge in
            let targetID = edge.source == nodeID ? edge.target : edge.source
            return map.nodes.first { $0.id == targetID }
        }
    }

    /// Aktive Kanten vom gegebenen Node aus (aktiver Layer).
    public func transitions(from nodeID: String) -> [HarmonyEdge] {
        activeEdges(from: nodeID)
    }

    /// Eine aktive Kante vom gegebenen Node aus, aufgelöst zu Zielknoten + effektivem Gewicht.
    /// `effectiveWeight` ist dieselbe Kontext-Modulation, die auch `weightedChoice(from:)` nutzt
    /// (ii-V-Boost, Rückkehr-Dämpfung, Spannungserhalt) — keine musikalische Sonderlogik in Konsumenten.
    public struct WeightedTransition {
        public let edge:            HarmonyEdge
        public let targetNode:      HarmonyNode
        public let effectiveWeight: Float
    }

    /// Alle aktiven Kanten vom gegebenen Node aus, aufgelöst zu Zielknoten + effektivem Gewicht.
    /// Deterministisch — keine RNG-Beteiligung. Basis für Phase-3.9.4b-Kandidatenlisten
    /// (RuntimeHarmonik.HarmonicCandidate) und für `weightedChoice(from:)`.
    public func weightedTransitions(from nodeID: String) -> [WeightedTransition] {
        activeEdges(from: nodeID).compactMap { edge in
            let targetID = edge.source == nodeID ? edge.target : edge.source
            guard let targetNode = map.nodes.first(where: { $0.id == targetID }) else { return nil }
            return WeightedTransition(
                edge:            edge,
                targetNode:      targetNode,
                effectiveWeight: effectiveWeight(edge: edge, targetID: targetID)
            )
        }
    }

    /// Wählt den nächsten Node über gewichtete Zufallsauswahl + Kontext-Modulation.
    /// Deterministisch wenn mit Seed initialisiert.
    /// Gibt nil zurück wenn keine Kanten vom Node aus existieren.
    public func weightedChoice(from nodeID: String) -> HarmonyNode? {
        let weighted = weightedTransitions(from: nodeID)
        guard !weighted.isEmpty else { return nil }

        let total = weighted.reduce(Float(0)) { $0 + $1.effectiveWeight }
        guard total > 0 else { return nil }

        // Gewichtete Zufallsauswahl via SeededRNG
        var pick = rng.f() * total
        for wt in weighted {
            pick -= wt.effectiveWeight
            if pick <= 0 {
                return wt.targetNode
            }
        }
        // Fallback: letzter Kandidat (numerische Ungenauigkeit)
        return weighted.last!.targetNode
    }

    /// Wechselt den aktiven Layer.
    /// Keine Wirkung wenn layerID nicht in map.layers existiert.
    public func setLayer(_ layerID: String) {
        guard map.layers.contains(where: { $0.id == layerID }) else {
            print("⚠️  HarmonyGraphEngine: Layer '\(layerID)' nicht in Map '\(map.id)'")
            return
        }
        activeLayer = layerID
        print("🎛  HarmonyGraphEngine: Layer → \(layerID)")
    }

    /// Registriert einen besuchten Node im Verlaufspuffer (max. 3 Einträge).
    /// 3 statt 2 Einträge, damit zwei aufeinanderfolgende Übergänge (Runde-015-Fix,
    /// siehe Typ-Kommentar) als getrennte Kontexte auflösbar sind. Regel 2
    /// (Rückkehr-Dämpfung) bleibt unverändert auf die letzten 2 Schritte begrenzt.
    public func recordVisit(_ nodeID: String) {
        history.append(nodeID)
        if history.count > 3 { history.removeFirst() }
    }

    // MARK: – Kontext-Modulation (privat)

    private func effectiveWeight(edge: HarmonyEdge, targetID: String) -> Float {
        var weight = edge.weight

        // Regel 1 — ii-V-Boost: letzter Schritt war ii-V → aktuelle V-I-Kante × 1.5
        if edge.relationTypes.contains(.vToI),
           let prev = lastTransition(), prev.relationTypes.contains(.iiToV) {
            weight *= 1.5
        }

        // Regel 2 — Rückkehr-Dämpfung: Zielknoten in letzten 2 Schritten → × 0.4
        // Bewusst nur die letzten 2 Einträge, unabhängig von der Puffergröße 3.
        if history.suffix(2).contains(targetID) {
            weight *= 0.4
        }

        // Regel 3 — Spannungserhalt: nach 2 starken Kanten schwache Kanten bevorzugen × 1.3
        let isWeak = edge.relationTypes.allSatisfy {
            $0 == .commonTone || $0 == .relMajMin || $0 == .parallelMajMin
        }
        let lastStrong = lastTransition()?.relationTypes
            .contains(where: { $0 == .vToI || $0 == .iiToV }) == true
        let prevStrong = prevTransition()?.relationTypes
            .contains(where: { $0 == .vToI || $0 == .iiToV }) == true
        if isWeak && lastStrong && prevStrong {
            weight *= 1.3
        }

        return max(weight, 0)
    }

    // MARK: – Hilfsmethoden (privat)

    /// Alle Kanten des aktiven Layers vom gegebenen Node aus.
    /// Gerichtete Kanten: nur wenn source == nodeID.
    /// Ungerichtete Kanten: wenn source == nodeID ODER target == nodeID.
    private func activeEdges(from nodeID: String) -> [HarmonyEdge] {
        map.edges.filter { edge in
            edge.layers.contains(activeLayer) &&
            (edge.source == nodeID || (!edge.directed && edge.target == nodeID))
        }
    }

    /// Deterministisch aufgelöster Kontext eines historischen Übergangs zwischen zwei
    /// Nodes: die Vereinigung der `relationTypes` aller im aktiven Layer passenden
    /// Kanten (gerichtet nur from→to, ungerichtet in beide Richtungen). Ersetzt eine
    /// einzelne, ordnungsabhängige `first`-Kante — bei parallelen Kanten oder Kanten aus
    /// anderen Layern zwischen demselben Node-Paar liefert diese Auflösung unabhängig
    /// von der Reihenfolge in `map.edges` dasselbe Ergebnis.
    private struct TransitionContext {
        let relationTypes: Set<RelationType>
    }

    private func transitionContext(from: String, to: String) -> TransitionContext? {
        let matching = map.edges.filter { edge in
            edge.layers.contains(activeLayer) &&
            ((edge.source == from && edge.target == to) ||
             (!edge.directed && edge.source == to && edge.target == from))
        }
        guard !matching.isEmpty else { return nil }
        let relationTypes = matching.reduce(into: Set<RelationType>()) { $0.formUnion($1.relationTypes) }
        return TransitionContext(relationTypes: relationTypes)
    }

    /// Kontext des letzten Übergangs (history[n-2] → history[n-1]).
    private func lastTransition() -> TransitionContext? {
        guard history.count >= 2 else { return nil }
        return transitionContext(from: history[history.count - 2], to: history[history.count - 1])
    }

    /// Kontext des vorletzten Übergangs (history[n-3] → history[n-2]) — ein von
    /// `lastTransition()` verschiedenes Node-Paar, sofern die Historie lang genug ist.
    private func prevTransition() -> TransitionContext? {
        guard history.count >= 3 else { return nil }
        return transitionContext(from: history[history.count - 3], to: history[history.count - 2])
    }
}
