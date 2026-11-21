import Foundation

// MARK: – AudioPresetValidator
//
// S-03: strukturierter Validierungsvertrag für `AudioSynthPreset`, im
// selben Stil wie `HarmonyMapValidator` (`HarmonyShared`): `Issue`-Werte
// mit `severity`/`code`/`objectPath`/`message` statt Bool-Flag oder
// print-Logging.
//
// Severity-Policy:
//   – Error:   strukturell ungültig (leere id/name, nicht unterstützte
//     schemaVersion, nicht-endliche Zahlen, Voice-/Stimmenzahlen < 1) —
//     blockiert Export/Save in den validierten Store-Pfaden.
//   – Warning: Wert liegt außerhalb des heute dokumentierten/im Produkt
//     tatsächlich geclampten Bereichs (siehe `AudioEngine.applyEffectConfigX`/
//     `ChannelFXConfig`-Feldkommentare) — blockiert nicht, weil AudioEngine
//     solche Werte schon heute sicher klemmt statt abzustürzen.
//
// Kein SceneKit, kein AppSettings, kein UI.

enum AudioPresetValidator {

    enum Severity: String {
        case error
        case warning
    }

    struct Issue: CustomStringConvertible {
        let severity:   Severity
        let code:       String
        let objectPath: String
        let message:    String

        var description: String { "[\(severity.rawValue)] \(code) @ \(objectPath): \(message)" }
    }

    struct Result {
        let issues: [Issue]

        var errors:   [Issue] { issues.filter { $0.severity == .error } }
        var warnings: [Issue] { issues.filter { $0.severity == .warning } }
        /// true nur wenn keine Errors vorliegen — Warnings blockieren nicht.
        var isAcceptable: Bool { errors.isEmpty }
    }

    // MARK: – Validate

    static func validate(_ preset: AudioSynthPreset) -> Result {
        var issues: [Issue] = []

        // ── schemaVersion — Hard Check ────────────────────────────────────
        if preset.schemaVersion != AudioSynthPreset.currentSchemaVersion {
            issues.append(Issue(
                severity: .error, code: "schemaVersionUnsupported", objectPath: "$.schemaVersion",
                message: "schemaVersion '\(preset.schemaVersion)' nicht unterstützt"
                    + " (erwartet: \"\(AudioSynthPreset.currentSchemaVersion)\")"
            ))
        }

        // ── id / name ──────────────────────────────────────────────────────
        if preset.id.isEmpty {
            issues.append(Issue(severity: .error, code: "presetIdEmpty", objectPath: "$.id",
                                 message: "id ist leer"))
        }
        if preset.name.isEmpty {
            issues.append(Issue(severity: .error, code: "presetNameEmpty", objectPath: "$.name",
                                 message: "name ist leer"))
        }

        // ── Synth-Sektion ──────────────────────────────────────────────────
        let synth = preset.synth
        let synthPath = "$.synth"

        checkFinite(synth.attack, "attack", synthPath, &issues)
        checkFinite(synth.decay, "decay", synthPath, &issues)
        checkFinite(synth.sustain, "sustain", synthPath, &issues)
        checkFinite(synth.release, "release", synthPath, &issues)
        checkFinite(synth.filterCutoff, "filterCutoff", synthPath, &issues)
        checkFinite(synth.filterResonance, "filterResonance", synthPath, &issues)
        checkFinite(synth.unisonDetune, "unisonDetune", synthPath, &issues)
        checkFinite(synth.unisonSpread, "unisonSpread", synthPath, &issues)

        if synth.unisonVoices < 1 {
            issues.append(Issue(severity: .error, code: "unisonVoicesInvalid", objectPath: synthPath,
                                 message: "unisonVoices \(synth.unisonVoices) < 1"))
        }
        if synth.maxVoices < 1 {
            issues.append(Issue(severity: .error, code: "maxVoicesInvalid", objectPath: synthPath,
                                 message: "maxVoices \(synth.maxVoices) < 1"))
        }

        checkRange(synth.attack, "attack", 0...1, synthPath, &issues)
        checkRange(synth.decay, "decay", 0.001...2.0, synthPath, &issues)
        checkRange(synth.sustain, "sustain", 0...1, synthPath, &issues)
        checkRange(synth.release, "release", 0.1...4.0, synthPath, &issues)
        checkRange(synth.filterCutoff, "filterCutoff", 0...1, synthPath, &issues)
        checkRange(synth.filterResonance, "filterResonance", 0...1, synthPath, &issues)
        checkRange(synth.unisonDetune, "unisonDetune", 0...20, synthPath, &issues)
        checkRange(synth.unisonSpread, "unisonSpread", 0...1, synthPath, &issues)

        // ── FX-Sektion ─────────────────────────────────────────────────────
        let fx = preset.fx
        let fxPath = "$.fx"

        for (label, time, feedback, mix, pan) in [
            ("delay1", fx.delay1Time, fx.delay1Feedback, fx.delay1Mix, fx.delay1Pan),
            ("delay2", fx.delay2Time, fx.delay2Feedback, fx.delay2Mix, fx.delay2Pan),
            ("delay3", fx.delay3Time, fx.delay3Feedback, fx.delay3Mix, fx.delay3Pan)
        ] {
            checkFinite(time, "\(label)Time", fxPath, &issues)
            checkFinite(feedback, "\(label)Feedback", fxPath, &issues)
            checkFinite(mix, "\(label)Mix", fxPath, &issues)
            checkFinite(pan, "\(label)Pan", fxPath, &issues)

            checkRange(time, "\(label)Time", 0.001...2.0, fxPath, &issues)
            checkRange(feedback, "\(label)Feedback", 0...1, fxPath, &issues)
            checkRange(mix, "\(label)Mix", 0...1, fxPath, &issues)
            checkRange(pan, "\(label)Pan", -1...1, fxPath, &issues)
        }

        checkFinite(fx.reverbMix, "reverbMix", fxPath, &issues)
        checkFinite(fx.channelVolume, "channelVolume", fxPath, &issues)
        checkFinite(fx.pan, "pan", fxPath, &issues)

        checkRange(fx.reverbMix, "reverbMix", 0...1, fxPath, &issues)
        checkRange(fx.channelVolume, "channelVolume", 0...1, fxPath, &issues)
        checkRange(fx.pan, "pan", -1...1, fxPath, &issues)

        // reverbPreset: heutiger Int-Wert ohne neue musikalische Bewertung
        // (siehe Handoff) — 0...11 sind die zwölf in `AudioMixerPanel`
        // angebotenen `AVAudioUnitReverbPreset`-Werte. `AudioEngine` faellt
        // bei unbekanntem Wert bereits sicher auf `.largeHall` zurueck
        // (`AVAudioUnitReverbPreset(rawValue:) ?? .largeHall`) — deshalb nur
        // Warning, kein Error.
        if !(0...11).contains(fx.reverbPreset) {
            issues.append(Issue(
                severity: .warning, code: "reverbPresetOutOfKnownRange", objectPath: fxPath,
                message: "reverbPreset \(fx.reverbPreset) außerhalb der bekannten Presets 0...11"
                    + " (AudioEngine faellt sicher auf .largeHall zurueck)"
            ))
        }

        return Result(issues: issues)
    }

    // MARK: – Helfer

    private static func checkFinite(_ value: Float, _ field: String, _ path: String,
                                     _ issues: inout [Issue]) {
        guard !value.isFinite else { return }
        issues.append(Issue(severity: .error, code: "fieldNonFinite", objectPath: path,
                             message: "\(field) ist nicht endlich (\(value))"))
    }

    private static func checkRange(_ value: Float, _ field: String, _ range: ClosedRange<Float>,
                                    _ path: String, _ issues: inout [Issue]) {
        guard value.isFinite, !range.contains(value) else { return }
        issues.append(Issue(
            severity: .warning, code: "fieldOutOfDocumentedRange", objectPath: path,
            message: "\(field) \(value) außerhalb des dokumentierten Bereichs \(range.lowerBound)"
                + "...\(range.upperBound)"
        ))
    }
}
