import Darwin

// MARK: – AudioCoreDeepSpaceFDNParameters
//
// S-08b (`.agent_handoff/latest_codex.md`, Runde 059), Teil 2: Parametersatz
// fuer den modulationsfreien Feedback-Delay-Network-Tail
// (`AudioCoreDeepSpaceFDNTail`, `SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 7.3:
// "Tail von kurzen Raeumen bis zu sehr langen Flaechen"). Ein eigener
// Parametertyp statt Wiederverwendung von `AudioCoreDeepSpaceParameters`,
// weil der Tail zusaetzliche, fuer Early Reflections/Diffusor nicht
// relevante Groessen braucht (`decay`, `damping`) und `size` hier eine
// andere Groessenachse (Delaylinien-Laengen fuer einen echten Rueckkopplungs-
// Tail) als bei den Early-Reflection-Taps beschreibt.
//
// Alle Felder sind reine Daten-/Sicherheitsgrenzen (technische Bereiche),
// keine Klangabnahme. `size`/`decay`/`damping` sind bewusst normalisierte
// 0...1-Groessen (wie bei allen bisherigen `HarmonyAudioCore`-Parametertypen),
// die konkrete Abbildung auf Millisekunden/RT60/Filterkoeffizient lebt in
// `AudioCoreDeepSpaceFDNTail`.
//
// S-08a-01-Lehre (gilt fuer jeden neuen Typ ab Runde 059): Felder sind
// `public var`, direkte Feldmutation nach `init` umgeht die Klemmung dort.
// `AudioCoreDeepSpaceFDNTail.setParameters(_:)` baut den uebernommenen
// Parametersatz deshalb ueber diesen `init` neu auf, statt eine zweite
// Klemmlogik zu duplizieren — identisches Muster zu
// `AudioCoreDeepSpaceEarlyReflections`/`AudioCoreDeepSpaceDiffuser`.
//
// S-08c (`.agent_handoff/latest_codex.md`, Runde 061): zwei zusaetzliche
// normalisierte 0...1-Groessen fuer die dekorrelierte Delaymodulation im
// Feedbackpfad (`SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 7.3: "langsame,
// decorrelierte Delaymodulation"). Default `modulationDepth = 0` haelt das
// bestehende, modulationsfreie Verhalten (Commit `01085ba`) bit-identisch
// bei jedem Aufrufer, der diesen Parameter nicht explizit setzt —
// `AudioCoreDeepSpaceFDNTail.process` verzweigt intern auf den
// unveraenderten S-08b-fix-Lesepfad, solange `modulationDepth == 0`.
// Konkrete Millisekunden-/Hz-Abbildung lebt wie bei `size`/`decay`/
// `damping` in `AudioCoreDeepSpaceFDNTail`.

public struct AudioCoreDeepSpaceFDNParameters: Sendable, Equatable {

    /// Kuerzeste abbildbare Abklingzeit (RT60), bei `decay == 0`.
    public static let minRT60Seconds: Float = 0.3
    /// Laengste abbildbare Abklingzeit (RT60), bei `decay == 1` — "sehr
    /// lange Flaechen" im Sinne von Abschnitt 7.3, ohne die
    /// Selbstoszillationsgrenze zu erreichen (jedes endliche RT60 ergibt
    /// einen Rundlauf-Gain < 1, siehe `AudioCoreDeepSpaceFDNTail`).
    public static let maxRT60Seconds: Float = 60.0

    /// Groesse/Ausbreitung des Tails, 0...1. Skaliert die acht
    /// Delaylinien-Laengen zwischen einem kurzen und einem sehr langen
    /// Referenzraum (`AudioCoreDeepSpaceFDNTail`).
    public var size: Float
    /// Abklingzeit, 0...1, logarithmisch auf RT60 `minRT60Seconds`...
    /// `maxRT60Seconds` abgebildet.
    public var decay: Float
    /// Frequenzabhaengige Daempfung je Feedbackleitung, 0...1 (0 = kein
    /// zusaetzlicher Hochtonverlust pro Umlauf, 1 = starker Hochtonverlust
    /// pro Umlauf durch einen Ein-Pol-Tiefpass im Feedbackpfad).
    public var damping: Float
    /// Tiefe der Delaymodulation je Linie, 0...1. `0` (Default) bedeutet
    /// keine Modulation — `AudioCoreDeepSpaceFDNTail.process` bleibt in
    /// diesem Fall bit-identisch zum modulationsfreien S-08b-fix-Stand.
    /// `1` bildet auf `AudioCoreDeepSpaceFDNTail.maxModulationDepthSamples`
    /// ab, zusaetzlich je Linie dynamisch auf `lineLengthSamples - 1`
    /// gedeckelt (verhindert negative effektive Delayzeiten bei sehr
    /// kurzen Linien, z. B. bei extrem niedrigen Sample Rates).
    public var modulationDepth: Float
    /// Rate der Delaymodulation, 0...1, linear auf
    /// `AudioCoreDeepSpaceFDNTail.minModulationRateHz`...
    /// `maxModulationRateHz` abgebildet (bewusst niedrig begrenzt — siehe
    /// dortige Konstanten). Ohne Wirkung, solange `modulationDepth == 0`.
    public var modulationRate: Float

    public init(size: Float = 0.5, decay: Float = 0.5, damping: Float = 0.5,
                modulationDepth: Float = 0.0, modulationRate: Float = 0.5) {
        self.size = AudioCoreDeepSpaceFDNParameters.clampUnit(size)
        self.decay = AudioCoreDeepSpaceFDNParameters.clampUnit(decay)
        self.damping = AudioCoreDeepSpaceFDNParameters.clampUnit(damping)
        self.modulationDepth = AudioCoreDeepSpaceFDNParameters.clampUnit(modulationDepth)
        self.modulationRate = AudioCoreDeepSpaceFDNParameters.clampUnit(modulationRate)
    }

    fileprivate static func clampUnit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return max(0.0, min(value, 1.0))
    }
}
