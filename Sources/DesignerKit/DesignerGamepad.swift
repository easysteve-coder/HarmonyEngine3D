import GameController
import Foundation

// MARK: – Gamepad-Anbindung für die 2D-Navigation
//
//  Rechter Stick    →  Cursor bewegen (X/Y)
//  R2               →  Speed Boost
//  Linker Stick     →  Chord-Tones (0=Root  1=Terz  2=Quinte  3=Septime)
//  D-Pad links/rechts + Touchpad-Swipe → Netzwerk wechseln
//  △ Dreieck        →  All Notes Off
//  OPTIONS (☰)      →  Help-Overlay
//  ✕ / ○ / □ / L1 / R1  →  frei konfigurierbar

final class DesignerGamepad {

    static let shared = DesignerGamepad()

    // ── Bewegungsachsen (rechter Stick) ───────────────────────────────────
    private(set) var moveX: Float = 0   // horizontal  [-1 … +1]
    private(set) var moveY: Float = 0   // vertikal    [-1 … +1]  (positiv = oben)
    private(set) var boost: Float = 0   // R2          [0 … 1]

    // ── Callbacks ─────────────────────────────────────────────────────────
    //  sectorIndex: 0=Root  1=Terz  2=Quinte  3=Septime
    var onChordTone:   ((Int, UInt8) -> Void)?
    var onNetworkPrev: (() -> Void)?
    var onNetworkNext: (() -> Void)?
    var onAllNotesOff: (() -> Void)?
    var onToggleHelp:  (() -> Void)?

    // Frei konfigurierbare Tasten (true=gedrückt, false=losgelassen)
    var onButtonA: ((Bool) -> Void)?   // ✕ Cross
    var onButtonB: ((Bool) -> Void)?   // ○ Circle
    var onButtonX: ((Bool) -> Void)?   // □ Square
    var onL1:      ((Bool) -> Void)?
    var onR1:      ((Bool) -> Void)?

    let deadzone: Float = 0.12

    // ── Interner State ────────────────────────────────────────────────────
    private var controller:         GCController?
    private var lastChordSector:    Int?  = nil
    private var touchpadSwipeFired: Bool  = false

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
            print("🎮 [2D] Gamepad verbunden: \(c.productCategory) – \(c.vendorName ?? "?")")
        } else {
            print("🎮 [2D] Kein Gamepad gefunden – warte auf Verbindung …")
        }
    }

    @objc private func controllerConnected(_ note: Notification) {
        guard let c = note.object as? GCController else { return }
        controller = c; setupHandlers(c)
        print("🎮 [2D] Gamepad verbunden: \(c.productCategory) – \(c.vendorName ?? "?")")
    }

    @objc private func controllerDisconnected(_ note: Notification) {
        print("🎮 [2D] Gamepad getrennt"); controller = nil
        moveX = 0; moveY = 0; boost = 0
        lastChordSector = nil
    }

    // MARK: – Handler registrieren

    private func setupHandlers(_ c: GCController) {
        guard let pad = c.extendedGamepad else {
            print("⚠️  Gamepad unterstützt kein extendedGamepad-Profil"); return
        }

        // ── Rechter Stick → Cursor-Bewegung ───────────────────────────────
        pad.rightThumbstick.valueChangedHandler = { [weak self] _, x, y in
            guard let self else { return }
            self.moveX = self.apply(x)
            self.moveY = self.apply(y)
        }

        // ── R2 → Speed Boost ──────────────────────────────────────────────
        pad.rightTrigger.valueChangedHandler = { [weak self] _, v, _ in self?.boost = v }

        // ── Linker Stick → Chord-Tones ────────────────────────────────────
        pad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            guard let self else { return }
            let mag = sqrt(x*x + y*y)
            if mag < 0.40 { self.lastChordSector = nil; return }
            let sector = self.dominantSector(x: x, y: y)
            guard sector != self.lastChordSector else { return }
            self.lastChordSector = sector
            let vel = UInt8(50 + Int(((mag - 0.4) / 0.6).clamped(to: 0...1) * 77))
            self.onChordTone?(sector, vel)
        }

        // ── D-Pad links/rechts: Netzwerk wechseln ─────────────────────────
        pad.dpad.left.valueChangedHandler  = { [weak self] _, _, p in if p { self?.onNetworkPrev?() } }
        pad.dpad.right.valueChangedHandler = { [weak self] _, _, p in if p { self?.onNetworkNext?() } }

        // ── △ Dreieck: All Notes Off ───────────────────────────────────────
        pad.buttonY.valueChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.onAllNotesOff?() }
        }

        // ── OPTIONS: Help-Overlay ─────────────────────────────────────────
        pad.buttonMenu.valueChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.onToggleHelp?() }
        }

        // ── Frei belegbare Tasten ─────────────────────────────────────────
        pad.buttonA.valueChangedHandler = { [weak self] _, _, p in self?.onButtonA?(p) }  // ✕
        pad.buttonB.valueChangedHandler = { [weak self] _, _, p in self?.onButtonB?(p) }  // ○
        pad.buttonX.valueChangedHandler = { [weak self] _, _, p in self?.onButtonX?(p) }  // □
        pad.leftShoulder.valueChangedHandler  = { [weak self] _, _, p in self?.onL1?(p) }
        pad.rightShoulder.valueChangedHandler = { [weak self] _, _, p in self?.onR1?(p) }

        // ── Touchpad: Swipe links/rechts → Netzwerk wechseln ─────────────
        if let dualSense = c.physicalInputProfile as? GCDualSenseGamepad {
            dualSense.touchpadPrimary.valueChangedHandler = { [weak self] (_, x, y) in
                guard let self else { return }
                let fx = Float(x)
                if fx > 0.55, !self.touchpadSwipeFired {
                    self.touchpadSwipeFired = true
                    self.onNetworkNext?()
                } else if fx < -0.55, !self.touchpadSwipeFired {
                    self.touchpadSwipeFired = true
                    self.onNetworkPrev?()
                } else if abs(fx) < 0.15 {
                    self.touchpadSwipeFired = false
                }
            }
            print("👆 [2D] Touchpad verfügbar")
        }
    }

    // MARK: – Hilfsfunktionen

    private func dominantSector(x: Float, y: Float) -> Int {
        if abs(y) >= abs(x) { return y > 0 ? 0 : 2 }
        else                 { return x > 0 ? 1 : 3 }
    }

    private func apply(_ value: Float) -> Float {
        abs(value) < deadzone ? 0 : value
    }
}

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
