import XCTest
import HarmonyShared

// MARK: – HarmonyMapCodecStrictDecodingTests
//
// Deckt HarmonyMapCodec (Decode aus Data, kanonisches Encode/Roundtrip) sowie
// das strikte Decoding-Verhalten aus HarmonyModel.swift ab (Runde 017 / F-03):
// fehlende optionale Felder bleiben erlaubt, vorhandene falsch typisierte
// optionale Felder werden jetzt Decode-Fehler statt still zu Default/nil zu
// werden (`decodeIfPresent` statt `try?`). Inline-JSON-Fixtures, kein Bezug
// auf Bundle-/App-Maps.

final class HarmonyMapCodecStrictDecodingTests: XCTestCase {

    private let validMapJSON = """
    {
      "schemaVersion": "1.0", "id": "strict-map", "name": "Strict",
      "layers": [{ "id": "L1", "name": "L1", "relationTypes": ["V-I"] }],
      "nodes": [
        { "id": "A", "root": 60, "type": "maj7", "function": "tonic",    "midiNotes": [60, 64, 67, 71] },
        { "id": "B", "root": 67, "type": "dom7", "function": "dominant", "midiNotes": [67, 71, 74, 77], "tags": ["test"] }
      ],
      "edges": [
        { "id": "B-A", "source": "B", "target": "A", "relationTypes": ["V-I"], "directed": true, "layers": ["L1"], "weight": 0.75 }
      ]
    }
    """

    // MARK: – Decode aus Data

    func test_decode_validMap_succeeds() throws {
        let map = try HarmonyMapCodec.decode(from: Data(validMapJSON.utf8))
        XCTAssertEqual(map.id, "strict-map")
        XCTAssertEqual(map.nodes.count, 2)
    }

    // MARK: – Kanonischer Encode/Decode-Roundtrip

    func test_encodeDecodeRoundtrip_preservesSemantics() throws {
        let original = try HarmonyMapCodec.decode(from: Data(validMapJSON.utf8))
        let encoded  = try HarmonyMapCodec.encode(original)
        let roundtripped = try HarmonyMapCodec.decode(from: encoded)

        XCTAssertEqual(roundtripped.id, original.id)
        XCTAssertEqual(roundtripped.nodes.map(\.id), original.nodes.map(\.id))
        XCTAssertEqual(roundtripped.nodes.first(where: { $0.id == "B" })?.tags, ["test"])
        XCTAssertEqual(roundtripped.edges.first?.weight, 0.75)
        XCTAssertEqual(roundtripped.edges.first?.relationTypes, original.edges.first?.relationTypes)
    }

    func test_encode_isDeterministic_sameInputSameOutput() throws {
        let map = try HarmonyMapCodec.decode(from: Data(validMapJSON.utf8))
        let encodedA = try HarmonyMapCodec.encode(map)
        let encodedB = try HarmonyMapCodec.encode(map)
        XCTAssertEqual(encodedA, encodedB)
    }

    // MARK: – Striktes Decoding: fehlendes optionales Feld bleibt erlaubt

    func test_decode_missingOptionalFields_succeedsWithDefaults() throws {
        // Node "A" hat kein tags/layout3D/layers, Edge kein weight/magnetProfile/bridgesTo.
        let map = try HarmonyMapCodec.decode(from: Data(validMapJSON.utf8))
        let nodeA = try XCTUnwrap(map.nodes.first { $0.id == "A" })
        XCTAssertEqual(nodeA.tags, [])
        XCTAssertNil(nodeA.layout3D)
        XCTAssertNil(nodeA.layers)
    }

    // MARK: – Striktes Decoding: vorhandenes falsch typisiertes optionales Feld scheitert

    func test_decode_wrongTypedNodeTags_throws() {
        let json = """
        {
          "schemaVersion": "1.0", "id": "bad-map", "name": "Bad",
          "layers": [], "nodes": [
            { "id": "A", "root": 60, "type": "maj7", "function": "tonic", "midiNotes": [60], "tags": "bad" }
          ],
          "edges": []
        }
        """
        XCTAssertThrowsError(try HarmonyMapCodec.decode(from: Data(json.utf8)))
    }

    func test_decode_wrongTypedEdgeWeight_throws() {
        let json = """
        {
          "schemaVersion": "1.0", "id": "bad-map", "name": "Bad",
          "layers": [{ "id": "L1", "name": "L1", "relationTypes": ["V-I"] }],
          "nodes": [
            { "id": "A", "root": 60, "type": "maj7", "function": "tonic", "midiNotes": [60] },
            { "id": "B", "root": 67, "type": "dom7", "function": "dominant", "midiNotes": [67] }
          ],
          "edges": [
            { "id": "B-A", "source": "B", "target": "A", "relationTypes": ["V-I"], "directed": true, "layers": ["L1"], "weight": "bad" }
          ]
        }
        """
        XCTAssertThrowsError(try HarmonyMapCodec.decode(from: Data(json.utf8)))
    }

    func test_decode_wrongTypedNodeLayout3D_throws() {
        let json = """
        {
          "schemaVersion": "1.0", "id": "bad-map", "name": "Bad",
          "layers": [], "nodes": [
            { "id": "A", "root": 60, "type": "maj7", "function": "tonic", "midiNotes": [60], "layout3D": "bad" }
          ],
          "edges": []
        }
        """
        XCTAssertThrowsError(try HarmonyMapCodec.decode(from: Data(json.utf8)))
    }
}
