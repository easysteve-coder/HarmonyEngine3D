import Foundation

// MARK: – RecentDocumentsStore
//
// Kleine Recent-Documents-Komponente (K-02, Scope B): haelt eine
// URL-Liste (neueste zuerst, dedupliziert, auf `limit` begrenzt) in
// `UserDefaults`. Nur normale Datei-Open/Save-As-Erfolge werden erfasst —
// Bundle-Templates fuehren bewusst KEIN separates Template-Recent (siehe
// Ruecklauf-Begruendung K-02: eine zweite parallele Liste/UI-Flaeche waere
// vor einer echten Recent-Documents-UI verfrueht, bleibt offen fuer
// K-03/K-06).
//
// Kein SceneKit, kein AppSettings, kein UI. Testbare Injection ueber
// `defaults`/`key`/`limit`.

public struct RecentDocumentsStore {
    private let defaults: UserDefaults
    private let key: String
    private let limit: Int

    public init(defaults: UserDefaults = .standard, key: String = "HarmonyAuthoring.RecentDocuments.v1", limit: Int = 10) {
        self.defaults = defaults
        self.key = key
        self.limit = limit
    }

    /// Neueste zuerst.
    public func recentURLs() -> [URL] {
        let raw = defaults.stringArray(forKey: key) ?? []
        return raw.compactMap { URL(string: $0) }
    }

    /// Setzt `url` an den Anfang (entfernt einen vorhandenen Eintrag zuerst
    /// — kein Duplikat), schneidet danach auf `limit`.
    public func record(_ url: URL) {
        var urls = recentURLs()
        urls.removeAll { $0 == url }
        urls.insert(url, at: 0)
        if urls.count > limit {
            urls = Array(urls.prefix(limit))
        }
        defaults.set(urls.map { $0.absoluteString }, forKey: key)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }
}
