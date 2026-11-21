import Foundation

// MARK: – AudioPresetStore
//
// S-03: User-Preset-Store in Application Support, im selben Stil wie
// `RuntimeMapImportStore` (V-01): atomisches Schreiben, `directory:`-
// Injection für Tests, kein Security-Scoped-Bookmark/Sharing/Export, keine
// UI. Reine Datei-/Codec-Schicht — kein SceneKit, kein AppSettings-Zugriff.
//
// Ablageort: `~/Library/Application Support/HarmonyEngine3D/AudioPresets`.

struct AudioPresetIndexEntry: Identifiable, Equatable {
    let fileName:    String
    let displayName: String
    /// `nil`, solange die Datei valide decodier-/validierbar ist (siehe
    /// `RuntimeMapImportStore.ImportedHarmonyMapEntry` für dasselbe Muster).
    let loadError:   String?

    var id: String { fileName }
    var isLoadable: Bool { loadError == nil }
}

enum AudioPresetStoreError: Error, CustomStringConvertible {
    case noApplicationSupportDirectory
    case write(underlying: Error)

    var description: String {
        switch self {
        case .noApplicationSupportDirectory:
            return "AudioPresetStore: kein Application-Support-Pfad verfügbar"
        case .write(let underlying):
            return "AudioPresetStore: Schreibfehler — \(underlying)"
        }
    }
}

enum AudioPresetStore {

    /// `~/Library/Application Support/HarmonyEngine3D/AudioPresets`.
    static func presetDirectory(fileManager: FileManager = .default) -> URL? {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport
            .appendingPathComponent("HarmonyEngine3D", isDirectory: true)
            .appendingPathComponent("AudioPresets", isDirectory: true)
    }

    /// Legt den Preset-Ordner an, falls er noch nicht existiert. Löscht/
    /// verändert nie vorhandene Dateien.
    @discardableResult
    static func ensurePresetDirectoryExists(at directory: URL? = nil, fileManager: FileManager = .default) -> URL? {
        guard let dir = directory ?? presetDirectory(fileManager: fileManager) else { return nil }
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Speichert `preset` atomisch als `<id>.json` im Preset-Ordner (legt
    /// den Ordner bei Bedarf an). Wirft `AudioPresetStoreError`/
    /// `AudioSynthPresetCodec.CodecError` bei Encode-/Schreibfehlern — kein
    /// Validator-Gate hier (Draft-Save-Vertrag wie `HarmonyMapDocumentStore`:
    /// Speichern ist erlaubt, auch mit Validator-Errors; ein Aufrufer, der
    /// nur fehlerfreie Presets speichern will, prüft vorher selbst über
    /// `AudioPresetValidator`).
    @discardableResult
    static func save(_ preset: AudioSynthPreset, in directory: URL? = nil,
                      fileManager: FileManager = .default) throws -> URL {
        guard let dir = ensurePresetDirectoryExists(at: directory, fileManager: fileManager) else {
            throw AudioPresetStoreError.noApplicationSupportDirectory
        }
        let url = dir.appendingPathComponent("\(preset.id).json")
        let data = try AudioSynthPresetCodec.encode(preset)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw AudioPresetStoreError.write(underlying: error)
        }
        return url
    }

    /// Lädt ein Preset anhand seiner `id` (Dateiname `<id>.json`). `nil`
    /// bei fehlender Datei oder Decode-Fehler — kein Crash bei defekten
    /// Dateien.
    static func load(id: String, in directory: URL? = nil, fileManager: FileManager = .default) -> AudioSynthPreset? {
        guard let dir = directory ?? presetDirectory(fileManager: fileManager) else { return nil }
        let url = dir.appendingPathComponent("\(id).json")
        return try? AudioSynthPresetCodec.decode(from: url)
    }

    /// Listet alle `.json`-Dateien im Preset-Ordner, stabil nach Dateiname
    /// sortiert. Ungültige/nicht dekodierbare Dateien werden NICHT
    /// ausgeschlossen, sondern mit `loadError` sichtbar markiert. Liefert
    /// `[]`, wenn der Ordner fehlt oder leer ist — kein Fehlerzustand.
    ///
    /// Im Default-Produktpfad (`directory == nil`) wird der Ordner bei
    /// Bedarf automatisch angelegt (wie `RuntimeMapImportStore`,
    /// Runde 041 / V-01.1) — ein explizit von Tests injiziertes
    /// `directory:` wird NIE automatisch angelegt.
    static func list(in directory: URL? = nil, fileManager: FileManager = .default) -> [AudioPresetIndexEntry] {
        let resolvedDirectory = directory ?? ensurePresetDirectoryExists(fileManager: fileManager)
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
                let preset = try AudioSynthPresetCodec.decode(from: url)
                return AudioPresetIndexEntry(fileName: fileName, displayName: preset.name, loadError: nil)
            } catch {
                return AudioPresetIndexEntry(fileName: fileName, displayName: fileName, loadError: "\(error)")
            }
        }
    }
}
