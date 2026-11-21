import Foundation
import HarmonyAudioCore

// MARK: – AudioPresetLegacyMigration
//
// S-03: explizite, testbare Migration zwischen dem heutigen
// `ChannelFXConfig` (`AppSettings.swift`) und dem neuen `AudioSynthPreset`-
// Modell. Bewusst eine Funktion, keine stille Default-Fuellung — jedes
// Feld wird 1:1 übernommen, keine Formel-Rundung, damit der Roundtrip
// verlustfrei bleibt.
//
// `AudioPresetSynthSection.audioCoreSynthParameters` deckt zusätzlich den
// Handoff-Punkt "SynthParams/AudioCoreSynthParameters-Anteile vollständig
// abdecken" ab: eine reine, abgeleitete Übersetzung nach
// `AudioCoreSynthParameters`, mit EXAKT derselben Formel wie
// `AudioEngine.synthParams(from:)` (dort `private`, hier bewusst
// eigenständig gehalten statt AudioEngine.swift für diesen reinen
// Daten-/Persistenzslice anzufassen — siehe Nicht-Scope "kein Audio-Graph-
// Umbau"). Nur eine Leserichtung (Preset → AudioCoreSynthParameters); die
// Migration zurueck zu `ChannelFXConfig` verlaeuft ueber die
// unveraenderten Rohfelder, nicht ueber diese Ableitung.

extension ChannelFXConfig {

    /// Erzeugt ein `AudioSynthPreset`, das diese `ChannelFXConfig`
    /// verlustfrei beschreibt (1:1-Feldkopie, keine Formel-Transformation).
    func audioSynthPreset(id: String, name: String, channelRole: AudioPresetChannelRole,
                           author: String? = nil, engineVersion: String? = nil) -> AudioSynthPreset {
        AudioSynthPreset(
            schemaVersion: AudioSynthPreset.currentSchemaVersion,
            id: id,
            name: name,
            channelRole: channelRole,
            author: author,
            engineVersion: engineVersion,
            synth: AudioPresetSynthSection(
                waveform: waveform,
                attack: attack,
                decay: decay,
                sustain: sustain,
                release: release,
                filterCutoff: filterCutoff,
                filterResonance: filterResonance,
                unisonVoices: unisonVoices,
                unisonDetune: unisonDetune,
                unisonSpread: unisonSpread,
                maxVoices: 16   // heutige AudioEngine-Konstante, siehe SynthNode.prepare()
            ),
            fx: AudioPresetFXSection(
                delay1Time: delay1Time, delay1Feedback: delay1Feedback,
                delay1Mix: delay1Mix, delay1Pan: delay1Pan,
                delay2Time: delay2Time, delay2Feedback: delay2Feedback,
                delay2Mix: delay2Mix, delay2Pan: delay2Pan,
                delay3Time: delay3Time, delay3Feedback: delay3Feedback,
                delay3Mix: delay3Mix, delay3Pan: delay3Pan,
                reverbPreset: reverbPreset,
                reverbMix: reverbMix,
                channelVolume: channelVolume,
                pan: pan
            )
        )
    }
}

extension AudioSynthPreset {

    /// Rekonstruiert eine `ChannelFXConfig` aus diesem Preset — verlustfrei
    /// für alle heutigen `ChannelFXConfig`-Felder (1:1-Feldkopie). `id`,
    /// `name`, `channelRole`, `author`, `engineVersion` und `maxVoices`
    /// existieren in `ChannelFXConfig` nicht und werden nicht übernommen.
    var channelFXConfig: ChannelFXConfig {
        ChannelFXConfig(
            delay1Time: fx.delay1Time, delay1Feedback: fx.delay1Feedback,
            delay1Mix: fx.delay1Mix, delay1Pan: fx.delay1Pan,
            delay2Time: fx.delay2Time, delay2Feedback: fx.delay2Feedback,
            delay2Mix: fx.delay2Mix, delay2Pan: fx.delay2Pan,
            delay3Time: fx.delay3Time, delay3Feedback: fx.delay3Feedback,
            delay3Mix: fx.delay3Mix, delay3Pan: fx.delay3Pan,
            reverbPreset: fx.reverbPreset,
            reverbMix: fx.reverbMix,
            channelVolume: fx.channelVolume,
            attack: synth.attack,
            decay: synth.decay,
            sustain: synth.sustain,
            release: synth.release,
            filterCutoff: synth.filterCutoff,
            filterResonance: synth.filterResonance,
            waveform: synth.waveform,
            pan: fx.pan,
            unisonVoices: synth.unisonVoices,
            unisonDetune: synth.unisonDetune,
            unisonSpread: synth.unisonSpread
        )
    }
}

extension AudioPresetSynthSection {

    /// Reine, abgeleitete Übersetzung nach `AudioCoreSynthParameters` —
    /// IDENTISCHE Formel zu `AudioEngine.synthParams(from:)`
    /// (`Sources/HarmonyEngine3D/AudioEngine.swift`): quadratische
    /// Attack-Kurve, lineare Decay-/Release-Umrechnung in Millisekunden,
    /// dieselben Clamp-Grenzen. Absichtlich hier dupliziert statt aus
    /// `AudioEngine` heraus geteilt, um diesen reinen Daten-/Persistenz-
    /// slice ohne jede Audio-Graph-Berührung zu halten (Nicht-Scope S-03).
    /// Nur zur Ableitung/Vorschau gedacht — noch nicht runtime-verdrahtet.
    var audioCoreSynthParameters: AudioCoreSynthParameters {
        let attackMs = max(1.0, pow(attack, 2.0) * 2000.0 + 1.0)
        return AudioCoreSynthParameters(
            waveform: waveform.audioCoreWaveform,
            attackMs: attackMs,
            decayMs: max(1.0, decay * 1000.0),
            sustain: max(0.0, min(sustain, 1.0)),
            releaseMs: max(50.0, release * 1000.0),
            maxVoices: max(1, maxVoices),
            filterCutoff: max(0.0, min(filterCutoff, 1.0)),
            filterResonance: max(0.0, min(filterResonance, 1.0)),
            unisonVoices: max(1, unisonVoices),
            unisonDetune: max(0.0, unisonDetune),
            unisonSpread: max(0.0, min(unisonSpread, 1.0))
        )
    }
}
