import Foundation

// MARK: – AudioSynthPresetCodec
//
// S-03: Decode-/Encode-Vertrag für `AudioSynthPreset`, im selben Stil wie
// `HarmonyMapCodec` (`HarmonyShared`). Striktes Decoding kommt allein aus
// `Codable`-Synthese über nicht-optionale Felder — kein `try?`, kein
// stiller Default bei falsch typisierten vorhandenen Feldern: ein Key mit
// falschem Typ lässt `JSONDecoder` werfen.
//
// Einzige Stelle, an der `AudioSynthPreset` aus `Data`/`URL` dekodiert und
// zu kanonischem JSON encodiert wird.

enum AudioSynthPresetCodec {

    enum CodecError: Error, CustomStringConvertible {
        case decode(underlying: Error)
        case encode(underlying: Error)

        var description: String {
            switch self {
            case .decode(let underlying):
                return "AudioSynthPresetCodec: Decode-Fehler — \(underlying)"
            case .encode(let underlying):
                return "AudioSynthPresetCodec: Encode-Fehler — \(underlying)"
            }
        }
    }

    /// Dekodiert ein Preset aus rohen JSON-Daten. Wirft bei defektem JSON
    /// oder falsch typisierten vorhandenen Feldern.
    static func decode(from data: Data) throws -> AudioSynthPreset {
        do {
            return try JSONDecoder().decode(AudioSynthPreset.self, from: data)
        } catch {
            throw CodecError.decode(underlying: error)
        }
    }

    /// Dekodiert ein Preset aus einer Datei-URL.
    static func decode(from url: URL) throws -> AudioSynthPreset {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CodecError.decode(underlying: error)
        }
        return try decode(from: data)
    }

    /// Encodiert ein Preset zu kanonischem JSON (sortierte Objekt-Keys,
    /// lesbar formatiert — deterministischer Diff/Roundtrip wie
    /// `HarmonyMapCodec.encode`).
    static func encode(_ preset: AudioSynthPreset) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(preset)
        } catch {
            throw CodecError.encode(underlying: error)
        }
    }
}
