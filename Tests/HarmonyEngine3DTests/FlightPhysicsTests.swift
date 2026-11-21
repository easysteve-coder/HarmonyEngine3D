import XCTest
import simd
@testable import HarmonyEngine3D

// MARK: – FlightPhysicsTests
//
// Regressionstests für FlightPhysics.update(...) (Runde 024 / E-04, Scope D).
// FlightState/InputState/FlightPhysics sind reine Value-Typen ohne SceneKit-/
// AppKit-/AppSettings-Abhängigkeit – direkt testbar, kein Refactoring nötig.
// Diese Tests fixieren das bestehende Flugverhalten, damit die E-04-Umstellung
// auf FlightInputSnapshot es nicht versehentlich verändert.

final class FlightPhysicsTests: XCTestCase {

    private let physics = FlightPhysics(thrustForce: 165.0, maxSpeed: 144.0, dragCoeff: 1.5)

    // MARK: – Vorwärtsschub

    func test_forwardInput_acceleratesForward() {
        var state = FlightState()
        var input = InputState()
        input.forward = 1.0

        physics.update(state: &state, input: input, dt: 1.0 / 60.0)

        // Identitäts-Orientierung: forward == (0, 0, -1) -> Beschleunigung nach -Z.
        XCTAssertGreaterThan(simd_length(state.velocity), 0)
        XCTAssertLessThan(state.velocity.z, 0)
        XCTAssertEqual(state.velocity.x, 0, accuracy: 1e-5)
        XCTAssertEqual(state.velocity.y, 0, accuracy: 1e-5)
    }

    // MARK: – Bremsen

    func test_braking_reducesSpeed() {
        var state = FlightState()
        state.velocity = simd_float3(0, 0, -50)

        var input = InputState()
        input.braking = true

        physics.update(state: &state, input: input, dt: 1.0 / 60.0)

        XCTAssertLessThan(simd_length(state.velocity), 50)
    }

    func test_braking_ignoresThrustInput() {
        var state = FlightState()
        state.velocity = simd_float3(0, 0, -10)

        var input = InputState()
        input.braking = true
        input.forward = 1.0   // muss bei aktivem Bremsen ignoriert werden

        physics.update(state: &state, input: input, dt: 1.0 / 60.0)

        // Nur exponentielle Dämpfung, kein zusätzlicher Schub -> Geschwindigkeit
        // bleibt strikt Richtung 0 fallend, kein Anstieg.
        XCTAssertLessThan(simd_length(state.velocity), 10)
    }

    // MARK: – Höchstgeschwindigkeit

    func test_maxSpeed_isClamped() {
        // Geschwindigkeit deutlich über maxSpeed vorgeben (z. B. nach einem
        // Frame-Hitch) -> Dämpfung allein reicht bei diesem dt nicht, um unter
        // maxSpeed zu fallen -> die explizite Klammerung muss greifen.
        var state = FlightState()
        state.velocity = simd_float3(0, 0, -500)
        let input = InputState()   // kein Schub, kein Bremsen

        physics.update(state: &state, input: input, dt: 1.0 / 60.0)

        XCTAssertEqual(simd_length(state.velocity), 144.0, accuracy: 1e-3)
    }

    func test_forwardThrust_neverExceedsMaxSpeed_overManyFrames() {
        var state = FlightState()
        var input = InputState()
        input.forward = 1.0

        for _ in 0..<600 {
            physics.update(state: &state, input: input, dt: 1.0 / 60.0)
            XCTAssertLessThanOrEqual(simd_length(state.velocity), 144.0 + 1e-3)
        }
    }

    // MARK: – Rotation (Yaw/Pitch)

    func test_yawDelta_rotatesOrientationDeterministically() {
        var stateA = FlightState()
        var stateB = FlightState()
        var input  = InputState()
        input.yawDelta = 0.1

        physics.update(state: &stateA, input: input, dt: 1.0 / 60.0)
        physics.update(state: &stateB, input: input, dt: 1.0 / 60.0)

        XCTAssertEqual(stateA.orientation.vector, stateB.orientation.vector)
        XCTAssertNotEqual(stateA.orientation.vector, FlightState().orientation.vector)
    }

    func test_pitchDelta_changesForwardVector() {
        var state = FlightState()
        var input = InputState()
        input.pitchDelta = .pi / 2   // 90° nach oben nicken

        physics.update(state: &state, input: input, dt: 1.0)

        // Nase zeigt jetzt näherungsweise nach oben (+Y) statt -Z.
        XCTAssertEqual(state.forward.y, 1.0, accuracy: 1e-4)
        XCTAssertEqual(state.forward.z, 0.0, accuracy: 1e-4)
    }

    func test_zeroInput_noRotation() {
        var state = FlightState()
        let input = InputState()   // alles 0

        physics.update(state: &state, input: input, dt: 1.0 / 60.0)

        XCTAssertEqual(state.orientation.vector, FlightState().orientation.vector)
    }
}
