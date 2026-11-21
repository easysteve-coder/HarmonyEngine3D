import simd

// MARK: – FlightState
//
// Vollständiger Flugzustand. Kein SceneKit, keine Abhängigkeiten.
//
// Orientierung als Quaternion gespeichert – kein Gimbal-Lock, Loopings möglich.
// forward/right werden aus der Quaternion abgeleitet.
//
// Steuerungskonvention (body-space):
//   pitchDelta > 0 → Nase hoch
//   yawDelta   > 0 → Nase nach links (Drehung um lokale +Y)
//   Beide Achsen bleiben nach Loopings konsistent relativ zur Schiffsorientierung.

struct FlightState {
    var position:    simd_float3 = .zero
    var velocity:    simd_float3 = .zero

    // Quaternion-Orientierung. Startwert = Identität (schaut in -Z, Y = oben).
    var orientation: simd_quatf  = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

    // ── Richtungsvektoren aus Quaternion ────────────────────────────────────
    var forward: simd_float3 { orientation.act(simd_float3(0,  0, -1)) }
    var right:   simd_float3 { orientation.act(simd_float3(1,  0,  0)) }
    var up:      simd_float3 { orientation.act(simd_float3(0,  1,  0)) }
}

// MARK: – InputState
//
// Neutraler Kanal zwischen Input-Layer (Tastatur, Gamepad, Autopilot) und Physik.
// yawDelta/pitchDelta werden body-space auf die Quaternion angewendet.

struct InputState {
    var forward:    Float = 0   // -1…+1
    var strafe:     Float = 0   // -1…+1
    var vertical:   Float = 0   // -1…+1
    var yawDelta:   Float = 0   // Radiant / Frame, body-space um lokale Y
    var pitchDelta: Float = 0   // Radiant / Frame, body-space um lokale X
    var braking:    Bool  = false
}

// MARK: – FlightPhysics
//
// Integriert InputState auf FlightState.
// Kein Pitch-Limit → volle Rotationsfreiheit inkl. Loopings.

struct FlightPhysics {

    let thrustForce: Float
    let maxSpeed:    Float
    let dragCoeff:   Float

    init(thrustForce: Float = 165.0,
         maxSpeed:    Float = 144.0,
         dragCoeff:   Float = 1.5) {
        self.thrustForce = thrustForce
        self.maxSpeed    = maxSpeed
        self.dragCoeff   = dragCoeff
    }

    func update(state: inout FlightState, input: InputState, dt: Float) {

        // ── 1. Rotation (body-space Quaternion-Komposition) ───────────────────
        //
        // Reihenfolge: erst Yaw (um lokale Y), dann Pitch (um lokale X nach Yaw).
        // Das entspricht dem natürlichen "Kopf drehen, dann nicken".
        if input.yawDelta != 0 || input.pitchDelta != 0 {
            let yawQ   = simd_quatf(angle: input.yawDelta,   axis: simd_float3(0, 1, 0))
            let pitchQ = simd_quatf(angle: input.pitchDelta,  axis: simd_float3(1, 0, 0))
            state.orientation = simd_normalize(state.orientation * yawQ * pitchQ)
        }

        // ── 2. Schub ──────────────────────────────────────────────────────────
        if input.braking {
            state.velocity *= exp(-8.0 * dt)
        } else {
            var thrust = simd_float3.zero
            if input.forward  != 0 { thrust += state.forward * (input.forward  * thrustForce) }
            if input.strafe   != 0 { thrust += state.right   * (input.strafe   * thrustForce) }
            if input.vertical != 0 { thrust += state.up      * (input.vertical * thrustForce) }

            // ── 3. Geschwindigkeit integrieren ────────────────────────────────
            state.velocity += thrust * dt

            // ── 4. Dämpfung: frame-rate-unabhängiger Exponentialabfall ────────
            state.velocity *= exp(-dragCoeff * dt)

            // ── 5. Höchstgeschwindigkeit ──────────────────────────────────────
            let spd = simd_length(state.velocity)
            if spd > maxSpeed { state.velocity *= maxSpeed / spd }
        }

        // ── 6. Position integrieren ───────────────────────────────────────────
        state.position += state.velocity * dt
    }

    // Winkel auf −π…π normalisieren (für Autopilot-Winkelberechnungen).
    static func wrapAngle(_ a: Float) -> Float {
        var r = a.truncatingRemainder(dividingBy: .pi * 2)
        if r >  .pi { r -= .pi * 2 }
        if r < -.pi { r += .pi * 2 }
        return r
    }
}
