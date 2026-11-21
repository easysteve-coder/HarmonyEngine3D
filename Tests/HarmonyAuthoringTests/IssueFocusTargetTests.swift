import XCTest
@testable import HarmonyAuthoring

final class IssueFocusTargetTests: XCTestCase {

    func test_parse_nodePath_returnsNodeTarget() {
        XCTAssertEqual(IssueFocusTarget.parse(objectPath: "$.nodes[n1]"), .node(id: "n1"))
    }

    func test_parse_edgePath_returnsEdgeTarget() {
        XCTAssertEqual(IssueFocusTarget.parse(objectPath: "$.edges[e1]"), .edge(id: "e1"))
    }

    func test_parse_layerPath_returnsLayerTarget() {
        XCTAssertEqual(IssueFocusTarget.parse(objectPath: "$.layers[l1]"), .layer(id: "l1"))
    }

    func test_parse_schemaVersionPath_returnsGlobal() {
        XCTAssertEqual(IssueFocusTarget.parse(objectPath: "$.schemaVersion"), .global)
    }

    func test_parse_collectionPathsWithoutBracket_returnGlobal() {
        XCTAssertEqual(IssueFocusTarget.parse(objectPath: "$.nodes"), .global)
        XCTAssertEqual(IssueFocusTarget.parse(objectPath: "$.edges"), .global)
        XCTAssertEqual(IssueFocusTarget.parse(objectPath: "$.layers"), .global)
    }

    func test_parse_unknownOrMalformedPath_fallsBackToGlobal_doesNotCrash() {
        XCTAssertEqual(IssueFocusTarget.parse(objectPath: ""), .global)
        XCTAssertEqual(IssueFocusTarget.parse(objectPath: "not-a-path"), .global)
        XCTAssertEqual(IssueFocusTarget.parse(objectPath: "$.nodes["), .global)
        XCTAssertEqual(IssueFocusTarget.parse(objectPath: "$.nodes[]"), .global)
    }

    func test_parse_idsWithSpecialCharacters_areExtractedVerbatim() {
        XCTAssertEqual(IssueFocusTarget.parse(objectPath: "$.nodes[n-1_copy]"), .node(id: "n-1_copy"))
    }
}
