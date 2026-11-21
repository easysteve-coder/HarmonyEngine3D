import Darwin

// MARK: – AudioCoreLFO
//
// S-05a (`.agent_handoff/latest_codex.md`, Runde 052), Scope B: eigenstaendiger
// LFO-Baustein des Atmospheric-Synth-Fundaments (`SYNTH_ARCHITECTURE_PLAN.md`,
// Abschnitt 6.4). Vier Formen: Sine, Triangle, Sample-and-Hold und
// geglaetteter Random. Kein Zugriff auf `AudioCoreVoice`-internen Zustand,
// keine aktive Nutzung durch `AudioCoreVoice`/`SynthNode`, keine
// Modulationsmatrix (Nicht-Scope S-05a, folgt in S-05b).
//
// Determinismus: Sample-and-Hold und geglaetteter Random ziehen ihre
// Zufallswerte aus einem expliziten xorshift64-Zustand (identisches Muster
// zu `AudioCoreTextureSource.nextWhiteSample()`) statt
// `SystemRandomNumberGenerator` — gleicher Seed und gleiche Parameter
// erzeugen bitgenau dieselbe Wertfolge.
//
// Per-Voice vs. global (Scope C): reiner Value-Typ, kein Singleton, kein
// globaler mutable State, expliziter State pro Instanz — dieselbe API kann
// sowohl pro Stimme als auch als ein einzelner globaler Modulator verwendet
// werden, je nachdem, wer die Instanz haelt.
//
// Realtime-Vertrag (Scope D): `nextValue()`/`render(into:frameCount:)`
// alloziieren nicht, sperren nicht, nutzen keine Dispatch-/Task-/Actor-
// Ausfuehrung und schreiben nicht (kein `print`).

public struct AudioCoreLFO: Sendable {

    public let sampleRate: Double
    public private(set) var parameters: AudioCoreLFOParameters

    /// Phase, immer `[0, 1)`. Bei Sine/Triangle direkt die Wellenform-Position,
    /// bei Sample-and-Hold/geglaettetem Random nur der Taktgeber fuer neue
    /// Zufallswerte pro Zyklus.
    private var phase: Double = 0

    private var rngState: UInt64
    private var heldValue: Float
    private var smoothedValue: Float

    private static let defaultSeedForZero: UInt64 = 0xC2B2_AE3D_27D4_EB4F

    public init(sampleRate: Double, parameters: AudioCoreLFOParameters = .defaults, seed: UInt64 = 1) {
        self.sampleRate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : 1.0
        self.parameters = parameters

        let seeded = seed == 0 ? AudioCoreLFO.defaultSeedForZero : seed
        let (nextState, firstRandom) = AudioCoreLFO.advanceRNG(seeded)
        self.rngState = nextState
        self.heldValue = firstRandom
        self.smoothedValue = firstRandom
    }

    // MARK: – Parameter
    //
    // Setter erzeugen die neuen Parameter ueber `AudioCoreLFOParameters.init`
    // neu, damit dieselbe Klemmlogik wie im Konstruktor greift, statt sie ein
    // zweites Mal zu duplizieren.

    public mutating func setFrequency(_ hz: Float) {
        parameters = AudioCoreLFOParameters(shape: parameters.shape, frequencyHz: hz, smoothingAmount: parameters.smoothingAmount)
    }

    public mutating func setShape(_ shape: AudioCoreLFOShape) {
        parameters = AudioCoreLFOParameters(shape: shape, frequencyHz: parameters.frequencyHz, smoothingAmount: parameters.smoothingAmount)
    }

    public mutating func setSmoothingAmount(_ amount: Float) {
        parameters = AudioCoreLFOParameters(shape: parameters.shape, frequencyHz: parameters.frequencyHz, smoothingAmount: amount)
    }

    // MARK: – Reset/Key-Sync
    //
    // Getrennt in Phasen- und Zufallszustand, damit ein Aufrufer gezielt nur
    // die Phase resynchronisieren (Key-Sync) oder zusaetzlich die
    // Zufallsfolge reproduzierbar zuruecksetzen kann (z. B. Tests/Offline-
    // Renders) — identisches Muster zu
    // `AudioCoreMorphOscillator.resetPhase(to:)` und
    // `AudioCoreTextureSource.resetState(to:)`.

    /// Setzt die Phase explizit zurueck (Key-Sync), gewrapped auf `[0, 1)`.
    /// Eine nicht-endliche `newPhase` (`.nan`/`.infinity`) faellt auf Phase
    /// `0` zurueck.
    public mutating func resetPhase(to newPhase: Double = 0) {
        let finitePhase = newPhase.isFinite ? newPhase : 0
        var wrapped = finitePhase.truncatingRemainder(dividingBy: 1.0)
        if wrapped < 0 { wrapped += 1.0 }
        phase = wrapped
    }

    /// Setzt den RNG-Zustand explizit zurueck und zieht sofort den ersten
    /// Zufallswert neu (identisch zur Init-Reihenfolge) — danach liefert
    /// dieselbe Aufrufsequenz bitgenau dieselbe Sample-and-Hold-/
    /// geglaettete-Random-Folge wie eine frische Instanz mit identischem
    /// Seed.
    public mutating func resetRandomState(to newSeed: UInt64) {
        let seeded = newSeed == 0 ? AudioCoreLFO.defaultSeedForZero : newSeed
        let (nextState, firstRandom) = AudioCoreLFO.advanceRNG(seeded)
        rngState = nextState
        heldValue = firstRandom
        smoothedValue = firstRandom
    }

    // MARK: – DSP-Render

    /// Liest genau einen Modulationswert und schreibt Phase-/Zufallszustand
    /// fort. Kein Heap-Zugriff, kein Lock, kein Dispatch, kein `print`.
    @discardableResult
    public mutating func nextValue() -> Float {
        let output: Float

        switch parameters.shape {

        case .sine:
            output = Float(sin(2.0 * Double.pi * phase))

        case .triangle:
            output = 1.0 - 4.0 * Float(abs(phase - 0.5))

        case .sampleAndHold:
            output = heldValue

        case .smoothedRandom:
            let coefficient = AudioCoreLFO.smoothingCoefficient(for: parameters.smoothingAmount)
            var nextSmoothed = smoothedValue + coefficient * (heldValue - smoothedValue)
            if !nextSmoothed.isFinite { nextSmoothed = 0 }
            smoothedValue = nextSmoothed
            output = smoothedValue
        }

        if advancePhase(), parameters.shape == .sampleAndHold || parameters.shape == .smoothedRandom {
            heldValue = nextRandomUnit()
        }

        return output.isFinite ? output : 0
    }

    /// Schreibt `frameCount` Werte in den aufrufer-bereitgestellten Puffer.
    @discardableResult
    public mutating func render(into buffer: UnsafeMutablePointer<Float>, frameCount: Int) -> Bool {
        for i in 0..<frameCount {
            buffer[i] = nextValue()
        }
        return true
    }

    // MARK: – Phase

    /// Rueckt die Phase um `frequencyHz / sampleRate` fort. `frequencyHz` ist
    /// auf `AudioCoreLFOParameters.maxFrequencyHz` begrenzt, daher bleibt der
    /// Fortschritt pro Sample immer klein genug fuer einen einzelnen
    /// Wrap-Schritt (identisches Muster zu `AudioCoreVoice`/
    /// `AudioCoreMorphOscillator`). Gibt `true` zurueck, wenn in diesem
    /// Schritt ein neuer Zyklus begonnen hat.
    @discardableResult
    private mutating func advancePhase() -> Bool {
        let increment = Double(parameters.frequencyHz) / sampleRate
        phase += increment
        guard phase.isFinite else { phase = 0; return false }
        if phase >= 1.0 {
            phase -= 1.0
            return true
        }
        return false
    }

    // MARK: – Deterministisches Zufallsrauschen (xorshift64)
    //
    // Identisches Muster zu `AudioCoreTextureSource.nextWhiteSample()`.

    private mutating func nextRandomUnit() -> Float {
        let (next, value) = AudioCoreLFO.advanceRNG(rngState)
        rngState = next
        return value
    }

    private static func advanceRNG(_ state: UInt64) -> (next: UInt64, unitValue: Float) {
        var s = state
        s ^= s << 13
        s ^= s >> 7
        s ^= s << 17

        // obere 53 Bit exakt in Double darstellbar -> deterministische,
        // plattformunabhaengige Normierung auf [-1, 1).
        let normalized = Double(s >> 11) * (1.0 / 9_007_199_254_740_992.0)
        return (s, Float(normalized * 2.0 - 1.0))
    }

    private static func smoothingCoefficient(for amount: Float) -> Float {
        let a = amount.isFinite ? max(0.0, min(amount, 1.0)) : 0.05
        // Bleibt immer im offenen Intervall (0, 1): weder Einfrieren (0) noch
        // Divergenz (>= 1) moeglich, unabhaengig vom `amount`-Wert —
        // identisches Stabilitaetsprinzip zu `AudioCoreTextureSource`s
        // Farbfilter-Koeffizient.
        return 0.0005 + a * 0.4
    }
}
