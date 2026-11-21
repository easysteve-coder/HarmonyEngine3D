import Foundation

// MARK: – WorkspaceKey
//
// Stabiler Sidecar-Schluessel pro Dokumentursprung (K-03, Scope A):
//   - `.file`: normalisierte Datei-URL (deterministisch gehasht fuer den
//     Dateinamen — siehe `stableHash`, NICHT `String.hashValue`/`Hasher`,
//     die Swift pro Prozessstart zufaellig salzen (DoS-Schutz) und damit
//     bei jedem Neustart einen anderen Sidecar-Dateinamen ergeben wuerden).
//   - `.template`: Template-Name (Bundle-Templates sind pro Name eindeutig).
//   - `.unsaved`: Map-ID (gilt nur fuer die laufende Session — ein neues
//     Dokument hat bei jedem `newDocument()`-Aufruf ohnehin eine frische ID).

public enum WorkspaceKey: Equatable {
    case file(URL)
    case template(name: String)
    case unsaved(mapID: String)

    public init(origin: DocumentOrigin, mapID: String) {
        switch origin {
        case .file(let url):              self = .file(url)
        case .readOnlyTemplate(let name): self = .template(name: name)
        case .unsaved:                    self = .unsaved(mapID: mapID)
        }
    }

    /// Dateiname-Stamm (ohne Extension) fuer den Sidecar — stabil ueber
    /// Prozessneustarts hinweg fuer denselben Schluessel.
    var stableSlug: String {
        switch self {
        case .file(let url):
            return "file-\(Self.stableHash(url.standardizedFileURL.path))"
        case .template(let name):
            return "template-\(Self.sanitize(name))"
        case .unsaved(let mapID):
            return "unsaved-\(Self.sanitize(mapID))"
        }
    }

    private static func sanitize(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }

    /// Deterministischer FNV-1a-Hash — bewusst kein `String.hashValue`.
    private static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }
}

// MARK: – HarmonyMapWorkspaceStore
//
// Persistiert `HarmonyMapWorkspaceState` als JSON-Sidecar in Application
// Support — nie in der `HarmonyMap`, nie als neues Map-JSON-Schema-Feld.
// Kein Security-Scoped Bookmark, kein neues Entitlement.

public enum HarmonyMapWorkspaceStore {

    public enum StoreError: Error, CustomStringConvertible {
        case write(underlying: Error)
        public var description: String {
            switch self {
            case .write(let underlying):
                return "HarmonyMapWorkspaceStore: Schreibfehler — \(underlying)"
            }
        }
    }

    /// `Application Support/HarmonyAuthoring/Workspaces`. Faellt bei nicht
    /// auflösbarem Application-Support-Pfad auf ein temporaeres Verzeichnis
    /// zurueck (bewusst kein Crash fuer ein reines Komfort-Feature).
    public static func defaultDirectory(fileManager: FileManager = .default) -> URL {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("HarmonyAuthoring/Workspaces", isDirectory: true)
    }

    /// Laedt den Workspace fuer `key`. Liefert einen sauberen Default-State
    /// (keine Positionen, Zoom 1.0), wenn noch kein Sidecar existiert oder
    /// er nicht dekodierbar ist — kein Error-Pfad fuer ein reines
    /// Komfort-Feature.
    public static func load(for key: WorkspaceKey, in directory: URL = HarmonyMapWorkspaceStore.defaultDirectory()) -> HarmonyMapWorkspaceState {
        let url = fileURL(for: key, in: directory)
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(HarmonyMapWorkspaceState.self, from: data)
        else {
            return HarmonyMapWorkspaceState()
        }
        return state
    }

    /// Speichert `state` atomisch fuer `key`. Wirft `StoreError.write` bei
    /// echten Encode-/Dateisystemfehlern.
    public static func save(
        _ state: HarmonyMapWorkspaceState, for key: WorkspaceKey,
        in directory: URL = HarmonyMapWorkspaceStore.defaultDirectory()
    ) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw StoreError.write(underlying: error)
        }
        let data: Data
        do {
            data = try JSONEncoder().encode(state)
        } catch {
            throw StoreError.write(underlying: error)
        }
        do {
            try data.write(to: fileURL(for: key, in: directory), options: .atomic)
        } catch {
            throw StoreError.write(underlying: error)
        }
    }

    static func fileURL(for key: WorkspaceKey, in directory: URL) -> URL {
        directory.appendingPathComponent("\(key.stableSlug).json")
    }
}
