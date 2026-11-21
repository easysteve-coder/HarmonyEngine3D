import AppKit
import Combine
import simd

// MARK: – ChordMapping
//
// Atomares Datenmodell für den Cockpit-Akkord-Zustand.
// Name und Töne können nur gemeinsam existieren → Inkonsistenz ausgeschlossen.
//
// tones: Vorberechnete Notenname-Strings (z. B. ["C", "E", "G", "Bb"]).
//        Maximal 4 Einträge (Sektor-Mapping ↑←→↓).
//        Wird nur gesetzt wenn !tones.isEmpty – kein ChordMapping ohne Töne.

struct ChordMapping: Equatable {
    let name:  String    // Akkordname (z. B. "Cmaj7")
    let tones: [String]  // Notenname-Strings, direkt displayfertig
}

// MARK: – FlightController
//
// Koordiniert Input (Tastatur, Gamepad, Autopilot) und Physik.
// Hält FlightState und ruft FlightPhysics.update() auf.
//
// Keine SceneKit-Abhängigkeit. Kein SCNNode.
// SceneKitView liest flightController.state und schreibt es auf die Kamera.
//
// Thread-Grenze (Runde 024 / E-04): FlightState wird ausschließlich innerhalb
// von update(...) mutiert, aufgerufen einzig vom Renderloop (SceneKitView.
// Coordinator.renderer(_:updateAtTime:)). Main-Thread-Input-Callbacks (Maus,
// Tastatur) schreiben nur noch in gelockte Accumulator/Set-Felder; update(...)
// konsumiert daraus einmal pro Frame einen FlightInputSnapshot. Autopilot-Ziel,
// harmonischer Magnet-Einfluss und Proximity-Magnet-Ziel sind keine gespeicherten
// Properties mehr, sondern Parameter von update(...) – sie fließen als Teil des
// Snapshots durch, ohne dass es dafür einen von außen beschreibbaren Zustand gibt.

final class FlightController: ObservableObject {

    // ── Flugzustand (gelesen von SceneKitView → Kamera) ──────────────────
    // private(set): von außen nur lesbar. Mutiert wird ausschließlich innerhalb
    // dieser Klasse (update(...), resetForRender(...)), beide nur vom Renderloop
    // aufgerufen.
    private(set) var state = FlightState()

    // ── Input-Quelle (Gamepad / Touch / …) ───────────────────────────────
    //
    // Wird vom App Layer nach dem Init gesetzt (AppModel.init).
    // FlightController kennt keine konkreten Input-Klassen mehr – nur dieses Protokoll.
    //
    // Bewusste Restkopplung: processSensors() greift weiterhin direkt auf
    // GamepadController.shared zu (Sensor-Telemetrie → MIDI CC, nicht Flug-Input).
    var inputProvider: (any InputProvider)?

    // ── Physik ────────────────────────────────────────────────────────────
    private var physics = FlightPhysics()

    var lookSensitivity: Float = 0.005   // Maus

    // ── Harmonischer Magnet: Zeitbasis (Phase 3.9.1c) ────────────────────
    // rate: Annäherungsgeschwindigkeit an harmonicMagnetInfluence.target, 1/s.
    //   alpha = 1 - exp(-rate * dt) ersetzt die vormals feste 85/15-Frame-Mischung,
    //   die bei 120 Hz doppelt so stark wirkte wie bei 60 Hz.
    //   9.75 ≈ jener Wert, der bei genau 60 Hz (dt ≈ 1/60 s) auf alpha ≈ 0.15 führt –
    //   also dieselbe Stärke wie die alte 60-Hz-Referenzmischung, jetzt aber
    //   für jede Framerate korrekt reproduziert statt zufällig verstärkt/abgeschwächt.
    //
    // Base-Werte × HarmonicMagnetInfluence-Multiplikatoren ergeben die effektiven
    // Werte (Phase 4.2a) — konservativ geklammert, damit MagnetProfile.Preset "strong"
    // + hoher scoreBoost keine spürbaren Geschwindigkeits-/Winkelsprünge erzeugen.
    private let harmonicMagnetRateBase: Float = 9.75
    private let harmonicMagnetRateMin:  Float = 3.0
    private let harmonicMagnetRateMax:  Float = 16.0
    // Obergrenze der Richtungsänderung pro Sekunde – verhindert Winkel-Sprünge
    // bei sehr großem dt (z. B. Frame-Hitches) unabhängig vom alpha-Wert.
    private let harmonicMagnetMaxAngularSpeedBase: Float = 3.0   // rad/s
    private let harmonicMagnetAngularSpeedMin:     Float = 1.0   // rad/s
    private let harmonicMagnetAngularSpeedMax:     Float = 5.0   // rad/s

    // ── UI-Zustand (hierher verlagert, da AppSettings kein UI-State mehr hält) ──
    @Published var showSettingsPanel:   Bool = false
    @Published var showCockpitPanel:    Bool = false
    @Published var showControlsOverlay: Bool = false
    @Published var showMixerPanel:      Bool = false
    @Published var showHarmonicRadar:   Bool = false   // Hotkey: R (keyCode 15)

    // ── HUD / Diagnose ────────────────────────────────────────────────────
    @Published var debugInput:         String = "–"
    @Published var cameraOK:           Bool   = true
    @Published var currentSpeed:       Float  = 0
    @Published var autopilotNextChord: String = ""

    // ── Akkord-Cockpit-Zustand ─────────────────────────────────────────────
    //
    // soundingChordName:
    //   Gesetzt solange CH0 MIDI-Noten ausgibt. Leer sobald der Akkord
    //   deaktiviert wird (noteOff). Steuert die Helligkeit im Cockpit.
    //
    // mappingChord:
    //   Letzter aktivierter Akkord als atomares Struct – bleibt gültige
    //   CH3-Mapping-Quelle bis ein neuer Akkord aktiviert wird.
    //   Name und Töne können nur gemeinsam gesetzt werden (ChordMapping-Struct).
    //   Inkonsistenz (Name ohne Töne) ist damit architektonisch ausgeschlossen.
    //   nil = noch kein Akkord aktiviert.
    @Published var soundingChordName: String        = ""
    @Published var mappingChord:      ChordMapping? = nil

    @Published var ch0Active: Bool = false
    @Published var ch1Active: Bool = false
    @Published var ch2Active: Bool = false
    @Published var ch3Active: Bool = false

    @Published var melodyPresetName: String = "Dorian Penta"

    @Published var leftStickSector: Int?  = nil
    @Published var stickOctaveUp:   Bool  = false

    @Published var approachChordLabel: String = ""
    @Published var approachChordProx:  Float  = 0
    @Published var approachBassLabel:  String = ""
    @Published var approachBassProx:   Float  = 0
    @Published var approachMelodyProx: Float  = 0

    @Published var gyroRoll:    Float = 0
    @Published var gyroPitch:   Float = 0
    @Published var rotationMag: Float = 0
    @Published var touchpadX:   Float = 0
    @Published var touchpadY:   Float = 0
    @Published var motionAvail: Bool  = false

    // ── Tastatur-State ────────────────────────────────────────────────────
    // keysDown wird vom Main-Thread-NSEvent-Monitor geschrieben und im
    // Renderloop (buildInputSnapshot, via snapshotKeysDown()) gelesen –
    // keysLock schützt vor dem daraus resultierenden Cross-Thread-Zugriff
    // (Runde 024 / E-04).
    private var keysDown       = Set<UInt16>()
    private let keysLock       = NSLock()
    private var monitorKeyDown: Any?
    private var monitorKeyUp:   Any?

    private enum Key: UInt16 {
        case w = 13, s = 1, a = 0, d = 2
        case q = 12, e = 14
    }

    // ── Maus-Delta-Accumulator ────────────────────────────────────────────
    // mouseDragged(_:) (Main-Thread-Callback aus FlightSCNView) akkumuliert nur
    // noch hier hinein, statt state.orientation direkt zu mutieren. Der
    // Renderloop konsumiert (liest + setzt auf 0) einmal pro Frame via
    // consumeMouseDelta() (Runde 024 / E-04).
    private var pendingMouseDeltaX: Float = 0
    private var pendingMouseDeltaY: Float = 0
    private let mouseLock = NSLock()

    // ── Config-Snapshots: Main-Thread-Combine statt Render-Thread-Live-Reads ──
    // Runde 025 / E-05. Ein Combine-Sink (subscribeToConfigChanges(),
    // abonniert in init(), läuft auf dem Main Thread) baut bei jeder
    // AppSettings.shared.flight/.midi-Änderung einen frischen Snapshot und
    // hält ihn hier gelockt vor. buildInputSnapshot()/processSensors() lesen
    // ausschließlich snapshotConfig() statt AppSettings.shared live vom
    // Render-Thread zu lesen.
    private var latestFlightConfig = FlightConfigSnapshot.current()
    private var latestMidiConfig   = MidiRuntimeConfigSnapshot.current()
    private let configLock = NSLock()
    private var settingsCancellables = Set<AnyCancellable>()

    // MARK: – Init / Deinit

    init() {
        startMonitoring()
        _ = GamepadController.shared
        subscribeToConfigChanges()
    }

    deinit { stopMonitoring() }

    // MARK: – Config-Snapshots

    private func subscribeToConfigChanges() {
        AppSettings.shared.$flight
            .sink { [weak self] _ in
                guard let self else { return }
                let snapshot = FlightConfigSnapshot.current()
                self.configLock.lock()
                self.latestFlightConfig = snapshot
                self.configLock.unlock()
            }
            .store(in: &settingsCancellables)

        AppSettings.shared.$midi
            .sink { [weak self] _ in
                guard let self else { return }
                let snapshot = MidiRuntimeConfigSnapshot.current()
                self.configLock.lock()
                self.latestMidiConfig = snapshot
                self.configLock.unlock()
            }
            .store(in: &settingsCancellables)
    }

    /// Thread-sicherer Snapshot der zuletzt vom Main-Thread-Sink gebauten
    /// Config-Werte (Runde 025 / E-05).
    private func snapshotConfig() -> (flight: FlightConfigSnapshot, midi: MidiRuntimeConfigSnapshot) {
        configLock.lock()
        defer { configLock.unlock() }
        return (latestFlightConfig, latestMidiConfig)
    }

    /// Testseam (Runde 025 / E-05, Scope C): injiziert einen deterministischen
    /// Config-Snapshot, ohne AppSettings.shared zu mutieren — belegt, dass
    /// update(...)/processSensors() ausschließlich den gecachten Snapshot
    /// verwenden, nicht live AppSettings.shared lesen.
    func setConfigForTesting(flight: FlightConfigSnapshot, midi: MidiRuntimeConfigSnapshot) {
        configLock.lock()
        latestFlightConfig = flight
        latestMidiConfig   = midi
        configLock.unlock()
    }

    // MARK: – Tastatur-Monitor

    private func startMonitoring() {
        monitorKeyDown = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            if event.keyCode == 15 {   // R → Harmonic Radar (Debug)
                DispatchQueue.main.async { self.showHarmonicRadar.toggle() }
                return nil
            }
            if event.keyCode == 46 {   // M → Audio Mixer
                DispatchQueue.main.async { self.showMixerPanel.toggle() }
                return nil
            }
            if event.keyCode == 48 {   // Tab → Settings
                DispatchQueue.main.async { self.showSettingsPanel.toggle() }
                return nil
            }
            if event.keyCode == 49 {   // Space → Autopilot
                DispatchQueue.main.async { AppSettings.shared.flight.autopilotEnabled.toggle() }
                return nil
            }
            if event.keyCode == 33 {   // [ → Energy runter
                DispatchQueue.main.async {
                    AppSettings.shared.harmony.energyLevel = max(0.0, AppSettings.shared.harmony.energyLevel - 0.1)
                }
                return nil
            }
            if event.keyCode == 30 {   // ] → Energy rauf
                DispatchQueue.main.async {
                    AppSettings.shared.harmony.energyLevel = min(1.0, AppSettings.shared.harmony.energyLevel + 0.1)
                }
                return nil
            }

            self.keysLock.lock()
            self.keysDown.insert(event.keyCode)
            self.keysLock.unlock()
            let char = event.charactersIgnoringModifiers ?? "?"
            DispatchQueue.main.async { self.debugInput = "KeyCode \(event.keyCode) [\(char)]" }
            return nil
        }
        monitorKeyUp = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self else { return event }
            self.keysLock.lock()
            self.keysDown.remove(event.keyCode)
            self.keysLock.unlock()
            return event
        }
    }

    /// Thread-sicherer Snapshot des aktuellen Tastatur-Zustands (Runde 024 / E-04).
    private func snapshotKeysDown() -> Set<UInt16> {
        keysLock.lock()
        defer { keysLock.unlock() }
        return keysDown
    }

    /// AppKit-frei testbar (Scope D) – setzt/löscht einen KeyCode ohne echtes
    /// NSEvent. Bypasst absichtlich die Sonderbehandlung einzelner Hotkeys
    /// (R/M/Tab/Space/[/]) im NSEvent-Monitor; deckt nur den reinen
    /// Tastatur→Snapshot→InputState-Pfad ab, den update(...) konsumiert.
    func setKeyDown(_ keyCode: UInt16, isDown: Bool) {
        keysLock.lock()
        if isDown { keysDown.insert(keyCode) } else { keysDown.remove(keyCode) }
        keysLock.unlock()
    }

    private func stopMonitoring() {
        if let m = monitorKeyDown { NSEvent.removeMonitor(m) }
        if let m = monitorKeyUp   { NSEvent.removeMonitor(m) }
        monitorKeyDown = nil
        monitorKeyUp   = nil
    }

    // MARK: – Maus
    //
    // mouseDragged(_:) läuft auf dem AppKit-Main-Thread (FlightSCNView-Override)
    // und mutiert seit Runde 024 / E-04 nicht mehr state.orientation direkt,
    // sondern akkumuliert nur noch in pendingMouseDeltaX/Y. Die eigentliche
    // Rotation (Quaternion body-space: erst Yaw um lokale Y, dann Pitch um
    // lokale X, keine Clamp-Grenze → Loopings möglich) passiert erst in
    // buildInputState(...), aufgerufen vom Renderloop über update(...).

    func mouseDragged(_ event: NSEvent) {
        let dx = Float(event.deltaX) * lookSensitivity
        let dy = Float(event.deltaY) * lookSensitivity
        recordMouseDelta(dx: dx, dy: dy)
    }

    /// AppKit-frei testbar (Scope D). deltaX > 0 = Maus rechts, deltaY > 0 = Maus hoch.
    func recordMouseDelta(dx: Float, dy: Float) {
        mouseLock.lock()
        pendingMouseDeltaX += dx
        pendingMouseDeltaY += dy
        mouseLock.unlock()
    }

    /// Liest die seit dem letzten Aufruf akkumulierten Maus-Deltas und setzt sie
    /// auf 0 zurück – ein Drag darf nicht über den konsumierten Frame hinaus
    /// weiterdrehen.
    private func consumeMouseDelta() -> (dx: Float, dy: Float) {
        mouseLock.lock()
        let result = (pendingMouseDeltaX, pendingMouseDeltaY)
        pendingMouseDeltaX = 0
        pendingMouseDeltaY = 0
        mouseLock.unlock()
        return result
    }

    // MARK: – Camera-Reset

    /// Setzt Position/Velocity/Orientierung zurück (Netzwerk-/World-Wechsel).
    /// Ausschließlich vom Renderloop aufzurufen (siehe SceneKitView.Coordinator) –
    /// ersetzt den vormals offenen Direktzugriff auf state von außen (Runde 024 / E-04).
    func resetForRender(position: simd_float3) {
        state.position    = position
        state.velocity    = .zero
        state.orientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    }

    // MARK: – Pro-Frame Update
    //
    // Einziger Ort, an dem state mutiert wird. Ausschließlich vom Renderloop
    // aufgerufen (SceneKitView.Coordinator.renderer(_:updateAtTime:)).
    //
    // autopilotTarget/harmonicMagnetInfluence/magnetTarget kommen aus HarmonyScene
    // (Render-Thread) als Parameter statt als von außen beschreibbare Properties –
    // siehe FlightInputSnapshot-Doku für die Trennung der beiden Magnet-Mechanismen.

    func update(deltaTime dt: Float,
                autopilotTarget: simd_float3?,
                harmonicMagnetInfluence: HarmonicMagnetInfluence?,
                magnetTarget: simd_float3?,
                autopilotNextChordName: String) {
        guard dt > 0 else { return }

        let snapshot = buildInputSnapshot(
            autopilotTarget: autopilotTarget,
            harmonicMagnetInfluence: harmonicMagnetInfluence,
            magnetTarget: magnetTarget
        )

        physics = FlightPhysics(
            thrustForce: snapshot.config.thrustForce,
            maxSpeed:    snapshot.config.maxSpeed,
            dragCoeff:   1.5
        )

        let input = buildInputState(dt: dt, snapshot: snapshot)
        physics.update(state: &state, input: input, dt: dt)

        // ── Magnetische Anziehung (manuell, post-physics) ─────────────────
        // hasPilotTranslationInput: echte Translationsabsicht (WASD/QE, Gamepad-
        // Schub). Reine Blick-/Stick-Rotation (yawDelta/pitchDelta) und Bremsen
        // zählen bewusst nicht – sonst würde der proximity-basierte Magnet die
        // Kamera schon aus dem Stillstand heraus in Bewegung setzen (Runde 007).
        let hasPilotTranslationInput = input.forward != 0 || input.strafe != 0 || input.vertical != 0
        applyMagneticForce(dt: dt, snapshot: snapshot, hasPilotTranslationInput: hasPilotTranslationInput)

        let sensors = processSensors()
        let hud = FlightHUDSnapshot(
            currentSpeed:       simd_length(state.velocity),
            autopilotNextChord: autopilotNextChordName,
            gyroRoll:           sensors.gyroRoll,
            gyroPitch:          sensors.gyroPitch,
            motionAvail:        sensors.motionAvail,
            rotationMag:        sensors.rotationMag
        )
        DispatchQueue.main.async { self.applyHUDSnapshot(hud) }
    }

    /// Wendet einen HUD-Snapshot in einem einzigen Schritt an (Main Thread,
    /// Runde 024 / E-04, Scope C) – ersetzt die vormals mehreren einzelnen
    /// DispatchQueue.main.async-Writes aus update()/processSensors().
    private func applyHUDSnapshot(_ hud: FlightHUDSnapshot) {
        currentSpeed       = hud.currentSpeed
        autopilotNextChord = hud.autopilotNextChord
        if let roll  = hud.gyroRoll  { gyroRoll  = roll }
        if let pitch = hud.gyroPitch { gyroPitch = pitch }
        motionAvail = hud.motionAvail
        rotationMag = hud.rotationMag
    }

    // MARK: – FlightInputSnapshot aufbauen

    private func buildInputSnapshot(autopilotTarget: simd_float3?,
                                     harmonicMagnetInfluence: HarmonicMagnetInfluence?,
                                     magnetTarget: simd_float3?) -> FlightInputSnapshot {
        let keys       = snapshotKeysDown()
        let mouseDelta = consumeMouseDelta()
        let ip         = inputProvider   // nil → kein Gamepad/Touch verbunden

        var snapshot = FlightInputSnapshot()

        if keys.contains(Key.w.rawValue) { snapshot.keyForward  +=  1 }
        if keys.contains(Key.s.rawValue) { snapshot.keyForward  += -1 }
        if keys.contains(Key.a.rawValue) { snapshot.keyStrafe   += -1 }
        if keys.contains(Key.d.rawValue) { snapshot.keyStrafe   +=  1 }
        if keys.contains(Key.q.rawValue) { snapshot.keyVertical +=  1 }
        if keys.contains(Key.e.rawValue) { snapshot.keyVertical += -1 }

        snapshot.mouseDeltaX = mouseDelta.dx
        snapshot.mouseDeltaY = mouseDelta.dy

        snapshot.gamepadThrustFwd = ip?.thrustFwd ?? 0
        snapshot.gamepadThrustBwd = ip?.thrustBwd ?? 0
        snapshot.gamepadLookX     = ip?.lookX     ?? 0
        snapshot.gamepadLookY     = ip?.lookY     ?? 0
        snapshot.gamepadBraking   = ip?.braking    ?? false

        snapshot.autopilotTarget         = autopilotTarget
        snapshot.harmonicMagnetInfluence = harmonicMagnetInfluence
        snapshot.magnetTarget            = magnetTarget
        snapshot.config                  = snapshotConfig().flight

        return snapshot
    }

    // MARK: – InputState aufbauen

    private func buildInputState(dt: Float, snapshot: FlightInputSnapshot) -> InputState {
        var input = InputState()
        input.braking = snapshot.gamepadBraking

        if snapshot.config.autopilotEnabled, let target = snapshot.autopilotTarget {
            // ── AUTOPILOT: body-space Lenkung zur Zielposition ───────────
            let delta = target - state.position
            let dist  = simd_length(delta)
            if dist > 1.0 {
                // Gewünschte Vorwärtsrichtung in Weltkoordinaten
                let desiredFwd = simd_normalize(delta)

                // Transformiere in body-space der aktuellen Orientierung
                let bodyDesired = simd_normalize(state.orientation.inverse.act(desiredFwd))

                // Winkel-Fehler in body-space (kleine Winkel, atan2 stabil)
                let yawErr   = atan2( bodyDesired.x, -bodyDesired.z)
                let hLen     = sqrt(bodyDesired.x * bodyDesired.x + bodyDesired.z * bodyDesired.z)
                let pitchErr = atan2( bodyDesired.y, hLen)

                let turnRate: Float = 1.2
                input.yawDelta   = -yawErr   * min(1.0, turnRate * dt)
                input.pitchDelta =  pitchErr * min(1.0, turnRate * dt)
                input.forward    = snapshot.config.autopilotSpeed
            }
        } else {
            // ── MANUELL: Tastatur ─────────────────────────────────────────
            input.forward  += snapshot.keyForward
            input.strafe   += snapshot.keyStrafe
            input.vertical += snapshot.keyVertical

            // ── Gamepad Schub (via InputProvider) ─────────────────────────
            if snapshot.gamepadThrustFwd > 0 { input.forward +=  snapshot.gamepadThrustFwd }
            if snapshot.gamepadThrustBwd > 0 { input.forward += -snapshot.gamepadThrustBwd }

            // ── Gamepad Blickrichtung (rechter Stick) ─────────────────────
            if snapshot.gamepadLookX != 0 || snapshot.gamepadLookY != 0 {
                let pitchSign: Float = snapshot.config.invertPitch ? 1 : -1
                input.yawDelta   -= snapshot.gamepadLookX * snapshot.config.gamepadYawSensitivity   * dt
                input.pitchDelta += pitchSign * snapshot.gamepadLookY * snapshot.config.gamepadPitchSensitivity * dt
            }
        }

        // ── Maus-Look: additiv, unabhängig von Autopilot/Manuell ───────────
        // Identisch zur alten mouseDragged-Semantik, die unabhängig vom
        // Flugmodus feuerte (Runde 024 / E-04: nur die Anwendung ist jetzt
        // hier statt im Main-Thread-Callback).
        input.yawDelta   += -snapshot.mouseDeltaX
        input.pitchDelta +=  snapshot.mouseDeltaY

        return input
    }

    // MARK: – Magnetische Anziehung
    //
    // Weiche Anziehung zum nächsten sichtbaren Akkord.
    // Nur im manuellen Modus, nicht bei Autopilot.
    // Kraft ∝ (1 - dist/radius)² → keine abrupten Sprünge an der Grenze.

    private func applyMagneticForce(dt: Float, snapshot: FlightInputSnapshot, hasPilotTranslationInput: Bool) {
        guard !snapshot.config.autopilotEnabled else { return }

        // ── Harmonische Richtungskorrektur (RuntimeHarmonik-Entscheidung) ─────
        // Zeitbasiertes Blending der Bewegungsrichtung → keine zusätzliche Kraft,
        // keine Geschwindigkeitsänderung. Spielerinput bleibt dominant (Pilot-Override,
        // siehe Phase 4.2) – alpha < 1 lässt gegenläufiges Steuern jederzeit zu.
        // Nur aktiv bei Bewegung (speed > 0.5), damit Normalisierung stabil bleibt.
        // Effektive Rate/Winkelgeschwindigkeit = Base × HarmonicMagnetInfluence-Multiplikatoren,
        // konservativ geklammert (Phase 4.2a) — ohne magnetProfile (rateMultiplier/
        // maxAngularSpeedMultiplier ≈ 1.0) verhält sich das nahezu wie der vorherige,
        // konstante v1-Wert.
        //
        // Runde 021 / E-02: isEnabled schaltet die Korrektur komplett ab (kein Floor-Clamp-
        // Risiko wie bei einer Rate-Multiplikator-Nullung, siehe Kommentar unten). effectiveRange/
        // falloff wirken als zusätzlicher Alpha-Faktor NACH der Winkelgeschwindigkeits-Klammer —
        // weich, kein harter Kraftrand. intensity ebenso als finaler Alpha-Faktor, NICHT in
        // rateMultiplier gebacken: harmonicMagnetRateMin (3.0) ist ein Floor auf die Rate-Konstante,
        // ein bei intensity=0 auf 0 gehender rateMultiplier würde durch diesen Floor trotzdem eine
        // spürbare Rate ergeben. Die finale Alpha-Multiplikation umgeht das korrekt bis auf 0.
        if let influence = snapshot.harmonicMagnetInfluence, influence.isEnabled {
            let speed = simd_length(state.velocity)
            if speed > 0.5 {
                let toTarget       = influence.target - state.position
                let toTargetLength = simd_length(toTarget)
                if toTargetLength > 1e-4 {
                    let falloff = HarmonicMagnetConfig.falloff(distance: toTargetLength, range: influence.effectiveRange)
                    if falloff > 0 {
                        let targetDir  = toTarget / toTargetLength
                        let currentDir = state.velocity / speed

                        // Winkel zwischen aktueller und Zielrichtung, für die
                        // Winkelgeschwindigkeits-Obergrenze.
                        let cosAngle = max(-1.0, min(1.0, simd_dot(currentDir, targetDir)))
                        let angle    = acos(cosAngle)

                        let rate = min(max(harmonicMagnetRateBase * influence.rateMultiplier,
                                            harmonicMagnetRateMin), harmonicMagnetRateMax)
                        let maxAngularSpeed = min(max(harmonicMagnetMaxAngularSpeedBase * influence.maxAngularSpeedMultiplier,
                                                       harmonicMagnetAngularSpeedMin), harmonicMagnetAngularSpeedMax)

                        var alpha = 1 - exp(-rate * dt)
                        if angle > 1e-5 {
                            alpha = min(alpha, (maxAngularSpeed * dt) / angle)
                        }
                        alpha *= falloff * influence.intensity

                        let blendedDir    = currentDir * (1 - alpha) + targetDir * alpha
                        let blendedLength = simd_length(blendedDir)
                        if blendedLength > 1e-4 {
                            state.velocity = (blendedDir / blendedLength) * speed
                        }
                    }
                }
            }
        }

        // ── Proximity-basiertes Magnet-Ziel (nächster sichtbarer Akkord) ──────
        // Nur bei echter Pilot-Translationsbewegung wirksam – sonst würde der
        // passive Magnet die Kamera im Stillstand selbst in Bewegung setzen und
        // ungewollt triggersArmed scharf schalten, ohne dass der Spieler geflogen
        // ist (Runde 007 / 3.9.1d-Akzeptanzkriterium "App-Start löst nicht aus").
        guard hasPilotTranslationInput else { return }
        guard let target = snapshot.magnetTarget else { return }
        let strength = snapshot.config.magnetStrength
        guard strength > 0 else { return }

        let delta  = target - state.position
        let dist   = simd_length(delta)
        let radius = snapshot.config.magnetRadius
        guard dist < radius, dist > 2.0 else { return }

        let t         = 1.0 - (dist / radius)          // 0 an Grenze, 1 im Zentrum
        let forceMag  = strength * t * t * 120.0        // Tuning-Konstante
        let forceDir  = simd_normalize(delta)
        // Velocity-Nudge: wird nächsten Frame gedämpft → weich und selbst-limitierend
        state.velocity += forceDir * forceMag * dt
    }

    // MARK: – Sensoren → MIDI CC + HUD

    /// gyroRoll/gyroPitch sind nil, wenn motionGravity diesen Frame nicht verfügbar
    /// ist (siehe FlightHUDSnapshot-Doku) – MIDI-CC-Versand bleibt unverändert ein
    /// Seiteneffekt dieser Methode, nur die HUD-Werte werden jetzt zurückgegeben
    /// statt einzeln dispatcht (Runde 024 / E-04, Scope C). Liest seit Runde 025 /
    /// E-05 den gelockten MidiRuntimeConfigSnapshot statt AppSettings.shared live
    /// vom Render-Thread.
    private func processSensors() -> (gyroRoll: Float?, gyroPitch: Float?, motionAvail: Bool, rotationMag: Float) {
        let gp = GamepadController.shared
        let midiConfig = snapshotConfig().midi
        let sens = midiConfig.gyroSensitivity

        var gyroRoll:  Float? = nil
        var gyroPitch: Float? = nil

        if let g = gp.motionGravity {
            let roll  = max(-1.0, min(1.0, g.x * sens))
            let pitch = max(-1.0, min(1.0, g.y * sens))
            gyroRoll  = roll
            gyroPitch = pitch
            if midiConfig.sensorEnabled && midiConfig.gyroEnabled {
                let rollCC  = max(0, min(127, Int((roll  + 1.0) / 2.0 * 127.0)))
                let pitchCC = max(0, min(127, Int((pitch + 1.0) / 2.0 * 127.0)))
                MIDIManager.shared.sendCC(channel: midiConfig.sensorMidiChannel, cc: midiConfig.gyroRollCC,  value: rollCC)
                MIDIManager.shared.sendCC(channel: midiConfig.sensorMidiChannel, cc: midiConfig.gyroPitchCC, value: pitchCC)
            }
        }

        let motAvail = gp.motionAvailable
        let rotMag   = gp.motionRotationMagnitude ?? 0
        if midiConfig.sensorEnabled && midiConfig.rotationEnabled && motAvail {
            let cc = max(0, min(127, Int(rotMag * 127.0)))
            MIDIManager.shared.sendCC(channel: midiConfig.sensorMidiChannel, cc: midiConfig.rotationCC, value: cc)
        }

        return (gyroRoll, gyroPitch, motAvail, rotMag)
    }
}
