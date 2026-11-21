import Darwin

// MARK: – AudioCoreAtmosphericVoice
//
// W-01 (`.agent_handoff/latest_codex.md`, Runde 066): erste spielbare
// Zusammenschaltung der seit S-04a einzeln gebauten DSP-Bausteine zu einer
// Stimme (`SYNTH_ARCHITECTURE_PLAN.md`, Abschnitte 6.1-6.5). Reine
// Core-Schicht, offline testbar, NOCH NICHT verdrahtet — die Verbindung zu
// `SynthNode`/`AudioEngine`/`AppSettings`/UI ist W-03, die
// DeepSpace-Kette ist W-02, MIDI-Eingang und CC-Mapping sind W-04/W-05.
//
// Signalweg (Reihenfolge ist Handoff-Vorgabe, sie bestimmt den
// Klangcharakter und ist nicht beliebig):
//
//     Quelle A ─┐
//     Quelle B ─┼→ Mixer → Filter (SVF) → Waveshaper → Amp-Huelle → Pan → L/R
//     Textur  ─┘
//
// Modulation laeuft parallel: Mod-Huelle und drei LFOs speisen die
// `AudioCoreModulationMatrix`, deren sieben Ausgaenge auf die Ziele wirken.
//
// ---------------------------------------------------------------------------
// Modulationsrate: Kontrollrate plus Glaettung
// ---------------------------------------------------------------------------
//
// Modulation laeuft auf einer festen internen Kontrollrate
// (`controlBlockSize` = 32 Samples, bei 48 kHz also 1.500 Hz), danach werden
// alle sieben Zielwerte per `AudioCoreParameterSmoother` auf Audiorate
// geglaettet. Begruendung:
//
// 1. Pro Sample waere die Matrixauswertung samt drei LFOs und Mod-Huelle der
//    teuerste Einzelposten der Stimme, ohne hoerbaren Gewinn: die
//    Modulationssignale selbst sind mit hoechstens 200 Hz (LFO-Obergrenze)
//    weit unterhalb der Kontrollrate bandbegrenzt.
// 2. Dass `AudioCoreParameterSmoother` seit S-05b existiert, weist genau auf
//    diesen Weg — Stufen entstehen erst, wenn ein Kontrollratenwert
//    ungeglaettet angewendet wird.
// 3. Die Kontrollperiode haengt bewusst NICHT an `frameCount`, sondern an
//    einem stimmeigenen Zaehler (`controlPhase`). Sonst haette dieselbe
//    Notenfolge je nach Puffergroesse des Aufrufers unterschiedlich
//    geklungen; so liefert ein Render in einem Stueck bit-exakt dasselbe wie
//    derselbe Render in beliebig geschnittenen Teilbloecken
//    (`test_render_isInvariantToBlockSegmentation`).
//
// Die LFOs und die Mod-Huelle laufen deshalb selbst auf Kontrollrate: sie
// werden mit `sampleRate / controlBlockSize` als Sample Rate gebaut, wodurch
// ihre Frequenzen bzw. ihre Zeiten in Millisekunden unveraendert korrekt
// bleiben. Die AMP-Huelle laeuft dagegen auf voller Audiorate — sie formt die
// Amplitude direkt, eine 32-Sample-Treppe waere dort ein hoerbares Knacken.
//
// Der Filter-Cutoff ist der eine Wert, der zwar auf Audiorate geglaettet,
// aber nur auf Kontrollrate ANGEWENDET wird: `AudioCoreStateVariableFilter
// .setParameters(_:)` rechnet `powf` und `tanf`: pro Sample waere das der
// teuerste Posten der ganzen Stimme. Der Filterzustand selbst bleibt bei
// einem Koeffizientenwechsel stetig, die Stufigkeit ist deshalb zweiter
// Ordnung — nachgewiesen in
// `test_controlRateModulation_producesNoAudibleSteps`.
//
// ---------------------------------------------------------------------------
// Realtime-Vertrag
// ---------------------------------------------------------------------------
//
// `render(intoL:intoR:frameCount:)`, `configure(...)`, `setParameters(_:)`,
// `triggerRelease()` und `reset()` allozieren nicht, sperren nicht, nutzen
// keine Dispatch-/Task-/Actor-Ausfuehrung und schreiben nicht (kein `print`).
// Alle Zwischenwerte sind Skalare in Registern; es gibt bewusst kein
// LFO-Array und keine Scratch-Puffer, weil die drei LFO-Slots als drei
// benannte Felder gehalten werden — identisch zur bereits bestehenden
// Modellierung in `AudioCoreModulationSourceValues` (`lfo1`/`lfo2`/`lfo3`).
// Damit entfaellt die Array-Indirektion, die in S-08b-fix erst per
// Scratch-Puffer entschaerft werden musste.
//
// Die beiden Wavetables sind gespeicherte `AudioCoreWavetable`-Werte; deren
// `[Float]`-Puffer werden im Renderpfad ausschliesslich GELESEN (ARC-
// Retain/Release, keine Allokation). Belegt per SIL, siehe Ruecklauf
// Runde 066.

public struct AudioCoreAtmosphericVoice: Sendable {

    // MARK: – Kontrollrate

    /// Samples pro Kontrollschritt. Zweierpotenz, damit der Zaehler billig
    /// bleibt; 32 ergibt bei 48 kHz 1.500 Hz Kontrollrate (0,67 ms).
    public static let controlBlockSize = 32

    // MARK: – Oeffentlicher Zustand (API-nah an der Legacy-`AudioCoreVoice`,
    //         damit `VoicePool` in W-03 nicht umgebaut werden muss)

    /// MIDI-Note dieser Stimme.
    public private(set) var note: UInt8 = 0

    /// Aktivierungsreihenfolge, vom Aufrufer vergeben (Voice-Stealing).
    public private(set) var activationOrder: UInt64 = 0

    /// Huellkurven-Stage der Stimme — identisch zur Stage der Amp-Huelle.
    public var stage: AudioCoreADSRStage { ampEnvelope.stage }

    /// true solange die Stimme Audio produziert.
    public var isActive: Bool { stage != .idle }

    /// Aktueller Space-Send-Anteil dieser Stimme, `0...1`, aktualisiert am
    /// Ende jedes Render-Blocks.
    ///
    /// Sonderfall unter den sieben Modulationszielen: `spaceSend` steuert
    /// keinen Klang INNERHALB der Stimme, sondern wie viel Signal spaeter in
    /// den gemeinsamen Space-Bus geht. Die Stimme macht den Wert deshalb nur
    /// sichtbar und wendet ihn NICHT selbst an — das tut W-03. Nachgewiesen
    /// in `test_spaceSend_isExposedButNotAppliedInsideTheVoice`.
    public private(set) var spaceSendLevel: Float = 0

    /// Sample Rate, auf die die Stimme vorbereitet ist (bereits geklemmt).
    public private(set) var sampleRate: Double

    /// Interne Kontrollrate in Hz (`sampleRate / controlBlockSize`).
    public var controlRate: Double { sampleRate / Double(AudioCoreAtmosphericVoice.controlBlockSize) }

    public private(set) var parameters: AudioCoreAtmosphericVoiceParameters

    // MARK: – Klangquellen

    private let wavetableA: AudioCoreWavetable
    private let wavetableB: AudioCoreWavetable

    private var sourceA: AudioCoreMorphOscillator
    private var sourceB: AudioCoreSourceB
    private var texture: AudioCoreTextureSource

    // MARK: – Filter und Shaping

    private var filter: AudioCoreStateVariableFilter
    private var waveshaperParameters: AudioCoreWaveshaperParameters

    // MARK: – Modulatoren

    private var ampEnvelope: AudioCoreEnvelope
    private var modEnvelope: AudioCoreEnvelope

    private var lfo1: AudioCoreLFO
    private var lfo2: AudioCoreLFO
    private var lfo3: AudioCoreLFO

    // MARK: – Kontrollraten-Zwischenwerte (Ziel der Matrix, vor Glaettung)

    private var controlPhase: Int = 0

    private var targetMorphPosition: Float = 0
    private var targetTextureLevel: Float = 0
    private var targetFilterCutoff: Float = 0
    private var targetMixDepth: Float = 0
    private var targetAmpEnvelopeDepth: Float = 0
    private var targetModEnvelopeDepth: Float = 0
    private var targetSpaceSend: Float = 0

    // MARK: – Glaettung (Audiorate, ein Smoother je Modulationsziel)

    private var morphSmoother: AudioCoreParameterSmoother
    private var textureLevelSmoother: AudioCoreParameterSmoother
    private var filterCutoffSmoother: AudioCoreParameterSmoother
    private var mixDepthSmoother: AudioCoreParameterSmoother
    private var ampEnvelopeDepthSmoother: AudioCoreParameterSmoother
    private var modEnvelopeDepthSmoother: AudioCoreParameterSmoother
    private var spaceSendSmoother: AudioCoreParameterSmoother

    // MARK: – Pro Note gesetzt

    private var velocity: Float = 0
    private var panGainL: Float = 1.0
    private var panGainR: Float = 1.0

    // MARK: – Initialisierung

    /// Baut eine Stimme fuer eine feste Sample Rate. Die beiden Wavetables
    /// sind bewusst Konstruktionsparameter und keine Note-On-Parameter: sie
    /// tragen die einzigen Heap-Puffer der Stimme und muessen deshalb
    /// ausserhalb des Renderpfads vorbereitet werden
    /// (`SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 5).
    public init(sampleRate: Double,
                wavetableA: AudioCoreWavetable = AudioCoreWavetableBank.warmOdd,
                wavetableB: AudioCoreWavetable = AudioCoreWavetableBank.brightFull,
                parameters: AudioCoreAtmosphericVoiceParameters = .defaults) {

        let safeRate = AudioCoreAtmosphericVoiceParameters.safeSampleRate(sampleRate)
        let controlRate = safeRate / Double(AudioCoreAtmosphericVoice.controlBlockSize)

        self.sampleRate = safeRate
        self.parameters = parameters
        self.wavetableA = wavetableA
        self.wavetableB = wavetableB

        self.sourceA = AudioCoreMorphOscillator(sampleRate: safeRate,
                                                 wavetableA: wavetableA,
                                                 wavetableB: wavetableB,
                                                 frequencyHz: 440.0,
                                                 morph: parameters.morphPosition)
        self.sourceB = AudioCoreSourceB(sampleRate: safeRate,
                                         wavetableA: wavetableA,
                                         wavetableB: wavetableB,
                                         baseFrequencyHz: 440.0,
                                         transpositionSemitones: parameters.sourceBTranspositionSemitones,
                                         fineTuneCents: parameters.sourceBFineTuneCents,
                                         morph: parameters.morphPosition)

        // Der Pegel der Texturquelle bleibt intern `1.0`; die Stimme wendet
        // stattdessen ihren eigenen, auf Audiorate geglaetteten Texturpegel
        // an. Sonst wuerde `textureLevel` nur auf Kontrollrate springen.
        self.texture = AudioCoreTextureSource(seed: parameters.textureSeed,
                                               brightness: parameters.textureBrightness,
                                               level: 1.0)

        self.filter = AudioCoreStateVariableFilter(
            sampleRate: safeRate,
            parameters: AudioCoreSVFParameters(cutoff: parameters.filterCutoff,
                                                resonance: parameters.filterResonance))
        self.waveshaperParameters = AudioCoreWaveshaperParameters(drive: parameters.drive,
                                                                   outputGain: parameters.waveshaperOutputGain)

        self.ampEnvelope = AudioCoreEnvelope(parameters: parameters.ampEnvelope)
        self.modEnvelope = AudioCoreEnvelope(parameters: parameters.modEnvelope)

        self.lfo1 = AudioCoreAtmosphericVoice.makeLFO(parameters.lfo1, controlRate: controlRate, seed: parameters.lfo1Seed)
        self.lfo2 = AudioCoreAtmosphericVoice.makeLFO(parameters.lfo2, controlRate: controlRate, seed: parameters.lfo2Seed)
        self.lfo3 = AudioCoreAtmosphericVoice.makeLFO(parameters.lfo3, controlRate: controlRate, seed: parameters.lfo3Seed)

        let smoothing = parameters.smoothingTimeMs
        self.morphSmoother = AudioCoreParameterSmoother(sampleRate: safeRate, timeMs: smoothing, initialValue: parameters.morphPosition)
        self.textureLevelSmoother = AudioCoreParameterSmoother(sampleRate: safeRate, timeMs: smoothing, initialValue: parameters.textureLevel)
        self.filterCutoffSmoother = AudioCoreParameterSmoother(sampleRate: safeRate, timeMs: smoothing, initialValue: parameters.filterCutoff)
        self.mixDepthSmoother = AudioCoreParameterSmoother(sampleRate: safeRate, timeMs: smoothing, initialValue: parameters.mixDepth)
        self.ampEnvelopeDepthSmoother = AudioCoreParameterSmoother(sampleRate: safeRate, timeMs: smoothing, initialValue: parameters.ampEnvelopeDepth)
        self.modEnvelopeDepthSmoother = AudioCoreParameterSmoother(sampleRate: safeRate, timeMs: smoothing, initialValue: parameters.modEnvelopeDepth)
        self.spaceSendSmoother = AudioCoreParameterSmoother(sampleRate: safeRate, timeMs: smoothing, initialValue: parameters.spaceSend)

        self.spaceSendLevel = parameters.spaceSend
        resetModulationTargetsToBase()
    }

    /// Baut einen `AudioCoreLFO` fuer die Kontrollrate.
    ///
    /// Die Frequenz wird zusaetzlich auf ein Viertel der Kontrollrate
    /// gedeckelt. Das ist eine rein technische Grenze: `AudioCoreLFO`
    /// wrappt seine Phase mit einem einzelnen Subtraktionsschritt, was nur
    /// bei einem Phaseninkrement `< 1` korrekt ist. Bei der zulaessigen
    /// Mindest-Sample-Rate (100 Hz) liegt die Kontrollrate bei 3,125 Hz —
    /// ohne diesen Deckel koennte die LFO-Obergrenze von 200 Hz ein
    /// Inkrement von 64 erzeugen und die Phase liefe unbegrenzt fort. Bei
    /// realen Sample Rates greift der Deckel nie (48 kHz ergeben 375 Hz,
    /// oberhalb der LFO-Obergrenze von 200 Hz).
    private static func makeLFO(_ parameters: AudioCoreLFOParameters,
                                 controlRate: Double,
                                 seed: UInt64) -> AudioCoreLFO {
        let capped = AudioCoreLFOParameters(shape: parameters.shape,
                                             frequencyHz: min(parameters.frequencyHz, Float(controlRate) * 0.25),
                                             smoothingAmount: parameters.smoothingAmount)
        return AudioCoreLFO(sampleRate: controlRate, parameters: capped, seed: seed)
    }

    // MARK: – Parameter (Post-Init-Mutationspfad, Gate 7)
    //
    // Baut den uebernommenen Satz ueber
    // `AudioCoreAtmosphericVoiceParameters.init` neu auf, damit auch ein
    // ueber `public var` nachtraeglich veraenderter Patch durch denselben
    // Klemmpfad laeuft (S-08a-01-Lehre). Kein Klemm-Duplikat in dieser Datei.
    //
    // Bewusst OHNE Reset der Glaetter: eine Parameteraenderung an einer
    // klingenden Stimme soll gleiten, nicht springen. Genau das ersetzt die
    // aus der Legacy-Voice NICHT uebernommene
    // `updateLowpassCoefficients(b0:b1:b2:a1:a2:)` — der Aufrufer uebergibt
    // keine Biquad-Koeffizienten mehr, sondern einen neuen Cutoff-/
    // Resonanzwert; die Stimme glaettet ihn selbst und rechnet die
    // SVF-Koeffizienten beim naechsten Kontrollschritt neu.
    public mutating func setParameters(_ newParameters: AudioCoreAtmosphericVoiceParameters) {
        parameters = AudioCoreAtmosphericVoiceParameters(
            mixMode: newParameters.mixMode,
            gainA: newParameters.gainA,
            mixDepth: newParameters.mixDepth,
            morphPosition: newParameters.morphPosition,
            textureLevel: newParameters.textureLevel,
            textureBrightness: newParameters.textureBrightness,
            textureSeed: newParameters.textureSeed,
            sourceBTranspositionSemitones: newParameters.sourceBTranspositionSemitones,
            sourceBFineTuneCents: newParameters.sourceBFineTuneCents,
            sourceBPhaseOffset: newParameters.sourceBPhaseOffset,
            filterMode: newParameters.filterMode,
            filterCutoff: newParameters.filterCutoff,
            filterResonance: newParameters.filterResonance,
            drive: newParameters.drive,
            waveshaperOutputGain: newParameters.waveshaperOutputGain,
            outputLevel: newParameters.outputLevel,
            ampEnvelope: newParameters.ampEnvelope,
            modEnvelope: newParameters.modEnvelope,
            ampEnvelopeDepth: newParameters.ampEnvelopeDepth,
            modEnvelopeDepth: newParameters.modEnvelopeDepth,
            lfo1: newParameters.lfo1,
            lfo2: newParameters.lfo2,
            lfo3: newParameters.lfo3,
            lfo1Seed: newParameters.lfo1Seed,
            lfo2Seed: newParameters.lfo2Seed,
            lfo3Seed: newParameters.lfo3Seed,
            modulationMatrix: newParameters.modulationMatrix,
            macros: newParameters.macros,
            spaceSend: newParameters.spaceSend,
            smoothingTimeMs: newParameters.smoothingTimeMs)

        applyParametersToBuildingBlocks()
    }

    /// Uebertraegt den geklemmten Parametersatz auf die Bausteine, ohne
    /// laufenden Klangzustand (Phasen, Filterzustand, Huellenstand) zu
    /// beruehren.
    private mutating func applyParametersToBuildingBlocks() {
        ampEnvelope.setParameters(parameters.ampEnvelope)
        modEnvelope.setParameters(parameters.modEnvelope)

        texture.setBrightness(parameters.textureBrightness)

        sourceB.setTransposition(semitones: parameters.sourceBTranspositionSemitones)
        sourceB.setFineTune(cents: parameters.sourceBFineTuneCents)

        filter.setParameters(AudioCoreSVFParameters(cutoff: filterCutoffSmoother.currentValue,
                                                     resonance: parameters.filterResonance))
        waveshaperParameters = AudioCoreWaveshaperParameters(drive: parameters.drive,
                                                              outputGain: parameters.waveshaperOutputGain)

        applyLFOParameters()

        morphSmoother.setTimeMs(parameters.smoothingTimeMs)
        textureLevelSmoother.setTimeMs(parameters.smoothingTimeMs)
        filterCutoffSmoother.setTimeMs(parameters.smoothingTimeMs)
        mixDepthSmoother.setTimeMs(parameters.smoothingTimeMs)
        ampEnvelopeDepthSmoother.setTimeMs(parameters.smoothingTimeMs)
        modEnvelopeDepthSmoother.setTimeMs(parameters.smoothingTimeMs)
        spaceSendSmoother.setTimeMs(parameters.smoothingTimeMs)
    }

    private mutating func applyLFOParameters() {
        let cap = Float(controlRate) * 0.25

        lfo1.setShape(parameters.lfo1.shape)
        lfo1.setFrequency(min(parameters.lfo1.frequencyHz, cap))
        lfo1.setSmoothingAmount(parameters.lfo1.smoothingAmount)

        lfo2.setShape(parameters.lfo2.shape)
        lfo2.setFrequency(min(parameters.lfo2.frequencyHz, cap))
        lfo2.setSmoothingAmount(parameters.lfo2.smoothingAmount)

        lfo3.setShape(parameters.lfo3.shape)
        lfo3.setFrequency(min(parameters.lfo3.frequencyHz, cap))
        lfo3.setSmoothingAmount(parameters.lfo3.smoothingAmount)
    }

    // MARK: – Sample Rate

    /// Bereitet die Stimme auf eine neue Sample Rate vor. Baut alle
    /// ratenabhaengigen Bausteine neu auf und setzt die Stimme dabei auf
    /// `idle` — ein Sample-Rate-Wechsel an einer klingenden Stimme ist kein
    /// definierter musikalischer Vorgang.
    public mutating func prepare(sampleRate newSampleRate: Double) {
        let safeRate = AudioCoreAtmosphericVoiceParameters.safeSampleRate(newSampleRate)
        guard safeRate != sampleRate else { return }

        sampleRate = safeRate
        let controlRate = safeRate / Double(AudioCoreAtmosphericVoice.controlBlockSize)

        sourceA = AudioCoreMorphOscillator(sampleRate: safeRate,
                                            wavetableA: wavetableA,
                                            wavetableB: wavetableB,
                                            frequencyHz: sourceA.frequencyHz,
                                            morph: parameters.morphPosition)
        sourceB = AudioCoreSourceB(sampleRate: safeRate,
                                    wavetableA: wavetableA,
                                    wavetableB: wavetableB,
                                    baseFrequencyHz: sourceB.baseFrequencyHz,
                                    transpositionSemitones: parameters.sourceBTranspositionSemitones,
                                    fineTuneCents: parameters.sourceBFineTuneCents,
                                    morph: parameters.morphPosition)

        filter.setSampleRate(safeRate)

        lfo1 = AudioCoreAtmosphericVoice.makeLFO(parameters.lfo1, controlRate: controlRate, seed: parameters.lfo1Seed)
        lfo2 = AudioCoreAtmosphericVoice.makeLFO(parameters.lfo2, controlRate: controlRate, seed: parameters.lfo2Seed)
        lfo3 = AudioCoreAtmosphericVoice.makeLFO(parameters.lfo3, controlRate: controlRate, seed: parameters.lfo3Seed)

        let smoothing = parameters.smoothingTimeMs
        morphSmoother = AudioCoreParameterSmoother(sampleRate: safeRate, timeMs: smoothing, initialValue: parameters.morphPosition)
        textureLevelSmoother = AudioCoreParameterSmoother(sampleRate: safeRate, timeMs: smoothing, initialValue: parameters.textureLevel)
        filterCutoffSmoother = AudioCoreParameterSmoother(sampleRate: safeRate, timeMs: smoothing, initialValue: parameters.filterCutoff)
        mixDepthSmoother = AudioCoreParameterSmoother(sampleRate: safeRate, timeMs: smoothing, initialValue: parameters.mixDepth)
        ampEnvelopeDepthSmoother = AudioCoreParameterSmoother(sampleRate: safeRate, timeMs: smoothing, initialValue: parameters.ampEnvelopeDepth)
        modEnvelopeDepthSmoother = AudioCoreParameterSmoother(sampleRate: safeRate, timeMs: smoothing, initialValue: parameters.modEnvelopeDepth)
        spaceSendSmoother = AudioCoreParameterSmoother(sampleRate: safeRate, timeMs: smoothing, initialValue: parameters.spaceSend)

        reset()
    }

    // MARK: – Reset
    //
    // Setzt allen laufenden Klangzustand zurueck, ohne zu allozieren — die
    // Vormerkung aus dem S-08b-fix-Review ("beim Verdrahten wird `reset()`
    // voraussichtlich aus einem Command im Rendercallback ausgeloest") gilt
    // fuer diesen Typ von Anfang an.
    public mutating func reset() {
        ampEnvelope.reset()
        modEnvelope.reset()
        filter.reset()

        sourceA.resetPhase(to: 0)
        sourceB.resetPhase(to: parameters.sourceBPhaseOffset)
        texture.resetState(to: parameters.textureSeed)

        lfo1.resetPhase(to: 0)
        lfo2.resetPhase(to: 0)
        lfo3.resetPhase(to: 0)
        lfo1.resetRandomState(to: parameters.lfo1Seed)
        lfo2.resetRandomState(to: parameters.lfo2Seed)
        lfo3.resetRandomState(to: parameters.lfo3Seed)

        controlPhase = 0
        resetSmoothersToBase()
        resetModulationTargetsToBase()
        spaceSendLevel = parameters.spaceSend
    }

    private mutating func resetSmoothersToBase() {
        morphSmoother.reset(to: parameters.morphPosition)
        textureLevelSmoother.reset(to: parameters.textureLevel)
        filterCutoffSmoother.reset(to: parameters.filterCutoff)
        mixDepthSmoother.reset(to: parameters.mixDepth)
        ampEnvelopeDepthSmoother.reset(to: parameters.ampEnvelopeDepth)
        modEnvelopeDepthSmoother.reset(to: parameters.modEnvelopeDepth)
        spaceSendSmoother.reset(to: parameters.spaceSend)
    }

    private mutating func resetModulationTargetsToBase() {
        targetMorphPosition = parameters.morphPosition
        targetTextureLevel = parameters.textureLevel
        targetFilterCutoff = parameters.filterCutoff
        targetMixDepth = parameters.mixDepth
        targetAmpEnvelopeDepth = parameters.ampEnvelopeDepth
        targetModEnvelopeDepth = parameters.modEnvelopeDepth
        targetSpaceSend = parameters.spaceSend
    }

    // MARK: – Note-On
    //
    // Sinngemaess identische Signatur zur Legacy-`AudioCoreVoice.configure`,
    // damit `VoicePool` beim Umschalten in W-03 nicht umgebaut werden muss.
    // Frequenzformel bewusst wiederverwendet statt dupliziert
    // (`AudioCoreVoice.frequency(forNote:detuneCents:)`).

    public mutating func configure(note: UInt8,
                                    velocity: UInt8,
                                    sampleRate: Double,
                                    parameters: AudioCoreAtmosphericVoiceParameters,
                                    activationOrder: UInt64 = 0,
                                    detuneCents: Float = 0.0,
                                    panPosition: Float = 0.0,
                                    gainScale: Float = 1.0) {

        prepare(sampleRate: sampleRate)
        setParameters(parameters)

        self.note = note
        self.activationOrder = activationOrder
        self.velocity = Float(velocity) / 127.0 * (gainScale.isFinite ? gainScale : 0)

        // Constant-Power-Panning, skaliert auf L=R=1.0 bei Pan=0 — identische
        // Formel wie in der Legacy-Voice, damit W-03 die Stereo-Verteilung
        // eines `VoicePool` nicht neu kalibrieren muss.
        let safePan = panPosition.isFinite ? max(-1.0, min(panPosition, 1.0)) : 0
        let panAngle = (safePan + 1.0) * Float.pi * 0.25
        panGainL = sqrtf(2.0) * cosf(panAngle)
        panGainR = sqrtf(2.0) * sinf(panAngle)

        let frequency = AudioCoreVoice.frequency(forNote: note, detuneCents: detuneCents)
        sourceA.setFrequency(frequency)
        sourceB.setBaseFrequency(frequency)

        reset()

        // Texturseed pro Stimme dekorrelieren: gleichzeitig klingende Stimmen
        // wuerden sonst bitgenau dasselbe Rauschen erzeugen und kohaerent
        // summieren (bei 16 Stimmen rund 24 dB lauter als unkorreliertes
        // Rauschen). Deterministisch, weil `activationOrder` vom Aufrufer
        // vergeben wird.
        texture.resetState(to: self.parameters.textureSeed ^ (activationOrder &* 0x9E37_79B9_7F4A_7C15))

        ampEnvelope.noteOn(sampleRate: self.sampleRate)
        modEnvelope.noteOn(sampleRate: controlRate)
    }

    // MARK: – Note-Off

    public mutating func triggerRelease() {
        ampEnvelope.noteOff()
        modEnvelope.noteOff()
    }

    // MARK: – Kontrollschritt
    //
    // Ein Durchlauf alle `controlBlockSize` Samples: Modulatoren
    // fortschreiben, Matrix auswerten, die sieben Zielwerte setzen und die
    // Filterkoeffizienten aus dem GEGLAETTETEN Cutoff neu rechnen.

    private mutating func updateControlStep() {
        let lfo1Value = lfo1.nextValue()
        let lfo2Value = lfo2.nextValue()
        let lfo3Value = lfo3.nextValue()
        let modEnvelopeValue = modEnvelope.nextValue()

        // Die Mod-Huelle geht mit ihrer aktuellen Tiefe skaliert in die
        // Matrix. Verwendet wird der geglaettete Tiefenwert, wie er nach dem
        // letzten Audiosample steht — dadurch ist auch eine selbstbezuegliche
        // Route (`modEnvelope -> modEnvelopeDepth`) definiert (Verzoegerung um
        // einen Kontrollschritt) statt eine algebraische Schleife.
        let sources = AudioCoreModulationSourceValues(
            macros: parameters.macros,
            lfo1: lfo1Value,
            lfo2: lfo2Value,
            lfo3: lfo3Value,
            ampEnvelope: ampEnvelope.value,
            modEnvelope: modEnvelopeValue * modEnvelopeDepthSmoother.currentValue)

        let targets = parameters.modulationMatrix.evaluate(sources: sources)

        targetMorphPosition    = AudioCoreAtmosphericVoice.clampUnit(parameters.morphPosition    + targets.morphPosition)
        targetTextureLevel     = AudioCoreAtmosphericVoice.clampUnit(parameters.textureLevel     + targets.textureLevel)
        targetFilterCutoff     = AudioCoreAtmosphericVoice.clampUnit(parameters.filterCutoff     + targets.filterCutoff)
        targetMixDepth         = AudioCoreAtmosphericVoice.clampUnit(parameters.mixDepth         + targets.mixDepth)
        targetAmpEnvelopeDepth = AudioCoreAtmosphericVoice.clampUnit(parameters.ampEnvelopeDepth + targets.ampEnvelopeDepth)
        targetModEnvelopeDepth = AudioCoreAtmosphericVoice.clampUnit(parameters.modEnvelopeDepth + targets.modEnvelopeDepth)
        targetSpaceSend        = AudioCoreAtmosphericVoice.clampUnit(parameters.spaceSend        + targets.spaceSend)

        filter.setParameters(AudioCoreSVFParameters(cutoff: filterCutoffSmoother.currentValue,
                                                     resonance: parameters.filterResonance))
    }

    // MARK: – DSP-Render
    //
    // Schreibt (additiv) in vom Aufrufer bereitgestellte L/R-Puffer —
    // identischer Vertrag wie `AudioCoreVoice.render(intoL:intoR:frameCount:)`.
    // Kein Heap-Zugriff, kein Alloc, kein Lock, keine Dispatch-/Task-/
    // Actor-Nutzung, kein `print`.

    @discardableResult
    public mutating func render(intoL outputL: UnsafeMutablePointer<Float>,
                                 intoR outputR: UnsafeMutablePointer<Float>,
                                 frameCount: Int) -> Bool {

        for frame in 0..<frameCount {
            if ampEnvelope.stage == .idle { break }

            if controlPhase == 0 { updateControlStep() }
            controlPhase += 1
            if controlPhase >= AudioCoreAtmosphericVoice.controlBlockSize { controlPhase = 0 }

            // Glaettung auf Audiorate — alle sieben Ziele einheitlich, damit
            // kein Ziel eine Sonderbehandlung braucht.
            let morph = morphSmoother.setTarget(targetMorphPosition)
            let textureGain = textureLevelSmoother.setTarget(targetTextureLevel)
            let mixDepth = mixDepthSmoother.setTarget(targetMixDepth)
            let ampDepth = ampEnvelopeDepthSmoother.setTarget(targetAmpEnvelopeDepth)
            filterCutoffSmoother.setTarget(targetFilterCutoff)
            modEnvelopeDepthSmoother.setTarget(targetModEnvelopeDepth)
            spaceSendSmoother.setTarget(targetSpaceSend)

            // Quellen
            sourceA.setMorph(morph)
            sourceB.setMorph(morph)
            let sampleA = sourceA.nextSample()
            let sampleB = sourceB.nextSample()
            let sampleC = texture.nextSample()

            // Mixer: nur die A/B-Interaktion. Die Textur wird bewusst
            // ausserhalb des Mixers addiert, weil `AudioCoreMixer` sie per
            // Vertrag nur im `.linear`-Modus beruecksichtigt
            // (`.ringModulation`/`.softPhaseModulation` ignorieren `c`). Ein
            // Modulationsziel, das nur im Default-Mixmodus wirkt, waere genau
            // der Fehler, den dieser Slice ausschliessen soll.
            let mixParameters = AudioCoreMixParameters(gainA: parameters.gainA,
                                                        gainB: mixDepth,
                                                        gainC: 0,
                                                        ringModDepth: mixDepth,
                                                        phaseModDepth: mixDepth)
            let mixedAB = AudioCoreMixer.mix(a: sampleA, b: sampleB, c: 0,
                                              mode: parameters.mixMode,
                                              parameters: mixParameters)
            let mixed = mixedAB + sampleC * textureGain

            // Filter -> Waveshaper
            let filtered = filter.process(mixed, mode: parameters.filterMode)
            let shaped = AudioCoreWaveshaper.process(filtered, parameters: waveshaperParameters)

            // Amp-Huelle -> Pan -> additive Akkumulation
            let ampValue = ampEnvelope.nextValue()
            let sample = shaped * ampValue * ampDepth * velocity * parameters.outputLevel

            outputL[frame] += sample * panGainL
            outputR[frame] += sample * panGainR
        }

        spaceSendLevel = spaceSendSmoother.currentValue
        return isActive
    }

    // MARK: – Hilfen

    private static func clampUnit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return max(0.0, min(value, 1.0))
    }
}
