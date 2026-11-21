import XCTest
import simd
@testable import HarmonyEngine3D

// MARK: – ConfigSnapshotTests
//
// Runde 025 / E-05, Scope C: deckt MidiRuntimeConfigSnapshot (neu) sowie den
// Nachweis ab, dass FlightController.update(...) einen injizierten
// Config-Snapshot verwendet statt live AppSettings.shared.flight zu lesen.
// Liest AppSettings.shared.midi nur lesend (keine Mutation, kein
// Debounce-Save-Risiko).

final class ConfigSnapshotTests: XCTestCase {

    // MARK: – MidiRuntimeConfigSnapshot

    func test_midiRuntimeConfigSnapshot_current_reflectsAppSettings() {
        let expected = AppSettings.shared.midi
        let snapshot = MidiRuntimeConfigSnapshot.current()

        XCTAssertEqual(snapshot.sensorEnabled,     expected.sensorEnabled)
        XCTAssertEqual(snapshot.gyroEnabled,       expected.gyroEnabled)
        XCTAssertEqual(snapshot.rotationEnabled,   expected.rotationEnabled)
        XCTAssertEqual(snapshot.sensorMidiChannel, expected.sensorMidiChannel)
        XCTAssertEqual(snapshot.gyroRollCC,        expected.gyroRollCC)
        XCTAssertEqual(snapshot.gyroPitchCC,       expected.gyroPitchCC)
        XCTAssertEqual(snapshot.rotationCC,        expected.rotationCC)
        XCTAssertEqual(snapshot.gyroSensitivity,   Float(expected.gyroSensitivity))
    }

    func test_midiRuntimeConfigSnapshot_isEquatableValue() {
        XCTAssertEqual(MidiRuntimeConfigSnapshot.current(), MidiRuntimeConfigSnapshot.current())
    }

    // MARK: – FlightController verwendet injizierten Snapshot, nicht live AppSettings

    func test_update_usesInjectedConfigSnapshot_notLiveAppSettings() {
        let controller = FlightController()

        // thrustForce/maxSpeed weit außerhalb jedes plausiblen AppSettings-Defaults
        // (Default maxSpeed = 144) -- die Geschwindigkeitsklammer auf exakt den
        // injizierten Wert (5) beweist, dass update() den gecachten Snapshot
        // verwendet statt live AppSettings.shared.flight zu lesen.
        let customFlight = FlightConfigSnapshot(
            thrustForce: 10_000, maxSpeed: 5,
            autopilotEnabled: false, autopilotSpeed: 0,
            invertPitch: false,
            gamepadYawSensitivity: 0, gamepadPitchSensitivity: 0,
            magnetStrength: 0, magnetRadius: 0
        )
        let customMidi = MidiRuntimeConfigSnapshot(
            gyroSensitivity: 0, sensorEnabled: false, gyroEnabled: false, rotationEnabled: false,
            sensorMidiChannel: 0, gyroRollCC: 0, gyroPitchCC: 0, rotationCC: 0
        )
        controller.setConfigForTesting(flight: customFlight, midi: customMidi)
        controller.setKeyDown(13, isDown: true)   // W

        controller.update(
            deltaTime: 1.0,
            autopilotTarget: nil,
            harmonicMagnetInfluence: nil,
            magnetTarget: nil,
            autopilotNextChordName: ""
        )

        XCTAssertEqual(simd_length(controller.state.velocity), 5, accuracy: 1e-3)
    }

    func test_update_withoutInjection_usesRealFlightConfigSnapshotDefaults() {
        // Regression: ohne setConfigForTesting() muss FlightController weiterhin
        // mit dem beim init() via Combine-Sink gebauten echten Snapshot laufen
        // (aus AppSettings.shared.flight zum Konstruktionszeitpunkt).
        let controller  = FlightController()
        let realDefault = FlightConfigSnapshot.current()
        controller.setKeyDown(13, isDown: true)

        controller.update(
            deltaTime: 1.0 / 60.0,
            autopilotTarget: nil,
            harmonicMagnetInfluence: nil,
            magnetTarget: nil,
            autopilotNextChordName: ""
        )

        XCTAssertLessThanOrEqual(simd_length(controller.state.velocity), realDefault.maxSpeed + 1e-3)
    }
}
