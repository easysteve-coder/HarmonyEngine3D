import SwiftUI
import SceneKit
import HarmonyShared
import HarmonyAudioCore   // AudioCoreMacroID — nur zur Benennung der vier Makros (W-05)

// MARK: – App-Version (hier zentral pflegen)
let appVersion = "3.8.2"

// MARK: – Haupt-View

struct ContentView: View {

    // Alle langlebigen Objekte kommen vom AppModel (App Entry Point).
    // ContentView besitzt nichts davon – es beobachtet nur.
    @ObservedObject var flightController:   FlightController
    @ObservedObject var targetingModel:     TargetingOverlayModel
    @ObservedObject private var settings = AppSettings.shared

    let scene:         HarmonyScene
    let stopAllAction: () -> Void
    let worldInfo:     RuntimeWorldInfo   // 3.9.2: welche Welt ist tatsächlich aktiv

    // MIDI-Eingang (Runde 073 / W-04): ausschließlich für die Quellenauswahl
    // in den Einstellungen — Geräteliste und Verbindungszustand. ContentView
    // bekommt dadurch weiterhin keinen AudioOutput zu sehen.
    let midiInput:     MIDIInputManager

    init(scene: HarmonyScene,
         flightController: FlightController,
         targetingModel: TargetingOverlayModel,
         stopAllAction: @escaping () -> Void,
         worldInfo: RuntimeWorldInfo,
         midiInput: MIDIInputManager) {
        self.scene                = scene
        self._flightController    = ObservedObject(wrappedValue: flightController)
        self._targetingModel      = ObservedObject(wrappedValue: targetingModel)
        self._settings            = ObservedObject(wrappedValue: AppSettings.shared)
        self.stopAllAction        = stopAllAction
        self.worldInfo            = worldInfo
        self.midiInput            = midiInput
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            SceneKitView(scene: scene, flightController: flightController, targetingModel: targetingModel)
                .ignoresSafeArea()

            // Lock-On Targeting Overlay
            TargetingOverlayView(model: targetingModel)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Top: Akkord + Stick-Karte + Approach-Radar (mit dunklem Hintergrund)
            VStack {
                topDisplay
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(red:0.02,green:0.02,blue:0.10,opacity:0.72))
                            .overlay(RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.07), lineWidth: 1))
                    )
                    .padding(.top, 28)
                Spacer()
            }

            // Bottom: Dashboard + Cockpit-Panel (am unteren Bildrand) + Settings
            VStack(spacing: 0) {
                Spacer()
                HStack(alignment: .bottom, spacing: 0) {
                    bottomDashboard
                    Spacer()
                    if flightController.showSettingsPanel {
                        SettingsPanel(midiInput: midiInput,
                                      onClose: { flightController.showSettingsPanel = false })
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                            .padding(.bottom, 16)
                    }
                }
                if flightController.showCockpitPanel {
                    CockpitControlPanel(
                        stopAllAction: stopAllAction,
                        onClose: { flightController.showCockpitPanel = false }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: flightController.showCockpitPanel)
            .animation(.easeInOut(duration: 0.25), value: flightController.showSettingsPanel)

            // Audio Mixer Panel (M-Taste) – zIndex 50
            if flightController.showMixerPanel {
                VStack(spacing: 0) {
                    Spacer()
                    AudioMixerPanel(onClose: { flightController.showMixerPanel = false })
                        .padding(.bottom, 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(50)
            }

            // Steuerungsübersicht (OPTIONS-Taste) – muss im ZStack sein damit zIndex greift
            if flightController.showControlsOverlay {
                ControlsOverlay(onDismiss: { flightController.showControlsOverlay = false })
                    .transition(.opacity)
                    .zIndex(100)
            }

        }
        .background(Color.black)
        .animation(.easeInOut(duration: 0.25), value: flightController.showMixerPanel)
        .animation(.easeInOut(duration: 0.20), value: flightController.showControlsOverlay)
    }

    // MARK: – Top Center: Akkord-Info + Left-Stick-Karte + Approach-Radar

    private var topDisplay: some View {
        VStack(spacing: 10) {

            // Akkordname:
            // – Sichtbar solange mappingChord gesetzt (= gültige CH3-Quelle vorhanden).
            // – Volle Helligkeit wenn Akkord gerade klingt (soundingChordName != "").
            // – Gedimmt wenn Akkord nicht mehr klingt, aber noch Mapping-Quelle ist.
            let isSounding = !flightController.soundingChordName.isEmpty
            if let mapping = flightController.mappingChord {
                Text(verbatim: mapping.name)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(isSounding ? 1.0 : 0.35))
                    .shadow(color: .white.opacity(isSounding ? 0.5 : 0.10), radius: 18)
                    .transition(.opacity.combined(with: .scale))
                    .animation(.easeInOut(duration: 0.25), value: mapping.name)
                    .animation(.easeInOut(duration: 0.20), value: isSounding)
            }

            // Autopilot-Ziel: nächster Akkord
            let apNext = flightController.autopilotNextChord
            if settings.flight.autopilotEnabled && !apNext.isEmpty {
                HStack(spacing: 5) {
                    Text("✈", bundle: .module)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.45))
                    Text(apNext)
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: apNext)
            }

            // Linker Stick: Richtungs-Karte mit Tönen
            leftStickMap

            // Annäherungs-Radar (3 Indikatoren)
            approachRadar.padding(.top, 4)
        }
    }

    // ── Linker Stick: Kreuz-Layout mit Tönen + Live-Richtungs-Highlight ──

    private var leftStickMap: some View {
        // Chord-Tones aus dem atomaren ChordMapping (Name + Töne immer konsistent).
        let mapping  = flightController.mappingChord
        let tones    = mapping?.tones ?? []
        let t0       = tones.count > 0 ? tones[0] : ""
        let t1       = tones.count > 1 ? tones[1] : ""
        let t2       = tones.count > 2 ? tones[2] : ""
        let t3       = tones.count > 3 ? tones[3] : ""
        let active   = mapping != nil
        let sector   = flightController.leftStickSector   // nil = Mitte
        let octaveUp = flightController.stickOctaveUp     // L3 gedrückt

        return VStack(spacing: 2) {
            // +8va Badge (erscheint wenn L3 gedrückt)
            if octaveUp {
                Text("+8va", bundle: .module)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(stickColor)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4)
                        .fill(stickColor.opacity(0.18))
                        .overlay(RoundedRectangle(cornerRadius: 4)
                            .stroke(stickColor.opacity(0.45), lineWidth: 1)))
                    .shadow(color: stickColor.opacity(0.6), radius: 6)
                    .transition(.opacity.combined(with: .scale))
            }
            // ↑ Sektor 0 = Root
            stickTone("↑", t0, lit: sector == 0)
            HStack(spacing: 24) {
                // ← Sektor 3 = Septime
                stickTone("←", t3, lit: sector == 3)

                // Mittelpunkt – leuchtet lila wenn Stick aktiv
                ZStack {
                    Circle()
                        .fill(sector != nil ? stickColor.opacity(0.80) : Color.white.opacity(0.10))
                        .frame(width: 10, height: 10)
                    if sector != nil {
                        Circle()
                            .fill(stickColor.opacity(0.30))
                            .frame(width: 18, height: 18)
                    }
                }
                .shadow(color: sector != nil ? stickColor.opacity(0.9) : .clear, radius: 5)
                .animation(.easeInOut(duration: 0.08), value: sector != nil)

                // → Sektor 1 = Terz
                stickTone("→", t1, lit: sector == 1)
            }
            // ↓ Sektor 2 = Quinte
            stickTone("↓", t2, lit: sector == 2)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.65))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(sector != nil
                            ? stickColor.opacity(0.30)
                            : Color.white.opacity(0.08),
                            lineWidth: 1))
        )
        .opacity(active ? 1 : 0)
        .animation(.easeInOut(duration: 0.08), value: sector)
        .animation(.easeInOut(duration: 0.12), value: octaveUp)
        .animation(.easeInOut(duration: 0.25), value: active)
    }

    private func stickTone(_ arrow: String, _ note: String, lit: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(arrow)
                .font(.system(size: lit ? 14 : 11,
                              weight: lit ? .bold : .light))
                .foregroundColor(lit ? stickColor : .white.opacity(0.35))
                .shadow(color: lit ? stickColor.opacity(0.9) : .clear, radius: 5)
            Text(note.isEmpty ? "–" : note)
                .font(.system(size: lit ? 22 : 18,
                              weight: .semibold, design: .rounded))
                .foregroundColor(lit ? .white : .white.opacity(0.78))
                .shadow(color: lit ? stickColor.opacity(0.5) : .clear, radius: 8)
        }
        .frame(minWidth: 60)
        .animation(.easeInOut(duration: 0.08), value: lit)
    }

    // ── Approach-Radar ────────────────────────────────────────────────────

    private var approachRadar: some View {
        HStack(spacing: 20) {
            approachIndicator(icon: "⬡",
                              label: flightController.approachChordLabel,
                              prox:  flightController.approachChordProx,
                              color: chordColor)
            approachIndicator(icon: "◎",
                              label: flightController.approachBassLabel,
                              prox:  flightController.approachBassProx,
                              color: bassColor)
            approachIndicator(icon: "✦",
                              label: "Melodie",
                              prox:  flightController.approachMelodyProx,
                              color: melodyColor)
        }
    }

    private func approachIndicator(icon: String, label: String,
                                   prox: Float, color: Color) -> some View {
        let opa = prox > 0.04 ? Double(prox) * 0.85 + 0.15 : 0.0
        return HStack(spacing: 6) {
            Text(icon).font(.system(size: 14))
            if !label.isEmpty {
                Text(label).font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Float(i) / 4.0 < prox ? color : Color.white.opacity(0.15))
                        .frame(width: 7, height: 11)
                }
            }
        }
        .foregroundColor(color)
        .opacity(opa)
        .animation(.easeInOut(duration: 0.18), value: prox)
    }


    // MARK: – Dashboard (Spaceship-Cockpit)

    private var bottomDashboard: some View {
        HStack(alignment: .center, spacing: 0) {

            // ── Speed-Instrument + Autopilot-Status ──────────────────────
            VStack(spacing: 4) {
                SpeedGauge(speed: flightController.currentSpeed,
                           maxSpeed: Float(settings.flight.maxSpeed))
                // Autopilot-Badge
                if settings.flight.autopilotEnabled {
                    Text("✈ AUTO", bundle: .module)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.3, green: 1.0, blue: 0.6))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color(red: 0.3, green: 1.0, blue: 0.6).opacity(0.15))
                        .cornerRadius(3)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 14)
            .animation(.easeInOut(duration: 0.3), value: settings.flight.autopilotEnabled)

            dashLine

            // ── MIDI-Kanäle ───────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 11) {
                midiRow(flightController.ch0Active, color: chordColor,
                        label: flightController.mappingChord.map { LocalizedStringKey($0.name) }
                            ?? "hud.chords")
                midiRow(flightController.ch1Active, color: bassColor,
                        label: "Bass  ·  \(settings.midi.bassHoldMode ? "Hold" : "Trigger")")
                midiRow(flightController.ch2Active, color: melodyColor,
                        label: "hud.melody")
                midiRow(flightController.ch3Active, color: stickColor,
                        label: "hud.chord.tones")
            }
            .padding(.horizontal, 20)

            dashLine

            // ── Preset + Hint ─────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("hud.melody.preset", bundle: .module)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                        .tracking(1.5)
                    HStack(spacing: 8) {
                        Text("L1 · R1", bundle: .module)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.28))
                        Text(flightController.melodyPresetName)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(melodyColor)
                            .animation(.easeInOut(duration: 0.2),
                                       value: flightController.melodyPresetName)
                    }
                }

                HStack(spacing: 10) {
                    // ◈ HARMONY CONTROL Panel
                    Button {
                        flightController.showCockpitPanel.toggle()
                    } label: {
                        HStack(spacing: 5) {
                            Text("◈", bundle: .module)
                            Text("HARMONY", bundle: .module)
                        }
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(flightController.showCockpitPanel
                                         ? Color(red: 1.0, green: 0.72, blue: 0.1)
                                         : .white.opacity(0.28))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(flightController.showCockpitPanel
                                      ? Color(red: 1.0, green: 0.72, blue: 0.1).opacity(0.15)
                                      : Color.white.opacity(0.05))
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        flightController.showSettingsPanel.toggle()
                    } label: {
                        HStack(spacing: 5) {
                            Text("Tab", bundle: .module)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.20))
                            Text("⚙", bundle: .module)
                                .font(.system(size: 14))
                                .foregroundColor(flightController.showSettingsPanel
                                                 ? .white.opacity(0.7) : .white.opacity(0.22))
                        }
                    }
                    .buttonStyle(.plain)
                }

                // Aktive Welt + Version (3.9.2: an worldInfo statt hart an NetworkParser gekoppelt)
                worldStatusLine
            }
            .padding(.horizontal, 18)

            dashLine

            // ── Sensor-Panel (Gyro + Touchpad + Rotation) ────────────────
            SensorPanel(
                roll:        flightController.gyroRoll,
                pitch:       flightController.gyroPitch,
                rotationMag: flightController.rotationMag,
                touchpadX:   flightController.touchpadX,
                touchpadY:   flightController.touchpadY,
                motionAvail: flightController.motionAvail,
                active:      settings.midi.sensorEnabled
            )
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.03, green: 0.04, blue: 0.14, opacity: 0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.6), radius: 20, y: 4)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    private var dashLine: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(width: 1, height: 90)
    }

    // ── Welt-Status (3.9.2: Modus-Wahrheit; Runde 023 / E-03: Layer sichtbar) ──
    // Explore: aktives NetworkParser-Netz (reagiert live auf Settings-Wechsel).
    // HarmonyWeb (worldInfo.kind == .mapPreview, Enum-Fallname unverändert —
    // siehe RuntimeWorldInfo-Doku in HarmonyEngine3DApp.swift): fester Map-Name
    // + Layer aus AppModel – ändert sich nicht zur Laufzeit.
    private var worldStatusLine: some View {
        Group {
            switch worldInfo.kind {
            case .explore:
                let netDef = NetworkParser.definitions[min(settings.harmony.networkIndex,
                                                           NetworkParser.definitions.count - 1)]
                Text("\(netDef.emoji) \(netDef.name)  ·  Explore  ·  v\(appVersion)", bundle: .module)
            case .mapPreview:
                Text("\(worldInfo.emoji) \(worldInfo.displayName)  ·  HarmonyWeb (\(worldInfo.layer ?? "–"))  ·  v\(appVersion)", bundle: .module)
            }
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .foregroundColor(.white.opacity(0.22))
        .tracking(0.8)
    }

    // Farben
    private var chordColor:  Color { .init(nsColor: .init(calibratedRed: 0.4,  green: 0.8,  blue: 1.0,  alpha: 1)) }
    private var bassColor:   Color { .init(nsColor: .init(calibratedRed: 1.0,  green: 0.55, blue: 0.1,  alpha: 1)) }
    private var melodyColor: Color { .init(nsColor: .init(calibratedRed: 0.1,  green: 0.85, blue: 0.9,  alpha: 1)) }
    private var stickColor:  Color { .init(nsColor: .init(calibratedRed: 0.85, green: 0.4,  blue: 1.0,  alpha: 1)) }

    // label: LocalizedStringKey — Keys werden in Localizable.strings aufgelöst.
    // Dynamische Werte (Akkordnamen wie "Cmaj7") sind keine Keys → Fallback auf Literal.
    private func midiRow(_ active: Bool, color: Color, label: LocalizedStringKey) -> some View {
        HStack(spacing: 11) {
            Circle()
                .fill(active ? color : Color.white.opacity(0.10))
                .frame(width: 14, height: 14)
                .shadow(color: active ? color.opacity(0.8) : .clear, radius: 6)
                .animation(.easeInOut(duration: 0.08), value: active)
            Text(label, bundle: .module)
                .font(.system(size: 17, weight: active ? .bold : .regular, design: .monospaced))
                .foregroundColor(active ? color : .white.opacity(0.35))
                .animation(.easeInOut(duration: 0.08), value: active)
        }
    }
}

// MARK: – Gyro-Tilt-Indikator (Bubble-Level-Stil)

// MARK: – Sensor-Panel (Gyro-Bubble + Touchpad + Rotationsrate)

struct SensorPanel: View {
    let roll:        Float   // gravity.x  -1…+1
    let pitch:       Float   // gravity.y  -1…+1
    let rotationMag: Float   // 0…1
    let touchpadX:   Float   // -1…+1
    let touchpadY:   Float   // -1…+1
    let motionAvail: Bool    // false → Sensor-HW nicht gefunden
    let active:      Bool    // Sensor-Master-Switch

    private var teal:   Color { Color(red: 0.1,  green: 0.85, blue: 0.9) }
    private var orange: Color { Color(red: 1.0,  green: 0.55, blue: 0.05) }
    private var dim:    Color { Color.white.opacity(0.14) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            // ── Zeile 1: Gyro-Bubble + Touchpad nebeneinander ─────────────
            HStack(spacing: 10) {
                gyroBubble
                touchpadDisplay
            }

            // ── Zeile 2: Rotationsrate-Balken ─────────────────────────────
            rotationBar
        }
    }

    // ── Gyro-Libelle (52×52) ─────────────────────────────────────────────
    private var gyroBubble: some View {
        let size:   CGFloat = 46
        let travel: CGFloat = 14
        let dotR:   CGFloat = 5.0
        let hasHW = motionAvail
        let color  = active && hasHW ? teal : dim

        return VStack(spacing: 3) {
            ZStack {
                Circle().fill(Color.black.opacity(0.55)).frame(width: size, height: size)
                Circle().stroke(color.opacity(0.55), lineWidth: 1.5).frame(width: size, height: size)
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 1)
                    .frame(width: dotR * 4, height: dotR * 4)
                Rectangle().fill(Color.white.opacity(0.07)).frame(width: size - 8, height: 0.5)
                Rectangle().fill(Color.white.opacity(0.07)).frame(width: 0.5, height: size - 8)

                let dx =  CGFloat(roll)  * travel
                let dy = -CGFloat(pitch) * travel
                Circle()
                    .fill(active && hasHW ? teal : Color.white.opacity(0.22))
                    .frame(width: dotR * 2, height: dotR * 2)
                    .shadow(color: active && hasHW ? teal.opacity(0.9) : .clear, radius: 4)
                    .offset(x: dx, y: dy)
                    .animation(.easeOut(duration: 0.06), value: roll)
                    .animation(.easeOut(duration: 0.06), value: pitch)

                // Kein-Sensor-Overlay
                if !hasHW {
                    Text("USB?", bundle: .module)
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.orange.opacity(0.70))
                }
            }
            Text("TILT", bundle: .module)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(color.opacity(0.7)).tracking(1.2)
        }
    }

    // ── Touchpad-Miniatur (querformat wie DualSense-Touchpad ~16:9) ──────
    private var touchpadDisplay: some View {
        let w: CGFloat = 62   // breiter als hoch – wie das physische Touchpad
        let h: CGFloat = 38
        let dotR: CGFloat = 4.0
        let tX = CGFloat(touchpadX) * (w / 2 - dotR - 2)
        let tY = -CGFloat(touchpadY) * (h / 2 - dotR - 2)
        let color = active ? orange : dim

        return VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.black.opacity(0.55))
                    .frame(width: w, height: h)
                RoundedRectangle(cornerRadius: 5)
                    .stroke(color.opacity(0.50), lineWidth: 1.2)
                    .frame(width: w, height: h)
                // Mittelkreuz
                Rectangle().fill(Color.white.opacity(0.07)).frame(width: w - 6, height: 0.5)
                Rectangle().fill(Color.white.opacity(0.07)).frame(width: 0.5, height: h - 6)
                // Dot
                Circle()
                    .fill(active ? orange : Color.white.opacity(0.22))
                    .frame(width: dotR * 2, height: dotR * 2)
                    .shadow(color: active ? orange.opacity(0.8) : .clear, radius: 3)
                    .offset(x: tX, y: tY)
                    .animation(.easeOut(duration: 0.05), value: touchpadX)
                    .animation(.easeOut(duration: 0.05), value: touchpadY)
            }
            Text("PAD", bundle: .module)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(color.opacity(0.7)).tracking(1.2)
        }
    }

    // ── Rotationsrate-Balken ──────────────────────────────────────────────
    private var rotationBar: some View {
        let totalW: CGFloat = 114  // Gesamtbreite: Gyro(46) + gap(10) + Pad(62) = 118 ≈ 114
        let color = active && motionAvail ? teal : dim

        return VStack(alignment: .leading, spacing: 2) {
            Text("ROT", bundle: .module)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(color.opacity(0.7)).tracking(1.2)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: totalW, height: 5)
                RoundedRectangle(cornerRadius: 2)
                    .fill(active && motionAvail ? teal.opacity(0.75) : dim.opacity(0.4))
                    .frame(width: max(2, CGFloat(rotationMag) * totalW), height: 5)
                    .animation(.easeOut(duration: 0.08), value: rotationMag)
            }
        }
    }
}

// MARK: – Tachometer

struct SpeedGauge: View {
    let speed: Float
    let maxSpeed: Float

    private var fraction: Double {
        Double(min(1.0, max(0, speed / max(1, maxSpeed))))
    }

    var body: some View {
        ZStack {
            // Hintergrund-Bogen 270°
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color.white.opacity(0.06),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(135))

            // Tick-Marks
            ForEach(0..<6, id: \.self) { i in
                let angle = 135.0 + Double(i) * 54.0
                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 1.5, height: 6)
                    .offset(y: -46)
                    .rotationEffect(.degrees(angle))
            }

            // Geschwindigkeits-Bogen
            Circle()
                .trim(from: 0, to: fraction * 0.75)
                .stroke(gaugeColor,
                        style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(135))
                .shadow(color: gaugeColor.opacity(0.6), radius: 8)
                .animation(.easeOut(duration: 0.10), value: fraction)

            // Zahl + Label
            VStack(spacing: 0) {
                Text("\(Int(speed))", bundle: .module)
                    .font(.system(size: 46, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .shadow(color: gaugeColor.opacity(0.7), radius: 10)
                Text("SPEED", bundle: .module)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.28))
                    .tracking(2.5)
            }
        }
        .frame(width: 148, height: 148)
    }

    private var gaugeColor: Color {
        if fraction < 0.50 { return Color(red: 0.20, green: 0.90, blue: 0.55) }
        if fraction < 0.80 { return Color(red: 1.00, green: 0.80, blue: 0.10) }
        return Color(red: 1.00, green: 0.35, blue: 0.10)
    }
}

// MARK: – Settings-Panel

// MARK: – Cockpit Control Panel (Harmonik-Steuerung)

struct CockpitControlPanel: View {
    let stopAllAction: () -> Void
    var onClose: () -> Void = {}
    @ObservedObject private var s = AppSettings.shared

    private let amber  = Color(red:1.0, green:0.72, blue:0.10)
    private let green  = Color(red:0.2,  green:1.0,  blue:0.5)
    private let orange = Color(red:1.0,  green:0.55, blue:0.1)
    private let purple = Color(red:0.8,  green:0.4,  blue:1.0)
    private let red    = Color(red:1.0,  green:0.25, blue:0.25)
    private let teal   = Color(red:0.1,  green:0.85, blue:0.9)
    private let keyNames = ["ALL","C","Db","D","Eb","E","F","F#","G","Ab","A","Bb","B"]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {

                // ── KEY CENTER ────────────────────────────────────────────
                cpSection("KEY CENTER") {
                    HStack(spacing: 5) {
                        ForEach(0..<keyNames.count, id: \.self) { i in
                            let sel = s.harmony.keyCenter == i - 1
                            Button(keyNames[i]) { s.harmony.keyCenter = i - 1 }
                                .font(.system(size: 12, weight: sel ? .bold : .regular,
                                              design: .monospaced))
                                .foregroundColor(sel ? .black : .white.opacity(0.60))
                                .padding(.horizontal, 7).padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 5)
                                    .fill(sel ? amber : Color.white.opacity(0.08)))
                                .buttonStyle(.plain)
                        }
                    }
                }

                cpDivider()

                // ── CHORD TYPES ───────────────────────────────────────────
                cpSection("CHORD TYPES") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 14) {
                            cpLED("△7",   isOn: $s.harmony.enableMaj7, color: green)
                            cpLED("m7",   isOn: $s.harmony.enableM7,   color: green)
                            cpLED("7",    isOn: $s.harmony.enableDom7,  color: orange)
                            cpLED("ø7",   isOn: $s.harmony.enableM7b5,  color: purple)
                            cpLED("dim7", isOn: $s.harmony.enableDim7,  color: red)
                        }
                        HStack(spacing: 14) {
                            cpLED("△9",   isOn: $s.harmony.enableMaj9, color: green)
                            cpLED("9",    isOn: $s.harmony.enable9,     color: orange)
                            cpLED("m9",   isOn: $s.harmony.enableM9,    color: green)
                            cpLED("sus4", isOn: $s.harmony.enableSus4,  color: teal)
                            cpLED("6",    isOn: $s.harmony.enable6,     color: green)
                        }
                    }
                }

                cpDivider()

                // ── TRANSPOSITION ─────────────────────────────────────────
                cpSection("TRANSP.") {
                    HStack(spacing: 20) {
                        cpOctave("CHORD", value: $s.midi.chordOctaveShift, range: -2...2)
                        cpOctave("BASS",  value: $s.midi.bassOctaveShift,  range: -2...2)
                    }
                }

                cpDivider()

                // ── BASS MODE ─────────────────────────────────────────────
                cpSection("BASS") {
                    cpLED("HOLD", isOn: $s.midi.bassHoldMode, color: orange)
                }

                Spacer(minLength: 20)

                // ── ALL NOTES OFF (△-Taste) ───────────────────────────────
                VStack(alignment: .center, spacing: 4) {
                    Text("△  TASTE", bundle: .module)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.30))
                        .tracking(1)
                    Button {
                        stopAllAction()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.fill").font(.system(size: 11))
                            Text("ALL NOTES OFF", bundle: .module)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(red)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(red.opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(red.opacity(0.40), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)

                // ── CLOSE ─────────────────────────────────────────────────
                Button { onClose() } label: {
                    Text("✕", bundle: .module)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)
                .padding(.top, 8)
            }
            .padding(.vertical, 12)
        }
        .background(Color(red:0.04, green:0.05, blue:0.12, opacity:0.97))
        .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.12)),
                 alignment: .top)
    }

    // ── Section-Wrapper ───────────────────────────────────────────────────
    @ViewBuilder
    private func cpSection<C: View>(_ label: LocalizedStringKey, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label, bundle: .module)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(amber.opacity(0.70))
                .tracking(1.4)
            content()
        }
        .padding(.horizontal, 14)
    }

    private func cpDivider() -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.09))
            .frame(width: 1, height: 52)
            .padding(.top, 20)
    }

    // ── LED-Toggle ────────────────────────────────────────────────────────
    @ViewBuilder
    private func cpLED(_ label: String, isOn: Binding<Bool>, color: Color) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(isOn.wrappedValue ? color : Color.white.opacity(0.10))
                    .frame(width: 12, height: 12)
                    .shadow(color: isOn.wrappedValue ? color.opacity(0.9) : .clear, radius: 5)
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(isOn.wrappedValue ? .white : .white.opacity(0.28))
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.10), value: isOn.wrappedValue)
    }

    // ── Oktav-Regler (+/−) ────────────────────────────────────────────────
    @ViewBuilder
    private func cpOctave(_ label: String, value: Binding<Int>,
                           range: ClosedRange<Int>) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.40))
            HStack(spacing: 6) {
                Button("−") { value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1) }
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.65))
                    .buttonStyle(.plain)
                Text(value.wrappedValue == 0 ? " 0"
                     : value.wrappedValue > 0 ? "+\(value.wrappedValue)"
                                              : "\(value.wrappedValue)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(value.wrappedValue == 0
                                     ? .white.opacity(0.35)
                                     : Color(red:0.3,green:1.0,blue:0.55))
                    .frame(width: 24)
                Button("+") { value.wrappedValue = min(range.upperBound, value.wrappedValue + 1) }
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.65))
                    .buttonStyle(.plain)
            }
        }
    }
}

// MARK: – Settings Panel

struct SettingsPanel: View {
    @ObservedObject var midiInput: MIDIInputManager
    var onClose: () -> Void = {}
    @ObservedObject private var s = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                HStack {
                    Text("settings.title", bundle: .module)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Spacer()
                    Button("✕") { onClose() }
                        .buttonStyle(.plain)
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 17))
                }
                .padding(.bottom, 14)

                // Runde 023 / E-03: Runtime-Weltwahl (Explore/HarmonyWeb) — getrennt vom
                // Explore-Netzwerk-Picker unten. Default bleibt Explore (Stephan-Entscheidung
                // Option A). Wirkt erst nach dem nächsten App-Start (kein Live-Rebuild in
                // diesem Slice, siehe HarmonyEngine3DApp.effectiveHarmonyWebRequest()).
                // Runde 040 / V-01: zusätzlich importierte Maps aus dem Application-
                // Support-Importordner wählbar — `externalMapFileName` gesetzt hat
                // Vorrang vor `harmonyWebMap` (Bundle-Katalog); beide Listen bleiben
                // gegenseitig exklusiv markiert (Bundle-Auswahl räumt das externe
                // Override, externe Auswahl macht die Bundle-Markierung bedeutungslos).
                settingsSection("settings.section.world") {
                    HStack(spacing: 8) {
                        worldModeButton(.explore,    label: "settings.world.mode.explore")
                        worldModeButton(.harmonyWeb, label: "settings.world.mode.harmonyweb")
                    }
                    if s.worldSelection.mode == .harmonyWeb {
                        ForEach(HarmonyWebMapCatalog.allCases) { map in
                            let isSelected = s.worldSelection.harmonyWebMap == map && s.worldSelection.externalMapFileName == nil
                            Button(action: {
                                s.worldSelection.harmonyWebMap = map
                                s.worldSelection.externalMapFileName = nil
                            }) {
                                HStack(spacing: 10) {
                                    Text(map.displayName)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(isSelected
                                                         ? Color(red: 0.4, green: 0.85, blue: 1.0)
                                                         : .white.opacity(0.85))
                                    Spacer()
                                    if isSelected {
                                        Text("▶", bundle: .module)
                                            .font(.system(size: 11))
                                            .foregroundColor(Color(red: 0.4, green: 0.85, blue: 1.0))
                                    }
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 6)
                                .background(isSelected ? Color.white.opacity(0.07) : Color.clear)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }

                        let importedMaps = RuntimeMapImportStore.listImportedMaps()
                        if !importedMaps.isEmpty {
                            Divider().background(Color.white.opacity(0.10)).padding(.vertical, 3)
                            Text("settings.world.imported.header", bundle: .module)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.45))
                            ForEach(importedMaps) { entry in
                                let isSelected = s.worldSelection.externalMapFileName == entry.fileName
                                Button(action: {
                                    guard entry.isLoadable else { return }
                                    s.worldSelection.externalMapFileName = entry.fileName
                                }) {
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(entry.displayName)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(!entry.isLoadable ? .white.opacity(0.3)
                                                                 : isSelected ? Color(red: 0.4, green: 0.85, blue: 1.0)
                                                                 : .white.opacity(0.85))
                                            if let error = entry.loadError {
                                                Text(error)
                                                    .font(.system(size: 9, design: .monospaced))
                                                    .foregroundColor(.orange.opacity(0.75))
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                        if isSelected {
                                            Text("▶", bundle: .module)
                                                .font(.system(size: 11))
                                                .foregroundColor(Color(red: 0.4, green: 0.85, blue: 1.0))
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 6)
                                    .background(isSelected ? Color.white.opacity(0.07) : Color.clear)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .disabled(!entry.isLoadable)
                            }
                        }
                    }
                    Text("settings.world.restart.desc", bundle: .module)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.38))
                        .padding(.top, 2)
                    if s.worldSelection.mode == .harmonyWeb {
                        Text("settings.world.import.folder.label", bundle: .module)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.38))
                            .padding(.top, 4)
                        Text(verbatim: RuntimeMapImportStore.importDirectoryDisplayPath())
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                            .textSelection(.enabled)
                    }
                }

                // Runde 073 / W-04: MIDI-Eingang. Das virtuelle Ziel
                // "HarmonyEngine3D Input" existiert unabhängig von dieser
                // Auswahl — hier wird nur die zusätzliche Verbindung zu einer
                // externen Quelle gewählt. Ein gerade nicht vorhandenes Gerät
                // löscht die Auswahl nicht, sondern wird als "nicht verfügbar"
                // angezeigt.
                settingsSection("settings.section.midiin") {
                    settingsToggle("settings.midiin.enabled", value: $s.midiInput.isEnabled)
                    Text("settings.midiin.virtual.desc", bundle: .module)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.38))

                    if s.midiInput.isEnabled {
                        Divider().background(Color.white.opacity(0.10)).padding(.vertical, 3)
                        Text("settings.midiin.sources.header", bundle: .module)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.45))

                        midiInputSourceButton(uniqueID: nil, name: "")

                        ForEach(midiInput.availableSources) { source in
                            midiInputSourceButton(uniqueID: source.uniqueID, name: source.displayName)
                        }

                        if case .unavailable(_, let name) = midiInput.connectionState {
                            Text(verbatim: name.isEmpty ? "—" : name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.orange.opacity(0.8))
                            Text("settings.midiin.unavailable.hint", bundle: .module)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.orange.opacity(0.6))
                        }

                        Text("settings.midiin.channel.desc", bundle: .module)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.38))
                            .padding(.top, 2)

                        macroCCSection
                    }
                }

                settingsSection("settings.section.network") {
                    ForEach(NetworkParser.definitions, id: \.index) { def in
                        Button(action: { s.harmony.networkIndex = def.index }) {
                            HStack(spacing: 10) {
                                Text(def.emoji)
                                    .font(.system(size: 18))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(def.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(s.harmony.networkIndex == def.index
                                                         ? Color(red: 0.4, green: 0.85, blue: 1.0)
                                                         : .white.opacity(0.85))
                                    Text(def.description)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.42))
                                }
                                Spacer()
                                if s.harmony.networkIndex == def.index {
                                    Text("▶", bundle: .module)
                                        .font(.system(size: 11))
                                        .foregroundColor(Color(red: 0.4, green: 0.85, blue: 1.0))
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(s.harmony.networkIndex == def.index
                                        ? Color.white.opacity(0.07)
                                        : Color.clear)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    Divider().background(Color.white.opacity(0.10)).padding(.vertical, 3)
                    settingsToggle("settings.show.edges", value: $s.render.showNetworkEdges)
                    if s.render.showNetworkEdges {
                        Text("settings.edges.desc", bundle: .module)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.38))
                            .padding(.top, 2)
                    }
                }

                settingsSection("settings.section.energy") {
                    settingsSliderF("settings.energy.label", value: $s.harmony.energyLevel, range: 0.0...1.0, decimals: 2)
                    Text("settings.energy.desc", bundle: .module)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.38))
                        .padding(.top, 2)
                }

                settingsSection("settings.section.autopilot") {
                    settingsToggle("settings.autopilot.active", value: $s.flight.autopilotEnabled)
                    if s.flight.autopilotEnabled {
                        settingsSliderF("settings.autopilot.speed", value: $s.flight.autopilotSpeed, range: 0.15...1.0, decimals: 2)
                        Text("settings.autopilot.desc", bundle: .module)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.38))
                            .padding(.top, 2)
                    }
                }

                settingsSection("settings.section.magnet") {
                    settingsSliderF("settings.magnet.strength", value: $s.flight.magnetStrength, range: 0.0...3.0, decimals: 1)
                    settingsSliderF("settings.magnet.radius", value: $s.flight.magnetRadius, range: 30.0...300.0, decimals: 0)
                    Text("settings.magnet.desc", bundle: .module)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.38))
                        .padding(.top, 2)
                }

                settingsSection("settings.section.rendering") {
                    settingsToggle("settings.hq.rendering", value: $s.render.highQualityRendering)
                    Text(s.render.highQualityRendering
                         ? "settings.hq.active.desc"
                         : "settings.hq.inactive.desc",
                         bundle: .module)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(s.render.highQualityRendering
                                         ? Color(red: 0.3, green: 0.9, blue: 0.5).opacity(0.7)
                                         : Color.orange.opacity(0.6))
                        .padding(.top, 2)

                    Divider().background(Color.white.opacity(0.10)).padding(.vertical, 3)

                    // ── Akkord-Farbschema ─────────────────────────────────
                    HStack {
                        Text("settings.color.scheme", bundle: .module).font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                        Spacer()
                        Picker("", selection: $s.render.chordColorMode) {
                            Text("settings.color.by.type", bundle: .module).tag(1)
                            Text("settings.color.by.circle", bundle: .module).tag(0)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                        .colorScheme(.dark)
                    }
                    Text(s.render.chordColorMode == 1
                         ? "settings.color.type.desc"
                         : "settings.color.circle.desc",
                         bundle: .module)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.42))
                        .padding(.top, 1)

                    Divider().background(Color.white.opacity(0.10)).padding(.vertical, 3)

                    // ── Visual-Stil ────────────────────────────────────────
                    Text("settings.chord.style", bundle: .module).font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                    // 5 Modi als Button-Grid — Keys werden in Localizable.strings aufgelöst
                    let visualLabels = ["settings.visual.style.spheres", "settings.visual.style.voxel",
                                        "settings.visual.style.minimal", "settings.visual.style.c64",
                                        "settings.visual.style.pril"]
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                        GridItem(.flexible())], spacing: 6) {
                        ForEach(0..<5) { idx in
                            Button(action: { s.render.chordVisualMode = idx }) {
                                Text(LocalizedStringKey(visualLabels[idx]), bundle: .module)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(s.render.chordVisualMode == idx
                                                     ? Color(red: 0.4, green: 0.85, blue: 1.0)
                                                     : .white.opacity(0.70))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                                    .background(s.render.chordVisualMode == idx
                                                ? Color.white.opacity(0.10)
                                                : Color.white.opacity(0.04))
                                    .cornerRadius(5)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Group {
                        switch s.render.chordVisualMode {
                        case 1: Text("settings.visual.mode.1.desc", bundle: .module)
                        case 2: Text("settings.visual.mode.2.desc", bundle: .module)
                        case 3: Text("settings.visual.mode.3.desc", bundle: .module)
                        case 4: Text("settings.visual.mode.4.desc", bundle: .module)
                        default: Text("settings.visual.mode.0.desc", bundle: .module)
                        }
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.42))
                    .padding(.top, 1)

                    Divider().background(Color.white.opacity(0.10)).padding(.vertical, 3)

                    // ── Morphing-Intensität (Phase 3.9.4c) ──────────────────
                    settingsSliderF("settings.morphing.intensity", value: $s.render.morphingIntensity, range: 0.0...1.0, decimals: 2)
                    Text("settings.morphing.desc", bundle: .module)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.42))
                        .padding(.top, 1)
                }
                settingsSection("settings.section.object.sizes") {
                    settingsSlider("settings.chord.sphere", value: $s.render.chordRadius,  range: 15...120, unit: "")
                    settingsSlider("settings.bass.portal",  value: $s.render.portalRadius, range: 40...200, unit: "")
                    settingsSlider("settings.melody.cloud", value: $s.render.cloudRadius,  range: 20...160, unit: "")
                }
                settingsSection("settings.section.trigger.radii") {
                    settingsSlider("settings.trigger.chords",  value: $s.harmony.chordTrigger,  range: 30...250, unit: "")
                    settingsSlider("settings.trigger.portals", value: $s.harmony.portalTrigger, range: 30...250, unit: "")
                    settingsSlider("settings.trigger.clouds",  value: $s.harmony.cloudTrigger,  range: 50...300, unit: "")
                }
                settingsSection("settings.section.density") {
                    settingsSlider("settings.density.chords",  value: $s.harmony.chordDensity,  range: 10...100, unit: "%")
                    settingsSlider("settings.density.portals", value: $s.harmony.portalDensity, range: 0...80,   unit: "%")
                    settingsSlider("settings.density.clouds",  value: $s.harmony.cloudDensity,  range: 0...80,   unit: "%")
                }
                settingsSection("settings.section.speed") {
                    settingsSlider("settings.max.speed",    value: $s.flight.maxSpeed,    range: 20...500, unit: "")
                    settingsSlider("settings.thrust.force", value: $s.flight.thrustForce, range: 20...500, unit: "")
                }
                settingsSection("settings.section.controls") {
                    settingsToggle("settings.invert.pitch", value: $s.flight.invertPitch)
                    settingsSliderF("settings.yaw.sensitivity",   value: $s.flight.gamepadYawSensitivity,   range: 0.3...4.0, decimals: 1)
                    settingsSliderF("settings.pitch.sensitivity", value: $s.flight.gamepadPitchSensitivity, range: 0.3...4.0, decimals: 1)
                }
                settingsSection("settings.section.voice.leading") {
                    settingsToggle("settings.voice.leading", value: $s.harmony.voiceLeadingEnabled)
                }
                settingsSection("settings.section.audio.output") {
                    HStack {
                        Text("settings.output.label", bundle: .module)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                        Spacer()
                        Picker("", selection: $s.audio.outputMode) {
                            Text("settings.output.midi", bundle: .module).tag(OutputMode.midi)
                            Text("settings.output.internal", bundle: .module).tag(OutputMode.internalAudio)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                        .colorScheme(.dark)
                    }
                    Text("settings.output.desc", bundle: .module)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.38))
                        .padding(.top, 2)

                    // Stimmtyp des internen Synths (W-03b1). Wirkt nur im
                    // Modus "Interner Synth"; im MIDI-Modus existiert kein
                    // Voice-Pool, den die Auswahl treffen koennte.
                    if s.audio.outputMode == .internalAudio {
                        Divider().background(Color.white.opacity(0.10)).padding(.vertical, 3)
                        HStack {
                            Text("settings.voiceEngine.label", bundle: .module)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.75))
                            Spacer()
                            Picker("", selection: $s.audio.voiceEngine) {
                                Text("settings.voiceEngine.legacy", bundle: .module).tag(SynthVoiceEngine.legacy)
                                Text("settings.voiceEngine.atmospheric", bundle: .module).tag(SynthVoiceEngine.atmospheric)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                            .colorScheme(.dark)
                        }
                        Text("settings.voiceEngine.desc", bundle: .module)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.38))
                            .padding(.top, 2)
                    }
                }
                settingsSection("settings.section.midi.velocities") {
                    settingsSlider("settings.chord.vel",     value: $s.midi.chordVelocity, range: 1...127,  unit: "")
                    settingsSlider("settings.bass.vel",      value: $s.midi.bassVelocity,  range: 1...127,  unit: "")
                    settingsSlider("settings.melody.vel.max", value: $s.midi.melodyVelMax, range: 20...127, unit: "")
                }
                settingsSection("settings.section.melody.tempo") {
                    settingsSliderF("settings.tempo.factor", value: $s.midi.melodyTempo, range: 0.25...4.0, decimals: 2)
                }
                settingsSection("settings.section.bass.behavior") {
                    settingsToggle("settings.bass.hold", value: $s.midi.bassHoldMode)
                }
                settingsSection("settings.section.sensors") {
                    settingsToggle("settings.sensors.master", value: $s.midi.sensorEnabled)
                    if s.midi.sensorEnabled {
                        Divider().background(Color.white.opacity(0.10)).padding(.vertical, 3)
                        settingsToggle("settings.gyro.tilt", value: $s.midi.gyroEnabled)
                        if s.midi.gyroEnabled {
                            settingsStepper("settings.gyro.roll.cc",   value: $s.midi.gyroRollCC,  range: 0...127)
                            settingsStepper("settings.gyro.pitch.cc",  value: $s.midi.gyroPitchCC, range: 0...127)
                            settingsSliderF("settings.gyro.sensitivity", value: $s.midi.gyroSensitivity, range: 0.5...3.0, decimals: 1)
                        }
                        Divider().background(Color.white.opacity(0.10)).padding(.vertical, 3)
                        settingsToggle("settings.rotation.active", value: $s.midi.rotationEnabled)
                        if s.midi.rotationEnabled {
                            settingsStepper("settings.rotation.cc", value: $s.midi.rotationCC, range: 0...127)
                        }
                        Divider().background(Color.white.opacity(0.10)).padding(.vertical, 3)
                        settingsToggle("settings.touchpad.active", value: $s.midi.touchpadEnabled)
                        if s.midi.touchpadEnabled {
                            settingsStepper("settings.touchpad.x.cc", value: $s.midi.touchpadXCC, range: 0...127)
                            settingsStepper("settings.touchpad.y.cc", value: $s.midi.touchpadYCC, range: 0...127)
                        }
                        Divider().background(Color.white.opacity(0.10)).padding(.vertical, 3)
                        settingsChannelRow("settings.midi.channel", value: $s.midi.sensorMidiChannel)
                        Text("In Mainstage: Track mit 'HarmonyEngine3D Output' CH \(s.midi.sensorMidiChannel + 1) anlegen", bundle: .module)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }
                settingsSection("settings.section.chord.types") {
                    settingsToggle("settings.chord.maj7", value: $s.harmony.enableMaj7)
                    settingsToggle("settings.chord.m7",   value: $s.harmony.enableM7)
                    settingsToggle("settings.chord.dom7", value: $s.harmony.enableDom7)
                    settingsToggle("settings.chord.m7b5", value: $s.harmony.enableM7b5)
                }

                // ── Sprache / Language ─────────────────────────────────────
                settingsSection("settings.section.language") {
                    HStack {
                        Text("settings.language.label", bundle: .module)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                        Spacer()
                        Picker("", selection: $s.language) {
                            ForEach(AppLanguage.allCases, id: \.self) { lang in
                                Text(verbatim: lang.displayName).tag(lang)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                        .colorScheme(.dark)
                    }
                }

                Text("settings.close.hint", bundle: .module)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.30))
                    .padding(.top, 12)
            }
            .padding(18)
        }
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red:0.04, green:0.05, blue:0.16, opacity:0.97))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 24, y: 4)
        )
        .cornerRadius(12)
        .padding(16)
    }

    @ViewBuilder
    private func settingsSection<C: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title, bundle: .module)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
                .padding(.top, 12)
            content()
        }
        Divider().background(Color.white.opacity(0.15)).padding(.vertical, 5)
    }

    private func settingsSlider(_ label: LocalizedStringKey, value: Binding<Double>,
                                range: ClosedRange<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label, bundle: .module)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Text("\(Int(value.wrappedValue))\(unit)", bundle: .module)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 44, alignment: .trailing)
            }
            Slider(value: value, in: range, step: 1).tint(.white.opacity(0.7))
        }
    }

    private func settingsSliderF(_ label: LocalizedStringKey, value: Binding<Double>,
                                 range: ClosedRange<Double>, decimals: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label, bundle: .module)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Text(String(format: "%.\(decimals)f", value.wrappedValue))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 48, alignment: .trailing)
            }
            Slider(value: value, in: range).tint(.white.opacity(0.7))
        }
    }

    // Runde 023 / E-03: kompakter Zwei-Zustands-Button für die Weltwahl,
    // gleiches visuelles Muster wie der bestehende Netzwerk-Picker-Button.
    private func worldModeButton(_ mode: RuntimeWorldMode, label: LocalizedStringKey) -> some View {
        let isSelected = s.worldSelection.mode == mode
        return Button(action: { s.worldSelection.mode = mode }) {
            Text(label, bundle: .module)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(isSelected ? Color(red: 0.4, green: 0.85, blue: 1.0) : .white.opacity(0.6))
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Color.white.opacity(0.10) : Color.white.opacity(0.03))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    /// Eine Zeile der Quellenauswahl. `uniqueID == nil` ist die Zeile
    /// "Keine (nur virtuelles Ziel)" — sie schaltet den Eingang nicht ab,
    /// sondern loest nur die Verbindung zu einer externen Quelle.
    private func midiInputSourceButton(uniqueID: Int32?, name: String) -> some View {
        let isSelected = s.midiInput.selectedSourceUniqueID == uniqueID
        let accent     = Color(red: 0.4, green: 0.85, blue: 1.0)
        return Button(action: {
            s.midiInput.selectedSourceUniqueID = uniqueID
            s.midiInput.selectedSourceName     = name
        }) {
            HStack(spacing: 10) {
                Group {
                    if uniqueID == nil {
                        Text("settings.midiin.source.none", bundle: .module)
                    } else {
                        Text(verbatim: name)
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isSelected ? accent : .white.opacity(0.85))
                Spacer()
                if isSelected {
                    Text(verbatim: "▶")
                        .font(.system(size: 11))
                        .foregroundColor(accent)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(isSelected ? Color.white.opacity(0.07) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private func settingsToggle(_ label: LocalizedStringKey, value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            Text(label, bundle: .module)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
        }
        .toggleStyle(.switch)
        .tint(.blue.opacity(0.8))
    }

    // ── CC-Nummern Stepper (0–127) ─────────────────────────────────────
    private func settingsStepper(_ label: LocalizedStringKey, value: Binding<Int>,
                                  range: ClosedRange<Int>) -> some View {
        HStack {
            Text(label, bundle: .module)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
            Spacer()
            HStack(spacing: 6) {
                Button("−") { value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1) }
                    .buttonStyle(.plain)
                    .foregroundColor(.white.opacity(0.65))
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                Text("\(value.wrappedValue)", bundle: .module)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red:0.3, green:1.0, blue:0.65))
                    .frame(width: 36, alignment: .center)
                Button("+") { value.wrappedValue = min(range.upperBound, value.wrappedValue + 1) }
                    .buttonStyle(.plain)
                    .foregroundColor(.white.opacity(0.65))
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
            }
        }
    }

    // ── CC → Performance-Makro (Runde 074 / W-05) ──────────────────────
    //
    // Bewusst als eigene Property und nicht inline im Einstellungs-Panel:
    // der Abschnitt dort ist bereits so gross, dass der Typechecker ihn nicht
    // mehr in vertretbarer Zeit aufloest ("unable to type-check this
    // expression in reasonable time"). Das Herausziehen ist die Loesung, die
    // SwiftUI dafuer vorsieht.
    //
    // Die vier Default-Nummern sind vorläufig; Stephan entscheidet nach dem
    // Drehen. Eine Nummer kann nur einem Makro gehören — wird sie neu
    // vergeben, steht das andere Makro danach sichtbar auf „—".
    @ViewBuilder
    private var macroCCSection: some View {
        Divider().background(Color.white.opacity(0.10)).padding(.vertical, 3)
        Text("settings.midiin.macro.header", bundle: .module)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundColor(.white.opacity(0.45))

        macroCCRow("settings.midiin.macro.motion", macro: .motion)
        macroCCRow("settings.midiin.macro.color",  macro: .color)
        macroCCRow("settings.midiin.macro.space",  macro: .space)
        macroCCRow("settings.midiin.macro.focus",  macro: .focus)

        Text("settings.midiin.macro.desc", bundle: .module)
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(.white.opacity(0.38))
            .padding(.top, 2)
    }

    // ── CC-Nummer eines Performance-Makros (Runde 074 / W-05) ──────────
    //
    // Anders als settingsStepper: der Wert ist optional („—" = nicht
    // zugeordnet) und wird über MIDIMacroCCMapping.assign gesetzt, damit die
    // Eindeutigkeit an genau einer Stelle durchgesetzt wird. Der Bereich
    // endet bei 119, weil 120–127 im Router nie als Control Change ankommen.
    private func macroCCRow(_ label: LocalizedStringKey, macro: AudioCoreMacroID) -> some View {
        let current = s.midiInput.macroCCMapping[macro]
        let maximum = Int(MIDIMacroCCMapping.maxAssignableController)

        // Ein Schritt unter 0 löst die Zuordnung; von „—" aufwärts beginnt
        // sie wieder bei 0. Damit ist „nicht zugeordnet" über dieselben zwei
        // Tasten erreichbar wie jede Nummer, ohne dritten Knopf.
        func step(_ delta: Int) {
            let next: UInt8?
            switch (current, delta) {
            case (nil, 1):            next = 0
            case (nil, _):            next = UInt8(maximum)
            case (let value?, _):
                let raw = Int(value) + delta
                next = (raw < 0 || raw > maximum) ? nil : UInt8(raw)
            }
            s.midiInput.macroCCMapping.assign(controller: next, to: macro)
        }

        return HStack {
            Text(label, bundle: .module)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
            Spacer()
            HStack(spacing: 6) {
                Button("−") { step(-1) }
                    .buttonStyle(.plain)
                    .foregroundColor(.white.opacity(0.65))
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                Text(verbatim: current.map { "CC \($0)" } ?? "—")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(current == nil
                                     ? .white.opacity(0.35)
                                     : Color(red: 0.3, green: 1.0, blue: 0.65))
                    .frame(width: 58, alignment: .center)
                Button("+") { step(1) }
                    .buttonStyle(.plain)
                    .foregroundColor(.white.opacity(0.65))
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
            }
        }
    }

    // ── MIDI-Kanal Stepper (zeigt 1-indexed "CH n") ────────────────────
    private func settingsChannelRow(_ label: LocalizedStringKey, value: Binding<Int>) -> some View {
        HStack {
            Text(label, bundle: .module)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
            Spacer()
            HStack(spacing: 6) {
                Button("−") { value.wrappedValue = max(0, value.wrappedValue - 1) }
                    .buttonStyle(.plain)
                    .foregroundColor(.white.opacity(0.65))
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                Text("CH \(value.wrappedValue + 1)", bundle: .module)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red:1.0, green:0.72, blue:0.1))
                    .frame(width: 48, alignment: .center)
                Button("+") { value.wrappedValue = min(15, value.wrappedValue + 1) }
                    .buttonStyle(.plain)
                    .foregroundColor(.white.opacity(0.65))
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
            }
        }
    }
}
