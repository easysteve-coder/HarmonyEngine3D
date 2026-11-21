import XCTest
@testable import HarmonyEngine3D

// MARK: – AudioPresetFactoryAndMigrationTests
//
// S-03: `AudioPresetFactory` (vier Legacy-Kanalrollen mit stabilen IDs) und
// `AudioPresetLegacyMigration` (`ChannelFXConfig` <-> `AudioSynthPreset`
// Roundtrip, `AudioCoreSynthParameters`-Ableitung).

final class AudioPresetFactoryAndMigrationTests: XCTestCase {

    // MARK: – 5. Factory-Liste enthaelt genau die vier Legacy-Kanalrollen mit stabilen IDs

    func test_legacyPresets_containsExactlyFourChannelRolesWithStableIDs() {
        let presets = AudioPresetFactory.legacyPresets
        XCTAssertEqual(presets.count, 4)

        let idsByRole = Dictionary(uniqueKeysWithValues: presets.map { ($0.channelRole, $0.id) })
        XCTAssertEqual(idsByRole[.chord], AudioPresetFactory.LegacyID.chord)
        XCTAssertEqual(idsByRole[.bass], AudioPresetFactory.LegacyID.bass)
        XCTAssertEqual(idsByRole[.melody], AudioPresetFactory.LegacyID.melody)
        XCTAssertEqual(idsByRole[.chordTone], AudioPresetFactory.LegacyID.chordTone)

        let roles = Set(presets.map { $0.channelRole })
        XCTAssertEqual(roles, Set(AudioPresetChannelRole.allCases), "alle vier Kanalrollen muessen genau einmal vertreten sein")
    }

    func test_legacyPresets_areAllValidatorAcceptable() {
        for preset in AudioPresetFactory.legacyPresets {
            let result = AudioPresetValidator.validate(preset)
            XCTAssertTrue(result.isAcceptable, "\(preset.id): \(result.errors)")
        }
    }

    // MARK: – 6. Legacy-Migration aller vier ChannelFXConfig.*Defaults ist roundtrip-faehig

    func test_allFourChannelFXConfigDefaults_migrateRoundtripLossless() {
        let defaults: [(String, ChannelFXConfig, AudioPresetChannelRole)] = [
            ("chord", .chordDefaults, .chord),
            ("bass", .bassDefaults, .bass),
            ("melody", .melodyDefaults, .melody),
            ("chordTone", .chordToneDefaults, .chordTone)
        ]

        for (label, config, role) in defaults {
            let preset = config.audioSynthPreset(id: "roundtrip.\(label)", name: label, channelRole: role)
            let restored = preset.channelFXConfig
            XCTAssertEqual(restored, config, "\(label): ChannelFXConfig -> Preset -> ChannelFXConfig muss verlustfrei sein")
        }
    }

    func test_channelFXConfigMigration_preservesEveryFieldGroup() {
        let config = ChannelFXConfig.bassDefaults   // hat Unison aktiv (2 Stimmen) — deckt mehr Felder ab
        let preset = config.audioSynthPreset(id: "field-check", name: "Field Check", channelRole: .bass)

        // Synth-Felder
        XCTAssertEqual(preset.synth.waveform, config.waveform)
        XCTAssertEqual(preset.synth.attack, config.attack)
        XCTAssertEqual(preset.synth.decay, config.decay)
        XCTAssertEqual(preset.synth.sustain, config.sustain)
        XCTAssertEqual(preset.synth.release, config.release)
        XCTAssertEqual(preset.synth.filterCutoff, config.filterCutoff)
        XCTAssertEqual(preset.synth.filterResonance, config.filterResonance)
        XCTAssertEqual(preset.synth.unisonVoices, config.unisonVoices)
        XCTAssertEqual(preset.synth.unisonDetune, config.unisonDetune)
        XCTAssertEqual(preset.synth.unisonSpread, config.unisonSpread)

        // FX-/Channel-Felder
        XCTAssertEqual(preset.fx.delay1Time, config.delay1Time)
        XCTAssertEqual(preset.fx.delay2Feedback, config.delay2Feedback)
        XCTAssertEqual(preset.fx.delay3Mix, config.delay3Mix)
        XCTAssertEqual(preset.fx.delay1Pan, config.delay1Pan)
        XCTAssertEqual(preset.fx.reverbPreset, config.reverbPreset)
        XCTAssertEqual(preset.fx.reverbMix, config.reverbMix)
        XCTAssertEqual(preset.fx.channelVolume, config.channelVolume)
        XCTAssertEqual(preset.fx.pan, config.pan)
    }

    // MARK: – AudioCoreSynthParameters-Ableitung (Handoff: "Anteile vollstaendig abdecken")

    func test_audioCoreSynthParameters_matchesAudioEngineFormula() {
        // Werte manuell nach derselben Formel wie AudioEngine.synthParams(from:)
        // berechnet (siehe AudioEngine.swift, "SynthParams-Mapping"), NICHT aus
        // der Implementierung selbst abgeleitet — damit der Test einen echten
        // Formelfehler erkennen wuerde.
        let config = ChannelFXConfig.chordDefaults   // attack=0.02, decay=0.10, release=2.0
        let preset = config.audioSynthPreset(id: "formula-check", name: "Formula Check", channelRole: .chord)

        let expectedAttackMs = max(1.0, pow(Float(0.02), 2.0) * 2000.0 + 1.0)
        let expectedDecayMs  = max(1.0, Float(0.10) * 1000.0)
        let expectedReleaseMs = max(50.0, Float(2.0) * 1000.0)

        let derived = preset.synth.audioCoreSynthParameters
        XCTAssertEqual(derived.attackMs, expectedAttackMs, accuracy: 1e-4)
        XCTAssertEqual(derived.decayMs, expectedDecayMs, accuracy: 1e-4)
        XCTAssertEqual(derived.releaseMs, expectedReleaseMs, accuracy: 1e-4)
        XCTAssertEqual(derived.sustain, config.sustain)
        XCTAssertEqual(derived.filterCutoff, config.filterCutoff)
        XCTAssertEqual(derived.filterResonance, config.filterResonance)
        XCTAssertEqual(derived.waveform, config.waveform.audioCoreWaveform)
        XCTAssertEqual(derived.unisonVoices, config.unisonVoices)
        XCTAssertEqual(derived.unisonDetune, config.unisonDetune)
        XCTAssertEqual(derived.unisonSpread, config.unisonSpread)
        XCTAssertEqual(derived.maxVoices, 16)
    }

    func test_audioCoreSynthParameters_clampsExtremeValues() {
        let synth = AudioPresetSynthSection(
            waveform: .sine, attack: 2.0, decay: -5.0, sustain: 1.5, release: -1.0,
            filterCutoff: -0.5, filterResonance: 1.5, unisonVoices: -3, unisonDetune: -10.0,
            unisonSpread: 2.0, maxVoices: -1
        )
        let derived = synth.audioCoreSynthParameters

        XCTAssertTrue(derived.attackMs.isFinite)
        XCTAssertGreaterThanOrEqual(derived.decayMs, 1.0)
        XCTAssertGreaterThanOrEqual(derived.releaseMs, 50.0)
        XCTAssertEqual(derived.sustain, 1.0)
        XCTAssertEqual(derived.filterCutoff, 0.0)
        XCTAssertEqual(derived.filterResonance, 1.0)
        XCTAssertEqual(derived.unisonVoices, 1)
        XCTAssertEqual(derived.unisonDetune, 0.0)
        XCTAssertEqual(derived.unisonSpread, 1.0)
        XCTAssertEqual(derived.maxVoices, 1)
    }
}
