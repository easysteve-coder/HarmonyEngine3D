import XCTest
import HarmonyShared

// MARK: – HarmonyMapCodecTests
//
// Deckt Decode einer gültigen HarmonyMap sowie das Auflösungsverhalten von
// HarmonyGraphEngine für gerichtete/ungerichtete Kanten und Layerfilterung ab.
// Nutzt eine kleine Inline-Fixture (kein Bezug auf Bundle-/App-Maps).

final class HarmonyMapCodecTests: XCTestCase {

    private let mapJSON = """
    {
      "schemaVersion": "1.0",
      "id": "test-map",
      "name": "Test Map",
      "layers": [
        { "id": "L1", "name": "Layer 1", "relationTypes": ["V-I", "ii-V"] },
        { "id": "L2", "name": "Layer 2", "relationTypes": ["relMajMin"] }
      ],
      "nodes": [
        { "id": "A", "root": 60, "type": "maj7", "function": "tonic",       "midiNotes": [60, 64, 67, 71] },
        { "id": "B", "root": 62, "type": "m7",   "function": "subdominant", "midiNotes": [62, 65, 69, 72] },
        { "id": "C", "root": 67, "type": "dom7", "function": "dominant",    "midiNotes": [67, 71, 74, 77] }
      ],
      "edges": [
        { "id": "A-B-directed",   "source": "A", "target": "B", "relationTypes": ["V-I"],       "directed": true,  "layers": ["L1"], "weight": 1.0 },
        { "id": "B-C-undirected", "source": "B", "target": "C", "relationTypes": ["ii-V"],      "directed": false, "layers": ["L1"], "weight": 0.9 },
        { "id": "A-C-otherLayer", "source": "A", "target": "C", "relationTypes": ["relMajMin"], "directed": false, "layers": ["L2"], "weight": 0.5 }
      ],
      "layout": { "strategy": "manual" }
    }
    """

    private func decodeMap() throws -> HarmonyMap {
        try JSONDecoder().decode(HarmonyMap.self, from: Data(mapJSON.utf8))
    }

    func test_decode_validMap_succeeds() throws {
        let map = try decodeMap()
        XCTAssertEqual(map.id, "test-map")
        XCTAssertEqual(map.nodes.count, 3)
        XCTAssertEqual(map.edges.count, 3)
        XCTAssertEqual(map.layers.map(\.id), ["L1", "L2"])
    }

    func test_directedEdge_onlySourceToTarget() throws {
        let map = try decodeMap()
        let engine = HarmonyGraphEngine(map: map, initialLayer: "L1")

        XCTAssertTrue(engine.neighbors(of: "A").contains { $0.id == "B" })
        XCTAssertFalse(engine.neighbors(of: "B").contains { $0.id == "A" })
    }

    func test_undirectedEdge_bothDirections() throws {
        let map = try decodeMap()
        let engine = HarmonyGraphEngine(map: map, initialLayer: "L1")

        XCTAssertTrue(engine.neighbors(of: "B").contains { $0.id == "C" })
        XCTAssertTrue(engine.neighbors(of: "C").contains { $0.id == "B" })
    }

    func test_layerFiltering_excludesEdgesFromInactiveLayer() throws {
        let map = try decodeMap()

        let engineL1 = HarmonyGraphEngine(map: map, initialLayer: "L1")
        XCTAssertFalse(engineL1.neighbors(of: "A").contains { $0.id == "C" })

        let engineL2 = HarmonyGraphEngine(map: map, initialLayer: "L2")
        XCTAssertTrue(engineL2.neighbors(of: "A").contains { $0.id == "C" })
    }
}
