import XCTest
@testable import HarmonyEngine3D

// MARK: – AudioPresetValidatorTests
//
// S-03: deckt `AudioPresetValidator` ab — Issue-Sammlung, Error-vs-
// Warning-Blockierverhalten, unbekannte schemaVersion.

final class AudioPresetValidatorTests: XCTestCase {

    private func validPreset() -> AudioSynthPreset {
        ChannelFXConfig.chordDefaults.audioSynthPreset(
            id: "test.preset", name: "Test Preset", channelRole: .chord
        )
    }

    // MARK: – 1. Ein valides Factory-abgeleitetes Preset ist fehlerfrei

    func test_validPreset_hasNoErrors() {
        let result = AudioPresetValidator.validate(validPreset())
        XCTAssertTrue(result.isAcceptable, "Aus ChannelFXConfig.chordDefaults abgeleitetes Preset sollte fehlerfrei sein: \(result.errors)")
    }

    // MARK: – 2. Nicht unterstuetzte schemaVersion blockiert

    func test_unsupportedSchemaVersion_producesBlockingError() {
        var preset = validPreset()
        preset.schemaVersion = "2.0"

        let result = AudioPresetValidator.validate(preset)
        XCTAssertFalse(result.isAcceptable)
        XCTAssertTrue(result.errors.contains { $0.code == "schemaVersionUnsupported" })
    }

    // MARK: – 3. Validator sammelt mehrere Issues in einem Lauf

    func test_multipleInvalidFields_produceMultipleIssuesInOneRun() {
        var preset = validPreset()
        preset.id = ""
        preset.name = ""
        preset.synth.unisonVoices = 0
        preset.synth.maxVoices = 0

        let result = AudioPresetValidator.validate(preset)
        let codes = Set(result.issues.map { $0.code })
        XCTAssertTrue(codes.contains("presetIdEmpty"))
        XCTAssertTrue(codes.contains("presetNameEmpty"))
        XCTAssertTrue(codes.contains("unisonVoicesInvalid"))
        XCTAssertTrue(codes.contains("maxVoicesInvalid"))
        XCTAssertGreaterThanOrEqual(result.errors.count, 4, "alle vier unabhaengigen Fehler muessen im selben Lauf auftauchen")
    }

    // MARK: – 4. Validator blockiert Errors, erlaubt Warnings

    func test_outOfRangeButFiniteValue_producesWarningOnly_notBlocking() {
        var preset = validPreset()
        // decay ausserhalb des dokumentierten 0.001...2.0s-Bereichs, aber
        // endlich und strukturell gueltig — AudioEngine klemmt das bereits
        // heute sicher (siehe AudioPresetValidator-Kommentar).
        preset.synth.decay = 5.0

        let result = AudioPresetValidator.validate(preset)
        XCTAssertTrue(result.isAcceptable, "Out-of-range, aber endlicher Wert darf nicht blockieren")
        XCTAssertTrue(result.warnings.contains { $0.code == "fieldOutOfDocumentedRange" })
        XCTAssertTrue(result.errors.isEmpty)
    }

    func test_nonFiniteValue_producesBlockingError() {
        var preset = validPreset()
        preset.synth.filterCutoff = .nan

        let result = AudioPresetValidator.validate(preset)
        XCTAssertFalse(result.isAcceptable)
        XCTAssertTrue(result.errors.contains { $0.code == "fieldNonFinite" })
    }

    func test_reverbPresetOutOfKnownRange_isWarningNotError() {
        var preset = validPreset()
        preset.fx.reverbPreset = 999

        let result = AudioPresetValidator.validate(preset)
        XCTAssertTrue(result.isAcceptable, "unbekannter reverbPreset darf nicht blockieren (AudioEngine faellt sicher zurueck)")
        XCTAssertTrue(result.warnings.contains { $0.code == "reverbPresetOutOfKnownRange" })
    }
}
