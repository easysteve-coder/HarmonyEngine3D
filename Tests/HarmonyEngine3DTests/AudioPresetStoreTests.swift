import XCTest
@testable import HarmonyEngine3D

// MARK: – AudioPresetStoreTests
//
// S-03: `AudioPresetStore` — atomisches Schreiben, Laden, deterministisches
// Listing (mit `directory:`-Injection, wie `RuntimeMapImportStoreTests`),
// sowie der Nachweis, dass Produktdefaults/UserDefaults unberührt bleiben.

final class AudioPresetStoreTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioPresetStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    private func preset(id: String, name: String) -> AudioSynthPreset {
        ChannelFXConfig.chordDefaults.audioSynthPreset(id: id, name: name, channelRole: .chord)
    }

    // MARK: – 7. Schreibt atomisch, laedt wieder, listet deterministisch

    func test_save_thenLoad_roundtripsExactly() throws {
        let original = preset(id: "user.one", name: "User One")
        let url = try AudioPresetStore.save(original, in: tempDirectory)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(url.lastPathComponent, "user.one.json")

        let loaded = AudioPresetStore.load(id: "user.one", in: tempDirectory)
        XCTAssertEqual(loaded, original)
    }

    func test_list_isEmptyForMissingDirectory_noCrash() {
        // tempDirectory existiert bewusst noch nicht (kein save() zuvor).
        let entries = AudioPresetStore.list(in: tempDirectory)
        XCTAssertEqual(entries, [])
    }

    func test_list_afterMultipleSaves_isSortedByFileNameAndDeterministic() throws {
        _ = try AudioPresetStore.save(preset(id: "zeta", name: "Zeta"), in: tempDirectory)
        _ = try AudioPresetStore.save(preset(id: "alpha", name: "Alpha"), in: tempDirectory)
        _ = try AudioPresetStore.save(preset(id: "mu", name: "Mu"), in: tempDirectory)

        let entries = AudioPresetStore.list(in: tempDirectory)
        XCTAssertEqual(entries.map(\.fileName), ["alpha.json", "mu.json", "zeta.json"])
        XCTAssertEqual(entries.map(\.displayName), ["Alpha", "Mu", "Zeta"])
        XCTAssertTrue(entries.allSatisfy(\.isLoadable))

        // Determinismus: zweiter Aufruf liefert exakt dieselbe Reihenfolge.
        let entriesAgain = AudioPresetStore.list(in: tempDirectory)
        XCTAssertEqual(entries.map(\.fileName), entriesAgain.map(\.fileName))
    }

    func test_list_marksUndecodableFileWithLoadErrorInsteadOfCrashing() throws {
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let brokenURL = tempDirectory.appendingPathComponent("broken.json")
        try Data("not valid json".utf8).write(to: brokenURL)

        let entries = AudioPresetStore.list(in: tempDirectory)
        XCTAssertEqual(entries.count, 1)
        XCTAssertFalse(entries[0].isLoadable)
        XCTAssertNotNil(entries[0].loadError)
    }

    func test_save_overwritesExistingFileAtomically() throws {
        _ = try AudioPresetStore.save(preset(id: "user.one", name: "Version 1"), in: tempDirectory)
        _ = try AudioPresetStore.save(preset(id: "user.one", name: "Version 2"), in: tempDirectory)

        let loaded = AudioPresetStore.load(id: "user.one", in: tempDirectory)
        XCTAssertEqual(loaded?.name, "Version 2")
        XCTAssertEqual(AudioPresetStore.list(in: tempDirectory).count, 1, "Ueberschreiben darf keine Zweitdatei erzeugen")
    }

    // MARK: – 9. Produktdefaults/UserDefaults werden durch Factory-/User-Store-Tests nicht veraendert

    func test_factoryAndStoreOperations_doNotTouchUserDefaults() throws {
        let before = he3dUserDefaultsSnapshot()

        _ = AudioPresetFactory.legacyPresets
        for p in AudioPresetFactory.legacyPresets {
            _ = try AudioPresetStore.save(p, in: tempDirectory)
        }
        _ = AudioPresetStore.list(in: tempDirectory)
        _ = AudioPresetStore.load(id: AudioPresetFactory.LegacyID.chord, in: tempDirectory)
        _ = AudioPresetValidator.validate(preset(id: "x", name: "x"))

        let after = he3dUserDefaultsSnapshot()
        XCTAssertEqual(before, after, "Factory-/Store-/Validator-Aufrufe duerfen keine 'he3d.'-UserDefaults-Keys veraendern")
    }

    /// Snapshot aller `UserDefaults.standard`-Keys mit Präfix `he3d.` als
    /// `[String: String]` (stringifizierter Wert genügt für einen reinen
    /// Änderungsvergleich).
    private func he3dUserDefaultsSnapshot() -> [String: String] {
        UserDefaults.standard.dictionaryRepresentation()
            .filter { $0.key.hasPrefix("he3d.") }
            .mapValues { "\($0)" }
    }
}
