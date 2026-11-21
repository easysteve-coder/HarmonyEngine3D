import SwiftUI
import simd

// MARK: – ScreenTarget

struct ScreenTarget: Identifiable {
    let id:   String      // interner Chunk-Key (stabil als ForEach-ID)
    let name: String      // echter Akkordname, z. B. "Bbm7"
    var screenPos:         CGPoint
    var distance:          Float
    var isAutopilotTarget: Bool
}

// MARK: – TargetingOverlayModel

final class TargetingOverlayModel: ObservableObject {
    @Published var targets: [ScreenTarget] = []
    var isEnabled: Bool = true
}

// MARK: – Proximity-Hilfsfunktionen

// Fernbereich: t = 0 bei ≥ 350 m   Nahbereich: t = 1 bei ≤ 30 m
private func proximityT(_ distance: Float) -> Double {
    let raw = Double((350 - distance) / 320)
    let c   = max(0, min(1, raw))
    return c * c * (3 - 2 * c)
}

// Ultra-Nahbereich: t = 0 bei ≥ 100 m   t = 1 bei ≤ 0 m  (für screen-filling)
private func ultraCloseT(_ distance: Float) -> Double {
    let raw = Double(max(0, 100 - distance) / 100)
    return raw * raw * (3 - 2 * raw)
}

// Farbinterpolation:
//  t = 0  → Eis-Cyan    (0.55, 0.90, 1.00)
//  t = 0.5 → Cyan-Grün   (0.78, 1.00, 0.48)
//  t = 1  → Bernstein   (1.00, 0.76, 0.10)
private func proximityColor(_ t: Double, autopilot: Bool) -> Color {
    if autopilot {
        let bright = 0.82 + t * 0.18
        return Color(red: 0.05, green: bright, blue: bright * 0.90)
    }
    let r = 0.55 + t * 0.45
    let g = t < 0.5
        ? 0.90 + t * 0.20
        : 1.00 - (t - 0.5) * 0.48
    let b = 1.00 - t * 0.90
    return Color(red: r, green: g, blue: b)
}

// MARK: – TargetingOverlayView
//
// TimelineView: treibt Sweep-Animation und Pulsieren ohne Timer oder State.
// GeometryReader: liefert Bildschirmbreite für Ultra-Nah-Skalierung.

struct TargetingOverlayView: View {

    @ObservedObject var model: TargetingOverlayModel

    var body: some View {
        if model.isEnabled {
            TimelineView(.animation) { timeline in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                GeometryReader { geo in
                    let screenW = geo.size.width
                    ForEach(model.targets) { target in
                        let t       = proximityT(target.distance)
                        let ultraT  = ultraCloseT(target.distance)
                        // Puls: 1 Hz weit → 2 Hz nah; Amplitude 0 → ±14 % (±6 % extra ultra-nah)
                        let freq    = 1.0 + t * 1.0
                        let amp     = t * 0.14 + ultraT * 0.06
                        let pulse   = 1.0 + amp * sin(elapsed * freq * 2 * .pi)

                        TargetReticle(
                            target:          target,
                            proximityT:      t,
                            ultraCloseT:     ultraT,
                            elapsed:         elapsed,
                            pulseMultiplier: pulse,
                            screenWidth:     screenW
                        )
                        .position(target.screenPos)
                        .transition(.scale(scale: 0.08, anchor: .center).combined(with: .opacity))
                    }
                }
                // Aufbau-Animation für neue Targets (spring, nicht hektisch)
                .animation(.spring(response: 0.42, dampingFraction: 0.70),
                           value: model.targets.map(\.id))
            }
        }
    }
}

// MARK: – TargetReticle

private struct TargetReticle: View {

    let target:          ScreenTarget
    let proximityT:      Double
    let ultraCloseT:     Double
    let elapsed:         Double
    let pulseMultiplier: Double
    let screenWidth:     CGFloat

    // ── Basisgrößen ──────────────────────────────────────────────────────
    private var baseReticleSize: CGFloat { target.isAutopilotTarget ? 29 : 21 }
    private var baseTextSize:    CGFloat { 14 }

    // ── Skalierung ────────────────────────────────────────────────────────
    // Phase 1 (350→100 m): normalScale bis +70 %
    // Phase 2 (100→0 m):   interpoliert zu 45 % Bildschirmbreite (= 90 % Diameter)
    private var scale: Double {
        let normalScale = 1.0 + proximityT * 0.70
        guard ultraCloseT > 0 else { return normalScale * pulseMultiplier }
        let targetRadius = Double(screenWidth) * 0.45
        let maxScale     = targetRadius / Double(baseReticleSize)
        let blended      = (1 - ultraCloseT) * normalScale + ultraCloseT * maxScale
        return blended * pulseMultiplier
    }

    private var reticleSize: CGFloat { baseReticleSize * CGFloat(scale) }
    private var armLength:   CGFloat { reticleSize * 0.38 }
    private var fontSize:    CGFloat { baseTextSize * CGFloat(scale) }
    // Linienbreite: 1.5 (weit) → 6.0 (sehr nah)
    private var lineWidth:   CGFloat { 1.5 + CGFloat(proximityT) * 1.5 + CGFloat(ultraCloseT) * 3.0 }
    private var glowRadius:  CGFloat { 2 + CGFloat(proximityT) * 16 + CGFloat(ultraCloseT) * 8 }

    // ── Deckkraft ─────────────────────────────────────────────────────────
    private var opacity: Double {
        let d = Double(target.distance)
        if d > 600 { return 0 }
        let base = 0.60 + proximityT * 0.40
        if d > 500 { return base * (1 - (d - 500) / 100) }
        return base
    }

    private var color: Color { proximityColor(proximityT, autopilot: target.isAutopilotTarget) }

    // ── Sweep-Animation ────────────────────────────────────────────────────
    // Umlaufgeschwindigkeit: 0.15 Hz (weit) → 0.45 Hz (nah)
    // Intensität: sichtbar ab t ≈ 0.2, voll bei t = 1
    private var sweepSpeed:     Double { 0.15 + proximityT * 0.30 }
    private var sweepPhase:     Double { (elapsed * sweepSpeed).truncatingRemainder(dividingBy: 1.0) }
    private var sweepIntensity: Double { max(0, min(1, (proximityT - 0.15) / 0.85)) }

    // ── Label-Abstand skaliert mit Reticle ───────────────────────────────
    private var labelOffset: CGFloat { reticleSize + 10 }

    var body: some View {
        ZStack {
            // ── Corner-Brackets (Glow + Hauptlinie) ───────────────────────
            CornerBrackets(size: reticleSize, armLength: armLength,
                           lineWidth: lineWidth, color: color, glowRadius: glowRadius)

            // ── Umlaufendes Sweep-Licht ────────────────────────────────────
            if sweepIntensity > 0 {
                // Kometenschweif: primärer Dot + zwei Geisterdots
                SweepDot(halfSize: reticleSize, phase: sweepPhase,
                         color: color, intensity: sweepIntensity, dotSize: 7)
                SweepDot(halfSize: reticleSize,
                         phase: (sweepPhase - 0.055).truncatingRemainder(dividingBy: 1.0),
                         color: color, intensity: sweepIntensity * 0.45, dotSize: 5)
                SweepDot(halfSize: reticleSize,
                         phase: (sweepPhase - 0.110).truncatingRemainder(dividingBy: 1.0),
                         color: color, intensity: sweepIntensity * 0.18, dotSize: 4)
            }

            // ── Zentraler Dot für Autopilot-Ziel ──────────────────────────
            if target.isAutopilotTarget {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                    .shadow(color: color, radius: glowRadius * 0.5)
            }

            // ── Akkordname ────────────────────────────────────────────────
            Text(target.name)
                .font(.system(size: max(11, min(fontSize, screenWidth * 0.08)),  // min 11 pt, max ~8 % Breite
                              weight: .semibold, design: .monospaced))
                .foregroundColor(color)
                .shadow(color: color.opacity(0.85), radius: glowRadius * 0.6)
                .fixedSize()
                .offset(y: labelOffset)
        }
        .opacity(opacity)
    }
}

// MARK: – CornerBrackets

private struct CornerBrackets: View {
    let size:       CGFloat
    let armLength:  CGFloat
    let lineWidth:  CGFloat
    let color:      Color
    let glowRadius: CGFloat

    var body: some View {
        ZStack {
            // Glow-Schicht
            ForEach(0..<4, id: \.self) { corner in
                CornerArm(corner: corner, size: size, armLength: armLength)
                    .stroke(color.opacity(0.28), lineWidth: lineWidth + 5)
                    .blur(radius: glowRadius * 0.45)
            }
            // Scharfe Hauptlinie
            ForEach(0..<4, id: \.self) { corner in
                CornerArm(corner: corner, size: size, armLength: armLength)
                    .stroke(color, lineWidth: lineWidth)
            }
        }
        .frame(width: size * 2, height: size * 2)
    }
}

// MARK: – SweepDot
//
// Leuchtpunkt der entlang des Quadrat-Umfangs des Reticle wandert.
// phase: 0…1 = vollständiger Umlauf.

private struct SweepDot: View {
    let halfSize:  CGFloat
    let phase:     Double
    let color:     Color
    let intensity: Double
    let dotSize:   CGFloat

    var body: some View {
        let pos = perimeterPos(phase: phase, s: halfSize)
        Circle()
            .fill(color)
            .frame(width: dotSize, height: dotSize)
            .blur(radius: dotSize * 0.75)
            .opacity(intensity)
            .offset(x: pos.x, y: pos.y)
    }

    // Gleichmäßige Bewegung entlang des Rechteck-Umfangs (4 Seiten, je 0…1)
    private func perimeterPos(phase: Double, s: CGFloat) -> CGPoint {
        let p = phase * 4         // 0…4
        let f = CGFloat(p.truncatingRemainder(dividingBy: 1.0))
        switch Int(p) {
        case 0: return CGPoint(x: -s + f * 2 * s, y: -s)          // oben:   links → rechts
        case 1: return CGPoint(x:  s,              y: -s + f * 2 * s)  // rechts: oben → unten
        case 2: return CGPoint(x:  s - f * 2 * s, y:  s)          // unten:  rechts → links
        default: return CGPoint(x: -s,             y:  s - f * 2 * s)  // links:  unten → oben
        }
    }
}

// MARK: – CornerArm (Shape)

private struct CornerArm: Shape {
    let corner:    Int
    let size:      CGFloat
    let armLength: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX, cy = rect.midY
        let sx: CGFloat = (corner == 1 || corner == 2) ?  size : -size
        let sy: CGFloat = corner >= 2                  ?  size : -size
        let dx: CGFloat = (corner == 0 || corner == 3) ?  armLength : -armLength
        let dy: CGFloat = corner < 2                   ?  armLength : -armLength
        p.move(to:    CGPoint(x: cx + sx,      y: cy + sy + dy))
        p.addLine(to: CGPoint(x: cx + sx,      y: cy + sy))
        p.addLine(to: CGPoint(x: cx + sx + dx, y: cy + sy))
        return p
    }
}
