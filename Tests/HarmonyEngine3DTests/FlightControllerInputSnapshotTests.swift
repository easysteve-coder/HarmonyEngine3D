import XCTest
import simd
@testable import HarmonyEngine3D

// MARK: – FlightControllerInputSnapshotTests
//
// Runde 024 / E-04, Scope D: deckt die neue FlightState-Thread-Grenze ab.
// mouseDragged/Tastatur werden über die AppKit-freien Testseams
// recordMouseDelta(dx:dy:)/setKeyDown(_:isDown:) simuliert (siehe Handoff-
// Empfehlung), statt echte NSEvent-Objekte zu konstruieren.
//
// autopilotTarget wird in jedem update(...)-Aufruf bewusst nil übergeben,
// damit die Tests unabhängig von persistierten AppSettings.shared.flight.
// autopilotEnabled-Werten deterministisch den manuellen Zweig durchlaufen
// (buildInputState fällt ohne autopilotTarget immer auf den Else-Zweig
// zurück, siehe FlightController.buildInputState).

final class FlightControllerInputSnapshotTests: XCTestCase {

    private func update(_ controller: FlightController, dt: Float = 1.0 / 60.0) {
        controller.update(
            deltaTime: dt,
            autopilotTarget: nil,
            harmonicMagnetInfluence: nil,
            magnetTarget: nil,
            autopilotNextChordName: ""
        )
    }

    // MARK: – Maus: kein Sofort-Effekt, Konsum + Reset im nächsten update()

    func test_recordMouseDelta_doesNotMutateStateImmediately() {
        let controller = FlightController()
        let before = controller.state.orientation.vector

        controller.recordMouseDelta(dx: 1.0, dy: 1.0)

        XCTAssertEqual(controller.state.orientation.vector, before)
    }

    func test_recordMouseDelta_appliedOnlyOnNextUpdate() {
        let controller = FlightController()
        let identity = controller.state.orientation.vector

        controller.recordMouseDelta(dx: 0.2, dy: 0.1)
        update(controller)

        XCTAssertNotEqual(controller.state.orientation.vector, identity)
    }

    func test_mouseDelta_isConsumedAndResetAfterUpdate() {
        let controller = FlightController()

        controller.recordMouseDelta(dx: 0.2, dy: 0.1)
        update(controller)
        let afterFirstUpdate = controller.state.orientation.vector

        // Kein neuer recordMouseDelta-Aufruf -> zweites update() darf die
        // Orientierung nicht mehr verändern (Delta wurde konsumiert + genullt).
        update(controller)
        let afterSecondUpdate = controller.state.orientation.vector

        XCTAssertEqual(afterFirstUpdate, afterSecondUpdate)
    }

    func test_recordMouseDelta_accumulatesMultipleCallsBeforeConsumption() {
        let controllerSingle = FlightController()
        controllerSingle.recordMouseDelta(dx: 0.4, dy: 0.0)
        update(controllerSingle)

        let controllerSplit = FlightController()
        controllerSplit.recordMouseDelta(dx: 0.1, dy: 0.0)
        controllerSplit.recordMouseDelta(dx: 0.3, dy: 0.0)
        update(controllerSplit)

        // Zwei kleine Deltas vor dem Konsum akkumulieren zum selben Ergebnis
        // wie ein einzelnes großes Delta.
        let distance = simd_distance(controllerSingle.state.orientation.vector,
                                      controllerSplit.state.orientation.vector)
        XCTAssertEqual(distance, 0, accuracy: 1e-6)
    }

    // MARK: – Tastatur: beeinflusst Snapshot/InputState, nicht FlightState direkt

    func test_setKeyDown_doesNotMutateStateImmediately() {
        let controller = FlightController()
        let before = controller.state.position

        controller.setKeyDown(13, isDown: true)   // W

        XCTAssertEqual(controller.state.position, before)
    }

    func test_setKeyDown_forwardMovesPositionOnNextUpdate() {
        let controller = FlightController()
        controller.setKeyDown(13, isDown: true)   // W

        update(controller, dt: 0.1)

        XCTAssertLessThan(controller.state.position.z, 0)   // Identität schaut nach -Z
    }

    func test_setKeyDown_upAndDown_cancelOut() {
        let controller = FlightController()
        controller.setKeyDown(13, isDown: true)   // W (forward)
        controller.setKeyDown(1,  isDown: true)   // S (backward) -> additiv 0

        update(controller, dt: 0.1)

        XCTAssertEqual(simd_length(controller.state.velocity), 0, accuracy: 1e-4)
    }

    func test_setKeyDown_keyUp_stopsMovement() {
        let controller = FlightController()
        controller.setKeyDown(13, isDown: true)
        update(controller, dt: 0.1)
        controller.setKeyDown(13, isDown: false)

        let velocityAfterKeyUp = controller.state.velocity
        update(controller, dt: 0.1)

        // Kein Schub mehr -> nur noch Dämpfung, Geschwindigkeit darf nicht steigen.
        XCTAssertLessThanOrEqual(simd_length(controller.state.velocity),
                                  simd_length(velocityAfterKeyUp) + 1e-4)
    }

    // MARK: – Camera-Reset über Controller-Methode

    func test_resetForRender_setsPositionVelocityOrientationDeterministically() {
        let controller = FlightController()
        controller.setKeyDown(13, isDown: true)
        update(controller, dt: 0.2)
        XCTAssertNotEqual(controller.state.position, .zero)

        let resetPos = simd_float3(10, 20, 30)
        controller.resetForRender(position: resetPos)

        XCTAssertEqual(controller.state.position, resetPos)
        XCTAssertEqual(controller.state.velocity, .zero)
        XCTAssertEqual(controller.state.orientation.vector, simd_quatf(ix: 0, iy: 0, iz: 0, r: 1).vector)
    }

    // MARK: – FlightConfigSnapshot ist ein Value

    func test_flightConfigSnapshot_isEquatableValue() {
        let a = FlightConfigSnapshot.current()
        let b = FlightConfigSnapshot.current()
        XCTAssertEqual(a, b)
    }
}
