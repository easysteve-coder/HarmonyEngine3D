import XCTest
import HarmonyShared
@testable import HarmonyEngine3D

// MARK: – WorldSessionTests
//
// Deckt den Konstruktionsvertrag von WorldSession ab (Runde 020 / E-01):
// valide Map + existierender Layer gelingt, unbekannter Layer/leere
// Layer-Sicht/Validator-Errors scheitern sauber, Snapshot ist deterministisch
// und entspricht der aktiven Layer-Sicht der Map, GraphEngine und
// RuntimeHarmonik stammen aus derselben Session. Inline-JSON-Fixtures, kein
// Bezug auf Bundle-Maps außer der bereits committeten kleinen F-03-Fixture
// für den Bundle-Factory-Test. Keine SceneKit-/Rendering-Abhängigkeit.

final class WorldSessionTests: XCTestCase {

    private func decode(_ json: String) throws -> HarmonyMap {
        try HarmonyMapCodec.decode(from: Data(json.utf8))
    }

    private let validMapJSON = """
    {
      "schemaVersion": "1.0", "id": "session-map", "name": "Session",
      "layers": [{ "id": "L1", "name": "L1", "relationTypes": ["V-I", "ii-V"] }],
      "nodes": [
        { "id": "Dm7",   "root": 62, "type": "m7",   "function": "subdominant", "midiNotes": [62, 65, 69, 72] },
        { "id": "G7",    "root": 67, "type": "dom7", "function": "dominant",    "midiNotes": [67, 71, 74, 77] },
        { "id": "Cmaj7", "root": 60, "type": "maj7", "function": "tonic",       "midiNotes": [60, 64, 67, 71] }
      ],
      "edges": [
        { "id": "Dm7-G7",   "source": "Dm7", "target": "G7",    "relationTypes": ["ii-V"], "directed": true, "layers": ["L1"], "weight": 1.0 },
        { "id": "G7-Cmaj7", "source": "G7",  "target": "Cmaj7", "relationTypes": ["V-I"],  "directed": true, "layers": ["L1"], "weight": 1.0 }
      ]
    }
    """

    // MARK: – Erfolgsfall

    func test_init_validMapAndExistingLayer_succeeds() throws {
        let map = try decode(validMapJSON)
        let session = try WorldSession(map: map, activeLayer: "L1")

        XCTAssertEqual(session.activeLayer, "L1")
        XCTAssertEqual(Set(session.snapshot.nodeIDs), ["Dm7", "G7", "Cmaj7"])
        XCTAssertTrue(session.warnings.isEmpty)
    }

    // MARK: – Fehlerfälle

    func test_init_unknownLayer_throws() throws {
        let map = try decode(validMapJSON)
        XCTAssertThrowsError(try WorldSession(map: map, activeLayer: "does-not-exist")) { error in
            guard case WorldSessionError.unknownLayer(let layer) = error else {
                return XCTFail("erwarteter Fehler .unknownLayer, bekommen: \(error)")
            }
            XCTAssertEqual(layer, "does-not-exist")
        }
    }

    func test_init_validatorErrors_throwsInvalidMap() throws {
        // Edge referenziert einen nicht existierenden Node → Validator-Error.
        let json = """
        {
          "schemaVersion": "1.0", "id": "broken-map", "name": "Broken",
          "layers": [{ "id": "L1", "name": "L1", "relationTypes": ["V-I"] }],
          "nodes": [
            { "id": "A", "root": 60, "type": "maj7", "function": "tonic", "midiNotes": [60] }
          ],
          "edges": [
            { "id": "X-A", "source": "X", "target": "A", "relationTypes": ["V-I"], "directed": true, "layers": ["L1"], "weight": 1.0 }
          ]
        }
        """
        let map = try decode(json)
        XCTAssertThrowsError(try WorldSession(map: map, activeLayer: "L1")) { error in
            guard case WorldSessionError.invalidMap(let errorDescriptions) = error else {
                return XCTFail("erwarteter Fehler .invalidMap, bekommen: \(error)")
            }
            XCTAssertTrue(errorDescriptions.contains { $0.contains("edgeSourceUnknown") })
        }
    }

    func test_init_layerWithoutActiveNodes_throwsEmptyLayerView() throws {
        // "orphan"-Layer ist gültig (relationTypes nicht leer), hat aber keine
        // Kante/keinen explizit aktiven Node → Validator gibt nur eine
        // layerEmpty-WARNING (kein Error), WorldSession scheitert trotzdem
        // sauber mit .emptyLayerView, weil keine sinnvolle Node-Sicht entsteht.
        let json = """
        {
          "schemaVersion": "1.0", "id": "orphan-layer-map", "name": "OrphanLayer",
          "layers": [
            { "id": "L1",     "name": "L1",     "relationTypes": ["V-I"] },
            { "id": "orphan", "name": "Orphan", "relationTypes": ["commonTone"] }
          ],
          "nodes": [
            { "id": "A", "root": 60, "type": "maj7", "function": "tonic",    "midiNotes": [60] },
            { "id": "B", "root": 67, "type": "dom7", "function": "dominant", "midiNotes": [67] }
          ],
          "edges": [
            { "id": "B-A", "source": "B", "target": "A", "relationTypes": ["V-I"], "directed": true, "layers": ["L1"], "weight": 1.0 }
          ]
        }
        """
        let map = try decode(json)
        XCTAssertThrowsError(try WorldSession(map: map, activeLayer: "orphan")) { error in
            guard case WorldSessionError.emptyLayerView(let layer) = error else {
                return XCTFail("erwarteter Fehler .emptyLayerView, bekommen: \(error)")
            }
            XCTAssertEqual(layer, "orphan")
        }
    }

    // MARK: – Snapshot: deterministisch + entspricht aktiver Layer-Sicht

    func test_snapshot_isDeterministicAcrossInstances() throws {
        let map = try decode(validMapJSON)
        let sessionA = try WorldSession(map: map, activeLayer: "L1")
        let sessionB = try WorldSession(map: map, activeLayer: "L1")

        XCTAssertEqual(sessionA.snapshot.nodeIDs, sessionB.snapshot.nodeIDs)
        XCTAssertEqual(sessionA.snapshot.edges.map(\.id), sessionB.snapshot.edges.map(\.id))
    }

    func test_snapshot_matchesActiveLayerViewOfMap() throws {
        let map = try decode(validMapJSON)
        let session = try WorldSession(map: map, activeLayer: "L1")

        let expectedActiveIDs = map.activeNodeIDs(in: "L1")
        XCTAssertEqual(Set(session.snapshot.nodeIDs), expectedActiveIDs)
        XCTAssertEqual(Set(session.snapshot.nodes.map(\.id)), expectedActiveIDs)
        // Beide Kanten liegen vollständig in L1 zwischen aktiven Nodes.
        XCTAssertEqual(session.snapshot.edges.map(\.id).sorted(), ["Dm7-G7", "G7-Cmaj7"])
    }

    // MARK: – GraphEngine + RuntimeHarmonik aus derselben Session

    func test_graphEngineAndRuntimeHarmonik_shareSameMapAndLayer() throws {
        let map = try decode(validMapJSON)
        let session = try WorldSession(map: map, activeLayer: "L1", seed: 42)

        // GraphEngine direkt: G7 → Cmaj7 ist die einzige Transition von G7 aus in L1.
        let graphChoice = session.graphEngine.weightedChoice(from: "G7")
        XCTAssertEqual(graphChoice?.id, "Cmaj7")

        // RuntimeHarmonik nutzt intern dieselbe GraphEngine-Instanz — der Vorschlag
        // für denselben Ausgangsakkord muss übereinstimmen (kein separat
        // konstruierter, potenziell abweichender GraphEngine-Zustand).
        let decision = session.runtimeHarmonik.process(
            currentChord: "G7",
            localNodes: [LocalNode(id: "n1", chordName: "Cmaj7", position: .zero, distance: 10)]
        )
        XCTAssertEqual(decision.suggestedChord, "Cmaj7")
        XCTAssertEqual(decision.strategy, .magnetismCandidate)
    }

    // MARK: – Bundle-Factory

    func test_load_fromBundle_succeeds() throws {
        // Nutzt die kleine, bereits committete F-03-Testfixture (2 Nodes/1 Edge,
        // Layer "functional") statt einer der untracked App-Maps.
        let session = try WorldSession.load(named: "harmony-map-loader-test-fixture", activeLayer: "functional")
        XCTAssertEqual(session.map.id, "harmony-map-loader-test-fixture")
        XCTAssertFalse(session.snapshot.nodeIDs.isEmpty)
    }
}
