import Foundation

// MARK: – EchoFieldPresetCodec
//
// S-07b: Decode-/Encode-Vertrag fuer `EchoFieldPreset`, im selben Stil wie
// `AudioSynthPresetCodec`. Striktes Decoding kommt allein aus
// `Codable`-Synthese ueber nicht-optionale Felder – kein `try?`, kein
// stiller Default bei falsch typisierten vorhandenen Feldern.
//
// Einzige Stelle, an der `EchoFieldPreset` aus `Data`/`URL` dekodiert und zu
// kanonischem JSON encodiert wird.

enum EchoFieldPresetCodec {

    enum CodecError: Error, CustomStringConvertible {
        case decode(underlying: Error)
        case encode(underlying: Error)

        var description: String {
            switch self {
            case .decode(let underlying):
                return "EchoFieldPresetCodec: Decode-Fehler — \(underlying)"
            case .encode(let underlying):
                return "EchoFieldPresetCodec: Encode-Fehler — \(underlying)"
            }
        }
    }

    /// Dekodiert ein Preset aus rohen JSON-Daten. Wirft bei defektem JSON
    /// oder falsch typisierten vorhandenen Feldern.
    static func decode(from data: Data) throws -> EchoFieldPreset {
        do {
            return try JSONDecoder().decode(EchoFieldPreset.self, from: data)
        } catch {
            throw CodecError.decode(underlying: error)
        }
    }

    /// Dekodiert ein Preset aus einer Datei-URL.
    static func decode(from url: URL) throws -> EchoFieldPreset {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CodecError.decode(underlying: error)
        }
        return try decode(from: data)
    }

    /// Encodiert ein Preset zu kanonischem JSON (sortierte Objekt-Keys,
    /// lesbar formatiert – deterministischer Diff/Roundtrip wie
    /// `AudioSynthPresetCodec.encode`).
    static func encode(_ preset: EchoFieldPreset) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(preset)
        } catch {
            throw CodecError.encode(underlying: error)
        }
    }
}
