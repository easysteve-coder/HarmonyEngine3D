// MARK: – AudioCoreTextureSource
//
// S-04b (`.agent_handoff/latest_codex.md`, Runde 051), Scope C: Texture
// Source C des Atmospheric-Synth-Fundaments (`SYNTH_ARCHITECTURE_PLAN.md`,
// Abschnitt 6.1). Kein Sampleimport, kein Dateizugriff, kein Granular —
// eine rein deterministische Rauschquelle mit explizitem RNG-Zustand
// (`state`) plus einfacher, stabiler One-Pole-Farbfilterung
// ("Brightness"). Granularwiedergabe folgt laut Plan erst spaeter.
//
// Determinismus: `state` ist ein expliziter xorshift64-Zustand. Gleicher
// Seed und gleiche Parameter erzeugen bei jedem Lauf bitgenau dieselbe
// Samplefolge — kein `Int.random`/`SystemRandomNumberGenerator`, die pro
// Prozess unterschiedliche Ergebnisse liefern wuerden.
//
// Farbfilterung: ein einzelner One-Pole-Tiefpass mit `brightness`-
// gesteuertem Filterkoeffizienten. `brightness = 0` ergibt eine stark
// gedaempfte, dunkle Textur (kleiner Koeffizient, langsame Filterantwort);
// `brightness = 1` naehert sich unfilteriertem weissen Rauschen an
// (Koeffizient nahe 1). Der Koeffizient bleibt bei jedem `brightness`-Wert
// im offenen Intervall `(0, 1)` — dadurch ist der Filter immer stabil
// (kein Einfrieren bei Koeffizient 0, keine Divergenz bei Koeffizient
// >= 1) und garantiert finite Ausgabe ohne DC-/Feedback-Explosion.
//
// Noch NICHT in `AudioCoreVoice`/`SynthNode` verwendet und nicht der aktive
// Klangpfad (Nicht-Scope S-04b).
//
// Realtime-Vertrag: `nextSample()`/`render(into:frameCount:)` alloziieren
// nicht, sperren nicht, nutzen keine Dispatch-/Task-/Actor-Ausfuehrung und
// schreiben nicht (kein `print`).

public struct AudioCoreTextureSource: Sendable, Equatable {

    /// Expliziter xorshift64-RNG-Zustand. Niemals `0` (degenerierter
    /// xorshift64-Fixpunkt) — ein Seed von `0` wird im Init auf einen festen
    /// von-Null-verschiedenen Ersatzwert abgebildet.
    public private(set) var state: UInt64

    /// Filterkoeffizient-Steuerung, geklemmt auf `0...1`. `0` = dunkel/stark
    /// gedaempft, `1` = nahe unfilteriertem weissen Rauschen.
    public private(set) var brightness: Float

    /// Ausgangspegel, geklemmt auf `0...1`.
    public private(set) var level: Float

    private var lowpassState: Float = 0

    private static let defaultSeedForZero: UInt64 = 0x9E37_79B9_7F4A_7C15

    public init(seed: UInt64, brightness: Float = 0.5, level: Float = 1.0) {
        self.state = seed == 0 ? AudioCoreTextureSource.defaultSeedForZero : seed
        self.brightness = AudioCoreTextureSource.clampUnit(brightness, fallback: 0.5)
        self.level = AudioCoreTextureSource.clampUnit(level, fallback: 0.0)
    }

    // MARK: – Parameter

    public mutating func setBrightness(_ value: Float) {
        brightness = AudioCoreTextureSource.clampUnit(value, fallback: 0.5)
    }

    public mutating func setLevel(_ value: Float) {
        level = AudioCoreTextureSource.clampUnit(value, fallback: 0.0)
    }

    /// Setzt RNG- UND Filterzustand explizit zurueck (z. B. fuer
    /// reproduzierbare Tests/Offline-Renders) — danach liefert dieselbe
    /// Aufrufsequenz bitgenau dieselben Samples wie eine frische Instanz mit
    /// identischem Seed. `0` wird wie im Init auf den festen Ersatzwert
    /// abgebildet.
    public mutating func resetState(to newState: UInt64) {
        state = newState == 0 ? AudioCoreTextureSource.defaultSeedForZero : newState
        lowpassState = 0
    }

    private static func clampUnit(_ value: Float, fallback: Float) -> Float {
        guard value.isFinite else { return fallback }
        return max(0.0, min(value, 1.0))
    }

    // MARK: – DSP-Render

    /// Erzeugt genau ein gefaerbtes Rauschsample und schreibt RNG- und
    /// Filterzustand fort. Kein Heap-Zugriff, kein Lock, kein Dispatch,
    /// kein `print`.
    @discardableResult
    public mutating func nextSample() -> Float {
        let white = nextWhiteSample()

        // Koeffizient bleibt immer in (0, 1): weder Einfrieren (0) noch
        // Divergenz (>= 1) moeglich, unabhaengig von `brightness`.
        let coefficient: Float = 0.001 + brightness * 0.98
        var newLowpassState = lowpassState + coefficient * (white - lowpassState)
        if !newLowpassState.isFinite { newLowpassState = 0 }
        lowpassState = newLowpassState

        let output = lowpassState * level
        return output.isFinite ? output : 0
    }

    /// Schreibt `frameCount` Samples in den aufrufer-bereitgestellten Puffer.
    @discardableResult
    public mutating func render(into buffer: UnsafeMutablePointer<Float>, frameCount: Int) -> Bool {
        for i in 0..<frameCount {
            buffer[i] = nextSample()
        }
        return true
    }

    // MARK: – Deterministisches weisses Rauschen (xorshift64)

    /// Naechster xorshift64-Zustand (Marsaglia), liefert 64 gleichverteilte
    /// Pseudozufallsbits. `state` ist niemals `0` (siehe Init), daher
    /// niemals im degenerierten Fixpunkt `0 -> 0`.
    private mutating func nextWhiteSample() -> Float {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17

        // obere 53 Bit exakt in Double darstellbar -> deterministische,
        // plattformunabhaengige Normierung auf [0, 1).
        let normalized = Double(state >> 11) * (1.0 / 9_007_199_254_740_992.0)
        return Float(normalized * 2.0 - 1.0)
    }
}
