import XCTest
import HarmonyShared

// MARK: – HarmonyMapLoaderTests
//
// Deckt `HarmonyMapLoader.load(named:)` als dünnen Adapter über
// `HarmonyMapCodec`/`HarmonyMapValidator` ab (Runde 017 / F-03). Nutzt eine
// eigene, kleine, committete Bundle-Fixture
// (`Resources/maps/harmony-map-loader-test-fixture.json`) — bewusst NICHT
// die bestehenden untracked Bundle-Maps (`harmony-web-c-center.json`,
// `harmony-web-c-diatonic.json`), wie im Handoff gefordert.

final class HarmonyMapLoaderTests: XCTestCase {

    func test_load_validFixture_succeeds() throws {
        let map = try XCTUnwrap(HarmonyMapLoader.load(named: "harmony-map-loader-test-fixture"))
        XCTAssertEqual(map.id, "harmony-map-loader-test-fixture")
        XCTAssertEqual(map.nodes.count, 2)
        XCTAssertEqual(map.edges.count, 1)
    }

    func test_load_unknownFilename_returnsNil() {
        XCTAssertNil(HarmonyMapLoader.load(named: "does-not-exist-fixture"))
    }
}
