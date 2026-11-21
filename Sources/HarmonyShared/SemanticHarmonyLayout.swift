import simd

// MARK: – SemanticHarmonyLayout (Phase 4.1a)
//
// Deterministische 3D-Ankerposition für einen HarmonyNode, ohne SceneKit.
// `node.layout3D` gewinnt immer (Autoren-Kontrolle hat Vorrang). Fehlt es, wird
// eine semantische Fallback-Position aus `root` (Quintenzirkel-Winkel in der
// XZ-Ebene), `function` (Radius) und `type` (Y-Höhe) berechnet.
//
// Keine Force-Directed-Relaxierung in dieser Runde — reine Funktion der
// Node-Felder, kein externer Zustand, kein RNG. Zwei Aufrufe mit demselben
// Node liefern immer dieselbe Position.
//
// Kein SceneKit, kein AppSettings, kein UI.

public enum SemanticHarmonyLayout {

    /// Basisradius der semantischen Fallback-Position, in Engine-Einheiten.
    /// Bewusst nah am bisherigen Ring-Layout-Radius (180, siehe
    /// `HarmonyScene.buildJsonWebLayout`) gewählt, damit bestehende Trigger-
    /// Radien (`AppSettings.harmony.chordTrigger` etc.) weiterhin sinnvoll
    /// greifen — die Fallback-Radien liegen je nach `function` zwischen
    /// `0.55×` und `1.15×` dieses Basiswerts (siehe `radiusFactor(for:)`).
    public static let baseRadius: Float = 150.0

    /// Liefert die 3D-Ankerposition für `node`.
    /// `node.layout3D` wird, falls vorhanden, 1:1 übernommen. Sonst liefert
    /// `semanticFallback(for:)` eine deterministische Position aus
    /// `root`/`function`/`type`.
    public static func position(for node: HarmonyNode) -> simd_float3 {
        if let l = node.layout3D {
            return simd_float3(l.x, l.y, l.z)
        }
        return semanticFallback(for: node)
    }

    /// `true`, wenn `position(for:)` `node.layout3D` genutzt hat (statt des
    /// semantischen Fallbacks) — für Layout-Quellen-Logging.
    public static func usesExplicitLayout(_ node: HarmonyNode) -> Bool {
        node.layout3D != nil
    }

    // MARK: – Fallback-Berechnung (privat)

    private static func semanticFallback(for node: HarmonyNode) -> simd_float3 {
        // XZ-Winkel: Quintenzirkel-Position aus `root`. `root` ist in den
        // vorhandenen Maps ein volles MIDI-Notennummer (z. B. 60 = C4), keine
        // reine Pitch-Class 0...11 — die Formel arbeitet aber ausschließlich
        // mit `root % 12`, sodass die Oktave keine Rolle spielt: zwei Nodes
        // mit derselben Pitch-Class (z. B. root 60 und 72, beide C) landen
        // bewusst am selben Winkel, unterschiedliche Pitch-Classes nie.
        // Ein Quintenschritt entspricht 7 Halbtönen; `(root * 7) % 12` ordnet
        // die 12 Pitch-Classes in Quinten-Reihenfolge an (C, G, D, A, E, B,
        // F#, C#, G#, D#, A#, F) — musikalisch vertraute Nachbarschaft statt
        // chromatischer Reihenfolge. Bijektiv über die Pitch-Class (ggT(7,12)=1).
        let fifthStep = Float((node.root * 7) % 12)
        let angle     = fifthStep / 12.0 * 2.0 * .pi

        let radius = baseRadius * radiusFactor(for: node.function)
        let x =  radius * cos(angle)
        let z = -radius * sin(angle)   // SceneKit-Konvention: -Z = vorwärts (siehe HarmonyScene)

        return simd_float3(x, yOffset(for: node.type), z)
    }

    /// Radius-Faktor nach harmonischer Funktion: tonic innen, dominant außen,
    /// ambiguous neutral zwischen subdominant und dominant.
    private static func radiusFactor(for function: HarmonicFunction) -> Float {
        switch function {
        case .tonic:       return 0.55
        case .subdominant: return 0.85
        case .ambiguous:   return 1.00
        case .dominant:    return 1.15
        }
    }

    /// Y-Höhe nach Akkordtyp: hellere/konsonantere Typen oben, dissonantere unten.
    /// Rein visuelle Staffelung, keine musikalische Bedeutung außerhalb des Renderns.
    private static func yOffset(for type: ChordType) -> Float {
        switch type {
        case .maj7: return  18
        case .maj:  return  14
        case .m7:   return   0
        case .min:  return   0
        case .sus4: return  -6
        case .dom7: return -12
        case .m7b5: return -24
        case .dim7: return -30
        }
    }
}
