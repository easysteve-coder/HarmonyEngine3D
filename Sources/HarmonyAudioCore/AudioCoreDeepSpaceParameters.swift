import Darwin

// MARK: – AudioCoreDeepSpaceParameters
//
// S-08a (`.agent_handoff/latest_codex.md`, Runde 057), Scope A: gemeinsames
// Parameterset fuer Early Reflections (Scope B) und Eingangs-Diffusoren
// (Scope C) des ersten `DeepSpace`-Bausteins (`SYNTH_ARCHITECTURE_PLAN.md`,
// Abschnitt 7.3). Bewusst EIN gemeinsamer Parametertyp statt zwei
// getrennter — beide Stufen teilen sich dieselbe Groessen-/Zeitachse
// ("Size" skaliert sowohl die Reflection-Ausbreitung als auch implizit den
// wahrgenommenen Raum), und Scope A verlangt ausdruecklich "klare
// Parameter/Config fuer Sample Rate, Pre-Delay/Early-Reflection-Mix,
// Diffusion/Feedback und Groesse/Zeiten".
//
// Alle Felder sind reine Daten-/Sicherheitsgrenzen (technische Bereiche),
// keine Klangabnahme. Konservative Defaults halten den bestehenden
// Produktklang unveraendert, da dieser Typ noch nirgends verdrahtet ist.
//
// S-08a-fix (Finding S-08a-01): die Felder sind `public var`, direkte
// Feldmutation an einer bereits konstruierten Instanz umgeht die Klemmung
// im `init`. `AudioCoreDeepSpaceEarlyReflections.setParameters(_:)` und
// `AudioCoreDeepSpaceDiffuser.setParameters(_:)` stellen die Invariante her,
// indem sie den uebernommenen Parametersatz ueber diesen `init` neu
// aufbauen, statt eine zweite Klemmlogik zu duplizieren.
//
// S-08b Teil 1 (Finding S-08a-02): `safeSampleRate` klemmte bisher nur nach
// unten (`isFinite && > 0`). Eine endliche, aber absurd grosse Sample Rate
// (z. B. `1e300`) liess die `Double -> Int`-Pufferlaengen-Konvertierung in
// `AudioCoreDeepSpaceEarlyReflections.capacity(forSampleRate:)` und
// `AudioCoreDeepSpaceAllpassStage.init(delayMs:sampleRate:)` ueberlaufen
// (verifizierter SIGTRAP). `maxSampleRate`/`safeSampleRate(_:)` sind jetzt
// die EINE gemeinsame Stelle fuer die gesamte `DeepSpace`-Familie (Early
// Reflections, Diffusor, FDN-Tail) statt einer Kopie pro Typ.
//
// Runde 064 (S-08c-Review-Beobachtung): `safeSampleRate` hatte bis hierhin
// keine Untergrenze -- jede endliche, positive Sample Rate war zulaessig,
// auch `0.001`. Unterhalb von ca. 0,7 Hz wird in
// `AudioCoreDeepSpaceFDNTail` `modIncrement > 1`, und der dortige einfache
// Phasen-Wrap (`if modPhase >= 1.0 { modPhase -= 1.0 }`) haelt `modPhase`
// dann nicht mehr in `[0, 1)` -- kein Crash (die bestehende Guard-Kette haelt
// alle Ausgaben endlich, verifiziert bei Sample Rate 44100/1/0.5/0.1), aber
// die Modulation degeneriert. `minSampleRate` (100 Hz) ist eine rein
// technische Sicherheitsgrenze: klar unterhalb jeder realen Audio-Hardware
// (professionelle Interfaces starten bei ca. 8 kHz), aber mit ~140-fachem
// Sicherheitsabstand deutlich oberhalb des 0,7-Hz-Problembereichs.

public struct AudioCoreDeepSpaceParameters: Sendable, Equatable {

    /// Technische Obergrenze fuer Sample Rates in der gesamten `DeepSpace`-
    /// Familie (Finding S-08a-02). 1.000.000 Hz liegt weit oberhalb jeder
    /// realen Audio-Hardware (professionelle Interfaces erreichen aktuell
    /// hoechstens ca. 768 kHz) und haelt gleichzeitig jede aus der Sample
    /// Rate abgeleitete Pufferlaenge in einem konservativen, dokumentierten
    /// Speicherbudget (siehe `AudioCoreDeepSpaceFDNTail`, dessen acht
    /// Delaylinien die groesste betroffene Allokation sind).
    public static let maxSampleRate: Double = 1_000_000.0

    /// Technische Untergrenze fuer Sample Rates in der gesamten `DeepSpace`-
    /// Familie (Runde 064, S-08c-Review-Beobachtung). 100 Hz liegt deutlich
    /// unterhalb jeder realen Audio-Hardware und mit grossem Sicherheitsabstand
    /// oberhalb des Bereichs (< ca. 0,7 Hz), in dem `AudioCoreDeepSpaceFDNTail`s
    /// Modulationsphasenlauf (`modIncrement`) degeneriert. Reine technische
    /// Sicherheitsgrenze, keine Klangentscheidung.
    public static let minSampleRate: Double = 100.0

    /// Obergrenze fuer Pre-Delay, technische Sicherheitsgrenze (Scope A).
    public static let maxPreDelaySeconds: Float = 0.1

    /// Pre-Delay vor der ersten Reflection, 0...0.1 s (100 ms) begrenzt.
    public var preDelaySeconds: Float
    /// Groesse/Ausbreitung des Raums, 0...1. Skaliert die Zeitabstaende der
    /// Early-Reflection-Taps zwischen einem kleinen (kurz) und einem
    /// grossen (lang) Referenzraum (`AudioCoreDeepSpaceEarlyReflections`).
    public var size: Float
    /// Wet-Anteil der Early-Reflection-Stufe, 0...1.
    public var earlyReflectionMix: Float
    /// Diffusionsmenge der Eingangs-Diffusor-Kette, 0...1. Wird intern auf
    /// einen sicheren, strikt unter der Runaway-Grenze liegenden Allpass-
    /// Koeffizientenbereich abgebildet (`AudioCoreDeepSpaceDiffuser`).
    public var diffusion: Float

    public init(preDelaySeconds: Float = 0.0,
                size: Float = 0.5,
                earlyReflectionMix: Float = 1.0,
                diffusion: Float = 0.5) {
        self.preDelaySeconds = AudioCoreDeepSpaceParameters.clamp(
            preDelaySeconds, 0.0, AudioCoreDeepSpaceParameters.maxPreDelaySeconds
        )
        self.size = AudioCoreDeepSpaceParameters.clampUnit(size)
        self.earlyReflectionMix = AudioCoreDeepSpaceParameters.clampUnit(earlyReflectionMix)
        self.diffusion = AudioCoreDeepSpaceParameters.clampUnit(diffusion)
    }

    fileprivate static func clampUnit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return max(0.0, min(value, 1.0))
    }

    fileprivate static func clamp(_ value: Float, _ lo: Float, _ hi: Float) -> Float {
        guard value.isFinite else { return lo }
        return max(lo, min(value, hi))
    }

    /// Gemeinsame Sample-Rate-Klemmung fuer die gesamte `DeepSpace`-Familie
    /// (Early Reflections, Diffusor, FDN-Tail) — eine Stelle statt einer
    /// Kopie pro Typ (Finding S-08a-02, Untergrenze seit Runde 064).
    public static func safeSampleRate(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 44_100.0 }
        return min(max(value, minSampleRate), maxSampleRate)
    }
}
