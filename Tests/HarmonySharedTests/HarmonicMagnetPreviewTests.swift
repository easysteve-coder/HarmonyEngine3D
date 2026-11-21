import XCTest
import HarmonyShared

// MARK: – HarmonicMagnetPreviewTests
//
// Deckt die deterministische Preset-/Feld-/Range-Zuordnung ab, die seit K-07
// die einzige Quelle für `RuntimeHarmonik` (Runtime) UND die DesignerKit-
// Simulation-Preview ist.

final class HarmonicMagnetPreviewTests: XCTestCase {

    // MARK: – fieldKind: Prioritätsreihenfolge

    func test_fieldKind_vToI_takesPriorityOverEverything() {
        XCTAssertEqual(HarmonicMagnetPreview.fieldKind(for: [.vToI, .iiToV, .commonTone]), .dominantResolution)
    }

    func test_fieldKind_iiToV_withoutVToI() {
        XCTAssertEqual(HarmonicMagnetPreview.fieldKind(for: [.iiToV, .commonTone]), .preDominantMotion)
    }

    func test_fieldKind_tritSubst_withoutHigherPriority() {
        XCTAssertEqual(HarmonicMagnetPreview.fieldKind(for: [.tritSubst, .relMajMin]), .substitution)
    }

    func test_fieldKind_relMajMin_withoutHigherPriority() {
        XCTAssertEqual(HarmonicMagnetPreview.fieldKind(for: [.relMajMin, .commonTone]), .relative)
    }

    func test_fieldKind_commonTone_alone() {
        XCTAssertEqual(HarmonicMagnetPreview.fieldKind(for: [.commonTone]), .commonTone)
    }

    func test_fieldKind_parallelMajMinOnly_fallsBackToGeneric() {
        XCTAssertEqual(HarmonicMagnetPreview.fieldKind(for: [.parallelMajMin]), .generic)
    }

    // MARK: – baseRange / effectiveRange

    func test_baseRange_presetMapping() {
        XCTAssertEqual(HarmonicMagnetPreview.baseRange(for: .strong), 25)
        XCTAssertEqual(HarmonicMagnetPreview.baseRange(for: .medium), 15)
        XCTAssertEqual(HarmonicMagnetPreview.baseRange(for: .weak), 8)
        XCTAssertEqual(HarmonicMagnetPreview.baseRange(for: nil), 15, "nil verhält sich wie medium")
    }

    func test_effectiveRange_multipliesByRangeScale() {
        XCTAssertEqual(HarmonicMagnetPreview.effectiveRange(preset: .strong, rangeScale: 2.0), 50)
        XCTAssertEqual(HarmonicMagnetPreview.effectiveRange(preset: .weak, rangeScale: 0.5), 4)
    }

    func test_effectiveRange_defaultRangeScale_isOne() {
        XCTAssertEqual(HarmonicMagnetPreview.effectiveRange(preset: .medium), 15)
    }
}
