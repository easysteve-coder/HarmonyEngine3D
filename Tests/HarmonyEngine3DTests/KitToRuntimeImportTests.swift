import XCTest
import HarmonyShared
import HarmonyAuthoring
@testable import HarmonyEngine3D

// MARK: – KitToRuntimeImportTests
//
// Runde 040 / V-01, Scope C: vertikaler Nachweis "Kit-nahe Map -> externe
// Datei im Runtime-Importordner -> RuntimeMapImportStore -> WorldSession".
// `HarmonyAuthoring` ist ausschließlich in diesem Test-Target erlaubt
// (siehe Package.swift-Kommentar) — der Runtime-Produktcode
// (`Sources/HarmonyEngine3D`) importiert weder `HarmonyAuthoring` noch
// `DesignerKit`.

final class KitToRuntimeImportTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("he3d-kit-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: – Kit-Pfad: HarmonyMapDocumentStore.newDocument() + DiatonicHarmonyBuilder

    func test_kitBuilderMap_exportedToImportFolder_loadsThroughWorldSession() throws {
        // 1. Kit-nahe Map: genau der Pfad, den ein Autor im Construction Kit
        //    geht — neues Dokument (Default-Layer "functional") + Builder-
        //    Apply, wie in V-00a/K-08 etabliert.
        var doc = HarmonyMapDocumentStore.newDocument()
        let diff = DiatonicHarmonyBuilder.proposeDiff(
            for: doc.draft, config: HarmonyBuilderConfig(keyRoot: 0, layerID: "functional")
        )
        try doc.perform(ApplyHarmonyBuilderDiffCommand(diff: diff))
        guard let validated = doc.validatedSnapshot() else {
            return XCTFail("Kit-Map sollte nach Builder-Apply valide sein")
        }

        // 2. Export in den Runtime-Importordner — derselbe kanonische Codec-
        //    Pfad wie das Construction-Kit-Export-Gate (K-06).
        let fileName = "kit-export-test.json"
        let data = try HarmonyMapCodec.encode(validated.map)
        try data.write(to: tempDir.appendingPathComponent(fileName))

        // 3. Runtime-Importquelle listet die Datei als ladbar.
        let listed = RuntimeMapImportStore.listImportedMaps(in: tempDir)
        XCTAssertEqual(listed.map(\.fileName), [fileName])
        XCTAssertTrue(listed[0].isLoadable)

        // 4. Laden über RuntimeMapImportStore (nicht toChordNetwork).
        guard let loadedMap = RuntimeMapImportStore.load(fileName: fileName, in: tempDir) else {
            return XCTFail("Map sollte ueber den Importordner ladbar sein")
        }
        XCTAssertEqual(Set(loadedMap.nodes.map(\.id)), Set(validated.map.nodes.map(\.id)))
        XCTAssertEqual(Set(loadedMap.edges.map(\.id)), Set(validated.map.edges.map(\.id)))

        // 5. WorldSession — derselbe Konstruktionspfad wie fuer Bundle-Maps.
        let session = try WorldSession(map: loadedMap, activeLayer: "functional")
        XCTAssertEqual(session.activeLayer, "functional")
        XCTAssertFalse(session.snapshot.nodeIDs.isEmpty)
        XCTAssertEqual(Set(session.snapshot.nodes.map(\.id)), Set(validated.map.nodes.map(\.id)))

        // GraphEngine/RuntimeHarmonik teilen denselben Layer wie die Map/Scene.
        XCTAssertNotNil(session.graphEngine)
        XCTAssertNotNil(session.runtimeHarmonik)
    }

    // MARK: – Feldtreue: RelationTypes, Gewicht, MagnetProfile, MIDI-Noten, layout3D

    func test_canonicalMapFixture_allSemanticFields_surviveImportRoundtrip() throws {
        // Handgebautes, kanonisches Fixture mit allen in Scope C explizit
        // geforderten Feldern (layout3D/MagnetProfile werden vom aktuellen
        // K-08-Builder nicht gesetzt — dieser Test beweist die Feldtreue
        // unabhängig vom Builder-Funktionsumfang, direkt über Codec +
        // RuntimeMapImportStore + WorldSession).
        let nodeA = HarmonyNode(
            id: "Cmaj7", root: 0, type: .maj7, function: .tonic, midiNotes: [60, 64, 67, 71],
            tags: ["tonic-home"], layout3D: Layout3D(x: 10, y: -5, z: 42), layers: ["functional"]
        )
        let nodeB = HarmonyNode(
            id: "G7", root: 7, type: .dom7, function: .dominant, midiNotes: [67, 71, 74, 77],
            layout3D: Layout3D(x: -20, y: 0, z: 100)
        )
        let edge = HarmonyEdge(
            id: "G7-Cmaj7", source: "G7", target: "Cmaj7", relationTypes: [.vToI, .commonTone],
            directed: true, layers: ["functional"], weight: 0.85,
            magnetProfile: MagnetProfile(preset: .strong)
        )
        let layer = HarmonyLayer(id: "functional", name: "Functional", relationTypes: [.vToI, .commonTone])
        let fixture = HarmonyMap(
            schemaVersion: "1.0", id: "canonical-fixture", name: "Canonical Fixture",
            layers: [layer], nodes: [nodeA, nodeB], edges: [edge]
        )

        let fileName = "canonical-fixture.json"
        try HarmonyMapCodec.encode(fixture).write(to: tempDir.appendingPathComponent(fileName))

        guard let loadedMap = RuntimeMapImportStore.load(fileName: fileName, in: tempDir) else {
            return XCTFail("Fixture sollte ladbar sein")
        }

        let loadedNodeA = loadedMap.nodes.first { $0.id == "Cmaj7" }
        XCTAssertEqual(loadedNodeA?.midiNotes, [60, 64, 67, 71])
        XCTAssertEqual(loadedNodeA?.tags, ["tonic-home"])
        XCTAssertEqual(loadedNodeA?.layout3D?.x, 10)
        XCTAssertEqual(loadedNodeA?.layout3D?.y, -5)
        XCTAssertEqual(loadedNodeA?.layout3D?.z, 42)
        XCTAssertEqual(loadedNodeA?.layers, ["functional"])

        let loadedEdge = loadedMap.edges.first { $0.id == "G7-Cmaj7" }
        XCTAssertEqual(loadedEdge?.relationTypes, [.vToI, .commonTone])
        XCTAssertEqual(loadedEdge?.directed, true)
        XCTAssertEqual(loadedEdge?.weight, 0.85)
        XCTAssertEqual(loadedEdge?.magnetProfile?.preset, .strong)

        let session = try WorldSession(map: loadedMap, activeLayer: "functional")
        XCTAssertEqual(session.snapshot.edges.first?.id, "G7-Cmaj7")
        XCTAssertEqual(session.snapshot.edges.first?.magnetProfile?.preset, .strong)
    }

    // MARK: – toChordNetwork ist kein operativer Bestandteil dieses Pfads

    func test_runtimeMapImportStore_doesNotDependOnLegacyToChordNetwork() throws {
        // Positiver, ausführbarer Beleg statt reinem Grep-Argument: eine Map
        // ohne jede Legacy-kompatible Degradierungsmöglichkeit (mehrere
        // RelationTypes + ungerichtete Kante + MagnetProfile — genau die
        // Felder, die `HarmonyMapLoader.toChordNetwork` laut eigener Doku
        // verlustbehaftet exportieren würde) lädt unverändert durch
        // `RuntimeMapImportStore` + `WorldSession`.
        let nodeA = HarmonyNode(id: "A", root: 0, type: .maj7, function: .tonic, midiNotes: [60, 64, 67, 71])
        let nodeB = HarmonyNode(id: "B", root: 7, type: .dom7, function: .dominant, midiNotes: [67, 71, 74, 77])
        let edge = HarmonyEdge(
            id: "A-B", source: "A", target: "B", relationTypes: [.vToI, .commonTone],
            directed: false, layers: ["functional"], weight: 0.5,
            magnetProfile: MagnetProfile(preset: .weak)
        )
        let layer = HarmonyLayer(id: "functional", name: "Functional", relationTypes: [.vToI, .commonTone])
        let fixture = HarmonyMap(schemaVersion: "1.0", id: "no-legacy", name: "No Legacy", layers: [layer], nodes: [nodeA, nodeB], edges: [edge])

        let fileName = "no-legacy.json"
        try HarmonyMapCodec.encode(fixture).write(to: tempDir.appendingPathComponent(fileName))
        guard let loadedMap = RuntimeMapImportStore.load(fileName: fileName, in: tempDir) else {
            return XCTFail("Fixture sollte ladbar sein")
        }

        let session = try WorldSession(map: loadedMap, activeLayer: "functional")
        // WorldSession.snapshot.edges enthält die ORIGINALE HarmonyEdge samt
        // relationTypes/magnetProfile/directed — ein toChordNetwork-Export
        // hätte diese Felder auf source/target/weight reduziert (siehe
        // HarmonyMapLoader.toChordNetwork-Doku, "verliert beim Export").
        let sessionEdge = session.snapshot.edges.first
        XCTAssertEqual(sessionEdge?.relationTypes, [.vToI, .commonTone])
        XCTAssertEqual(sessionEdge?.directed, false)
        XCTAssertEqual(sessionEdge?.magnetProfile?.preset, .weak)
    }
}
