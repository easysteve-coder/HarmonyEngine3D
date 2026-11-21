import GameController
import Foundation

// MARK: – PS5 DualSense / Xbox / MFi Gamepad-Anbindung
//
//  Achsen-Layout (DualSense):
//   Linker Stick        →  Akkordton spielen (4 Richtungen = Root/Terz/Quinte/Septime)
//                          Magnitude → Velocity  |  L3 = +8va Toggle (bistabil)
//   Rechter Stick  X/Y →  Yaw / Pitch (Blickrichtung)
//   L2 / R2            →  Schub rückwärts / vorwärts
//   L1 / R1            →  Melodie-Preset zurück / vor
//   D-Pad oben         →  Bass-Mode Toggle (Trigger ↔ Hold)
//
//  Chord-Tone-Sektor:
//   Oben   → note[0]  (Root)
//   Rechts → note[1]  (Terz)
//   Unten  → note[2]  (Quinte)
//   Links  → note[3]  (Septime)
//   Magnitude (0.4–1.0) → Velocity 50–127

final class GamepadController {

    static let shared = GamepadController()

    // ── Flug-Achsen (Rechter Stick + Trigger) ─────────────────────────────
    private(set) var lookX:     Float = 0   // Yaw    [-1 … +1]
    private(set) var lookY:     Float = 0   // Pitch  [-1 … +1]
    private(set) var thrustFwd: Float = 0   // R2     [0 … 1]
    private(set) var thrustBwd: Float = 0   // L2     [0 … 1]
    private(set) var braking:      Bool  = false
    // L3 gedrückt → Chord-Tones +1 Oktave (momentary, solange gedrückt)
    private(set) var stickOctaveUp: Bool = false

    // ── Chord-Tone-Callbacks (linker Stick) ──────────────────────────────
    //  sectorIndex: 0=Root 1=Terz 2=Quinte 3=Septime
    //  velocity:    50–127 (aus Stick-Magnitude)
    //
    //  chordToneProvider: Closure, gesetzt vom OutputCoordinator.
    //    Liefert die aktuellen MIDI-Noten (bereits mit Oktavverschiebung) als UInt8-Array.
    //    Wird genau beim NoteOn (Sektor-Eintritt) abgerufen — nicht beim NoteOff.
    //    Setzt die Note für die Dauer des Tastendrucks fest.
    //
    //  onChordTone:    Stick betritt Sektor → NoteOn     (sectorIndex, note, velocity)
    //  onChordToneOff: Stick verlässt Sektor → NoteOff   (sectorIndex, note — fixiert beim NoteOn)
    //
    //  Die Note wird in activeChordToneNote gespeichert und beim NoteOff
    //  unverändert weitergegeben — unabhängig davon, ob sich der aktive Akkord
    //  zwischen On und Off geändert hat. Kein Tracking im Empfänger nötig.
    var chordToneProvider:    (() -> [UInt8])?
    var onChordTone:          ((Int, UInt8, UInt8) -> Void)?   // (sector, note, velocity)
    var onChordToneOff:       ((Int, UInt8) -> Void)?           // (sector, note)

    // ── Live-Stick-Position (linker Stick, für HUD-Visualisierung) ────────
    //  sector: 0=oben 1=rechts 2=unten 3=links  |  nil = Stick in Mitte
    //  magnitude: 0.0–1.0
    var onLeftStickChanged: ((Int?, Float) -> Void)?

    // ── Sonstige Button-Callbacks ─────────────────────────────────────────
    var onMelodyPrev:    (() -> Void)?        // L1
    var onMelodyNext:    (() -> Void)?        // R1
    var onBassToggle:    (() -> Void)?        // D-Pad oben
    var onNetworkPrev:   (() -> Void)?        // D-Pad links  ← Netzwerk zurück
    var onNetworkNext:   (() -> Void)?        // D-Pad rechts ← Netzwerk vor
    var onAllNotesOff:   (() -> Void)?        // △ Dreieck-Taste
    var onToggleHelp:    (() -> Void)?        // OPTIONS (☰) – Steuerungsübersicht
    var onL3Change:      ((Bool) -> Void)?    // L3: Oktave hoch (bistabil – Toggle)
    var onMotionChanged:   ((Float, Float) -> Void)?  // (roll, pitch) -1…+1 für Gyro-HUD
    var onTouchpadChanged: ((Float, Float) -> Void)?  // (x, y) -1…+1 für Touchpad-HUD

    let deadzone: Float = 0.12

    /// true wenn c.motion existiert (Controller hat Sensor-Hardware)
    var motionAvailable: Bool { controller?.motion != nil }

    /// Tilt-Vektor für HUD-Libelle.
    /// DualSense über Bluetooth liefert hasGravityAndUserAcceleration = false →
    /// nur motion.acceleration (Gesamtbeschleunigung) ist verfügbar.
    /// Im Ruhezustand ≈ Schwerkraftvektor, perfekt für Libellen-Anzeige.
    var motionGravity: (x: Float, y: Float)? {
        guard let m = controller?.motion else { return nil }
        if m.hasGravityAndUserAcceleration {
            // Sensor-Fusion verfügbar (USB / neueres Framework)
            return (x: Float(m.gravity.x), y: Float(m.gravity.y))
        } else {
            // DualSense Bluetooth: Gesamtbeschleunigung nutzen
            let ax = Float(m.acceleration.x)
            let ay = Float(m.acceleration.y)
            return (ax != 0 || ay != 0) ? (x: ax, y: ay) : nil
        }
    }

    /// Betrag der Rotationsrate – 0.0=still, 1.0=schnell (~3 rad/s).
    var motionRotationMagnitude: Float? {
        guard let m = controller?.motion else { return nil }
        let r = m.rotationRate
        return min(1.0, Float(sqrt(r.x*r.x + r.y*r.y + r.z*r.z)) / 3.0)
    }

    // ── Interner State ────────────────────────────────────────────────────
    private var controller:           GCController?
    private var lastChordSector:      Int?   = nil    // Debounce für Chord-Tone
    private var activeChordToneNote:  UInt8? = nil    // CH3-Note, festgelegt beim NoteOn
    private var lastMotionSend:       Date   = .distantPast  // Throttle 20 Hz
    private var touchpadSwipeFired:   Bool   = false  // Debounce für Touchpad-Swipe

    private init() {
        connect()
        NotificationCenter.default.addObserver(
            self, selector: #selector(controllerConnected(_:)),
            name: .GCControllerDidConnect,  object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(controllerDisconnected(_:)),
            name: .GCControllerDidDisconnect, object: nil)
    }

    // MARK: – Verbinden

    private func connect() {
        controller = GCController.controllers().first
        if let c = controller {
            setupHandlers(c)
            print("🎮 Gamepad verbunden: \(c.productCategory) – \(c.vendorName ?? "?")")
        } else {
            print("🎮 Kein Gamepad gefunden – warte auf Verbindung …")
        }
    }

    @objc private func controllerConnected(_ note: Notification) {
        guard let c = note.object as? GCController else { return }
        controller = c; setupHandlers(c)
        print("🎮 Gamepad verbunden: \(c.productCategory) – \(c.vendorName ?? "?")")
    }

    @objc private func controllerDisconnected(_ note: Notification) {
        print("🎮 Gamepad getrennt"); controller = nil; resetAll()
    }

    // MARK: – Handler registrieren

    private func setupHandlers(_ c: GCController) {
        guard let pad = c.extendedGamepad else {
            print("⚠️  Gamepad unterstützt kein extendedGamepad-Profil"); return
        }

        // ── Linker Stick → Chord-Tones ────────────────────────────────────
        pad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            guard let self else { return }
            let mag = sqrt(x*x + y*y)

            if mag < 0.40 {
                // Stick in Mitte → Off für den aktiven Sektor senden, dann Zustand löschen.
                if let old = self.lastChordSector, let note = self.activeChordToneNote {
                    self.onChordToneOff?(old, note)
                    self.activeChordToneNote = nil
                }
                self.lastChordSector = nil
                self.onLeftStickChanged?(nil, 0)
                return
            }

            let sector = self.dominantSector(x: x, y: y)

            // Live-HUD: immer feuern (auch wenn Sektor gleich bleibt)
            self.onLeftStickChanged?(sector, mag)

            guard sector != self.lastChordSector else { return }   // kein Doppel-Trigger

            // Sektorwechsel: Off für den alten Sektor vor On für den neuen.
            if let old = self.lastChordSector, let note = self.activeChordToneNote {
                self.onChordToneOff?(old, note)
                self.activeChordToneNote = nil
            }
            self.lastChordSector = sector

            // Note beim NoteOn fixieren: Provider jetzt abrufen (nicht beim Off).
            // Velocity: Magnitude 0.4–1.0 → 50–127
            let vel = UInt8(50 + Int(((mag - 0.4) / 0.6).clamped(to: 0...1) * 77))
            if let notes = self.chordToneProvider?(), !notes.isEmpty {
                let note = notes[min(sector, notes.count - 1)]
                self.activeChordToneNote = note
                self.onChordTone?(sector, note, vel)
            }
        }

        // ── Rechter Stick → Blickrichtung ─────────────────────────────────
        pad.rightThumbstick.valueChangedHandler = { [weak self] _, x, y in
            guard let self else { return }
            self.lookX = self.apply(deadzone: x)
            self.lookY = self.apply(deadzone: y)
        }

        // ── Trigger: Schub ────────────────────────────────────────────────
        pad.rightTrigger.valueChangedHandler = { [weak self] _, v, _ in self?.thrustFwd = v }
        pad.leftTrigger.valueChangedHandler  = { [weak self] _, v, _ in self?.thrustBwd = v }

        // ── L3: Chord-Tone Oktave +1 (bistabil – Toggle) ─────────────────
        pad.leftThumbstickButton?.valueChangedHandler = { [weak self] _, _, pressed in
            guard let self else { return }
            if pressed {
                self.stickOctaveUp.toggle()
                self.onL3Change?(self.stickOctaveUp)
            }
        }

        // ── R3: Vollbremse ────────────────────────────────────────────────
        pad.rightThumbstickButton?.valueChangedHandler = { [weak self] _, _, pressed in
            self?.braking = pressed
        }

        // ── L1 / R1: Melodie-Preset ───────────────────────────────────────
        pad.leftShoulder.valueChangedHandler  = { [weak self] _, _, p in if p { self?.onMelodyPrev?() } }
        pad.rightShoulder.valueChangedHandler = { [weak self] _, _, p in if p { self?.onMelodyNext?() } }

        // ── D-Pad oben: Bass-Mode Toggle ──────────────────────────────────
        pad.dpad.up.valueChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.onBassToggle?() }
        }
        // ── D-Pad links/rechts: Netzwerk wechseln ─────────────────────────
        pad.dpad.left.valueChangedHandler  = { [weak self] _, _, p in if p { self?.onNetworkPrev?() } }
        pad.dpad.right.valueChangedHandler = { [weak self] _, _, p in if p { self?.onNetworkNext?() } }

        // ── △ Dreieck: All Notes Off ───────────────────────────────────────
        pad.buttonY.valueChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.onAllNotesOff?() }
        }

        // ── OPTIONS (☰): Steuerungsübersicht ein/ausblenden ───────────────
        pad.buttonMenu.valueChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.onToggleHelp?() }
        }

        // ── Touchpad X/Y → MIDI CC (via physicalInputProfile) ───────────────
        if let dualSense = c.physicalInputProfile as? GCDualSenseGamepad {
            dualSense.touchpadPrimary.valueChangedHandler = { [weak self] (_, x, y) in
                guard let self else { return }
                // HUD immer aktualisieren
                self.onTouchpadChanged?(Float(x), Float(y))
                // Swipe-Erkennung für Netzwerkwechsel (alternativ zu D-Pad)
                let fx = Float(x)
                if fx > 0.55, !self.touchpadSwipeFired {
                    self.touchpadSwipeFired = true
                    self.onNetworkNext?()
                } else if fx < -0.55, !self.touchpadSwipeFired {
                    self.touchpadSwipeFired = true
                    self.onNetworkPrev?()
                } else if abs(fx) < 0.15 {
                    self.touchpadSwipeFired = false   // Finger zur Mitte → Reset
                }
                // MIDI nur wenn aktiv
                let s = AppSettings.shared
                guard s.midi.sensorEnabled, s.midi.touchpadEnabled else { return }
                let xCC = max(0, min(127, Int((Float(x) + 1.0) / 2.0 * 127.0)))
                let yCC = max(0, min(127, Int((Float(y) + 1.0) / 2.0 * 127.0)))
                MIDIManager.shared.sendCC(channel: s.midi.sensorMidiChannel, cc: s.midi.touchpadXCC, value: xCC)
                MIDIManager.shared.sendCC(channel: s.midi.sensorMidiChannel, cc: s.midi.touchpadYCC, value: yCC)
            }
            print("👆 Touchpad verfügbar (physicalInputProfile)")
        } else {
            print("👆 Kein DualSense-Profil – Touchpad nicht verfügbar")
        }

        // ── GCMotion: Gyro-Tilt → MIDI CC ────────────────────────────────
        //  Benutzt Schwerkraft-Vektor (gravity) für stabile Winkel:
        //    gravity.x  ≈  Tilt links/rechts  (-1 … +1)
        //    gravity.y  ≈  Tilt vor/zurück     (-1 … +1)
        //  Throttle auf 20 Hz um MIDI-Datenstau zu vermeiden.
        if let motion = c.motion {
            motion.sensorsActive = true
            print("🔄 GCMotion verfügbar – sensorsActive gesetzt")
            motion.valueChangedHandler = { [weak self] m in
                guard let self else { return }
                let s = AppSettings.shared
                let now = Date()
                guard now.timeIntervalSince(self.lastMotionSend) >= 0.05 else { return }
                self.lastMotionSend = now
                let sens  = Float(s.midi.gyroSensitivity)
                let roll  = max(-1.0, min(1.0, Float(m.gravity.x) * sens))
                let pitch = max(-1.0, min(1.0, Float(m.gravity.y) * sens))
                // HUD immer aktualisieren (unabhängig von sensorEnabled)
                self.onMotionChanged?(roll, pitch)
                // MIDI CC nur senden wenn Sensor aktiviert
                guard s.midi.sensorEnabled, s.midi.gyroEnabled else { return }
                let rollCC  = max(0, min(127, Int((roll  + 1.0) / 2.0 * 127.0)))
                let pitchCC = max(0, min(127, Int((pitch + 1.0) / 2.0 * 127.0)))
                MIDIManager.shared.sendCC(channel: s.midi.sensorMidiChannel, cc: s.midi.gyroRollCC,  value: rollCC)
                MIDIManager.shared.sendCC(channel: s.midi.sensorMidiChannel, cc: s.midi.gyroPitchCC, value: pitchCC)
            }
            print("🔄 Motion-Sensor aktiv: Gyro + Beschleunigung verfügbar")
        } else {
            print("⚠️  c.motion ist nil – Gyro nicht verfügbar (USB-Kabel statt Bluetooth?)")
            print("    Controller: \(c.productCategory) / \(c.vendorName ?? "?")")
        }
    }

    // MARK: – Hilfsfunktionen

    /// Dominante Richtung des Sticks als Sektor 0–3
    /// 0=oben(Root)  1=rechts(Terz)  2=unten(Quinte)  3=links(Septime)
    private func dominantSector(x: Float, y: Float) -> Int {
        if abs(y) >= abs(x) {
            return y > 0 ? 0 : 2   // Oben / Unten
        } else {
            return x > 0 ? 1 : 3   // Rechts / Links
        }
    }

    private func apply(deadzone value: Float) -> Float {
        abs(value) < deadzone ? 0 : value
    }

    private func resetAll() {
        lookX = 0; lookY = 0
        thrustFwd = 0; thrustBwd = 0
        braking = false
        stickOctaveUp = false   // Toggle zurücksetzen beim Trennen
        onL3Change?(false)
        // Off für aktiven Chord-Ton senden (mit Sektor + fixierter Note), bevor Zustand gelöscht wird.
        if let old = lastChordSector, let note = activeChordToneNote {
            onChordToneOff?(old, note)
        }
        lastChordSector     = nil
        activeChordToneNote = nil
    }
}

// MARK: – InputProvider-Conformance
//
// Alle fünf Protokoll-Properties existieren bereits (thrustFwd, thrustBwd,
// lookX, lookY, braking) – keine zusätzlichen Wrapper nötig.
//
// Bewusst NICHT im Protokoll: Sensor-Telemetrie (motionGravity,
// motionRotationMagnitude, motionAvailable) und Audio-Callbacks –
// das gehört nicht zur Flugsteuerungs-Schnittstelle.

extension GamepadController: InputProvider {}

// MARK: – Float-Clamp Hilfsfunktion
private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
