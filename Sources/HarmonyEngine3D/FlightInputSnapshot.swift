import simd

// MARK: – FlightConfigSnapshot
//
// Wert-Snapshot der für FlightController.update(...) relevanten AppSettings.flight-
// Werte (Runde 024 / E-04). Seit Runde 025 / E-05 ruft ausschließlich ein
// Main-Thread-Combine-Sink (FlightController.subscribeToConfigChanges()) noch
// .current() auf; der Renderpfad liest den zuletzt so gebauten Snapshot nur
// noch gelockt (FlightController.snapshotConfig()), statt AppSettings.shared
// selbst live vom Render-Thread zu lesen.

struct FlightConfigSnapshot: Equatable {
    let thrustForce:              Float
    let maxSpeed:                 Float
    let autopilotEnabled:         Bool
    let autopilotSpeed:           Float
    let invertPitch:              Bool
    let gamepadYawSensitivity:    Float
    let gamepadPitchSensitivity:  Float
    let magnetStrength:           Float
    let magnetRadius:             Float

    static func current() -> FlightConfigSnapshot {
        let f = AppSettings.shared.flight
        return FlightConfigSnapshot(
            thrustForce:             Float(f.thrustForce),
            maxSpeed:                Float(f.maxSpeed),
            autopilotEnabled:        f.autopilotEnabled,
            autopilotSpeed:          Float(f.autopilotSpeed),
            invertPitch:             f.invertPitch,
            gamepadYawSensitivity:   Float(f.gamepadYawSensitivity),
            gamepadPitchSensitivity: Float(f.gamepadPitchSensitivity),
            magnetStrength:          Float(f.magnetStrength),
            magnetRadius:            Float(f.magnetRadius)
        )
    }
}

// MARK: – MidiRuntimeConfigSnapshot
//
// Wert-Snapshot der für FlightController.processSensors() relevanten
// AppSettings.shared.midi-Werte (Runde 025 / E-05). Wie FlightConfigSnapshot
// wird .current() nur noch von einem Main-Thread-Combine-Sink aufgerufen
// (FlightController.subscribeToConfigChanges()), nie mehr live vom
// Render-Thread — siehe FlightController.snapshotConfig().

struct MidiRuntimeConfigSnapshot: Equatable {
    let gyroSensitivity:   Float
    let sensorEnabled:     Bool
    let gyroEnabled:       Bool
    let rotationEnabled:   Bool
    let sensorMidiChannel: Int
    let gyroRollCC:        Int
    let gyroPitchCC:       Int
    let rotationCC:        Int

    static func current() -> MidiRuntimeConfigSnapshot {
        let m = AppSettings.shared.midi
        return MidiRuntimeConfigSnapshot(
            gyroSensitivity:   Float(m.gyroSensitivity),
            sensorEnabled:     m.sensorEnabled,
            gyroEnabled:       m.gyroEnabled,
            rotationEnabled:   m.rotationEnabled,
            sensorMidiChannel: m.sensorMidiChannel,
            gyroRollCC:        m.gyroRollCC,
            gyroPitchCC:       m.gyroPitchCC,
            rotationCC:        m.rotationCC
        )
    }
}

// MARK: – FlightInputSnapshot
//
// Immutables Bündel aller Eingaben, die FlightController.update(...) für einen
// Frame braucht (Runde 024 / E-04). Wird ausschließlich innerhalb von
// FlightController.update(...) (Renderloop-Aufrufer) aus dem aktuellen
// Input-/Ziel-Zustand gebaut – Input-Callbacks (Maus, Tastatur) schreiben nur
// noch Inputzustand, FlightState selbst wird außerhalb des Renderloops nicht
// mehr mutiert.
//
// harmonicMagnetInfluence/magnetTarget: zwei getrennte Mechanismen (siehe
// FlightController.applyMagneticForce) – harmonicMagnetInfluence liefert eine
// sanfte, profil-/score-modulierte Richtungskorrektur (keine Kraft), magnetTarget
// einen Velocity-Nudge (Kraft proportional zur Distanz). Bewusst nicht
// zusammengeführt, um die bestehende Trennung nicht zu verwischen.

struct FlightInputSnapshot {
    var keyForward:  Float = 0   // WASD-abgeleitete Translationsabsicht, additiv, -1…+1
    var keyStrafe:   Float = 0
    var keyVertical: Float = 0

    var mouseDeltaX: Float = 0   // seit dem letzten Snapshot akkumuliert, danach 0
    var mouseDeltaY: Float = 0

    var gamepadThrustFwd: Float = 0
    var gamepadThrustBwd: Float = 0
    var gamepadLookX:     Float = 0
    var gamepadLookY:     Float = 0
    var gamepadBraking:   Bool  = false

    var autopilotTarget:         simd_float3?             = nil
    var harmonicMagnetInfluence: HarmonicMagnetInfluence?  = nil
    var magnetTarget:            simd_float3?              = nil

    var config: FlightConfigSnapshot = FlightConfigSnapshot(
        thrustForce: 165.0, maxSpeed: 144.0,
        autopilotEnabled: false, autopilotSpeed: 0,
        invertPitch: false,
        gamepadYawSensitivity: 0, gamepadPitchSensitivity: 0,
        magnetStrength: 0, magnetRadius: 0
    )
}

// MARK: – FlightHUDSnapshot
//
// Immutables Bündel aller HUD-relevanten Werte, die FlightController.update(...)
// am Ende eines Frames einmalig (statt mehrerer einzelner Dispatches) auf den
// Main Thread überführt (Runde 024 / E-04, Scope C).
//
// gyroRoll/gyroPitch sind optional: nil bedeutet "diesen Frame keine neuen
// Gyro-Daten verfügbar" (GamepadController.motionGravity == nil) – der bisherige
// HUD-Wert bleibt dann unverändert, statt überschrieben zu werden (identisch zum
// bisherigen Verhalten, das in diesem Fall einfach nicht dispatchte).
//
// debugInput bewusst nicht Teil dieses Snapshots: es wird ausschließlich aus dem
// Tastatur-Callback gesetzt (nicht pro Frame), ist dort bereits Main-Thread-sicher
// (eigener DispatchQueue.main.async) und hat keinen Bezug zum Renderloop-Takt.

struct FlightHUDSnapshot {
    let currentSpeed:       Float
    let autopilotNextChord: String
    let gyroRoll:            Float?
    let gyroPitch:           Float?
    let motionAvail:         Bool
    let rotationMag:         Float
}
