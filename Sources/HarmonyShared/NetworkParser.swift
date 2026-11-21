import Foundation

// MARK: – Datenmodell

public struct ChordData {
    public let name: String
    public let midiNotes: [Int]
    public init(name: String, midiNotes: [Int]) {
        self.name = name
        self.midiNotes = midiNotes
    }
}

public struct EdgeData {
    public let source: String
    public let target: String
    public let weight: Float
    public init(source: String, target: String, weight: Float) {
        self.source = source
        self.target = target
        self.weight = weight
    }
}

public struct ChordNetwork {
    public let chords: [ChordData]
    public let edges:  [EdgeData]
    public init(chords: [ChordData], edges: [EdgeData]) {
        self.chords = chords
        self.edges  = edges
    }
}

// MARK: – Netzwerk-Definitionen

public struct NetworkDefinition {
    public let index:       Int
    public let name:        String
    public let emoji:       String
    public let description: String
    public let filename:    String   // Basis-Dateiname ohne .txt, dient auch als Save-Schlüssel
    public var isCurated:   Bool
    public var fileURL:     URL?     // nil = Bundle.module, non-nil = User-Ordner

    public init(index: Int, name: String, emoji: String,
                description: String, filename: String,
                isCurated: Bool = false, fileURL: URL? = nil) {
        self.index       = index
        self.name        = name
        self.emoji       = emoji
        self.description = description
        self.filename    = filename
        self.isCurated   = isCurated
        self.fileURL     = fileURL
    }
}

// MARK: – Parser

public enum NetworkParser {

    // ── Eingebaute Netzwerke (Bundle) ──────────────────────────────────────

    private static let builtinDefinitions: [NetworkDefinition] = [
        NetworkDefinition(index: 0, name: "Jazz",          emoji: "🎷",
                          description: "ii–V–I · Modal Interchange · Tritonussub.",
                          filename: "network"),
        NetworkDefinition(index: 1, name: "Quintenzirkel", emoji: "🎸",
                          description: "I–IV–V · Dur/Moll · Rock & Pop",
                          filename: "network_quinten"),
        NetworkDefinition(index: 2, name: "Diatonisch",    emoji: "🎼",
                          description: "Stufenharmonik · Funktionen einer Durtonart",
                          filename: "network_diatonisch"),
        NetworkDefinition(index: 3, name: "Blues",         emoji: "🎵",
                          description: "I–IV–V Dominanten · 12-Bar Blues",
                          filename: "network_blues"),
        NetworkDefinition(index: 4, name: "Modal",         emoji: "🌊",
                          description: "Dorian · Lydisch · Mixolydisch",
                          filename: "network_modal"),
        NetworkDefinition(index: 5, name: "Romantik",       emoji: "🎻",
                          description: "Terzverwandte · Chromatische Medianten",
                          filename: "network_romantic"),
        NetworkDefinition(index: 6, name: "Harm. Moll",    emoji: "🕯️",
                          description: "Leittondominante · Flamenco · Übermäßige Sekunde",
                          filename: "network_harmonic_minor"),
        NetworkDefinition(index: 7, name: "Ganzton",       emoji: "🌀",
                          description: "Debussy · Symmetrische Skala · Kein Tonikagefühl",
                          filename: "network_wholetone"),
        NetworkDefinition(index: 8, name: "Status Quo",    emoji: "🤘",
                          description: "Whatever You Want",
                          filename: "network_statusquo",
                          isCurated: true),
        NetworkDefinition(index: 9,  name: "Coltrane",      emoji: "🌀",
                          description: "Giant Steps · Terzenpendel B–G–Eb · ii–V–I",
                          filename: "network_coltrane"),
        NetworkDefinition(index: 10, name: "Bach / Barock", emoji: "🎹",
                          description: "Quintfall-Sequenz · Picardische Terz · Neapolitaner",
                          filename: "network_bach"),
        NetworkDefinition(index: 11, name: "Steven Wilson", emoji: "🔮",
                          description: "mMaj7 · Porcupine Tree · Chromatische Medianten",
                          filename: "network_steven_wilson"),
        NetworkDefinition(index: 12, name: "Harmony Codex", emoji: "🪜",
                          description: "Dur→Moll→Quinte→… · 24 Akkorde · Infinite Staircase",
                          filename: "network_harmony_codex",
                          isCurated: true),
    ]

    // ── Benutzer-Netzwerke (User-Ordner, dynamisch) ────────────────────────

    /// Ordner: ~/Library/Application Support/Harmony2D/networks/
    public static var userNetworkFolder: URL? {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = appSupport.appendingPathComponent("Harmony2D/networks", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var _userDefinitions: [NetworkDefinition] = []

    /// Kombiniert eingebaute + Benutzer-Netzwerke
    public static var definitions: [NetworkDefinition] {
        builtinDefinitions + _userDefinitions
    }

    /// Scannt den User-Ordner und aktualisiert die Liste.
    /// Beim ersten Aufruf wird eine Vorlage angelegt.
    public static func refreshUserNetworks() {
        guard let dir = userNetworkFolder else { return }
        createTemplateIfNeeded(in: dir)

        let fm = FileManager.default
        let urls: [URL]
        do {
            urls = try fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.nameKey],
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension == "txt" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            print("⚠️  Konnte User-Netzwerk-Ordner nicht lesen: \(error)")
            _userDefinitions = []
            return
        }

        let base = builtinDefinitions.count
        _userDefinitions = urls.enumerated().map { (i, url) in
            let filename = url.deletingPathExtension().lastPathComponent
            let (name, emoji, description) = metadataFromFile(at: url)
            return NetworkDefinition(
                index: base + i,
                name: name,
                emoji: emoji,
                description: description,
                filename: filename,
                isCurated: false,
                fileURL: url
            )
        }

        if !_userDefinitions.isEmpty {
            print("📂  \(_userDefinitions.count) Benutzer-Netzwerk(e) gefunden:")
            _userDefinitions.forEach { print("    \($0.emoji) \($0.name) (\($0.filename).txt)") }
        }
    }

    // ── Metadaten aus Kommentaren lesen ───────────────────────────────────
    // Unterstützte Kommentarzeilen am Anfang der Datei:
    //   # name: Mein Song
    //   # emoji: 🎸
    //   # description: I–IV–V in C-Dur

    private static func metadataFromFile(at url: URL) -> (name: String, emoji: String, description: String) {
        let rawFilename = url.deletingPathExtension().lastPathComponent
        var name        = rawFilename
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
        var emoji       = "📄"
        var description = "Benutzerdefiniertes Netzwerk"

        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return (name, emoji, description)
        }
        for line in text.components(separatedBy: "\n").prefix(20) {
            let l = line.trimmingCharacters(in: .whitespaces)
            guard l.hasPrefix("#") else { break }   // Metadaten nur am Anfang
            if let v = tagValue(l, tag: "name")        { name        = v }
            if let v = tagValue(l, tag: "emoji")       { emoji       = v }
            if let v = tagValue(l, tag: "description") { description = v }
        }
        return (name, emoji, description)
    }

    private static func tagValue(_ line: String, tag: String) -> String? {
        let prefix = "# \(tag):"
        guard line.lowercased().hasPrefix(prefix.lowercased()) else { return nil }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }

    // ── Vorlage beim ersten Start anlegen ─────────────────────────────────

    private static func createTemplateIfNeeded(in dir: URL) {
        let templateURL = dir.appendingPathComponent("_vorlage.txt")
        guard !FileManager.default.fileExists(atPath: templateURL.path) else { return }
        let template = """
        # name: Mein Song
        # emoji: 🎸
        # description: Eigene Akkordfolge
        #
        # Format:
        #   chord <Name> <MIDI1> <MIDI2> <MIDI3> [<MIDI4>]
        #   neighbor <Quelle> <Ziel> <Gewicht 0.0–1.0>
        #
        # Beispiel – C-Dur / A-Moll Pop-Vierklang:

        chord C   60 64 67
        chord Am  69 72 76
        chord F   65 69 72
        chord G   67 71 74

        neighbor C  Am  1.0
        neighbor Am F   0.95
        neighbor F  G   0.95
        neighbor G  C   1.0
        neighbor C  F   0.9
        neighbor G  Am  0.85
        """
        try? template.write(to: templateURL, atomically: true, encoding: .utf8)
        print("📄  Netzwerk-Vorlage angelegt: \(templateURL.path)")
    }

    // MARK: – Laden

    /// Lädt ein Netzwerk per Index
    public static func load(index: Int) -> ChordNetwork {
        let def = definitions[max(0, min(index, definitions.count - 1))]

        // User-Netzwerk: direkt aus dem Dateisystem
        if let url = def.fileURL {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                print("⚠️  Konnte \(url.lastPathComponent) nicht lesen – Fallback auf Demo")
                return demo()
            }
            print("✅  \(def.name)-Netzwerk geladen (User: \(url.lastPathComponent))")
            return parse(text)
        }

        // Eingebautes Netzwerk: aus dem Bundle
        guard
            let url  = Bundle.module.url(forResource: def.filename, withExtension: "txt"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            print("⚠️  \(def.filename).txt nicht gefunden – Fallback auf Demo")
            return demo()
        }
        print("✅  \(def.name)-Netzwerk geladen (\(def.filename).txt)")
        return parse(text)
    }

    /// Lädt das Jazz-Standardnetzwerk
    public static func loadFromBundle() -> ChordNetwork { load(index: 0) }

    // MARK: – Parser

    /// Parst einen String im chord/neighbor-Format
    public static func parse(_ content: String) -> ChordNetwork {
        var chordMap: [String: [Int]] = [:]
        var edges: [EdgeData] = []

        for raw in content.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }

            switch parts[0] {
            case "chord":
                guard parts.count >= 3 else { continue }
                chordMap[parts[1]] = parts[2...].compactMap { Int($0) }

            case "neighbor":
                guard parts.count >= 4 else { continue }
                edges.append(EdgeData(
                    source: parts[1],
                    target: parts[2],
                    weight: Float(parts[3]) ?? 1.0
                ))

            default:
                break
            }
        }

        let chords = chordMap
            .map { ChordData(name: $0.key, midiNotes: $0.value) }
            .sorted { $0.name < $1.name }

        print("   \(chords.count) Akkorde, \(edges.count) Verbindungen")
        return ChordNetwork(chords: chords, edges: edges)
    }

    // MARK: – Fallback Demo

    public static func demo() -> ChordNetwork {
        let chords = [
            ChordData(name: "Cmaj7", midiNotes: [60, 64, 67, 71]),
            ChordData(name: "Am7",   midiNotes: [69, 72, 76, 79]),
            ChordData(name: "Fmaj7", midiNotes: [65, 69, 72, 76]),
            ChordData(name: "G7",    midiNotes: [67, 71, 74, 77]),
        ]
        let edges = [
            EdgeData(source: "Cmaj7", target: "Am7",   weight: 1.0),
            EdgeData(source: "Am7",   target: "Fmaj7", weight: 0.9),
            EdgeData(source: "Fmaj7", target: "G7",    weight: 0.9),
            EdgeData(source: "G7",    target: "Cmaj7", weight: 1.0),
        ]
        return ChordNetwork(chords: chords, edges: edges)
    }
}
