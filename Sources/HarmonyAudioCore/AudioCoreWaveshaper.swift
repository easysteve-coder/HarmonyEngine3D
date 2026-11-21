import Darwin

// MARK: – AudioCoreWaveshaper
//
// S-06 (`.agent_handoff/latest_codex.md`, Runde 054), Scope C: kleiner
// Drive/Waveshaper-Baustein fuer die Atmospheric Voice
// (`SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 6.3: "Drive/Waveshaper mit
// kompensiertem Ausgangspegel"). Bewusst KEINE Nachbildung eines
// proprietaeren Algorithmus — `tanh` ist eine allgemein bekannte, in
// unzaehligen frei dokumentierten Soft-Clipping-Beschreibungen verwendete
// symmetrische Sigmoidfunktion (ungerade Funktion, daher automatisch
// symmetrisch fuer positive/negative Eingaben).
//
// Pegelkompensation: der geshapte Wert wird durch `tanh(driveGain)`
// dividiert, bevor `outputGain` angewendet wird — dadurch bleibt der
// Ausgangspegel bei Vollaussteuerung (`|input| == 1`) ueber den gesamten
// Drive-Bereich naeherungsweise konstant, statt mit steigendem Drive nur
// unkontrolliert lauter zu werden (Scope-C-Vorgabe).
//
// Zustandslos (reine Funktion) — kein `reset()` noetig, jeder Aufruf haengt
// ausschliesslich von `input` und `parameters` ab.
//
// Realtime-Vertrag: `process(_:parameters:)` alloziiert nicht, sperrt
// nicht, nutzt keine Dispatch-/Task-/Actor-Ausfuehrung und schreibt nicht
// (kein `print`). Reine Gleitkomma-Arithmetik auf einem Eingabewert.

public struct AudioCoreWaveshaperParameters: Sendable, Equatable {

    /// Drive, 0...1, intern auf eine Drive-Verstaerkung 1...20 abgebildet.
    public var drive: Float
    /// Manuelle zusaetzliche Ausgangsverstaerkung nach der Pegelkompensation,
    /// 0...4, Default 1.0 (unveraendert).
    public var outputGain: Float

    public init(drive: Float = 0.0, outputGain: Float = 1.0) {
        self.drive = AudioCoreWaveshaperParameters.clampUnit(drive)
        self.outputGain = AudioCoreWaveshaperParameters.clampGain(outputGain)
    }

    fileprivate static func clampUnit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return max(0.0, min(value, 1.0))
    }

    fileprivate static func clampGain(_ value: Float) -> Float {
        guard value.isFinite else { return 1.0 }
        return max(0.0, min(value, 4.0))
    }
}

public enum AudioCoreWaveshaper {

    private static let minDriveGain: Float = 1.0
    private static let maxDriveGain: Float = 20.0

    /// Formt `input` per `tanh`-Soft-Clipping und wendet Pegelkompensation
    /// plus `outputGain` an. Nicht-endliche Eingaben werden defensiv als `0`
    /// behandelt, das Ergebnis ist immer endlich und auf `[-1, 1]` geklemmt.
    public static func process(_ input: Float, parameters: AudioCoreWaveshaperParameters) -> Float {
        let x = input.isFinite ? input : 0

        let driveGain = minDriveGain + parameters.drive * (maxDriveGain - minDriveGain)
        let shaped = tanhf(x * driveGain)

        let normalizer = tanhf(driveGain)
        let compensated = normalizer > 0.0001 ? shaped / normalizer : shaped

        let output = compensated * parameters.outputGain
        guard output.isFinite else { return 0 }
        return max(-1.0, min(output, 1.0))
    }
}
