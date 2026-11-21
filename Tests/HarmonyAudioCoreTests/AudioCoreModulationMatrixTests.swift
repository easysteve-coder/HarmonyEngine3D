import XCTest
@testable import HarmonyAudioCore

// MARK: – AudioCoreModulationMatrixTests
//
// S-05b (`.agent_handoff/latest_codex.md`, Runde 053), Scope B/D: bipolares
// Route-Amount-Clamping, 16-Routen-Grenze, Determinismus, deterministische
// Akkumulation mehrerer Routen auf dasselbe Ziel, deaktivierte Routen ohne
// Wirkung, definierter leerer Matrix-Fall und finite/begrenzte Zielwerte
// bei Extremeingaben.

final class AudioCoreModulationMatrixTests: XCTestCase {

    // MARK: – 3. Route-Amount wird bipolar begrenzt

    func test_routeAmount_isClampedToBipolarRange() {
        let overPositive = AudioCoreModulationRoute(source: .macro(.motion), target: .morphPosition, amount: 5.0)
        let overNegative = AudioCoreModulationRoute(source: .macro(.motion), target: .morphPosition, amount: -5.0)
        let nonFinite = AudioCoreModulationRoute(source: .macro(.motion), target: .morphPosition, amount: .nan)

        XCTAssertEqual(overPositive.amount, 1.0)
        XCTAssertEqual(overNegative.amount, -1.0)
        XCTAssertEqual(nonFinite.amount, 0.0)
    }

    // MARK: – 4. Matrix akzeptiert hoechstens 16 Routen

    func test_matrix_truncatesToAtMost16RoutesDeterministically() {
        let routes = (0..<20).map { index in
            AudioCoreModulationRoute(source: .macro(.motion), target: .morphPosition, amount: Float(index) / 20.0)
        }
        let matrix = AudioCoreModulationMatrix(routes: routes)

        XCTAssertEqual(matrix.routes.count, AudioCoreModulationMatrix.maxRouteCount)
        XCTAssertEqual(matrix.routes, Array(routes.prefix(16)), "Truncation muss die ersten 16 Routen in Eingabereihenfolge behalten")
    }

    // MARK: – 5. Gleiche Inputs liefern gleiche Outputs

    func test_evaluate_isDeterministicForIdenticalInputs() {
        let matrix = AudioCoreModulationMatrix(routes: [
            AudioCoreModulationRoute(source: .macro(.motion), target: .morphPosition, amount: 0.6),
            AudioCoreModulationRoute(source: .lfo(.lfo2), target: .filterCutoff, amount: -0.4)
        ])
        let sources = AudioCoreModulationSourceValues(macros: AudioCoreMacroValues(motion: 0.5), lfo2: 0.25)

        let first = matrix.evaluate(sources: sources)
        let second = matrix.evaluate(sources: sources)

        XCTAssertEqual(first, second)
    }

    // MARK: – 6. Mehrere Routen auf dasselbe Target werden deterministisch akkumuliert

    func test_multipleRoutesToSameTarget_accumulateDeterministically() {
        let matrix = AudioCoreModulationMatrix(routes: [
            AudioCoreModulationRoute(source: .macro(.motion), target: .morphPosition, amount: 0.5),
            AudioCoreModulationRoute(source: .macro(.color), target: .morphPosition, amount: 0.4)
        ])
        let sources = AudioCoreModulationSourceValues(macros: AudioCoreMacroValues(motion: 0.5, color: 0.3))

        // 0.5*0.5 + 0.3*0.4 = 0.25 + 0.12 = 0.37, bleibt innerhalb [-1, 1] -> keine Klemmung ueberdeckt die Summe.
        let result = matrix.evaluate(sources: sources)
        XCTAssertEqual(result.morphPosition, 0.37, accuracy: 1e-6)
    }

    // MARK: – 7. Deaktivierte Routen haben keine Wirkung

    func test_disabledRoute_hasNoEffectOnEvaluation() {
        let enabledOnly = AudioCoreModulationMatrix(routes: [
            AudioCoreModulationRoute(source: .macro(.motion), target: .morphPosition, amount: 0.5)
        ])
        let withDisabledExtra = AudioCoreModulationMatrix(routes: [
            AudioCoreModulationRoute(source: .macro(.motion), target: .morphPosition, amount: 0.5),
            AudioCoreModulationRoute(source: .macro(.color), target: .morphPosition, amount: 0.9, isEnabled: false)
        ])
        let sources = AudioCoreModulationSourceValues(macros: AudioCoreMacroValues(motion: 0.5, color: 1.0))

        XCTAssertEqual(enabledOnly.evaluate(sources: sources), withDisabledExtra.evaluate(sources: sources))
    }

    // MARK: – leerer Matrix-Fall ist definiert

    func test_emptyMatrix_evaluatesToAllZeroTargets() {
        let sources = AudioCoreModulationSourceValues(macros: AudioCoreMacroValues(motion: 1.0, color: 1.0, space: 1.0, focus: 1.0),
                                                       lfo1: 1.0, lfo2: -1.0, lfo3: 1.0, ampEnvelope: 1.0, modEnvelope: 1.0)
        let result = AudioCoreModulationMatrix.empty.evaluate(sources: sources)

        XCTAssertEqual(result, AudioCoreModulationTargetValues())
        for target in AudioCoreModulationTarget.allCases {
            XCTAssertEqual(result[target], 0.0, "leere Matrix sollte Ziel \(target) unveraendert bei 0 lassen")
        }
    }

    // MARK: – 8./10. Zielwerte bleiben endlich und begrenzt, auch bei Extremeingaben

    func test_targetValues_remainFiniteAndBoundedForExtremeInputs() {
        let matrix = AudioCoreModulationMatrix(routes: [
            AudioCoreModulationRoute(source: .macro(.motion), target: .morphPosition, amount: 1.0),
            AudioCoreModulationRoute(source: .macro(.color), target: .morphPosition, amount: 1.0),
            AudioCoreModulationRoute(source: .lfo(.lfo1), target: .filterCutoff, amount: 1.0),
            AudioCoreModulationRoute(source: .envelope(.amp), target: .ampEnvelopeDepth, amount: -1.0)
        ])

        let extremeSourceSets: [AudioCoreModulationSourceValues] = [
            AudioCoreModulationSourceValues(macros: AudioCoreMacroValues(motion: 1.0, color: 1.0), lfo1: .nan, ampEnvelope: .infinity),
            AudioCoreModulationSourceValues(macros: AudioCoreMacroValues(motion: 1.0, color: 1.0), lfo1: .infinity, ampEnvelope: -.infinity),
            AudioCoreModulationSourceValues(lfo1: -.infinity, ampEnvelope: .nan)
        ]

        for sources in extremeSourceSets {
            let result = matrix.evaluate(sources: sources)
            for target in AudioCoreModulationTarget.allCases {
                let value = result[target]
                XCTAssertTrue(value.isFinite, "Ziel \(target) sollte fuer Extremeingaben endlich bleiben, war \(value)")
                XCTAssertTrue(value >= AudioCoreModulationTargetValues.range.lowerBound && value <= AudioCoreModulationTargetValues.range.upperBound,
                              "Ziel \(target) sollte innerhalb \(AudioCoreModulationTargetValues.range) bleiben, war \(value)")
            }
        }
    }

    // MARK: – Typisierte Source-Referenzen lesen die erwarteten Felder

    func test_sourceValues_subscriptReadsExpectedFieldPerSlotAndRole() {
        let sources = AudioCoreModulationSourceValues(macros: AudioCoreMacroValues(motion: 0.1, color: 0.2, space: 0.3, focus: 0.4),
                                                       lfo1: 0.5, lfo2: 0.6, lfo3: 0.7,
                                                       ampEnvelope: 0.8, modEnvelope: 0.9)

        XCTAssertEqual(sources[.macro(.motion)], 0.1)
        XCTAssertEqual(sources[.macro(.color)], 0.2)
        XCTAssertEqual(sources[.macro(.space)], 0.3)
        XCTAssertEqual(sources[.macro(.focus)], 0.4)
        XCTAssertEqual(sources[.lfo(.lfo1)], 0.5)
        XCTAssertEqual(sources[.lfo(.lfo2)], 0.6)
        XCTAssertEqual(sources[.lfo(.lfo3)], 0.7)
        XCTAssertEqual(sources[.envelope(.amp)], 0.8)
        XCTAssertEqual(sources[.envelope(.mod)], 0.9)
    }
}
