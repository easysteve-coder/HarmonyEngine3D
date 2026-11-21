import Darwin

// MARK: – AudioCoreParameterSmoother
//
// S-05b (`.agent_handoff/latest_codex.md`, Runde 053), Scope C:
// wiederverwendbarer, deterministischer One-Pole-Glaettungsbaustein fuer
// Makro- oder Modulationszielwerte. Kein globaler Takt, kein `AudioClock`,
// kein Tempo-Sync — die Glaettungszeit ist ein expliziter, pro Instanz
// gesetzter Parameter (`timeMs`), identisch zum Ratenberechnungsprinzip in
// `AudioCoreEnvelope`/`AudioCoreVoice` (Zeit + Samplerate -> Koeffizient).
//
// Koeffizientenformel: `1 - exp(-1 / (timeMs * 0.001 * sampleRate))` — fuer
// jede endliche, positive `timeMs`/`sampleRate`-Kombination liegt das
// Ergebnis immer im offenen Intervall `(0, 1)` (kein Einfrieren, keine
// Divergenz), `timeMs <= 0` faellt auf einen sofortigen Sprung
// (Koeffizient `1`) zurueck.
//
// Realtime-Vertrag: `setTarget(_:)` alloziiert nicht, sperrt nicht, nutzt
// keine Dispatch-/Task-/Actor-Ausfuehrung und schreibt nicht (kein `print`).

public struct AudioCoreParameterSmoother: Sendable, Equatable {

    public let sampleRate: Double
    public private(set) var timeMs: Float
    public private(set) var currentValue: Float

    private var coefficient: Float

    public init(sampleRate: Double, timeMs: Float = 20.0, initialValue: Float = 0) {
        self.sampleRate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : 1.0
        self.timeMs = AudioCoreParameterSmoother.clampTime(timeMs)
        self.currentValue = initialValue.isFinite ? initialValue : 0
        self.coefficient = AudioCoreParameterSmoother.computeCoefficient(timeMs: self.timeMs, sampleRate: self.sampleRate)
    }

    // MARK: – Parameter

    public mutating func setTimeMs(_ ms: Float) {
        timeMs = AudioCoreParameterSmoother.clampTime(ms)
        coefficient = AudioCoreParameterSmoother.computeCoefficient(timeMs: timeMs, sampleRate: sampleRate)
    }

    // MARK: – Reset

    /// Setzt den laufenden Wert ohne Glaettungsrampe direkt auf `value`
    /// zurueck (z. B. Key-Sync/Testreproduzierbarkeit). Ein nachfolgender
    /// `setTarget(_:)`-Aufruf naehert sich von diesem Wert aus an.
    public mutating func reset(to value: Float = 0) {
        currentValue = value.isFinite ? value : 0
    }

    // MARK: – DSP-Render

    /// Naehert `currentValue` einen Glaettungsschritt in Richtung `target`
    /// an und gibt den neuen `currentValue` zurueck. Bei festem Koeffizient
    /// `(0, 1)` ist die Annaeherung an einen konstanten `target`-Wert immer
    /// monoton (kein Ueberschwingen, keine Oszillation). Kein Heap-Zugriff,
    /// kein Lock, kein Dispatch, kein `print`.
    @discardableResult
    public mutating func setTarget(_ target: Float) -> Float {
        let finiteTarget = target.isFinite ? target : 0
        var next = currentValue + coefficient * (finiteTarget - currentValue)
        if !next.isFinite { next = finiteTarget }
        currentValue = next
        return currentValue
    }

    // MARK: – Koeffizient

    private static func clampTime(_ ms: Float) -> Float {
        guard ms.isFinite else { return 20.0 }
        return max(0.0, ms)
    }

    private static func computeCoefficient(timeMs: Float, sampleRate: Double) -> Float {
        guard timeMs > 0 else { return 1.0 }
        let timeConstantSamples = Double(timeMs) * 0.001 * sampleRate
        guard timeConstantSamples > 0 else { return 1.0 }

        let raw = 1.0 - exp(-1.0 / timeConstantSamples)
        guard raw.isFinite else { return 1.0 }
        return Float(max(0.0001, min(raw, 1.0)))
    }
}
