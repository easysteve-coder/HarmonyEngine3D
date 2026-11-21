import SwiftUI
import SceneKit
import AppKit

// MARK: – SwiftUI-Wrapper für SCNView

struct SceneKitView: NSViewRepresentable {

    let scene:            HarmonyScene
    let flightController: FlightController
    let targetingModel:   TargetingOverlayModel

    func makeNSView(context: Context) -> FlightSCNView {
        let view = FlightSCNView(frame: .zero, options: nil)
        view.scene                      = scene
        view.backgroundColor            = NSColor(calibratedRed: 0.02, green: 0.02, blue: 0.08, alpha: 1)
        view.antialiasingMode           = .multisampling4X
        view.autoenablesDefaultLighting = false
        view.showsStatistics            = false
        view.isPlaying                  = true
        view.delegate                   = context.coordinator
        view.flightController           = flightController
        return view
    }

    func updateNSView(_ nsView: FlightSCNView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(scene: scene, flightController: flightController, targetingModel: targetingModel)
    }

    // MARK: – Render-Loop

    final class Coordinator: NSObject, SCNSceneRendererDelegate {

        private let scene:            HarmonyScene
        private let flightController: FlightController
        private let targetingModel:   TargetingOverlayModel
        private var lastTime: TimeInterval = 0

        // Targeting: alle 3 Frames (≈50 ms bei 60 fps)
        private var targetingTick = 0

        // NSView.bounds darf nur auf dem Main Thread gelesen werden.
        // Der Cache wird im Targeting-Takt asynchron vom Main Thread aktualisiert
        // und vom Render-Thread schreibgeschützt gelesen.
        // Initialisierung mit typischer Fenstergröße; korrekte Größe liegt spätestens
        // nach dem ersten Targeting-Zyklus (≈50 ms) vor.
        private var cachedViewSize = CGSize(width: 1280, height: 800)
        private let viewSizeLock   = NSLock()

        // Zuletzt berechnetes Proximity-Magnet-Ziel (nächster sichtbarer Akkord).
        // Wird nur alle 3 Frames in updateTargets(...) neu bestimmt, aber jeden
        // Frame in den FlightController-Update-Aufruf gegeben – ausschließlich vom
        // Render-Thread gelesen/geschrieben, kein Lock nötig (Runde 024 / E-04:
        // ersetzt den vormals async auf Main dispatchten Direktschreibzugriff auf
        // flightController.magnetTarget).
        private var latestMagnetTarget: simd_float3? = nil

        init(scene: HarmonyScene, flightController: FlightController, targetingModel: TargetingOverlayModel) {
            self.scene            = scene
            self.flightController = flightController
            self.targetingModel   = targetingModel
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            let delta = lastTime == 0 ? 0.016 : Float(time - lastTime)
            lastTime  = time
            let dt    = min(delta, 0.1)

            // ── Kamera-Reset bei Netzwerkwechsel ─────────────────────────────
            // Setzt Position, Velocity und Orientierung (Quaternion) zurück, über
            // eine Controller-Methode statt offenem Direktzugriff auf state
            // (Runde 024 / E-04).
            if let newPos = scene.consumePendingCameraReset() {
                flightController.resetForRender(position: newPos)
            }

            // ── Physik-Update ─────────────────────────────────────────────────
            // Autopilot-Ziel, harmonischer Magnet-Einfluss und Proximity-Magnet-
            // Ziel werden als Parameter übergeben statt separat als Properties
            // gesetzt zu werden (Runde 024 / E-04) – update(...) ist der einzige
            // Ort, an dem FlightState mutiert wird.
            flightController.update(
                deltaTime:               dt,
                autopilotTarget:         scene.autopilotEngine.targetPosition,
                harmonicMagnetInfluence: scene.magnetInfluence,
                magnetTarget:            latestMagnetTarget,
                autopilotNextChordName:  scene.autopilotNextChordName
            )

            // ── FlightState → Kamera-Transform ───────────────────────────────
            let st = flightController.state
            scene.cameraNode.simdPosition    = st.position
            scene.cameraNode.simdOrientation = st.orientation

            // ── Szene mit aktueller Kameraposition aktualisieren ──────────────
            let cameraPos = SCNVector3(st.position)
            scene.updateProximity(cameraPosition: cameraPos, deltaTime: dt)

            scene.wrapCamera(scene.cameraNode)

            // ── Targeting + Magnet-Target ─────────────────────────────────────
            targetingTick += 1
            guard targetingTick % 3 == 0,
                  let scnView = renderer as? SCNView else { return }

            // NSView.bounds ist Main-Thread-Pflicht.
            // Cache für diesen Zyklus bereits vorhanden; hier wird der nächste
            // Zyklus vorbereitet. Bounds ändern sich nur bei Fenstergrößenänderung –
            // eine Verzögerung von 3 Frames (≈ 50 ms) ist in diesem Kontext nicht wahrnehmbar.
            DispatchQueue.main.async { [weak self, weak scnView] in
                guard let self, let scnView else { return }
                let size = scnView.bounds.size
                self.viewSizeLock.lock()
                self.cachedViewSize = size
                self.viewSizeLock.unlock()
            }

            updateTargets(scnView: scnView, cameraPos: st.position)
        }

        // ── Targeting-Berechnung + Magnet-Target-Selektion ───────────────────

        private func updateTargets(scnView: SCNView, cameraPos: simd_float3) {
            // NSView.bounds: ausschließlich über Cache lesen (Main-Thread-sicher)
            viewSizeLock.lock()
            let viewSize = cachedViewSize
            viewSizeLock.unlock()
            let viewH              = Float(viewSize.height)
            let autopilotTargetPos = scene.autopilotEngine.targetPosition
            var targets: [ScreenTarget] = []
            var nearestDist: Float = .infinity
            var nearestPos:  simd_float3? = nil

            for (uniqueKey, node) in scene.chordNodes {
                guard node.opacity > 0.5 else { continue }

                let worldPos = node.simdWorldPosition
                let dist     = simd_distance(cameraPos, worldPos)
                guard dist < 700 else { continue }

                // Projektion in Screen-Space
                let projected = scnView.projectPoint(SCNVector3(worldPos))
                guard projected.z > 0, projected.z < 1 else { continue }   // vor der Kamera

                // macOS: SCNView-Ursprung unten-links → SwiftUI oben-links
                let screenX = CGFloat(projected.x)
                let screenY = CGFloat(viewH) - CGFloat(projected.y)
                guard screenX > -40, screenX < viewSize.width  + 40,
                      screenY > -40, screenY < viewSize.height + 40 else { continue }

                // Echter Akkordname aus chordDataMap; uniqueKey als Fallback
                let displayName = scene.chordDataMap[uniqueKey]?.name ?? uniqueKey

                let isAutopilot: Bool
                if let ap = autopilotTargetPos {
                    isAutopilot = simd_distance(worldPos, ap) < 2.0
                } else {
                    isAutopilot = false
                }

                targets.append(ScreenTarget(
                    id:                uniqueKey,
                    name:              displayName,
                    screenPos:         CGPoint(x: screenX, y: screenY),
                    distance:          dist,
                    isAutopilotTarget: isAutopilot
                ))

                // Nächsten Akkord für Magnet tracken
                if dist < nearestDist {
                    nearestDist = dist
                    nearestPos  = worldPos
                }
            }

            // Nach Distanz sortieren, maximal 15 anzeigen
            targets.sort { $0.distance < $1.distance }
            let trimmed = Array(targets.prefix(15))

            // Render-Thread-lokal, kein Dispatch nötig – wird direkt im nächsten
            // update(...)-Aufruf verwendet (Runde 024 / E-04). Nur targetingModel
            // (SwiftUI @Published) braucht den Main-Thread-Dispatch.
            latestMagnetTarget = nearestPos

            DispatchQueue.main.async {
                self.targetingModel.targets = trimmed
            }
        }
    }
}

// MARK: – SCNView-Subklasse mit Tastatur- und Mauseingabe

final class FlightSCNView: SCNView {

    var flightController: FlightController?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            self.window?.makeKeyAndOrderFront(nil)
            self.window?.makeFirstResponder(self)
        }
    }

    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) { /* handled by FlightController monitor */ }
    override func keyUp(with event: NSEvent)   { /* handled by FlightController monitor */ }

    override func mouseDragged(with event: NSEvent) {
        flightController?.mouseDragged(event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        flightController?.mouseDragged(event)
    }
}
