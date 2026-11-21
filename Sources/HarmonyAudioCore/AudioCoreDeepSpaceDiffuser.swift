import Darwin

// MARK: – AudioCoreDeepSpaceDiffuser
//
// S-08a (`.agent_handoff/latest_codex.md`, Runde 057), Scope C: kleine
// Eingangs-Diffusor-Kette fuer den ersten `DeepSpace`-Baustein
// (`SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 7.3: "Eingangs-Diffusoren").
// Vier in Serie geschaltete Schroeder-Allpass-Stufen je Kanal — eine
// allgemein bekannte, in unzaehligen frei dokumentierten Reverb-/
// Diffusor-Beschreibungen verwendete Topologie (ein gemeinsamer Feedback-/
// Feedforward-Koeffizient `g` pro Stufe, |g| < 1 fuer unbedingte
// Stabilitaet unabhaengig von der Verzoegerungslaenge), keine proprietaere
// Implementierung. Links und rechts nutzen unterschiedliche, feste
// Verzoegerungszeiten, damit die Kanaele nach der Kette leicht dekorreliert
// sind (Stereobreite), ohne Zufall oder Modulation ("keine Modulation in
// S-08a", Scope-C-Vorgabe).
//
// Bewusst KEINE Rueckkopplungsmatrix zwischen den Kanaelen und KEINE lange
// FDN-Struktur (Nicht-Scope S-08a) — die Kette bereitet den spaeteren
// S-08b-Tail nur vor, nimmt ihn aber nicht vorweg.
//
// Realtime-Vertrag: `process(left:right:)` alloziiert nicht, sperrt nicht,
// nutzt keine Dispatch-/Task-/Actor-Ausfuehrung und schreibt nicht (kein
// `print`). Alle Stufenpuffer werden ausschliesslich in `init`/
// `prepare(sampleRate:)` alloziiert, niemals in `process(left:right:)`.

public struct AudioCoreDeepSpaceDiffuser: Sendable, Equatable {

    /// Anzahl in Serie geschalteter Allpass-Stufen je Kanal.
    public static let stageCount = 4

    // Feste, deterministische Verzoegerungszeiten je Stufe in Millisekunden.
    // Links/rechts bewusst unterschiedlich (Stereo-Dekorrelation).
    private static let leftStageDelaysMs: [Float] = [4.7, 7.9, 11.3, 15.8]
    private static let rightStageDelaysMs: [Float] = [5.4, 9.7, 13.1, 18.2]

    // Sichere Obergrenze fuer den Allpass-Koeffizienten, strikt < 1
    // (Runaway-Grenze) — "Feedback-/Diffusionskoeffizienten bleiben strikt
    // unter Runaway-Grenzen" (Scope-A-Vorgabe).
    private static let maxCoefficient: Float = 0.65

    public private(set) var sampleRate: Double
    public private(set) var parameters: AudioCoreDeepSpaceParameters

    private var leftStages: [AudioCoreDeepSpaceAllpassStage]
    private var rightStages: [AudioCoreDeepSpaceAllpassStage]

    public init(sampleRate: Double, parameters: AudioCoreDeepSpaceParameters = AudioCoreDeepSpaceParameters()) {
        let safeSampleRate = AudioCoreDeepSpaceParameters.safeSampleRate(sampleRate)
        self.sampleRate = safeSampleRate
        self.parameters = parameters
        self.leftStages = AudioCoreDeepSpaceDiffuser.leftStageDelaysMs.map {
            AudioCoreDeepSpaceAllpassStage(delayMs: $0, sampleRate: safeSampleRate)
        }
        self.rightStages = AudioCoreDeepSpaceDiffuser.rightStageDelaysMs.map {
            AudioCoreDeepSpaceAllpassStage(delayMs: $0, sampleRate: safeSampleRate)
        }
    }

    // MARK: – Parameter/Prepare

    public mutating func setParameters(_ newParameters: AudioCoreDeepSpaceParameters) {
        // S-08a-fix (Finding S-08a-01): dieselbe Klemm-Wiederherstellung wie
        // `AudioCoreDeepSpaceEarlyReflections.setParameters(_:)`, damit die
        // Invariante fuer beide `DeepSpace`-Typen konsistent gilt, auch wenn
        // hier heute kein Trap moeglich ist (nur ein Diffusionsrunaway).
        parameters = AudioCoreDeepSpaceParameters(
            preDelaySeconds: newParameters.preDelaySeconds,
            size: newParameters.size,
            earlyReflectionMix: newParameters.earlyReflectionMix,
            diffusion: newParameters.diffusion
        )
    }

    /// Bereitet die Kette fuer eine (neue) Sample-Rate vor: alloziiert alle
    /// Stufenpuffer neu und setzt den Zustand zurueck. Keine Allokation
    /// ausserhalb von `init`/`prepare(sampleRate:)`.
    public mutating func prepare(sampleRate: Double) {
        let safeSampleRate = AudioCoreDeepSpaceParameters.safeSampleRate(sampleRate)
        self.sampleRate = safeSampleRate
        leftStages = AudioCoreDeepSpaceDiffuser.leftStageDelaysMs.map {
            AudioCoreDeepSpaceAllpassStage(delayMs: $0, sampleRate: safeSampleRate)
        }
        rightStages = AudioCoreDeepSpaceDiffuser.rightStageDelaysMs.map {
            AudioCoreDeepSpaceAllpassStage(delayMs: $0, sampleRate: safeSampleRate)
        }
    }

    // MARK: – Reset
    //
    // Setzt alle Stufenpuffer zurueck, ohne neu zu allozieren. Dieselbe
    // Eingabefolge nach `reset()` reproduziert denselben Ausgabeverlauf wie
    // eine frische Instanz mit identischen Parametern.
    public mutating func reset() {
        for i in leftStages.indices { leftStages[i].reset() }
        for i in rightStages.indices { rightStages[i].reset() }
    }

    // MARK: – DSP-Render
    //
    // Ein Sample-Schritt: verarbeitet links/rechts unabhaengig durch je vier
    // in Serie geschaltete Allpass-Stufen. Kein Heap-Zugriff, kein Alloc,
    // kein Lock, keine Dispatch-/Task-/Actor-Nutzung, kein `print`.
    public mutating func process(left: Float, right: Float) -> (left: Float, right: Float) {
        let rawCoefficient = AudioCoreDeepSpaceDiffuser.maxCoefficient * parameters.diffusion
        let coefficient = rawCoefficient.isFinite ? rawCoefficient : 0

        var l = left.isFinite ? left : 0
        for i in leftStages.indices {
            l = leftStages[i].process(l, coefficient: coefficient)
        }

        var r = right.isFinite ? right : 0
        for i in rightStages.indices {
            r = rightStages[i].process(r, coefficient: coefficient)
        }

        return (l.isFinite ? l : 0, r.isFinite ? r : 0)
    }
}

// MARK: – AudioCoreDeepSpaceAllpassStage
//
// Kleiner, interner Delayline-Hilfstyp fuer genau eine Schroeder-Allpass-
// Stufe. Bewusst eng an `AudioCoreDeepSpaceDiffuser` gebunden (kein
// generisches Patchgraph-/Delayline-Framework, Scope-A-Vorgabe: "halte ihn
// eng, testbar und ohne generisches Patchgraph-Design").
//
// Formel (effiziente Ein-Puffer-Form des klassischen Schroeder-Allpass mit
// einem Verzoegerungstap D, siehe z. B. Julius O. Smith, "Physical Audio
// Signal Processing", Abschnitt "Allpass Filters" — frei dokumentierte
// Standardformel, keine proprietaere Implementierung):
// w(n) = x(n) + g*w(n-D); y(n) = -g*w(n) + w(n-D). Der Puffer speichert
// w(n-D); der Ausgang haengt vom rueckgekoppelten w(n) ab, nicht vom rohen
// Eingang x(n). Fuer jedes |g| < 1 unbedingt stabil (Unity-Gain-Allpass),
// unabhaengig von der Verzoegerungslaenge.

private struct AudioCoreDeepSpaceAllpassStage: Sendable, Equatable {

    private var buffer: [Float]
    private var index: Int = 0

    init(delayMs: Float, sampleRate: Double) {
        let samples = Int((Double(delayMs) / 1000.0 * sampleRate).rounded())
        buffer = Array(repeating: 0, count: max(samples, 1))
    }

    mutating func reset() {
        for i in buffer.indices { buffer[i] = 0 }
        index = 0
    }

    mutating func process(_ input: Float, coefficient: Float) -> Float {
        let x = input.isFinite ? input : 0
        let g = coefficient.isFinite ? coefficient : 0

        // Effiziente Ein-Puffer-Form des Schroeder-Allpass (siehe
        // Dateikommentar): w(n) = x(n) + g*w(n-D), y(n) = -g*w(n) + w(n-D).
        // WICHTIG: der Ausgangsterm nutzt w(n) (den rueckgekoppelten Wert),
        // NICHT den rohen Eingang x(n) — sonst ist die Stufe kein Allpass
        // mehr (kein Unity-Gain, Energie kann anwachsen statt erhalten zu
        // bleiben).
        let delayed = buffer[index]
        var recirculated = x + g * delayed
        if !recirculated.isFinite { recirculated = 0 }

        let output = -g * recirculated + delayed
        buffer[index] = recirculated

        index = (index + 1) % buffer.count
        return output.isFinite ? output : 0
    }
}
