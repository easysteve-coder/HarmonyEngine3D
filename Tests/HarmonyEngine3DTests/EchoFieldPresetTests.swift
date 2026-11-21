import XCTest
@testable import HarmonyEngine3D

// MARK: – EchoFieldPresetTests
//
// S-07b (`.agent_handoff/latest_codex.md`, Runde 056): `EchoFieldPreset`-
// Modell, Legacy-Migration aus `ChannelFXConfig`/`AudioPresetFXSection`,
// Factory, Codec-Roundtrip und Validator.

final class EchoFieldPresetTests: XCTestCase {

    private func samplePreset() -> EchoFieldPreset {
        ChannelFXConfig.chordDefaults.echoFieldPreset(
            id: "test.echo", name: "Test Echo", channelRole: .chord,
            author: "Stephan", engineVersion: "3.9.9"
        )
    }

    // MARK: – 1. Vier Tap-Slots, stabile Reihenfolge

    func test_taps_hasExactlyFourSlotsInStableOrder() {
        let preset = samplePreset()
        XCTAssertEqual(preset.taps.count, 4)
        XCTAssertEqual(preset.taps[0], preset.tap1)
        XCTAssertEqual(preset.taps[1], preset.tap2)
        XCTAssertEqual(preset.taps[2], preset.tap3)
        XCTAssertEqual(preset.taps[3], preset.tap4)
    }

    // MARK: – 2. Legacy-ChannelFXConfig-Migration kopiert Tap 1/2/3 feldgenau

    func test_channelFXConfigMigration_copiesTap1Through3FieldForField() {
        let config = ChannelFXConfig.melodyDefaults   // hat die groessten Delay-/Feedback-Werte
        let preset = config.echoFieldPreset(id: "field-check", name: "Field Check", channelRole: .melody)

        XCTAssertEqual(preset.tap1.time, config.delay1Time)
        XCTAssertEqual(preset.tap1.feedback, config.delay1Feedback)
        XCTAssertEqual(preset.tap1.mix, config.delay1Mix)
        XCTAssertEqual(preset.tap1.pan, config.delay1Pan)

        XCTAssertEqual(preset.tap2.time, config.delay2Time)
        XCTAssertEqual(preset.tap2.feedback, config.delay2Feedback)
        XCTAssertEqual(preset.tap2.mix, config.delay2Mix)
        XCTAssertEqual(preset.tap2.pan, config.delay2Pan)

        XCTAssertEqual(preset.tap3.time, config.delay3Time)
        XCTAssertEqual(preset.tap3.feedback, config.delay3Feedback)
        XCTAssertEqual(preset.tap3.mix, config.delay3Mix)
        XCTAssertEqual(preset.tap3.pan, config.delay3Pan)
    }

    // MARK: – 3. Tap 4 ist deterministisch neutral/deaktiviert

    func test_tap4_isDeterministicallyNeutral() {
        let preset = samplePreset()
        XCTAssertEqual(preset.tap4, .neutral)
        XCTAssertEqual(preset.tap4.mix, 0.0, "Tap 4 muss stumm sein (mix 0)")
        XCTAssertEqual(preset.tap4.feedback, 0.0, "Tap 4 darf kein Feedback tragen")
    }

    func test_tap4_isNeutralAcrossAllFourLegacyChannelDefaults() {
        for preset in EchoFieldPresetFactory.legacyPresets {
            XCTAssertEqual(preset.tap4, .neutral, "\(preset.id): Tap 4 muss ueberall neutral sein")
        }
    }

    // MARK: – 4. Alle vier Legacy-Kanaldefaults migrieren deterministisch

    func test_allFourChannelFXConfigDefaults_migrateDeterministically() {
        let defaults: [(String, ChannelFXConfig, AudioPresetChannelRole)] = [
            ("chord", .chordDefaults, .chord),
            ("bass", .bassDefaults, .bass),
            ("melody", .melodyDefaults, .melody),
            ("chordTone", .chordToneDefaults, .chordTone)
        ]

        for (label, config, role) in defaults {
            let presetA = config.echoFieldPreset(id: "det.\(label)", name: label, channelRole: role)
            let presetB = config.echoFieldPreset(id: "det.\(label)", name: label, channelRole: role)
            XCTAssertEqual(presetA, presetB, "\(label): identische Eingabe muss identisches Preset liefern")
        }
    }

    func test_legacyPresets_containsExactlyFourChannelRolesWithStableIDs() {
        let presets = EchoFieldPresetFactory.legacyPresets
        XCTAssertEqual(presets.count, 4)

        let idsByRole = Dictionary(uniqueKeysWithValues: presets.map { ($0.channelRole, $0.id) })
        XCTAssertEqual(idsByRole[.chord], EchoFieldPresetFactory.LegacyID.chord)
        XCTAssertEqual(idsByRole[.bass], EchoFieldPresetFactory.LegacyID.bass)
        XCTAssertEqual(idsByRole[.melody], EchoFieldPresetFactory.LegacyID.melody)
        XCTAssertEqual(idsByRole[.chordTone], EchoFieldPresetFactory.LegacyID.chordTone)

        let roles = Set(presets.map { $0.channelRole })
        XCTAssertEqual(roles, Set(AudioPresetChannelRole.allCases), "alle vier Kanalrollen muessen genau einmal vertreten sein")
    }

    func test_legacyPresets_areAllValidatorAcceptable() {
        for preset in EchoFieldPresetFactory.legacyPresets {
            let result = EchoFieldPresetValidator.validate(preset)
            XCTAssertTrue(result.isAcceptable, "\(preset.id): \(result.errors)")
        }
    }

    // MARK: – 5. Migration aus AudioSynthPreset/AudioPresetFXSection bleibt konsistent

    func test_audioSynthPresetDerivedEchoField_matchesUnderlyingFXFields() {
        let synthPreset = ChannelFXConfig.bassDefaults.audioSynthPreset(
            id: "synth.bass", name: "Synth Bass", channelRole: .bass
        )
        let echoPreset = synthPreset.echoFieldPreset(id: "echo.bass", name: "Echo Bass")

        XCTAssertEqual(echoPreset.channelRole, synthPreset.channelRole)
        XCTAssertEqual(echoPreset.author, synthPreset.author)
        XCTAssertEqual(echoPreset.engineVersion, synthPreset.engineVersion)

        XCTAssertEqual(echoPreset.tap1.time, synthPreset.fx.delay1Time)
        XCTAssertEqual(echoPreset.tap1.feedback, synthPreset.fx.delay1Feedback)
        XCTAssertEqual(echoPreset.tap1.mix, synthPreset.fx.delay1Mix)
        XCTAssertEqual(echoPreset.tap1.pan, synthPreset.fx.delay1Pan)
        XCTAssertEqual(echoPreset.tap2.time, synthPreset.fx.delay2Time)
        XCTAssertEqual(echoPreset.tap3.mix, synthPreset.fx.delay3Mix)
        XCTAssertEqual(echoPreset.tap4, .neutral)
    }

    func test_audioSynthPresetDerivedEchoField_agreesWithDirectChannelFXConfigMigration() {
        // Zwei unabhaengige Pfade zum selben Ziel muessen dieselben ersten
        // drei Taps liefern: ChannelFXConfig -> EchoFieldPreset direkt, und
        // ChannelFXConfig -> AudioSynthPreset -> EchoFieldPreset indirekt.
        let config = ChannelFXConfig.chordToneDefaults
        let direct = config.echoFieldPreset(id: "x", name: "x", channelRole: .chordTone)
        let viaSynthPreset = config
            .audioSynthPreset(id: "y", name: "y", channelRole: .chordTone)
            .echoFieldPreset(id: "x", name: "x")

        XCTAssertEqual(direct.tap1, viaSynthPreset.tap1)
        XCTAssertEqual(direct.tap2, viaSynthPreset.tap2)
        XCTAssertEqual(direct.tap3, viaSynthPreset.tap3)
        XCTAssertEqual(direct.tap4, viaSynthPreset.tap4)
    }

    // MARK: – 6. Codable-Roundtrip und deterministisches Encoding

    func test_codableRoundtrip_isDeterministicAndLossless() throws {
        let original = samplePreset()

        let dataA = try EchoFieldPresetCodec.encode(original)
        let dataB = try EchoFieldPresetCodec.encode(original)
        XCTAssertEqual(dataA, dataB, "Encode desselben Presets muss bitgenau deterministisch sein (sortedKeys)")

        let decoded = try EchoFieldPresetCodec.decode(from: dataA)
        XCTAssertEqual(decoded, original, "Roundtrip Encode -> Decode muss verlustfrei sein")
    }

    func test_codableRoundtrip_viaURL() throws {
        let original = samplePreset()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EchoFieldPresetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let url = tempDir.appendingPathComponent("preset.json")
        try EchoFieldPresetCodec.encode(original).write(to: url)

        let decoded = try EchoFieldPresetCodec.decode(from: url)
        XCTAssertEqual(decoded, original)
    }

    func test_strictDecoding_failsOnWrongTypeForExistingField() throws {
        var json = try JSONSerialization.jsonObject(with: EchoFieldPresetCodec.encode(samplePreset()))
            as! [String: Any]
        json["name"] = 12345
        let corruptedData = try JSONSerialization.data(withJSONObject: json)

        XCTAssertThrowsError(try EchoFieldPresetCodec.decode(from: corruptedData)) { error in
            guard case EchoFieldPresetCodec.CodecError.decode = error else {
                return XCTFail("erwartete CodecError.decode, bekam \(error)")
            }
        }
    }

    func test_strictDecoding_failsOnWrongTypeInTap() throws {
        var json = try JSONSerialization.jsonObject(with: EchoFieldPresetCodec.encode(samplePreset()))
            as! [String: Any]
        var tap1 = json["tap1"] as! [String: Any]
        tap1["time"] = "not-a-number"
        json["tap1"] = tap1
        let corruptedData = try JSONSerialization.data(withJSONObject: json)

        XCTAssertThrowsError(try EchoFieldPresetCodec.decode(from: corruptedData))
    }

    func test_strictDecoding_failsOnMissingRequiredField() throws {
        var json = try JSONSerialization.jsonObject(with: EchoFieldPresetCodec.encode(samplePreset()))
            as! [String: Any]
        json.removeValue(forKey: "tap4")
        let corruptedData = try JSONSerialization.data(withJSONObject: json)

        XCTAssertThrowsError(try EchoFieldPresetCodec.decode(from: corruptedData))
    }

    // MARK: – 7. Validator/Parametergrenzen

    func test_validPreset_hasNoErrors() {
        let result = EchoFieldPresetValidator.validate(samplePreset())
        XCTAssertTrue(result.isAcceptable, "\(result.errors)")
    }

    func test_unsupportedSchemaVersion_producesBlockingError() {
        var preset = samplePreset()
        preset.schemaVersion = "2.0"

        let result = EchoFieldPresetValidator.validate(preset)
        XCTAssertFalse(result.isAcceptable)
        XCTAssertTrue(result.errors.contains { $0.code == "schemaVersionUnsupported" })
    }

    func test_multipleInvalidFields_produceMultipleIssuesInOneRun() {
        var preset = samplePreset()
        preset.id = ""
        preset.name = ""
        preset.tap1.time = .nan
        preset.tap2.feedback = 1.5

        let result = EchoFieldPresetValidator.validate(preset)
        let codes = Set(result.issues.map { $0.code })
        XCTAssertTrue(codes.contains("presetIdEmpty"))
        XCTAssertTrue(codes.contains("presetNameEmpty"))
        XCTAssertTrue(codes.contains("fieldNonFinite"))
        XCTAssertTrue(codes.contains("tapFeedbackRunawayRisk"))
        XCTAssertGreaterThanOrEqual(result.errors.count, 4, "alle unabhaengigen Fehler muessen im selben Lauf auftauchen")
    }

    func test_timeOutOfDocumentedRangeButFinite_producesWarningOnly_notBlocking() {
        var preset = samplePreset()
        preset.tap1.time = 5.0   // > 4.0 s, aber endlich

        let result = EchoFieldPresetValidator.validate(preset)
        XCTAssertTrue(result.isAcceptable, "Out-of-range, aber endlicher Wert darf nicht blockieren")
        XCTAssertTrue(result.warnings.contains { $0.code == "fieldOutOfDocumentedRange" })
        XCTAssertTrue(result.errors.isEmpty)
    }

    func test_nonFiniteTime_producesBlockingError() {
        var preset = samplePreset()
        preset.tap1.time = .infinity

        let result = EchoFieldPresetValidator.validate(preset)
        XCTAssertFalse(result.isAcceptable)
        XCTAssertTrue(result.errors.contains { $0.code == "fieldNonFinite" })
    }

    func test_nonFinitePan_producesBlockingError() {
        var preset = samplePreset()
        preset.tap2.pan = .nan

        let result = EchoFieldPresetValidator.validate(preset)
        XCTAssertFalse(result.isAcceptable)
        XCTAssertTrue(result.errors.contains { $0.code == "fieldNonFinite" && $0.objectPath == "$.tap2" })
    }

    func test_panOutOfRange_producesWarningOnly() {
        var preset = samplePreset()
        preset.tap3.pan = 1.5

        let result = EchoFieldPresetValidator.validate(preset)
        XCTAssertTrue(result.isAcceptable)
        XCTAssertTrue(result.warnings.contains { $0.code == "fieldOutOfDocumentedRange" && $0.objectPath == "$.tap3" })
    }

    func test_mixOutOfRange_producesWarningOnly() {
        var preset = samplePreset()
        preset.tap1.mix = 1.5

        let result = EchoFieldPresetValidator.validate(preset)
        XCTAssertTrue(result.isAcceptable)
        XCTAssertTrue(result.warnings.contains { $0.code == "fieldOutOfDocumentedRange" })
    }

    func test_feedbackAtRunawayThreshold_producesBlockingError() {
        var preset = samplePreset()
        preset.tap1.feedback = 1.0

        let result = EchoFieldPresetValidator.validate(preset)
        XCTAssertFalse(result.isAcceptable)
        XCTAssertTrue(result.errors.contains { $0.code == "tapFeedbackRunawayRisk" })
    }

    func test_feedbackAboveRunawayThreshold_producesBlockingError() {
        var preset = samplePreset()
        preset.tap1.feedback = 2.5

        let result = EchoFieldPresetValidator.validate(preset)
        XCTAssertFalse(result.isAcceptable)
        XCTAssertTrue(result.errors.contains { $0.code == "tapFeedbackRunawayRisk" })
    }

    func test_feedbackJustBelowRunawayThreshold_doesNotBlock() {
        var preset = samplePreset()
        preset.tap1.feedback = 0.99   // < 1.0 -> kein Runaway-Error, nur Warning (außerhalb 0...0.98)

        let result = EchoFieldPresetValidator.validate(preset)
        XCTAssertTrue(result.isAcceptable)
        XCTAssertFalse(result.errors.contains { $0.code == "tapFeedbackRunawayRisk" })
    }
}
