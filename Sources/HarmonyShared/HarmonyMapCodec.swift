import Foundation

// MARK: – HarmonyMapCodec
//
// Öffentlicher Decode-/Encode-Vertrag für HarmonyMap (Runde 017 / F-03).
// Einzige Stelle, an der HarmonyMap aus Data/URL/Bundle-Resource dekodiert und
// zu kanonischem JSON encodiert wird — Engine (`HarmonyMapLoader`) und
// DesignerKit (später) nutzen denselben Pfad statt eigener `JSONDecoder`-Aufrufe.
//
// Striktes Decoding kommt aus `HarmonyMap`/`HarmonyNode`/`HarmonyEdge` selbst
// (`decodeIfPresent` statt `try?`, siehe HarmonyModel.swift) — dieser Typ fügt
// keine eigene Decode-Logik hinzu, nur die drei Eingabe-Pfade + kanonisches
// Encode.
//
// Kein SceneKit, kein AppSettings, kein UI.

public enum HarmonyMapCodec {

    public enum CodecError: Error, CustomStringConvertible {
        case fileNotFound(String)
        case decode(underlying: Error)
        case encode(underlying: Error)

        public var description: String {
            switch self {
            case .fileNotFound(let name):
                return "HarmonyMapCodec: Resource '\(name).json' nicht im Bundle gefunden"
            case .decode(let underlying):
                return "HarmonyMapCodec: Decode-Fehler — \(underlying)"
            case .encode(let underlying):
                return "HarmonyMapCodec: Encode-Fehler — \(underlying)"
            }
        }
    }

    // MARK: – Decode

    /// Dekodiert eine HarmonyMap aus rohen JSON-Daten.
    /// Wirft bei defektem JSON oder falsch typisierten vorhandenen optionalen
    /// Feldern (striktes Decoding, siehe HarmonyModel.swift).
    public static func decode(from data: Data) throws -> HarmonyMap {
        do {
            return try JSONDecoder().decode(HarmonyMap.self, from: data)
        } catch {
            throw CodecError.decode(underlying: error)
        }
    }

    /// Dekodiert eine HarmonyMap aus einer Datei-URL.
    public static func decode(from url: URL) throws -> HarmonyMap {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CodecError.decode(underlying: error)
        }
        return try decode(from: data)
    }

    /// Dekodiert eine HarmonyMap aus einer Bundle-Resource (`<name>.json`).
    /// `bundle: nil` (Default) → `Bundle.module` (HarmonyShared), dieselbe
    /// Wurzel, aus der `HarmonyMapLoader` bisher direkt gelesen hat (SPM
    /// `.process("Resources")` legt .json-Dateien an der Bundle-Wurzel ab,
    /// kein `subdirectory:`). `Bundle.module` ist SPM-generiert und `internal`
    /// — kann deshalb nicht direkt als Default-Parameterwert einer `public`
    /// Funktion stehen, daher der Umweg über `Bundle?`.
    public static func decode(fromBundleResource name: String, bundle: Bundle? = nil) throws -> HarmonyMap {
        let resolvedBundle = bundle ?? .module
        guard let url = resolvedBundle.url(forResource: name, withExtension: "json") else {
            throw CodecError.fileNotFound(name)
        }
        return try decode(from: url)
    }

    // MARK: – Encode

    /// Encodiert eine HarmonyMap zu kanonischem JSON.
    /// `sortedKeys`: deterministische Object-Key-Reihenfolge (Roundtrip-/Diff-
    /// stabil). Array-Reihenfolge (nodes/edges/layers/relationTypes/midiNotes)
    /// bleibt exakt die Modell-Reihenfolge — `JSONEncoder` sortiert Arrays nicht,
    /// nur Objekt-Keys. `prettyPrinted` für lesbare Autorentools-/Testausgabe.
    public static func encode(_ map: HarmonyMap) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(map)
        } catch {
            throw CodecError.encode(underlying: error)
        }
    }
}
