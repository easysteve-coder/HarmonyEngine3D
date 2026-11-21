import Foundation

// MARK: – InputProvider
//
// Minimales Protokoll für Flug-Eingabequellen.
//
// Transportiert exakt die Rohwerte, die der FlightController für
// Flugphysik und Kameraorientierung (buildInputState) benötigt.
//
// Bewusst ausgeschlossen:
//   · Sensor-Telemetrie (Gyro, Touchpad → MIDI CC)
//     → bleibt direkt in GamepadController/FlightController.processSensors()
//   · Chord-Tone-Callbacks, Melodie-Preset, Netzwerk-Navigation
//     → Audio-Output-Layer, nicht Flugsteuerung
//   · Tastatur (WASDQE) + Maus-Drag
//     → macOS-lokale Eingaben, bleiben im FlightController selbst
//
// Erweiterungspunkt: Ein späterer TouchInputProvider für iPhone
// implementiert dieses Protokoll. FlightController bleibt dabei unverändert.

protocol InputProvider: AnyObject {

    /// Schub vorwärts: R2-Trigger (0 … 1)
    var thrustFwd: Float { get }

    /// Schub rückwärts: L2-Trigger (0 … 1)
    var thrustBwd: Float { get }

    /// Yaw-Achse des Blick-Sticks: rechter Stick X (-1 … +1)
    var lookX: Float { get }

    /// Pitch-Achse des Blick-Sticks: rechter Stick Y (-1 … +1)
    var lookY: Float { get }

    /// Vollbremse: R3 gedrückt
    var braking: Bool { get }
}
