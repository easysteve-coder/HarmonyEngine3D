import XCTest
@testable import HarmonyAudioCore

// MARK: – AudioCoreWaveshaperTests
//
// S-06 (`.agent_handoff/latest_codex.md`, Runde 054), Scope E, Punkte 7-9:
// Waveshaper bleibt fuer extreme Inputs endlich/begrenzt, Drive/Output-
// Kompensation haelt den Pegel bei Vollaussteuerung ueber den Drive-Bereich
// stabil, Parameter-Clamping fuer nicht-endliche/ausserhalb liegende Werte.

final class AudioCoreWaveshaperTests: XCTestCase {

    // MARK: – 7. Waveshaper bleibt fuer extreme Inputs endlich und begrenzt

    func test_process_extremeInputs_stayFiniteAndBounded() {
        let extremeInputs: [Float] = [.nan, .infinity, -.infinity, 1_000_000, -1_000_000, 0.0]
        let extremeDrives: [Float] = [0.0, 0.5, 1.0, .nan, .infinity, -1.0, 2.0]
        let extremeGains: [Float] = [0.0, 1.0, 4.0, .nan, .infinity, -1.0, 10.0]

        for input in extremeInputs {
            for drive in extremeDrives {
                for gain in extremeGains {
                    let parameters = AudioCoreWaveshaperParameters(drive: drive, outputGain: gain)
                    let output = AudioCoreWaveshaper.process(input, parameters: parameters)
                    XCTAssertTrue(output.isFinite,
                                  "Waveshaper lieferte nicht-endlich bei input=\(input), drive=\(drive), gain=\(gain)")
                    XCTAssertLessThanOrEqual(abs(output), 1.0,
                                              "Waveshaper ueberschritt die Pegelgrenze bei input=\(input), drive=\(drive), gain=\(gain)")
                }
            }
        }
    }

    // MARK: – Symmetrisches Verhalten fuer positive/negative Eingaben

    func test_process_isSymmetricForPositiveAndNegativeInputs() {
        let parameters = AudioCoreWaveshaperParameters(drive: 0.7, outputGain: 1.0)
        for magnitude: Float in [0.1, 0.3, 0.5, 0.8, 1.0] {
            let positive = AudioCoreWaveshaper.process(magnitude, parameters: parameters)
            let negative = AudioCoreWaveshaper.process(-magnitude, parameters: parameters)
            XCTAssertEqual(positive, -negative, accuracy: 0.0001,
                            "Waveshaper war nicht symmetrisch bei magnitude=\(magnitude)")
        }
    }

    // MARK: – 8. Drive/Output-Kompensation: Pegel skaliert nicht unkontrolliert mit Drive

    func test_pegelkompensation_keepsFullScaleOutputLevelStableAcrossDriveRange() {
        let driveValues: [Float] = [0.0, 0.25, 0.5, 0.75, 1.0]
        let levels = driveValues.map { drive -> Float in
            let parameters = AudioCoreWaveshaperParameters(drive: drive, outputGain: 1.0)
            return abs(AudioCoreWaveshaper.process(1.0, parameters: parameters))
        }

        // Ohne Pegelkompensation wuerde der Ausgang mit steigendem Drive nur
        // staerker in die Saettigung laufen und dabei praktisch nur lauter
        // erscheinen. Mit Kompensation bleibt der Vollaussteuerungspegel
        // ueber den gesamten Drive-Bereich in einem engen Band.
        guard let minLevel = levels.min(), let maxLevel = levels.max() else {
            return XCTFail("keine Pegelwerte berechnet")
        }
        XCTAssertLessThan(maxLevel - minLevel, 0.05,
                           "Vollaussteuerungspegel schwankte zu stark ueber den Drive-Bereich: \(levels)")
    }

    func test_outputGain_scalesResultLinearly() {
        let baseParameters = AudioCoreWaveshaperParameters(drive: 0.5, outputGain: 1.0)
        let doubledParameters = AudioCoreWaveshaperParameters(drive: 0.5, outputGain: 2.0)

        // Kleiner Eingabewert, damit die Verdopplung nicht an der [-1, 1]-Grenze abgeschnitten wird.
        let base = AudioCoreWaveshaper.process(0.05, parameters: baseParameters)
        let doubled = AudioCoreWaveshaper.process(0.05, parameters: doubledParameters)

        XCTAssertEqual(doubled, base * 2.0, accuracy: 0.0001)
    }

    // MARK: – 9. Parameter-Clamping fuer nicht-endliche und ausserhalb liegende Werte

    func test_parameters_clampNonFiniteAndOutOfRangeValues() {
        let parameters = AudioCoreWaveshaperParameters(drive: .nan, outputGain: .nan)
        XCTAssertEqual(parameters.drive, 0.0)
        XCTAssertEqual(parameters.outputGain, 1.0)

        let outOfRange = AudioCoreWaveshaperParameters(drive: 5.0, outputGain: -3.0)
        XCTAssertEqual(outOfRange.drive, 1.0)
        XCTAssertEqual(outOfRange.outputGain, 0.0)

        // Nicht-endliche Eingaben (NaN/Infinity) fallen defensiv auf den
        // jeweiligen Default zurueck, identisch zum bestehenden
        // Clamping-Muster in `AudioCoreMixParameters`/
        // `AudioCoreParameterSmoother` (0 fuer Unit-Parameter, Default fuer
        // Gain-Parameter).
        let infiniteParameters = AudioCoreWaveshaperParameters(drive: .infinity, outputGain: .infinity)
        XCTAssertEqual(infiniteParameters.drive, 0.0)
        XCTAssertEqual(infiniteParameters.outputGain, 1.0)
    }

    // MARK: – 10. Determinismus gleicher Inputs/Parameter

    func test_process_isDeterministicForIdenticalInputsAndParameters() {
        let parameters = AudioCoreWaveshaperParameters(drive: 0.6, outputGain: 1.5)
        let first = AudioCoreWaveshaper.process(0.42, parameters: parameters)
        let second = AudioCoreWaveshaper.process(0.42, parameters: parameters)
        XCTAssertEqual(first, second)
    }
}
