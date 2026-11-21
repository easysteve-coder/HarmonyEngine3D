import Darwin

// MARK: – AudioCoreDeepSpaceFDNTail
//
// S-08b (`.agent_handoff/latest_codex.md`, Runde 059), Teil 2:
// modulationsfreier Feedback-Delay-Network-Tail fuer den `DeepSpace`-
// Baustein (`SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 7.3: "mindestens acht
// unterschiedlich lange Delaylines; orthogonale Feedback-Matrix;
// frequenzabhaengige Daempfung; Tail von kurzen Raeumen bis zu sehr langen
// Flaechen"). Bewusst OHNE Delaymodulation (S-08c folgt separat) — reine,
// entkoppelte DSP-Infrastruktur, noch nicht mit Early Reflections/Diffusor
// verbunden und noch nicht an einen Send-Bus angeschlossen.
//
// Topologie (Standard-FDN nach Jot, siehe auch Julius O. Smith, "Physical
// Audio Signal Processing", Abschnitt "Feedback Delay Networks" — frei
// dokumentiert, keine proprietaere Implementierung):
//
// - Acht Delaylinien mit paarweise TEILERFREMDEN Laengen: jede Linienlaenge
//   wird auf die naechste, noch nicht vergebene Primzahl gerundet
//   (`nearestPrime`). Zwei verschiedene Primzahlen haben zwingend ggT 1 —
//   das macht "teilerfremd" zu einer exakten, testbaren Eigenschaft statt
//   einer Naeherung, unabhaengig von `size`/Sample Rate.
// - `AudioCoreDeepSpaceFDNMatrix`: energieerhaltende Ordnung-8-Hadamard-
//   Feedback-Matrix.
// - je Linie ein Ein-Pol-Tiefpass im Feedbackpfad (frequenzabhaengige
//   Daempfung, DC-Gain exakt 1, monoton fallende Verstaerkung zu hohen
//   Frequenzen).
// - je Linie ein Rundlauf-Gain `g_i = 10^(-3 * L_i_seconds / RT60)`
//   (Jot-Standardformel), abgeleitet aus einem gemeinsamen RT60-Sollwert —
//   alle acht Linien klingen dadurch konsistent im selben RT60 ab,
//   unabhaengig von ihrer individuellen Laenge.
//
// Stabilitaetsargument (keine Selbstoszillation, auch nicht am
// Parameterlimit): fuer jedes ENDLICHE RT60 > 0 ist `g_i` streng kleiner
// als 1 (zusaetzlich hart auf `maxLineGain` gedeckelt). Der Ein-Pol-
// Tiefpass hat bei jeder Frequenz eine Verstaerkung <= 1 (DC-Gain exakt 1,
// faellt zu hohen Frequenzen). Die Hadamard-Matrix ist energieerhaltend
// (`||Mx|| == ||x||`). Die Gesamtschleifenverstaerkung bei jeder Frequenz
// ist damit fuer jedes endliche `decay`/`size` durch `max(g_i) < 1`
// begrenzt — die Zustandsnorm nimmt bei jedem vollstaendigen Umlauf ab,
// unabhaengig davon, wie nah `decay` an 1 liegt.
//
// Realtime-Vertrag (korrigiert, S-08b-fix, Finding S-08b-01):
// `process(left:right:)` alloziiert keine Arrays mehr, sperrt nicht, nutzt
// keine Dispatch-/Task-/Actor-Ausfuehrung und schreibt nicht (kein
// `print`). Per SIL (`swiftc -O -wmo -emit-sil`) belegt: vor diesem Fix
// blieben trotz Optimizer mindestens zwei Heap-Array-Allokationen pro
// Sample uebrig (`delayed`/`damped` in `process` plus das Ausgabe-Array
// von `AudioCoreDeepSpaceFDNMatrix.apply`). Alle drei Zwischenpuffer
// (`delayedScratch`/`dampedScratch`/`matrixScratch`) sind jetzt gespeicherte
// Eigenschaften mit fester Groesse `lineCount`, ausschliesslich in `init`/
// `prepare(sampleRate:)` angelegt und in `process` nur noch beschrieben.
// `AudioCoreDeepSpaceFDNMatrix.apply(_:into:)` schreibt direkt in
// `matrixScratch`, alloziiert selbst nichts.
//
// Die acht Delaylinien liegen nicht mehr als `[[Float]]` vor (geschachtelte
// Array-Indirektion mit eigener Uniqueness-Pruefung je Linie, im SIL-Beleg
// als zusaetzliche `_ArrayBuffer._consumeAndCreateNew`-CoW-Pfade sichtbar),
// sondern als ein einziger flacher `[Float]`-Puffer mit einem festen
// Offset je Linie (`lineOffset`) — ein flacher Puffer statt geschachtelter
// Arrays macht den Realtime-Vertrag robuster und leichter beweisbar.
// Alle acht Delaypuffer werden ausschliesslich in `init`/
// `prepare(sampleRate:)` alloziiert, niemals in `process(left:right:)`.
// `setParameters(_:)` veraendert nur Zielwerte (Linienlaengen/-gains/
// Daempfungskoeffizient) innerhalb bereits allozierter Kapazitaet — keine
// Reallokation.
//
// W-03a (`.agent_handoff/latest_codex.md`, Runde 068): der Realtime-Vertrag
// gilt seitdem fuer den GANZEN Typ, nicht nur fuer `process(left:right:)`.
// Jede Funktion, die spaeter aus einem Command im Rendercallback erreichbar
// ist -- `process(left:right:)`, `setParameters(_:)`, `reset()` -- ist
// allokationsfrei. Nur `init` und `prepare(sampleRate:)` duerfen allozieren;
// beide laufen ausschliesslich auf der Kontrollrate.
//
// Drei Stellen waren dafuer zu schliessen, alle drei ohne Klangaenderung
// (bit-identisch zu `b7f26d1`, siehe `AudioCoreDeepSpaceFDNTests`):
//
// 1. `recomputeLineState()` fuehrte die Ausschlussliste der Primzahlwahl als
//    `Set<Int>` -- 4 Allokationen je `setParameters(_:)`-Aufruf, innerhalb
//    der Standardbibliothek und damit unsichtbar fuer einen SIL-Textscan
//    ueber Instruktions-Opcodes (Finding W-02-01). Ersetzt durch den festen
//    `usedPrimeScratch` mit linearer Suche.
// 2. `reset()` baute `writeIndex`/`dampingFilterState` mit
//    `Array(repeating:count:)` neu auf -- 2 Allokationen je Aufruf. Jetzt in
//    place genullt.
// 3. Neu in W-03a gefunden, und zwar erst durch die Laufzeitmessung: zwei
//    AUFGESCHOBENE Allokationen, die nicht in der aufrufenden Funktion
//    anfielen, sondern im naechsten `process`-Aufruf -- die
//    Copy-on-Write-Kopie von `modPhase` nach `modPhase =
//    modulationPhaseOffsets` (1 je `init`/`prepare`/`reset`) und die faule
//    `static let`-Initialisierung der beiden ueber `map` gebildeten
//    Gewichtstabellen (2 einmalig je Prozess). Siehe
//    `resetModulationPhase()` und die Renderkonstanten-Eigenschaften.
//
// Die Nachweismethode ist entsprechend zweiteilig plus Messung: SIL-Scan auf
// Allokations-Instruktionen, SIL-Scan auf die AUFRUFLISTEN nach allozierenden
// Stdlib-Aufrufen, und eine Laufzeitmessung mit interponiertem
// `malloc`/`calloc`/`realloc`. Nur die Messung findet Fall 3 -- eine
// aufgeschobene Kopie steht in keiner der beiden Aufruflisten.
//
// S-08c (`.agent_handoff/latest_codex.md`, Runde 061): dekorrelierte
// Delaymodulation im Feedbackpfad, mit fraktionaler, linear interpolierter
// Leseposition je Linie (`SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 7.3:
// "langsame, decorrelierte Delaymodulation").
//
// Dekorrelation: Rate- und Phasenversatz je Linie kommen aus zwei
// Kronecker/Weyl-Folgen ueber zwei verschiedene irrationale Konstanten
// (goldener Schnitt bzw. Silberner Schnitt, siehe
// `modulationRateMultipliers`/`modulationPhaseOffsets`). Fuer zwei Linien
// i != j ist das Verhaeltnis ihrer Raten damit nie ein einfacher
// rationaler Bruch — es entsteht keine gemeinsame Periode, also keine
// hoerbare Schwebung zwischen den acht Modulationsverlaeufen, unabhaengig
// von der Renderdauer.
//
// Interpolation: linear (naheliegender, im Auftrag vorgeschlagener
// Startpunkt), als einzige Implementierung in `linearInterpolate(_:_:
// fraction:)`. Linear genuegt hier aus zwei Gruenden: (1) die
// Modulationstiefe ist klein (`maxModulationDepthSamples`, siehe unten),
// linear vs. Allpass/Lagrange unterscheidet sich bei so kleinen
// fraktionalen Verschiebungen kaum hoerbar, waehrend Allpass-Interpolation
// selbst einen (kleinen, aber echten) Zustand mit eigener
// Reset-/Determinismuspflicht einfuehren wuerde; (2) linear ist eine
// KONVEXKOMBINATION der beiden Nachbar-Taps (Gewichte `1-frac`/`frac`,
// beide in `[0,1]`, Summe exakt 1) — der interpolierte Wert kann die
// Amplitude der beiden Quell-Samples nachweisbar nie ueberschreiten
// (`|Interpolation| <= max(|tapA|, |tapB|)`, Dreiecksungleichung). Das
// bestehende Stabilitaetsargument (Rundlauf-Gain `g_i < 1`, Tiefpass
// `|H| <= 1`, orthonormale Matrix) greift damit unveraendert auch auf den
// interpolierten Wert, ohne eine eigene Stabilitaetsanalyse fuer die
// Interpolationsstufe zu brauchen. Ein Allpass/Lagrange-Wechsel waere ein
// Mehraufwand ohne belegten Artefaktvorteil bei dieser Modulationstiefe —
// siehe `test_linearInterpolate_isBoundedConvexCombination` und die
// Kontinuitaets-/Sample-Delta-Tests in `AudioCoreDeepSpaceFDNTests.swift`.
//
// Bit-Identitaet bei Tiefe 0: `process(left:right:)` verzweigt VOR jeder
// Modulationsrechnung auf `parameters.modulationDepth > 0`. Bei `false`
// (Default) laeuft exakt derselbe, textuell unveraenderte Lesepfad wie im
// S-08b-fix-Stand (`(writeIndex[i] - lineLengthSamples[i] + capacity) %
// capacity`) — keine Gleitkomma-Rechenkette, die zufaellig auf denselben
// Wert rundet, sondern derselbe Code, dieselben Bits.
//
// Kapazitaetsreserve: `lineLengthSamples`/`lineGain`/`dampingCoefficient`
// werden weiterhin exakt wie vor S-08c berechnet — `recomputeLineState()`
// nutzt dafuer `baseCapacity[i] - 1` (identisch zum alten
// `lineCapacity[i] - 1` vor S-08c) als Klemm-/Suchgrenze, nicht die neue,
// groessere `lineCapacity[i]`. Das haelt die Linienlaengen-/Primzahlwahl
// byteidentisch zu `01085ba`, unabhaengig von der zusaetzlichen Reserve.
// `lineCapacity[i]` (der tatsaechlich allozierte Puffer) ist um
// `modulationCapacityReserve` groesser als `baseCapacity[i]` — fest
// bemessen fuer den maximal moeglichen Modulationsausschlag
// (`maxModulationDepthSamples`) plus einen Interpolations-Tap
// (`interpolationTapGuard`), damit die fraktionale Leseposition (Basis-
// Delay plus/minus Modulationshub, plus ein Tap fuer die Interpolation)
// niemals ausserhalb der allozierten Kapazitaet liegen kann — rechnerisch
// bewiesen, nicht zur Laufzeit geklemmt (siehe `recomputeModulationState()`
// fuer die per-Linie-Deckelung gegen zu kurze Linien). Die effektive
// Leselaenge bleibt dadurch immer `>= 1` und `<= lineCapacity[i] - 2`.

public struct AudioCoreDeepSpaceFDNTail: Sendable, Equatable {

    /// Anzahl Delaylinien.
    public static let lineCount = AudioCoreDeepSpaceFDNMatrix.order

    // Geometrisch gespreizte Laengenverhaeltnisse je Linie (1.0...2.6, acht
    // Stufen) -- sorgen fuer deutlich unterschiedliche Ziel-Laengen vor der
    // Primzahlrundung, Grundlage der "moeglichst teilerfremd"-Anforderung.
    private static let lengthRatios: [Float] = (0..<lineCount).map { i -> Float in
        powf(2.6, Float(i) / Float(lineCount - 1))
    }

    // Referenz-Durchschnittslaenge in Millisekunden bei size = 0 (kurzer
    // Raum) bzw. size = 1 (sehr lange Flaeche). Multipliziert mit
    // `lengthRatios` ergibt das acht Ziel-Laengen je Linie.
    private static let minAverageLengthMs: Float = 20.0
    private static let maxAverageLengthMs: Float = 180.0

    // Sicherheitsmarge in Samples oberhalb der bei size = 1 berechneten
    // Ziel-Laenge -- haelt die feste Pufferkapazitaet je Linie immer echt
    // groesser als jede bei aktuellem `size` moegliche Arbeits-Laenge, ohne
    // Reallokation bei einer `setParameters(_:)`-Groessenaenderung.
    private static let capacityMarginSamples = 32

    // Rundlauf-Gain wird zusaetzlich zur RT60-Formel hart gedeckelt (siehe
    // Dateikommentar, Stabilitaetsargument) -- reine Sicherheitsmarge gegen
    // Gleitkomma-Randfaelle nahe 1.
    private static let maxLineGain: Float = 0.999

    // Ein-Pol-Tiefpass-Koeffizient bei damping = 1. Deutlich unter 1, damit
    // der Filter bei jedem `damping`-Wert unbedingt stabil bleibt und
    // spuerbar, aber nicht extrem daempft.
    private static let maxDampingCoefficient: Float = 0.7

    // Fester Eingangs-Injektionsvektor: alternierende Vorzeichen dekorrelieren
    // die acht Linien sofort ab dem ersten Sample, 1/sqrt(8) haelt die
    // injizierte Energie pro Linie konservativ.
    private static let inputWeightTable: [Float] = (0..<lineCount).map { i in
        (i % 2 == 0 ? 1.0 : -1.0) * (1.0 / Float(lineCount).squareRoot())
    }

    // Feste Stereo-Ausgangsgewichte je Linie (links/rechts komplementaer,
    // asymmetrisch je Linie -- definierter, stabiler, nicht-identischer
    // Stereo-Ausgang ohne Zufall/Modulation). `outputGain` haelt die Summe
    // der acht gewichteten Taps in einem konservativen Amplitudenbereich.
    private static let outputLeftWeightTable: [Float] = [0.8, 0.2, 0.7, 0.3, 0.6, 0.4, 0.55, 0.45]
    private static let outputRightWeightTable: [Float] = outputLeftWeightTable.map { 1.0 - $0 }
    private static let outputGain: Float = 0.125

    // Obergrenze fuer die Primzahlsuche (siehe `nearestPrime`) -- reine
    // Terminierungsgarantie, praktisch bei Weitem nicht erreichbar (Primzahl-
    // luecken sind fuer die hier vorkommenden Groessenordnungen winzig).
    private static let maxPrimeSearchOffset = 100_000

    // MARK: – S-08c: Delaymodulation, Konstanten
    //
    // Konservative Obergrenze fuer den Modulationshub: selbst bei der
    // kuerzesten vorkommenden Referenzlaenge (`minAverageLengthMs` = 20 ms,
    // z. B. 882 Samples bei 44,1 kHz) bleibt +-8 Samples ein kleiner
    // Bruchteil (< 1 %) der Linienlaenge -- genug fuer hoerbare
    // Dekorrelation der acht Linien, ohne wahrnehmbares Detuning/Pitch-
    // Wobble im Tail. Zusaetzlich je Linie dynamisch auf
    // `lineLengthSamples - 1` gedeckelt (siehe `recomputeModulationState()`),
    // damit die effektive Delayzeit bei sehr kurzen Linien (z. B. extrem
    // niedrige Sample Raten) nie negativ werden kann.
    static let maxModulationDepthSamples: Float = 8.0

    // Bewusst niedrig gehaltener Ratenbereich ("langsame" Modulation laut
    // Auftrag/Abschnitt 7.3): 0,02 Hz entspricht einer Periode von 50 s,
    // 0,35 Hz einer Periode von knapp 2,9 s. Beides bleibt deutlich
    // unterhalb der Rate, ab der Delaymodulation als Chorus/Vibrato bzw.
    // als "Zwitschern" wahrnehmbar wird -- die Modulation soll den Tail nur
    // langsam dekorrelieren, kein hoerbares Modulationsartefakt selbst sein.
    static let minModulationRateHz: Float = 0.02
    static let maxModulationRateHz: Float = 0.35

    // Zusaetzliche Pufferreserve (in Samples) oberhalb von `baseCapacity`,
    // ausschliesslich fuer den Modulationshub plus einen Interpolations-Tap
    // reserviert (siehe Dateikommentar, Abschnitt "Kapazitaetsreserve").
    private static let interpolationTapGuard = 1
    private static let modulationCapacityReserve =
        Int(maxModulationDepthSamples.rounded(.up)) + interpolationTapGuard

    // Kronecker/Weyl-Folgen fuer Rate-/Phasenversatz je Linie (siehe
    // Dateikommentar, Abschnitt "Dekorrelation"). Zwei verschiedene
    // irrationale Konstanten fuer Rate und Phase, damit beide Groessen
    // nicht zufaellig miteinander korrelieren.
    private static let goldenRatioConjugate: Double = 0.618_033_988_749_895
    private static let silverRatioConjugate: Double = 0.414_213_562_373_095

    /// Rate-Multiplikator je Linie, Bereich `[1, 2)`, paarweise mit
    /// irrationalem Verhaeltnis (Kronecker-Folge ueber den goldenen
    /// Schnitt). `internal` statt `private` -- direkt testbar via
    /// `@testable import` fuer den Dekorrelationsnachweis (Akzeptanzgate 4).
    static let modulationRateMultipliers: [Float] = (0..<lineCount).map { i -> Float in
        let fraction = (Double(i) * goldenRatioConjugate).truncatingRemainder(dividingBy: 1.0)
        return Float(1.0 + fraction)
    }

    /// Phasen-Startversatz je Linie, Bereich `[0, 1)` (Kronecker-Folge ueber
    /// den silbernen Schnitt). `internal` aus demselben Grund wie
    /// `modulationRateMultipliers`.
    static let modulationPhaseOffsets: [Double] = (0..<lineCount).map { i -> Double in
        (Double(i) * silverRatioConjugate).truncatingRemainder(dividingBy: 1.0)
    }

    public private(set) var sampleRate: Double
    public private(set) var parameters: AudioCoreDeepSpaceFDNParameters

    /// Basis-Pufferkapazitaet je Linie OHNE Modulationsreserve -- identisch
    /// zur alten (Vor-S-08c) `lineCapacity`-Formel. Ausschliesslich als
    /// Klemm-/Suchgrenze fuer die Linienlaengen-/Primzahlwahl in
    /// `recomputeLineState()` verwendet, damit diese Wahl byteidentisch zu
    /// `01085ba` bleibt (siehe Dateikommentar, Abschnitt
    /// "Kapazitaetsreserve"). Nicht oeffentlich -- kein eigenstaendiger
    /// Vertrag, reines internes Hilfsfeld.
    private var baseCapacity: [Int]

    /// Feste Pufferkapazitaet je Linie in Samples (aus `size` = 1 bei der
    /// aktuellen Sample Rate plus Marge, PLUS Modulationsreserve seit
    /// S-08c) -- unabhaengig vom aktuellen `size`-Wert, damit
    /// `setParameters(_:)` niemals reallozieren muss. Oeffentlich lesbar
    /// fuer Tests/Speicherbudget-Nachweis (analog `lineLengthSamples`).
    public private(set) var lineCapacity: [Int]

    /// Fester Start-Offset je Linie innerhalb des flachen `lineBuffer` --
    /// Praefixsumme ueber `lineCapacity`. Ersetzt die vorherige
    /// `[[Float]]`-Verschachtelung durch einen einzigen zusammenhaengenden
    /// Puffer (S-08b-fix, siehe Dateikommentar).
    private var lineOffset: [Int]
    /// Ein einziger flacher Puffer fuer alle acht Delaylinien
    /// (`lineCapacity.reduce(0, +)` Samples). Linie `i` belegt den Bereich
    /// `lineOffset[i]..<lineOffset[i] + lineCapacity[i]`.
    private var lineBuffer: [Float]
    private var writeIndex: [Int]

    /// Aus Parametern/Sample Rate abgeleitete Linienlaengen in Samples,
    /// paarweise teilerfremd (verschiedene Primzahlen). Oeffentlich
    /// lesbar fuer Tests (analog `sampleRate`/`parameters`).
    public private(set) var lineLengthSamples: [Int]
    private var lineGain: [Float]
    private var dampingFilterState: [Float]
    private var dampingCoefficient: Float = 0

    // S-08c: Modulationszustand. `modPhase` ist fortlaufender, deterministischer
    // Zustand (wie `dampingFilterState`) -- persistiert ueber `setParameters(_:)`
    // hinweg, wird NUR von `init`/`prepare(sampleRate:)`/`reset()` auf die
    // festen `modulationPhaseOffsets` zurueckgesetzt. `modDepthSamples`/
    // `modIncrement` sind dagegen abgeleitete Kontrollrate-Groessen (wie
    // `lineGain`/`dampingCoefficient`) -- neu berechnet bei jedem
    // `recomputeLineState()`-Aufruf, nie in `process(left:right:)`.
    private var modPhase: [Double]
    private var modIncrement: [Double]
    private var modDepthSamples: [Float]

    // Feste Scratch-Puffer fuer `process(left:right:)`, Groesse `lineCount`,
    // ausschliesslich in `init`/`prepare(sampleRate:)` angelegt (S-08b-fix,
    // Finding S-08b-01). `process` beschreibt sie nur noch, alloziiert
    // nicht neu.
    private var delayedScratch: [Float]
    private var dampedScratch: [Float]
    private var matrixScratch: [Float]

    /// Fester Scratch-Puffer fuer die Ausschlussliste der Primzahlwahl in
    /// `recomputeLineState()`, Groesse `lineCount` (W-03a, Finding W-02-01).
    /// Ersetzt das fruehere `var usedPrimes = Set<Int>()`, das pro
    /// `setParameters(_:)`-Aufruf vier Heap-Allokationen INNERHALB der
    /// Standardbibliothek erzeugt hat. Bei acht Elementen ist die lineare
    /// Suche zusaetzlich schneller als ein Set (kein Hashing, ein einziger
    /// zusammenhaengender Speicherbereich).
    ///
    /// Gueltig sind immer nur die ersten `i` Eintraege, waehrend Linie `i`
    /// bearbeitet wird -- Eintraege ab `i` stammen noch aus dem vorherigen
    /// `recomputeLineState()`-Durchlauf. Deshalb fuehrt `nearestPrime` einen
    /// expliziten `usedCount` mit, statt den ganzen Puffer zu durchsuchen.
    private var usedPrimeScratch: [Int]

    // Renderkonstanten, in `init` an die Instanz gebunden statt im Renderpfad
    // ueber `AudioCoreDeepSpaceFDNTail.<static>` gelesen (W-03a, Teil 3).
    //
    // Grund: `static let`-Arrays werden in Swift beim ERSTEN Zugriff angelegt
    // (`swift_once` plus Heap-Allokation, sofern der Wert nicht als
    // statisches Datum ins Binary emittierbar ist). `inputWeightTable` und
    // `outputRightWeightTable` entstehen ueber `map`, sind also nicht
    // statisch emittierbar -- ihr erster Zugriff stand bis W-03a in
    // `process(left:right:)` und fiel damit in den ersten Rendercallback des
    // Prozesses (gemessen: 2 Allokationen im allerersten `process`-Aufruf,
    // danach nie wieder). Die Bindung in `init` verschiebt diese einmalige
    // Allokation auf die Kontrollrate und nimmt zugleich die
    // `swift_once`-Pruefung aus dem Renderpfad.
    //
    // Kein zusaetzlicher Heap-Bedarf je Instanz: die Zuweisung eines Arrays
    // kopiert nicht, sie teilt den Puffer der Konstante. Da diese drei
    // Eigenschaften nie beschrieben werden, entsteht auch nie eine
    // Copy-on-Write-Kopie. Die Werte sind dieselben -- dieselben Arrays, nur
    // frueher gebunden.
    private let inputWeights: [Float]
    private let outputLeftWeights: [Float]
    private let outputRightWeights: [Float]

    public init(sampleRate: Double, parameters: AudioCoreDeepSpaceFDNParameters = AudioCoreDeepSpaceFDNParameters()) {
        let safeSampleRate = AudioCoreDeepSpaceParameters.safeSampleRate(sampleRate)
        self.sampleRate = safeSampleRate
        self.parameters = parameters
        let baseCapacities = AudioCoreDeepSpaceFDNTail.computeBaseCapacities(forSampleRate: safeSampleRate)
        self.baseCapacity = baseCapacities
        let capacities = AudioCoreDeepSpaceFDNTail.capacities(fromBase: baseCapacities)
        self.lineCapacity = capacities
        self.lineOffset = AudioCoreDeepSpaceFDNTail.computeOffsets(fromCapacities: capacities)
        self.lineBuffer = Array(repeating: 0, count: capacities.reduce(0, +))
        self.writeIndex = Array(repeating: 0, count: AudioCoreDeepSpaceFDNTail.lineCount)
        self.lineLengthSamples = Array(repeating: 1, count: AudioCoreDeepSpaceFDNTail.lineCount)
        self.lineGain = Array(repeating: 0, count: AudioCoreDeepSpaceFDNTail.lineCount)
        self.dampingFilterState = Array(repeating: 0, count: AudioCoreDeepSpaceFDNTail.lineCount)
        // Eigener, ausschliesslich dieser Instanz gehoerender Puffer -- NICHT
        // `modPhase = modulationPhaseOffsets` (siehe `resetModulationPhase()`).
        self.modPhase = Array(repeating: 0, count: AudioCoreDeepSpaceFDNTail.lineCount)
        self.modIncrement = Array(repeating: 0, count: AudioCoreDeepSpaceFDNTail.lineCount)
        self.modDepthSamples = Array(repeating: 0, count: AudioCoreDeepSpaceFDNTail.lineCount)
        self.delayedScratch = Array(repeating: 0, count: AudioCoreDeepSpaceFDNTail.lineCount)
        self.dampedScratch = Array(repeating: 0, count: AudioCoreDeepSpaceFDNTail.lineCount)
        self.matrixScratch = Array(repeating: 0, count: AudioCoreDeepSpaceFDNTail.lineCount)
        self.usedPrimeScratch = Array(repeating: 0, count: AudioCoreDeepSpaceFDNTail.lineCount)
        self.inputWeights = AudioCoreDeepSpaceFDNTail.inputWeightTable
        self.outputLeftWeights = AudioCoreDeepSpaceFDNTail.outputLeftWeightTable
        self.outputRightWeights = AudioCoreDeepSpaceFDNTail.outputRightWeightTable
        resetModulationPhase()
        recomputeLineState()
    }

    // MARK: – Parameter/Prepare

    public mutating func setParameters(_ newParameters: AudioCoreDeepSpaceFDNParameters) {
        // S-08a-01-Lehre (Pflicht ab Runde 059 fuer jeden neuen Typ): baut
        // den uebernommenen Parametersatz ueber `init(...)` neu auf, statt
        // eine zweite Klemmlogik zu duplizieren -- identisch zum Muster in
        // `AudioCoreDeepSpaceEarlyReflections`/`AudioCoreDeepSpaceDiffuser`.
        // S-08c: `modulationDepth`/`modulationRate` gehoeren zum selben
        // Klemmpfad wie `size`/`decay`/`damping` -- ohne sie hier
        // mitzunehmen wuerde jeder `setParameters(_:)`-Aufruf die
        // Modulation stillschweigend auf die Defaults zuruecksetzen.
        parameters = AudioCoreDeepSpaceFDNParameters(
            size: newParameters.size, decay: newParameters.decay, damping: newParameters.damping,
            modulationDepth: newParameters.modulationDepth, modulationRate: newParameters.modulationRate
        )
        recomputeLineState()
    }

    /// Bereitet den Tail fuer eine (neue) Sample-Rate vor: alloziiert alle
    /// acht Delaypuffer mit fester, ausreichender Kapazitaet neu und setzt
    /// den Zustand zurueck. Keine Allokation ausserhalb von `init`/
    /// `prepare(sampleRate:)`.
    public mutating func prepare(sampleRate: Double) {
        let safeSampleRate = AudioCoreDeepSpaceParameters.safeSampleRate(sampleRate)
        self.sampleRate = safeSampleRate
        let baseCapacities = AudioCoreDeepSpaceFDNTail.computeBaseCapacities(forSampleRate: safeSampleRate)
        baseCapacity = baseCapacities
        let capacities = AudioCoreDeepSpaceFDNTail.capacities(fromBase: baseCapacities)
        lineCapacity = capacities
        lineOffset = AudioCoreDeepSpaceFDNTail.computeOffsets(fromCapacities: capacities)
        lineBuffer = Array(repeating: 0, count: capacities.reduce(0, +))
        writeIndex = Array(repeating: 0, count: AudioCoreDeepSpaceFDNTail.lineCount)
        dampingFilterState = Array(repeating: 0, count: AudioCoreDeepSpaceFDNTail.lineCount)
        resetModulationPhase()
        recomputeLineState()
    }

    // MARK: – Reset
    //
    // Setzt alle Delaypuffer, Schreibzeiger und Filterzustaende zurueck,
    // ohne neu zu allozieren. Dieselbe Eingabefolge nach `reset()`
    // reproduziert denselben Ausgabeverlauf wie eine frische Instanz mit
    // identischen Parametern. S-08c: `modPhase` wird auf dieselben festen
    // Startversaetze wie in `init` zurueckgesetzt -- sonst wuerde `reset()`
    // bei aktiver Modulation keine wirklich frische Instanz mehr
    // reproduzieren.
    //
    // W-03a (Teil 2): `writeIndex` und `dampingFilterState` werden in place
    // genullt statt mit `Array(repeating:count:)` neu aufgebaut. Vorher: 2
    // Heap-Allokationen pro Aufruf. `reset()` wird beim Verdrahten
    // voraussichtlich aus einem Command im Rendercallback ausgeloest und
    // faellt damit unter denselben Hard Stop wie `process(left:right:)`.
    public mutating func reset() {
        for i in lineBuffer.indices { lineBuffer[i] = 0 }
        for i in writeIndex.indices { writeIndex[i] = 0 }
        for i in dampingFilterState.indices { dampingFilterState[i] = 0 }
        resetModulationPhase()
    }

    /// Setzt die Modulationsphase auf die festen Startversaetze zurueck --
    /// elementweise in den EIGENEN Puffer, bewusst nicht als Zuweisung
    /// `modPhase = modulationPhaseOffsets` (W-03a, Teil 3).
    ///
    /// Eine solche Zuweisung kopiert nicht, sie teilt den Puffer der
    /// Konstante. `modPhase` waere danach nicht mehr eindeutig referenziert,
    /// und der naechste Schreibzugriff -- `modPhase[i] += modIncrement[i]`
    /// im ersten `process(left:right:)`-Aufruf nach `init`/`prepare`/`reset`
    /// -- haette eine Copy-on-Write-Kopie im Renderpfad ausgeloest. Gemessen:
    /// genau 1 Heap-Allokation je `reset()`, faellig im Rendercallback statt
    /// im `reset()` selbst; deshalb war sie bisher keiner der beiden
    /// bekannten Faelle. Die Werte sind unveraendert.
    private mutating func resetModulationPhase() {
        for i in modPhase.indices {
            modPhase[i] = AudioCoreDeepSpaceFDNTail.modulationPhaseOffsets[i]
        }
    }

    // MARK: – Kapazitaet/Linienzustand
    //
    // Kapazitaet wird immer fuer den maximal moeglichen `size`-Wert (1.0)
    // bei der aktuellen Sample Rate bemessen, unabhaengig vom aktuellen
    // Parameterwert -- dadurch aendert sich die Puffergroesse nie innerhalb
    // des gueltigen Parameterbereichs, nur bei einer expliziten
    // `prepare(sampleRate:)`.

    // Unveraendert seit vor S-08c (nur der Funktionsname ist neu) -- dient
    // ausschliesslich als Klemm-/Suchgrenze fuer die Linienlaengen-/
    // Primzahlwahl in `recomputeLineState()` (siehe Dateikommentar,
    // Abschnitt "Kapazitaetsreserve"). NICHT die tatsaechlich allozierte
    // Puffergroesse -- die liefert `capacities(fromBase:)`.
    private static func computeBaseCapacities(forSampleRate sampleRate: Double) -> [Int] {
        (0..<lineCount).map { i -> Int in
            let maxMs = maxAverageLengthMs * lengthRatios[i]
            let raw = (Double(maxMs) / 1000.0 * sampleRate).rounded(.up)
            let samples = raw.isFinite ? Int(raw) : 0
            return max(samples + capacityMarginSamples, 16)
        }
    }

    // Tatsaechliche Pufferkapazitaet (S-08c): `baseCapacity` plus feste
    // Modulationsreserve (Modulationshub plus ein Interpolations-Tap).
    private static func capacities(fromBase base: [Int]) -> [Int] {
        base.map { $0 + modulationCapacityReserve }
    }

    // Praefixsumme ueber `capacities`: fester Start-Offset je Linie
    // innerhalb des flachen `lineBuffer` (S-08b-fix, siehe Dateikommentar).
    private static func computeOffsets(fromCapacities capacities: [Int]) -> [Int] {
        var offsets = [Int](repeating: 0, count: capacities.count)
        var running = 0
        for i in 0..<capacities.count {
            offsets[i] = running
            running += capacities[i]
        }
        return offsets
    }

    private mutating func recomputeLineState() {
        let averageMs = AudioCoreDeepSpaceFDNTail.minAverageLengthMs
            + parameters.size * (AudioCoreDeepSpaceFDNTail.maxAverageLengthMs - AudioCoreDeepSpaceFDNTail.minAverageLengthMs)

        for i in 0..<AudioCoreDeepSpaceFDNTail.lineCount {
            let targetMs = averageMs * AudioCoreDeepSpaceFDNTail.lengthRatios[i]
            // S-08c: `baseCapacity[i] - 1`, NICHT `lineCapacity[i] - 1` --
            // haelt diese Klemm-/Suchgrenze identisch zum Vor-S-08c-Stand,
            // unabhaengig von der neuen Modulationsreserve in
            // `lineCapacity` (siehe Dateikommentar, "Kapazitaetsreserve").
            let maxAllowed = baseCapacity[i] - 1
            let rawSamples = (Double(targetMs) / 1000.0 * sampleRate).rounded()
            let scaledSamples = rawSamples.isFinite ? rawSamples : 0
            let boundedTargetDouble = max(0.0, min(scaledSamples, Double(maxAllowed)))
            let boundedTarget = max(1, Int(boundedTargetDouble))

            // `usedCount: i` -- ausgeschlossen sind exakt die Laengen der
            // bereits vergebenen Linien `0..<i`, in genau der Reihenfolge, in
            // der das fruehere `Set<Int>` sie aufgenommen hat. Die Reihenfolge
            // bestimmt die Primzahlwahl (siehe `nearestPrime`), deshalb wird
            // hier unveraendert aufsteigend ueber die Linien iteriert.
            let prime = AudioCoreDeepSpaceFDNTail.nearestPrime(
                to: boundedTarget, maxAllowed: maxAllowed,
                excluding: usedPrimeScratch, usedCount: i
            )
            let length = max(1, min(prime, maxAllowed))
            lineLengthSamples[i] = length
            usedPrimeScratch[i] = length
        }

        let rt60 = AudioCoreDeepSpaceFDNTail.rt60Seconds(forDecay: parameters.decay)
        for i in 0..<AudioCoreDeepSpaceFDNTail.lineCount {
            let lineSeconds = Double(lineLengthSamples[i]) / sampleRate
            let exponent = -3.0 * lineSeconds / Double(rt60)
            let rawGain = pow(10.0, exponent)
            let gain = rawGain.isFinite ? Float(max(0.0, min(rawGain, Double(AudioCoreDeepSpaceFDNTail.maxLineGain)))) : 0
            lineGain[i] = gain
        }

        let rawCoefficient = parameters.damping * AudioCoreDeepSpaceFDNTail.maxDampingCoefficient
        dampingCoefficient = rawCoefficient.isFinite
            ? max(0.0, min(rawCoefficient, AudioCoreDeepSpaceFDNTail.maxDampingCoefficient))
            : 0

        recomputeModulationState()
    }

    // MARK: – S-08c: Modulationszustand (Kontrollrate)
    //
    // Leitet aus `parameters.modulationDepth`/`modulationRate` die je Linie
    // gueltige Modulationstiefe in Samples und den Phasenzuwachs pro Sample
    // ab. Laeuft ausschliesslich hier (Kontrollrate, bei `init`/
    // `prepare(sampleRate:)`/`setParameters(_:)`), nie in
    // `process(left:right:)`. `lineLengthSamples` ist an dieser Stelle
    // bereits final (oben in derselben Funktion berechnet).
    private mutating func recomputeModulationState() {
        let depthUnit = parameters.modulationDepth.isFinite
            ? max(0.0, min(parameters.modulationDepth, 1.0)) : 0
        let requestedDepth = depthUnit * AudioCoreDeepSpaceFDNTail.maxModulationDepthSamples

        let rateUnit = parameters.modulationRate.isFinite
            ? max(0.0, min(parameters.modulationRate, 1.0)) : 0
        let baseRateHz = AudioCoreDeepSpaceFDNTail.minModulationRateHz
            + rateUnit * (AudioCoreDeepSpaceFDNTail.maxModulationRateHz - AudioCoreDeepSpaceFDNTail.minModulationRateHz)

        for i in 0..<AudioCoreDeepSpaceFDNTail.lineCount {
            // Deckelt den Hub zusaetzlich auf `lineLengthSamples[i] - 1`:
            // verhindert eine negative effektive Delayzeit
            // (`lineLengthSamples[i] - modDepthSamples[i]`) bei sehr kurzen
            // Linien, z. B. bei extrem niedrigen Sample Raten, wo bereits
            // die Basislaenge nur 1 Sample betragen kann. Fuer diese Linien
            // ist die Modulation dann faktisch (deterministisch) inaktiv.
            let perLineCeiling = max(0.0, Float(lineLengthSamples[i] - 1))
            modDepthSamples[i] = min(requestedDepth, perLineCeiling)

            let rateHz = baseRateHz * AudioCoreDeepSpaceFDNTail.modulationRateMultipliers[i]
            let increment = Double(rateHz) / sampleRate
            modIncrement[i] = increment.isFinite ? increment : 0
        }
    }

    /// Lineare Interpolation zwischen zwei Nachbar-Taps -- Konvexkombination
    /// (`fraction` geklemmt auf `[0, 1]`), siehe Dateikommentar fuer die
    /// daraus folgende Amplitudenschranke/Stabilitaetsbegruendung. Einzige
    /// Implementierung dieser Formel -- `process(left:right:)` ruft
    /// ausschliesslich diese Funktion auf, keine Logikduplikation.
    static func linearInterpolate(_ a: Float, _ b: Float, fraction: Float) -> Float {
        let f = fraction.isFinite ? max(0.0, min(fraction, 1.0)) : 0
        let result = a + (b - a) * f
        return result.isFinite ? result : 0
    }

    private static func rt60Seconds(forDecay decay: Float) -> Float {
        let d = decay.isFinite ? max(0.0, min(decay, 1.0)) : 0
        let minRT60 = AudioCoreDeepSpaceFDNParameters.minRT60Seconds
        let maxRT60 = AudioCoreDeepSpaceFDNParameters.maxRT60Seconds
        let value = minRT60 * powf(maxRT60 / minRT60, d)
        return value.isFinite ? value : minRT60
    }

    // MARK: – Primzahlsuche
    //
    // Deterministisch, nur bei Init/Prepare/Parameteraenderung aufgerufen
    // (Kontrollrate, nicht in `process(left:right:)`). Sucht symmetrisch um
    // `target` nach der naechstgelegenen, noch nicht in `used` enthaltenen
    // Primzahl <= `maxAllowed` -- die Obergrenze schuetzt die feste
    // Pufferkapazitaet, die im Wesentlichen unbegrenzte Abwaertssuche findet
    // dank dichter Primzahlluecken praktisch immer sofort einen Treffer.

    private static func isPrime(_ n: Int) -> Bool {
        guard n >= 2 else { return false }
        if n == 2 { return true }
        if n % 2 == 0 { return false }
        var i = 3
        while i * i <= n {
            if n % i == 0 { return false }
            i += 2
        }
        return true
    }

    /// Lineare Suche in der Ausschlussliste. Ersetzt `Set<Int>.contains` (W-03a,
    /// Teil 1): geprueft werden hoechstens `lineCount` = 8 `Int`-Werte in einem
    /// zusammenhaengenden Puffer, was ohne Hashing und ohne Indirektion
    /// auskommt und in dieser Groessenordnung schneller ist als ein Set.
    ///
    /// Gleichwertig zum vorherigen Set, weil `contains` nur nach ENTHALTENSEIN
    /// fragt: Reihenfolge und Vielfachheit sind fuer das Ergebnis unerheblich.
    /// Ein Duplikat, das ein Set geschluckt haette (moeglich nur im
    /// entarteten Fall `maxAllowed < 2`, wo mehrere Linien auf dieselbe
    /// geklemmte Laenge fallen), belegt hier lediglich einen weiteren der acht
    /// Plaetze -- die Antwort von `contains` bleibt dieselbe. Der Puffer kann
    /// nicht ueberlaufen: pro `recomputeLineState()`-Durchlauf wird genau ein
    /// Eintrag je Linie geschrieben.
    private static func contains(_ value: Int, in used: [Int], usedCount: Int) -> Bool {
        var i = 0
        while i < usedCount {
            if used[i] == value { return true }
            i += 1
        }
        return false
    }

    private static func nearestPrime(to target: Int, maxAllowed: Int,
                                     excluding used: [Int], usedCount: Int) -> Int {
        let start = max(2, min(target, maxAllowed))

        if start >= 2, isPrime(start), !contains(start, in: used, usedCount: usedCount) { return start }

        for offset in 1...maxPrimeSearchOffset {
            let lower = start - offset
            if lower >= 2, isPrime(lower), !contains(lower, in: used, usedCount: usedCount) { return lower }

            let upper = start + offset
            if upper <= maxAllowed, isPrime(upper), !contains(upper, in: used, usedCount: usedCount) { return upper }
        }

        // Praktisch unerreichbar (Primzahlluecken sind fuer die hier
        // vorkommenden Groessenordnungen winzig) -- deterministischer
        // Fallback innerhalb der Kapazitaetsgrenze, keine Endlosschleife.
        return max(2, min(start, maxAllowed))
    }

    // MARK: – DSP-Render
    //
    // Ein Sample-Schritt: liest acht Delaylinien, mischt sie zu Stereo-
    // Ausgang, daempft/gaint sie je Linie, verteilt sie ueber die Hadamard-
    // Matrix, injiziert den Eingang und schreibt zurueck. Keine
    // Array-Allokation mehr (S-08b-fix, Finding S-08b-01): `delayedScratch`/
    // `dampedScratch`/`matrixScratch` sind feste, bei `init`/
    // `prepare(sampleRate:)` angelegte Puffer, `lineBuffer` ist ein flacher
    // Puffer mit festem Offset je Linie. Kein Lock, keine Dispatch-/Task-/
    // Actor-Nutzung, kein `print`.
    //
    // S-08c: bei `parameters.modulationDepth == 0` (Default) laeuft der
    // Lesepfad UNVERAENDERT wie vor S-08c -- derselbe Code, keine
    // Gleitkomma-Rechenkette dazwischen (Bit-Identitaet zu `01085ba`, siehe
    // Dateikommentar). Der Phasenfortschritt (letzte Zeile der Schleife)
    // laeuft dagegen immer, unabhaengig von `modulationDepth` -- so bleibt
    // der Modulationszustand deterministisch fortlaufend und ein spaeteres
    // Aktivieren startet nicht ueberraschend bei Phase 0.
    public mutating func process(left: Float, right: Float) -> (left: Float, right: Float) {
        let inputLeft = left.isFinite ? left : 0
        let inputRight = right.isFinite ? right : 0
        let monoInput = (inputLeft + inputRight) * 0.5

        let modulationActive = parameters.modulationDepth > 0

        for i in 0..<AudioCoreDeepSpaceFDNTail.lineCount {
            let capacity = lineCapacity[i]

            if modulationActive {
                let modSignal = sinf(2.0 * Float.pi * Float(modPhase[i]))
                let effectiveDelay = Float(lineLengthSamples[i]) + modDepthSamples[i] * modSignal
                let flooredDelay = effectiveDelay.isFinite ? floor(effectiveDelay) : Float(lineLengthSamples[i])
                let frac = effectiveDelay.isFinite ? effectiveDelay - flooredDelay : 0
                let delaySamples = Int(flooredDelay)

                let readIndexA = (((writeIndex[i] - delaySamples) % capacity) + capacity) % capacity
                let readIndexB = (((writeIndex[i] - delaySamples - 1) % capacity) + capacity) % capacity
                let tapA = lineBuffer[lineOffset[i] + readIndexA]
                let tapB = lineBuffer[lineOffset[i] + readIndexB]
                delayedScratch[i] = AudioCoreDeepSpaceFDNTail.linearInterpolate(tapA, tapB, fraction: frac)
            } else {
                let readIndex = (writeIndex[i] - lineLengthSamples[i] + capacity) % capacity
                delayedScratch[i] = lineBuffer[lineOffset[i] + readIndex]
            }

            modPhase[i] += modIncrement[i]
            if modPhase[i] >= 1.0 { modPhase[i] -= 1.0 }
            if !modPhase[i].isFinite { modPhase[i] = AudioCoreDeepSpaceFDNTail.modulationPhaseOffsets[i] }
        }

        var outLeft: Float = 0
        var outRight: Float = 0
        for i in 0..<AudioCoreDeepSpaceFDNTail.lineCount {
            outLeft += delayedScratch[i] * outputLeftWeights[i]
            outRight += delayedScratch[i] * outputRightWeights[i]
        }
        outLeft *= AudioCoreDeepSpaceFDNTail.outputGain
        outRight *= AudioCoreDeepSpaceFDNTail.outputGain

        for i in 0..<AudioCoreDeepSpaceFDNTail.lineCount {
            let x = delayedScratch[i]
            var filtered = (1.0 - dampingCoefficient) * x + dampingCoefficient * dampingFilterState[i]
            if !filtered.isFinite { filtered = 0 }
            dampingFilterState[i] = filtered
            dampedScratch[i] = filtered * lineGain[i]
        }

        AudioCoreDeepSpaceFDNMatrix.apply(dampedScratch, into: &matrixScratch)

        for i in 0..<AudioCoreDeepSpaceFDNTail.lineCount {
            var inject = matrixScratch[i] + inputWeights[i] * monoInput
            if !inject.isFinite { inject = 0 }
            let capacity = lineCapacity[i]
            lineBuffer[lineOffset[i] + writeIndex[i]] = inject
            writeIndex[i] = (writeIndex[i] + 1) % capacity
        }

        let safeLeft = outLeft.isFinite ? outLeft : 0
        let safeRight = outRight.isFinite ? outRight : 0
        return (safeLeft, safeRight)
    }
}
