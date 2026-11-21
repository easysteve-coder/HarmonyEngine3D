import XCTest
import HarmonyAudioCore
@testable import HarmonyEngine3D

// MARK: – AudioCoreMappingTests
//
// S-02b (`.agent_handoff/latest_codex.md`, Runde 047): deckt das schmale
// App-seitige Mapping `Waveform -> AudioCoreWaveform` und
// `SynthParams -> AudioCoreSynthParameters` ab (`AudioCoreMapping.swift`).
// Kein DSP-Verhalten — reine Werteabbildung.

final class AudioCoreMappingTests: XCTestCase {

    func test_waveformMapping_coversAllCases() {
        XCTAssertEqual(Waveform.sine.audioCoreWaveform, .sine)
        XCTAssertEqual(Waveform.saw.audioCoreWaveform, .saw)
        XCTAssertEqual(Waveform.square.audioCoreWaveform, .square)
        XCTAssertEqual(Waveform.triangle.audioCoreWaveform, .triangle)

        // Iteriert alle Faelle statt sie nur einzeln aufzuzaehlen — schuetzt
        // auch gegen einen kuenftig ergaenzten, aber im Mapping vergessenen Fall.
        XCTAssertEqual(Waveform.allCases.count, AudioCoreWaveform.allCases.count,
                       "Legacy- und Core-Wellenform-Fallmenge muessen deckungsgleich bleiben")
        for legacy in Waveform.allCases {
            XCTAssertEqual(legacy.audioCoreWaveform.rawValue, legacy.rawValue,
                           "Waveform \(legacy) muss denselben rawValue wie ihr Core-Gegenstueck behalten")
        }
    }

    func test_synthParamsMapping_coversAllElevenFields() {
        var params = SynthParams()
        params.waveform = .square
        params.attackMs = 12.5
        params.decayMs = 234.0
        params.sustain = 0.42
        params.releaseMs = 567.0
        params.maxVoices = 7
        params.filterCutoff = 0.33
        params.filterResonance = 0.81
        params.unisonVoices = 3
        params.unisonDetune = 15.0
        params.unisonSpread = 0.6

        let mapped = params.audioCoreParameters

        XCTAssertEqual(mapped.waveform, .square)
        XCTAssertEqual(mapped.attackMs, params.attackMs)
        XCTAssertEqual(mapped.decayMs, params.decayMs)
        XCTAssertEqual(mapped.sustain, params.sustain)
        XCTAssertEqual(mapped.releaseMs, params.releaseMs)
        XCTAssertEqual(mapped.maxVoices, params.maxVoices)
        XCTAssertEqual(mapped.filterCutoff, params.filterCutoff)
        XCTAssertEqual(mapped.filterResonance, params.filterResonance)
        XCTAssertEqual(mapped.unisonVoices, params.unisonVoices)
        XCTAssertEqual(mapped.unisonDetune, params.unisonDetune)
        XCTAssertEqual(mapped.unisonSpread, params.unisonSpread)
    }

    func test_defaultSynthParamsMapping_matchesAudioCoreDefaults() {
        XCTAssertEqual(SynthParams.defaults.audioCoreParameters, AudioCoreSynthParameters.defaults,
                       "SynthParams.defaults und AudioCoreSynthParameters.defaults muessen fachlich identisch bleiben")
    }
}
