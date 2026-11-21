import Darwin

// MARK: – AudioCoreDeepSpaceEarlyReflections
//
// S-08a (`.agent_handoff/latest_codex.md`, Runde 057), Scope B:
// deterministische Early-Reflection-Stufe fuer den ersten `DeepSpace`-
// Baustein (`SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 7.3: "Pre-Delay;
// getrennte Early Reflections"). Kein Zufallsmodell — sieben feste, bei
// Init/Prepare aus Parametern abgeleitete Taps ("stabile, kurze Reflection-
// Taps, abgeleitet aus Parametern statt Zufallswerten", Scope-B-Vorgabe).
// Tap-Zeiten wachsen gemeinsam mit `size`; Tap-Gains fallen geometrisch ab,
// damit die Summe der Reflection-Energie unabhaengig vom Parameterbereich
// konservativ deutlich unter 1 bleibt (siehe `tapBaseGain`/`tapGainDecay`)
// — "Reflection-Gains muessen in Summe konservativ sein, sodass eine
// Impulsantwort nicht explodiert" (Scope-B-Vorgabe).
//
// Stereo entsteht rein aus einem festen, alternierenden Links-/Rechts-
// Gewichtungsmuster ueber die sieben Taps (kein Zufall, keine Modulation)
// — eine bewusst einfache, deterministische Stereo-Verteilung als
// technisches Fundament, keine Klang-/Art-Direction-Entscheidung
// ("keine psychoakustische Feintuning-Entscheidung erzwingen", Scope-B).
//
// Endliche Impulsantwort (FIR): jeder Tap liest genau eine feste,
// vorausberechnete Position aus dem Ringpuffer zurueck, es gibt keine
// Rueckkopplung — die Impulsantwortlaenge ist dadurch von Natur aus
// endlich und durch den laengsten Tap begrenzt.
//
// Realtime-Vertrag: `process(_:)` alloziiert nicht, sperrt nicht, nutzt
// keine Dispatch-/Task-/Actor-Ausfuehrung und schreibt nicht (kein
// `print`). Der Verzoegerungspuffer wird ausschliesslich in `init`/
// `prepare(sampleRate:)` alloziiert, niemals in `process(_:)`.
//
// Runde 064 (Stephan-Entscheidung 1, 2026-08-01): `process(_:)` klemmte den
// Ausgang bisher zusaetzlich hart auf `±1`. Diese Wertebereichsklemmung
// wurde entfernt -- die `isFinite`-Absicherung (NaN/Infinity -> 0) bleibt
// unveraendert bestehen. Gruende: (1) Diffusor und FDN-Tail klemmen nicht,
// die drei `DeepSpace`-Bausteine waren dadurch inkonsistent; (2) dieser
// Baustein ist fuer einen gemeinsamen Send-Bus gebaut, auf dem das Signal
// die Summe mehrerer Stimmen traegt und danach ueber Send-Pegel/Fader
// heruntergezogen wird -- ein Zwischenwert ueber 1,0 ist dort normal und
// waere nach dem Fader nie zu laut; (3) Begrenzung gehoert ans Ende einer
// Kette, nicht in einen Zwischenbaustein. Im bisherigen Normalfall
// (Eingang <= 1,0) war die Klemmung ohnehin praktisch immer inaktiv: die
// Ausgangsspitze liegt bei 0 dBFS Eingang bei ca. 0,238 (staerkster Tap-Gain
// 0,28 * mix<=1 * staerkstes Links-/Rechts-Gewicht 0,85), die Klemmung
// griff erst zwischen ca. +9,5 und +14 dBFS Eingang -- das Entfernen aendert
// den Normalfall daher nicht messbar, siehe
// `test_earlyReflections_normalRangeInput_matchesPreRemovalChecksum` und
// `test_earlyReflections_process_noLongerClampsAboveUnity`.

public struct AudioCoreDeepSpaceEarlyReflections: Sendable, Equatable {

    /// Anzahl fester Reflection-Taps.
    public static let tapCount = 7

    // Feste, deterministische Zeit-Fraktionen je Tap (0...1), skaliert mit
    // dem groessenabhaengigen Room-Span. Monoton steigend, keine Kollisionen.
    private static let tapFractions: [Float] = [0.05, 0.13, 0.24, 0.38, 0.55, 0.75, 1.0]

    // Geometrisch fallende Gains je Tap. Summe = tapBaseGain * (1 - r^n) / (1 - r)
    // mit r = 0.7, n = 7 -> Faktor ~3.03; tapBaseGain 0.28 haelt die Summe
    // konservativ bei ca. 0.85, unabhaengig von `earlyReflectionMix` (<= 1).
    private static let tapGainDecay: Float = 0.7
    private static let tapBaseGain: Float = 0.28

    // Alternierendes Links-/Rechts-Gewichtungsmuster je Tap (1 = ganz links,
    // 0 = ganz rechts), fest und deterministisch.
    private static let tapLeftWeights: [Float] = [0.85, 0.15, 0.8, 0.2, 0.7, 0.3, 0.5]

    // Referenz-Room-Span in Millisekunden bei size = 0 bzw. size = 1.
    private static let roomSpanMsAtMinSize: Float = 15.0
    private static let roomSpanMsAtMaxSize: Float = 150.0

    public private(set) var sampleRate: Double
    public private(set) var parameters: AudioCoreDeepSpaceParameters

    // Kreisfoermiger Verzoegerungspuffer, bei init/prepare alloziert.
    private var delayBuffer: [Float]
    private var writeIndex: Int = 0

    // Aus Parametern/SampleRate abgeleitete Tap-Verzoegerungen in Samples,
    // bei init/prepare/Parameteraenderung neu berechnet.
    private var tapDelaySamples: [Int]

    public init(sampleRate: Double, parameters: AudioCoreDeepSpaceParameters = AudioCoreDeepSpaceParameters()) {
        let safeSampleRate = AudioCoreDeepSpaceParameters.safeSampleRate(sampleRate)
        self.sampleRate = safeSampleRate
        self.parameters = parameters
        self.tapDelaySamples = Array(repeating: 0, count: AudioCoreDeepSpaceEarlyReflections.tapCount)
        self.delayBuffer = Array(
            repeating: 0,
            count: AudioCoreDeepSpaceEarlyReflections.capacity(forSampleRate: safeSampleRate)
        )
        recomputeTapDelays()
    }

    // MARK: – Parameter/Prepare

    public mutating func setParameters(_ newParameters: AudioCoreDeepSpaceParameters) {
        // S-08a-fix (Finding S-08a-01): `AudioCoreDeepSpaceParameters` hat
        // `public var`-Felder, direkte Feldmutation nach `init` umgeht jede
        // Grenze. Der Neuaufbau ueber `init(...)` erzwingt den bestehenden
        // Klemmpfad erneut, statt eine zweite Klemmlogik zu duplizieren.
        parameters = AudioCoreDeepSpaceParameters(
            preDelaySeconds: newParameters.preDelaySeconds,
            size: newParameters.size,
            earlyReflectionMix: newParameters.earlyReflectionMix,
            diffusion: newParameters.diffusion
        )
        recomputeTapDelays()
    }

    /// Bereitet die Stufe fuer eine (neue) Sample-Rate vor: alloziiert den
    /// Verzoegerungspuffer mit fester, ausreichender Kapazitaet neu und
    /// setzt den Zustand zurueck. Keine Allokation ausserhalb von `init`/
    /// `prepare(sampleRate:)`.
    public mutating func prepare(sampleRate: Double) {
        let safeSampleRate = AudioCoreDeepSpaceParameters.safeSampleRate(sampleRate)
        self.sampleRate = safeSampleRate
        delayBuffer = Array(
            repeating: 0,
            count: AudioCoreDeepSpaceEarlyReflections.capacity(forSampleRate: safeSampleRate)
        )
        writeIndex = 0
        recomputeTapDelays()
    }

    // MARK: – Reset
    //
    // Setzt Puffer und Schreibzeiger zurueck, ohne neu zu allozieren.
    // Dieselbe Eingabefolge nach `reset()` reproduziert denselben
    // Ausgabeverlauf wie eine frische Instanz mit identischen Parametern.
    public mutating func reset() {
        for i in delayBuffer.indices { delayBuffer[i] = 0 }
        writeIndex = 0
    }

    // MARK: – Kapazitaet/Tap-Berechnung
    //
    // Kapazitaet wird immer fuer den maximal moeglichen Pre-Delay- +
    // Room-Span-Wert bemessen, unabhaengig vom aktuellen Parameterwert —
    // dadurch aendert sich die Puffergroesse nie innerhalb des gueltigen
    // Parameterbereichs, nur bei einer expliziten `prepare(sampleRate:)`.

    private static func capacity(forSampleRate sampleRate: Double) -> Int {
        let maxSeconds = Double(AudioCoreDeepSpaceParameters.maxPreDelaySeconds)
            + Double(roomSpanMsAtMaxSize) / 1000.0
        let samples = Int((maxSeconds * sampleRate).rounded(.up))
        return max(samples + 4, 16)
    }

    private mutating func recomputeTapDelays() {
        let roomSpanMs = AudioCoreDeepSpaceEarlyReflections.roomSpanMsAtMinSize
            + parameters.size * (AudioCoreDeepSpaceEarlyReflections.roomSpanMsAtMaxSize
                                  - AudioCoreDeepSpaceEarlyReflections.roomSpanMsAtMinSize)
        let preDelayMs = parameters.preDelaySeconds * 1000.0
        let capacity = delayBuffer.count

        for i in 0..<AudioCoreDeepSpaceEarlyReflections.tapCount {
            let tapMs = preDelayMs + roomSpanMs * AudioCoreDeepSpaceEarlyReflections.tapFractions[i]
            // Redundante Crash-Sicherung (S-08a-fix, Finding S-08a-01,
            // analog S-04a-fix): die Klemmung in `AudioCoreDeepSpaceParameters`
            // ist die Semantik, dieser Guard schuetzt nur die trappende
            // Double->Int-Konvertierung direkt davor.
            let scaledSamples = (Double(tapMs) / 1000.0 * sampleRate).rounded()
            let samples = scaledSamples.isFinite ? Int(scaledSamples) : 0
            tapDelaySamples[i] = max(0, min(samples, capacity - 1))
        }
    }

    // MARK: – DSP-Render
    //
    // Ein Sample-Schritt: schreibt `input` in den Ringpuffer, liest sieben
    // feste Taps zurueck und mischt sie gewichtet auf Stereo. Kein Heap-
    // Zugriff, kein Alloc, kein Lock, keine Dispatch-/Task-/Actor-Nutzung,
    // kein `print`.
    public mutating func process(_ input: Float) -> (left: Float, right: Float) {
        let x = input.isFinite ? input : 0
        let capacity = delayBuffer.count

        delayBuffer[writeIndex] = x

        var left: Float = 0
        var right: Float = 0
        var gain = AudioCoreDeepSpaceEarlyReflections.tapBaseGain * parameters.earlyReflectionMix

        for i in 0..<AudioCoreDeepSpaceEarlyReflections.tapCount {
            let readIndex = (writeIndex - tapDelaySamples[i] + capacity) % capacity
            let tapSample = delayBuffer[readIndex] * gain
            let leftWeight = AudioCoreDeepSpaceEarlyReflections.tapLeftWeights[i]
            left += tapSample * leftWeight
            right += tapSample * (1.0 - leftWeight)
            gain *= AudioCoreDeepSpaceEarlyReflections.tapGainDecay
        }

        writeIndex = (writeIndex + 1) % capacity

        // Runde 064: keine Wertebereichsklemmung mehr (siehe Dateikommentar)
        // -- nur die Endlichkeitsabsicherung bleibt.
        let safeLeft = left.isFinite ? left : 0
        let safeRight = right.isFinite ? right : 0
        return (safeLeft, safeRight)
    }
}
