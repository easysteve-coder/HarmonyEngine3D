import XCTest
import HarmonyShared
@testable import HarmonyEngine3D

// MARK: – RuntimeMapImportStoreTests
//
// Runde 040 / V-01, Scope A: Runtime-Importordner + Map-Quelle. Alle Tests
// nutzen ein temporäres Verzeichnis über den injizierbaren `directory:`-
// Parameter — nie den echten Application-Support-Pfad des Testrechners.

// MARK: – RedirectingFileManager
//
// Runde 041 / V-01.1: leitet `.applicationSupportDirectory` auf ein
// temporäres Testverzeichnis um, damit der Default-Produktpfad
// (`directory: nil`) geprüft werden kann, ohne den echten
// Application-Support-Ordner des Testrechners anzufassen.
private final class RedirectingFileManager: FileManager {
    let redirectedApplicationSupport: URL

    init(redirectedApplicationSupport: URL) {
        self.redirectedApplicationSupport = redirectedApplicationSupport
    }

    override func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
        if directory == .applicationSupportDirectory {
            return [redirectedApplicationSupport]
        }
        return super.urls(for: directory, in: domainMask)
    }
}

final class RuntimeMapImportStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("he3d-import-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeValidMap(id: String = "test-map", name: String = "Test") -> HarmonyMap {
        let nodeA = HarmonyNode(id: "n1", root: 0, type: .maj7, function: .tonic, midiNotes: [60, 64, 67, 71])
        let nodeB = HarmonyNode(id: "n2", root: 5, type: .dom7, function: .dominant, midiNotes: [65, 69, 72, 75])
        let edge  = HarmonyEdge(id: "e1", source: "n1", target: "n2", relationTypes: [.vToI], directed: true, layers: ["functional"])
        let layer = HarmonyLayer(id: "functional", name: "Functional", relationTypes: [.vToI])
        return HarmonyMap(schemaVersion: "1.0", id: id, name: name, layers: [layer], nodes: [nodeA, nodeB], edges: [edge])
    }

    // MARK: – importDirectory / ensureImportDirectoryExists

    func test_importDirectory_pointsUnderApplicationSupport() {
        let dir = RuntimeMapImportStore.importDirectory()
        XCTAssertNotNil(dir)
        XCTAssertTrue(dir!.path.contains("HarmonyEngine3D/HarmonyWeb/Maps"))
    }

    func test_ensureImportDirectoryExists_createsDirectory_withoutDeletingExistingFiles() throws {
        let dir = tempDir.appendingPathComponent("Maps", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))

        RuntimeMapImportStore.ensureImportDirectoryExists(at: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))

        // Existierende Datei bleibt erhalten, wenn ensure erneut aufgerufen wird.
        let marker = dir.appendingPathComponent("marker.json")
        try Data("{}".utf8).write(to: marker)
        RuntimeMapImportStore.ensureImportDirectoryExists(at: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
    }

    // MARK: – listImportedMaps: Default-Produktpfad legt Ordner an (Runde 041 / V-01.1)

    func test_listImportedMaps_defaultProductPath_autoCreatesMissingImportDirectory() throws {
        let fakeAppSupport = tempDir.appendingPathComponent("AppSupport", isDirectory: true)
        let fm = RedirectingFileManager(redirectedApplicationSupport: fakeAppSupport)
        let expectedDir = RuntimeMapImportStore.importDirectory(fileManager: fm)!
        XCTAssertFalse(fm.fileExists(atPath: expectedDir.path))

        // `directory: nil` (Default-Parameter) -> Produktpfad, kein Test-Directory injiziert.
        XCTAssertTrue(RuntimeMapImportStore.listImportedMaps(fileManager: fm).isEmpty)
        XCTAssertTrue(fm.fileExists(atPath: expectedDir.path), "Der Produktpfad muss den fehlenden Importordner automatisch anlegen")
    }

    func test_listImportedMaps_explicitMissingDirectory_isNotAutoCreated() {
        // Ein von Tests explizit injiziertes, fehlendes `directory:` darf NICHT
        // automatisch angelegt werden — sonst waere der No-Crash-Pfad fuer ein
        // fehlendes Testverzeichnis nicht mehr isoliert testbar (siehe
        // `test_listImportedMaps_missingDirectory_returnsEmptyArray_noCrash`).
        let missing = tempDir.appendingPathComponent("does-not-exist-explicit", isDirectory: true)
        XCTAssertTrue(RuntimeMapImportStore.listImportedMaps(in: missing).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }

    func test_listImportedMaps_defaultProductPath_doesNotDeleteExistingFiles() throws {
        let fakeAppSupport = tempDir.appendingPathComponent("AppSupport2", isDirectory: true)
        let fm = RedirectingFileManager(redirectedApplicationSupport: fakeAppSupport)
        let expectedDir = RuntimeMapImportStore.importDirectory(fileManager: fm)!

        // Ordner existiert bereits mit einer validen Map-Datei, bevor Listing aufgerufen wird.
        try fm.createDirectory(at: expectedDir, withIntermediateDirectories: true)
        let data = try HarmonyMapCodec.encode(makeValidMap(name: "Vorhandene Map"))
        let existingFile = expectedDir.appendingPathComponent("existing.json")
        try data.write(to: existingFile)

        let listed = RuntimeMapImportStore.listImportedMaps(fileManager: fm)
        XCTAssertEqual(listed.map(\.fileName), ["existing.json"])
        XCTAssertTrue(fm.fileExists(atPath: existingFile.path), "Bestehende Datei darf beim automatischen Anlegen/Listing nie geloescht werden")
    }

    // MARK: – listImportedMaps

    func test_listImportedMaps_emptyDirectory_returnsEmptyArray() {
        XCTAssertTrue(RuntimeMapImportStore.listImportedMaps(in: tempDir).isEmpty)
    }

    func test_listImportedMaps_missingDirectory_returnsEmptyArray_noCrash() {
        let missing = tempDir.appendingPathComponent("does-not-exist", isDirectory: true)
        XCTAssertTrue(RuntimeMapImportStore.listImportedMaps(in: missing).isEmpty)
    }

    func test_listImportedMaps_ignoresNonJSONFiles() throws {
        try Data("not json".utf8).write(to: tempDir.appendingPathComponent("readme.txt"))
        let data = try HarmonyMapCodec.encode(makeValidMap())
        try data.write(to: tempDir.appendingPathComponent("valid.json"))

        let listed = RuntimeMapImportStore.listImportedMaps(in: tempDir)
        XCTAssertEqual(listed.map(\.fileName), ["valid.json"])
    }

    func test_listImportedMaps_sortsStablyByFileName() throws {
        let data = try HarmonyMapCodec.encode(makeValidMap())
        for name in ["c.json", "a.json", "b.json"] {
            try data.write(to: tempDir.appendingPathComponent(name))
        }
        let listed = RuntimeMapImportStore.listImportedMaps(in: tempDir)
        XCTAssertEqual(listed.map(\.fileName), ["a.json", "b.json", "c.json"])
    }

    func test_listImportedMaps_validFile_isLoadableWithDisplayName() throws {
        let data = try HarmonyMapCodec.encode(makeValidMap(name: "My HarmonyWeb"))
        try data.write(to: tempDir.appendingPathComponent("my-web.json"))

        let listed = RuntimeMapImportStore.listImportedMaps(in: tempDir)
        XCTAssertEqual(listed.count, 1)
        XCTAssertTrue(listed[0].isLoadable)
        XCTAssertNil(listed[0].loadError)
        XCTAssertEqual(listed[0].displayName, "My HarmonyWeb")
    }

    // MARK: – Ungültige/nicht dekodierbare Dateien: kein Crash

    func test_listImportedMaps_undecodableFile_isListedButNotLoadable() throws {
        try Data("{ this is not valid json".utf8).write(to: tempDir.appendingPathComponent("broken.json"))

        let listed = RuntimeMapImportStore.listImportedMaps(in: tempDir)
        XCTAssertEqual(listed.count, 1)
        XCTAssertFalse(listed[0].isLoadable)
        XCTAssertNotNil(listed[0].loadError)
        XCTAssertEqual(listed[0].displayName, "broken.json", "Ohne dekodierbaren Namen faellt displayName auf den Dateinamen zurueck")
    }

    func test_listImportedMaps_schemaValidationError_isListedButNotLoadable() throws {
        // Deckt Validator-Errors ab (z. B. nicht unterstuetzte schemaVersion),
        // nicht nur Decode-Fehler.
        let node = HarmonyNode(id: "n1", root: 0, type: .maj7, function: .tonic, midiNotes: [60, 64, 67, 71])
        let invalidMap = HarmonyMap(schemaVersion: "0.9", id: "bad", name: "Bad", layers: [], nodes: [node], edges: [])
        let data = try HarmonyMapCodec.encode(invalidMap)
        try data.write(to: tempDir.appendingPathComponent("bad-schema.json"))

        let listed = RuntimeMapImportStore.listImportedMaps(in: tempDir)
        XCTAssertEqual(listed.count, 1)
        XCTAssertFalse(listed[0].isLoadable)
    }

    // MARK: – load(fileName:): kein Crash, sauberer Fallback

    func test_load_validFile_succeeds() throws {
        let data = try HarmonyMapCodec.encode(makeValidMap(id: "kit-map"))
        try data.write(to: tempDir.appendingPathComponent("kit-map.json"))

        let loaded = RuntimeMapImportStore.load(fileName: "kit-map.json", in: tempDir)
        XCTAssertEqual(loaded?.id, "kit-map")
    }

    func test_load_missingFile_returnsNil_noCrash() {
        XCTAssertNil(RuntimeMapImportStore.load(fileName: "does-not-exist.json", in: tempDir))
    }

    func test_load_undecodableFile_returnsNil_noCrash() throws {
        try Data("{ broken".utf8).write(to: tempDir.appendingPathComponent("broken.json"))
        XCTAssertNil(RuntimeMapImportStore.load(fileName: "broken.json", in: tempDir))
    }

    func test_load_validatorErrors_returnsNil_noCrash() throws {
        let node = HarmonyNode(id: "n1", root: 0, type: .maj7, function: .tonic, midiNotes: [60, 64, 67, 71])
        let invalidMap = HarmonyMap(schemaVersion: "0.9", id: "bad", name: "Bad", layers: [], nodes: [node], edges: [])
        let data = try HarmonyMapCodec.encode(invalidMap)
        try data.write(to: tempDir.appendingPathComponent("bad-schema.json"))

        XCTAssertNil(RuntimeMapImportStore.load(fileName: "bad-schema.json", in: tempDir))
    }
}
