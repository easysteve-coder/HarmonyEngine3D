import Foundation

// MARK: – RuntimeWorldMode
//
// Persistierbarer Startmodus (Runde 023 / E-03). Getrennt von
// `RuntimeWorldInfo.Kind` (HarmonyEngine3DApp.swift) — Mode ist die
// gespeicherte *Absicht* des Nutzers, Info beschreibt, was tatsächlich läuft
// (kann bei Fallback abweichen, z. B. HarmonyWeb-Wahl + defekte Map → Explore
// läuft trotzdem tatsächlich).

enum RuntimeWorldMode: String, CaseIterable {
    case explore
    case harmonyWeb
}

// MARK: – HarmonyWebMapCatalog
//
// Bekannte, im Bundle mitgelieferte HarmonyWeb-Maps, direkt wählbar ohne
// externe Datei-UI (Runde 023 / E-03). Externe Datei-Auswahl ist bewusst
// nicht Teil dieses Slices — Sicherheits-/Bookmark-/Sandbox-Entscheidung, im
// Handoff explizit als Stop-Kriterium benannt, falls sie den Slice aufbläht.
//
// rawValue == Bundle-Resource-Name für `HarmonyMapLoader.load(named:)`/
// `WorldSession.load(named:activeLayer:)`.

enum HarmonyWebMapCatalog: String, CaseIterable, Identifiable {
    case referenceCore   = "reference-core"
    case webCenter        = "harmony-web-c-center"
    case webDiatonic      = "harmony-web-c-diatonic"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .referenceCore: return "Core Functional (C-Dur)"
        case .webCenter:      return "HarmonyWeb – C-Zentrum"
        case .webDiatonic:    return "HarmonyWeb – Diatonisch C-Dur"
        }
    }
}

// MARK: – RuntimeWorldSelection
//
// Persistierte Runtime-Weltwahl (Runde 023 / E-03) — getrennt von
// `HarmonyConfig.networkIndex` (Explore-Netzwerkauswahl, unverändert, bleibt
// nur innerhalb von Explore wirksam). Default ist `.explore` (Stephan-
// Entscheidung Option A: HarmonyWeb wird normal wählbar, Explore bleibt
// App-Default). `harmonyWebLayer` startet mit `"functional"` — derselbe
// Layer, der bisher fest für den Map-Preview-Pfad verdrahtet war.
//
// Reiner Value-Typ, kein SceneKit/AppSettings-Zugriff hier — wird von
// `AppSettings` gehalten und von `AppModel.init()` gelesen.

struct RuntimeWorldSelection {
    var mode:            RuntimeWorldMode      = .explore
    var harmonyWebMap:   HarmonyWebMapCatalog  = .referenceCore
    var harmonyWebLayer: String                = "functional"

    /// Stabiler Dateiname (nicht der absolute Pfad, siehe
    /// `RuntimeMapImportStore`) einer extern importierten HarmonyMap im
    /// Runtime-Importordner (Runde 040 / V-01). `nil` (Default) — HarmonyWeb
    /// lädt weiterhin aus `harmonyWebMap` (Bundle-Katalog). Gesetzt — diese
    /// externe Datei hat Vorrang vor `harmonyWebMap`, solange sie im
    /// Importordner noch existiert und ladbar ist; scheitert das Laden,
    /// fällt `AppModel.init()` auf Explore zurück (kein automatischer
    /// Rückfall auf `harmonyWebMap`, um keinen stillen Auswahlwechsel zu
    /// erzeugen).
    var externalMapFileName: String? = nil
}
