import Foundation
import HarmonyShared

// MARK: – ImportedHarmonyMapEntry
//
// Ein extern importiertes HarmonyWeb — eine Datei im Runtime-Importordner
// (Runde 040 / V-01). `fileName` ist der stabile Identifier (Dateiname
// inkl. Extension), nicht der absolute Pfad — Persistenz in
// `RuntimeWorldSelection`/`AppSettings` bleibt dadurch stabil, auch wenn
// sich die Application-Support-Wurzel oder das Benutzer-Homeverzeichnis
// ändern (Handoff-Vorgabe: "Persistenz darf nicht an absolute, fragile
// Pfade gekoppelt werden, wenn ein stabiler Dateiname/Identifier reicht").

struct ImportedHarmonyMapEntry: Identifiable, Equatable {
    let fileName:    String
    let displayName: String
    /// `nil`, solange die Datei valide decodier-/validierbar ist. Sonst
    /// eine kurze Diagnose (Grund, warum sie aktuell nicht ladbar ist) —
    /// die Datei bleibt sichtbar gelistet, nur nicht wählbar (Scope A:
    /// "Ungueltige... Dateien duerfen die App nicht crashen... entweder
    /// nicht waehlbar sein oder mit Diagnose/Fallback sichtbar behandelt
    /// werden").
    let loadError:   String?

    var id: String { fileName }
    var isLoadable: Bool { loadError == nil }
}

// MARK: – RuntimeMapImportStore
//
// Einfache Runtime-Importquelle für extern importierte HarmonyMap-JSON-
// Dateien (Runde 040 / V-01) — ein Application-Support-Ordner statt
// NSOpenPanel/Security-Scoped Bookmarks/URL-Scheme (Stephan-Entscheidung,
// siehe `.agent_handoff/latest_codex.md` Runde 040). Reine Datei-/Codec-
// Schicht: kein SceneKit, kein AppSettings-Zugriff, kein UI — testbar ohne
// App-Kontext. Nutzt ausschließlich `HarmonyMapCodec`/`HarmonyMapValidator`
// (`HarmonyShared`), keinen `DesignerKit`-/`HarmonyAuthoring`-Import.
//
// Alle Funktionen akzeptieren ein optionales `directory:`, das den
// abgeleiteten Application-Support-Pfad überschreibt — ausschließlich für
// Tests gedacht (z. B. ein temporäres Verzeichnis statt des echten
// Benutzerordners). Produktions-Aufrufer lassen `directory` weg.

enum RuntimeMapImportStore {

    /// `~/Library/Application Support/HarmonyEngine3D/HarmonyWeb/Maps`.
    /// `nil` nur, wenn das System keinen Application-Support-Pfad liefert
    /// (in der Praxis auf macOS nie der Fall).
    static func importDirectory(fileManager: FileManager = .default) -> URL? {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport
            .appendingPathComponent("HarmonyEngine3D", isDirectory: true)
            .appendingPathComponent("HarmonyWeb", isDirectory: true)
            .appendingPathComponent("Maps", isDirectory: true)
    }

    /// Nutzerfreundlicher Pfad für die Settings-Statusanzeige (Scope B:
    /// "sichtbare, knappe Status-/Hilfsinfo zum Importordner").
    static func importDirectoryDisplayPath(fileManager: FileManager = .default) -> String {
        importDirectory(fileManager: fileManager)?.path ?? "—"
    }

    /// Legt den Importordner an, falls er noch nicht existiert. Löscht/
    /// verändert nie vorhandene Dateien.
    @discardableResult
    static func ensureImportDirectoryExists(at directory: URL? = nil, fileManager: FileManager = .default) -> URL? {
        guard let dir = directory ?? importDirectory(fileManager: fileManager) else { return nil }
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Listet alle `.json`-Dateien im Importordner, stabil nach Dateiname
    /// sortiert. Ungültige/nicht dekodierbare Dateien werden NICHT
    /// ausgeschlossen, sondern mit `loadError` sichtbar markiert — die
    /// Datei existiert, ist aber (noch) nicht ladbar. Liefert `[]`, wenn
    /// der Ordner fehlt oder leer ist — kein Fehlerzustand.
    ///
    /// Runde 041 / V-01.1 (Supervisor-Nachlauf zu V-01): im Produktpfad
    /// (`directory == nil`, z. B. `ContentView`s WELT-Abschnitt) wird der
    /// Importordner hier automatisch und nicht-destruktiv angelegt
    /// (`ensureImportDirectoryExists`) — vorher blieb er unsichtbar
    /// fehlend, bis ihn jemand manuell erstellt hatte. Ein explizit von
    /// Tests injiziertes `directory:` wird NIE automatisch angelegt (auch
    /// wenn es fehlt) — sonst wäre der No-Crash-Pfad für ein fehlendes
    /// Testverzeichnis nicht mehr isoliert testbar (siehe
    /// `test_listImportedMaps_missingDirectory_returnsEmptyArray_noCrash`).
    static func listImportedMaps(in directory: URL? = nil, fileManager: FileManager = .default) -> [ImportedHarmonyMapEntry] {
        let resolvedDirectory = directory ?? ensureImportDirectoryExists(fileManager: fileManager)
        guard let dir = resolvedDirectory,
              fileManager.fileExists(atPath: dir.path),
              let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }

        let jsonFileNames = contents
            .filter { $0.pathExtension.lowercased() == "json" }
            .map { $0.lastPathComponent }
            .sorted()

        return jsonFileNames.map { fileName in
            let url = dir.appendingPathComponent(fileName)
            do {
                let map = try HarmonyMapCodec.decode(from: url)
                let result = HarmonyMapValidator.validate(map)
                guard result.isAcceptable else {
                    let firstError = result.errors.first?.message ?? "unbekannter Validierungsfehler"
                    return ImportedHarmonyMapEntry(fileName: fileName, displayName: map.name, loadError: firstError)
                }
                return ImportedHarmonyMapEntry(fileName: fileName, displayName: map.name, loadError: nil)
            } catch {
                return ImportedHarmonyMapEntry(fileName: fileName, displayName: fileName, loadError: "\(error)")
            }
        }
    }

    /// Lädt + validiert eine importierte Map anhand ihres stabilen
    /// Dateinamens. `nil` bei fehlender Datei, Decode-Fehler oder
    /// Validierungsfehlern (Errors) — Warnings blockieren nicht, identisch
    /// zum Vertrag von `HarmonyMapLoader.load(named:)` (Bundle-Pfad). Kein
    /// Crash bei defekten Dateien — jeder Fehlerfall liefert `nil` +
    /// Log-Diagnose, der Aufrufer entscheidet über den Fallback.
    static func load(fileName: String, in directory: URL? = nil, fileManager: FileManager = .default) -> HarmonyMap? {
        guard let dir = directory ?? importDirectory(fileManager: fileManager) else { return nil }
        let url = dir.appendingPathComponent(fileName)
        do {
            let map = try HarmonyMapCodec.decode(from: url)
            let result = HarmonyMapValidator.validate(map)
            for issue in result.issues {
                let prefix = issue.severity == .error ? "⚠️ " : "ℹ️ "
                print("\(prefix) RuntimeMapImportStore [\(fileName)]: \(issue.objectPath) — \(issue.message) [\(issue.code)]")
            }
            guard result.isAcceptable else { return nil }
            print("✅  RuntimeMapImportStore: '\(map.name)' geladen"
                + " (\(map.nodes.count) Nodes, \(map.edges.count) Edges,"
                + " \(map.layers.count) Layer) aus '\(fileName)'")
            return map
        } catch {
            print("⚠️  RuntimeMapImportStore: '\(fileName)' nicht ladbar — \(error)")
            return nil
        }
    }
}
