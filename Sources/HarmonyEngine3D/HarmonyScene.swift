import SceneKit
import AppKit
import Combine
import HarmonyShared

// MARK: – ChordPositionEntry / resolveChordPositionMap
//
// Reine, SceneKit-freie Hilfsfunktion für `HarmonyScene.buildChordPositionMap()`
// (Runde 038 / V-00b, Fable-5-Review Finding A8). Existieren mehrere
// sichtbare Instanzen desselben Akkordnamens (Chunk-Streaming erzeugt das
// systematisch), entschied vorher die prozesszufällige Dictionary-
// Iterationsreihenfolge von `chordNodes` per Last-Writer-Wins, welche
// Position gewinnt — dieselbe Eingabe konnte je nach Prozessstart zu einem
// anderen Autopilot-Ziel führen. `resolveChordPositionMap` sortiert die
// Einträge zuerst deterministisch nach `key` (Szenen-eindeutiger Node-
// Schlüssel) und lässt danach den letzten gewinnen — welche Instanz konkret
// gewinnt, ist weiterhin beliebig, aber bei gleicher Eingabe immer
// dieselbe. Keine SceneKit-Abhängigkeit, direkt ohne HarmonyScene-Instanz
// testbar.

struct ChordPositionEntry {
    let key:      String
    let name:     String
    let position: simd_float3
    let visible:  Bool
}

func resolveChordPositionMap(entries: [ChordPositionEntry]) -> [String: simd_float3] {
    var map: [String: simd_float3] = [:]
    for entry in entries.sorted(by: { $0.key < $1.key }) where entry.visible {
        map[entry.name] = entry.position
    }
    return map
}

// MARK: – HarmonyScene

final class HarmonyScene: SCNScene {

    private(set) var cameraNode = SCNNode()

    // ── Dynamische Node-Pools ────────────────────────────────────────────
    private(set) var chordNodes:      [String: SCNNode] = [:]
    private(set) var bassPortalNodes: [String: SCNNode] = [:]
    private(set) var cloudNodes:      [String: SCNNode] = [:]

    // ── Akkord-Anker-Registry (Phase 3.9.3a) ─────────────────────────────
    // Entkoppelt von chordNodes (SCNNode-Referenzen für Rendering).
    // Wird beim Platzieren eines Akkordnodes einmal gesetzt, beim Unload gelöscht.
    // Einzige Quelle für musikalische Akkordpositionen (Trigger, Kandidatenwahl,
    // Magnetziel, Autopilot-Positionsmap). SCNNode.position/simdWorldPosition
    // bleibt für Rendering/Sichtbarkeit erlaubt, ist aber nicht mehr Datenquelle
    // für harmonische Logik — künftige Render-Bewegung/Morphing kann Trigger
    // und Kandidatenwahl damit nicht mehr versehentlich beeinflussen.
    private var chordAnchorPositions: [String: simd_float3] = [:]

    // ── Akkord-Render-Offset-Registry (Phase 3.9.3a, Runde 009) ──────────
    // Rein visueller Versatz zur Anker-Position. Default .zero — für diese
    // Runde wird nirgends ein Nicht-Null-Offset gesetzt, die sichtbare Welt
    // bleibt unverändert. Infrastruktur für künftiges Morphing (Phase 3.9.4+).
    // Musikalische Logik darf hierauf niemals zugreifen — nur die Render-
    // Position-Helfer (chordRenderPosition/applyChordRenderPosition) lesen sie.
    private var chordRenderOffsets: [String: simd_float3] = [:]

    /// Render-Position eines Akkordnodes: Anker + visueller Offset.
    /// nil wenn kein Anker vorhanden (Node nicht/nicht mehr registriert).
    private func chordRenderPosition(for key: String) -> simd_float3? {
        guard let anchor = chordAnchorPositions[key] else { return nil }
        return anchor + (chordRenderOffsets[key] ?? .zero)
    }

    /// Setzt SCNNode.position aus anchor + offset. No-op wenn Node oder Anker fehlt.
    private func applyChordRenderPosition(key: String) {
        guard let node = chordNodes[key], let renderPos = chordRenderPosition(for: key) else { return }
        node.position = SCNVector3(renderPos)
    }

    /// Setzt den visuellen Render-Offset eines Akkordnodes und wendet ihn sofort an.
    private func setChordRenderOffset(_ offset: simd_float3, for key: String) {
        chordRenderOffsets[key] = offset
        applyChordRenderPosition(key: key)
    }

    // ── Harmonischer Impuls + Nachbarschafts-Antwort (Phase 3.9.4a) ──────
    // Erster Verbraucher von chordRenderOffsets: wenn ein Akkord aktiviert wird,
    // bekommen seine gewichteten Nachbarn im aktiven Layer einen kurzen, zerfallenden
    // Render-Offset in Richtung des Impulsursprungs. Rein visuell — Trigger, Distanzen,
    // Kandidatenwahl und Notes lesen ausschließlich chordAnchorPositions und werden von
    // hier nie beeinflusst. Nur im JSON-Web-Modus aktiv (echtes Graph/Layer-Wissen aus
    // jsonWebMap); ohne Map-Info bleibt triggerHarmonicImpulse ein stabiler No-op.
    private struct ChordImpulse {
        var amplitude: Float        // 0...1, zerfällt linear auf 0
        var direction: simd_float3  // normiert, vom Nachbarn zum Impulsursprung
    }
    private var chordImpulses: [String: ChordImpulse] = [:]

    private let impulseMaxNeighbors:   Int   = 4      // harte Obergrenze gleichzeitig aktiver Nachbarn
    private let impulseDecayDuration:  Float = 0.9    // Sekunden bis Amplitude 0
    private let impulseMaxOffset:      Float = 6.0    // Einheiten Auslenkung bei Amplitude 1.0

    /// Löst einen Impuls auf die gewichteten Nachbarn von `activatedKey` aus.
    /// Gewichtung aus Graph (Kante vorhanden) + Layer (aktiver Layer) + Relation
    /// (edge.weight) + Distanz. Deterministische Nachbarauswahl bei Gleichstand
    /// (Score absteigend, dann Node-Key aufsteigend).
    private func triggerHarmonicImpulse(from activatedKey: String) {
        guard let map = jsonWebMap,
              let activeAnchor = chordAnchorPositions[activatedKey],
              let activeName   = chordDataMap[activatedKey]?.name
        else { return }   // kein Map-Wissen → stabiler No-op

        struct Scored { let key: String; let score: Float }
        var scored: [Scored] = []
        for edge in map.edges where edge.layers.contains(jsonWebLayer) {
            let neighborName: String?
            if edge.source == activeName {
                neighborName = edge.target
            } else if !edge.directed && edge.target == activeName {
                neighborName = edge.source
            } else {
                neighborName = nil
            }
            guard let nName = neighborName else { continue }
            let neighborKey = "chord_json_\(nName)"
            guard neighborKey != activatedKey,
                  let node = chordNodes[neighborKey], node.opacity > 0.5,
                  let nAnchor = chordAnchorPositions[neighborKey]
            else { continue }

            let dist = simd_distance(activeAnchor, nAnchor)
            guard dist > 0.001 else { continue }
            let score = edge.weight / (1.0 + dist / 100.0)
            scored.append(Scored(key: neighborKey, score: score))
        }

        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.key < $1.key }

        for s in scored.prefix(impulseMaxNeighbors) {
            guard let nAnchor = chordAnchorPositions[s.key] else { continue }
            let direction = simd_normalize(activeAnchor - nAnchor)
            chordImpulses[s.key] = ChordImpulse(amplitude: min(s.score, 1.0), direction: direction)
        }
    }

    /// Zerfall + Anwendung aller aktiven Impulse (Render-Thread, einmal pro Frame).
    /// Erst Updates/Removals sammeln, dann mutieren — lesbarer und robuster als eine
    /// Mutation von `chordImpulses` während der eigenen Iteration (Runde 011, Review-Hinweis).
    private func updateHarmonicImpulses(deltaTime dt: Float) {
        guard !chordImpulses.isEmpty else { return }

        var expired: [String] = []
        var updated: [String: ChordImpulse] = [:]
        for (key, impulse) in chordImpulses {
            let newAmplitude = impulse.amplitude - dt / impulseDecayDuration
            if newAmplitude <= 0 {
                expired.append(key)
            } else {
                updated[key] = ChordImpulse(amplitude: newAmplitude, direction: impulse.direction)
            }
        }

        // morphingIntensity (Phase 3.9.4c) — reiner Render-Multiplikator. Bei 0.0 fällt der
        // Offset auf .zero, der Zerfall selbst (chordImpulses-State) läuft unverändert weiter,
        // damit ein späteres Hochregeln des Reglers ohne Neuauslösung sofort sichtbar wird.
        let morphing = Float(AppSettings.shared.render.morphingIntensity)

        for key in expired {
            chordImpulses.removeValue(forKey: key)
            setChordRenderOffset(.zero, for: key)
        }
        for (key, impulse) in updated {
            chordImpulses[key] = impulse
            setChordRenderOffset(impulse.direction * (impulse.amplitude * impulseMaxOffset * morphing), for: key)
        }
    }

    // ── Licht-Flash bei Akkord-Trigger ───────────────────────────────────
    private let chordFlashNode = SCNNode()

    // ── Direktionales Hauptlicht (für Qualitäts-Toggle) ──────────────────
    private var directionalLightNode: SCNNode?

    private(set) var chordDataMap:   [String: ChordData] = [:]
    private var portalBassNote:      [String: Int]        = [:]

    // ── Gesendete MIDI-Noten (Phase 3.9.1a) ──────────────────────────────
    // Snapshot der tatsächlich oktavverschobenen, gesendeten Noten – getrennt von
    // chordDataMap/portalBassNote, da CH3 (chordToneProvider) weiterhin die
    // unverschobenen Basisnoten von chordDataMap braucht und selbst verschiebt.
    // noteOff liest ausschließlich hier – nie aus der aktuellen AppSettings-Oktavlage
    // rekonstruiert, da chordOctaveShift/bassOctaveShift sich während eine Note
    // klingt geändert haben könnte (führte sonst zu hängenden Noten).
    // Chord-Snapshot lebt seit Runde 026 / E-06a in interactionRuntime,
    // Bass-Snapshot seit Runde 027 / E-06b ebenfalls (siehe
    // InteractionRuntime.bassOutputNote(forKey:)).

    // ── Bass-Portal-Triggergeometrie ─────────────────────────────────────
    // Entkoppelt von bassPortalNodes (SCNNode-Referenzen für Rendering).
    // Wird beim Platzieren eines Portals geschrieben und beim Unload gelöscht.
    // updatePortalProximity liest ausschließlich hier — kein simdWorldPosition-Zugriff.
    //
    // Inhalt: Weltposition des Ringmittelpunkts (= Container-Origin).
    // Triggerzone: Kugel-Hitbox mit Radius portalTrigger um diesen Punkt.
    // Die visuelle Ringform (SCNTorus) ist bewusst NICHT die Triggergeometrie.
    // Prinzip: innerhalb des Radius = aktiv, außerhalb = inaktiv. Keine Richtungslogik.
    private var bassPortalPositions: [String: simd_float3] = [:]

    // ── Interaction-Runtime (Proximity + Trigger für alle drei Kanäle) ────
    // SceneKit-frei, besitzt TriggerEngine je Kanal + VoiceLeadingEngine
    // (Chord, Runde 026 / E-06a) + MelodyEngine (Cloud, Runde 027 / E-06b).
    // HarmonyScene behält nur noch die Render-/Positions-Datenschicht
    // (chordDataMap/chordAnchorPositions/bassPortalPositions/cloudNodes/
    // portalBassNote) und die SceneKit-Helfer, siehe InteractionRuntime.swift.
    private var interactionRuntime = InteractionRuntime()

    // ── Chord-Pool + Kanten ──────────────────────────────────────────────
    private var allChords: [ChordData] = []
    private var allEdges:  [EdgeData]  = []   // für Autopilot + Verbindungslinien

    // ── Autopilot-Engine (HarmonyShared, kein SceneKit) ──────────────────
    // private(set): SceneKitView liest targetPosition direkt, ohne SCNVector3-Konvertierung
    private(set) var autopilotEngine = AutopilotEngine()
    /// Name des nächsten Akkords (für HUD)
    var autopilotNextChordName: String { autopilotEngine.targetChordName }

    // ── Netzwerk-Verbindungslinien ────────────────────────────────────────
    private var edgesNode: SCNNode?

    // ── Melodie-Presets ──────────────────────────────────────────────────
    //
    //  MelodyEngine (Presets/Skalen/Voice-Leading) lebt seit Runde 027 /
    //  E-06b in interactionRuntime. HarmonyScene delegiert nextMelodyPreset/
    //  prevMelodyPreset und feuert Callbacks.
    //  Umschalten per L1 / R1 am Controller (OutputCoordinator verdrahtet das).

    var currentMelodyPresetName: String { interactionRuntime.currentMelodyPresetName }

    func nextMelodyPreset() {
        let name = interactionRuntime.nextMelodyPreset()
        onMelodyPresetChanged?(name)
    }
    func prevMelodyPreset() {
        let name = interactionRuntime.prevMelodyPreset()
        onMelodyPresetChanged?(name)
    }

    // ── Chunk-System ─────────────────────────────────────────────────────
    private var loadedChunks:   [ChunkCoord: [SCNNode]] = [:]
    private var lastChunkCenter = ChunkCoord(x: Int.max, y: Int.max, z: Int.max)
    private var chunkLoadQueue: [ChunkCoord] = []   // gestaffelt: max 2 pro Frame

    // Chunk-Berechnungslogik (SceneKit-frei, deterministisch).
    // chunkSize und loadRadius werden zentral hier gehalten.
    private let chunkLogic = ChunkLogic(chunkSize: 160.0, loadRadius: 3)

    // ── Trigger-Radien: live aus AppSettings ─────────────────────────────
    private var chordTrigger:  CGFloat { CGFloat(AppSettings.shared.harmony.chordTrigger)  }
    private var portalTrigger: CGFloat { CGFloat(AppSettings.shared.harmony.portalTrigger) }
    private var cloudTrigger:  CGFloat { CGFloat(AppSettings.shared.harmony.cloudTrigger)  }

    // ── Combine-Abonnements ───────────────────────────────────────────────
    private var settingsCancellables = Set<AnyCancellable>()

    // ── Render-Commands: thread-sichere Queue statt loser Pending-Flags ───
    // Runde 025 / E-05. Settings-Änderungen (Main-Thread-Combine-Sinks) und
    // interne Render-Thread-Kaskaden (z. B. reloadAllChunks() → .visibilityRebuild)
    // enqueuen gleichermaßen über enqueueRenderCommand(_:) — von jedem Thread
    // sicher aufrufbar. Konsumiert wird ausschließlich innerhalb von
    // updateProximity(...) (Render-Thread), siehe drainRenderCommands(phase:).
    private let commandQueue = RenderCommandQueue()

    private func enqueueRenderCommand(_ command: RenderCommand) {
        commandQueue.enqueue(command)
    }

    private var curatedNetworkFilename   = ""             // aktiver kuratierter Layout-Typ
    // Kamera-Reset nach Netzwerkwechsel: SceneKitView liest und wendet auf FlightState an
    private(set) var pendingCameraReset: simd_float3? = nil

    func consumePendingCameraReset() -> simd_float3? {
        defer { pendingCameraReset = nil }
        return pendingCameraReset
    }

    /// Kamera-Reset anfordern und Trigger-Sicherung scharf stellen (Phase 3.9.1d).
    /// Trigger bleiben gesperrt, bis sich die Kamera nach dem Reset um
    /// triggerArmDistance vom neuen Startpunkt entfernt hat. Der eigentliche
    /// pendingCameraReset-Wert wird erst beim Drain von .cameraReset gesetzt
    /// (Runde 025 / E-05) — triggersArmed/armReferencePos bleiben bewusst
    /// synchron mit dem Aufruf, nicht mit dem späteren Drain.
    private func requestCameraReset(_ pos: simd_float3) {
        enqueueRenderCommand(.cameraReset(pos))
        triggersArmed      = false
        armReferencePos    = nil
    }

    // ── Kuratierter Modus (Status Quo Easter Egg) ─────────────────────────
    // Statt unendlichem Raum: feste Bühnen-Aufstellung mit wenigen Objekten
    private var curatedMode            = false
    private let curatedCoord           = ChunkCoord(x: 999999, y: 999999, z: 999999)

    // ── JSON-Web-Modus (Entwicklungsmodus ab v1) ───────────────────────────
    // Wenn eine HarmonyMap übergeben wird, wird die 3D-Welt direkt aus dem
    // JSON erzeugt statt aus dem Chunk-System. Das Chunk-System und der
    // Settings-Netzwerkwechsel werden dann vollständig überbrückt.
    // jsonWebMap = nil → klassischer Chunk-Betrieb (Fallback unberührt).
    private var jsonWebMap:  HarmonyMap? = nil
    private var jsonWebMode: Bool        { jsonWebMap != nil }
    private let jsonWebCoord             = ChunkCoord(x: 888888, y: 888888, z: 888888)

    // Aktiver Layer für den JSON-Web-Modus (Phase 3.9.3b). Bestimmt, welche Nodes
    // der Map überhaupt gebaut/getriggert werden — siehe HarmonyMap.activeNodeIDs(in:).
    private var jsonWebLayer: String = "functional"

    // ── Spawn-Sicherheit (Phase 3.9.1d) ─────────────────────────────────
    // Nach einem Kamera-Reset darf kein Trigger sofort im selben Startzustand
    // feuern, nur weil die neue Position zufällig in einem Trigger-Radius liegt.
    // Gesperrt bis die Kamera sich um triggerArmDistance vom Reset-Punkt entfernt hat.
    private var triggersArmed:    Bool = true
    private var armReferencePos:  simd_float3? = nil
    private let triggerArmDistance: Float = 5.0

    // ── Magnetismus-Ziel (Phase 4.3) ─────────────────────────────────────
    // Einzige Quelle der Wahrheit: die Node-ID der letzten HarmonicDecision.
    // Gesetzt/gelöscht in applyHarmonicDecision(), ausschließlich auf dem Render-Thread.
    // Kein Pending-Flag nötig, da onGraphHook synchron auf dem Render-Thread feuert.
    //
    // magnetTargetPosition ist eine computed property — kein eigener Zustand.
    // Sie liest die Anker-Position aus chordAnchorPositions (Phase 3.9.3a),
    // nicht mehr die live simdWorldPosition des Render-Nodes.
    // Ist der Anker nicht (mehr) vorhanden, liefert sie automatisch nil.
    private var currentMagnetNodeID: String? = nil

    // Statischer (nicht-positionaler) Anteil des aktuellen Magnet-Einflusses (Phase 4.2a,
    // erweitert um fieldKind/relationTypes in Phase 4.2b).
    // Gemeinsam mit currentMagnetNodeID in applyHarmonicDecision() gesetzt/gelöscht.
    // Die Zielposition bleibt weiterhin live aus chordAnchorPositions abgeleitet
    // (siehe magnetInfluence) — hier wird nur das Profil/Score/Feld-Ergebnis der zuletzt
    // gewählten HarmonicCandidate gehalten.
    private var currentMagnetProfile: (
        rateMultiplier: Float, maxAngularSpeedMultiplier: Float,
        score: Float, preset: MagnetProfile.Preset?,
        fieldKind: HarmonicMagnetFieldKind, relationTypes: [RelationType],
        effectiveRange: Float, intensity: Float, isEnabled: Bool
    )? = nil

    /// Aktuelle Magnet-Zielposition — aus chordAnchorPositions abgeleitet, nie gespeichert.
    /// nil wenn kein Ziel aktiv oder der Anker nicht mehr vorhanden ist.
    var magnetTargetPosition: simd_float3? {
        guard let id = currentMagnetNodeID else { return nil }
        return chordAnchorPositions[id]
    }

    /// Aktueller Magnet-Einfluss für FlightController (Phase 4.2a, Feldklassifikation
    /// Phase 4.2b) — bündelt Zielposition (live aus chordAnchorPositions) und die
    /// Profil-/Feld-/Score-Multiplikatoren der zuletzt gewählten HarmonicCandidate in
    /// einem Wert, damit beide nie auseinanderlaufen können.
    /// nil wenn kein Ziel aktiv oder der Anker nicht mehr vorhanden ist.
    var magnetInfluence: HarmonicMagnetInfluence? {
        guard let id = currentMagnetNodeID,
              let pos = chordAnchorPositions[id],
              let profile = currentMagnetProfile else { return nil }
        return HarmonicMagnetInfluence(
            target:                    pos,
            rateMultiplier:            profile.rateMultiplier,
            maxAngularSpeedMultiplier: profile.maxAngularSpeedMultiplier,
            score:                     profile.score,
            preset:                    profile.preset,
            fieldKind:                 profile.fieldKind,
            relationTypes:             profile.relationTypes,
            effectiveRange:            profile.effectiveRange,
            intensity:                 profile.intensity,
            isEnabled:                 profile.isEnabled
        )
    }

    // ── Callbacks ────────────────────────────────────────────────────────
    var onChordActivated:         ((ChordData) -> Void)?
    var onChordDeactivated:       ((ChordData) -> Void)?
    var onBassNoteOn:             ((Int) -> Void)?
    var onBassNoteOff:            ((Int) -> Void)?
    var onMelodyNote:             ((Int) -> Void)?
    var onMelodyNoteWithVelocity: ((Int, UInt8) -> Void)?
    var onMelodyNoteOff:          ((Int) -> Void)?
    var onMelodyPresetChanged:    ((String) -> Void)?

    // Annäherungs-Callbacks: (label, proximity 0…1), feuern jeden Frame
    var onNearestChord:  ((String, Float) -> Void)?
    var onNearestPortal: ((String, Float) -> Void)?
    var onNearestCloud:  ((String, Float) -> Void)?

    // Radar-Snapshot-Callback: kontinuierlich (~10 Hz), nur für Debug-Anzeige.
    // Parameter: (localNodes, playerPosition, magnetTarget).
    // magnetTarget = magnetTargetPosition (computed: currentMagnetNodeID → chordAnchorPositions[id]).
    // Aufgerufen auf dem Render-Thread — AppModel dispatcht auf Main Thread.
    // Kein Inhalt außerhalb des App Layers nutzt diesen Callback.
    var onRadarSnapshot: (([LocalNode], simd_float3, simd_float3?) -> Void)?

    // Frame-Zähler für Radar-Throttle (6 Frames ≈ 10 Hz bei 60 fps)
    private var radarFrameCounter = 0

    // graphSuggest wurde hier als temporärer Test entfernt (3.9.0 → 3.9.1).
    // Harmonische Logik soll lokal auf bestehende Nodes wirken, nicht über
    // verzögerte Neuerzeugung in Chunks. Standardmechanismus: Phase 4.3 (Magnetismus).
    // Bis dahin bleibt die Chunk-Generierung von der GraphEngine unbeeinflusst.

    /// Töne des aktuell aktiven Akkords – für Chord-Tone-Spieler am linken Stick
    var activeChordNotes: [Int] {
        guard let name = interactionRuntime.activeKey,
              let data = chordDataMap[name] else { return [] }
        return data.midiNotes
    }

    /// Töne des nächsten Akkords (aktiv ODER nur in der Annäherungs-Zone).
    /// Damit ist der linke Stick schon benutzbar bevor der Trigger ausgelöst wird.
    var nearestChordNotes: [Int] {
        if let name = interactionRuntime.activeKey,   let data = chordDataMap[name] { return data.midiNotes }
        if let name = interactionRuntime.lastApproachKey, let data = chordDataMap[name] { return data.midiNotes }
        return []
    }

    /// Alle aktuell geladenen Akkord-Nodes als SceneKit-freie LocalNode-Liste.
    /// Anker-Position und Spieler-Distanz werden hier berechnet (Phase 3.9.3a:
    /// Position kommt aus chordAnchorPositions, nicht mehr aus dem Render-Node).
    /// Wird von RuntimeHarmonik für die lokale Kandidatenauswahl genutzt.
    /// Aufgerufen auf dem Render-Thread.
    ///
    /// HarmonyScene applies runtime decisions but does not decide harmonic strategy.
    var localChordNodes: [LocalNode] {
        let camPos = cameraNode.simdWorldPosition
        return chordNodes.compactMap { (key, _) in
            guard let chordData = chordDataMap[key], let pos = chordAnchorPositions[key] else { return nil }
            let dist = simd_distance(pos, camPos)
            return LocalNode(id: key, chordName: chordData.name, position: pos, distance: dist)
        }
    }

    // MARK: – RuntimeHarmonik-Schnittstelle

    /// Konsumiert eine HarmonicDecision und setzt currentMagnetNodeID + currentMagnetProfile.
    ///
    /// Aufgerufen auf dem Render-Thread (via onChordActivated → OutputCoordinator → onGraphHook).
    /// HarmonyScene wendet die Entscheidung an — sie trifft keine eigene Harmonieentscheidung.
    ///
    /// Nur Node-ID + Profil-Multiplikatoren werden gespeichert. Die Position wird nie
    /// persistent gehalten — magnetTargetPosition/magnetInfluence leiten sie bei jedem
    /// Zugriff live aus chordAnchorPositions ab.
    func applyHarmonicDecision(_ decision: HarmonicDecision) {
        applyCandidateGlow(candidates: decision.candidates)

        switch decision.strategy {

        case .magnetismCandidate:
            // decision.selectedNodeID ist stets candidates.first?.nodeID (RuntimeHarmonik-Invariante,
            // Phase 3.9.4b) — best trägt daher konsistent die Profil-/Score-Daten desselben Kandidaten.
            guard let nodeID = decision.selectedNodeID,
                  let best = decision.candidates.first, best.nodeID == nodeID else {
                currentMagnetNodeID = nil
                currentMagnetProfile = nil
                print("[Magnetism] cleared (selectedNodeID nil)")
                return
            }
            // Anker ist die alleinige Datenquelle (Phase 3.9.3a) — kein Fallback auf
            // Render-Position. Fehlt der Anker, gilt der Kandidat als nicht vorhanden.
            guard let anchorPos = chordAnchorPositions[nodeID] else {
                currentMagnetNodeID = nil
                currentMagnetProfile = nil
                print("[Magnetism] cleared (no anchor for \(nodeID))")
                return
            }
            currentMagnetNodeID = nodeID
            currentMagnetProfile = (
                rateMultiplier:            best.magnetRateMultiplier,
                maxAngularSpeedMultiplier: best.magnetAngularSpeedMultiplier,
                score:                     best.score,
                preset:                    best.magnetPreset,
                fieldKind:                 best.magnetFieldKind,
                relationTypes:             best.relationTypes,
                effectiveRange:            best.effectiveRange,
                intensity:                 decision.magnetConfig.intensity,
                isEnabled:                 decision.magnetConfig.isEnabled
            )
            let dist = simd_distance(anchorPos, cameraNode.simdWorldPosition)
            let relStr = best.relationTypes.map { $0.rawValue }.joined(separator: "+")
            print("[Magnetism] active  target: \(nodeID)  distance: \(String(format: "%.0f", dist)) m"
                + "  preset: \(best.magnetPreset?.rawValue ?? "–")"
                + "  field: \(best.magnetFieldKind.rawValue) [\(relStr)]"
                + "  rate×\(String(format: "%.2f", best.magnetRateMultiplier))"
                + "  angular×\(String(format: "%.2f", best.magnetAngularSpeedMultiplier))"
                + "  range=\(String(format: "%.1f", best.effectiveRange))m"
                + "  enabled=\(decision.magnetConfig.isEnabled)"
                + "  intensity=\(String(format: "%.2f", decision.magnetConfig.intensity))")

        case .noCandidate, .noSuggestion:
            currentMagnetNodeID = nil
            currentMagnetProfile = nil
            print("[Magnetism] cleared")
        }
    }

    // MARK: – Init

    init(network: ChordNetwork, harmonyMap: HarmonyMap? = nil, layer: String = "functional") {
        super.init()
        allChords = network.chords
        allEdges  = network.edges
        setupBackground()
        setupLighting()
        setupCamera()
        setupStarfield()
        jsonWebMap   = harmonyMap
        jsonWebLayer = layer
        if let map = harmonyMap {
            buildJsonWebLayout(map: map)
        } else {
            updateChunks(cameraPosition: cameraNode.position)
        }

        // Chunks neu laden wenn Chunk-relevante Settings geändert werden.
        // Flags werden hier NUR gesetzt – der eigentliche Rebuild passiert
        // am Beginn des nächsten Render-Frames in updateProximity(), damit
        // kein Thread-Konflikt mit dem SceneKit-Render-Thread entsteht.
        AppSettings.shared.chunkRebuildPublisher
            .sink { [weak self] in
                self?.enqueueRenderCommand(.lightingUpdate)
                self?.enqueueRenderCommand(.reload)
            }
            .store(in: &settingsCancellables)

        // Netzwerk-Wechsel: neues ChordNetwork laden → Render-Thread führt aus
        AppSettings.shared.$harmony
            .map { $0.networkIndex }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] idx in
                let network = NetworkParser.load(index: idx)
                let def = NetworkParser.definitions[max(0, min(idx, NetworkParser.definitions.count - 1))]
                self?.enqueueRenderCommand(.switchNetwork(network, isCurated: def.isCurated, filename: def.filename))
            }
            .store(in: &settingsCancellables)

        // Verbindungslinien ein-/ausblenden → auf Render-Thread rebuilden
        AppSettings.shared.$render
            .map { $0.showNetworkEdges }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.enqueueRenderCommand(.edgeRebuild) }
            .store(in: &settingsCancellables)
    }

    /// Baut die Szene direkt aus einer WorldSession (Runde 020 / E-01) — die
    /// einzige Datenquelle für Map und aktiven Layer im Map-Preview-
    /// Produktpfad. `allChords`/`allEdges` (Autopilot, Verbindungslinien)
    /// kommen aus `worldSession.snapshot`, NICHT mehr über
    /// `HarmonyMapLoader.toChordNetwork` — dieselbe Kanten-Transformation wie
    /// dort (symmetrische Duplikation ungerichteter Kanten, `EdgeData` kennt
    /// kein `directed`), aber lokal statt über den Legacy-Adapter.
    /// `buildJsonWebLayout` (Anker/Render) liest ohnehin schon direkt aus
    /// `harmonyMap` (Phase 3.9.3a) — unverändert.
    convenience init(worldSession: WorldSession) {
        self.init(
            network:    Self.chordNetwork(from: worldSession.snapshot),
            harmonyMap: worldSession.map,
            layer:      worldSession.activeLayer
        )
    }

    private static func chordNetwork(from snapshot: WorldSession.Snapshot) -> ChordNetwork {
        let chords = snapshot.nodes.map { ChordData(name: $0.id, midiNotes: $0.midiNotes) }
        var edges: [EdgeData] = []
        edges.reserveCapacity(snapshot.edges.count * 2)
        for e in snapshot.edges {
            edges.append(EdgeData(source: e.source, target: e.target, weight: e.weight))
            if !e.directed {
                edges.append(EdgeData(source: e.target, target: e.source, weight: e.weight))
            }
        }
        return ChordNetwork(chords: chords, edges: edges)
    }

    // MARK: – Netzwerk wechseln (auf Render-Thread aufgerufen)

    private func loadNetwork(_ network: ChordNetwork, isCurated: Bool, filename: String) {
        guard !jsonWebMode else { return }   // JSON-Web-Modus: Settings-Netzwerkwechsel ignoriert
        allChords              = network.chords
        allEdges               = network.edges
        curatedMode            = isCurated
        curatedNetworkFilename = filename
        reloadAllChunks()
        if curatedMode {
            if curatedNetworkFilename == "network_harmony_codex" {
                buildHarmonyCodexLayout()
            } else {
                buildCuratedLayout()
            }
        }
    }

    // MARK: – Status Quo Bühnen-Aufstellung 🤘

    private func buildCuratedLayout() {
        // "In Search of the Fourth Chord" – Status Quo, 2007
        // Gleichseitiges Dreieck, Seite = 140 · Zentroid bei z ≈ -100
        // Kamera von weit hinten für dramatischen Überblick
        let layout: [(name: String, pos: SCNVector3)] = [
            ("A",  SCNVector3(  0,  0,    -39)),  // I   – Apex (näher)
            ("D",  SCNVector3(-70,  0,   -160)),  // IV  – Basis links
            ("E",  SCNVector3( 70,  0,   -160)),  // V   – Basis rechts
            // Der vierte Akkord: wirklich suuuuhr weit weg
            ("G",  SCNVector3(  0, 400, -9000)),  // ♭VII – irgendwo da draußen im Universum
        ]

        var curatedNodes: [SCNNode] = []
        for item in layout {
            guard let chord = allChords.first(where: { $0.name == item.name }) else { continue }
            let name = "chord_curated_\(item.name)"
            chordDataMap[name] = chord
            let node = makeChordNode(chord: chord, position: item.pos, uniqueName: name)
            chordNodes[name]   = node
            chordAnchorPositions[name] = simd3(item.pos)
            chordRenderOffsets[name]   = .zero
            applyChordRenderPosition(key: name)
            rootNode.addChildNode(node)
            curatedNodes.append(node)
        }

        // Ein einziger Bass-Portal: A2 (= MIDI 45) in der Mitte des Dreiecks
        var rng = SeededRNG(seed: 0x5354_4154_5553_5155)  // "STATUSQU"
        let portal = makeBassPortalNode(bassNote: 45, rng: &rng)
        let portalName = "portal_curated_sq"
        portal.position     = SCNVector3(0, -15, -100)
        portal.name         = portalName
        portalBassNote[portalName]       = 45
        bassPortalNodes[portalName]      = portal
        bassPortalPositions[portalName]  = simd_float3(0, -15, -100)
        rootNode.addChildNode(portal)
        curatedNodes.append(portal)

        // ── Banner: "Search the fourth chord!" – am Horizont ────────────
        // Riesige Schrift, weit entlang -Z, dreht sich zur Kamera (Billboard)
        let hint      = SCNText(string: "Search the fourth chord!", extrusionDepth: 5.0)
        hint.font     = NSFont.systemFont(ofSize: 300.0, weight: .bold)
        hint.flatness = 0.2; hint.chamferRadius = 1.5
        let hintMat   = SCNMaterial()
        hintMat.lightingModel     = .constant
        hintMat.diffuse.contents  = NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.30, alpha: 1)
        hintMat.emission.contents = NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.10, alpha: 1)
        hint.materials = [hintMat]
        let hintContainer = SCNNode()
        hintContainer.position = SCNVector3(0, 0, -2000)   // am Horizont
        let bb = SCNBillboardConstraint(); bb.freeAxes = []
        hintContainer.constraints = [bb]
        // Text-Node zentrieren (300pt × 17 chars × 0.55 / 2 ≈ 1403)
        let hintNode = SCNNode(geometry: hint)
        let (bMin, bMax) = hint.boundingBox
        let halfW: CGFloat = (bMax.x - bMin.x) > 1.0 ? (bMax.x - bMin.x) / 2.0 : 1403.0
        hintNode.position = SCNVector3(-halfW, 0, 0)
        // Sanftes Pulsieren
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.50; pulse.toValue = 1.0; pulse.duration = 2.2
        pulse.autoreverses = true; pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        hintContainer.addAnimation(pulse, forKey: "pulse")
        hintContainer.addChildNode(hintNode)
        rootNode.addChildNode(hintContainer)
        curatedNodes.append(hintContainer)

        // Alle kuratierten Nodes als einen Pseudo-Chunk registrieren
        // → reloadAllChunks() räumt sie automatisch auf
        loadedChunks[curatedCoord] = curatedNodes

        // Kamera-Reset: SceneKitView übernimmt auf FlightState
        requestCameraReset(simd_float3(0, 20, 140))
    }

    // MARK: – Harmony Codex – Kreis-Aufstellung 🪜

    private func buildHarmonyCodexLayout() {
        // "The Harmony Codex" (Steven Wilson, 2023) – Infinite Staircase
        //
        // 24 Akkorde auf einem flachen Kreis in der XZ-Ebene.
        // Großer Radius → genug Abstand damit jeder Akkord musikalisch wirkt.
        //
        // Geometrie:
        //   Radius = 1000 · y = 0 für alle Akkorde
        //   Umfang ≈ 6283 → Abstand benachbarter Akkorde ≈ 262 Einheiten
        //   Autopilot bei ~70 Einh./s: ~3-4 Sekunden pro Akkord
        //
        //   i=0  (E):  angle=  0° x=+1000 z=    0
        //   i=6  (Cis): angle= 90° x=    0 z=-1000
        //   i=12 (Bb): angle=180° x=-1000 z=    0
        //   i=18 (G):  angle=270° x=    0 z=+1000

        let sequence: [String] = [
            "E","Em","B","Bm","Fis","Fism","Cis","Cism",
            "Ab","Abm","Eb","Ebm","Bb","Bbm","F","Fm",
            "C","Cm","G","Gm","D","Dm","A","Am"
        ]
        let n       = sequence.count   // 24
        let radius: Float = 1000.0

        var curatedNodes: [SCNNode] = []

        for (i, chordName) in sequence.enumerated() {
            guard let chord = allChords.first(where: { $0.name == chordName }) else { continue }

            let angle = Float(i) / Float(n) * 2.0 * .pi
            let x     =  radius * cos(angle)
            let z     = -radius * sin(angle)   // SceneKit: -Z vorwärts
            let pos   = SCNVector3(x, 0, z)

            let key  = "chord_codex_\(chordName)"
            chordDataMap[key] = chord
            let node = makeChordNode(chord: chord, position: pos, uniqueName: key)
            chordNodes[key]   = node
            chordAnchorPositions[key] = simd3(pos)
            chordRenderOffsets[key]   = .zero
            applyChordRenderPosition(key: key)
            rootNode.addChildNode(node)
            curatedNodes.append(node)

            // Bass-Portal an Dur-Akkorden (i gerade: E, B, Fis, …) – etwas tiefer gesetzt
            if i % 2 == 0 {
                let pc       = ((chord.midiNotes[0] % 12) + 12) % 12
                let bassNote = 36 + pc
                var rng      = SeededRNG(seed: UInt64(0xC0DE_C0DE) &+ UInt64(i))
                let portal   = makeBassPortalNode(bassNote: bassNote, rng: &rng)
                let pKey     = "portal_codex_\(chordName)"
                portal.position          = SCNVector3(x, -18, z)
                portal.name              = pKey
                portalBassNote[pKey]         = bassNote
                bassPortalNodes[pKey]        = portal
                bassPortalPositions[pKey]    = simd_float3(x, -18, z)
                rootNode.addChildNode(portal)
                curatedNodes.append(portal)
            }
        }

        // ── Banner: "∞ The Infinite Staircase" – am Horizont ────────────
        // Riesige Schrift, weit hinter dem Kreis (Radius 1000), dreht sich zur Kamera
        let hint      = SCNText(string: "∞  The Infinite Staircase", extrusionDepth: 15.0)
        hint.font     = NSFont.systemFont(ofSize: 1000.0, weight: .bold)
        hint.flatness = 0.3; hint.chamferRadius = 5.0
        let hintMat   = SCNMaterial()
        hintMat.lightingModel     = .constant
        hintMat.diffuse.contents  = NSColor(calibratedRed: 0.85, green: 0.95, blue: 1.0, alpha: 1)
        hintMat.emission.contents = NSColor(calibratedRed: 0.6,  green: 0.85, blue: 1.0, alpha: 1)
        hint.materials = [hintMat]
        let hintContainer    = SCNNode()
        hintContainer.position = SCNVector3(0, 0, -8000)   // am Horizont
        let bb = SCNBillboardConstraint(); bb.freeAxes = []
        hintContainer.constraints = [bb]
        // Text-Node zentrieren (1000pt × 25 chars × 0.55 / 2 ≈ 6875)
        let hintNode       = SCNNode(geometry: hint)
        let (bMin, bMax)   = hint.boundingBox
        let halfW: CGFloat = (bMax.x - bMin.x) > 1.0 ? (bMax.x - bMin.x) / 2.0 : 6875.0
        hintNode.position  = SCNVector3(-halfW, 0, 0)
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.3; pulse.toValue = 0.85; pulse.duration = 3.0
        pulse.autoreverses = true; pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        hintContainer.addAnimation(pulse, forKey: "pulse")
        hintContainer.addChildNode(hintNode)
        rootNode.addChildNode(hintContainer)
        curatedNodes.append(hintContainer)

        // Pseudo-Chunk registrieren → reloadAllChunks() räumt auf
        loadedChunks[curatedCoord] = curatedNodes

        // Kamera-Reset: SceneKitView übernimmt auf FlightState
        requestCameraReset(simd_float3(1150, 0, 120))
    }

    // MARK: – JSON-Web-Layout 🌐

    /// Platziert alle Nodes der HarmonyMap anhand semantischer 3D-Anker (Phase 4.1a).
    ///
    /// Geometrie:
    ///   – node.layout3D gewinnt immer; ohne layout3D deterministischer semantischer
    ///     Fallback aus root/function/type (SemanticHarmonyLayout, HarmonyShared, SceneKit-frei)
    ///   – Fallback-Radius nah am früheren Ring-Radius (baseRadius 150), damit bestehende
    ///     Trigger-Radien weiterhin grob passen
    ///   – Kamera-Start: Bounding-Box über alle Anker (cameraPosition(forAnchors:)),
    ///     kein fester Punkt mehr
    ///
    /// Alle Nodes werden als Pseudo-Chunk unter jsonWebCoord registriert,
    /// damit reloadAllChunks() sie automatisch aufräumt.
    ///
    /// - Parameter resetCamera: Kamera-Reset via pendingCameraReset setzen (default: true).
    ///   Beim Reload (reloadJsonWebLayout) wird resetCamera = false übergeben,
    ///   damit die Spielerposition erhalten bleibt.
    private func buildJsonWebLayout(map: HarmonyMap, resetCamera: Bool = true) {
        // Nur im aktiven Layer erreichbare/markierte Nodes werden gebaut (Phase 3.9.3b) —
        // z. B. bleiben rein modal angebundene Nodes im "functional"-Preview unsichtbar.
        let activeIDs = map.activeNodeIDs(in: jsonWebLayer)
        let nodes     = map.nodes.filter { activeIDs.contains($0.id) }
        let n         = nodes.count
        guard n > 0 else { return }

        var jsonNodes: [SCNNode] = []
        var anchors:   [simd_float3] = []
        var explicitCount = 0
        var fallbackCount = 0

        for harmNode in nodes {
            // Phase 4.1a: node.layout3D gewinnt immer, sonst deterministischer
            // semantischer Fallback aus root/function/type — SceneKit-frei,
            // siehe SemanticHarmonyLayout (HarmonyShared). Kein Ring-Index mehr.
            let anchor = SemanticHarmonyLayout.position(for: harmNode)
            if SemanticHarmonyLayout.usesExplicitLayout(harmNode) {
                explicitCount += 1
            } else {
                fallbackCount += 1
            }
            anchors.append(anchor)

            let key   = "chord_json_\(harmNode.id)"
            let chord = ChordData(name: harmNode.id, midiNotes: harmNode.midiNotes)
            chordDataMap[key] = chord

            // makeChordNode bekommt die Anker-Position nur als Startwert — der
            // einzige Render-Schreibpfad bleibt applyChordRenderPosition (Anchor + Offset).
            let node = makeChordNode(chord: chord, position: SCNVector3(anchor), uniqueName: key)
            chordNodes[key] = node
            chordAnchorPositions[key] = anchor
            chordRenderOffsets[key]   = .zero
            applyChordRenderPosition(key: key)
            rootNode.addChildNode(node)
            jsonNodes.append(node)
        }

        // Pseudo-Chunk registrieren → reloadAllChunks() räumt automatisch auf
        loadedChunks[jsonWebCoord] = jsonNodes

        if resetCamera {
            requestCameraReset(cameraPosition(forAnchors: anchors))
        }

        if AppSettings.shared.render.showNetworkEdges { enqueueRenderCommand(.edgeRebuild) }
        let skipped = map.nodes.count - n
        print("[JsonWebLayout] ✅ \(n) Nodes im Layer '\(jsonWebLayer)' platziert"
            + " (\(explicitCount) mit layout3D, \(fallbackCount) semantischer Fallback"
            + (skipped > 0 ? ", \(skipped) Node(s) außerhalb des Layers übersprungen" : "") + ")")
    }

    /// Einfache Bounding-Box-Kamera für das JSON-Web-Layout (Phase 4.1a).
    /// Keine echte Blickfeld-/Look-at-Berechnung — die Kamera behält nach dem
    /// Reset stets die Identitäts-Orientierung (Blick entlang -Z, siehe
    /// SceneKitView.consumePendingCameraReset). Zentriert daher horizontal +
    /// vertikal über die Anker-Bounding-Box und weicht in Z proportional zur
    /// Spannweite zurück, damit auch größere/kleinere Layouts grob im Blick sind.
    private func cameraPosition(forAnchors anchors: [simd_float3]) -> simd_float3 {
        guard var minV = anchors.first else { return simd_float3(0, 30, 240) }
        var maxV = minV
        for a in anchors {
            minV = simd_min(minV, a)
            maxV = simd_max(maxV, a)
        }
        let center = (minV + maxV) * 0.5
        let span   = max(maxV.x - minV.x, maxV.z - minV.z, 40)   // Mindestspanne bei wenigen Nodes
        let margin = span * 0.75 + 60
        return simd_float3(center.x, center.y + 30, maxV.z + margin)
    }

    /// Räumt bestehende JSON-Web-Nodes auf und baut das Layout neu.
    /// Kamera-Reset wird unterdrückt – Spielerposition bleibt erhalten.
    private func reloadJsonWebLayout() {
        guard let map = jsonWebMap else { return }
        reloadAllChunks()
        buildJsonWebLayout(map: map, resetCamera: false)
    }

    // MARK: – Autopilot-Ziel

    /// Autopilot-Navigation: rein distanzbasiert, unabhängig vom MIDI-System.
    ///
    /// Prinzip: Das Schiff fliegt das aktuelle Ziel-Zentrum konsequent an.
    /// Sobald es nah genug am Zentrum ist (passThru-Radius), wird sofort das
    /// nächste Ziel über Netzwerk-Kanten bestimmt – einmalig, ohne Schwanken.
    /// "Kein aktiver Akkord" spielt für die Navigation keine Rolle mehr.
    func updateAutopilotTarget(cameraPos: SCNVector3) {
        guard AppSettings.shared.flight.autopilotEnabled else {
            autopilotEngine.reset()
            return
        }

        let camF = simd_float3(Float(cameraPos.x), Float(cameraPos.y), Float(cameraPos.z))
        let passThru = Float(AppSettings.shared.render.chordRadius) * 2.0

        // Noch weit vom Ziel → keine Arbeit nötig
        if let target = autopilotEngine.targetPosition,
           simd_distance(camF, target) >= passThru { return }

        autopilotEngine.update(
            cameraPos:      camF,
            passThruRadius: passThru,
            maxReach:       Float(AppSettings.shared.harmony.chordTrigger) * 15.0,
            edges:          allEdges,
            positions:      buildChordPositionMap()
        )
    }

    /// Sichtbare Akkord-Instanz je Name → simd_float3 (für AutopilotEngine)
    /// Position aus chordAnchorPositions (Phase 3.9.3a) — Sichtbarkeit weiterhin über node.opacity.
    private func buildChordPositionMap() -> [String: simd_float3] {
        let entries: [ChordPositionEntry] = chordNodes.compactMap { key, node in
            guard let name   = chordDataMap[key]?.name,
                  let anchor = chordAnchorPositions[key] else { return nil }
            return ChordPositionEntry(key: key, name: name, position: anchor, visible: node.opacity > 0.5)
        }
        return resolveChordPositionMap(entries: entries)
    }

    // MARK: – Netzwerk-Verbindungslinien

    /// Zeichnet Verbindungen zwischen geladenen Akkordknoten als dünne Zylinder.
    /// SCNGeometryPrimitiveType.line ist auf Metal/macOS quasi unsichtbar → Zylinder sind zuverlässig.
    private func rebuildEdgeLines() {
        edgesNode?.removeFromParentNode()
        edgesNode = nil
        guard AppSettings.shared.render.showNetworkEdges else { return }

        var byChordName: [String: [SCNNode]] = [:]
        for (key, node) in chordNodes {
            guard let name = chordDataMap[key]?.name else { continue }
            byChordName[name, default: []].append(node)
        }

        let container  = SCNNode()
        let lineColor  = NSColor(calibratedRed: 0.45, green: 0.85, blue: 1.0, alpha: 1.0)
        var seen       = Set<String>()

        for edge in allEdges {
            let key = [edge.source, edge.target].sorted().joined(separator: "↔")
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            guard let srcList = byChordName[edge.source], !srcList.isEmpty,
                  let dstList = byChordName[edge.target], !dstList.isEmpty
            else { continue }

            // Nächstes Paar wählen
            var bestDist = CGFloat.greatestFiniteMagnitude
            var bestSrc  = srcList[0].position
            var bestDst  = dstList[0].position
            for s in srcList { for d in dstList {
                let dist = dist3(s.position, d.position)
                if dist < bestDist { bestDist = dist; bestSrc = s.position; bestDst = d.position }
            }}
            guard bestDist > 1.0 else { continue }

            container.addChildNode(makeEdgeCylinder(from: bestSrc, to: bestDst,
                                                     color: lineColor, weight: edge.weight))
        }

        rootNode.addChildNode(container)
        edgesNode = container
    }

    /// Erstellt einen dünnen Zylinder zwischen zwei 3D-Punkten.
    private func makeEdgeCylinder(from a: SCNVector3, to b: SCNVector3,
                                   color: NSColor, weight: Float) -> SCNNode {
        let dx = b.x - a.x; let dy = b.y - a.y; let dz = b.z - a.z
        let len = sqrt(dx*dx + dy*dy + dz*dz)
        guard len > 0.1 else { return SCNNode() }

        // Radius proportional zum Kantengewicht
        let radius = CGFloat(0.6 + weight * 0.9)
        let cyl    = SCNCylinder(radius: radius, height: CGFloat(len))
        cyl.radialSegmentCount = 6   // niedrig-poly genügt

        let mat = SCNMaterial()
        mat.lightingModel      = .constant
        mat.diffuse.contents   = color.withAlphaComponent(0.75)
        mat.emission.contents  = color.withAlphaComponent(0.55)
        mat.writesToDepthBuffer = false
        mat.isDoubleSided      = true
        cyl.materials          = [mat]

        let node     = SCNNode(geometry: cyl)
        node.position = SCNVector3((a.x+b.x)/2, (a.y+b.y)/2, (a.z+b.z)/2)

        // Zylinder-Achse ist Y → zur Richtung a→b rotieren
        // cross(Y, dir) = (dz, 0, -dx) · angle = acos(dy/len)
        let nx = dx/len; let ny = dy/len; let nz = dz/len
        if abs(ny - 1.0) < 0.0001 {
            // Bereits Y-aufwärts – keine Rotation nötig
        } else if abs(ny + 1.0) < 0.0001 {
            node.eulerAngles = SCNVector3(Float.pi, 0, 0)
        } else {
            node.rotation = SCNVector4(nz, 0, -nx, acos(ny))
        }
        return node
    }

    // MARK: – Chunks komplett neu laden (nach Settings-Änderung)

    func reloadAllChunks() {
        // Runde 038 / V-00b, Fable-5-Review Finding A2: NoteOff nutzt
        // ausschließlich den Output-Snapshot, kein Fallback mehr auf
        // `data.midiNotes` (unverschobene, nie gesendete Noten). Der
        // Snapshot ist immer gesetzt, solange `activeKey` nicht nil ist
        // (siehe `InteractionRuntime.updateChord` — Snapshot wird bei
        // jeder Aktivierung geschrieben).
        if let key = interactionRuntime.activeKey, let outputNotes = interactionRuntime.outputNotes(forKey: key) {
            let name = chordDataMap[key]?.name ?? ""
            onChordDeactivated?(ChordData(name: name, midiNotes: outputNotes))
        }
        if let key = interactionRuntime.portalActiveKey, let outputNote = interactionRuntime.bassOutputNote(forKey: key) {
            onBassNoteOff?(outputNote)
        }
        if let offNote = interactionRuntime.stopMelody() { onMelodyNoteOff?(offNote) }
        interactionRuntime.resetAll()
        currentMagnetNodeID = nil
        currentMagnetProfile = nil
        autopilotEngine.reset()
        enqueueRenderCommand(.visibilityRebuild)   // Sichtbarkeit nach Reload neu berechnen
        onNearestChord?("", 0); onNearestPortal?("", 0); onNearestCloud?("", 0)
        for coord in Array(loadedChunks.keys) { unloadChunk(coord) }
        lastChunkCenter = ChunkCoord(x: Int.max, y: Int.max, z: Int.max)
        chunkLoadQueue.removeAll()
        edgesNode?.removeFromParentNode(); edgesNode = nil   // sofort entfernen, nach Reload neu bauen
        // updateChunks wird beim nächsten Frame automatisch aufgerufen
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: – Szene-Grundaufbau

    private func setupBackground() {
        background.contents = NSColor(calibratedRed: 0.012, green: 0.012, blue: 0.055, alpha: 1.0)
    }

    private func setupLighting() {
        // ── Ambient (schwach, nur Grundhelligkeit) ────────────────────
        let ambient = SCNLight(); ambient.type = .ambient
        ambient.color = NSColor(white: 0.04, alpha: 1.0)
        let an = SCNNode(); an.light = ambient; rootNode.addChildNode(an)

        // ── Omni: weiches Fill-Licht ohne Schatten ────────────────────
        let omni = SCNLight(); omni.type = .omni
        omni.color = NSColor(white: 0.28, alpha: 1.0)
        omni.attenuationStartDistance = 80
        omni.attenuationEndDistance   = 3000
        let on = SCNNode(); on.light = omni; rootNode.addChildNode(on)

        // ── Directional: Hauptlicht mit weichen Schatten ──────────────
        let dir = SCNLight(); dir.type = .directional
        dir.color                = NSColor(calibratedRed: 0.95, green: 0.90, blue: 1.00, alpha: 1.0)
        dir.intensity            = 900
        dir.castsShadow          = AppSettings.shared.render.highQualityRendering
        dir.shadowMode           = .deferred
        dir.shadowSampleCount    = 4            // 4 = weich, performant
        dir.shadowRadius         = 12
        dir.shadowColor          = NSColor.black.withAlphaComponent(0.50)
        dir.shadowMapSize        = CGSize(width: 2048, height: 2048)
        let dn = SCNNode(); dn.light = dir
        dn.eulerAngles = SCNVector3(-Float.pi * 0.38, Float.pi * 0.18, 0) // schräg von oben-rechts
        rootNode.addChildNode(dn)
        directionalLightNode = dn           // Referenz für späteren Toggle

        // ── Licht-Flash (Akkord-Trigger) ──────────────────────────────
        let flash = SCNLight(); flash.type = .omni; flash.intensity = 0
        flash.color = NSColor(calibratedRed: 0.85, green: 0.75, blue: 1.0, alpha: 1.0)
        flash.attenuationStartDistance = 30; flash.attenuationEndDistance = 500
        chordFlashNode.light = flash; rootNode.addChildNode(chordFlashNode)
    }

    /// Schaltet Schatten am Direktionallicht je nach highQualityRendering-Flag.
    /// Wird beim Start und beim Toggle aufgerufen (ohne Chunk-Rebuild).
    private func applyLightingQuality() {
        let hq = AppSettings.shared.render.highQualityRendering
        directionalLightNode?.light?.castsShadow = hq
    }

    // MARK: – Starfield (statisch, 350 Sterne auf großer Kugel)

    private func setupStarfield() {
        var rng = SeededRNG(seed: 0xC0FFEE_AFFE_1234)
        let starR: Float = 2600
        for _ in 0..<350 {
            // Gleichmäßige Kugelverteilung (Marsaglia-Methode)
            var u: Float = 0; var v: Float = 0; var s: Float = 2
            while s >= 1 { u = rng.f(in: -1...1); v = rng.f(in: -1...1); s = u*u + v*v }
            let sq = sqrt(1 - s)
            let x  = 2 * u * sq * starR
            let y  = 2 * v * sq * starR
            let z  = (1 - 2 * s) * starR

            let size  = CGFloat(rng.f(in: 0.7...3.2))
            let bright = 0.45 + Double(rng.f()) * 0.55
            // Leichte Farbtönung für Abwechslung
            let tint   = rng.i(5)
            let color: NSColor
            switch tint {
            case 0:  color = NSColor(calibratedRed: bright,       green: bright*0.85, blue: bright,       alpha: 1)  // leicht blau
            case 1:  color = NSColor(calibratedRed: bright,       green: bright,      blue: bright*0.82,  alpha: 1)  // leicht warm
            default: color = NSColor(white: bright, alpha: 1)
            }

            let sphere = SCNSphere(radius: size); sphere.segmentCount = 4
            let mat = SCNMaterial()
            mat.diffuse.contents  = color
            mat.emission.contents = color
            mat.lightingModel     = .constant
            sphere.materials      = [mat]

            let node = SCNNode(geometry: sphere)
            node.position = SCNVector3(x, y, z)
            rootNode.addChildNode(node)
        }
    }

    private func setupCamera() {
        let cam = SCNCamera()
        cam.zNear = 1.0; cam.zFar = 4000; cam.fieldOfView = 80
        cameraNode.camera   = cam
        cameraNode.position = SCNVector3(0, 0, 0)
        rootNode.addChildNode(cameraNode)
    }

    // MARK: – Chunk laden / entladen

    func updateChunks(cameraPosition pos: SCNVector3) {
        let camSimd = simd_float3(Float(pos.x), Float(pos.y), Float(pos.z))
        let center  = chunkLogic.currentChunk(for: camSimd)

        if center != lastChunkCenter {
            lastChunkCenter = center

            let needed = chunkLogic.neededChunkCoords(around: center)

            for coord in Array(loadedChunks.keys) where !needed.contains(coord) {
                unloadChunk(coord)
            }

            // Neue Chunks nächster-zuerst in Queue einreihen
            let newCoords = needed.filter { loadedChunks[$0] == nil && !chunkLoadQueue.contains($0) }
            chunkLoadQueue.append(contentsOf: chunkLogic.sortedByDistance(from: center, coords: Array(newCoords)))
        }

        // Node-Budgeting: Lastbegrenzung über tatsächlich erzeugte Top-Level-Nodes
        // statt über eine feste Chunk-Anzahl. Ein Cloud-Chunk (teuer) verbraucht
        // mehr Budget als ein leerer Chunk — ehrlichere Begrenzung.
        //
        // Leere Chunks (kein Akkord, kein Portal, keine Cloud → 0 Nodes) zählen
        // als 1, damit das Budget immer fortschreitet und kein Endlos-Loop entsteht.
        var didLoad        = false
        var nodesThisFrame = 0
        let maxNodesPerFrame = 3

        while nodesThisFrame < maxNodesPerFrame, !chunkLoadQueue.isEmpty {
            let coord = chunkLoadQueue.removeFirst()
            guard loadedChunks[coord] == nil else { continue }
            loadChunk(coord)
            didLoad = true
            nodesThisFrame += max(1, loadedChunks[coord]?.count ?? 1)
        }
        if didLoad && AppSettings.shared.render.showNetworkEdges { enqueueRenderCommand(.edgeRebuild) }
    }

    private func loadChunk(_ coord: ChunkCoord) {
        let s = AppSettings.shared

        // ── Peek-RNG: Vorschau auf den Akkord-Dichte-Check ───────────────────
        // Separater RNG mit gleichem Seed wie computeChunkData — kein echter Daten-RNG.
        // Zweck: Filter + Gewichtungsberechnung nur ausführen, wenn dieser Chunk
        // tatsächlich einen Akkord enthalten wird. Stellt das Vor-Sub-Step-B-Verhalten
        // wieder her: die teure allEdges-Iteration entfällt für akkordlose Chunks.
        //
        // Korrektheit: computeChunkData startet seinen eigenen RNG neu (gleicher Seed),
        // ruft rng.i(100) als erste Operation auf und erhält denselben Wert wie peek —
        // der echte Daten-RNG-Flow ist dadurch bit-for-bit unverändert.
        var peek = SeededRNG(seed: chunkLogic.chunkSeed(for: coord))
        let willHaveChord = peek.i(100) < Int(s.harmony.chordDensity)

        // ── Akkord-Pool: Typ-Filter + Key-Center-Filter ───────────────────────
        // Filter und Gewichtung bleiben in HarmonyScene (AppSettings-Zugriff erlaubt).
        // computeChunkData() erhält nur den vorbereiteten, gewichteten Pool.
        // Berechnung erfolgt nur wenn willHaveChord == true (Regression-Fix).
        let weightedChords: [(name: String, weight: Float)]
        if willHaveChord && !allChords.isEmpty {
            let pool = allChords.filter { chord in
                let sfx = chordSuffix(chord.name)
                switch sfx {
                case "m7b5":  if !s.harmony.enableM7b5 { return false }
                case "m7":    if !s.harmony.enableM7   { return false }
                case "maj7":  if !s.harmony.enableMaj7 { return false }
                case "7":     if !s.harmony.enableDom7 { return false }
                case "dim7":  if !s.harmony.enableDim7 { return false }
                case "maj9":  if !s.harmony.enableMaj9 { return false }
                case "9":     if !s.harmony.enable9    { return false }
                case "sus4":  if !s.harmony.enableSus4 { return false }
                case "6":     if !s.harmony.enable6    { return false }
                case "m9":    if !s.harmony.enableM9   { return false }
                default:      break
                }
                if s.harmony.keyCenter >= 0 { return isChordInKey(chord, key: s.harmony.keyCenter) }
                return true
            }
            let chords = pool.isEmpty ? allChords : pool

            // Energie-Gewichtung: Nachbar-Akkorde des aktiven Akkords bevorzugt.
            // Energy 0.0 → starke Nachbar-Bevorzugung (4× Bonus)
            // Energy 1.0 → gleichmäßig zufällig (kein Bonus)
            //
            // Hinweis: Ein früherer GraphEngine-Bias (×2.0 auf empfohlene Akkorde) wurde
            // hier entfernt. Harmonische Logik soll lokal auf bestehende Nodes wirken,
            // nicht über Neuerzeugung in Chunks. Standardmechanismus folgt in Phase 4.3
            // (Magnetismus via RuntimeHarmonik). Chunk-Generierung bleibt bis dahin
            // ausschließlich durch Energie-Gewichtung + EdgeData gesteuert.
            let boost        = Float((1.0 - s.harmony.energyLevel) * 4.0)
            let activeChordN = interactionRuntime.activeKey.flatMap { chordDataMap[$0]?.name }
            weightedChords = chords.map { c in
                guard boost > 0, let active = activeChordN else { return (name: c.name, weight: 1.0) }
                let edgeW = allEdges
                    .filter { $0.source == active && $0.target == c.name }
                    .map    { $0.weight }.max() ?? 0
                return (name: c.name, weight: 1.0 + boost * edgeW)
            }
        } else {
            // Kein Akkord in diesem Chunk: leere Liste → computeChunkData überspringt
            // die Akkord-Auswahl (Guard: !weightedChords.isEmpty bleibt false).
            weightedChords = []
        }

        // Deterministischen Chunk-Inhalt berechnen (kein SceneKit, kein AppSettings)
        let data = chunkLogic.computeChunkData(
            coord:          coord,
            chordDensity:   Int(s.harmony.chordDensity),
            portalDensity:  Int(s.harmony.portalDensity),
            cloudDensity:   Int(s.harmony.cloudDensity),
            weightedChords: weightedChords
        )

        // SceneKit-Nodes bauen und im Szenenbaum registrieren
        buildNodes(from: data)
    }

    // ── buildNodes(from:) ──────────────────────────────────────────────────
    // Erstellt SCNNodes aus ChunkData und registriert sie in den internen Dictionaries.
    // Keine Entscheidungslogik, kein AppSettings-Zugriff — nur Rendering + Registrierung.
    //
    // Visueller RNG: SeededRNG(seed: data.visualSeed)
    //   Separater RNG-Strom, geseeded nach allen Daten-Entscheidungen in computeChunkData.
    //   Akzeptierter Nebeneffekt: visuelle Variation (Knotenerscheinung) ändert sich
    //   einmalig gegenüber der Vorgänger-Implementierung. Positionen, Akkorde,
    //   Bass-Noten und Roots sind davon NICHT betroffen.
    private func buildNodes(from data: ChunkData) {
        var nodes:      [SCNNode] = []
        var visualRNG = SeededRNG(seed: data.visualSeed)
        let coord = data.coord

        // ── Track 1: Akkord ──────────────────────────────────────────────────
        if let chordEntry = data.chord {
            let name = "chord_\(coord.x)_\(coord.y)_\(coord.z)"
            let pos  = SCNVector3(chordEntry.position)
            // ChordData (HarmonyShared) via Name aus dem geladenen Netzwerk nachschlagen
            if let chordData = allChords.first(where: { $0.name == chordEntry.name }) {
                chordDataMap[name] = chordData
                let node = makeChordNode(chord: chordData, position: pos, uniqueName: name)
                chordNodes[name] = node
                chordAnchorPositions[name] = chordEntry.position   // bereits simd_float3
                chordRenderOffsets[name]   = .zero
                applyChordRenderPosition(key: name)
                rootNode.addChildNode(node)
                nodes.append(node)
            }
        }

        // ── Track 2: Bass-Portal ─────────────────────────────────────────────
        if let bassEntry = data.bass {
            let name = "portal_\(coord.x)_\(coord.y)_\(coord.z)"
            let pos  = SCNVector3(bassEntry.position)
            portalBassNote[name]      = bassEntry.note
            let node = makeBassPortalNode(bassNote: bassEntry.note, rng: &visualRNG)
            node.position = pos; node.name = name
            bassPortalNodes[name]     = node
            bassPortalPositions[name] = bassEntry.position   // simd_float3 direkt
            rootNode.addChildNode(node)
            nodes.append(node)
        }

        // ── Track 3: Melodie-Wolke ───────────────────────────────────────────
        if let cloudEntry = data.cloud {
            let name = "cloud_\(coord.x)_\(coord.y)_\(coord.z)"
            let pos  = SCNVector3(cloudEntry.position)
            interactionRuntime.addCloud(key: name, root: cloudEntry.root)
            let node = makeMelodyCloudNode(rng: &visualRNG)
            node.position = pos; node.name = name
            cloudNodes[name] = node
            rootNode.addChildNode(node)
            nodes.append(node)
        }

        loadedChunks[coord] = nodes
    }

    private func unloadChunk(_ coord: ChunkCoord) {
        guard let nodes = loadedChunks[coord] else { return }
        for node in nodes {
            let n = node.name ?? ""
            node.removeFromParentNode()
            chordNodes.removeValue(forKey: n)
            chordAnchorPositions.removeValue(forKey: n)
            chordRenderOffsets.removeValue(forKey: n)
            chordImpulses.removeValue(forKey: n)
            chordCandidateGlow.removeValue(forKey: n)
            bassPortalNodes.removeValue(forKey: n)
            bassPortalPositions.removeValue(forKey: n)
            cloudNodes.removeValue(forKey: n)
            let unloadedChordData        = chordDataMap.removeValue(forKey: n)
            let unloadedChordOutputNotes = interactionRuntime.removeOutputNotes(forKey: n)
            portalBassNote.removeValue(forKey: n)
            let unloadedBassOutputNote   = interactionRuntime.removeBassOutputNote(forKey: n)
            interactionRuntime.removeCloud(n)
            if interactionRuntime.activeKey  == n {
                // Runde 038 / V-00b, Fable-5-Review Finding A2: kein Fallback
                // mehr auf `data.midiNotes` — nur der Output-Snapshot liefert
                // die tatsächlich gesendeten (oktavverschobenen) Noten.
                if let outputNotes = unloadedChordOutputNotes {
                    let name = unloadedChordData?.name ?? ""
                    onChordDeactivated?(ChordData(name: name, midiNotes: outputNotes))
                }
                interactionRuntime.clearActiveTrigger()
            }
            // Finding 062-01 (Runde 063): das Off gilt jetzt fuer JEDE beim
            // Entladen tatsaechlich noch klingende Bassnote, nicht nur die
            // des aktiven Portals — `removeBassOutputNote` liefert den Wert
            // nur zurueck, wenn er wirklich klang. Getrennt vom
            // `portalActiveKey`-Check, damit kein doppeltes Off entsteht.
            if let outputNote = unloadedBassOutputNote { onBassNoteOff?(outputNote) }
            if interactionRuntime.portalActiveKey == n {
                interactionRuntime.clearActivePortalTrigger()
            }
            if interactionRuntime.cloudActiveKey  == n {
                if let offNote = interactionRuntime.stopMelody() { onMelodyNoteOff?(offNote) }
                interactionRuntime.clearActiveCloudTrigger()
            }
            interactionRuntime.clearApproach(ifEquals: n)
            interactionRuntime.clearPortalApproach(ifEquals: n)
            interactionRuntime.clearCloudApproach(ifEquals: n)
        }
        loadedChunks.removeValue(forKey: coord)
    }

    // MARK: – Key-Center Harmonik-Filter

    /// Gibt zurück ob ein Akkord zur angegebenen Dur-Tonart gehört (diatonisch).
    /// Tonart C=0, Db=1 … B=11.  Diatonisches Schema: I=maj7  II/III/VI=m7  V=7  VII=m7b5
    private func isChordInKey(_ chord: ChordData, key: Int) -> Bool {
        let root   = chordChroma(chord.name)
        let suffix = chordSuffix(chord.name)
        let degree = (root - key + 12) % 12
        switch suffix {
        case "maj7", "maj9", "6":       return degree == 0 || degree == 5  // I, IV
        case "m7",   "m9":              return degree == 2 || degree == 4 || degree == 9  // II, III, VI
        case "7",    "9",   "sus4":     return degree == 7   // V
        case "m7b5", "dim7":            return degree == 11  // VII
        default:                        return true
        }
    }

    // Chromatischer Grundton aus Akkordname (C=0 … B=11)
    private func chordChroma(_ name: String) -> Int {
        let table: [(String, Int)] = [
            ("F#",6),("Db",1),("Ab",8),("Eb",3),("Bb",10),
            ("C",0),("D",2),("E",4),("F",5),("G",7),("A",9),("B",11)
        ]
        for (pfx, idx) in table { if name.hasPrefix(pfx) { return idx } }
        return 0
    }

    // Suffix (Akkordtyp) aus Akkordname: "maj7", "m7", "7", "m7b5"
    private func chordSuffix(_ name: String) -> String {
        let prefixes = ["F#","Db","Ab","Eb","Bb","C","D","E","F","G","A","B"]
        for pfx in prefixes { if name.hasPrefix(pfx) { return String(name.dropFirst(pfx.count)) } }
        return ""
    }

    // MARK: – Render-Commands konsumieren
    //
    // Drei Phasen pro Frame, exakt an den bisherigen Pending-Flag-Konsumpunkten
    // (Runde 025 / E-05): .top vor jeder Chunk-/Proximity-Logik (Netzwerkwechsel/
    // Reload/Lighting/CameraReset), .postChunks direkt nach updateChunks
    // (Edge-Rebuild — braucht die von updateChunks evtl. neu geladenen Nodes,
    // darf also nicht vorher laufen), .end nach den übrigen Proximity-Passes
    // (Visibility — wie zuvor bewusst zuletzt). Commands, die in einer noch
    // nicht zuständigen Phase drainen (in der Praxis nur bei race-artigem
    // Timing zwischen Main-Thread-Enqueue und Render-Thread-Drain möglich),
    // werden zurück in die Queue gestellt statt verworfen oder verfrüht
    // angewendet.

    private enum RenderCommandPhase { case top, postChunks, end }

    private func drainRenderCommands(phase: RenderCommandPhase, cameraPosition pos: SCNVector3) {
        let batch = commandQueue.drain()
        guard !batch.isEmpty else { return }
        var deferred: [RenderCommand] = []
        for command in batch {
            switch (phase, command) {
            case (.top, .switchNetwork(let network, let isCurated, let filename)):
                // jsonWebMode: Settings-Netzwerkwechsel wird ignoriert (wie vormals pendingNetwork = nil)
                if !jsonWebMode { loadNetwork(network, isCurated: isCurated, filename: filename) }
            case (.top, .reload):
                if jsonWebMode {
                    reloadJsonWebLayout()      // JSON-Ring neu aufbauen (ohne Kamera-Reset)
                } else {
                    reloadAllChunks()
                }
            case (.top, .lightingUpdate):
                applyLightingQuality()
            case (.top, .cameraReset(let cameraPos)):
                pendingCameraReset = cameraPos
            case (.postChunks, .edgeRebuild):
                rebuildEdgeLines()
            case (.end, .visibilityRebuild):
                updateChordVisibility(pos)
            default:
                deferred.append(command)
            }
        }
        for command in deferred { commandQueue.enqueue(command) }
    }

    // MARK: – Proximity + Chunk-Update

    func updateProximity(cameraPosition pos: SCNVector3, deltaTime dt: Float = 0) {
        // ── Render-Commands VOR jeder Proximity-Prüfung konsumieren ──────
        // Commands kommen thread-sicher über RenderCommandQueue (Main-Thread-
        // Combine-Sinks oder Render-Thread-interne Kaskaden wie
        // reloadAllChunks() → .visibilityRebuild), hier FIFO und vollständig
        // angewendet (Runde 025 / E-05). Phasenaufteilung entspricht exakt der
        // vormaligen Pending-Flag-Reihenfolge, siehe drainRenderCommands(phase:).
        drainRenderCommands(phase: .top, cameraPosition: pos)
        // kein return oben: updateChunks läuft noch im selben Frame → sofort sichtbar
        if !curatedMode && !jsonWebMode { updateChunks(cameraPosition: pos) }
        drainRenderCommands(phase: .postChunks, cameraPosition: pos)

        // ── Spawn-Sicherheit: Trigger erst nach kleiner echter Bewegung scharf ──
        // Verhindert Sofort-Trigger, wenn der Reset-Punkt zufällig in einem
        // Trigger-Radius landet (siehe requestCameraReset).
        if !triggersArmed {
            let camSimd = simd_float3(Float(pos.x), Float(pos.y), Float(pos.z))
            if let ref = armReferencePos {
                if simd_distance(camSimd, ref) > triggerArmDistance { triggersArmed = true }
            } else {
                armReferencePos = camSimd
            }
        }

        // Harmonischer Magnet-Einfluss bereit für FlightController (Phase 4.2a).
        // SceneKitView liest magnetInfluence nach diesem Aufruf und übergibt es als
        // update(...)-Parameter (Runde 024 / E-04) — Render-Thread-sicher, ein Frame Latenz.

        updateChordProximity(pos)
        updateHarmonicImpulses(deltaTime: dt)
        updateCandidateGlow(deltaTime: dt)
        updatePortalProximity(pos)
        updateCloudProximity(pos)
        updateAutopilotTarget(cameraPos: pos)
        // Duplikat-Unterdrückung: nur bei Chunk-Load/Unload (nie periodisch)
        drainRenderCommands(phase: .end, cameraPosition: pos)

        // ── Radar-Snapshot (kontinuierlich, ~10 Hz) ──────────────────────
        // Throttle: jeder 6. Frame → unabhängig von Akkord-Events.
        // localChordNodes + simdWorldPosition sind auf dem Render-Thread sicher lesbar.
        radarFrameCounter += 1
        if radarFrameCounter % 6 == 0, let snap = onRadarSnapshot {
            let nodes  = localChordNodes
            let camPos = cameraNode.simdWorldPosition
            let magnet = magnetTargetPosition
            snap(nodes, camPos, magnet)
        }
    }

    private func updateChordProximity(_ pos: SCNVector3) {
        let trigR     = Float(chordTrigger)
        let entryR    = trigR * 0.65
        let approachR = trigR * 3.0
        let camSimd   = simd_float3(Float(pos.x), Float(pos.y), Float(pos.z))

        // Kandidaten: ALLE geladenen Chord-Knoten (nicht nur sichtbare!) — die
        // Runtime filtert intern für die Proximity-Auswertung nach `visible`,
        // braucht aber auch unsichtbare Knoten für die Trigger-Deaktivierung
        // (ein Knoten kann im selben Frame unsichtbar werden UND den
        // Trigger-Radius verlassen; chordDataMap kannte solche Knoten schon
        // vorher unabhängig von der Sichtbarkeit). Position aus dem Anker
        // (Phase 3.9.3a).
        // Sortiert nach `key` (Runde 038 / V-00b, Fable-5-Review Finding A8):
        // `chordNodes` ist ein Dictionary, dessen Iterationsreihenfolge pro
        // Prozessstart neu geseedet wird. `ProximityTracker.evaluate` löst
        // Distanzgleichstände über strikten Vergleich (erster Treffer in
        // Array-Reihenfolge gewinnt) auf — ohne stabile Vorsortierung wäre
        // das Ergebnis bei exaktem Gleichstand prozesszufällig statt
        // deterministisch reproduzierbar.
        let candidates: [ChordInteractionCandidate] = chordNodes.compactMap { key, node in
            guard let anchor = chordAnchorPositions[key], let chord = chordDataMap[key] else { return nil }
            return ChordInteractionCandidate(key: key, position: anchor, chord: chord, visible: node.opacity > 0.5)
        }.sorted { $0.key < $1.key }

        let input = ChordInteractionInput(
            candidates:     candidates,
            cameraPosition: camSimd,
            config: ChordInteractionConfig(
                entryRadius:         entryR,
                exitRadius:          trigR,
                approachRadius:      approachR,
                triggersArmed:       triggersArmed,
                voiceLeadingEnabled: AppSettings.shared.harmony.voiceLeadingEnabled,
                chordOctaveShift:    AppSettings.shared.midi.chordOctaveShift
            )
        )

        applyInteractionActions(interactionRuntime.updateChord(input))
    }

    /// Wendet die von `InteractionRuntime.update{Chord,Portal,Cloud}(...)`
    /// gelieferten Actions in exakt der gelieferten Reihenfolge an — die
    /// relative Reihenfolge zwischen RenderEffects und OutputEvents
    /// entspricht dem bisherigen `update*Proximity`-Ablauf (Runde 026 /
    /// E-06a Chord, Runde 027 / E-06b Portal+Cloud).
    private func applyInteractionActions(_ actions: [InteractionAction]) {
        for action in actions {
            switch action {
            case .renderEffect(let effect):
                switch effect {
                case .resetApproachGlow(let key):
                    resetChordApproachGlow(key)
                case .setApproachGlow(let key, let proximity):
                    setChordApproachGlow(name: key, proximity: proximity)
                case .setHighlighted(let key, let active):
                    setChordHighlighted(name: key, active: active)
                case .triggerHarmonicImpulse(let key):
                    triggerHarmonicImpulse(from: key)
                case .updateChordData(let key, let chord):
                    // Voice-geführte (noch nicht oktavverschobene) Noten zurückschreiben:
                    // activeChordNotes/nearestChordNotes lesen chordDataMap direkt und
                    // müssen die aktuell klingende Voicing widerspiegeln.
                    chordDataMap[key] = chord
                case .resetPortalApproachGlow(let key):
                    resetPortalApproachGlow(key)
                case .setPortalApproachGlow(let key, let proximity):
                    setPortalApproachGlow(name: key, proximity: proximity)
                case .setPortalHighlighted(let key, let active):
                    setPortalHighlighted(name: key, active: active)
                case .resetCloudApproachGlow(let key):
                    resetCloudApproachGlow(key)
                case .setCloudApproachGlow(let key, let proximity):
                    setCloudApproachGlow(name: key, proximity: proximity)
                case .setCloudHighlighted(let key, let active):
                    setCloudHighlighted(name: key, active: active)
                }
            case .outputEvent(let event):
                switch event {
                case .nearestChord(let name, let proximity):
                    onNearestChord?(name, proximity)
                case .chordActivated(let chord):
                    onChordActivated?(chord)
                case .chordDeactivated(let chord):
                    onChordDeactivated?(chord)
                case .nearestPortal(let bassNote, let proximity):
                    onNearestPortal?(bassNote.map { noteNameStr($0) } ?? "", proximity)
                case .bassNoteOn(let note):
                    onBassNoteOn?(note)
                case .bassNoteOff(let note):
                    onBassNoteOff?(note)
                case .nearestCloud(let name, let proximity):
                    onNearestCloud?(name, proximity)
                case .melodyNoteWithVelocity(let note, let velocity):
                    onMelodyNoteWithVelocity?(note, velocity)
                case .melodyNoteOff(let note):
                    onMelodyNoteOff?(note)
                }
            }
        }
    }

    // MARK: – Chord-Sichtbarkeit: Waise aktivieren

    /// Wird nur bei Chunk-Load/Unload aufgerufen – niemals periodisch.
    /// Prüft für jeden Akkordnamen ob noch eine sichtbare Instanz existiert.
    /// Fehlt eine (weil der sichtbare Knoten gerade entladen wurde), wird die
    /// nächstgelegene verbleibende Instanz sofort auf opacity 1 gesetzt.
    /// Keine Animationen → kein Pop-in, kein plötzliches Erscheinen.
    private func updateChordVisibility(_ cameraPos: SCNVector3) {
        guard !curatedMode else { return }
        let camAnchor = simd3(cameraPos)

        // Instanzen pro Akkordname — Distanz aus dem Anker (Phase 3.9.3a), nicht node.position.
        var byName: [String: [(node: SCNNode, dist: Float)]] = [:]
        for (key, node) in chordNodes {
            guard let name = chordDataMap[key]?.name, let anchor = chordAnchorPositions[key] else { continue }
            byName[name, default: []].append((node, simd_distance(anchor, camAnchor)))
        }

        for (_, instances) in byName {
            let hasVisible = instances.contains { $0.node.opacity > 0.5 }
            guard !hasVisible else { continue }   // mind. eine sichtbar → nichts tun
            // Waise: nächstgelegene Instanz sofort sichtbar machen
            if let nearest = instances.min(by: { $0.dist < $1.dist }) {
                nearest.node.opacity = 1.0
            }
        }
    }

    /// Adapter (Runde 027 / E-06b): baut Portal-Kandidaten aus
    /// `bassPortalPositions`/`portalBassNote`, ruft die Runtime auf und
    /// wendet das Ergebnis an — trifft selbst keine Proximity-/Trigger-
    /// Entscheidung mehr.
    private func updatePortalProximity(_ pos: SCNVector3) {
        let trigR     = Float(portalTrigger)
        let entryR    = trigR * 0.65
        let approachR = trigR * 3.0
        let camSimd   = simd_float3(Float(pos.x), Float(pos.y), Float(pos.z))

        // Triggergeometrie: Kugel-Hitbox um den Ringmittelpunkt.
        // Quelle: bassPortalPositions (gecacht beim Platzieren) — kein simdWorldPosition-Zugriff.
        // Die visuelle SCNTorus-Form ist nicht die Hitbox — Ringform und Triggerzone sind entkoppelt.
        // Sortiert nach `key` — dieselbe Determinismus-Begründung wie bei
        // den Chord-Kandidaten oben (Runde 038 / V-00b, Fable-5-Review
        // Finding A8).
        let candidates: [PortalInteractionCandidate] = bassPortalPositions.map { key, position in
            PortalInteractionCandidate(key: key, position: position, bassNote: portalBassNote[key])
        }.sorted { $0.key < $1.key }

        let input = PortalInteractionInput(
            candidates:     candidates,
            cameraPosition: camSimd,
            config: PortalInteractionConfig(
                entryRadius:    entryR,
                exitRadius:     trigR,
                approachRadius: approachR,
                triggersArmed:  triggersArmed,
                bassHoldMode:    AppSettings.shared.midi.bassHoldMode,
                bassOctaveShift: AppSettings.shared.midi.bassOctaveShift
            )
        )

        applyInteractionActions(interactionRuntime.updatePortal(input))
    }

    /// Adapter (Runde 027 / E-06b): baut Cloud-Kandidaten frisch aus
    /// `cloudNodes` (kein Positions-Cache wie bei Chord/Portal — identisch
    /// zum bisherigen Verhalten), ruft die Runtime auf und wendet das
    /// Ergebnis an.
    private func updateCloudProximity(_ pos: SCNVector3) {
        let trigR     = Float(cloudTrigger)
        let entryR    = trigR * 0.65
        let approachR = trigR * 3.0
        let camSimd   = simd_float3(Float(pos.x), Float(pos.y), Float(pos.z))

        // Sortiert nach `key` — dieselbe Determinismus-Begründung wie bei
        // den Chord-Kandidaten oben (Runde 038 / V-00b, Fable-5-Review
        // Finding A8).
        let candidates: [CloudInteractionCandidate] = cloudNodes.map { key, node in
            CloudInteractionCandidate(key: key, position: node.simdWorldPosition)
        }.sorted { $0.key < $1.key }

        let s = AppSettings.shared
        let input = CloudInteractionInput(
            candidates:     candidates,
            cameraPosition: camSimd,
            config: CloudInteractionConfig(
                entryRadius:    entryR,
                exitRadius:     trigR,
                approachRadius: approachR,
                triggersArmed:  triggersArmed,
                melodyTempo:    s.midi.melodyTempo,
                melodyVelMax:   Float(s.midi.melodyVelMax),
                energyLevel:    Float(s.harmony.energyLevel),
                now:            Date().timeIntervalSinceReferenceDate
            )
        )

        applyInteractionActions(interactionRuntime.updateCloud(input))
    }

    // MARK: – wrapCamera (No-op – Raum ist unendlich)

    func wrapCamera(_ node: SCNNode) {}

    // ── Kandidatenbetonung (Phase 3.9.4a/3.9.4b, Runde 011) ──────────────
    // Render-only Hervorhebung der HarmonicDecision.candidates im Raum. Nutzt denselben
    // Zerfallspfad wie die Nachbarschafts-Impulse (impulseDecayDuration), aber einen
    // eigenen Zustand (chordCandidateGlow) und -Emission-Helfer — unabhängig davon,
    // ob morphingIntensity 0 ist (Kandidaten-Glow ist keine Positionsverschiebung,
    // siehe applyCandidateGlow: bewusst NICHT an morphingIntensity gekoppelt, damit die
    // harmonische Entscheidung auch mit deaktiviertem Morphing lesbar bleibt).
    private struct CandidateGlow { var amplitude: Float }  // 0...1, zerfällt linear auf 0
    private var chordCandidateGlow: [String: CandidateGlow] = [:]

    /// Setzt/ersetzt die Kandidaten-Glow-Zustände für eine neue HarmonicDecision.
    /// Kandidaten, die in der neuen Entscheidung nicht mehr vorkommen, werden sofort
    /// zurückgesetzt statt weiter auszulaufen ("Reset ... beim nächsten Akkord").
    /// Bester Kandidat (candidates.first) bekommt volle Amplitude 1.0, weitere Kandidaten
    /// eine anteilige Amplitude aus ihrem Score relativ zum besten Kandidaten.
    private func applyCandidateGlow(candidates: [HarmonicCandidate]) {
        let newIDs = Set(candidates.map { $0.nodeID })
        for key in chordCandidateGlow.keys where !newIDs.contains(key) {
            resetChordApproachGlow(key)
        }
        chordCandidateGlow = chordCandidateGlow.filter { newIDs.contains($0.key) }

        let bestScore = candidates.first?.score ?? 0
        for (i, c) in candidates.enumerated() {
            let relative: Float = bestScore > 0 ? c.score / bestScore : 0
            let amplitude: Float = i == 0 ? 1.0 : (0.15 + 0.45 * relative)
            chordCandidateGlow[c.nodeID] = CandidateGlow(amplitude: amplitude)
        }
    }

    /// Zerfall + Anwendung aller aktiven Kandidaten-Glows (Render-Thread, einmal pro Frame).
    /// Erst Updates/Removals sammeln, dann mutieren (siehe updateHarmonicImpulses).
    private func updateCandidateGlow(deltaTime dt: Float) {
        guard !chordCandidateGlow.isEmpty else { return }

        var expired: [String] = []
        var updated: [String: CandidateGlow] = [:]
        for (key, glow) in chordCandidateGlow {
            let newAmplitude = glow.amplitude - dt / impulseDecayDuration
            if newAmplitude <= 0 {
                expired.append(key)
            } else {
                updated[key] = CandidateGlow(amplitude: newAmplitude)
            }
        }

        for key in expired {
            chordCandidateGlow.removeValue(forKey: key)
            resetChordApproachGlow(key)
        }
        for (key, glow) in updated {
            chordCandidateGlow[key] = glow
            guard key != interactionRuntime.activeKey,
                  let node = chordNodes[key],
                  let sn   = node.childNode(withName: "sphere", recursively: false),
                  let mat  = sn.geometry?.firstMaterial,
                  let col  = mat.diffuse.contents as? NSColor else { continue }
            mat.emission.contents = col.withAlphaComponent(CGFloat(0.22 + Double(glow.amplitude) * 0.65))
        }
    }

    // MARK: – Highlights

    private func setChordHighlighted(name: String, active: Bool) {
        guard let node = chordNodes[name] else { return }
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0.3
        let s: CGFloat = active ? 1.35 : 1.0; node.scale = SCNVector3(s, s, s)
        if let sn  = node.childNode(withName: "sphere", recursively: false),
           let mat = sn.geometry?.firstMaterial,
           let col = mat.diffuse.contents as? NSColor {
            mat.emission.contents = col.withAlphaComponent(active ? 0.95 : 0.22)
        }
        SCNTransaction.commit()

        // ── Licht-Flash beim Aktivieren ───────────────────────────────
        if active {
            chordFlashNode.position = node.position
            chordFlashNode.light?.intensity = 0
            let flash = CABasicAnimation(keyPath: "light.intensity")
            flash.fromValue  = 700          // Startwert des Blitzes
            flash.toValue    = 0            // auf 0 ausblenden
            flash.duration   = 0.55
            flash.fillMode   = .forwards
            flash.timingFunction = CAMediaTimingFunction(name: .easeOut)
            flash.isRemovedOnCompletion = true
            chordFlashNode.addAnimation(flash, forKey: "chordFlash")
        }
    }

    private func setPortalHighlighted(name: String, active: Bool) {
        guard let node = bassPortalNodes[name] else { return }
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0.2
        let s: CGFloat = active ? 1.3 : 1.0; node.scale = SCNVector3(s, s, s)
        if let ring = node.childNode(withName: "ring", recursively: false),
           let mat  = ring.geometry?.firstMaterial {
            mat.emission.contents = NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.05,
                                            alpha: active ? 1.0 : 0.65)
        }
        SCNTransaction.commit()
    }

    private func setCloudHighlighted(name: String, active: Bool) {
        guard let node = cloudNodes[name] else { return }
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0.5
        let s: CGFloat = active ? 1.18 : 1.0; node.scale = SCNVector3(s, s, s)
        SCNTransaction.commit()
    }

    // MARK: – Approach Glows (Annäherungs-Leuchten vor dem Trigger)

    private func setChordApproachGlow(name: String, proximity: Float) {
        guard name != interactionRuntime.activeKey,
              let node = chordNodes[name],
              let sn   = node.childNode(withName: "sphere", recursively: false),
              let mat  = sn.geometry?.firstMaterial,
              let col  = mat.diffuse.contents as? NSColor else { return }
        mat.emission.contents = col.withAlphaComponent(CGFloat(0.22 + Double(proximity) * 0.55))
        let s = CGFloat(1.0 + Double(proximity) * 0.22)
        node.scale = SCNVector3(s, s, s)
    }

    private func resetChordApproachGlow(_ name: String) {
        guard name != interactionRuntime.activeKey,
              let node = chordNodes[name],
              let sn   = node.childNode(withName: "sphere", recursively: false),
              let mat  = sn.geometry?.firstMaterial,
              let col  = mat.diffuse.contents as? NSColor else { return }
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0.5
        mat.emission.contents = col.withAlphaComponent(0.22)
        node.scale = SCNVector3(1, 1, 1)
        SCNTransaction.commit()
    }

    private func setPortalApproachGlow(name: String, proximity: Float) {
        guard name != interactionRuntime.portalActiveKey,
              let node = bassPortalNodes[name],
              let ring = node.childNode(withName: "ring", recursively: false),
              let mat  = ring.geometry?.firstMaterial else { return }
        let alpha = CGFloat(0.50 + Double(proximity) * 0.50)
        mat.emission.contents = NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.05, alpha: alpha)
        let s = CGFloat(1.0 + Double(proximity) * 0.20)
        node.scale = SCNVector3(s, s, s)
    }

    private func resetPortalApproachGlow(_ name: String) {
        guard name != interactionRuntime.portalActiveKey,
              let node = bassPortalNodes[name],
              let ring = node.childNode(withName: "ring", recursively: false),
              let mat  = ring.geometry?.firstMaterial else { return }
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0.5
        mat.emission.contents = NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.05, alpha: 0.65)
        node.scale = SCNVector3(1, 1, 1)
        SCNTransaction.commit()
    }

    private func setCloudApproachGlow(name: String, proximity: Float) {
        guard name != interactionRuntime.cloudActiveKey, let node = cloudNodes[name] else { return }
        node.scale = SCNVector3(CGFloat(1.0 + Double(proximity) * 0.18),
                                CGFloat(1.0 + Double(proximity) * 0.18),
                                CGFloat(1.0 + Double(proximity) * 0.18))
    }

    private func resetCloudApproachGlow(_ name: String) {
        guard name != interactionRuntime.cloudActiveKey, let node = cloudNodes[name] else { return }
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0.5
        node.scale = SCNVector3(1, 1, 1)
        SCNTransaction.commit()
    }

    // MARK: – Visual: Akkord-Kugel

    private func makeChordNode(chord: ChordData, position: SCNVector3, uniqueName: String) -> SCNNode {
        let container = SCNNode(); container.position = position; container.name = uniqueName
        let visR = CGFloat(AppSettings.shared.render.chordRadius)
        let hq   = AppSettings.shared.render.highQualityRendering

        // ── Easter Theme: Ostereier (überschreibt alle anderen Modi) ─────────
        if AppSettings.shared.render.easterTheme {
            container.addChildNode(makeEasterEggNode(chord: chord, visR: visR))
            return container
        }

        // ── Visueller Körper (Kugel / Voxel / Minimalistisch / C64 / Pril) ──
        let visualNode: SCNNode
        switch AppSettings.shared.render.chordVisualMode {
        case 1:  visualNode = makeVoxelBodyNode(chord: chord, visR: visR, hq: hq)
        case 2:  visualNode = makeMinimalistNode(chord: chord, visR: visR)
        case 3:  visualNode = makeC64Node(chord: chord, visR: visR)
        case 4:  visualNode = makePrilFlowerNode(chord: chord, visR: visR)
        default: visualNode = makeSphereVisualNode(chord: chord, visR: visR, hq: hq)
        }
        container.addChildNode(visualNode)

        // Akkord-Namen werden vom Lock-On Targeting Overlay (SwiftUI) angezeigt.
        return container
    }

    // ── Kugel-Visual (klassisch) ──────────────────────────────────────────
    private func makeSphereVisualNode(chord: ChordData, visR: CGFloat, hq: Bool) -> SCNNode {
        let sphere = SCNSphere(radius: visR); sphere.segmentCount = 24
        let mat    = SCNMaterial()
        let color  = chordColor(for: chord.name)
        if hq {
            mat.lightingModel      = .physicallyBased
            mat.roughness.contents = NSNumber(value: 0.28)
            mat.metalness.contents = NSNumber(value: 0.62)
        } else {
            mat.lightingModel     = .phong
            mat.specular.contents = NSColor.white
            mat.shininess         = 70
        }
        mat.diffuse.contents  = color
        mat.emission.contents = color.withAlphaComponent(0.22)
        sphere.materials = [mat]
        let sn = SCNNode(geometry: sphere); sn.name = "sphere"
        sn.castsShadow = hq
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.6; pulse.toValue = 1.0
        pulse.duration = 1.8 + Double.random(in: 0...1.2)
        pulse.autoreverses = true; pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        sn.addAnimation(pulse, forKey: "pulse")
        return sn
    }

    // ── Voxel-Mob-Visual 🐷 ──────────────────────────────────────────────
    // Akkordtyp → Mob:  maj7=Creeper(grün)  m7=Enderman(schwarz)
    //                   m7b5=Fledermaus(lila)  sonst=Schwein(pink)
    // Körper-/Kopffarbe = kanonische Mob-Farbe
    // Akkordfarbe = Glow/Emission (leuchtet in der Akkordfarbe)
    private func makeVoxelBodyNode(chord: ChordData, visR: CGFloat, hq: Bool) -> SCNNode {
        let container  = SCNNode(); container.name = "sphere"  // ← Glow-Effekte greifen hier an
        let accentColor = chordColor(for: chord.name)          // Akkordfarbe nur für Glow
        let sfx        = chordSuffix(chord.name)
        let s          = visR

        // ── Kanonische Mob-Farben ─────────────────────────────────────────
        let isCreeper  = sfx.contains("maj7") || sfx.contains("maj9")
        let isBat      = sfx.contains("m7b5") || sfx.contains("ø") || sfx.contains("dim")
        let isEnderman = sfx.contains("m7") || sfx.contains("m9")
        // Pig = alles andere

        let bodyColor: NSColor
        let headColor: NSColor
        switch true {
        case isCreeper:
            bodyColor = NSColor(calibratedRed: 0.18, green: 0.60, blue: 0.18, alpha: 1)  // Creeper-Grün
            headColor = NSColor(calibratedRed: 0.22, green: 0.68, blue: 0.22, alpha: 1)
        case isBat:
            bodyColor = NSColor(calibratedRed: 0.22, green: 0.12, blue: 0.30, alpha: 1)  // Dunkelviolett
            headColor = NSColor(calibratedRed: 0.28, green: 0.15, blue: 0.38, alpha: 1)
        case isEnderman:
            bodyColor = NSColor(calibratedRed: 0.08, green: 0.06, blue: 0.12, alpha: 1)  // Fast-Schwarz
            headColor = NSColor(calibratedRed: 0.10, green: 0.08, blue: 0.16, alpha: 1)
        default:
            bodyColor = NSColor(calibratedRed: 0.95, green: 0.62, blue: 0.72, alpha: 1)  // Schweine-Pink
            headColor = NSColor(calibratedRed: 1.00, green: 0.70, blue: 0.78, alpha: 1)
        }

        // Hilfsfunktion: Material – Körperfarbe als diffuse, Akkordfarbe als Glow
        func mat(_ c: NSColor, emitColor: NSColor? = nil, emitA: CGFloat = 0.0) -> SCNMaterial {
            let m = SCNMaterial()
            if hq { m.lightingModel = .physicallyBased
                    m.roughness.contents = NSNumber(value: 0.92)
                    m.metalness.contents = NSNumber(value: 0.02) }
            else  { m.lightingModel = .phong }
            m.diffuse.contents  = c
            let glow = emitColor ?? accentColor
            m.emission.contents = glow.withAlphaComponent(emitA)
            return m
        }
        func addBox(to parent: SCNNode, w: CGFloat, h: CGFloat, d: CGFloat,
                    chamfer: CGFloat = 0, color c: NSColor,
                    emitColor: NSColor? = nil, emitA: CGFloat = 0.0,
                    pos: SCNVector3 = .init(0,0,0), rot: SCNVector3 = .init(0,0,0)) {
            let b = SCNBox(width: w, height: h, length: d, chamferRadius: chamfer)
            b.materials = [mat(c, emitColor: emitColor, emitA: emitA)]
            let n = SCNNode(geometry: b); n.position = pos; n.eulerAngles = rot
            n.castsShadow = hq; parent.addChildNode(n)
        }

        let bW = s * 1.8, bH = s * 2.2, bD = s * 1.2
        let hS = s * 1.6
        let headY = Float(bH / 2 + hS / 2)
        let fZ    = Float(hS / 2) + 1

        // ── Körper (leuchtet dezent in Akkordfarbe) ───────────────────────
        let bodyGeo = SCNBox(width: bW, height: bH, length: bD, chamferRadius: s * 0.04)
        bodyGeo.materials = [mat(bodyColor, emitA: 0.18)]
        let bodyNode = SCNNode(geometry: bodyGeo); bodyNode.castsShadow = hq
        container.addChildNode(bodyNode)

        // ── Kopf ──────────────────────────────────────────────────────────
        addBox(to: container, w: hS, h: hS, d: hS, chamfer: s * 0.03,
               color: headColor, emitA: 0.20, pos: SCNVector3(0, headY, 0))

        // ── Typ-spezifische Gesichtsmerkmale ──────────────────────────────
        if isCreeper {
            // CREEPER – schwarze quadratische Augen + T-Mund
            for xOff: Float in [-Float(s)*0.28, Float(s)*0.28] {
                addBox(to: container, w: hS*0.22, h: hS*0.22, d: s*0.06,
                       color: .black, pos: SCNVector3(xOff, headY + Float(s*0.12), fZ))
            }
            for xi: Float in [-1, 0] { for yi: Float in [0, 1] {
                addBox(to: container, w: hS*0.15, h: hS*0.15, d: s*0.04, color: .black,
                       pos: SCNVector3(xi*Float(s*0.17)+Float(s*0.05),
                                       headY - Float(s*0.10) + yi*Float(s*0.17), fZ))
            }}

        } else if isBat {
            // FLEDERMAUS – leuchtend rote Augen + Flügel in Akkordfarbe
            let eyeC = NSColor(calibratedRed: 1.0, green: 0.05, blue: 0.05, alpha: 1)
            for xOff: Float in [-Float(s)*0.25, Float(s)*0.25] {
                addBox(to: container, w: hS*0.18, h: hS*0.24, d: s*0.05,
                       color: eyeC, emitColor: eyeC, emitA: 0.90,
                       pos: SCNVector3(xOff, headY + Float(s*0.06), fZ))
            }
            for sign: Float in [-1, 1] {
                addBox(to: container, w: s*1.1, h: s*1.5, d: s*0.10,
                       color: bodyColor.blended(withFraction: 0.3, of: .black) ?? bodyColor,
                       emitA: 0.30,
                       pos: SCNVector3(sign * Float(bW/2 + s*0.55), Float(s*0.3), 0),
                       rot: SCNVector3(0, 0, -sign * 0.45))
            }

        } else if isEnderman {
            // ENDERMAN – schmale lila Augen, lange Arme in Akkordfarbe
            let eyeC = NSColor(calibratedRed: 0.55, green: 0.0, blue: 1.0, alpha: 1)
            for xOff: Float in [-Float(s)*0.30, Float(s)*0.30] {
                addBox(to: container, w: hS*0.20, h: hS*0.10, d: s*0.05,
                       color: eyeC, emitColor: eyeC, emitA: 0.95,
                       pos: SCNVector3(xOff, headY + Float(s*0.10), fZ))
            }
            for sign: Float in [-1, 1] {
                addBox(to: container, w: s*0.35, h: bH*0.9, d: s*0.35,
                       color: bodyColor, emitA: 0.12,
                       pos: SCNVector3(sign * Float(bW/2 + s*0.18), -Float(bH*0.05), 0))
            }

        } else {
            // SCHWEIN – pinke Schnaupe, schwarze Augen
            addBox(to: container, w: hS*0.55, h: hS*0.38, d: s*0.10, chamfer: s*0.05,
                   color: headColor, emitA: 0.15,
                   pos: SCNVector3(0, headY - Float(s*0.10), fZ + 1.0))
            for xOff: Float in [-Float(s)*0.13, Float(s)*0.13] {
                addBox(to: container, w: hS*0.13, h: hS*0.12, d: s*0.06,
                       color: NSColor(calibratedRed: 0.28, green: 0.06, blue: 0.06, alpha: 1),
                       pos: SCNVector3(xOff, headY - Float(s*0.10), fZ + 2.5))
            }
            for xOff: Float in [-Float(s)*0.27, Float(s)*0.27] {
                addBox(to: container, w: hS*0.16, h: hS*0.16, d: s*0.05,
                       color: .black, pos: SCNVector3(xOff, headY + Float(s*0.15), fZ))
            }
        }

        // ── Pulse-Animation ───────────────────────────────────────────────
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.6; pulse.toValue = 1.0
        pulse.duration = 1.8 + Double.random(in: 0...1.2)
        pulse.autoreverses = true; pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        container.addAnimation(pulse, forKey: "pulse")
        return container
    }

    // ── Minimalistisch: Drahtgitter-Kugel ────────────────────────────────
    private func makeMinimalistNode(chord: ChordData, visR: CGFloat) -> SCNNode {
        let sphere = SCNSphere(radius: visR)
        sphere.segmentCount = 10        // wenige Segmente → klar sichtbare Kanten
        let color = chordColor(for: chord.name)
        let mat   = SCNMaterial()
        mat.lightingModel     = .constant
        mat.fillMode          = .lines
        mat.diffuse.contents  = color
        mat.emission.contents = color   // Linien leuchten satt
        mat.isDoubleSided     = true
        sphere.materials      = [mat]
        let sn = SCNNode(geometry: sphere); sn.name = "sphere"
        // Langsame Eigenrotation → Drahtgitter dreht sich leise
        let rot = CABasicAnimation(keyPath: "eulerAngles.y")
        rot.fromValue = 0.0; rot.toValue = Double.pi * 2
        rot.duration  = 7.0 + Double.random(in: 0...3.0)
        rot.repeatCount = .infinity
        sn.addAnimation(rot, forKey: "spin")
        return sn
    }

    // ── C64-Hommage: Pixel-Sprite mit C64-Farbpalette ────────────────────
    private func makeC64Node(chord: ChordData, visR: CGFloat) -> SCNNode {
        let color = c64PaletteColor(for: chord.name)
        // Haupt-Sprite-Block (der "Körper")
        let block = SCNBox(width: visR * 1.6, height: visR * 1.4, length: visR * 0.45,
                           chamferRadius: 0)
        let mat = SCNMaterial()
        mat.lightingModel     = .constant
        mat.diffuse.contents  = color
        mat.emission.contents = color.withAlphaComponent(0.55)
        block.materials = [mat]
        let sn = SCNNode(geometry: block); sn.name = "sphere"

        // Zwei Pixel-Augen (schwarze Quadrate)
        let eyeColor = NSColor(white: 0.0, alpha: 1.0)
        for xOff: CGFloat in [-visR * 0.38, visR * 0.38] {
            let eye = SCNBox(width: visR * 0.28, height: visR * 0.28,
                             length: visR * 0.50, chamferRadius: 0)
            let em  = SCNMaterial(); em.lightingModel = .constant
            em.diffuse.contents = eyeColor; eye.materials = [em]
            let en  = SCNNode(geometry: eye)
            en.position = SCNVector3(xOff, visR * 0.16, 0)
            sn.addChildNode(en)
        }
        // Mund (ein horizontaler Pixel-Balken)
        let mouth = SCNBox(width: visR * 0.72, height: visR * 0.18,
                           length: visR * 0.50, chamferRadius: 0)
        let mm = SCNMaterial(); mm.lightingModel = .constant
        mm.diffuse.contents = eyeColor; mouth.materials = [mm]
        let mn = SCNNode(geometry: mouth)
        mn.position = SCNVector3(0, -visR * 0.28, 0)
        sn.addChildNode(mn)

        // C64-typisches Blinken (Cursor-Rhythmus)
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values   = [1.0, 1.0, 0.05, 1.0, 1.0]
        blink.keyTimes = [0.0, 0.82, 0.88, 0.94, 1.0]
        blink.duration = 3.2 + Double.random(in: 0...2.5)
        blink.repeatCount = .infinity
        sn.addAnimation(blink, forKey: "blink")
        return sn
    }

    // C64-Farbpalette: 16 Farben, auf Akkordtypen gemappt
    private func c64PaletteColor(for name: String) -> NSColor {
        let sfx = chordSuffix(name)
        if sfx.contains("maj9")                               { return NSColor(calibratedRed: 0.67, green: 1.00, blue: 0.40, alpha: 1) } // Hellgrün
        if sfx.contains("maj7")                               { return NSColor(calibratedRed: 0.93, green: 0.93, blue: 0.47, alpha: 1) } // Gelb
        if sfx.contains("m9")                                 { return NSColor(calibratedRed: 0.00, green: 0.53, blue: 1.00, alpha: 1) } // Hellblau
        if sfx.contains("m7b5") || sfx.contains("ø")         { return NSColor(calibratedRed: 0.80, green: 0.27, blue: 0.80, alpha: 1) } // Lila
        if sfx.contains("dim7") || sfx == "dim"               { return NSColor(calibratedRed: 0.20, green: 0.20, blue: 0.20, alpha: 1) } // Dunkelgrau
        if sfx.contains("m7")                                 { return NSColor(calibratedRed: 0.00, green: 0.00, blue: 0.67, alpha: 1) } // Blau
        if sfx == "7" || sfx == "9"                           { return NSColor(calibratedRed: 0.87, green: 0.53, blue: 0.33, alpha: 1) } // Orange
        if sfx.contains("sus")                                { return NSColor(calibratedRed: 0.67, green: 1.00, blue: 0.93, alpha: 1) } // Cyan
        if sfx == "6" || sfx == "add9"                        { return NSColor(calibratedRed: 0.00, green: 0.80, blue: 0.33, alpha: 1) } // Grün
        if sfx == "m"                                         { return NSColor(calibratedRed: 0.53, green: 0.00, blue: 0.00, alpha: 1) } // Rot
        if sfx == "aug" || sfx.contains("s5")                 { return NSColor(calibratedRed: 0.87, green: 0.27, blue: 0.53, alpha: 1) } // Pink
        return NSColor(calibratedRed: 0.93, green: 0.93, blue: 0.93, alpha: 1)    // Weiß
    }

    // ── Pril-Blume: 70er-Retro-Blume mit Mittelpunkt + 6 Blütenblättern ──
    private func makePrilFlowerNode(chord: ChordData, visR: CGFloat) -> SCNNode {
        let color = chordColor(for: chord.name)

        // Mittelpunkt-Scheibe (flacher Zylinder, Achse zeigt nach vorne = Z)
        let disc = SCNCylinder(radius: visR * 0.52, height: visR * 0.20)
        let cm   = SCNMaterial()
        cm.lightingModel     = .constant
        cm.diffuse.contents  = color
        cm.emission.contents = color.withAlphaComponent(0.45)
        cm.isDoubleSided     = true
        disc.materials       = [cm]
        let sn = SCNNode(geometry: disc); sn.name = "sphere"
        // Zylinder-Achse ist Y → 90° um X drehen damit die Scheibe in der XY-Ebene liegt
        sn.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)

        // 6 Blütenblätter im Kreis
        let petalDist: CGFloat = visR * 0.88
        let petalR:    CGFloat = visR * 0.33
        // Alternierend zwei Farbtöne (70er Zweifarbigkeit)
        let petalA = color.blended(withFraction: 0.30, of: NSColor.white) ?? color
        let petalB = color.blended(withFraction: 0.20, of: NSColor.black) ?? color
        for i in 0..<6 {
            let angle  = CGFloat(i) * .pi * 2.0 / 6.0
            let petal  = SCNSphere(radius: petalR)
            petal.segmentCount = 10
            let pm = SCNMaterial()
            pm.lightingModel     = .constant
            pm.diffuse.contents  = i % 2 == 0 ? petalA : petalB
            pm.emission.contents = (i % 2 == 0 ? petalA : petalB).withAlphaComponent(0.35)
            petal.materials = [pm]
            let pn = SCNNode(geometry: petal)
            pn.position = SCNVector3(cos(angle) * petalDist, sin(angle) * petalDist, 0)
            pn.scale    = SCNVector3(1.0, 1.0, 0.45)   // flach drücken = Blütenblatt
            sn.addChildNode(pn)
        }
        // Kleiner weißer Kern in der Mitte (das Pril-Zentrum)
        let core  = SCNCylinder(radius: visR * 0.20, height: visR * 0.22)
        let corem = SCNMaterial(); corem.lightingModel = .constant
        corem.diffuse.contents  = NSColor.white
        corem.emission.contents = NSColor.white.withAlphaComponent(0.70)
        core.materials = [corem]
        sn.addChildNode(SCNNode(geometry: core))

        // Sanfte Eigenrotation (die Blume dreht sich gemächlich)
        let spin = CABasicAnimation(keyPath: "eulerAngles.y")
        spin.fromValue  = 0.0
        spin.toValue    = Double.pi * 2
        spin.duration   = 14.0 + Double.random(in: 0...5.0)
        spin.repeatCount = .infinity
        sn.addAnimation(spin, forKey: "spin")
        return sn
    }

    // MARK: – Visual: Bass-Portal (Diamant, Radius aus AppSettings)
    //
    // Geometrie: zwei SCNPyramid Rücken an Rücken → Oktaeder-/Diamantform.
    // Ersetzt den früheren SCNTorus (Mode 0/1/2) und Kugelkranz (Mode 4).
    // Kostenvorteil: ~6 Dreiecke pro Pyramide (12 gesamt) statt ~1152 (Torus)
    // bzw. ~3200 (16 Kugeln × segmentCount 10).
    // Triggerlogik, Proximitiy-Hitbox, Positionen und Namen: unverändert.

    private func makeBassPortalNode(bassNote: Int, rng: inout SeededRNG) -> SCNNode {
        let container = SCNNode()
        let mode  = AppSettings.shared.render.chordVisualMode
        let rr    = CGFloat(AppSettings.shared.render.portalRadius)
        let hq    = AppSettings.shared.render.highQualityRendering
        let amber = NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.05, alpha: 1.0)

        // ── Easter Theme: Möhre statt Diamant ────────────────────────────────
        if AppSettings.shared.render.easterTheme {
            return makeCarrotNode(rr: rr, rng: &rng)
        }

        // ── Diamant-Dimensionen ────────────────────────────────────────────
        // dw/dl: Basis-Breite/-Tiefe (vergleichbar mit früherem Torus-Durchmesser)
        // dh: Höhe pro Pyramide; gesamt: 2×dh von Spitze zu Spitze
        let dw = rr * 0.35
        let dh = rr * 0.30
        let dl = rr * 0.35

        // ── Material je nach Modus ─────────────────────────────────────────
        let mat = SCNMaterial()
        switch mode {
        case 1: // Voxel – mattig orange
            mat.lightingModel     = .phong
            mat.diffuse.contents  = NSColor(calibratedRed: 0.82, green: 0.40, blue: 0.10, alpha: 1)
            mat.emission.contents = NSColor(calibratedRed: 0.82, green: 0.40, blue: 0.10, alpha: 0.30)
            mat.specular.contents = NSColor.white; mat.shininess = 12
        case 2: // Minimal – Drahtgitter
            mat.lightingModel     = .constant; mat.fillMode = .lines
            mat.diffuse.contents  = amber; mat.emission.contents = amber
            mat.isDoubleSided     = true
        case 3: // C64 – retro orange
            mat.lightingModel     = .constant
            let c = NSColor(calibratedRed: 0.87, green: 0.53, blue: 0.33, alpha: 1)
            mat.diffuse.contents  = c; mat.emission.contents = c.withAlphaComponent(0.6)
        case 4: // Pril – leuchtendes Gelb-Orange
            mat.lightingModel     = .constant
            let c = NSColor(calibratedHue: 0.10, saturation: 0.90, brightness: 1.0, alpha: 1)
            mat.diffuse.contents  = c; mat.emission.contents = c.withAlphaComponent(0.60)
        default: // 0 – Amber, PBR oder Phong
            if hq {
                mat.lightingModel      = .physicallyBased
                mat.roughness.contents = NSNumber(value: 0.15)
                mat.metalness.contents = NSNumber(value: 0.88)
            } else {
                mat.lightingModel      = .phong
                mat.specular.contents  = NSColor.white; mat.shininess = 55
            }
            mat.diffuse.contents  = amber
            mat.emission.contents = amber.withAlphaComponent(0.55)
        }

        // ── Obere Pyramide: Basis bei y=0, Spitze nach oben (+y) ──────────
        let topGeo = SCNPyramid(width: dw, height: dh, length: dl)
        topGeo.materials = [mat]
        let top = SCNNode(geometry: topGeo)
        top.name = "diamond_top"
        top.castsShadow = hq && mode == 0
        container.addChildNode(top)

        // ── Untere Pyramide: um X-Achse gespiegelt, Spitze nach unten (−y) ─
        let botGeo = SCNPyramid(width: dw, height: dh, length: dl)
        botGeo.materials = [mat]
        let bot = SCNNode(geometry: botGeo)
        bot.name = "diamond_bot"
        bot.eulerAngles = SCNVector3(Float.pi, 0, 0)
        bot.castsShadow = hq && mode == 0
        container.addChildNode(bot)

        // Basstonname wird über das SwiftUI-HUD (approachBassLabel) angezeigt.

        // ── Pulse: unveränderter Opacity-Sweep, passt zum Diamanten ──────────
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.50; pulse.toValue = 1.0
        pulse.duration = 2.8 + Double(rng.f(in: 0...1.5))
        pulse.autoreverses = true; pulse.repeatCount = .infinity
        container.addAnimation(pulse, forKey: "pulse")
        return container
    }

    // MARK: – Visual: Easter Theme

    // ── Osterei (Akkord-Knoten) ───────────────────────────────────────────────
    // Nur aktiv wenn AppSettings.shared.render.easterTheme == true.
    // Geometrie: SCNSphere mit Y-Skalierung 1.35 → Ei-Form + dekoratives Äquatorband.
    // Node-Name "sphere": Scale-Effekt bei Akkord-Aktivierung bleibt aktiv (wie Voxel-Modus).
    // Glow-Effekt greift nicht (kein Geometry am "sphere"-Container) — harmonisch unkritisch.
    // Hitbox, Position, Trigger-Logik: unverändert.

    private func makeEasterEggNode(chord: ChordData, visR: CGFloat) -> SCNNode {
        // Wrapper heißt "sphere" — Glow-Lookup childNode(withName:"sphere") findet ihn,
        // geometry=nil → Emission-Update schlägt still fehl, Scale-Update greift.
        let wrapper = SCNNode(); wrapper.name = "sphere"

        // Pastellfarbe: Akkordfarbe + 45 % Weiß → weiche Oster-Tönung
        let baseColor = chordColor(for: chord.name)
        let pastel    = baseColor.blended(withFraction: 0.45, of: .white) ?? baseColor

        // Ei-Körper: Kugel mit Y-Skalierung
        let sphere = SCNSphere(radius: visR); sphere.segmentCount = 20
        let bodyMat = SCNMaterial()
        bodyMat.lightingModel     = .phong
        bodyMat.diffuse.contents  = pastel
        bodyMat.emission.contents = pastel.withAlphaComponent(0.20)
        bodyMat.specular.contents = NSColor.white; bodyMat.shininess = 65
        sphere.materials = [bodyMat]
        let eggNode = SCNNode(geometry: sphere)
        eggNode.scale = SCNVector3(1.0, 1.35, 1.0)
        wrapper.addChildNode(eggNode)

        // Dekoband: dünner Zylinder um den Äquator (unabhängig von Egg-Y-Scale)
        let band = SCNCylinder(radius: visR * 1.06, height: visR * 0.13)
        band.radialSegmentCount = 18
        let bandMat = SCNMaterial()
        bandMat.lightingModel     = .constant
        let stripe = baseColor.blended(withFraction: 0.18, of: .white) ?? baseColor
        bandMat.diffuse.contents  = stripe
        bandMat.emission.contents = stripe.withAlphaComponent(0.45)
        bandMat.isDoubleSided     = true
        band.materials = [bandMat]
        wrapper.addChildNode(SCNNode(geometry: band))

        // Sanfte Dauerrotation (schräge Achse für organische Wirkung)
        eggNode.runAction(.repeatForever(
            .rotateBy(x: 0, y: .pi * 2, z: CGFloat(Float.pi * 0.05),
                      duration: 14.0 + Double.random(in: 0...5))
        ))

        // Pulse
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.65; pulse.toValue = 1.0
        pulse.duration  = 1.9 + Double.random(in: 0...1.2)
        pulse.autoreverses = true; pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        wrapper.addAnimation(pulse, forKey: "pulse")

        return wrapper
    }

    // ── Möhre (Bass-Portal) ──────────────────────────────────────────────────
    // Nur aktiv wenn easterTheme == true.
    // Körper: invertierte SCNPyramid (Spitze nach unten), orange.
    // Blattwerk: 3 kleine grüne SCNPyramid-Knospen am Kopf, leicht gespreizt.
    // Pulse: identisch mit Diamant-Portal. Hitbox, Basslogik: unverändert.

    private func makeCarrotNode(rr: CGFloat, rng: inout SeededRNG) -> SCNNode {
        let container = SCNNode()
        let carrotH   = rr * 0.55
        let carrotW   = rr * 0.22

        // Möhrenkörper: Pyramide, Spitze nach unten
        let bodyGeo = SCNPyramid(width: carrotW, height: carrotH, length: carrotW)
        let bodyMat = SCNMaterial()
        bodyMat.lightingModel     = .phong
        bodyMat.diffuse.contents  = NSColor(calibratedRed: 1.0,  green: 0.50, blue: 0.05, alpha: 1)
        bodyMat.emission.contents = NSColor(calibratedRed: 1.0,  green: 0.40, blue: 0.05, alpha: 0.30)
        bodyMat.specular.contents = NSColor.white; bodyMat.shininess = 45
        bodyGeo.materials = [bodyMat]
        let bodyNode = SCNNode(geometry: bodyGeo)
        // SCNPyramid: Basis bei y=0, Spitze bei y=+carrotH → π-Kipp für Spitze nach unten
        bodyNode.eulerAngles = SCNVector3(Float.pi, 0, 0)
        // Verschiebung: Basis (jetzt unten) bei y=0, Spitze bei y=carrotH → Mitte bei carrotH/2
        bodyNode.position = SCNVector3(0, Float(carrotH) * 0.5, 0)
        container.addChildNode(bodyNode)

        // Grünes Blattwerk: 3 Pyramiden-Knospen am Kopf, gleichmäßig gespreizt
        let leafGreen = NSColor(calibratedRed: 0.18, green: 0.68, blue: 0.12, alpha: 1)
        let leafMat   = SCNMaterial()
        leafMat.lightingModel     = .phong
        leafMat.diffuse.contents  = leafGreen
        leafMat.emission.contents = leafGreen.withAlphaComponent(0.28)
        let leafH  = rr * 0.28
        let leafW  = rr * 0.09
        let angles: [Float] = [0, Float.pi * 2/3, Float.pi * 4/3]
        for angle in angles {
            let leafGeo = SCNPyramid(width: leafW, height: leafH, length: leafW * 0.6)
            leafGeo.materials = [leafMat]
            let leafNode = SCNNode(geometry: leafGeo)
            leafNode.eulerAngles = SCNVector3(-Float.pi * 0.18, angle, 0)
            leafNode.position    = SCNVector3(
                sin(angle) * Float(carrotW) * 0.22,
                Float(carrotH),
                cos(angle) * Float(carrotW) * 0.22
            )
            container.addChildNode(leafNode)
        }

        // Pulse: identisch mit Diamant-Portal
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.50; pulse.toValue = 1.0
        pulse.duration  = 2.8 + Double(rng.f(in: 0...1.5))
        pulse.autoreverses = true; pulse.repeatCount = .infinity
        container.addAnimation(pulse, forKey: "pulse")

        return container
    }

    // ── Osterglocken-Cluster / Narzissen (Melodie-Wolke) ─────────────────────
    // Nur aktiv wenn easterTheme == true.
    // 1 Hauptblume + 3–4 kleinere Satelliten-Narzissen.
    // Jede Narzisse: gelbe Trompete (SCNSphere) + 6 abgeflachte Blütenblätter (SCNSphere).
    // Animation: sanftes Wackeln + langsame Y-Rotation (wie Nebula-Wolke).
    // Hitbox, Position, Melodielogik: unverändert.

    private func makeEasterBellNode(rng: inout SeededRNG, cr: CGFloat) -> SCNNode {
        let container = SCNNode()

        // Farbvariante: zufällig crème-gelb oder reinweiß
        let isYellow    = rng.i(2) == 0
        let petalColor  = isYellow
            ? NSColor(calibratedRed: 1.00, green: 0.97, blue: 0.72, alpha: 1)  // Crème-Gelb
            : NSColor(calibratedRed: 0.97, green: 0.96, blue: 0.90, alpha: 1)  // Reinweiß
        let trumpetColor = NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.08, alpha: 1) // Dottergelb

        // Materialien einmalig erstellen (werden geteilt)
        let tMat = SCNMaterial()
        tMat.lightingModel     = .phong
        tMat.diffuse.contents  = trumpetColor
        tMat.emission.contents = trumpetColor.withAlphaComponent(0.50)
        tMat.specular.contents = NSColor.white; tMat.shininess = 55

        let pMat = SCNMaterial()
        pMat.lightingModel     = .phong
        pMat.diffuse.contents  = petalColor
        pMat.emission.contents = petalColor.withAlphaComponent(0.12)
        pMat.specular.contents = NSColor.white; pMat.shininess = 30

        // Hilfsfunktion: eine einzelne Narzisse als SCNNode
        func makeNarcissus(scale s: CGFloat) -> SCNNode {
            let flower = SCNNode()

            // Trompete: gelbe Kugel im Zentrum
            let tGeo = SCNSphere(radius: cr * 0.16 * s); tGeo.segmentCount = 10
            tGeo.materials = [tMat]
            flower.addChildNode(SCNNode(geometry: tGeo))

            // 6 Blütenblätter, gleichmäßig im Ring, leicht abgeflacht
            let petalR = cr * 0.17 * s
            let dist   = cr * 0.27 * s
            for i in 0..<6 {
                let angle = Double(i) / 6.0 * .pi * 2
                let pGeo  = SCNSphere(radius: petalR); pGeo.segmentCount = 8
                pGeo.materials = [pMat]
                let pNode = SCNNode(geometry: pGeo)
                pNode.scale    = SCNVector3(1.0, 0.42, 1.0)
                pNode.position = SCNVector3(
                    Float(cos(angle) * dist), 0, Float(sin(angle) * dist)
                )
                flower.addChildNode(pNode)
            }
            return flower
        }

        // Hauptblume in der Mitte
        container.addChildNode(makeNarcissus(scale: 1.0))

        // 3–4 kleinere Satellitenblumen im Volumen
        let count = 3 + rng.i(2)
        for _ in 0..<count {
            let fx = CGFloat(rng.f(in: -Float(cr) * 0.44...Float(cr) * 0.44))
            let fy = CGFloat(rng.f(in: -Float(cr) * 0.22...Float(cr) * 0.22))
            let fz = CGFloat(rng.f(in: -Float(cr) * 0.44...Float(cr) * 0.44))
            let s  = CGFloat(rng.f(in: 0.46...0.80))
            let mini = makeNarcissus(scale: s)
            mini.position = SCNVector3(fx, fy, fz)
            container.addChildNode(mini)
        }

        // Sanftes Wackeln (wie Nebula-Wolke)
        let drift = CGFloat(rng.f(in: 4...10))
        let dur   = Double(rng.f(in: 4...9))
        let up   = SCNAction.moveBy(x: 0, y: drift,  z: 0, duration: dur)
        let down = SCNAction.moveBy(x: 0, y: -drift, z: 0, duration: dur)
        up.timingMode = .easeInEaseOut; down.timingMode = .easeInEaseOut
        container.runAction(.repeatForever(.sequence([up, down])))
        container.runAction(.repeatForever(
            .rotateBy(x: 0, y: .pi * 2, z: 0, duration: Double(rng.f(in: 22...38)))
        ))

        return container
    }

    // MARK: – Visual: Melodie-Wolke (modus-abhängig)

    private func makeMelodyCloudNode(rng: inout SeededRNG) -> SCNNode {
        let cr   = CGFloat(AppSettings.shared.render.cloudRadius)
        // ── Easter Theme: Osterglocken statt Wolken ───────────────────────────
        if AppSettings.shared.render.easterTheme { return makeEasterBellNode(rng: &rng, cr: cr) }
        switch AppSettings.shared.render.chordVisualMode {
        case 2:  return makeMelodyCloudMinimal(rng: &rng, cr: cr)
        case 3:  return makeMelodyCloudC64(rng: &rng, cr: cr)
        case 4:  return makeMelodyCloudPril(rng: &rng, cr: cr)
        default: return makeMelodyCloudNebula(rng: &rng, cr: cr)  // 0 + 1
        }
    }

    // Modus 0+1: klassische Nebula-Wolke
    private func makeMelodyCloudNebula(rng: inout SeededRNG, cr: CGFloat) -> SCNNode {
        let container = SCNNode()

        let hue  = Double(rng.f(in: 0.40...0.82))
        let hue2 = (hue + 0.14).truncatingRemainder(dividingBy: 1.0)
        let sat  = 0.60 + Double(rng.f()) * 0.28
        let color  = NSColor(calibratedHue: hue,  saturation: sat,        brightness: 1.0, alpha: 1.0)
        let color2 = NSColor(calibratedHue: hue2, saturation: sat * 0.75, brightness: 1.0, alpha: 1.0)

        addCloudLayer(to: container, color: color,  radius: cr,        diffA: 0.028, emitA: 0.042, seg: 20)
        addCloudLayer(to: container, color: color2, radius: cr * 0.60, diffA: 0.055, emitA: 0.085, seg: 16)
        addCloudLayer(to: container, color: color,  radius: cr * 0.30, diffA: 0.100, emitA: 0.160, seg: 14)
        addCloudLayer(to: container, color: color,  radius: cr * 0.08, diffA: 1.000, emitA: 0.950, seg: 12)

        for _ in 0..<10 {
            var u: Float = 0; var v: Float = 0; var s: Float = 2
            while s >= 1 { u = rng.f(in: -1...1); v = rng.f(in: -1...1); s = u*u + v*v }
            let sq = sqrt(1 - s)
            let d  = CGFloat(rng.f(in: Float(cr) * 0.22...Float(cr) * 0.84))
            let r  = CGFloat(rng.f(in: Float(cr) * 0.04...Float(cr) * 0.15))
            let blob = SCNSphere(radius: r); blob.segmentCount = 8
            let bm = SCNMaterial()
            let bc = rng.i(2) == 0 ? color : color2
            bm.diffuse.contents  = bc.withAlphaComponent(0.06 + CGFloat(rng.f()) * 0.09)
            bm.emission.contents = bc.withAlphaComponent(0.09 + CGFloat(rng.f()) * 0.12)
            bm.isDoubleSided = true; blob.materials = [bm]
            let bn = SCNNode(geometry: blob)
            bn.position = SCNVector3(CGFloat(2*u*sq)*d, CGFloat(2*v*sq)*d, CGFloat(1-2*s)*d)
            container.addChildNode(bn)
        }
        for _ in 0..<7 {
            let angle = Double(rng.f()) * Double.pi * 2
            let dist  = CGFloat(rng.f()) * cr * 0.28
            let r     = CGFloat(rng.f(in: 1.2...3.2))
            let fy    = CGFloat(rng.f(in: -Float(cr) * 0.20...Float(cr) * 0.20))
            let spark = SCNSphere(radius: r); spark.segmentCount = 4
            let sm = SCNMaterial()
            sm.diffuse.contents = color.withAlphaComponent(0.9)
            sm.emission.contents = color; sm.lightingModel = .constant
            spark.materials = [sm]
            let sn = SCNNode(geometry: spark)
            sn.position = SCNVector3(CGFloat(cos(angle))*dist, fy, CGFloat(sin(angle))*dist)
            container.addChildNode(sn)
        }
        let drift = CGFloat(rng.f(in: 5...13)); let duration = Double(rng.f(in: 5...11))
        let up   = SCNAction.moveBy(x: 0, y: drift,  z: 0, duration: duration)
        let down = SCNAction.moveBy(x: 0, y: -drift, z: 0, duration: duration)
        up.timingMode = .easeInEaseOut; down.timingMode = .easeInEaseOut
        container.runAction(.repeatForever(.sequence([up, down])))
        if let outerShell = container.childNodes.first {
            let rotDur = Double(rng.f(in: 22...42))
            outerShell.runAction(.repeatForever(
                .rotateBy(x: CGFloat(rng.f(in: -0.4...0.4)),
                          y: .pi * 2,
                          z: CGFloat(rng.f(in: -0.3...0.3)),
                          duration: rotDur)
            ))
        }
        return container
    }

    // Modus 2: Minimal – rotierende Drahtgitter-Kugel
    private func makeMelodyCloudMinimal(rng: inout SeededRNG, cr: CGFloat) -> SCNNode {
        let container = SCNNode()
        let hue   = Double(rng.f(in: 0.40...0.82))
        let color = NSColor(calibratedHue: hue, saturation: 0.90, brightness: 1.0, alpha: 1)
        // Äußere Drahtgitter-Kugel
        let sphere = SCNSphere(radius: cr); sphere.segmentCount = 12
        let m = SCNMaterial(); m.lightingModel = .constant; m.fillMode = .lines
        m.diffuse.contents = color; m.emission.contents = color; m.isDoubleSided = true
        sphere.materials = [m]
        let sn = SCNNode(geometry: sphere); container.addChildNode(sn)
        // Leuchtender Kern
        let core  = SCNSphere(radius: cr * 0.07); core.segmentCount = 6
        let cm    = SCNMaterial(); cm.lightingModel = .constant
        cm.diffuse.contents = color; cm.emission.contents = color; core.materials = [cm]
        container.addChildNode(SCNNode(geometry: core))
        // Langsame Rotation
        let rot = CABasicAnimation(keyPath: "eulerAngles.y")
        rot.fromValue = 0.0; rot.toValue = Double.pi * 2
        rot.duration = 8.0 + Double(rng.f(in: 0...4)); rot.repeatCount = .infinity
        sn.addAnimation(rot, forKey: "spin")
        // Drift-Bob
        let drift = CGFloat(rng.f(in: 4...10)); let dur = Double(rng.f(in: 4...9))
        let up = SCNAction.moveBy(x: 0, y: drift, z: 0, duration: dur)
        let dn = SCNAction.moveBy(x: 0, y: -drift, z: 0, duration: dur)
        up.timingMode = .easeInEaseOut; dn.timingMode = .easeInEaseOut
        container.runAction(.repeatForever(.sequence([up, dn])))
        return container
    }

    // Modus 3: C64 – Pixel-Grid aus SCNBox-Blöcken
    private func makeMelodyCloudC64(rng: inout SeededRNG, cr: CGFloat) -> SCNNode {
        let container = SCNNode()
        let palette: [NSColor] = [
            NSColor(calibratedRed: 0.93, green: 0.93, blue: 0.47, alpha: 1), // Gelb
            NSColor(calibratedRed: 0.00, green: 0.53, blue: 1.00, alpha: 1), // Hellblau
            NSColor(calibratedRed: 0.00, green: 0.80, blue: 0.33, alpha: 1), // Grün
            NSColor(calibratedRed: 0.67, green: 1.00, blue: 0.93, alpha: 1), // Cyan
            NSColor(calibratedRed: 0.80, green: 0.27, blue: 0.80, alpha: 1), // Lila
        ]
        let gridN  = 7
        let pxSize = cr * 0.28
        let step   = pxSize + cr * 0.04
        let offset = -step * CGFloat(gridN - 1) / 2.0
        for row in 0..<gridN {
            for col in 0..<gridN {
                guard rng.i(10) > 2 else { continue }
                let c   = palette[rng.i(palette.count)]
                let box = SCNBox(width: pxSize, height: pxSize, length: pxSize * 0.4, chamferRadius: 0)
                let mat = SCNMaterial(); mat.lightingModel = .constant
                mat.diffuse.contents = c; mat.emission.contents = c.withAlphaComponent(0.55)
                box.materials = [mat]
                let n = SCNNode(geometry: box)
                n.position = SCNVector3(offset + step * CGFloat(col),
                                        offset + step * CGFloat(row), 0)
                container.addChildNode(n)
            }
        }
        // C64-Cursor-Blinken
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values   = [1.0, 1.0, 0.1, 1.0]
        blink.keyTimes = [0.0, 0.85, 0.90, 1.0]
        blink.duration = 2.8 + Double(rng.f(in: 0...2)); blink.repeatCount = .infinity
        container.addAnimation(blink, forKey: "blink")
        // Drift
        let drift = CGFloat(rng.f(in: 3...8)); let dur = Double(rng.f(in: 4...8))
        let up = SCNAction.moveBy(x: 0, y: drift, z: 0, duration: dur)
        let dn = SCNAction.moveBy(x: 0, y: -drift, z: 0, duration: dur)
        up.timingMode = .easeInEaseOut; dn.timingMode = .easeInEaseOut
        container.runAction(.repeatForever(.sequence([up, dn])))
        return container
    }

    // Modus 4: Pril – konzentrische Kugelringe (Blüten-Cluster)
    private func makeMelodyCloudPril(rng: inout SeededRNG, cr: CGFloat) -> SCNNode {
        let container = SCNNode()
        let hue = Double(rng.f(in: 0.0...1.0))
        let layers: [(numP: Int, dist: CGFloat, r: CGFloat, hOff: Double)] = [
            (8, cr * 0.72, cr * 0.20, 0.00),
            (6, cr * 0.42, cr * 0.28, 0.15),
            (4, cr * 0.16, cr * 0.35, 0.30),
        ]
        for layer in layers {
            let h     = (hue + layer.hOff).truncatingRemainder(dividingBy: 1.0)
            let color = NSColor(calibratedHue: h, saturation: 0.85, brightness: 1.0, alpha: 1)
            for i in 0..<layer.numP {
                let a = Double(i) * .pi * 2 / Double(layer.numP)
                let s = SCNSphere(radius: layer.r); s.segmentCount = 10
                let m = SCNMaterial(); m.lightingModel = .constant
                m.diffuse.contents = color; m.emission.contents = color.withAlphaComponent(0.45)
                s.materials = [m]
                let n = SCNNode(geometry: s)
                n.position = SCNVector3(CGFloat(cos(a)) * layer.dist,
                                        CGFloat(sin(a)) * layer.dist,
                                        CGFloat(rng.f(in: -Float(cr)*0.12...Float(cr)*0.12)))
                container.addChildNode(n)
            }
        }
        container.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0,
                                                      duration: Double(rng.f(in: 12...22)))))
        let drift = CGFloat(rng.f(in: 5...12)); let dur = Double(rng.f(in: 5...10))
        let up = SCNAction.moveBy(x: 0, y: drift, z: 0, duration: dur)
        let dn = SCNAction.moveBy(x: 0, y: -drift, z: 0, duration: dur)
        up.timingMode = .easeInEaseOut; dn.timingMode = .easeInEaseOut
        container.runAction(.repeatForever(.sequence([up, dn])))
        return container
    }

    // MARK: – Hilfsfunktionen

    private func addCloudLayer(to node: SCNNode, color: NSColor,
                               radius: CGFloat, diffA: CGFloat, emitA: CGFloat, seg: Int) {
        let sphere = SCNSphere(radius: radius)
        sphere.segmentCount = seg
        let mat = SCNMaterial()
        mat.diffuse.contents  = color.withAlphaComponent(diffA)
        mat.emission.contents = color.withAlphaComponent(emitA)
        mat.isDoubleSided     = true
        sphere.materials      = [mat]
        node.addChildNode(SCNNode(geometry: sphere))
    }

    private func dist3(_ a: SCNVector3, _ b: SCNVector3) -> CGFloat {
        let dx = a.x - b.x; let dy = a.y - b.y; let dz = a.z - b.z
        return sqrt(dx*dx + dy*dy + dz*dz)
    }

    private func noteNameStr(_ midi: Int) -> String {
        let names = ["C","Db","D","Eb","E","F","F#","G","Ab","A","Bb","B"]
        let octave = midi / 12 - 1
        return "\(names[((midi % 12) + 12) % 12])\(octave)"
    }

    private func chordColor(for name: String) -> NSColor {
        switch AppSettings.shared.render.chordColorMode {
        case 0:  return chordColorFifths(for: name)
        default: return chordColorQuality(for: name)
        }
    }

    // ── Modus 1: Qualitäts-Farben (vivid, nach Akkordtyp) ────────────────
    private func chordColorQuality(for name: String) -> NSColor {
        let sfx = chordSuffix(name)
        // Reihenfolge wichtig: spezifischste Suffixe zuerst
        if sfx == "maj9"                            { return .init(calibratedHue: 0.130, saturation: 0.85, brightness: 1.0, alpha: 1) } // weiches Gold
        if sfx.contains("maj7")                    { return .init(calibratedHue: 0.140, saturation: 1.00, brightness: 1.0, alpha: 1) } // Gold
        if sfx.contains("m7b5") || sfx.contains("ø") { return .init(calibratedHue: 0.780, saturation: 1.00, brightness: 0.90, alpha: 1) } // Violett
        if sfx == "m9"                              { return .init(calibratedHue: 0.640, saturation: 0.90, brightness: 0.90, alpha: 1) } // Tiefblau
        if sfx.contains("m7")                      { return .init(calibratedHue: 0.620, saturation: 0.85, brightness: 1.00, alpha: 1) } // Elektrisch Blau
        if sfx.contains("dim7") || sfx == "°7"     { return .init(calibratedHue: 0.020, saturation: 1.00, brightness: 0.72, alpha: 1) } // Dunkelrot
        if sfx.contains("dim")  || sfx == "°"      { return .init(calibratedHue: 0.000, saturation: 0.85, brightness: 0.62, alpha: 1) } // Scharlach
        if sfx.contains("aug")  || sfx.hasSuffix("+") { return .init(calibratedHue: 0.510, saturation: 1.00, brightness: 1.00, alpha: 1) } // Cyan
        if sfx.contains("sus")                     { return .init(calibratedHue: 0.240, saturation: 0.90, brightness: 1.00, alpha: 1) } // Gelbgrün
        if sfx.contains("6")                       { return .init(calibratedHue: 0.380, saturation: 0.85, brightness: 1.00, alpha: 1) } // Smaragd
        if sfx == "9"  || sfx.contains("13")       { return .init(calibratedHue: 0.060, saturation: 1.00, brightness: 1.00, alpha: 1) } // Rotoran.
        if sfx == "7"  || sfx.hasSuffix("7")       { return .init(calibratedHue: 0.076, saturation: 1.00, brightness: 1.00, alpha: 1) } // Orange
        if sfx.hasSuffix("m")                      { return .init(calibratedHue: 0.675, saturation: 0.80, brightness: 0.85, alpha: 1) } // Indigo
        return .init(calibratedHue: 0.08, saturation: 0.12, brightness: 1.0, alpha: 1)  // Warm-Weiß (Major)
    }

    // ── Modus 0: Quintenzirkel-Farben (Grundton → Hue, Typ → Helligkeit) ─
    private func chordColorFifths(for name: String) -> NSColor {
        let chroma = chordChroma(name)
        let sfx    = chordSuffix(name)
        // C G D A E B F# Db Ab Eb Bb F → Positionen 0…11 im Quintenzirkel
        let order: [Int] = [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5]
        let pos = order.firstIndex(of: ((chroma % 12) + 12) % 12) ?? 0
        let hue = Double(pos) / 12.0
        let (sat, bri): (Double, Double) = {
            if sfx.contains("maj7") || sfx.contains("maj9") { return (0.85, 1.00) }
            if sfx.contains("m7b5") || sfx.contains("ø")    { return (1.00, 0.62) }
            if sfx.contains("m7")   || sfx.contains("m9")   { return (0.88, 0.78) }
            if sfx.contains("dim")                           { return (0.95, 0.50) }
            if sfx.hasSuffix("7") || sfx.contains("9")      { return (1.00, 0.95) }
            return (0.70, 0.92)
        }()
        return NSColor(calibratedHue: hue, saturation: sat, brightness: bri, alpha: 1)
    }
}
