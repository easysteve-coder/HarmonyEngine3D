import XCTest
@testable import HarmonyAudioCore

// MARK: – AudioCoreTextureSourceTests
//
// S-04b (`.agent_handoff/latest_codex.md`, Runde 051), Scope E, Punkte 3-4:
// Texture Source C erzeugt bei gleichem Seed/State identische Samplefolgen
// und bleibt fuer Extremparameter finite und pegelkontrolliert.

final class AudioCoreTextureSourceTests: XCTestCase {

    // MARK: – 3. Gleicher Seed/State erzeugt identische Samplefolge

    func test_identicalSeed_producesIdenticalSampleSequence() {
        func renderScenario() -> [Float] {
            var texture = AudioCoreTextureSource(seed: 0xDEAD_BEEF_1234_5678, brightness: 0.4, level: 0.8)
            let frameCount = 4_000
            var buffer = [Float](repeating: 0, count: frameCount)
            buffer.withUnsafeMutableBufferPointer { buf in
                _ = texture.render(into: buf.baseAddress!, frameCount: frameCount)
            }
            return buffer
        }

        XCTAssertEqual(renderScenario(), renderScenario(),
                        "gleicher Seed/Parameter muss bitgenau identische Samplefolge liefern")
    }

    func test_differentSeeds_produceDifferentSampleSequences() {
        var textureA = AudioCoreTextureSource(seed: 1, brightness: 1.0, level: 1.0)
        var textureB = AudioCoreTextureSource(seed: 2, brightness: 1.0, level: 1.0)

        let framesA = (0..<64).map { _ in textureA.nextSample() }
        let framesB = (0..<64).map { _ in textureB.nextSample() }

        XCTAssertNotEqual(framesA, framesB, "unterschiedliche Seeds sollten unterschiedliche Samplefolgen erzeugen")
    }

    func test_resetState_reproducesSameSequenceAsFreshInit() {
        var fresh = AudioCoreTextureSource(seed: 777, brightness: 0.6, level: 0.5)
        let freshSamples = (0..<32).map { _ in fresh.nextSample() }

        var reused = AudioCoreTextureSource(seed: 999, brightness: 0.6, level: 0.5)
        _ = (0..<10).map { _ in reused.nextSample() }
        reused.resetState(to: 777)
        let reusedSamples = (0..<32).map { _ in reused.nextSample() }

        XCTAssertEqual(freshSamples, reusedSamples)
    }

    func test_zeroSeed_doesNotDegenerateToConstantZeroOutput() {
        var texture = AudioCoreTextureSource(seed: 0, brightness: 1.0, level: 1.0)
        let samples = (0..<64).map { _ in texture.nextSample() }
        XCTAssertTrue(samples.contains { $0 != 0 }, "Seed 0 sollte auf einen von-Null-verschiedenen Ersatzwert abgebildet werden")
    }

    // MARK: – 4. Extremparameter bleiben finite und pegelkontrolliert

    func test_extremeParameters_produceFiniteAndLevelBoundedSamples() {
        let extremeCases: [(seed: UInt64, brightness: Float, level: Float)] = [
            (1, .nan, 1.0),
            (1, .infinity, 1.0),
            (1, -.infinity, 1.0),
            (1, 0.5, .nan),
            (1, 0.5, .infinity),
            (1, -1_000, 1.0),
            (1, 1_000, 1.0),
            (1, 0.5, -1_000),
            (1, 0.5, 1_000),
            (0, 0, 0)
        ]

        for testCase in extremeCases {
            var texture = AudioCoreTextureSource(seed: testCase.seed, brightness: testCase.brightness, level: testCase.level)
            XCTAssertGreaterThanOrEqual(texture.brightness, 0, "brightness sollte auf 0...1 geklemmt sein: \(testCase)")
            XCTAssertLessThanOrEqual(texture.brightness, 1, "brightness sollte auf 0...1 geklemmt sein: \(testCase)")
            XCTAssertGreaterThanOrEqual(texture.level, 0, "level sollte auf 0...1 geklemmt sein: \(testCase)")
            XCTAssertLessThanOrEqual(texture.level, 1, "level sollte auf 0...1 geklemmt sein: \(testCase)")

            let frameCount = 512
            var buffer = [Float](repeating: 0, count: frameCount)
            buffer.withUnsafeMutableBufferPointer { buf in
                _ = texture.render(into: buf.baseAddress!, frameCount: frameCount)
            }
            for sample in buffer {
                XCTAssertTrue(sample.isFinite, "Extremfall \(testCase) erzeugte ein nicht-endliches Sample")
                XCTAssertLessThanOrEqual(abs(sample), 1.0, "Sample \(sample) ueberschreitet den erwarteten Pegelrahmen [-1, 1] bei \(testCase)")
            }
        }
    }

    func test_levelZero_producesSilence() {
        var texture = AudioCoreTextureSource(seed: 42, brightness: 0.7, level: 0.0)
        let samples = (0..<128).map { _ in texture.nextSample() }
        XCTAssertTrue(samples.allSatisfy { $0 == 0 })
    }
}
