import XCTest
@testable import HarmonyAudioCore

// MARK: – AudioCoreMacroValuesTests
//
// S-05b (`.agent_handoff/latest_codex.md`, Runde 053), Scope A/D: genau
// vier Makros mit stabiler Reihenfolge/Identitaet, Clamping auf `0...1` und
// definiertes Verhalten bei nicht-endlichen Eingaben.

final class AudioCoreMacroValuesTests: XCTestCase {

    // MARK: – 1. Genau vier Makros mit stabiler Reihenfolge/Identitaet

    func test_fourMacros_haveStableOrderAndIdentity() {
        XCTAssertEqual(AudioCoreMacroID.allCases, [.motion, .color, .space, .focus])
        XCTAssertEqual(AudioCoreMacroID.allCases.count, 4)
        XCTAssertEqual(Set(AudioCoreMacroID.allCases).count, 4, "alle vier Makro-IDs muessen paarweise verschieden sein")
    }

    // MARK: – 2. Makro-Werte werden auf 0...1 geklemmt

    func test_init_clampsAllFieldsToUnitRange() {
        let values = AudioCoreMacroValues(motion: -1.0, color: 2.0, space: 0.5, focus: 1.5)

        XCTAssertEqual(values.motion, 0.0)
        XCTAssertEqual(values.color, 1.0)
        XCTAssertEqual(values.space, 0.5)
        XCTAssertEqual(values.focus, 1.0)
    }

    func test_subscriptSetter_clampsToUnitRangeIdenticalToInit() {
        var values = AudioCoreMacroValues.defaults
        values[.motion] = -5.0
        values[.color] = 5.0

        XCTAssertEqual(values.motion, 0.0)
        XCTAssertEqual(values.color, 1.0)
        XCTAssertEqual(values[.motion], values.motion)
        XCTAssertEqual(values[.color], values.color)
    }

    // MARK: – 2. Nicht-endliche Eingaben werden definiert behandelt (Fallback 0)

    func test_nonFiniteInputs_fallBackToZero() {
        let values = AudioCoreMacroValues(motion: .nan, color: .infinity, space: -.infinity, focus: 0.7)

        XCTAssertEqual(values.motion, 0.0)
        XCTAssertEqual(values.color, 0.0)
        XCTAssertEqual(values.space, 0.0)
        XCTAssertEqual(values.focus, 0.7)

        var mutated = AudioCoreMacroValues.defaults
        mutated[.focus] = .nan
        XCTAssertEqual(mutated.focus, 0.0)
    }

    func test_defaults_areAllZero() {
        let defaults = AudioCoreMacroValues.defaults
        for id in AudioCoreMacroID.allCases {
            XCTAssertEqual(defaults[id], 0.0, "Default fuer \(id) sollte 0 sein")
        }
    }
}
