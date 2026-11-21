import SwiftUI
import simd

// MARK: – HarmonicRadarView
//
// Debug-Overlay: Radar-Draufsicht der lokalen Harmonie-Umgebung.
//
// Zeigt:
//   – Alle lokalen Akkord-Nodes als Punkte in der XZ-Ebene (Vogelperspektive)
//   – Spieler als Fadenkreuz in der Mitte
//   – Magnet-Ziel als Ring-Marker (Magenta), wenn aktiv
//   – Farbkodierung nach HarmonicDecision:
//       Grün  → selectedNodeID   (konkretes Magnet-Ziel, RuntimeHarmonik)
//       Gelb  → suggestedChord   (Empfehlung der HarmonyLogic)
//       Weiß  → activeChord      (zuletzt aktivierter Akkord)
//       Grau  → alle übrigen Nodes
//
// Das Panel liest ausschließlich aus HarmonicDebugModel.
// Keine Logik, keine Entscheidungen, kein SceneKit, kein AppSettings.
//
// Zwei Aktualisierungspfade (ab v3.9.4):
//   Kontinuierlich (~10 Hz): localNodes, playerPosition, magnetTarget
//   Ereignisbasiert:         lastDecision, activeChord

// MARK: – Konstanten

private enum RadarStyle {
    static let radarSize:  CGFloat = 516          // Durchmesser der Radarfläche (3× Ausgangsgröße)
    static let radarRange: Float   = 350          // Welt-Einheiten bis Radarrand
    static let dotSize:    CGFloat = 9            // Durchmesser eines Node-Punkts
    static let panelWidth: CGFloat = 546          // Gesamtbreite des Panels

    static let bgColor        = Color(red: 0.06, green: 0.08, blue: 0.06)
    static let ringColor      = Color(white: 0.20).opacity(0.35)
    static let axisColor      = Color(white: 0.25).opacity(0.20)
    static let borderColor    = Color(white: 0.25)
    static let headerBg       = Color(red: 0.09, green: 0.12, blue: 0.09)

    static let colSelected    = Color(red: 0.30, green: 1.00, blue: 0.45) // Grün
    static let colSuggested   = Color(red: 1.00, green: 0.85, blue: 0.20) // Gelb
    static let colActive      = Color(red: 0.85, green: 0.85, blue: 1.00) // Hellblau-weiß
    static let colDefault     = Color(white: 0.52)                         // Grau
    static let colMagnet      = Color(red: 1.00, green: 0.30, blue: 0.90) // Magenta (Magnet-Ziel)
}

// MARK: – HarmonicRadarView

struct HarmonicRadarView: View {

    @ObservedObject var debugModel: HarmonicDebugModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            radarHeader
            radarCanvas
                .padding(10)
            decisionStatus
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
        .frame(width: RadarStyle.panelWidth)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(RadarStyle.bgColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(RadarStyle.borderColor, lineWidth: 1)
                )
        )
    }

    // MARK: – Header

    private var radarHeader: some View {
        HStack(spacing: 7) {
            // Grünes Statuslämpchen
            Circle()
                .fill(RadarStyle.colSelected.opacity(debugModel.lastDecision != nil ? 1.0 : 0.30))
                .frame(width: 6, height: 6)

            Text("HARMONIC RADAR")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(Color(white: 0.65))
                .tracking(2.5)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color(white: 0.45))
                    .frame(width: 18, height: 18)
                    .background(Color(white: 0.18))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RadarStyle.headerBg)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 10, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: 10
            )
        )
    }

    // MARK: – Radar-Canvas

    private var radarCanvas: some View {
        let s = RadarStyle.radarSize
        return ZStack {

            // ── Hintergrund-Kreis ─────────────────────────────────────────────
            Circle()
                .fill(Color(red: 0.04, green: 0.07, blue: 0.04))
            Circle()
                .stroke(RadarStyle.ringColor, lineWidth: 1)

            // ── Entfernungs-Ringe ─────────────────────────────────────────────
            ForEach([CGFloat(0.33), 0.66, 1.0], id: \.self) { fraction in
                Circle()
                    .stroke(RadarStyle.ringColor, lineWidth: 0.5)
                    .frame(width: s * fraction, height: s * fraction)
            }

            // ── Kreuz-Achsen ──────────────────────────────────────────────────
            Rectangle()
                .fill(RadarStyle.axisColor)
                .frame(width: s, height: 0.5)
            Rectangle()
                .fill(RadarStyle.axisColor)
                .frame(width: 0.5, height: s)

            // ── "N" Nordmarkierung (Z- = vorwärts = oben) ─────────────────────
            Text("↑")
                .font(.system(size: 8))
                .foregroundColor(Color(white: 0.30))
                .position(x: s / 2, y: 8)

            // ── Akkord-Nodes ──────────────────────────────────────────────────
            ForEach(debugModel.localNodes, id: \.id) { node in
                let pt = worldToRadar(node.position, size: s)
                nodeMarker(for: node)
                    .position(pt)
            }

            // ── Magnet-Ziel-Marker ────────────────────────────────────────────
            // Zeigt die räumliche Weltposition von magnetTargetPosition als
            // offenen Ring (Magenta). Überlagert ggf. den Node-Punkt — das ist
            // gewollt: Zielposition und Akkord-Node fallen im Normalfall zusammen.
            if let magPos = debugModel.magnetTarget {
                let pt = worldToRadar(magPos, size: s)
                magnetMarker
                    .position(pt)
            }

            // ── Spieler-Fadenkreuz ────────────────────────────────────────────
            playerMarker
        }
        .frame(width: s, height: s)
        // Kein clipShape — Labels am Rand können leicht überlappen; für Debug OK.
    }

    // MARK: – Node-Marker

    @ViewBuilder
    private func nodeMarker(for node: LocalNode) -> some View {
        let col = nodeColor(for: node)
        VStack(spacing: 2) {
            Circle()
                .fill(col)
                .frame(width: RadarStyle.dotSize, height: RadarStyle.dotSize)
                .overlay(
                    // Glow-Ring für hervorgehobene Nodes
                    Circle()
                        .stroke(col.opacity(0.40), lineWidth: 2.5)
                        .scaleEffect(1.8)
                        .opacity(isHighlighted(node) ? 1 : 0)
                )
            Text(verbatim: node.chordName)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(col)
                .fixedSize()
        }
    }

    // MARK: – Magnet-Ziel-Marker
    //
    // Offener Ring in Magenta: unterscheidet sich von Node-Punkt (gefüllt) und
    // Spieler-Fadenkreuz. Zeigt die tatsächliche Weltposition von magnetTargetPosition.

    private var magnetMarker: some View {
        ZStack {
            Circle()
                .stroke(RadarStyle.colMagnet, lineWidth: 2)
                .frame(width: 18, height: 18)
            Circle()
                .stroke(RadarStyle.colMagnet.opacity(0.30), lineWidth: 5)
                .frame(width: 28, height: 28)
        }
        .allowsHitTesting(false)
    }

    // MARK: – Spieler-Marker
    //
    // Kein .position() nötig — liegt standardmäßig in der Mitte des äußeren ZStack.

    private var playerMarker: some View {
        ZStack {
            // Kleiner Außenring
            Circle()
                .stroke(Color.white.opacity(0.40), lineWidth: 1)
                .frame(width: 11, height: 11)
            // Fadenkreuz (zwei Rectangles, in Mitte zentriert)
            Rectangle()
                .fill(Color.white.opacity(0.75))
                .frame(width: 13, height: 1.2)
            Rectangle()
                .fill(Color.white.opacity(0.75))
                .frame(width: 1.2, height: 13)
        }
        .allowsHitTesting(false)
    }

    // MARK: – Entscheidungs-Status

    private var decisionStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
                .background(Color(white: 0.18))
                .padding(.bottom, 2)

            statusRow(
                icon: "arrow.up.circle",
                color: RadarStyle.colSuggested,
                label: "suggested",
                value: debugModel.lastDecision?.suggestedChord ?? "–"
            )
            statusRow(
                icon: "scope",
                color: RadarStyle.colSelected,
                label: "target",
                value: targetString
            )
            statusRow(
                icon: "music.note",
                color: RadarStyle.colActive,
                label: "active",
                value: debugModel.activeChord.isEmpty ? "–" : debugModel.activeChord
            )
            magnetRow
            strategyRow
        }
    }

    @ViewBuilder
    private func statusRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundColor(color.opacity(0.80))
                .frame(width: 11)
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(white: 0.42))
            Text(verbatim: value)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // ── Magnet-Ziel-Distanz ───────────────────────────────────────────────
    // Zeigt Echtzeit-Distanz von Spieler zu magnetTargetPosition.
    // "–" wenn kein Magnet aktiv.

    private var magnetRow: some View {
        HStack(spacing: 5) {
            Circle()
                .stroke(RadarStyle.colMagnet, lineWidth: 1.2)
                .frame(width: 8, height: 8)
                .frame(width: 11)
            Text("magnet")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(white: 0.42))
            Text(verbatim: magnetDistanceString)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(RadarStyle.colMagnet)
                .lineLimit(1)
        }
    }

    private var strategyRow: some View {
        HStack(spacing: 5) {
            Image(systemName: "chart.bar")
                .font(.system(size: 8))
                .foregroundColor(Color(white: 0.35))
                .frame(width: 11)
            Text("strategy")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(white: 0.42))
            Text(verbatim: debugModel.lastDecision?.strategy.rawValue ?? "–")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(strategyColor)
        }
    }

    // MARK: – Hilfsmethoden

    /// Projiziert eine Weltposition auf Radar-Koordinaten (XZ → XY, Z-Achse = nach oben).
    private func worldToRadar(_ worldPos: simd_float3, size: CGFloat) -> CGPoint {
        let dx =  worldPos.x - debugModel.playerPosition.x
        let dz = -worldPos.z + debugModel.playerPosition.z   // Z negieren: vorwärts = oben
        let scale = Float(size / 2) / RadarStyle.radarRange
        let x = CGFloat(size / 2) + CGFloat(dx * scale)
        let y = CGFloat(size / 2) + CGFloat(dz * scale)
        // Weiche Clamp: Punkte außerhalb Radarrange auf Randbereich drücken
        let margin: CGFloat = 10
        return CGPoint(
            x: min(max(x, margin), size - margin),
            y: min(max(y, margin), size - margin)
        )
    }

    private func nodeColor(for node: LocalNode) -> Color {
        if node.id == debugModel.lastDecision?.selectedNodeID {
            return RadarStyle.colSelected
        }
        if node.chordName == debugModel.lastDecision?.suggestedChord {
            return RadarStyle.colSuggested
        }
        if node.chordName == debugModel.activeChord {
            return RadarStyle.colActive
        }
        return RadarStyle.colDefault
    }

    private func isHighlighted(_ node: LocalNode) -> Bool {
        node.id == debugModel.lastDecision?.selectedNodeID ||
        node.chordName == debugModel.lastDecision?.suggestedChord
    }

    private var targetString: String {
        guard let dec = debugModel.lastDecision,
              let id  = dec.selectedNodeID else { return "–" }
        if let dist = dec.selectedNodeDistance {
            return "\(id)  \(String(format: "%.0f", dist))m"
        }
        return id
    }

    /// Echtzeit-Distanz von Spieler zu magnetTargetPosition.
    private var magnetDistanceString: String {
        guard let magPos = debugModel.magnetTarget else { return "–" }
        let dist = simd_distance(magPos, debugModel.playerPosition)
        return String(format: "%.0f m", dist)
    }

    private var strategyColor: Color {
        switch debugModel.lastDecision?.strategy {
        case .magnetismCandidate: return RadarStyle.colSelected
        case .noCandidate:        return RadarStyle.colSuggested.opacity(0.70)
        case .noSuggestion:       return RadarStyle.colDefault
        case nil:                 return RadarStyle.colDefault
        }
    }
}
