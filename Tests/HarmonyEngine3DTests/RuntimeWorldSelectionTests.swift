import XCTest
import HarmonyShared
@testable import HarmonyEngine3D

// MARK: – RuntimeWorldSelectionTests
//
// Deckt die Startauswahl-Logik aus Runde 023 / E-03 ab: Default bleibt
// Explore, HarmonyWeb-Auswahl liefert Map+Layer korrekt, der Developer-
// Override (--map-preview/HE3D_MAP_PREVIEW) hat Vorrang vor der persistierten
// Auswahl, `reference-core` ergibt eine valide WorldSession unter dem Layer
// "functional". `AppModel.effectiveHarmonyWebRequest(envOverride:selection:)`
// nimmt beide Quellen als injizierbare Parameter — Tests mutieren
// `AppSettings.shared` deshalb nie direkt (das würde über den bestehenden
// 500ms-Debounce-Save reale UserDefaults verändern). Keine SceneKit-/Audio-
// Hardware-Abhängigkeit.

final class RuntimeWorldSelectionTests: XCTestCase {

    // MARK: – Defaults

    func test_defaultSelection_isExplore() {
        let selection = RuntimeWorldSelection()
        XCTAssertEqual(selection.mode, .explore)
        XCTAssertEqual(selection.harmonyWebMap, .referenceCore)
        XCTAssertEqual(selection.harmonyWebLayer, "functional")
        XCTAssertNil(selection.externalMapFileName, "Runde 040 / V-01: kein externes Map-Override per Default")
    }

    func test_harmonyWebMapCatalog_rawValuesMatchBundleResourceNames() {
        // rawValue == Bundle-Resource-Name für HarmonyMapLoader.load(named:)/
        // WorldSession.load(named:activeLayer:) — siehe HarmonyWebMapCatalog-Doku.
        XCTAssertEqual(HarmonyWebMapCatalog.referenceCore.rawValue, "reference-core")
        XCTAssertEqual(HarmonyWebMapCatalog.webCenter.rawValue,     "harmony-web-c-center")
        XCTAssertEqual(HarmonyWebMapCatalog.webDiatonic.rawValue,   "harmony-web-c-diatonic")
    }

    // MARK: – effectiveHarmonyWebRequest: Explore bleibt Default

    func test_effectiveHarmonyWebRequest_exploreSelection_noEnvOverride_notRequested() {
        let request = AppModel.effectiveHarmonyWebRequest(
            envOverride: (requested: false, mapName: ""),
            selection:   RuntimeWorldSelection()   // Default: .explore
        )
        XCTAssertFalse(request.requested, "ein frischer Start ohne env/args und Default-Settings bleibt Explore")
        XCTAssertFalse(request.isExternal)
    }

    // MARK: – effectiveHarmonyWebRequest: persistierte HarmonyWeb-Auswahl

    func test_effectiveHarmonyWebRequest_harmonyWebSelection_returnsMapAndLayer() {
        var selection = RuntimeWorldSelection()
        selection.mode = .harmonyWeb
        selection.harmonyWebMap = .referenceCore
        selection.harmonyWebLayer = "functional"

        let request = AppModel.effectiveHarmonyWebRequest(
            envOverride: (requested: false, mapName: ""),
            selection:   selection
        )
        XCTAssertTrue(request.requested)
        XCTAssertEqual(request.mapName, "reference-core")
        XCTAssertEqual(request.layer, "functional")
        XCTAssertFalse(request.isExternal, "Bundle-Katalog-Auswahl ist keine externe Map")
    }

    func test_effectiveHarmonyWebRequest_harmonyWebSelection_otherMapAndLayer() {
        var selection = RuntimeWorldSelection()
        selection.mode = .harmonyWeb
        selection.harmonyWebMap = .webDiatonic
        selection.harmonyWebLayer = "modal"

        let request = AppModel.effectiveHarmonyWebRequest(
            envOverride: (requested: false, mapName: ""),
            selection:   selection
        )
        XCTAssertEqual(request.mapName, "harmony-web-c-diatonic")
        XCTAssertEqual(request.layer, "modal")
    }

    // MARK: – Runde 040 / V-01: externe importierte Map hat Vorrang vor harmonyWebMap

    func test_effectiveHarmonyWebRequest_externalMapFileName_takesPrecedenceOverBundleCatalog() {
        var selection = RuntimeWorldSelection()
        selection.mode = .harmonyWeb
        selection.harmonyWebMap = .webCenter   // gesetzt, aber muss ignoriert werden
        selection.harmonyWebLayer = "functional"
        selection.externalMapFileName = "my-web.json"

        let request = AppModel.effectiveHarmonyWebRequest(
            envOverride: (requested: false, mapName: ""),
            selection:   selection
        )
        XCTAssertTrue(request.requested)
        XCTAssertTrue(request.isExternal)
        XCTAssertEqual(request.mapName, "my-web.json")
        XCTAssertEqual(request.layer, "functional")
    }

    func test_effectiveHarmonyWebRequest_envOverride_takesPrecedenceOverExternalMap() {
        // Der Developer-Override bleibt vorrangig auch gegenüber einer
        // persistierten externen Map-Auswahl — unverändertes Verhalten aus
        // Runde 023 / E-03, jetzt zusätzlich gegen die neue Quelle geprüft.
        var selection = RuntimeWorldSelection()
        selection.mode = .harmonyWeb
        selection.externalMapFileName = "my-web.json"

        let request = AppModel.effectiveHarmonyWebRequest(
            envOverride: (requested: true, mapName: "reference-core"),
            selection:   selection
        )
        XCTAssertFalse(request.isExternal, "Der Flag-Pfad laedt immer aus dem Bundle, nie aus dem Importordner")
        XCTAssertEqual(request.mapName, "reference-core")
    }

    // MARK: – Developer-Override hat Vorrang

    func test_effectiveHarmonyWebRequest_envOverride_takesPrecedenceOverExploreSelection() {
        let request = AppModel.effectiveHarmonyWebRequest(
            envOverride: (requested: true, mapName: "harmony-web-c-diatonic"),
            selection:   RuntimeWorldSelection()   // Default: .explore
        )
        XCTAssertTrue(request.requested, "env/--map-preview-Override wirkt unabhängig von der persistierten Auswahl")
        XCTAssertEqual(request.mapName, "harmony-web-c-diatonic")
    }

    func test_effectiveHarmonyWebRequest_envOverride_alwaysUsesFunctionalLayer() {
        var selection = RuntimeWorldSelection()
        selection.mode = .harmonyWeb
        selection.harmonyWebLayer = "modal"   // persistierte Wahl hat einen anderen Layer

        let request = AppModel.effectiveHarmonyWebRequest(
            envOverride: (requested: true, mapName: "reference-core"),
            selection:   selection
        )
        // Der bestehende Flag-Pfad bleibt unverändert: Layer immer "functional",
        // unabhängig von einer eventuell abweichenden persistierten Layer-Wahl.
        XCTAssertEqual(request.layer, "functional")
    }

    // MARK: – reference-core unter "functional" ist eine valide WorldSession

    func test_worldSession_referenceCore_underFunctionalLayer_isValid() throws {
        let session = try WorldSession.load(named: "reference-core", activeLayer: "functional")
        XCTAssertEqual(session.activeLayer, "functional")
        XCTAssertFalse(session.snapshot.nodeIDs.isEmpty)
    }
}
