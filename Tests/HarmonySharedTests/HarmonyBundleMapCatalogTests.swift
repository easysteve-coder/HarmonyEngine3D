import XCTest
import HarmonyShared

// MARK: – HarmonyBundleMapCatalogTests
//
// Runde 065: haelt den Layer-Katalog (`HarmonyLayer.relationTypes`) aller
// mitgelieferten Bundle-Maps gegen die auf ihren Kanten tatsaechlich
// genutzten RelationTypes fest (`HarmonyMapValidator`-Regel
// `layerRelationTypeCatalogMismatch`, Scope C). Ohne diesen Test faellt eine
// kuenftige Abweichung erst bei einem Smoke-Lauf auf statt sofort im Build.
//
// Bewusst eine feste Namensliste statt Verzeichnis-Enumeration — Bundle-
// Resources sind zur Testlaufzeit nicht als Verzeichnis durchsuchbar (SPM
// legt sie flach in der Bundle-Wurzel ab), und eine feste Liste macht
// sichtbar, welche Maps geprueft werden.

final class HarmonyBundleMapCatalogTests: XCTestCase {

    private static let bundleMapNames = [
        "harmony-map-loader-test-fixture",
        "harmony-web-c-center",
        "harmony-web-c-diatonic",
        "reference-core",
    ]

    func test_allBundleMaps_layerCatalogCoversUsedRelationTypes() throws {
        for name in Self.bundleMapNames {
            let map = try HarmonyMapCodec.decode(fromBundleResource: name)
            let result = HarmonyMapValidator.validate(map)
            let mismatches = result.warnings.filter { $0.code == "layerRelationTypeCatalogMismatch" }
            XCTAssertTrue(
                mismatches.isEmpty,
                "\(name).json: Layer-Katalog deckt genutzte relationTypes nicht ab: \(mismatches)"
            )
        }
    }
}
