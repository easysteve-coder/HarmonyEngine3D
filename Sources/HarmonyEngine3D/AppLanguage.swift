import Foundation

// MARK: – AppLanguage
//
// Unterstützte Anzeigesprachen der App.
//
// Persistenz: AppSettings.shared.language → UserDefaults (Key: "he3d.ui.language").
// Locale-Injektion: HarmonyEngine3DApp liest denselben Key via @AppStorage und
// injiziert `.environment(\.locale, Locale(identifier: language.rawValue))` in den
// Root-WindowGroup-Inhalt. SwiftUI verwendet diese Locale beim Auflösen von
// LocalizedStringKey in Text()-Views (macOS 13+).
//
// Sprachdateien:
//   Sources/HarmonyEngine3D/Resources/de.lproj/Localizable.strings
//   Sources/HarmonyEngine3D/Resources/en.lproj/Localizable.strings
//
// Neue Sprache hinzufügen:
//   1. Case zu AppLanguage hinzufügen.
//   2. .lproj-Ordner mit Localizable.strings anlegen.
//   3. displayName ergänzen.
//   4. Picker in SettingsPanel passt sich automatisch an (iteriert über CaseIterable).

enum AppLanguage: String, CaseIterable, Hashable {
    case german  = "de"
    case english = "en"

    /// Anzeigename im Sprach-Picker (nicht lokalisiert – immer in der jeweiligen Sprache).
    var displayName: String {
        switch self {
        case .german:  return "Deutsch"
        case .english: return "English"
        }
    }

    /// Locale-Identifier für Locale(identifier:) und UserDefaults.
    var localeIdentifier: String { rawValue }
}
