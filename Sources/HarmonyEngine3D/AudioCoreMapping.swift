import HarmonyAudioCore

// MARK: – AudioCoreMapping
//
// S-02b (`.agent_handoff/latest_codex.md`, Runde 047): schmales Mapping
// zwischen den App-Legacy-Typen (`Waveform`, `SynthParams`,
// `Sources/HarmonyEngine3D/SynthParams.swift`) und den Core-Typen
// (`AudioCoreWaveform`, `AudioCoreSynthParameters`, `HarmonyAudioCore`).
//
// Lebt bewusst im App-Target: `HarmonyAudioCore` darf `HarmonyEngine3D`
// nicht importieren, das Mapping muss daher hier stehen.

extension Waveform {

    /// Fachlich identische Core-Wellenform. 1:1-Fallabbildung, keine
    /// Interpretation.
    var audioCoreWaveform: AudioCoreWaveform {
        switch self {
        case .sine:     return .sine
        case .saw:      return .saw
        case .square:   return .square
        case .triangle: return .triangle
        }
    }
}

extension SynthParams {

    /// Vollstaendige Core-Parameterabbildung — alle elf Legacy-Felder.
    var audioCoreParameters: AudioCoreSynthParameters {
        AudioCoreSynthParameters(
            waveform: waveform.audioCoreWaveform,
            attackMs: attackMs,
            decayMs: decayMs,
            sustain: sustain,
            releaseMs: releaseMs,
            maxVoices: maxVoices,
            filterCutoff: filterCutoff,
            filterResonance: filterResonance,
            unisonVoices: unisonVoices,
            unisonDetune: unisonDetune,
            unisonSpread: unisonSpread
        )
    }

    /// Parametersatz der Atmospheric Voice (W-03b1).
    ///
    /// Bewusst eine SCHMALE Abbildung: uebertragen werden ausschliesslich die
    /// Werte, die es in `SynthParams` ueberhaupt gibt und deren Bedeutung in
    /// beiden Stimmtypen dieselbe ist — die vier ADSR-Zeiten als Amp-Huelle
    /// sowie Filter-Cutoff und -Resonanz (beide normiert `0…1`, in beiden
    /// Stimmen logarithmisch auf 20 Hz…20 kHz bzw. Q 0,5…20 abgebildet).
    /// Alles Uebrige — Quellen-Mix, Morphposition, Textur, Waveshaper,
    /// Mod-Huelle, LFOs, Modulationsmatrix, Makros — bleibt auf den in W-01
    /// dokumentierten Defaults.
    ///
    /// Seit W-03c kommt `spaceSend` hinzu: der Basis-Sendpegel in den
    /// gemeinsamen Raum. Er ist kein Klangparameter der Stimme (die Stimme
    /// wendet ihn nicht an, siehe `AudioCoreAtmosphericVoice.spaceSendLevel`),
    /// sondern die Vorgabe fuer den Sendweg — und deshalb der einzige Wert
    /// dieser Abbildung, der die Stimme wieder verlaesst statt in ihr zu
    /// wirken. Der neutrale `SynthParams`-Default ist `0`; den produktiv
    /// verwendeten Wert setzt `AudioEngine.synthParams(from:)`.
    ///
    /// Seit W-05 kommen die vier Makros hinzu. Sie sind der zweite Wert
    /// dieser Abbildung, der nicht selbst klingt: die Stimme legt sie in
    /// `AudioCoreModulationSourceValues` und laesst die Modulationsmatrix
    /// entscheiden, welches Ziel sich bewegt.
    ///
    /// **Warum die Stimme die Makrowerte NICHT zusaetzlich direkt bekommt**
    /// (die Frage aus dem W-05-Handoff): die bestehende Verschaltung reicht,
    /// und ein direkter Weg waere schlechter. Die Matrix liefert bereits
    /// alles, was fehlt — Klemmung auf `[-1, 1]`, deterministische
    /// Zielakkumulation und die Glaettung ueber die sieben
    /// `AudioCoreParameterSmoother` der Stimme. Ein direkter Makrozugriff
    /// muesste diese drei Dinge duplizieren und wuerde zugleich festschreiben,
    /// WELCHES Ziel ein Makro bewegt — also genau das Controller-Mapping im
    /// Synth-Core, das `SYNTH_ARCHITECTURE_PLAN.md` Abschnitt 10 ausdruecklich
    /// ausschliesst ("kein Controller-Mapping wird im Synth-Core
    /// hardcodiert"; "ein Preset definiert, welche internen Ziele ein Makro
    /// bewegt", Abschnitt 6.5). Was gefehlt hat, war nicht der Weg, sondern
    /// die Routen — die liegen jetzt in
    /// `AudioCoreAtmosphericVoiceParameters.defaultModulationMatrix` und
    /// bleiben damit austauschbare Daten statt Code.
    ///
    /// Bewusst NICHT abgebildet:
    ///   – `waveform`: die Atmospheric Voice hat keine Wellenform-Auswahl,
    ///     sondern zwei Wavetables plus Morphposition. Eine Zuordnung
    ///     (z. B. `.saw` → Morph 0,8) waere eine Klangentscheidung und kein
    ///     Mapping — sie gehoert zu W-05, nicht hierher.
    ///   – `unisonVoices`/`unisonDetune`/`unisonSpread`: liegen wie bisher
    ///     im `VoicePool` (Detune-/Pan-Verteilung ueber mehrere Stimmen), nicht
    ///     im Parametersatz einer einzelnen Stimme.
    ///   – `maxVoices`: Poolgroesse, nach `prepare()` fixiert.
    ///
    /// Allokationsfrei: der Initialisierer klemmt nur Skalare und uebernimmt
    /// die `modulationMatrix` als Referenz, ohne sie neu zu bauen (siehe
    /// `AudioCoreAtmosphericVoiceParameters`, Abschnitt "Ausnahme mit
    /// Begruendung").
    var atmosphericVoiceParameters: AudioCoreAtmosphericVoiceParameters {
        AudioCoreAtmosphericVoiceParameters(
            filterCutoff:    filterCutoff,
            filterResonance: filterResonance,
            ampEnvelope: AudioCoreEnvelopeParameters(
                attackMs:     attackMs,
                decayMs:      decayMs,
                sustainLevel: sustain,
                releaseMs:    releaseMs
            ),
            macros: macros,
            spaceSend: spaceSend
        )
    }
}
