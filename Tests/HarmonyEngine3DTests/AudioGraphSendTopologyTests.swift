import XCTest
@testable import HarmonyEngine3D

// MARK: – AudioGraphSendTopologyTests
//
// S-07a: reine Topologie-Deskriptor-Tests ohne AVAudioEngine-/Hardware-
// Abhängigkeit. Verifizieren den deklarativen Plan, an welchem Punkt im
// Kanal-Signalfluss ein späterer gemeinsamer Echo-/Space-Send abgreifen
// soll — insbesondere den CH1-Kompressor-Option-A-Nachweis.

final class AudioGraphSendTopologyTests: XCTestCase {

    func test_planCoversAllFourChannels() {
        let channels = Set(AudioGraphSendTopology.plan.map(\.channel))
        XCTAssertEqual(channels, [0, 1, 2, 3])
    }

    func test_planHasNoDuplicateChannelEntries() {
        let channels = AudioGraphSendTopology.plan.map(\.channel)
        XCTAssertEqual(channels.count, Set(channels).count)
    }

    func test_ch1Bass_tapsBeforeChannelDynamics_optionA() {
        // Stephan-Entscheidung 2026-07-30, Option A: der CH1-Kompressor
        // bleibt auf den CH1-Dry-Pfad beschränkt. Der spätere gemeinsame
        // Send muss daher VOR dem Kompressor abgreifen, nicht dahinter.
        XCTAssertEqual(AudioGraphSendTopology.tapPoint(forChannel: 1), .preChannelDynamics)
    }

    func test_otherChannels_tapDirectlyAfterGain() {
        XCTAssertEqual(AudioGraphSendTopology.tapPoint(forChannel: 0), .postGain)
        XCTAssertEqual(AudioGraphSendTopology.tapPoint(forChannel: 2), .postGain)
        XCTAssertEqual(AudioGraphSendTopology.tapPoint(forChannel: 3), .postGain)
    }

    func test_unknownChannel_hasNoTapPoint() {
        XCTAssertNil(AudioGraphSendTopology.tapPoint(forChannel: 99))
    }
}
