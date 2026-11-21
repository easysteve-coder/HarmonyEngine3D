import Darwin

// MARK: – AudioCoreSourceB
//
// S-04b (`.agent_handoff/latest_codex.md`, Runde 051), Scope B: zweite,
// unabhaengige Morph-Oszillator-Quelle des Atmospheric-Synth-Fundaments
// (`SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 6.1). Wrappt einen eigenen
// `AudioCoreMorphOscillator` (Scope-Vorgabe: "Source B darf den bestehenden
// AudioCoreMorphOscillator wiederverwenden") und fuegt ausschliesslich die
// fuer Source B geforderte Parameterschicht hinzu:
//
//   – Transposition in Halbtoenen (`transpositionSemitones`);
//   – Feinstimmung in Cent (`fineTuneCents`), reine Hz-Skalierung;
//   – eigene Phase/Reset-Logik (delegiert an den gekapselten Oszillator,
//     dadurch unabhaengig von Source A).
//
// Kennt weder MIDI noch Harmonie-/Akkordlogik — Grundfrequenz kommt
// ausschliesslich in Hz (`baseFrequencyHz`, vom Aufrufer gesetzt, z. B. aus
// derselben MIDI->Hz-Umrechnung wie Source A).
//
// Noch NICHT in `AudioCoreVoice`/`SynthNode` verwendet und nicht der aktive
// Klangpfad (Nicht-Scope S-04b).
//
// Realtime-Vertrag: `nextSample()`/`render(into:frameCount:)` alloziieren
// nicht, sperren nicht, nutzen keine Dispatch-/Task-/Actor-Ausfuehrung und
// schreiben nicht (kein `print`).

public struct AudioCoreSourceB: Sendable {

    public let sampleRate: Double

    private var oscillator: AudioCoreMorphOscillator

    /// Unskalierte Grundfrequenz in Hz (z. B. dieselbe Notenfrequenz wie
    /// Source A, ohne Transposition/Feinstimmung).
    public private(set) var baseFrequencyHz: Double

    /// Transposition in Halbtoenen, geklemmt auf `-24...24`.
    public private(set) var transpositionSemitones: Double

    /// Feinstimmung in Cent, geklemmt auf `-100...100` (ein Halbton).
    public private(set) var fineTuneCents: Double

    public init(sampleRate: Double,
                wavetableA: AudioCoreWavetable,
                wavetableB: AudioCoreWavetable,
                baseFrequencyHz: Double = 440.0,
                transpositionSemitones: Double = 0,
                fineTuneCents: Double = 0,
                morph: Float = 0.0) {
        let clampedSampleRate = sampleRate > 0 ? sampleRate : 1.0
        self.sampleRate = clampedSampleRate
        self.baseFrequencyHz = AudioCoreSourceB.clampBaseFrequency(baseFrequencyHz)
        self.transpositionSemitones = AudioCoreSourceB.clampTransposition(transpositionSemitones)
        self.fineTuneCents = AudioCoreSourceB.clampFineTune(fineTuneCents)

        let effectiveHz = AudioCoreSourceB.effectiveFrequency(base: self.baseFrequencyHz,
                                                                semitones: self.transpositionSemitones,
                                                                cents: self.fineTuneCents)
        self.oscillator = AudioCoreMorphOscillator(sampleRate: clampedSampleRate,
                                                     wavetableA: wavetableA,
                                                     wavetableB: wavetableB,
                                                     frequencyHz: effectiveHz,
                                                     morph: morph)
    }

    // MARK: – Parameter

    /// Setzt die unskalierte Grundfrequenz in Hz. Nicht-endliche/negative
    /// Werte werden zu `0`.
    public mutating func setBaseFrequency(_ hz: Double) {
        baseFrequencyHz = AudioCoreSourceB.clampBaseFrequency(hz)
        updateOscillatorFrequency()
    }

    /// Setzt die Transposition in Halbtoenen, geklemmt auf `-24...24`.
    public mutating func setTransposition(semitones: Double) {
        transpositionSemitones = AudioCoreSourceB.clampTransposition(semitones)
        updateOscillatorFrequency()
    }

    /// Setzt die Feinstimmung in Cent, geklemmt auf `-100...100`.
    public mutating func setFineTune(cents: Double) {
        fineTuneCents = AudioCoreSourceB.clampFineTune(cents)
        updateOscillatorFrequency()
    }

    public mutating func setMorph(_ value: Float) {
        oscillator.setMorph(value)
    }

    /// Setzt die interne Phase explizit, gewrapped/finite-abgesichert durch
    /// den gekapselten `AudioCoreMorphOscillator` (S-04a-fix-Vertrag).
    public mutating func resetPhase(to newPhase: Double = 0) {
        oscillator.resetPhase(to: newPhase)
    }

    public var frequencyHz: Double { oscillator.frequencyHz }
    public var morph: Float { oscillator.morph }

    private mutating func updateOscillatorFrequency() {
        let hz = AudioCoreSourceB.effectiveFrequency(base: baseFrequencyHz,
                                                       semitones: transpositionSemitones,
                                                       cents: fineTuneCents)
        oscillator.setFrequency(hz)
    }

    // MARK: – Transposition/Feinstimmung als reine Hz-Skalierung

    private static func effectiveFrequency(base: Double, semitones: Double, cents: Double) -> Double {
        guard base.isFinite, base > 0 else { return 0 }
        let totalSemitones = semitones + cents / 100.0
        let factor = pow(2.0, totalSemitones / 12.0)
        let hz = base * factor
        return hz.isFinite && hz > 0 ? hz : 0
    }

    private static func clampBaseFrequency(_ hz: Double) -> Double {
        guard hz.isFinite, hz > 0 else { return 0 }
        return hz
    }

    private static func clampTransposition(_ semitones: Double) -> Double {
        guard semitones.isFinite else { return 0 }
        return max(-24.0, min(semitones, 24.0))
    }

    private static func clampFineTune(_ cents: Double) -> Double {
        guard cents.isFinite else { return 0 }
        return max(-100.0, min(cents, 100.0))
    }

    // MARK: – DSP-Render

    /// Liest genau ein Sample und schreibt die Phase fort. Kein Heap-Zugriff,
    /// kein Lock, kein Dispatch, kein `print`.
    @discardableResult
    public mutating func nextSample() -> Float {
        oscillator.nextSample()
    }

    /// Schreibt `frameCount` Samples in den aufrufer-bereitgestellten Puffer.
    /// Optionale Test-/Offline-Render-Hilfsfunktion — noch nicht der
    /// produktive Renderpfad (Nicht-Scope S-04b).
    @discardableResult
    public mutating func render(into buffer: UnsafeMutablePointer<Float>, frameCount: Int) -> Bool {
        oscillator.render(into: buffer, frameCount: frameCount)
    }
}
