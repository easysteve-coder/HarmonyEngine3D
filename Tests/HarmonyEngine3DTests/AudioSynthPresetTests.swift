import XCTest
@testable import HarmonyEngine3D

// MARK: – AudioSynthPresetTests
//
// S-03 (`.agent_handoff/latest_codex.md`, Runde 048): Codable-Roundtrip und
// striktes Decoding fuer `AudioSynthPreset` (`AudioSynthPresetCodec`).

final class AudioSynthPresetTests: XCTestCase {

    private func samplePreset() -> AudioSynthPreset {
        ChannelFXConfig.chordDefaults.audioSynthPreset(
            id: "test.preset", name: "Test Preset", channelRole: .chord,
            author: "Stephan", engineVersion: "3.9.9"
        )
    }

    // MARK: – 1. Codable-Roundtrip deterministisch

    func test_codableRoundtrip_isDeterministicAndLossless() throws {
        let original = samplePreset()

        let dataA = try AudioSynthPresetCodec.encode(original)
        let dataB = try AudioSynthPresetCodec.encode(original)
        XCTAssertEqual(dataA, dataB, "Encode desselben Presets muss bitgenau deterministisch sein (sortedKeys)")

        let decoded = try AudioSynthPresetCodec.decode(from: dataA)
        XCTAssertEqual(decoded, original, "Roundtrip Encode -> Decode muss verlustfrei sein")
    }

    func test_codableRoundtrip_viaURL() throws {
        let original = samplePreset()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioSynthPresetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let url = tempDir.appendingPathComponent("preset.json")
        try AudioSynthPresetCodec.encode(original).write(to: url)

        let decoded = try AudioSynthPresetCodec.decode(from: url)
        XCTAssertEqual(decoded, original)
    }

    // MARK: – 2. Striktes Decoding scheitert bei falsch typisierten Feldern

    func test_strictDecoding_failsOnWrongTypeForExistingField() throws {
        var json = try JSONSerialization.jsonObject(with: AudioSynthPresetCodec.encode(samplePreset()))
            as! [String: Any]
        // `name` ist als String deklariert — ein vorhandener, aber falsch
        // typisierter Wert darf NICHT still zu einem Default werden.
        json["name"] = 12345
        let corruptedData = try JSONSerialization.data(withJSONObject: json)

        XCTAssertThrowsError(try AudioSynthPresetCodec.decode(from: corruptedData)) { error in
            guard case AudioSynthPresetCodec.CodecError.decode = error else {
                return XCTFail("erwartete CodecError.decode, bekam \(error)")
            }
        }
    }

    func test_strictDecoding_failsOnWrongTypeInSynthSection() throws {
        var json = try JSONSerialization.jsonObject(with: AudioSynthPresetCodec.encode(samplePreset()))
            as! [String: Any]
        var synth = json["synth"] as! [String: Any]
        // `unisonVoices` ist Int — ein String darf nicht still zu 0/Default werden.
        synth["unisonVoices"] = "not-a-number"
        json["synth"] = synth
        let corruptedData = try JSONSerialization.data(withJSONObject: json)

        XCTAssertThrowsError(try AudioSynthPresetCodec.decode(from: corruptedData))
    }

    func test_strictDecoding_failsOnMissingRequiredField() throws {
        var json = try JSONSerialization.jsonObject(with: AudioSynthPresetCodec.encode(samplePreset()))
            as! [String: Any]
        json.removeValue(forKey: "schemaVersion")
        let corruptedData = try JSONSerialization.data(withJSONObject: json)

        XCTAssertThrowsError(try AudioSynthPresetCodec.decode(from: corruptedData))
    }
}
