import SwiftUI

// MARK: – Steuerungsübersicht (PS5 DualSense)
//
//  Einblenden:  OPTIONS-Taste (☰) am Controller  oder  Klick auf Overlay
//  Ausblenden:  nochmal OPTIONS drücken  oder  irgendwo klicken

struct ControlsOverlay: View {

    // Callback zum Schließen – ContentView übergibt Closure, die FlightController setzt.
    var onDismiss: () -> Void = {}

    // Farben passend zum Cockpit
    private let amber   = Color(red:1.0,  green:0.72, blue:0.10)
    private let chordC  = Color(red:0.4,  green:0.8,  blue:1.0)
    private let bassC   = Color(red:1.0,  green:0.55, blue:0.1)
    private let melodyC = Color(red:0.1,  green:0.85, blue:0.9)
    private let stickC  = Color(red:0.85, green:0.4,  blue:1.0)
    private let redC    = Color(red:1.0,  green:0.25, blue:0.25)

    var body: some View {
        ZStack {
            // ── Hintergrund ───────────────────────────────────────────────
            Color.black.opacity(0.82)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {

                // ── Header ────────────────────────────────────────────────
                HStack {
                    HStack(spacing: 12) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 26))
                            .foregroundColor(amber)
                        Text("controls.title", bundle: .module)
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Text("OPTIONS", bundle: .module)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                        optionsIcon
                        Text("controls.close.hint", bundle: .module)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                .padding(.horizontal, 36)
                .padding(.top, 30)
                .padding(.bottom, 24)

                // ── Hauptbereich ──────────────────────────────────────────
                HStack(alignment: .top, spacing: 0) {

                    // ── Linke Label-Spalte ────────────────────────────────
                    VStack(alignment: .trailing, spacing: 0) {
                        Spacer().frame(height: 10)
                        labelBlock(buttons: ["L2"],              desc: "controls.l2.desc",    color: bassC)
                        labelBlock(buttons: ["L1"],              desc: "controls.l1.desc",    color: melodyC)
                        Spacer().frame(height: 32)
                        labelBlock(buttons: ["controls.lstick.button"],
                                   desc: "controls.lstick.desc",
                                   color: stickC)
                        Spacer().frame(height: 18)
                        labelBlock(buttons: ["controls.l3.button"], desc: "controls.l3.desc",    color: stickC)
                        Spacer().frame(height: 18)
                        labelBlock(buttons: ["controls.dpad.button"], desc: "controls.dpad.desc", color: bassC)
                    }
                    .frame(width: 210)
                    .padding(.trailing, 16)

                    // ── Controller-Zeichnung ──────────────────────────────
                    PS5Diagram()
                        .frame(width: 520, height: 400)

                    // ── Rechte Label-Spalte ───────────────────────────────
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer().frame(height: 10)
                        labelBlock(buttons: ["R2"],                    desc: "controls.r2.desc",       color: bassC,   right: true)
                        labelBlock(buttons: ["R1"],                    desc: "controls.r1.desc",       color: melodyC, right: true)
                        Spacer().frame(height: 32)
                        labelBlock(buttons: ["controls.rstick.button"], desc: "controls.rstick.desc",
                                   color: .white, right: true)
                        Spacer().frame(height: 18)
                        labelBlock(buttons: ["controls.r3.button"],    desc: "controls.r3.desc",       color: bassC,   right: true)
                        Spacer().frame(height: 18)
                        labelBlock(buttons: ["△"],                     desc: "controls.triangle.desc", color: redC,    right: true)
                        Spacer().frame(height: 18)
                        labelBlock(buttons: ["OPTIONS  ☰"],           desc: "controls.options.desc",  color: amber,   right: true)
                    }
                    .frame(width: 210)
                    .padding(.leading, 16)
                }

                // ── MIDI-Kanal-Legende ─────────────────────────────────────
                HStack(spacing: 36) {
                    midiLegend("controls.midi.ch1", color: chordC)
                    midiLegend("controls.midi.ch2", color: bassC)
                    midiLegend("controls.midi.ch3", color: melodyC)
                    midiLegend("controls.midi.ch4", color: stickC)
                }
                .padding(.top, 24)
                .padding(.bottom, 30)
            }
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(red:0.04, green:0.05, blue:0.14, opacity:0.98))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.75), radius: 50)
            )
            .padding(.horizontal, 44)
            .padding(.vertical, 32)
            .onTapGesture { onDismiss() }
        }
    }

    // ── Hilfsfunktionen ───────────────────────────────────────────────────

    // buttons: Literal-Strings (Button-Bezeichner: L2, R1 etc.) — kein Lookup nötig.
    // desc:    LocalizedStringKey → wird in Localizable.strings aufgelöst.
    @ViewBuilder
    private func labelBlock(buttons: [String], desc: LocalizedStringKey,
                             color: Color, right: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if right {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(buttons, id: \.self) { btn in
                        Text(LocalizedStringKey(btn), bundle: .module)  // Lookup → Fallback auf btn wenn kein Key
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(color)
                    }
                    Text(desc, bundle: .module)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white.opacity(0.60))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 20)
            } else {
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    ForEach(buttons, id: \.self) { btn in
                        Text(LocalizedStringKey(btn), bundle: .module)  // Lookup → Fallback auf btn wenn kein Key
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(color)
                    }
                    Text(desc, bundle: .module)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white.opacity(0.60))
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 20)
            }
        }
    }

    private func midiLegend(_ label: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 9) {
            Circle()
                .fill(color)
                .frame(width: 13, height: 13)
                .shadow(color: color.opacity(0.8), radius: 5)
            Text(label, bundle: .module)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundColor(color.opacity(0.90))
        }
    }

    private var optionsIcon: some View {
        Text("☰", bundle: .module)
            .font(.system(size: 14))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.14)))
    }
}

// MARK: – PS5 DualSense Zeichnung  (Front-View, 520×400)
//
//  Korrektes DualSense Front-View Layout:
//   Oben-Links:    D-Pad                  Oben-Rechts:   Face Buttons (△□○✕)
//   Unten-Links:   L.Stick (Chord-Töne)   Unten-Rechts:  R.Stick (Blick)
//   Mitte oben:    Großes Touchpad
//   Ganz oben:     L2/R2 Trigger  +  L1/R1 Schultertasten
//
//  Koordinatensystem: (0,0) = Mittelpunkt des 520×400-Frames

private struct PS5Diagram: View {

    private let bassC   = Color(red:1.0, green:0.55, blue:0.1)
    private let melodyC = Color(red:0.1, green:0.85, blue:0.9)
    private let stickC  = Color(red:0.85, green:0.4,  blue:1.0)
    private let amber   = Color(red:1.0, green:0.72, blue:0.1)

    var body: some View {
        ZStack {

            // ══════════════════════════════════════════════════════════════
            // GRIFFE  (zuerst zeichnen → liegen hinter Körper)
            // ══════════════════════════════════════════════════════════════

            Ellipse()
                .fill(Color(white: 0.11))
                .frame(width: 108, height: 152)
                .rotationEffect(.degrees(-7))
                .offset(x: -124, y: 120)
            Ellipse()
                .fill(Color(white: 0.11))
                .frame(width: 108, height: 152)
                .rotationEffect(.degrees(7))
                .offset(x:  124, y: 120)

            // ══════════════════════════════════════════════════════════════
            // HAUPTKÖRPER  (breites Oval, obere Hälfte)
            // ══════════════════════════════════════════════════════════════

            RoundedRectangle(cornerRadius: 52)
                .fill(Color(white: 0.15))
                .frame(width: 456, height: 248)
                .offset(y: -18)
            RoundedRectangle(cornerRadius: 52)
                .stroke(Color.white.opacity(0.12), lineWidth: 1.5)
                .frame(width: 456, height: 248)
                .offset(y: -18)

            // ══════════════════════════════════════════════════════════════
            // L2 / R2  (ganz oben, Trigger)
            // ══════════════════════════════════════════════════════════════

            cpButton("L2", color: bassC,   offset: (-178, -134), w: 70, h: 30)
            cpButton("R2", color: bassC,   offset: ( 178, -134), w: 70, h: 30)

            // ══════════════════════════════════════════════════════════════
            // L1 / R1  (Schultertasten, knapp unter L2/R2)
            // ══════════════════════════════════════════════════════════════

            cpButton("L1", color: melodyC, offset: (-178, -101), w: 70, h: 22)
            cpButton("R1", color: melodyC, offset: ( 178, -101), w: 70, h: 22)

            // ══════════════════════════════════════════════════════════════
            // TOUCHPAD  (großes Rechteck, Mitte oben)
            // ══════════════════════════════════════════════════════════════

            RoundedRectangle(cornerRadius: 13)
                .fill(Color(white: 0.22))
                .frame(width: 148, height: 82)
                .offset(y: -68)
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                .frame(width: 148, height: 82)
                .offset(y: -68)
            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(width: 1, height: 74)
                .offset(y: -68)
            Text("TOUCHPAD", bundle: .module)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.22))
                .offset(y: -68)

            // ══════════════════════════════════════════════════════════════
            // CREATE  (links vom Touchpad)
            // ══════════════════════════════════════════════════════════════

            RoundedRectangle(cornerRadius: 5)
                .fill(Color(white: 0.28))
                .frame(width: 28, height: 16)
                .offset(x: -88, y: -68)
            Text("✦", bundle: .module)
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(0.42))
                .offset(x: -88, y: -68)

            // ══════════════════════════════════════════════════════════════
            // OPTIONS  (rechts vom Touchpad, amber)
            // ══════════════════════════════════════════════════════════════

            RoundedRectangle(cornerRadius: 5)
                .fill(amber.opacity(0.60))
                .frame(width: 30, height: 16)
                .offset(x: 88, y: -68)
            Text("☰", bundle: .module)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.black.opacity(0.85))
                .offset(x: 88, y: -68)

            // ══════════════════════════════════════════════════════════════
            // D-PAD  ——  OBEN-LINKS  (über dem linken Stick)
            // ══════════════════════════════════════════════════════════════

            // Kreuz vertikal
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(white: 0.28))
                .frame(width: 19, height: 60)
                .offset(x: -152, y: -28)
            // Kreuz horizontal
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(white: 0.28))
                .frame(width: 60, height: 19)
                .offset(x: -152, y: -28)
            // Kontur
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                .frame(width: 19, height: 60)
                .offset(x: -152, y: -28)
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                .frame(width: 60, height: 19)
                .offset(x: -152, y: -28)
            // ↑ Bass-Toggle hervorheben
            Text("↑", bundle: .module)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(bassC.opacity(0.92))
                .offset(x: -152, y: -52)

            // ══════════════════════════════════════════════════════════════
            // FACE BUTTONS  ——  OBEN-RECHTS  (über dem rechten Stick)
            // △=oben  ○=rechts  ✕=unten  □=links  (Raute)
            // ══════════════════════════════════════════════════════════════

            faceButton("△", color: Color(red:0.3, green:1.0, blue:0.4),  offset: ( 152, -52))
            faceButton("○", color: Color(red:1.0, green:0.3, blue:0.3),  offset: ( 178, -28))
            faceButton("✕", color: Color(red:0.3, green:0.5, blue:1.0),  offset: ( 152,  -4))
            faceButton("□", color: Color(red:0.8, green:0.5, blue:1.0),  offset: ( 126, -28))

            // ══════════════════════════════════════════════════════════════
            // LINKER STICK  ——  UNTEN-LINKS  (unter dem D-Pad)
            // ══════════════════════════════════════════════════════════════

            Circle()
                .fill(Color(white: 0.18))
                .frame(width: 72, height: 72)
                .offset(x: -104, y: 62)
            Circle()
                .fill(stickC.opacity(0.26))
                .frame(width: 50, height: 50)
                .offset(x: -104, y: 62)
            Circle()
                .stroke(stickC.opacity(0.75), lineWidth: 3)
                .frame(width: 72, height: 72)
                .offset(x: -104, y: 62)
            Text("L", bundle: .module)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.68))
                .offset(x: -104, y: 62)
            // Richtungspfeile
            Group {
                Text("↑", bundle: .module).font(.system(size: 12)).foregroundColor(stickC.opacity(0.78)).offset(x: -104, y:  30)
                Text("↓", bundle: .module).font(.system(size: 12)).foregroundColor(stickC.opacity(0.78)).offset(x: -104, y:  94)
                Text("←", bundle: .module).font(.system(size: 12)).foregroundColor(stickC.opacity(0.78)).offset(x: -138, y:  62)
                Text("→", bundle: .module).font(.system(size: 12)).foregroundColor(stickC.opacity(0.78)).offset(x:  -70, y:  62)
            }
            Text("L3  +8va", bundle: .module)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(stickC.opacity(0.88))
                .offset(x: -104, y: 112)

            // ══════════════════════════════════════════════════════════════
            // RECHTER STICK  ——  UNTEN-RECHTS  (unter den Face Buttons)
            // ══════════════════════════════════════════════════════════════

            Circle()
                .fill(Color(white: 0.18))
                .frame(width: 72, height: 72)
                .offset(x: 104, y: 62)
            Circle()
                .fill(Color(white: 0.26))
                .frame(width: 50, height: 50)
                .offset(x: 104, y: 62)
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 2.5)
                .frame(width: 72, height: 72)
                .offset(x: 104, y: 62)
            Text("R", bundle: .module)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.58))
                .offset(x: 104, y: 62)
            Text("R3  Bremse", bundle: .module)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(bassC.opacity(0.88))
                .offset(x: 104, y: 112)

            // ══════════════════════════════════════════════════════════════
            // PS HOME BUTTON  (zwischen den Sticks)
            // ══════════════════════════════════════════════════════════════

            Circle()
                .fill(Color(white: 0.24))
                .frame(width: 30, height: 30)
                .offset(y: 44)
            Text("PS", bundle: .module)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white.opacity(0.38))
                .offset(y: 44)

            // ══════════════════════════════════════════════════════════════
            // MUTE BUTTON  (unter PS-Button)
            // ══════════════════════════════════════════════════════════════

            RoundedRectangle(cornerRadius: 5)
                .fill(Color(white: 0.22))
                .frame(width: 38, height: 14)
                .offset(y: 84)
            Text("🔇", bundle: .module)
                .font(.system(size: 7))
                .foregroundColor(.white.opacity(0.28))
                .offset(y: 84)
        }
        .frame(width: 520, height: 400)
    }

    // ── Schultertasten-Helper ─────────────────────────────────────────────
    @ViewBuilder
    private func cpButton(_ label: String, color: Color,
                           offset: (CGFloat, CGFloat), w: CGFloat, h: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(color.opacity(0.68))
            .frame(width: w, height: h)
            .offset(x: offset.0, y: offset.1)
        Text(label)
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundColor(.black.opacity(0.88))
            .offset(x: offset.0, y: offset.1)
    }

    // ── Face-Button-Helper ────────────────────────────────────────────────
    @ViewBuilder
    private func faceButton(_ symbol: String, color: Color,
                              offset: (CGFloat, CGFloat)) -> some View {
        Circle()
            .fill(color.opacity(0.72))
            .frame(width: 32, height: 32)
            .offset(x: offset.0, y: offset.1)
        Circle()
            .stroke(color, lineWidth: 1.5)
            .frame(width: 32, height: 32)
            .offset(x: offset.0, y: offset.1)
        Text(symbol)
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.black.opacity(0.88))
            .offset(x: offset.0, y: offset.1)
    }
}
