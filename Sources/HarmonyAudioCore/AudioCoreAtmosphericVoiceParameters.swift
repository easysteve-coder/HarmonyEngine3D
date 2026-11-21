// MARK: – AudioCoreAtmosphericVoiceParameters
//
// W-01 (`.agent_handoff/latest_codex.md`, Runde 066): vollstaendiger
// Parametersatz einer `AudioCoreAtmosphericVoice`
// (`SYNTH_ARCHITECTURE_PLAN.md`, Abschnitte 6.1-6.5). Reiner Value-Typ:
// Klangkonfiguration, Huellen-/LFO-Profile, Modulationsmatrix und die vier
// Performance-Makros in einem Snapshot, den die Stimme bei Note-On oder ueber
// `setParameters(_:)` uebernimmt.
//
// Klemmvertrag (S-08a-01-Lehre, seit Runde 059 Pflicht fuer jeden neuen Typ):
// ALLE Grenzen liegen ausschliesslich im Initialisierer. Die Felder sind
// bewusst `public var`, damit ein Aufrufer einen Patch bequem punktuell
// aendern kann; `AudioCoreAtmosphericVoice.setParameters(_:)` baut den
// uebernommenen Satz deshalb ueber genau diesen Initialisierer neu auf, statt
// die Werte roh zu uebernehmen. Auch die verschachtelten Huellen-/LFO-
// Parameter werden dabei durch ihre eigenen Initialisierer neu gebaut, weil
// auch sie `public var`-Felder haben und eine Post-Init-Mutation sonst am
// Klemmpfad vorbeiliefe.
//
// Ausnahme mit Begruendung: `modulationMatrix` wird NICHT neu gebaut. Ein
// `AudioCoreModulationMatrix` ist nach seiner Konstruktion unveraenderlich
// (`public let routes`), auf 16 Routen gekuerzt und mit geklemmten Amounts
// gebaut; zusaetzlich klemmt `evaluate(sources:)` jedes Ergebnis erneut auf
// `[-1, 1]` und ueberspringt nicht-endliche Beitraege. Ein Neubau waere
// reine Redundanz und wuerde eine Array-Allokation in `setParameters(_:)`
// erzeugen — genau das, was der Realtime-Vertrag im Verdrahtungsslice
// (W-03) nicht gebrauchen kann.

public struct AudioCoreAtmosphericVoiceParameters: Sendable, Equatable {

    // MARK: – Technische Sample-Rate-Grenzen
    //
    // Identische Werte wie `AudioCoreDeepSpaceParameters.minSampleRate`/
    // `.maxSampleRate` (S-08b Teil 1 / Runde 064), hier bewusst als eigene
    // Konstanten und nicht per Zugriff auf den `DeepSpace`-Typ: jene Grenzen
    // sind ausdruecklich als "die EINE gemeinsame Stelle fuer die gesamte
    // DeepSpace-Familie" dokumentiert. Eine gemeinsame, familienuebergreifende
    // Ablage waere eine Aenderung an bestehenden, abgenommenen Bausteinen und
    // liegt ausserhalb des W-01-Scopes; sie ist im Ruecklauf als Kandidat fuer
    // eine spaetere Konsolidierung vermerkt.
    //
    // Untergrenze: die Stimme leitet ihre Kontrollrate als
    // `sampleRate / controlBlockSize` ab. Ohne Untergrenze degeneriert diese
    // Rate gegen 0 und der Ein-Schritt-Phasen-Wrap in `AudioCoreLFO` waere
    // nicht mehr korrekt. Obergrenze: schuetzt jede spaetere
    // `Double -> Int`-Konvertierung vor Ueberlauf (verifizierter SIGTRAP in
    // S-08a-02).

    public static let minSampleRate: Double = 100.0
    public static let maxSampleRate: Double = 1_000_000.0

    /// Klemmt eine Sample Rate auf `[minSampleRate, maxSampleRate]`.
    /// Nicht-endliche oder nicht-positive Werte fallen auf 44.100 Hz zurueck.
    public static func safeSampleRate(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 44_100.0 }
        return min(max(value, minSampleRate), maxSampleRate)
    }

    // MARK: – Quellen und Mix

    /// Mixmodus fuer die Interaktion von Quelle A und Quelle B.
    public var mixMode: AudioCoreMixMode

    /// Grundpegel von Quelle A im Mix, `0...1`.
    public var gainA: Float

    /// Basiswert des Modulationsziels `mixDepth`, `0...1`. Bedeutung haengt
    /// am aktiven `mixMode`: bei `.linear` der Pegel von Quelle B, bei
    /// `.ringModulation` die Ringmodulationstiefe, bei `.softPhaseModulation`
    /// die Phasenmodulationstiefe. So bewegt das Ziel in JEDEM Modus den
    /// Mix-/Blend-Anteil und nicht nur im Default-Modus.
    public var mixDepth: Float

    /// Basis-Morphposition beider Morph-Oszillatoren, `0...1`.
    public var morphPosition: Float

    /// Basispegel der Texturquelle, `0...1`.
    public var textureLevel: Float

    /// Farbe der Texturquelle, `0...1` (`0` dunkel, `1` nahe weissem Rauschen).
    public var textureBrightness: Float

    /// Seed der deterministischen Texturquelle. Die Stimme mischt bei Note-On
    /// zusaetzlich ihre `activationOrder` ein, damit gleichzeitig klingende
    /// Stimmen nicht dasselbe Rauschen erzeugen (kohaerente Summierung waere
    /// deutlich lauter als unkorrelierte).
    public var textureSeed: UInt64

    /// Transposition von Quelle B in Halbtoenen, `-24...24`.
    public var sourceBTranspositionSemitones: Double

    /// Feinstimmung von Quelle B in Cent, `-100...100`.
    public var sourceBFineTuneCents: Double

    /// Startphase von Quelle B bei Note-On, gewrapped auf `[0, 1)`.
    public var sourceBPhaseOffset: Double

    // MARK: – Filter und Shaping

    public var filterMode: AudioCoreSVFMode

    /// Basis-Cutoff, `0...1` (logarithmisch 20 Hz...20 kHz, siehe
    /// `AudioCoreStateVariableFilter`).
    public var filterCutoff: Float

    /// Resonanz, `0...1` (Q 0,5...20).
    public var filterResonance: Float

    /// Drive des Waveshapers, `0...1`.
    public var drive: Float

    /// Zusaetzliche Ausgangsverstaerkung des Waveshapers nach der
    /// Pegelkompensation, `0...4`.
    public var waveshaperOutputGain: Float

    /// Ausgangspegel der gesamten Stimme, `0...1`.
    public var outputLevel: Float

    // MARK: – Huellen

    public var ampEnvelope: AudioCoreEnvelopeParameters
    public var modEnvelope: AudioCoreEnvelopeParameters

    /// Basiswert des Modulationsziels `ampEnvelopeDepth`, `0...1`. Skaliert,
    /// wie stark die Amp-Huelle die Ausgangsamplitude bestimmt. Default `1.0`
    /// entspricht voller Wirkung; das Ziel wirkt von dort aus nach unten.
    public var ampEnvelopeDepth: Float

    /// Basiswert des Modulationsziels `modEnvelopeDepth`, `0...1`. Skaliert
    /// den Wert der Mod-Huelle, BEVOR er als Modulationsquelle in die Matrix
    /// geht.
    public var modEnvelopeDepth: Float

    // MARK: – LFOs

    public var lfo1: AudioCoreLFOParameters
    public var lfo2: AudioCoreLFOParameters
    public var lfo3: AudioCoreLFOParameters

    public var lfo1Seed: UInt64
    public var lfo2Seed: UInt64
    public var lfo3Seed: UInt64

    // MARK: – Modulation und Performance

    public var modulationMatrix: AudioCoreModulationMatrix
    public var macros: AudioCoreMacroValues

    /// Basiswert des Modulationsziels `spaceSend`, `0...1`. Die Stimme wendet
    /// diesen Wert NICHT selbst an — sie macht ihn nur ueber
    /// `AudioCoreAtmosphericVoice.spaceSendLevel` nach aussen sichtbar
    /// (Anwendung im Send-Bus ist W-03).
    public var spaceSend: Float

    /// Glaettungszeit aller sieben Modulationsziele in Millisekunden, `>= 0`.
    /// `0` bedeutet ungeglaettet (sofortiger Sprung).
    public var smoothingTimeMs: Float

    // MARK: – Initialisierer (einzige Klemmstelle)

    public init(mixMode: AudioCoreMixMode = .linear,
                gainA: Float = 0.70,
                mixDepth: Float = 0.25,
                morphPosition: Float = 0.35,
                textureLevel: Float = 0.06,
                textureBrightness: Float = 0.35,
                textureSeed: UInt64 = 0x853C_49E6_748F_EA9B,
                sourceBTranspositionSemitones: Double = 0.0,
                sourceBFineTuneCents: Double = -7.0,
                sourceBPhaseOffset: Double = 0.0,
                filterMode: AudioCoreSVFMode = .lowpass,
                filterCutoff: Float = 0.85,
                filterResonance: Float = 0.05,
                drive: Float = 0.0,
                waveshaperOutputGain: Float = 1.0,
                outputLevel: Float = 0.15,
                ampEnvelope: AudioCoreEnvelopeParameters = AudioCoreEnvelopeParameters(attackMs: 12.0,
                                                                                       decayMs: 300.0,
                                                                                       sustainLevel: 0.75,
                                                                                       releaseMs: 400.0),
                modEnvelope: AudioCoreEnvelopeParameters = AudioCoreEnvelopeParameters(attackMs: 40.0,
                                                                                       decayMs: 600.0,
                                                                                       sustainLevel: 0.50,
                                                                                       releaseMs: 600.0),
                ampEnvelopeDepth: Float = 1.0,
                modEnvelopeDepth: Float = 1.0,
                lfo1: AudioCoreLFOParameters = AudioCoreLFOParameters(shape: .sine, frequencyHz: 0.13),
                lfo2: AudioCoreLFOParameters = AudioCoreLFOParameters(shape: .triangle, frequencyHz: 0.07),
                lfo3: AudioCoreLFOParameters = AudioCoreLFOParameters(shape: .smoothedRandom, frequencyHz: 0.25),
                lfo1Seed: UInt64 = 0x2545_F491_4F6C_DD1D,
                lfo2Seed: UInt64 = 0x9E37_79B9_7F4A_7C15,
                lfo3Seed: UInt64 = 0xBF58_476D_1CE4_E5B9,
                modulationMatrix: AudioCoreModulationMatrix = AudioCoreAtmosphericVoiceParameters.defaultModulationMatrix,
                macros: AudioCoreMacroValues = .defaults,
                spaceSend: Float = 0.0,
                smoothingTimeMs: Float = 12.0) {

        self.mixMode = mixMode
        self.gainA = AudioCoreAtmosphericVoiceParameters.clampUnit(gainA, fallback: 0.0)
        self.mixDepth = AudioCoreAtmosphericVoiceParameters.clampUnit(mixDepth, fallback: 0.0)
        self.morphPosition = AudioCoreAtmosphericVoiceParameters.clampUnit(morphPosition, fallback: 0.0)
        self.textureLevel = AudioCoreAtmosphericVoiceParameters.clampUnit(textureLevel, fallback: 0.0)
        self.textureBrightness = AudioCoreAtmosphericVoiceParameters.clampUnit(textureBrightness, fallback: 0.5)
        self.textureSeed = textureSeed

        self.sourceBTranspositionSemitones = AudioCoreAtmosphericVoiceParameters
            .clampRange(sourceBTranspositionSemitones, lower: -24.0, upper: 24.0)
        self.sourceBFineTuneCents = AudioCoreAtmosphericVoiceParameters
            .clampRange(sourceBFineTuneCents, lower: -100.0, upper: 100.0)
        self.sourceBPhaseOffset = AudioCoreAtmosphericVoiceParameters.wrapPhase(sourceBPhaseOffset)

        self.filterMode = filterMode
        self.filterCutoff = AudioCoreAtmosphericVoiceParameters.clampUnit(filterCutoff, fallback: 1.0)
        self.filterResonance = AudioCoreAtmosphericVoiceParameters.clampUnit(filterResonance, fallback: 0.0)
        self.drive = AudioCoreAtmosphericVoiceParameters.clampUnit(drive, fallback: 0.0)
        self.waveshaperOutputGain = AudioCoreAtmosphericVoiceParameters
            .clampRange(waveshaperOutputGain, lower: 0.0, upper: 4.0, fallback: 1.0)
        self.outputLevel = AudioCoreAtmosphericVoiceParameters.clampUnit(outputLevel, fallback: 0.0)

        // Verschachtelte Parametertypen bewusst ueber ihre eigenen
        // Initialisierer neu bauen — sie haben ebenfalls `public var`-Felder.
        self.ampEnvelope = AudioCoreEnvelopeParameters(attackMs: ampEnvelope.attackMs,
                                                       decayMs: ampEnvelope.decayMs,
                                                       sustainLevel: ampEnvelope.sustainLevel,
                                                       releaseMs: ampEnvelope.releaseMs)
        self.modEnvelope = AudioCoreEnvelopeParameters(attackMs: modEnvelope.attackMs,
                                                       decayMs: modEnvelope.decayMs,
                                                       sustainLevel: modEnvelope.sustainLevel,
                                                       releaseMs: modEnvelope.releaseMs)

        self.ampEnvelopeDepth = AudioCoreAtmosphericVoiceParameters.clampUnit(ampEnvelopeDepth, fallback: 1.0)
        self.modEnvelopeDepth = AudioCoreAtmosphericVoiceParameters.clampUnit(modEnvelopeDepth, fallback: 1.0)

        self.lfo1 = AudioCoreLFOParameters(shape: lfo1.shape,
                                            frequencyHz: lfo1.frequencyHz,
                                            smoothingAmount: lfo1.smoothingAmount)
        self.lfo2 = AudioCoreLFOParameters(shape: lfo2.shape,
                                            frequencyHz: lfo2.frequencyHz,
                                            smoothingAmount: lfo2.smoothingAmount)
        self.lfo3 = AudioCoreLFOParameters(shape: lfo3.shape,
                                            frequencyHz: lfo3.frequencyHz,
                                            smoothingAmount: lfo3.smoothingAmount)

        self.lfo1Seed = lfo1Seed
        self.lfo2Seed = lfo2Seed
        self.lfo3Seed = lfo3Seed

        self.modulationMatrix = modulationMatrix
        self.macros = AudioCoreMacroValues(motion: macros.motion,
                                            color: macros.color,
                                            space: macros.space,
                                            focus: macros.focus)
        self.spaceSend = AudioCoreAtmosphericVoiceParameters.clampUnit(spaceSend, fallback: 0.0)
        self.smoothingTimeMs = AudioCoreAtmosphericVoiceParameters.clampNonNegative(smoothingTimeMs, fallback: 12.0)
    }

    // MARK: – Default-Patch
    //
    // Ruhiger, nicht-harscher Startpunkt, KEINE Art-Direction-Entscheidung
    // (Handoff-Vorgabe W-01): moderate Morphposition, wenig Textur, offener
    // Filter, sanfte Huelle, dezente Modulation. Die eigentliche
    // Klanggestaltung macht Stephan spaeter am Controller (W-05).

    public static let defaults = AudioCoreAtmosphericVoiceParameters()

    /// Dezente Default-Modulation: zwei sehr langsame LFO-Routen mit kleinem
    /// Amount plus die vier Makrorouten aus W-05. Bewusst minimal — keine
    /// Presetbank, kein Effekthaschen.
    ///
    /// ── Die vier Makrorouten (W-05, VORLAEUFIG — Stephan-Entscheidung offen) ──
    ///
    /// Ohne diese vier Routen waere ein Makrowert wirkungslos: die Stimme
    /// reicht `parameters.macros` zwar als Modulationsquelle in die Matrix
    /// (`updateControlStep()`), aber eine Quelle ohne Route bewegt nichts.
    ///
    /// **Die Zuordnung ist eine Naeherung, keine Umsetzung von
    /// `SYNTH_ARCHITECTURE_PLAN.md` 6.4.** Die dort genannten Wirkungen —
    /// LFO-Tiefe, Stereo-Breite, Transienten, Dry/Wet — existieren in
    /// `AudioCoreModulationTarget` gar nicht; von den sieben vorhandenen
    /// Zielen entspricht nur `spaceSend` einem Plan-Makro exakt. Zwei
    /// Einschraenkungen, die aus der festen Matrix folgen und hier nicht
    /// stillschweigend umgedeutet werden:
    ///
    ///   1. Ein Makro kann nur einen STATISCHEN Beitrag auf ein Ziel legen.
    ///      "Motion = LFO-Tiefe" waere Quelle x Quelle und kann die Matrix
    ///      nicht; Motion bekommt deshalb den Teil "Morphbewegung".
    ///   2. Alle Makros sind unipolar `0...1` mit Default `0` (Voraussetzung
    ///      fuer die Bit-Identitaet ohne CC-Eingang). Ein Makro kann vom
    ///      Basiswert aus also nur in EINE Richtung wirken; die Richtung
    ///      steckt im Vorzeichen des Amount.
    ///
    /// `color` traegt deshalb ein negatives Vorzeichen: der Kanal-Basiswert
    /// `filterCutoff` ist in `AppSettings.ChannelFXConfig.chordDefaults` 1,0
    /// (voll offen). Ein positiver Amount waere dort vollstaendig
    /// weggeklemmt, das Makro also ein toter Regler. "Color hoch = dunkler"
    /// ist die Folge davon, nicht eine Klangentscheidung — und genau der
    /// Punkt, an dem Stephan nach dem Drehen entscheidet.
    ///
    /// Bit-Identitaet: bei `macros == .defaults` ist jeder Quellwert `0`,
    /// jeder Beitrag damit `±0.0` und die Zielsumme unveraendert. Die vier
    /// Routen stehen bewusst NACH den beiden LFO-Routen, damit auch die
    /// Auswertungsreihenfolge der bestehenden Beitraege gleich bleibt.
    public static let defaultModulationMatrix = AudioCoreModulationMatrix(routes: [
        AudioCoreModulationRoute(source: .lfo(.lfo1), target: .morphPosition, amount: 0.12),
        AudioCoreModulationRoute(source: .lfo(.lfo2), target: .filterCutoff, amount: 0.08),
        // Motion: Morphbewegung (Basis 0,35 → bis 0,80).
        AudioCoreModulationRoute(source: .macro(.motion), target: .morphPosition, amount: 0.45),
        // Color: Filter. Negativ, siehe Begruendung oben.
        AudioCoreModulationRoute(source: .macro(.color), target: .filterCutoff, amount: -0.55),
        // Space: Raumanteil. Einzige 1:1-Entsprechung zum Plan.
        AudioCoreModulationRoute(source: .macro(.space), target: .spaceSend, amount: 0.50),
        // Focus: Balance Quelle A ↔ B (Basis 0,25 → bis 0,75). Deutlichste
        // Abweichung vom Plan — dessen drei Focus-Wirkungen sind keine Ziele.
        AudioCoreModulationRoute(source: .macro(.focus), target: .mixDepth, amount: 0.50)
    ])

    // MARK: – Klemmhilfen

    private static func clampUnit(_ value: Float, fallback: Float) -> Float {
        guard value.isFinite else { return fallback }
        return max(0.0, min(value, 1.0))
    }

    private static func clampNonNegative(_ value: Float, fallback: Float) -> Float {
        guard value.isFinite else { return fallback }
        return max(0.0, value)
    }

    private static func clampRange(_ value: Float, lower: Float, upper: Float, fallback: Float) -> Float {
        guard value.isFinite else { return fallback }
        return max(lower, min(value, upper))
    }

    private static func clampRange(_ value: Double, lower: Double, upper: Double) -> Double {
        guard value.isFinite else { return 0.0 }
        return max(lower, min(value, upper))
    }

    private static func wrapPhase(_ value: Double) -> Double {
        guard value.isFinite else { return 0.0 }
        var wrapped = value.truncatingRemainder(dividingBy: 1.0)
        if wrapped < 0 { wrapped += 1.0 }
        return wrapped
    }
}
