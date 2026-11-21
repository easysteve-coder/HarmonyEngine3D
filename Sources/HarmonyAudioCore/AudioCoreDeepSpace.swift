import Darwin

// MARK: – AudioCoreDeepSpace
//
// W-02 (`.agent_handoff/latest_codex.md`, Runde 067): Zusammenschaltung der
// seit S-08a/S-08b/S-08c einzeln gebauten `DeepSpace`-Bausteine zu einem
// Raumprozessor (`SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 7.3). Reine
// Core-Schicht, offline testbar, NOCH NICHT verdrahtet — die Verbindung an
// `sharedSpaceSendBus`/`AudioEngine`/`AppSettings`/UI ist W-03.
//
// ---------------------------------------------------------------------------
// Signalweg (Handoff-Vorgabe, unveraendert uebernommen)
// ---------------------------------------------------------------------------
//
//     Eingang → Pre-Delay → ┬→ Early Reflections ──┐
//                           │                      ├→ Summe → Stereo-Ausgang
//                           └→ Diffusor → FDN-Tail ┘
//
// Reflexionen und Tail laufen PARALLEL, nicht in Serie. Der Diffusor sitzt
// vor dem Tail, nicht vor den Reflexionen — er speist die Rueckkopplung und
// verschmiert die diskreten Erstreflexionen nicht. Die Topologie war
// technisch haltbar; es gab keinen Grund, von der Vorgabe abzuweichen.
//
// ---------------------------------------------------------------------------
// Warum das Pre-Delay hier liegt und nicht mehr in den Early Reflections
// ---------------------------------------------------------------------------
//
// `AudioCoreDeepSpaceEarlyReflections` bringt ein eigenes Pre-Delay mit: es
// addiert `preDelaySeconds` auf jede Tap-Zeit. Das war richtig, solange die
// Stufe allein lief. In der Kette liegt das Pre-Delay laut Vorgabe VOR der
// Aufteilung und muss daher beide Zweige gleich verzoegern.
//
// Die Kette haelt deshalb eine eigene Pre-Delay-Verzoegerungslinie und
// uebergibt der Early-Reflection-Stufe einen Parametersatz mit
// `preDelaySeconds = 0` (siehe `branchParameters(from:)`). Andernfalls waere
// das Pre-Delay auf dem Reflexionszweig doppelt und auf dem Tail-Zweig gar
// nicht wirksam — die beiden Zweige waeren gegeneinander verschoben.
//
// Das ist KEINE Aenderung an `AudioCoreDeepSpaceEarlyReflections`: der
// Baustein bleibt unveraendert, die Kette uebergibt ihm nur einen anderen
// Wert. `parameters.early.preDelaySeconds` behaelt seine Bedeutung; die
// Stelle, an der es wirkt, ist eine Stufe nach vorn gewandert.
//
// ---------------------------------------------------------------------------
// Mono-Eingang, Stereo-Ausgang
// ---------------------------------------------------------------------------
//
// Die Kette nimmt EIN Sample und liefert Stereo. Das ist keine Vereinfachung,
// sondern das, was die Bausteine hergeben:
// `AudioCoreDeepSpaceEarlyReflections.process(_:)` ist per Konstruktion
// mono-in, und `AudioCoreDeepSpaceFDNTail.process(left:right:)` mittelt seinen
// Eingang intern sofort auf mono (`(l + r) * 0.5`). Ein Stereo-Eingang wuerde
// an beiden Zweigen zusammenfallen und nur eine Breite vortaeuschen, die die
// Kette nicht traegt. Der Stereo-Ausgang entsteht ausschliesslich aus den
// festen Ausgangsgewichten der beiden Zweige.
//
// Folge fuer den Diffusor, offen benannt: seine Links-/Rechts-Dekorrelation
// (unterschiedliche Allpass-Zeiten je Kanal) ueberlebt die Mono-Mittelung im
// Tail nicht als Stereobild. Sie bleibt trotzdem wirksam — die Mittelung
// zweier unterschiedlich diffundierter Signale ist selbst ein staerker
// diffundiertes Signal, und der Stereo-Eindruck des Tails kommt ohnehin aus
// dessen eigener Ausgangsmatrix. Kein Defekt, aber ein Punkt, den W-03 kennen
// sollte, falls dort mehr Breite gewuenscht wird.
//
// ---------------------------------------------------------------------------
// Realtime-Vertrag
// ---------------------------------------------------------------------------
//
// Der Renderpfad — `process(_:)` und
// `render(input:intoL:intoR:frameCount:)` — alloziert nicht, sperrt nicht,
// nutzt keine Dispatch-/Task-/Actor-Ausfuehrung und schreibt nicht (kein
// `print`). Alle Puffer werden ausschliesslich in `init`/
// `prepare(sampleRate:)` angelegt. Zur Laufzeit gemessen (interponierter
// `malloc`-Zaehler, Runde 067): 0 Allokationen ueber 1.024.000 Samples.
//
// W-03a (Runde 068): die in Runde 067 hier dokumentierten GEERBTEN
// Allokationspfade sind geschlossen. `AudioCoreDeepSpaceFDNTail.reset()`
// (2 Allokationen pro Aufruf) und `.setParameters(_:)` (4 pro Aufruf, aus dem
// `Set<Int>` der Primzahlwahl) allozieren nicht mehr; dazu kam eine dritte,
// erst durch die Laufzeitmessung sichtbare Stelle — eine AUFGESCHOBENE
// Copy-on-Write-Kopie der Modulationsphase, die nicht in `reset()` selbst
// anfiel, sondern im ersten `process`-Aufruf danach. Details im
// Dateikommentar von `AudioCoreDeepSpaceFDNTail.swift`.
//
// Damit gilt fuer die GESAMTE Kette derselbe Vertrag wie fuer
// `AudioCoreAtmosphericVoice`: `process(_:)`, `render(...)`,
// `setParameters(_:)` und `reset()` sind allokationsfrei und duerfen aus dem
// Rendercallback laufen; nur `init` und `prepare(sampleRate:)` allozieren und
// gehoeren auf die Kontrollrate. Gemessen (interponierter
// `malloc`/`calloc`/`realloc`-Zaehler, Runde 068): 0 Allokationen ueber
// 1.024.000 Samples `render`, ueber je 10.000 `setParameters(_:)`- und
// `reset()`-Aufrufe und in den jeweils ersten Samples nach `init`/`reset()`.

public struct AudioCoreDeepSpace: Sendable, Equatable {

    // Sicherheitsmarge in Samples oberhalb der maximal moeglichen
    // Pre-Delay-Laenge — haelt die feste Pufferkapazitaet immer echt groesser
    // als jede innerhalb des gueltigen Parameterbereichs erreichbare
    // Verzoegerung, ohne Reallokation bei `setParameters(_:)`.
    private static let preDelayCapacityMargin = 4

    public private(set) var sampleRate: Double
    public private(set) var parameters: AudioCoreDeepSpaceChainParameters

    // MARK: – Bausteine (unveraendert uebernommen)

    private var earlyReflections: AudioCoreDeepSpaceEarlyReflections
    private var diffuser: AudioCoreDeepSpaceDiffuser
    private var tail: AudioCoreDeepSpaceFDNTail

    // MARK: – Pre-Delay (eigener Ringpuffer, siehe Dateikommentar)

    private var preDelayBuffer: [Float]
    private var preDelayWriteIndex: Int = 0
    /// Aus `parameters.early.preDelaySeconds` und `sampleRate` abgeleitet,
    /// neu berechnet bei `init`/`prepare(sampleRate:)`/`setParameters(_:)` —
    /// nie in `process(_:)`.
    private var preDelaySamples: Int = 0

    // MARK: – Initialisierung

    public init(sampleRate: Double,
                parameters: AudioCoreDeepSpaceChainParameters = AudioCoreDeepSpaceChainParameters()) {

        let safeSampleRate = AudioCoreDeepSpaceParameters.safeSampleRate(sampleRate)
        // Neuaufbau ueber den Klemmpfad, damit auch ein ueber `public var`
        // veraenderter Satz geklemmt ankommt (S-08a-01-Lehre).
        let clamped = AudioCoreDeepSpaceChainParameters(early: parameters.early,
                                                        tail: parameters.tail,
                                                        earlyLevel: parameters.earlyLevel,
                                                        tailLevel: parameters.tailLevel)

        self.sampleRate = safeSampleRate
        self.parameters = clamped

        let branch = AudioCoreDeepSpace.branchParameters(from: clamped.early)
        self.earlyReflections = AudioCoreDeepSpaceEarlyReflections(sampleRate: safeSampleRate,
                                                                    parameters: branch)
        self.diffuser = AudioCoreDeepSpaceDiffuser(sampleRate: safeSampleRate,
                                                    parameters: branch)
        self.tail = AudioCoreDeepSpaceFDNTail(sampleRate: safeSampleRate,
                                               parameters: clamped.tail)

        self.preDelayBuffer = Array(
            repeating: 0,
            count: AudioCoreDeepSpace.preDelayCapacity(forSampleRate: safeSampleRate)
        )
        recomputePreDelay()
    }

    // MARK: – Parameterableitung fuer die Bausteine
    //
    // Einzige Stelle, an der die Kette von den uebergebenen Parametern
    // abweicht: `preDelaySeconds = 0`, weil die Kette das Pre-Delay selbst
    // vor der Aufteilung anwendet (siehe Dateikommentar). Alle uebrigen Werte
    // gehen unveraendert durch — und laufen im `init` der Bausteinparameter
    // erneut durch deren Klemmung.

    private static func branchParameters(
        from parameters: AudioCoreDeepSpaceParameters
    ) -> AudioCoreDeepSpaceParameters {
        AudioCoreDeepSpaceParameters(preDelaySeconds: 0,
                                      size: parameters.size,
                                      earlyReflectionMix: parameters.earlyReflectionMix,
                                      diffusion: parameters.diffusion)
    }

    // MARK: – Parameter/Prepare

    /// Post-Init-Mutationspfad. Baut den uebernommenen Satz ueber
    /// `AudioCoreDeepSpaceChainParameters.init(...)` neu auf (und damit ueber
    /// die Klemmung der beiden Bausteinparametertypen) und reicht ihn an die
    /// drei Bausteine weiter, die ihrerseits erneut klemmen. Kein
    /// Klemm-Duplikat in dieser Datei.
    ///
    /// Seit W-03a (Runde 068) rendercallback-sicher: der eigene Rumpf hat nie
    /// alloziert, und die geerbte `Set<Int>`-Allokation in
    /// `AudioCoreDeepSpaceFDNTail.recomputeLineState()` ist geschlossen
    /// (siehe Dateikommentar).
    public mutating func setParameters(_ newParameters: AudioCoreDeepSpaceChainParameters) {
        parameters = AudioCoreDeepSpaceChainParameters(early: newParameters.early,
                                                        tail: newParameters.tail,
                                                        earlyLevel: newParameters.earlyLevel,
                                                        tailLevel: newParameters.tailLevel)

        let branch = AudioCoreDeepSpace.branchParameters(from: parameters.early)
        earlyReflections.setParameters(branch)
        diffuser.setParameters(branch)
        tail.setParameters(parameters.tail)

        recomputePreDelay()
    }

    /// Bereitet die gesamte Kette fuer eine (neue) Sample-Rate vor: alle
    /// Bausteine und der Pre-Delay-Puffer werden neu bemessen und der Zustand
    /// zurueckgesetzt. Keine Allokation ausserhalb von `init`/
    /// `prepare(sampleRate:)`.
    public mutating func prepare(sampleRate: Double) {
        let safeSampleRate = AudioCoreDeepSpaceParameters.safeSampleRate(sampleRate)
        self.sampleRate = safeSampleRate

        earlyReflections.prepare(sampleRate: safeSampleRate)
        diffuser.prepare(sampleRate: safeSampleRate)
        tail.prepare(sampleRate: safeSampleRate)

        preDelayBuffer = Array(
            repeating: 0,
            count: AudioCoreDeepSpace.preDelayCapacity(forSampleRate: safeSampleRate)
        )
        preDelayWriteIndex = 0
        recomputePreDelay()
    }

    // MARK: – Reset
    //
    // Setzt den gesamten Kettenzustand zurueck. Dieselbe Eingabefolge nach
    // `reset()` reproduziert denselben Ausgabeverlauf wie eine frische Instanz
    // mit identischen Parametern.
    //
    // Alloziert nicht (In-Place-Nullen des Ringpuffers, wie in
    // `AudioCoreDeepSpaceEarlyReflections.reset()`). Seit W-03a gilt das fuer
    // die ganze Kette inklusive des geerbten
    // `AudioCoreDeepSpaceFDNTail.reset()`: gemessen 0 Allokationen ueber
    // 10.000 Aufrufe (siehe Dateikommentar, "Realtime-Vertrag").
    public mutating func reset() {
        for i in preDelayBuffer.indices { preDelayBuffer[i] = 0 }
        preDelayWriteIndex = 0

        earlyReflections.reset()
        diffuser.reset()
        tail.reset()
    }

    // MARK: – Kapazitaet/Pre-Delay-Berechnung
    //
    // Die Kapazitaet wird immer fuer den maximal moeglichen Pre-Delay-Wert
    // bemessen, unabhaengig vom aktuellen Parameterwert — dadurch aendert sich
    // die Puffergroesse nie innerhalb des gueltigen Parameterbereichs, nur bei
    // einer expliziten `prepare(sampleRate:)`. Identisches Muster wie in
    // `AudioCoreDeepSpaceEarlyReflections.capacity(forSampleRate:)`.

    private static func preDelayCapacity(forSampleRate sampleRate: Double) -> Int {
        let maxSeconds = Double(AudioCoreDeepSpaceParameters.maxPreDelaySeconds)
        let samples = Int((maxSeconds * sampleRate).rounded(.up))
        return max(samples + preDelayCapacityMargin, 16)
    }

    private mutating func recomputePreDelay() {
        let capacity = preDelayBuffer.count
        // Redundante Crash-Sicherung (Muster aus S-08a-fix): die Klemmung in
        // `AudioCoreDeepSpaceParameters` ist die Semantik, dieser Guard
        // schuetzt nur die trappende `Double -> Int`-Konvertierung davor.
        let scaled = (Double(parameters.early.preDelaySeconds) * sampleRate).rounded()
        let samples = scaled.isFinite ? Int(scaled) : 0
        preDelaySamples = max(0, min(samples, capacity - 1))
    }

    // MARK: – DSP-Render
    //
    // Ein Sample-Schritt durch die vollstaendige Kette. Kein Alloc, kein Lock,
    // keine Dispatch-/Task-/Actor-Nutzung, kein `print`.
    //
    // Bei `preDelaySamples == 0` faellt die Verzoegerungslinie auf einen
    // exakten Durchreicher zurueck: Lese- und Schreibindex sind dann gleich,
    // gelesen wird das gerade geschriebene Sample. Der Default-Pre-Delay ist 0
    // — die Kette startet also ohne zusaetzliche Latenz.
    public mutating func process(_ input: Float) -> (left: Float, right: Float) {
        let x = input.isFinite ? input : 0

        let capacity = preDelayBuffer.count
        preDelayBuffer[preDelayWriteIndex] = x
        let readIndex = (preDelayWriteIndex - preDelaySamples + capacity) % capacity
        let delayed = preDelayBuffer[readIndex]
        preDelayWriteIndex = (preDelayWriteIndex + 1) % capacity

        // Zweig 1: diskrete Erstreflexionen, ohne Diffusor.
        let early = earlyReflections.process(delayed)

        // Zweig 2: Diffusor speist den Rueckkopplungs-Tail.
        let diffused = diffuser.process(left: delayed, right: delayed)
        let tailOutput = tail.process(left: diffused.left, right: diffused.right)

        let earlyLevel = parameters.earlyLevel
        let tailLevel = parameters.tailLevel

        let left = early.left * earlyLevel + tailOutput.left * tailLevel
        let right = early.right * earlyLevel + tailOutput.right * tailLevel

        // Wie bei den drei Bausteinen seit Runde 064: keine
        // Wertebereichsklemmung in einem Zwischenbaustein, nur die
        // Endlichkeitsabsicherung.
        return (left.isFinite ? left : 0, right.isFinite ? right : 0)
    }

    /// Blockweise Variante von `process(_:)` — schreibt ADDITIV in die vom
    /// Aufrufer bereitgestellten Stereo-Puffer, identischer Vertrag wie
    /// `AudioCoreAtmosphericVoice.render(intoL:intoR:frameCount:)`.
    ///
    /// Die Kette haelt keinerlei blockbezogenen Zustand: jedes Sample laeuft
    /// unabhaengig durch dieselbe Sample-Schrittfunktion. Ein Render in einem
    /// Stueck ist deshalb bit-identisch zu demselben Render in beliebig
    /// geschnittenen Teilbloecken, auch bei Blockgroessen, die kein Teiler
    /// interner Perioden sind
    /// (`test_render_isInvariantToBlockSegmentation`).
    public mutating func render(input: UnsafePointer<Float>,
                                 intoL outputL: UnsafeMutablePointer<Float>,
                                 intoR outputR: UnsafeMutablePointer<Float>,
                                 frameCount: Int) {
        for frame in 0..<frameCount {
            let stereo = process(input[frame])
            outputL[frame] += stereo.left
            outputR[frame] += stereo.right
        }
    }
}
