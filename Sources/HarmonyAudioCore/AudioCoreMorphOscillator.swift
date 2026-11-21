import Darwin

// MARK: – AudioCoreMorphOscillator
//
// S-04a (`.agent_handoff/latest_codex.md`, Runde 049): erster reiner
// Oszillatorzustand des Atmospheric-Synth-Fundaments (Source A,
// `SYNTH_ARCHITECTURE_PLAN.md` Abschnitt 6.1). Liest phasenkonsistent aus
// zwei `AudioCoreWavetable`-Instanzen und morpht kontinuierlich zwischen
// ihnen. Kennt weder MIDI noch Harmonie/Akkordsemantik — Frequenz kommt
// ausschliesslich in Hz.
//
// Phasenkonsistenz: beide Wellenformen sind bei Phase 0 auf denselben
// Tabellenindex 0 verankert (reine additive Sinus-Synthese ohne
// Zufallsphasen, siehe `AudioCoreWavetableBank`). Ein linear gewichteter
// Uebergang zwischen beiden Tabellenwerten an identischer Phase erzeugt
// deshalb keinen Phasensprung.
//
// Noch NICHT in `AudioCoreVoice`/`SynthNode` verwendet und nicht der aktive
// Klangpfad (Nicht-Scope S-04a).
//
// Realtime-Vertrag: `nextSample()`/`render(into:frameCount:)` alloziieren
// nicht, sperren nicht, nutzen keine Dispatch-/Task-/Actor-Ausfuehrung und
// schreiben nicht (kein `print`).

public struct AudioCoreMorphOscillator: Sendable {

    public let sampleRate: Double
    public let wavetableA: AudioCoreWavetable
    public let wavetableB: AudioCoreWavetable

    private var phase: Double = 0

    public private(set) var frequencyHz: Double
    public private(set) var morph: Float

    private var mipIndexA: Int
    private var mipIndexB: Int

    public init(sampleRate: Double,
                wavetableA: AudioCoreWavetable,
                wavetableB: AudioCoreWavetable,
                frequencyHz: Double = 440.0,
                morph: Float = 0.0) {
        self.sampleRate = sampleRate > 0 ? sampleRate : 1.0
        self.wavetableA = wavetableA
        self.wavetableB = wavetableB

        let clampedFreq = AudioCoreMorphOscillator.clampFrequency(frequencyHz, sampleRate: self.sampleRate)
        self.frequencyHz = clampedFreq
        self.morph = max(0.0, min(morph, 1.0))

        self.mipIndexA = wavetableA.mipLevelIndex(frequencyHz: clampedFreq, sampleRate: self.sampleRate)
        self.mipIndexB = wavetableB.mipLevelIndex(frequencyHz: clampedFreq, sampleRate: self.sampleRate)
    }

    // MARK: – Parameter (Scope D: kleine, explizite Parametergrenzen)

    /// Setzt die Grundfrequenz in Hz. Wird auf `0...Nyquist` geklemmt (nicht
    /// endliche/negative Werte werden zu `0`) und waehlt sofort die
    /// passende Mip-Stufe pro Tabelle neu.
    public mutating func setFrequency(_ hz: Double) {
        frequencyHz = AudioCoreMorphOscillator.clampFrequency(hz, sampleRate: sampleRate)
        mipIndexA = wavetableA.mipLevelIndex(frequencyHz: frequencyHz, sampleRate: sampleRate)
        mipIndexB = wavetableB.mipLevelIndex(frequencyHz: frequencyHz, sampleRate: sampleRate)
    }

    /// Setzt die Morph-Position, geklemmt auf `0...1`. `0` = reines
    /// Spektrum A (`wavetableA`), `1` = reines Spektrum B (`wavetableB`).
    public mutating func setMorph(_ value: Float) {
        morph = max(0.0, min(value, 1.0))
    }

    /// Setzt die Phase explizit (z. B. fuer Tests), gewrapped auf `[0, 1)`.
    /// Eine nicht-endliche `newPhase` (`.nan`/`.infinity`) faellt auf Phase
    /// `0` zurueck (S-04a-fix, Runde 050) — sonst bliebe `wrapped` nach
    /// `truncatingRemainder(dividingBy:)` nicht-endlich und liesse eine
    /// spaetere `Double -> Int`-Konvertierung in `AudioCoreWavetable.sample`
    /// trappen.
    public mutating func resetPhase(to newPhase: Double = 0) {
        let finitePhase = newPhase.isFinite ? newPhase : 0
        var wrapped = finitePhase.truncatingRemainder(dividingBy: 1.0)
        if wrapped < 0 { wrapped += 1.0 }
        phase = wrapped
    }

    private static func clampFrequency(_ hz: Double, sampleRate: Double) -> Double {
        guard hz.isFinite, hz > 0 else { return 0 }
        let nyquist = sampleRate * 0.5
        return min(hz, nyquist)
    }

    // MARK: – DSP-Render

    /// Liest genau ein Sample und schreibt die Phase fort. Kein Heap-Zugriff,
    /// kein Lock, kein Dispatch, kein `print`.
    @discardableResult
    public mutating func nextSample() -> Float {
        let sampleA = wavetableA.sample(phase: phase, mipLevelIndex: mipIndexA)
        let sampleB = wavetableB.sample(phase: phase, mipLevelIndex: mipIndexB)
        let output = sampleA * (1.0 - morph) + sampleB * morph

        let phaseIncrement = sampleRate > 0 ? frequencyHz / sampleRate : 0
        phase += phaseIncrement
        if phase >= 1.0 { phase -= 1.0 }

        return output
    }

    /// Schreibt `frameCount` Samples in den aufrufer-bereitgestellten Puffer.
    /// Optionale Test-/Offline-Render-Hilfsfunktion — noch nicht der
    /// produktive Renderpfad (Nicht-Scope S-04a).
    @discardableResult
    public mutating func render(into buffer: UnsafeMutablePointer<Float>, frameCount: Int) -> Bool {
        for i in 0..<frameCount {
            buffer[i] = nextSample()
        }
        return true
    }
}
