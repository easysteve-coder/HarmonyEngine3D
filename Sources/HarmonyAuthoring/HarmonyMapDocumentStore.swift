import Foundation
import HarmonyShared

// MARK: – HarmonyMapDocumentStore
//
// Dokument-I/O fuer `HarmonyMapDocument` (K-02): Neu anlegen, aus beliebiger
// JSON-URL oder Bundle-Resource oeffnen, atomisch speichern/Save As. Lesen/
// Schreiben laeuft ausschliesslich ueber `HarmonyMapCodec`. Draft-Save ist
// erlaubt, auch wenn `HarmonyMapValidator` Errors meldet — das
// Runtime-Export-Gate bleibt K-06, hier wird nur der Dokumentdraft
// persistiert.
//
// Kein SceneKit, kein AppSettings, kein UI.

public enum HarmonyMapDocumentStore {

    public enum StoreError: Error, CustomStringConvertible {
        /// Dokument hat noch keine Ziel-URL (frisch via `newDocument()`).
        /// `save()` verweigert das Schreiben — `saveAs(_:to:)` verwenden.
        case noSaveTarget
        /// Dokument ist ein read-only Bundle-Template. `save()` verweigert
        /// das Schreiben — `saveAs(_:to:)` erzeugt daraus eine normale Datei.
        case readOnlyTemplate
        case write(underlying: Error)

        public var description: String {
            switch self {
            case .noSaveTarget:
                return "HarmonyMapDocumentStore: kein Speicherziel — saveAs(_:to:) verwenden"
            case .readOnlyTemplate:
                return "HarmonyMapDocumentStore: Dokument ist ein read-only Template — saveAs(_:to:) verwenden"
            case .write(let underlying):
                return "HarmonyMapDocumentStore: Schreibfehler — \(underlying)"
            }
        }
    }

    // MARK: – Neu / Oeffnen

    /// Erzeugt ein neues, ungespeichertes Dokument mit einer minimal
    /// neutralen Draft-Map (keine musikalische Starter-Map-Entscheidung,
    /// keine Builder-Regel): `schemaVersion "1.0"`, frische UUID-basierte ID
    /// (kollisionsfrei, nicht reproduzierbar — "stabil" im Sinn von
    /// eindeutig, nicht im Sinn von konstant), leere Nodes/Edges.
    ///
    /// Layers enthaelt genau einen Default-Layer `functional` mit
    /// `relationTypes: [.commonTone]` (Runde 037 / V-00a, Stephan-Entscheidung):
    /// ohne mindestens einen vorhandenen Layer erzeugt der K-08-Diatonic-Builder
    /// layerlose, fuer `HarmonyGraphEngine` untraversierbare Kanten (Builder-A1,
    /// Fable-5-Review Runde 036). `functional` ist reine Dokument-/UX-Basis,
    /// keine neue musikalische Runtime-Regel — der Builder erzeugt seine
    /// Ring-Kanten ohnehin als `.commonTone` (siehe `DiatonicHarmonyBuilder`),
    /// daher deckt genau dieser eine RelationType den Default-Layer-Katalog ab.
    /// Darf Validator-Errors haben (hier: keine — ein leerer Layer erzeugt nur
    /// die `layerEmpty`-Warning, kein Error) und ist trotzdem speicherbar.
    public static func newDocument(name: String = "Untitled HarmonyWeb") -> HarmonyMapDocument {
        let defaultLayer = HarmonyLayer(id: "functional", name: "Functional", relationTypes: [.commonTone])
        let map = HarmonyMap(
            schemaVersion: "1.0",
            id: "untitled-\(UUID().uuidString)",
            name: name,
            layers: [defaultLayer],
            nodes: [],
            edges: [],
            layout: nil
        )
        return HarmonyMapDocument(map: map, origin: .unsaved)
    }

    /// Dekodiert eine HarmonyMap aus einer beliebigen JSON-Datei-URL.
    /// Wirft `HarmonyMapCodec.CodecError` bei Lese-/Decode-Fehlern — kein
    /// Validator-Gate, ein invalider Draft darf geoeffnet werden.
    public static func openDocument(at url: URL) throws -> HarmonyMapDocument {
        let map = try HarmonyMapCodec.decode(from: url)
        return HarmonyMapDocument(map: map, origin: .file(url))
    }

    /// Dekodiert eine HarmonyMap aus einer Bundle-Resource als read-only
    /// Template. Wirft `HarmonyMapCodec.CodecError` bei Lese-/Decode-Fehlern
    /// — kein Validator-Gate (Draft-Save-Vertrag gilt auch fuer Templates).
    public static func openBundledTemplate(named name: String, bundle: Bundle? = nil) throws -> HarmonyMapDocument {
        let map = try HarmonyMapCodec.decode(fromBundleResource: name, bundle: bundle)
        return HarmonyMapDocument(map: map, origin: .readOnlyTemplate(name: name))
    }

    // MARK: – Speichern

    /// Speichert an der bestehenden Datei-URL des Dokuments. Wirft
    /// `.noSaveTarget` fuer ein ungespeichertes Dokument und
    /// `.readOnlyTemplate` fuer ein Bundle-Template — beide Faelle
    /// schreiben nicht still, `saveAs(_:to:)` verwenden. Bei Erfolg:
    /// `document.isDirty == false`, `origin` bleibt/wird `.file(url)`.
    @discardableResult
    public static func save(_ document: inout HarmonyMapDocument) throws -> URL {
        switch document.origin {
        case .file(let url):
            try write(document.draft, to: url)
            document.markSaved(at: url)
            return url
        case .unsaved:
            throw StoreError.noSaveTarget
        case .readOnlyTemplate:
            throw StoreError.readOnlyTemplate
        }
    }

    /// Schreibt den Draft atomisch an `url`, unabhaengig vom bisherigen
    /// `origin` (ungespeichert, normale Datei oder read-only Template —
    /// ein Template wird dadurch zu einer normalen Datei). Bei Erfolg:
    /// `document.origin == .file(url)`, `document.isDirty == false`.
    @discardableResult
    public static func saveAs(_ document: inout HarmonyMapDocument, to url: URL) throws -> URL {
        try write(document.draft, to: url)
        document.markSaved(at: url)
        return url
    }

    /// Encodiert ueber `HarmonyMapCodec` (Fehler propagieren unveraendert als
    /// `HarmonyMapCodec.CodecError`, bereits strukturiert) und schreibt
    /// atomisch (`Data.write(..., options: .atomic)`) — nur echte
    /// Dateisystemfehler werden als `StoreError.write` typisiert.
    private static func write(_ map: HarmonyMap, to url: URL) throws {
        let data = try HarmonyMapCodec.encode(map)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw StoreError.write(underlying: error)
        }
    }
}
