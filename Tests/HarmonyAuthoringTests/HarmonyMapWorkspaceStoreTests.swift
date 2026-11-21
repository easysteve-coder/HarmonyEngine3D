import XCTest
@testable import HarmonyAuthoring
import HarmonyShared

final class HarmonyMapWorkspaceStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HarmonyAuthoringWorkspaceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: – Default state

    func test_load_withoutExistingSidecar_returnsDefaultState_noCrash() {
        let key = WorkspaceKey.unsaved(mapID: "does-not-exist")
        let state = HarmonyMapWorkspaceStore.load(for: key, in: tempDir)
        XCTAssertTrue(state.positions.isEmpty)
        XCTAssertTrue(state.pinnedNodeIDs.isEmpty)
        XCTAssertEqual(state.zoom, 1.0)
        XCTAssertNil(state.activeLayer)
    }

    // MARK: – Save/Load roundtrip

    func test_saveLoadRoundtrip_preservesPositionsPinsAndZoom() throws {
        let key = WorkspaceKey.unsaved(mapID: "roundtrip-map")
        var state = HarmonyMapWorkspaceState()
        state.setPosition(WorkspacePoint(x: 12.5, y: -7.25), forNodeID: "n1")
        state.setPosition(WorkspacePoint(x: 100, y: 200), forNodeID: "n2")
        state.togglePin("n1")
        state.zoom = 1.75
        state.activeLayer = "functional"

        try HarmonyMapWorkspaceStore.save(state, for: key, in: tempDir)
        let reloaded = HarmonyMapWorkspaceStore.load(for: key, in: tempDir)

        XCTAssertEqual(reloaded.position(forNodeID: "n1"), WorkspacePoint(x: 12.5, y: -7.25))
        XCTAssertEqual(reloaded.position(forNodeID: "n2"), WorkspacePoint(x: 100, y: 200))
        XCTAssertTrue(reloaded.isPinned("n1"))
        XCTAssertFalse(reloaded.isPinned("n2"))
        XCTAssertEqual(reloaded.zoom, 1.75)
        XCTAssertEqual(reloaded.activeLayer, "functional")
    }

    // MARK: – Key-Strategie

    func test_differentOrigins_produceDifferentStableSlugs() {
        let fileKeyA = WorkspaceKey(origin: .file(URL(fileURLWithPath: "/tmp/a.json")), mapID: "m")
        let fileKeyB = WorkspaceKey(origin: .file(URL(fileURLWithPath: "/tmp/b.json")), mapID: "m")
        let templateKey = WorkspaceKey(origin: .readOnlyTemplate(name: "reference-core"), mapID: "m")
        let unsavedKey  = WorkspaceKey(origin: .unsaved, mapID: "map-id-1")

        let slugs = [fileKeyA.stableSlug, fileKeyB.stableSlug, templateKey.stableSlug, unsavedKey.stableSlug]
        XCTAssertEqual(Set(slugs).count, slugs.count, "Alle vier Origin-Varianten müssen unterschiedliche Sidecar-Keys erzeugen")
    }

    func test_sameFileURL_producesStableSlugAcrossCalls() {
        let url = URL(fileURLWithPath: "/Users/test/Documents/my-map.json")
        let a = WorkspaceKey(origin: .file(url), mapID: "m").stableSlug
        let b = WorkspaceKey(origin: .file(url), mapID: "m").stableSlug
        XCTAssertEqual(a, b, "Derselbe File-Origin muss über mehrere Aufrufe/Prozessstarts hinweg denselben Slug ergeben")
    }

    func test_fileOrigin_savedUnderOneKey_isLoadableUnderSameKey_notUnderDifferentKey() throws {
        let urlA = URL(fileURLWithPath: "/tmp/map-a.json")
        let urlB = URL(fileURLWithPath: "/tmp/map-b.json")
        let keyA = WorkspaceKey(origin: .file(urlA), mapID: "m")
        let keyB = WorkspaceKey(origin: .file(urlB), mapID: "m")

        var state = HarmonyMapWorkspaceState()
        state.setPosition(WorkspacePoint(x: 1, y: 1), forNodeID: "n1")
        try HarmonyMapWorkspaceStore.save(state, for: keyA, in: tempDir)

        XCTAssertNotNil(HarmonyMapWorkspaceStore.load(for: keyA, in: tempDir).position(forNodeID: "n1"))
        XCTAssertNil(HarmonyMapWorkspaceStore.load(for: keyB, in: tempDir).position(forNodeID: "n1"))
    }

    // MARK: – Map-JSON bleibt frei von Workspace-Feldern

    func test_mapCodecEncoding_containsNoWorkspaceFieldNames() throws {
        let node = HarmonyNode(id: "n1", root: 0, type: .maj7, function: .tonic, midiNotes: [60, 64, 67, 71])
        let map = HarmonyMap(schemaVersion: "1.0", id: "m", name: "Test", layers: [], nodes: [node], edges: [])
        let data = try HarmonyMapCodec.encode(map)
        let json = String(data: data, encoding: .utf8) ?? ""

        for forbidden in ["positions", "pinnedNodeIDs", "zoom", "activeLayer"] {
            XCTAssertFalse(json.contains("\"\(forbidden)\""), "Map-JSON darf kein Workspace-Feld '\(forbidden)' enthalten")
        }
    }
}
