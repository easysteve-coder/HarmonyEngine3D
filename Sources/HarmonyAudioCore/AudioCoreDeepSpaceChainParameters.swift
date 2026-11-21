import Darwin

// MARK: – AudioCoreDeepSpaceChainParameters
//
// W-02 (`.agent_handoff/latest_codex.md`, Runde 067): Parametersatz fuer den
// zusammengeschalteten Raumprozessor `AudioCoreDeepSpace`
// (`SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 7.3).
//
// Bewusst eine KLAMMER um die beiden bestehenden Parametertypen statt eines
// dritten, flachen Parametersatzes: `AudioCoreDeepSpaceParameters` (Pre-Delay,
// Groesse, Early-Reflection-Mix, Diffusion) und
// `AudioCoreDeepSpaceFDNParameters` (Groesse, Decay, Daempfung,
// Modulationstiefe/-rate) sind abgenommen, getestet und tragen ihre eigene
// Klemmung. Ein flacher Neuentwurf haette diese Klemmung dupliziert — genau
// der Fehler, den Finding S-08a-01 aufgedeckt hat.
//
// Hinzu kommen genau zwei neue Groessen: die Pegel der beiden parallelen
// Zweige (`earlyLevel`, `tailLevel`). Sie sind das einzige klangpraegende
// Verhaeltnis dieses Slices und deshalb ausdruecklich VORLAEUFIG (siehe
// `defaultEarlyLevel`/`defaultTailLevel`).
//
// S-08a-01-Lehre (Pflicht fuer jeden neuen Typ seit Runde 059): alle Felder
// sind `public var`, direkte Feldmutation nach `init` umgeht jede Grenze.
// Dieser `init` baut deshalb AUCH die beiden eingebetteten Parametersaetze
// ueber deren eigene `init(...)` neu auf — die Klemmung der Bausteine wird
// dadurch erzwungen statt hier dupliziert. `AudioCoreDeepSpace
// .setParameters(_:)` laeuft ueber genau diesen `init`.

public struct AudioCoreDeepSpaceChainParameters: Sendable, Equatable {

    // MARK: – Vorlaeufige Zweigpegel
    //
    // ACHTUNG, ausdruecklich VORLAEUFIG (Handoff Runde 067: "konservative
    // Startwerte waehlen und im Ruecklauf ausdruecklich als vorlaeufig
    // melden, keine Art Direction"). Stephan hoert die Kette ab W-03 zum
    // ersten Mal und entscheidet dann ueber das Verhaeltnis.
    //
    // Warum ausgerechnet 0,5 / 0,5 — und warum das KEINE Klangentscheidung
    // ist:
    //
    // 1. Gleiche Gewichtung ist der einzige Wert, der keine Praeferenz
    //    ausdrueckt. Jede Ungleichverteilung waere bereits eine Aussage
    //    darueber, ob der Raum eher "nah/diskret" (Reflexionen dominant) oder
    //    eher "weit/verwaschen" (Tail dominant) klingen soll — genau die
    //    Entscheidung, die dieser Slice nicht treffen darf.
    // 2. Beide Zweige bleiben hoerbar. Ein Wert von 0 an einem Zweig haette
    //    die Zusammenschaltung fuer die erste Abnahme entwertet.
    // 3. Der Faktor 0,5 auf beiden Zweigen halbiert zugleich den Summenpegel
    //    gegenueber einer ungewichteten Addition — das ist der konservative,
    //    headroom-freundliche Startpunkt fuer einen Send-Bus-Prozessor, der
    //    die Summe mehrerer Stimmen traegt.
    public static let defaultEarlyLevel: Float = 0.5
    public static let defaultTailLevel: Float = 0.5

    /// Parameter des Early-Reflection-Zweigs UND des Eingangs-Diffusors.
    ///
    /// `preDelaySeconds` wirkt in der Kette vor der Aufteilung auf die beiden
    /// Zweige (siehe `AudioCoreDeepSpace`, Abschnitt "Signalweg") und damit
    /// auf Reflexionen und Tail gleichermassen — nicht mehr nur innerhalb der
    /// Early-Reflection-Stufe.
    public var early: AudioCoreDeepSpaceParameters

    /// Parameter des FDN-Tails.
    ///
    /// `size` ist hier bewusst von `early.size` GETRENNT: die beiden Groessen
    /// beschreiben verschiedene Zeitachsen (Ausbreitung diskreter Reflexions-
    /// Taps gegenueber Laenge der acht Rueckkopplungslinien). Ob und wie beide
    /// an einem gemeinsamen Bedienelement haengen, ist eine UX-/Klangfrage und
    /// gehoert nach W-03/W-05, nicht in diesen Slice.
    public var tail: AudioCoreDeepSpaceFDNParameters

    /// Pegel des Early-Reflection-Zweigs in der Summe, 0...1. Vorlaeufig.
    public var earlyLevel: Float

    /// Pegel des Tail-Zweigs in der Summe, 0...1. Vorlaeufig.
    public var tailLevel: Float

    public init(early: AudioCoreDeepSpaceParameters = AudioCoreDeepSpaceParameters(),
                tail: AudioCoreDeepSpaceFDNParameters = AudioCoreDeepSpaceFDNParameters(),
                earlyLevel: Float = AudioCoreDeepSpaceChainParameters.defaultEarlyLevel,
                tailLevel: Float = AudioCoreDeepSpaceChainParameters.defaultTailLevel) {

        // Neuaufbau ueber die `init` der Bausteinparameter: erzwingt deren
        // bestehende Klemmung auch bei einem ueber `public var` nachtraeglich
        // veraenderten Satz. Kein Klemm-Duplikat in dieser Datei.
        self.early = AudioCoreDeepSpaceParameters(
            preDelaySeconds: early.preDelaySeconds,
            size: early.size,
            earlyReflectionMix: early.earlyReflectionMix,
            diffusion: early.diffusion
        )
        self.tail = AudioCoreDeepSpaceFDNParameters(
            size: tail.size,
            decay: tail.decay,
            damping: tail.damping,
            modulationDepth: tail.modulationDepth,
            modulationRate: tail.modulationRate
        )
        self.earlyLevel = AudioCoreDeepSpaceChainParameters.clampUnit(earlyLevel)
        self.tailLevel = AudioCoreDeepSpaceChainParameters.clampUnit(tailLevel)
    }

    fileprivate static func clampUnit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return max(0.0, min(value, 1.0))
    }
}
