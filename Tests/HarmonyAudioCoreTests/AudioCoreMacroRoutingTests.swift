import XCTest
@testable import HarmonyAudioCore

// MARK: – AudioCoreMacroRoutingTests
//
// W-05 (`.agent_handoff/latest_codex.md`, Runde 074), Teil 1 und Teil 4.
//
// Geprueft wird ausdruecklich die PRODUKTIVE Matrix
// (`AudioCoreAtmosphericVoiceParameters.defaultModulationMatrix`), nicht eine
// im Test gebaute. `AudioCoreAtmosphericVoiceTests` weist bereits nach, dass
// jedes der sieben Ziele grundsaetzlich wirkt — das beweist aber nichts
// darueber, ob im Produkt eine Route dorthin fuehrt. Genau diese Luecke
// schliesst diese Datei: bis Runde 073 waren die Makros nirgends verdrahtet,
// und ein Test mit selbstgebauter Matrix haette das nicht gezeigt.
//
//  1. jedes der vier Makros bewegt den Klang ueber die Default-Matrix
//  2. Gate 7: `macros == .defaults` klingt bit-identisch zu einer Matrix ohne
//     Makrorouten — der Zustand vor dieser Runde
//  3. Gate 3: ein 7-Bit-Reglerschwenk erzeugt keine Sprunggroesse, die ueber
//     der eines ungeglaetteten Verlaufs liegt (mit Positivkontrolle)

final class AudioCoreMacroRoutingTests: XCTestCase {

    // MARK: – Hilfen

    private func render(_ voice: inout AudioCoreAtmosphericVoice, frames: Int) -> (l: [Float], r: [Float]) {
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        _ = left.withUnsafeMutableBufferPointer { lb in
            _ = right.withUnsafeMutableBufferPointer { rb in
                voice.render(intoL: lb.baseAddress!, intoR: rb.baseAddress!, frameCount: frames)
            }
        }
        return (left, right)
    }

    private func makeVoice(_ parameters: AudioCoreAtmosphericVoiceParameters,
                           sampleRate: Double = 48_000) -> AudioCoreAtmosphericVoice {
        var voice = AudioCoreAtmosphericVoice(sampleRate: sampleRate)
        voice.configure(note: 60, velocity: 100, sampleRate: sampleRate,
                        parameters: parameters, activationOrder: 7)
        return voice
    }

    private func differenceRMS(_ a: [Float], _ b: [Float], from index: Int) -> Float {
        precondition(a.count == b.count)
        var sum: Double = 0
        var count = 0
        for i in index..<a.count {
            let d = Double(a[i]) - Double(b[i])
            sum += d * d
            count += 1
        }
        guard count > 0 else { return 0 }
        return Float((sum / Double(count)).squareRoot())
    }

    /// Groesste Unstetigkeit, getrennt nach "liegt genau auf einer
    /// Parameteraenderung" und "liegt dazwischen".
    ///
    /// Aufbau wie in S-08c (`AudioCoreAtmosphericVoiceTests
    /// .test_controlRateModulation_producesNoAudibleSteps`): das Signal wird
    /// mit sich selbst verglichen, nicht mit einem separat gerenderten
    /// Referenzton. Ein Vergleich gegen einen "stehenden Ton" waere hier
    /// wertlos, weil eine Filteraenderung die Flankensteilheit des GANZEN
    /// Signals mitverschiebt.
    ///
    /// Gemessen wird die erste Differenz. Eine zweite Differenz waere hier
    /// ausdruecklich FALSCH, obwohl sie als Unstetigkeitsmass naeherliegt:
    /// `x[i] - 2x[i-1] + x[i-2]` greift ueber drei Samples und sieht eine
    /// Kante zwischen `i-1` und `i` deshalb an ZWEI Indizes. Der zweite davon
    /// faellt in "dazwischen" und hebt den Vergleichswert exakt auf
    /// Kantenhoehe — der Detektor kann dann nichts mehr trennen und meldet
    /// gruen, ohne zu messen (empirisch: innen 0,042 gegen Grenze 0,041).
    /// Dass die erste Differenz trennt, weist `test_positiveControl_...` nach.
    ///
    /// Damit die Eigensteilheit der Wellenform den Vergleich nicht dominiert,
    /// laeuft der Aufbau auf Note 24 (~32,7 Hz): dort liegt die groesste
    /// Sample-zu-Sample-Differenz des unveraenderten Klangs bei 0,008,
    /// waehrend eine ungeglaettete Kante rund 0,03 erzeugt (beides gemessen).
    /// Bei Note 60 waeren es 0,079 gegen 0,03 — kein Detektor mehr.
    private func stepsAtAndBetween(_ samples: [Float],
                                    boundaryEvery: Int,
                                    skipFirst: Int) -> (atBoundary: Float, inside: Float) {
        var atBoundary: Float = 0
        var inside: Float = 0
        for index in skipFirst..<samples.count {
            let delta = abs(samples[index] - samples[index - 1])
            if index % boundaryEvery == 0 {
                atBoundary = max(atBoundary, delta)
            } else {
                inside = max(inside, delta)
            }
        }
        return (atBoundary, inside)
    }

    /// Grobes Helligkeitsmass: mittlere Sample-zu-Sample-Aenderung im
    /// Verhaeltnis zum Pegel. Steigt mit dem Hochtonanteil und ist damit
    /// unempfindlich gegen die Pegelanhebung, die eine Filterresonanz auf der
    /// Grundwelle erzeugt.
    private func brightness(_ samples: ArraySlice<Float>) -> Double {
        var diffEnergy: Double = 0
        var energy: Double = 0
        var previous = Double(samples.first ?? 0)
        for value in samples.dropFirst() {
            let current = Double(value)
            diffEnergy += (current - previous) * (current - previous)
            energy += current * current
            previous = current
        }
        guard energy > 0 else { return 0 }
        return (diffEnergy / energy).squareRoot()
    }

    /// Der Stand VOR W-05: dieselbe Matrix ohne die vier Makrorouten.
    private static let matrixWithoutMacroRoutes = AudioCoreModulationMatrix(routes: [
        AudioCoreModulationRoute(source: .lfo(.lfo1), target: .morphPosition, amount: 0.12),
        AudioCoreModulationRoute(source: .lfo(.lfo2), target: .filterCutoff, amount: 0.08)
    ])

    private func parameters(macros: AudioCoreMacroValues) -> AudioCoreAtmosphericVoiceParameters {
        var p = AudioCoreAtmosphericVoiceParameters.defaults
        p.macros = macros
        return p
    }

    // MARK: – 1. Jedes Makro bewegt den Klang ueber die Default-Matrix

    /// Die vier Makros werden einzeln von 0 auf 1 gedreht; jedes muss den
    /// gerenderten Klang messbar veraendern. Faellt eine Route weg, faellt
    /// genau ein Fall dieses Tests.
    func test_defaultMatrix_everyMacroChangesTheSound() {
        let neutral = parameters(macros: .defaults)
        var neutralVoice = makeVoice(neutral)
        let reference = render(&neutralVoice, frames: 24_000).l

        let cases: [(AudioCoreMacroID, AudioCoreMacroValues)] = [
            (.motion, AudioCoreMacroValues(motion: 1.0)),
            (.color,  AudioCoreMacroValues(color: 1.0)),
            (.space,  AudioCoreMacroValues(space: 1.0)),
            (.focus,  AudioCoreMacroValues(focus: 1.0))
        ]

        for (id, macros) in cases {
            var voice = makeVoice(parameters(macros: macros))
            let moved = render(&voice, frames: 24_000).l

            if id == .space {
                // Sonderfall: `spaceSend` klingt nicht IN der Stimme, sondern
                // wird nur nach aussen sichtbar gemacht (W-01/W-03c). Das
                // Trockensignal muss deshalb unveraendert bleiben — und der
                // Sendpegel sich bewegen.
                XCTAssertEqual(differenceRMS(reference, moved, from: 0), 0,
                               "space darf das Trockensignal der Stimme nicht veraendern")
                XCTAssertGreaterThan(voice.spaceSendLevel, neutralVoice.spaceSendLevel + 0.3,
                                     "space muss den Sendpegel deutlich anheben")
            } else {
                XCTAssertGreaterThan(differenceRMS(reference, moved, from: 12_000), 0.001,
                                     "Makro \(id) hat ueber die Default-Matrix keine hoerbare Wirkung")
            }
        }
    }

    /// Die Richtung von `color` ist bewusst negativ (Begruendung an der
    /// Matrix). Dieser Test pinnt sie, damit ein spaeterer Vorzeichenwechsel
    /// eine bewusste Entscheidung bleibt und kein Versehen.
    func test_colorMacro_reducesFilterCutoff() {
        var bright = AudioCoreAtmosphericVoiceParameters.defaults
        bright.filterCutoff = 1.0
        bright.macros = .defaults

        var dark = bright
        dark.macros = AudioCoreMacroValues(color: 1.0)

        var brightVoice = makeVoice(bright)
        var darkVoice = makeVoice(dark)

        let a = render(&brightVoice, frames: 24_000).l
        let b = render(&darkVoice, frames: 24_000).l

        // Bewusst NICHT ueber die Gesamtenergie gemessen: die Resonanz des
        // SVF hebt bei geschlossenem Filter die Grundwelle an (Q ~ 1,5), die
        // Energie STEIGT dabei sogar. Gemessen wird deshalb der
        // Hochtonanteil.
        XCTAssertLessThan(brightness(b[12_000...]), brightness(a[12_000...]) * 0.9,
                          "color hoch muss den Filter schliessen, nicht oeffnen")
    }

    // MARK: – 2. Gate 7: bit-identisch ohne CC-Eingang

    /// Ohne CC-Eingang stehen alle vier Makros auf 0. Dann muss die um vier
    /// Routen erweiterte Matrix bitgenau dasselbe liefern wie die alte.
    func test_macrosAtDefault_areBitIdenticalToMatrixWithoutMacroRoutes() {
        var before = AudioCoreAtmosphericVoiceParameters.defaults
        before.modulationMatrix = Self.matrixWithoutMacroRoutes

        var beforeVoice = makeVoice(before)
        var afterVoice = makeVoice(parameters(macros: .defaults))

        let a = render(&beforeVoice, frames: 48_000)
        let b = render(&afterVoice, frames: 48_000)

        for i in 0..<a.l.count where a.l[i].bitPattern != b.l[i].bitPattern {
            XCTFail("Makrorouten veraendern den Klang bei macros == .defaults, Index \(i)")
            return
        }
        for i in 0..<a.r.count where a.r[i].bitPattern != b.r[i].bitPattern {
            XCTFail("Makrorouten veraendern den rechten Kanal bei macros == .defaults, Index \(i)")
            return
        }
        XCTAssertEqual(beforeVoice.spaceSendLevel.bitPattern, afterVoice.spaceSendLevel.bitPattern)
    }

    /// Der Beitrag `0 * amount` ist bei negativem Amount `-0.0`. Dass das die
    /// Zielsumme nicht kippt, ist die Voraussetzung des Tests darueber und
    /// wird hier direkt an der Matrix geprueft.
    func test_negativeAmountWithZeroMacro_doesNotProduceNegativeZeroTarget() {
        let matrix = AudioCoreAtmosphericVoiceParameters.defaultModulationMatrix
        let targets = matrix.evaluate(sources: AudioCoreModulationSourceValues(macros: .defaults))

        XCTAssertEqual(targets.filterCutoff.bitPattern, Float(0).bitPattern,
                       "negativer Amount x Makro 0 darf kein -0.0 hinterlassen")
        XCTAssertEqual(targets.morphPosition.bitPattern, Float(0).bitPattern)
        XCTAssertEqual(targets.mixDepth.bitPattern, Float(0).bitPattern)
        XCTAssertEqual(targets.spaceSend.bitPattern, Float(0).bitPattern)
    }

    // MARK: – 3. Gate 3: keine hoerbaren Stufen beim Reglerschwenk

    // Geprueft wird an `focus -> mixDepth`, nicht an `color -> filterCutoff`.
    //
    // Grund, und er ist wichtig fuer die Aussagekraft: ein Cutoff-Wechsel kann
    // per Konstruktion GAR KEINE Kante erster Ordnung erzeugen. Der SVF
    // behaelt bei einem Koeffizientenwechsel seinen Zustand, die Stufigkeit
    // ist zweiter Ordnung (so dokumentiert in `AudioCoreAtmosphericVoice`, und
    // hier empirisch bestaetigt: selbst mit `smoothingTimeMs = 0` bleiben die
    // Spruenge an den Parameterwechseln UNTER denen dazwischen). Ein Test an
    // diesem Ziel haette also gruen gemeldet, ohne etwas zu messen — genau die
    // Sorte gruener Test, die nichts beweist.
    //
    // `mixDepth` wirkt dagegen multiplikativ auf den Sample-Wert: ein
    // ungeglaetteter Sprung ist dort sofort eine Kante. Damit laesst sich
    // zeigen, dass der Detektor ueberhaupt anschlaegt.

    private func macroSweepParameters(smoothingTimeMs: Float) -> AudioCoreAtmosphericVoiceParameters {
        // Tiefe Note, keine Textur: die Wellenform selbst hat dann kleine
        // Sample-zu-Sample-Deltas, eine Parameterstufe steche heraus.
        //
        // Filter voll offen: ein Tiefpass ist selbst ein Glaetter und
        // verkleinert jede Kante am Ausgang. Mit dem Default-Cutoff 0,85
        // (~7 kHz) daempft er einen ungeglaetteten `mixDepth`-Sprung von 0,5
        // bereits auf rund ein Fuenftel — gemessen, und genug, damit die
        // Positivkontrolle nicht mehr anschlaegt. Der Filter darf hier also
        // nicht mitmessen.
        var p = AudioCoreAtmosphericVoiceParameters.defaults
        p.textureLevel = 0
        p.filterCutoff = 1.0
        p.smoothingTimeMs = smoothingTimeMs
        return p
    }

    private func renderMacroSweep(smoothingTimeMs: Float,
                                   stepCount: Int,
                                   framesPerStep: Int,
                                   matrix: AudioCoreModulationMatrix
                                     = AudioCoreAtmosphericVoiceParameters.defaultModulationMatrix,
                                   focus: (Int) -> Float) -> [Float] {
        var base = macroSweepParameters(smoothingTimeMs: smoothingTimeMs)
        base.modulationMatrix = matrix
        var voice = AudioCoreAtmosphericVoice(sampleRate: 48_000)
        // Note 24 (~32,7 Hz): die Wellenform selbst hat dann eine sehr kleine
        // Kruemmung. Bei Note 36 lag sie mit rund 0,046 bereits auf Hoehe der
        // Kante, die ein ungeglaetteter Sprung erzeugt — gemessen, und der
        // Grund fuer diese Wahl.
        voice.configure(note: 24, velocity: 127, sampleRate: 48_000,
                        parameters: base, activationOrder: 7)

        var output: [Float] = []
        output.reserveCapacity(stepCount * framesPerStep)
        for step in 0..<stepCount {
            var stepParameters = base
            stepParameters.macros = AudioCoreMacroValues(focus: focus(step))
            voice.setParameters(stepParameters)
            output.append(contentsOf: render(&voice, frames: framesPerStep).l)
        }
        return output
    }

    /// Positivkontrolle fuer die beiden Tests darunter: derselbe Detektor,
    /// derselbe Aufbau, aber ein ungeglaetteter Extremsprung (Makro springt
    /// alle 20 ms zwischen 0 und 1). Schlaegt er hier nicht an, misst er auch
    /// in den beiden Messungen nichts.
    ///
    /// Die Matrix ist hier bewusst auf die eine Makroroute reduziert. Mit der
    /// vollen Default-Matrix waeren bei `smoothingTimeMs = 0` auch die beiden
    /// LFO-Routen ungeglaettet und wuerden alle 32 Samples (Kontrollrate)
    /// eigene Kanten erzeugen — die landen in "dazwischen" und heben den
    /// Vergleichswert genau so weit an, dass der Detektor nichts mehr trennen
    /// kann (gemessen: innen 0,040 gegen Grenze 0,024). Die Positivkontrolle
    /// prueft den DETEKTOR; die produktive Matrix pruefen die Messungen
    /// darunter.
    func test_positiveControl_unsmoothedExtremeJumpIsDetected() {
        let framesPerStep = 960
        let onlyFocusRoute = AudioCoreModulationMatrix(routes: [
            AudioCoreModulationRoute(source: .macro(.focus), target: .mixDepth, amount: 0.50)
        ])
        let steps = stepsAtAndBetween(
            renderMacroSweep(smoothingTimeMs: 0.0, stepCount: 40, framesPerStep: framesPerStep,
                             matrix: onlyFocusRoute) {
                $0.isMultiple(of: 2) ? 0.0 : 1.0
            },
            boundaryEvery: framesPerStep, skipFirst: 4_800)

        XCTAssertGreaterThan(steps.inside, 0, "Testaufbau muss ein Signal liefern")
        XCTAssertGreaterThan(steps.atBoundary, steps.inside * 1.5,
                             "Der Sprungdetektor schlaegt bei einem ungeglaetteten Extremsprung "
                             + "nicht an (Grenze \(steps.atBoundary), innen \(steps.inside))")
    }

    /// Messung 1: `focus` in 7-Bit-Schritten (128 Stufen) ueber den vollen Weg,
    /// mit der produktiven Glaettung. An den Parameterwechseln darf nichts
    /// herausstechen.
    func test_sevenBitSweep_producesNoStepsAtTheParameterBoundaries() {
        let framesPerStep = 192     // 4 ms bei 48 kHz — 128 Stufen in 0,512 s
        let steps = stepsAtAndBetween(
            renderMacroSweep(smoothingTimeMs: 12.0, stepCount: 128, framesPerStep: framesPerStep) {
                Float($0) / 127.0
            },
            boundaryEvery: framesPerStep, skipFirst: 4_800)

        XCTAssertGreaterThan(steps.inside, 0, "Testaufbau muss ein Signal liefern")
        XCTAssertLessThanOrEqual(steps.atBoundary, steps.inside * 1.5,
                                 "7-Bit-Schwenk erzeugt an den Parameterwechseln systematisch "
                                 + "groessere Spruenge als dazwischen "
                                 + "(Grenze \(steps.atBoundary), innen \(steps.inside))")
    }

    /// Messung 2: der grobere Takt, mit dem der `MIDIMacroCoalescer` die
    /// CC-Flut buendelt — 20-ms-Spruenge statt 7-Bit-Schritten. 0,05 pro
    /// Schritt entspricht einem vollen Reglerweg in 0,4 s und ist damit
    /// schneller als jeder reale Schwenk.
    func test_coalescedTwentyMillisecondJumps_produceNoStepsAtTheParameterBoundaries() {
        let framesPerTick = 960     // 20 ms bei 48 kHz
        let steps = stepsAtAndBetween(
            renderMacroSweep(smoothingTimeMs: 12.0, stepCount: 40, framesPerStep: framesPerTick) {
                min(Float($0) * 0.05, 1.0)
            },
            boundaryEvery: framesPerTick, skipFirst: 4_800)

        XCTAssertGreaterThan(steps.inside, 0, "Testaufbau muss ein Signal liefern")
        XCTAssertLessThanOrEqual(steps.atBoundary, steps.inside * 1.5,
                                 "20-ms-Stufen des Coalescers sind im Signal sichtbar "
                                 + "(Grenze \(steps.atBoundary), innen \(steps.inside))")
    }
}
