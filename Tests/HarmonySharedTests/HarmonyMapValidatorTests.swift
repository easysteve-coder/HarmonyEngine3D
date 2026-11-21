import XCTest
import HarmonyShared

// MARK: – HarmonyMapValidatorTests
//
// Deckt den strukturierten Validierungsvertrag ab (Runde 017 / F-03):
// gültige Map ohne Errors, mehrere gesammelte Errors in einem Lauf, Warnings
// blockieren die Runtime-Akzeptanz nicht, und die neue Layer-Katalog-vs-
// Edge-Zuordnung-Regel. Inline-JSON-Fixtures, kein Bezug auf Bundle-/App-Maps.

final class HarmonyMapValidatorTests: XCTestCase {

    private func decode(_ json: String) throws -> HarmonyMap {
        try HarmonyMapCodec.decode(from: Data(json.utf8))
    }

    // MARK: – Gültige Map: keine Errors

    func test_validate_validMap_noErrors() throws {
        let json = """
        {
          "schemaVersion": "1.0", "id": "valid-map", "name": "Valid",
          "layers": [{ "id": "L1", "name": "L1", "relationTypes": ["V-I"] }],
          "nodes": [
            { "id": "A", "root": 60, "type": "maj7", "function": "tonic",    "midiNotes": [60, 64, 67, 71] },
            { "id": "B", "root": 67, "type": "dom7", "function": "dominant", "midiNotes": [67, 71, 74, 77] }
          ],
          "edges": [
            { "id": "B-A", "source": "B", "target": "A", "relationTypes": ["V-I"], "directed": true, "layers": ["L1"], "weight": 1.0 }
          ]
        }
        """
        let map = try decode(json)
        let result = HarmonyMapValidator.validate(map)

        XCTAssertTrue(result.errors.isEmpty, "unerwartete Errors: \(result.errors)")
        XCTAssertTrue(result.isAcceptable)
    }

    // MARK: – Mehrere Errors in einem Lauf gesammelt

    func test_validate_collectsMultipleErrorsInOneRun() throws {
        // Zwei unabhängige Fehler gleichzeitig: doppelte Node-ID (via zwei Nodes
        // mit derselben id) UND eine Edge, die auf einen unbekannten Node zeigt.
        let json = """
        {
          "schemaVersion": "1.0", "id": "multi-error-map", "name": "MultiError",
          "layers": [],
          "nodes": [
            { "id": "A", "root": 60, "type": "maj7", "function": "tonic", "midiNotes": [60] },
            { "id": "A", "root": 62, "type": "m7",   "function": "tonic", "midiNotes": [] }
          ],
          "edges": [
            { "id": "X-A", "source": "X", "target": "A", "relationTypes": ["V-I"], "directed": true, "layers": [], "weight": 1.0 }
          ]
        }
        """
        let map = try decode(json)
        let result = HarmonyMapValidator.validate(map)

        let codes = Set(result.errors.map(\.code))
        XCTAssertTrue(codes.contains("duplicateNodeID"), "Codes: \(codes)")
        XCTAssertTrue(codes.contains("edgeSourceUnknown"), "Codes: \(codes)")
        XCTAssertTrue(codes.contains("nodeMidiNotesEmpty"), "Codes: \(codes)")
        XCTAssertGreaterThanOrEqual(result.errors.count, 3, "Validator soll nicht beim ersten Fehler abbrechen")
        XCTAssertFalse(result.isAcceptable)
    }

    // MARK: – Warnings blockieren Runtime-Akzeptanz nicht

    func test_validate_warningsDoNotBlockAcceptance() throws {
        let json = """
        {
          "schemaVersion": "1.0", "id": "warning-map", "name": "Warning",
          "layers": [
            { "id": "L1", "name": "L1", "relationTypes": ["V-I"] },
            { "id": "empty", "name": "Empty", "relationTypes": ["commonTone"] }
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
        let result = HarmonyMapValidator.validate(map)

        XCTAssertTrue(result.errors.isEmpty, "unerwartete Errors: \(result.errors)")
        XCTAssertTrue(result.warnings.contains { $0.code == "layerEmpty" }, "erwartete layerEmpty-Warning fehlt")
        XCTAssertTrue(result.isAcceptable, "Warnings duerfen die Runtime-Akzeptanz nicht blockieren")
    }

    // MARK: – Layer-Katalog vs. operative Edge-Zuordnung (Scope C)

    func test_validate_layerRelationTypeCatalogMismatch_isWarningNotError() throws {
        // Layer "L1" deklariert nur V-I, die einzige Kante in diesem Layer
        // traegt aber ii-V — Abweichung, Kante bleibt operative Quelle.
        let json = """
        {
          "schemaVersion": "1.0", "id": "mismatch-map", "name": "Mismatch",
          "layers": [{ "id": "L1", "name": "L1", "relationTypes": ["V-I"] }],
          "nodes": [
            { "id": "A", "root": 60, "type": "maj7", "function": "tonic",       "midiNotes": [60] },
            { "id": "B", "root": 62, "type": "m7",   "function": "subdominant", "midiNotes": [62] }
          ],
          "edges": [
            { "id": "B-A", "source": "B", "target": "A", "relationTypes": ["ii-V"], "directed": true, "layers": ["L1"], "weight": 1.0 }
          ]
        }
        """
        let map = try decode(json)
        let result = HarmonyMapValidator.validate(map)

        XCTAssertTrue(result.errors.isEmpty, "unerwartete Errors: \(result.errors)")
        let mismatch = result.warnings.first { $0.code == "layerRelationTypeCatalogMismatch" }
        XCTAssertNotNil(mismatch, "erwartete layerRelationTypeCatalogMismatch-Warning fehlt")
        XCTAssertTrue(mismatch?.message.contains("ii-V") == true, "Message: \(mismatch?.message ?? "nil")")
        XCTAssertTrue(result.isAcceptable)
    }

    func test_validate_layerRelationTypeCatalogMatches_noMismatchWarning() throws {
        let json = """
        {
          "schemaVersion": "1.0", "id": "match-map", "name": "Match",
          "layers": [{ "id": "L1", "name": "L1", "relationTypes": ["V-I"] }],
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
        let result = HarmonyMapValidator.validate(map)
        XCTAssertFalse(result.warnings.contains { $0.code == "layerRelationTypeCatalogMismatch" })
    }
}
