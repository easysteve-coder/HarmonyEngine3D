import Foundation

// MARK: – HarmonicMagnetFieldKind
//
// Klassifiziert den musikalischen Charakter einer Kante für den
// harmonischen Magnet. Bis K-07 lebte dieser Typ privat in
// `HarmonyEngine3D/RuntimeHarmonik.swift` — nach `HarmonyShared` verschoben,
// weil `DesignerKit` (Construction-Kit-Simulation-Preview, K-07)
// `RuntimeHarmonik` nicht importieren kann (liegt im
// `HarmonyEngine3D`-Executable-Target). `RuntimeHarmonik` delegiert seither
// auf denselben Typ/dieselbe Funktion (siehe `HarmonicMagnetPreview`
// unten) statt eine zweite Kopie zu pflegen — keine Verhaltensänderung.

public enum HarmonicMagnetFieldKind: String, CaseIterable {
    case dominantResolution   // .vToI          — starke, gerichtete Auflösung
    case preDominantMotion    // .iiToV         — vorbereitende Bewegung zur Dominante
    case substitution         // .tritSubst     — Tritonus-Substitution
    case relative             // .relMajMin     — parallele Tonart, weich/symmetrisch
    case commonTone           // .commonTone    — gemeinsamer Ton, am weichsten
    case generic              // .parallelMajMin oder keine der obigen — neutraler Fallback
}

// MARK: – HarmonicMagnetPreview
//
// Reine, deterministische Preset-/Feld-/Range-Zuordnung — einzige Quelle für
// `RuntimeHarmonik` (3D-Runtime, `HarmonyEngine3D`) UND die DesignerKit-
// Simulation-Preview (`HarmonyGraphSimulation`, K-07). Keine Duplikate:
// beide Konsumenten rufen exakt dieselben Funktionen auf.
//
// Kein SceneKit, kein AppSettings, kein UI.

public enum HarmonicMagnetPreview {

    /// `relationTypes` → Feldkategorie. Deterministische Prioritätsreihenfolge
    /// (dominant/prädominant vor Substitution vor relativ vor commonTone vor
    /// generic) — identisch zur bisherigen `RuntimeHarmonik`-Logik.
    public static func fieldKind(for relationTypes: [RelationType]) -> HarmonicMagnetFieldKind {
        if relationTypes.contains(.vToI)       { return .dominantResolution }
        if relationTypes.contains(.iiToV)      { return .preDominantMotion }
        if relationTypes.contains(.tritSubst)  { return .substitution }
        if relationTypes.contains(.relMajMin)  { return .relative }
        if relationTypes.contains(.commonTone) { return .commonTone }
        return .generic
    }

    /// Preset → Basis-Reichweite in Metern (nil/medium = 15, strong = 25,
    /// weak = 8) — identisch zur bisherigen `HarmonicMagnetConfig.baseRange`.
    public static func baseRange(for preset: MagnetProfile.Preset?) -> Float {
        switch preset ?? .medium {
        case .strong: return 25
        case .medium: return 15
        case .weak:   return 8
        }
    }

    /// Effektive Reichweite: Preset-Basis × `rangeScale`. Default `1.0` —
    /// die Runtime übergibt den echten `HarmonicMagnetConfig.rangeScale`-Wert
    /// (aus `AppSettings.harmonicMagnet`), die DesignerKit-Preview den
    /// Default, da `HarmonyAuthoring`/`DesignerKit` keinen `AppSettings`-
    /// Zugriff haben (und keinen brauchen sollen).
    public static func effectiveRange(preset: MagnetProfile.Preset?, rangeScale: Float = 1.0) -> Float {
        baseRange(for: preset) * rangeScale
    }
}
