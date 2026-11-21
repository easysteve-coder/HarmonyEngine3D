import Foundation

// MARK: – EchoFieldPresetValidator
//
// S-07b: strukturierter Validierungsvertrag fuer `EchoFieldPreset`, im
// selben Stil wie `AudioPresetValidator`/`HarmonyMapValidator`: `Issue`-
// Werte mit `severity`/`code`/`objectPath`/`message` statt Bool-Flag.
//
// Severity-Policy (analog `AudioPresetValidator`):
//   – Error:   strukturell ungueltig (leere id/name, nicht unterstuetzte
//     schemaVersion, nicht-endliche Zahlen) oder ein konkretes
//     Feedback-Runaway-Risiko (feedback >= 1.0 – ein Delay-Tap ohne
//     Daempfung sustaint unbegrenzt statt abzuklingen).
//   – Warning: Wert liegt ausserhalb des im Plan dokumentierten Bereichs
//     (`SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 7.2), aber strukturell
//     gueltig – blockiert nicht, weil dieses Slice ohnehin keinen
//     DSP-Konsumenten hat, der den Wert unsicher verwenden koennte.
//
// Kein SceneKit, kein AppSettings, kein UI.

enum EchoFieldPresetValidator {

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
        /// true nur wenn keine Errors vorliegen – Warnings blockieren nicht.
        var isAcceptable: Bool { errors.isEmpty }
    }

    /// Dokumentierter Zeitbereich aus dem Plan (Abschnitt 7.2): 1 ms bis 4 s.
    static let documentedTimeRange: ClosedRange<Float> = 0.001...4.0
    /// Feedback jenseits dieser Grenze ist ein konkretes Runaway-Risiko,
    /// nicht nur "undokumentiert" – siehe Severity-Policy oben.
    static let feedbackRunawayThreshold: Float = 1.0

    // MARK: – Validate

    static func validate(_ preset: EchoFieldPreset) -> Result {
        var issues: [Issue] = []

        // ── schemaVersion — Hard Check ────────────────────────────────────
        if preset.schemaVersion != EchoFieldPreset.currentSchemaVersion {
            issues.append(Issue(
                severity: .error, code: "schemaVersionUnsupported", objectPath: "$.schemaVersion",
                message: "schemaVersion '\(preset.schemaVersion)' nicht unterstützt"
                    + " (erwartet: \"\(EchoFieldPreset.currentSchemaVersion)\")"
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

        // ── Taps ───────────────────────────────────────────────────────────
        let labeledTaps: [(String, EchoFieldTap)] = [
            ("tap1", preset.tap1), ("tap2", preset.tap2),
            ("tap3", preset.tap3), ("tap4", preset.tap4)
        ]

        for (label, tap) in labeledTaps {
            let path = "$.\(label)"

            checkFinite(tap.time, "time", path, &issues)
            checkFinite(tap.feedback, "feedback", path, &issues)
            checkFinite(tap.mix, "mix", path, &issues)
            checkFinite(tap.pan, "pan", path, &issues)

            checkRange(tap.time, "time", documentedTimeRange, path, &issues)
            checkRange(tap.mix, "mix", 0...1, path, &issues)
            checkRange(tap.pan, "pan", -1...1, path, &issues)

            // Feedback: dokumentierter Bereich als Warning (wie andere
            // Felder), zusaetzlich ein blockierender Error ab der
            // Runaway-Schwelle – siehe Severity-Policy oben.
            checkRange(tap.feedback, "feedback", 0...0.98, path, &issues)
            if tap.feedback.isFinite, tap.feedback >= feedbackRunawayThreshold {
                issues.append(Issue(
                    severity: .error, code: "tapFeedbackRunawayRisk", objectPath: path,
                    message: "feedback \(tap.feedback) >= \(feedbackRunawayThreshold) – Tap sustaint unbegrenzt statt abzuklingen"
                ))
            }
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
