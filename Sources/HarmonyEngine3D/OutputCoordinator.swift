import Foundation
import HarmonyShared

// MARK: – OutputConfig
//
// Audio-Parameter für den OutputCoordinator.
// Wird als Closure-Snapshot beim Event-Zeitpunkt ausgelesen.
// Kein AppSettings-Zugriff im Coordinator selbst.

struct OutputConfig {
    let chordOctaveShift: Int     // Oktav-Verschiebung Akkord-Kanal – auch für CH3 (chordToneProvider) gebraucht
    let chordVelocity:    Int     // MIDI-Velocity Akkord-Kanal (0…127)
    let bassVelocity:     Int     // MIDI-Velocity Bass-Kanal (0…127)
}

// MARK: – OutputCoordinator
//
// Einzige Stelle im System, an der HarmonyScene-Events und GamepadController-Events
// auf einen AudioOutput-Kanal treffen.
//
// Initialisiert werden:
//   - scene:            Quelle aller Harmonie-Events
//   - flightController: Empfänger von HUD-Updates
//   - output:           AudioOutput (MIDIManager oder AudioEngine)
//   - config:           Closure, die beim Event-Zeitpunkt den aktuellen OutputConfig liefert
//
// App-Level-Aktionen (Gamepad-Navigation, UI-Toggle) werden als Closures
// von AppModel nach der Initialisierung gesetzt.
//
// ContentView hat keinen Zugriff auf diesen Koordinator.
// App Layer erstellt und hält ihn für die gesamte Laufzeit.
//
// ── Protokoll-Mapping (Rev. 5) ───────────────────────────────────────────────────
//
// CH0 Akkorde:   noteOn(channel:0, note:n, velocity:)  / noteOff(channel:0, note:n)
//   → onChordActivated / onChordDeactivated tragen chord.midiNotes → gezieltes noteOff möglich.
//
// CH1 Bass:      noteOn(channel:1, note:n, velocity:)  / noteOff(channel:1, note:n)
//   → onBassNoteOff((Int)) trägt Notennummer (portalBassNote[old] in HarmonyScene).
//   → On/Off symmetrisch. Kein Tracking, kein Hard-Kill. Zielzustand erreicht.
//
// CH2 Melodie:   noteOn(channel:2, note:n, velocity:)  / noteOff(channel:2, note:n)
//   → onMelodyNoteOff((Int)) trägt Notennummer aus MelodyEngine.stop().
//   → On/Off symmetrisch. Kein Tracking, kein Hard-Kill. Zielzustand erreicht.
//
// CH3 Chord-Tones: noteOn(channel:3, note:n, velocity:)  / noteOff(channel:3, note:n)
//   → chordToneProvider: Closure, liefert Noten-Array beim NoteOn-Zeitpunkt.
//   → GamepadController fixiert Note in activeChordToneNote (Eingabeschicht-State).
//   → onChordTone(sector, note, vel) / onChordToneOff(sector, note) — vollständige Events.
//   → OutputCoordinator ist reiner Durchreicher. Kein Tracking. Endzustand CH3.

final class OutputCoordinator {

    private let scene:            HarmonyScene
    private let flightController: FlightController
    private let output:           AudioOutput
    private let config:           () -> OutputConfig

    // App-level state mutations – werden von AppModel gesetzt.
    // OutputCoordinator delegiert, trifft selbst keine AppSettings-Entscheidung.
    var onBassToggle:  () -> Void = {}
    var onNetworkPrev: () -> Void = {}
    var onNetworkNext: () -> Void = {}
    var onToggleHelp:  () -> Void = {}

    // v1-Netzwerkmodell: Hook für GraphEngine-Beobachtung.
    // Wird von AppModel gesetzt. OutputCoordinator kennt keine Details der Engine.
    // Closure erhält den Namen des aktivierten Akkords.
    var onGraphHook: ((String) -> Void)? = nil

    init(
        scene:            HarmonyScene,
        flightController: FlightController,
        output:           AudioOutput,
        config:           @escaping () -> OutputConfig
    ) {
        self.scene            = scene
        self.flightController = flightController
        self.output           = output
        self.config           = config
        setupBindings()
    }

    // MARK: – Alle Verdrahtungen

    private func setupBindings() {
        bindSceneEvents()
        bindGamepadEvents()
    }

    // MARK: – Scene-Events → Output + HUD

    private func bindSceneEvents() {

        // ── CH 0: Akkord-Kugeln ────────────────────────────────────────────
        scene.onChordActivated = { [weak self] chord in
            guard let self else { return }
            let tonesArray = chord.midiNotes.map { Self.noteNameShort($0) }
            // Guard: ChordMapping nur setzen wenn Töne vorhanden.
            // Leere midiNotes (z. B. defekte ChordData) → kein Update, altes Mapping bleibt.
            guard !tonesArray.isEmpty else { return }
            let mapping = ChordMapping(name: chord.name, tones: tonesArray)
            DispatchQueue.main.async {
                // soundingChordName: klingender Akkord (wird bei Deaktivierung geleert).
                self.flightController.soundingChordName = chord.name
                // mappingChord: atomares Update – Name und Töne immer gemeinsam.
                self.flightController.mappingChord = mapping
                self.flightController.ch0Active    = true
            }
            // Noten kommen von HarmonyScene bereits oktavverschoben (Phase 3.9.1a) –
            // OutputCoordinator wendet chordOctaveShift hier nicht mehr an.
            let cfg = self.config()
            let vel = UInt8(max(0, min(cfg.chordVelocity, 127)))
            for raw in chord.midiNotes {
                let n = UInt8(max(0, min(raw, 127)))
                self.output.noteOn(channel: 0, note: n, velocity: vel)
            }
            // v1-Netzwerkmodell: GraphEngine-Hook aufrufen (rein beobachtend).
            // Kein Einfluss auf Akkordauswahl, Trigger oder Audio.
            self.onGraphHook?(chord.name)
        }

        scene.onChordDeactivated = { [weak self] chord in
            guard let self else { return }
            DispatchQueue.main.async {
                // Nur soundingChordName leeren – mappingChord* bleiben als CH3-Quelle erhalten.
                if self.flightController.soundingChordName == chord.name {
                    self.flightController.soundingChordName = ""
                }
                self.flightController.ch0Active = false
            }
            // CH0: noteOff pro Note – chord.midiNotes trägt bereits die exakten,
            // beim NoteOn gesendeten (oktavverschobenen) Notennummern (Phase 3.9.1a).
            for raw in chord.midiNotes {
                let n = UInt8(max(0, min(raw, 127)))
                self.output.noteOff(channel: 0, note: n)
            }
        }

        // ── CH 1: Bass-Portale ─────────────────────────────────────────────
        scene.onBassNoteOn = { [weak self] note in
            guard let self else { return }
            DispatchQueue.main.async { self.flightController.ch1Active = true }
            // Note kommt von HarmonyScene bereits oktavverschoben (Phase 3.9.1a).
            let cfg = self.config()
            let n   = UInt8(max(0, min(note, 127)))
            let vel = UInt8(max(0, min(cfg.bassVelocity, 127)))
            self.output.noteOn(channel: 1, note: n, velocity: vel)
        }

        scene.onBassNoteOff = { [weak self] note in
            guard let self else { return }
            DispatchQueue.main.async { self.flightController.ch1Active = false }

            // CH1 – Symmetrisches noteOff (Zielzustand).
            //
            // Die Notennummer kommt bereits fertig oktavverschoben aus dem
            // bassOutputNotes-Snapshot der Eventquelle (HarmonyScene, Phase 3.9.1a) –
            // kein erneutes Anwenden von bassOctaveShift hier, da sich der Wert
            // seit dem NoteOn geändert haben könnte. Kein Tracking im Coordinator.
            let n = UInt8(max(0, min(note, 127)))
            self.output.noteOff(channel: 1, note: n)
        }

        // ── CH 2: Melodie-Wolken ───────────────────────────────────────────
        scene.onMelodyNoteWithVelocity = { [weak self] note, velocity in
            guard let self else { return }
            DispatchQueue.main.async {
                self.flightController.ch2Active = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.flightController.ch2Active = false
                }
            }
            let n = UInt8(max(0, min(note, 127)))
            self.output.noteOn(channel: 2, note: n, velocity: velocity)
        }

        scene.onMelodyNoteOff = { [weak self] note in
            guard let self else { return }
            // CH2 – Symmetrisches noteOff (Zielzustand).
            //
            // Die Notennummer kommt direkt aus MelodyEngine.stop() via HarmonyScene.
            // Kein Tracking im Coordinator. Gleiche Semantik wie CH1.
            // Ersetzt die frühere allNotesOff(channel: 2)-Zwischenlösung vollständig.
            let n = UInt8(max(0, min(note, 127)))
            self.output.noteOff(channel: 2, note: n)
        }

        // ── Melodie-Preset-Name → HUD ──────────────────────────────────────
        scene.onMelodyPresetChanged = { [weak self] name in
            guard let self else { return }
            DispatchQueue.main.async { self.flightController.melodyPresetName = name }
        }

        // ── Annäherungs-Radar → HUD ───────────────────────────────────────
        scene.onNearestChord = { [weak self] label, prox in
            guard let self else { return }
            DispatchQueue.main.async {
                self.flightController.approachChordLabel = label
                self.flightController.approachChordProx  = prox
            }
        }

        scene.onNearestPortal = { [weak self] label, prox in
            guard let self else { return }
            DispatchQueue.main.async {
                self.flightController.approachBassLabel = label
                self.flightController.approachBassProx  = prox
            }
        }

        scene.onNearestCloud = { [weak self] _, prox in
            guard let self else { return }
            DispatchQueue.main.async {
                self.flightController.approachMelodyProx = prox
            }
        }
    }

    // MARK: – Gamepad-Events → Output + Navigation + HUD

    private func bindGamepadEvents() {
        let gp = GamepadController.shared

        // ── Melodie-Preset (L1 / R1) ──────────────────────────────────────
        gp.onMelodyNext = { [weak scene] in scene?.nextMelodyPreset() }
        gp.onMelodyPrev = { [weak scene] in scene?.prevMelodyPreset() }

        // ── D-Pad oben: Bass-Mode Toggle (delegiert an AppModel) ──────────
        gp.onBassToggle = { [weak self] in self?.onBassToggle() }

        // ── D-Pad links/rechts: Netzwerk wechseln (delegiert an AppModel) ─
        gp.onNetworkPrev = { [weak self] in self?.onNetworkPrev() }
        gp.onNetworkNext = { [weak self] in self?.onNetworkNext() }

        // ── △ Dreieck: All Notes Off ───────────────────────────────────────
        gp.onAllNotesOff = { [weak self] in
            self?.output.allNotesOff()
        }

        // ── OPTIONS (☰): Steuerungsübersicht (delegiert an AppModel) ──────
        gp.onToggleHelp = { [weak self] in self?.onToggleHelp() }

        // ── Linker Stick: Live-Position → HUD ─────────────────────────────
        gp.onLeftStickChanged = { [weak self] sector, _ in
            guard let self else { return }
            DispatchQueue.main.async { self.flightController.leftStickSector = sector }
        }

        // ── L3: Oktave hoch (momentary) → HUD ────────────────────────────
        gp.onL3Change = { [weak self] pressed in
            guard let self else { return }
            DispatchQueue.main.async { self.flightController.stickOctaveUp = pressed }
        }

        // ── CH3: Provider setzen (Mapping-Quelle für GamepadController) ──────
        //
        // Wird genau beim NoteOn von GamepadController abgerufen.
        // Berechnet Noten aus nearestChordNotes zum Zeitpunkt des Sektor-Eintritts.
        // Die Note lebt danach in GamepadController.activeChordToneNote —
        // der OutputCoordinator selbst trackt nichts.
        gp.chordToneProvider = { [weak self] in
            guard let self else { return [] }
            let cfg      = self.config()
            let octBoost = GamepadController.shared.stickOctaveUp ? 12 : 0
            return self.scene.nearestChordNotes.map {
                UInt8(max(0, min($0 + cfg.chordOctaveShift * 12 + octBoost, 127)))
            }
        }

        // ── Linker Stick: Akkordton spielen (CH 3) ────────────────────────
        //
        // GamepadController fixiert die Note beim NoteOn (via chordToneProvider).
        // OutputCoordinator ist reiner Durchreicher — kein Tracking, keine Berechnung.
        gp.onChordTone = { [weak self] _, note, velocity in
            guard let self else { return }
            self.output.noteOn(channel: 3, note: note, velocity: velocity)
            DispatchQueue.main.async {
                self.flightController.ch3Active = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self.flightController.ch3Active = false
                }
            }
        }

        gp.onChordToneOff = { [weak self] _, note in
            guard let self else { return }
            // CH3 – Reiner Durchreicher.
            // Die Note kommt fix von GamepadController (activeChordToneNote beim NoteOn gespeichert).
            // Kein Tracking im Coordinator. Endzustand für CH3.
            self.output.noteOff(channel: 3, note: note)
        }

        // ── Touchpad → HUD ────────────────────────────────────────────────
        gp.onTouchpadChanged = { [weak self] x, y in
            guard let self else { return }
            DispatchQueue.main.async {
                self.flightController.touchpadX = x
                self.flightController.touchpadY = y
            }
        }
    }

    // MARK: – Hilfsmethoden

    /// All-Notes-Off: direkt aufrufbar (z. B. vom UI-Button)
    func stopAll() {
        output.allNotesOff()
    }

    // Notennamen für HUD (war static func auf ContentView)
    private static func noteNameShort(_ midi: Int) -> String {
        let names = ["C","Db","D","Eb","E","F","F#","G","Ab","A","Bb","B"]
        return names[((midi % 12) + 12) % 12]
    }
}
