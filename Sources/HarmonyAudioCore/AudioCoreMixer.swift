import Darwin

// MARK: – AudioCoreMixer
//
// S-04b (`.agent_handoff/latest_codex.md`, Runde 051), Scope D: sichere,
// feste Mixmodi fuer A/B/C des Atmospheric-Synth-Fundaments
// (`SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 6.1). Bewusst als reine,
// zustandslose Funktion ueber drei bereits gerenderte Samples (nicht als
// Besitzer eigener Oszillatorinstanzen) — das haelt Source A, Source B und
// Texture C vollstaendig entkoppelt und macht jeden Mixmodus isoliert
// testbar. "Feste, typisierte Auswahl, keine freie Modulationsmatrix"
// (Scope-A-Vorgabe): `AudioCoreMixMode` ist ein geschlossenes `enum`, keine
// generische Patchgraph-Logik.
//
// Reduzierte Variante fuer Phasen-/Frequenzmodulation (Scope-D-Vorgabe,
// "wenn sie zu breit wird, stoppe oder begruende eine reduzierte
// Variante"): eine echte Audio-Rate-Phasenmodulation muesste in die
// interne Phase von Source A oder B eingreifen und wuerde damit die
// Kapselung der einzelnen Quellen aufloesen — das waere im Kern bereits ein
// kleiner Patchgraph. Stattdessen implementiert `.softPhaseModulation` eine
// begrenzte, phasenverzerrungs-aehnliche Nachbearbeitung rein auf den
// bereits gerenderten Samplewerten (`a + depth * sin(pi * b)`), lokal,
// zustandslos und mathematisch bandbegrenzt durch `sin()` (immer in
// `[-1, 1]`) — sicher ohne Zugriff auf interne Oszillatorzustaende.
//
// Realtime-Vertrag: `AudioCoreMixer.mix` alloziiert nicht, sperrt nicht,
// nutzt keine Dispatch-/Task-/Actor-Ausfuehrung und schreibt nicht (kein
// `print`). Reine Gleitkomma-Arithmetik auf drei Eingabewerten.

public enum AudioCoreMixMode: Sendable, Equatable {
    /// Linearer Mix aus A/B/C mit geklemmten Gains.
    case linear
    /// Ringmodulation A x B, ueberblendet mit trockenem A ueber `ringModDepth`.
    case ringModulation
    /// Begrenzte, phasenverzerrungs-aehnliche Modulation von A durch B
    /// (reduzierte, patchgraph-freie Variante — siehe Dateikommentar).
    case softPhaseModulation
}

public struct AudioCoreMixParameters: Sendable, Equatable {

    /// Gain fuer Source A im linearen Mix, geklemmt auf `0...1`.
    public var gainA: Float
    /// Gain fuer Source B im linearen Mix, geklemmt auf `0...1`.
    public var gainB: Float
    /// Gain fuer Texture C im linearen Mix, geklemmt auf `0...1`.
    public var gainC: Float
    /// Tiefe der Ringmodulation A x B, geklemmt auf `0...1`
    /// (`0` = trockenes A, `1` = volle Ringmodulation).
    public var ringModDepth: Float
    /// Tiefe der begrenzten Phasenmodulation, geklemmt auf `0...1`.
    public var phaseModDepth: Float

    public init(gainA: Float = 1.0, gainB: Float = 0.0, gainC: Float = 0.0,
                ringModDepth: Float = 0.0, phaseModDepth: Float = 0.0) {
        self.gainA = AudioCoreMixParameters.clampUnit(gainA)
        self.gainB = AudioCoreMixParameters.clampUnit(gainB)
        self.gainC = AudioCoreMixParameters.clampUnit(gainC)
        self.ringModDepth = AudioCoreMixParameters.clampUnit(ringModDepth)
        self.phaseModDepth = AudioCoreMixParameters.clampUnit(phaseModDepth)
    }

    fileprivate static func clampUnit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return max(0.0, min(value, 1.0))
    }
}

public enum AudioCoreMixer {

    /// Mischt drei bereits gerenderte Samples nach dem gewaehlten Modus.
    /// Nicht-endliche Eingaben werden defensiv als `0` behandelt, das
    /// Ergebnis ist immer auf `[-1, 1]` geklemmt und immer endlich.
    public static func mix(a: Float, b: Float, c: Float,
                            mode: AudioCoreMixMode,
                            parameters: AudioCoreMixParameters) -> Float {
        let sa = a.isFinite ? a : 0
        let sb = b.isFinite ? b : 0
        let sc = c.isFinite ? c : 0

        let result: Float
        switch mode {
        case .linear:
            result = linearMix(a: sa, b: sb, c: sc, parameters: parameters)
        case .ringModulation:
            result = ringModulationMix(a: sa, b: sb, parameters: parameters)
        case .softPhaseModulation:
            result = softPhaseModulationMix(a: sa, b: sb, parameters: parameters)
        }

        guard result.isFinite else { return 0 }
        return max(-1.0, min(result, 1.0))
    }

    private static func linearMix(a: Float, b: Float, c: Float, parameters: AudioCoreMixParameters) -> Float {
        a * parameters.gainA + b * parameters.gainB + c * parameters.gainC
    }

    private static func ringModulationMix(a: Float, b: Float, parameters: AudioCoreMixParameters) -> Float {
        let dry = a
        let ringModulated = a * b
        let depth = parameters.ringModDepth
        return dry * (1.0 - depth) + ringModulated * depth
    }

    private static func softPhaseModulationMix(a: Float, b: Float, parameters: AudioCoreMixParameters) -> Float {
        let modulator = sinf(Float.pi * b)
        return a + parameters.phaseModDepth * modulator
    }
}
