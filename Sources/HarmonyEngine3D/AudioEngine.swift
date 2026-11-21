import Foundation
import AVFoundation
import AudioToolbox  // kAudioUnitType_Effect, kAudioUnitSubType_DynamicsProcessor, AudioUnitSetParameter
import QuartzCore   // CACurrentMediaTime() – für Audio-Debug-Timestamps
import HarmonyAudioCore   // AudioCoreMacroValues (Performance-Makros, W-05)

// MARK: – AudioEngine (4 vollständig unabhängige Kanäle)
//
// Signalfluss pro Kanal X (Chord / Bass / Melody / ChordTone):
//
//   synthX → gainX ─┬→ sumX (direkt, Dry-Signal) ─────────────────────────────┐
//                    ├→ delay1SendX → delay1X ─┐                               │
//                    ├→ delay2SendX → delay2X  ├→ sumX → reverbX → mainMixerNode
//                    └→ delay3SendX → delay3X ─┘
//
// Alle vier Kanäle folgen exakt demselben Signalfluss.
// CH3 (ChordTone) ist vollständig unabhängig von CH0 (Chord).
// Kein geteilter Node, keine Cross-Channel-Kopplung.
//
// Send-Modell:
//   delay1/2/3SendX: AVAudioMixerNode VOR dem Delay.
//   outputVolume → Send-Pegel (Signal-Feed in den Delay).
//   delay.wetDryMix = 100 %: Delay gibt ausschließlich Wet-Signal aus.
//   Dry-Signal fließt direkt von gainX → sumX.
//
// Gemeinsame Echo-/Space-Send-Busse (S-07a, Vorbereitung für A3):
//   sharedEchoSendBus / sharedSpaceSendBus sind ab Runde 055 an
//   mainMixerNode angeschlossen. sharedEchoSendBus ist weiterhin ungespeist
//   (EchoField folgt in S-09); sharedSpaceSendBus wird seit W-03c/Runde 072
//   von der gemeinsamen DeepSpace-Kette gespeist:
//
//     vier SynthNodes ──(SpaceSendBus, pro Stimme mit spaceSendLevel)──┐
//                                                                      ↓
//               DeepSpaceReturnNode → sharedSpaceSendBus → mainMixerNode
//
//   Der Send entsteht in Software statt als Knotenabgriff, weil er PRO
//   STIMME gewichtet ist — vollständige Begründung und die Zuordnung zum
//   getesteten Topologie-Deskriptor (AudioGraphTopology.swift, für CH1/Bass
//   vor compressorBass, Option A) stehen in SpaceSendBus.swift.
//
//   Die kanalgetrennte Legacy-FX-Kette oben bleibt unverändert der aktive
//   Trockenpfad; der Raum kommt additiv dazu.
//
// SynthParams-Mapping:
//   applyEffectConfigX() leitet neben FX-Parametern auch SynthParams an synthX weiter.
//   Mapping: attack × 2000 → attackMs, decay × 1000 → decayMs, sustain → sustain,
//            release × 1000 → releaseMs, filterCutoff, filterResonance, waveform.
//   Der Mapping-Pfad liegt vollständig in AudioEngine — SynthNode/AudioCoreVoice werten
//   ChannelFXConfig nicht aus.
//
// Kanalmodell:
//   CH 0 = Akkorde     CH 1 = Bass     CH 2 = Melodie     CH 3 = Chord-Tones
//
// Die Engine ist ausschließlich ein Note-Event-Router.
// Polyphonie, Voice-Stealing und ADSR: Entscheidung von SynthNode/AudioCoreVoice.
// Kein AppSettings-Zugriff. Kein Singleton.
//
// ── Producer-Serialisierung (Runde 016 / F-02) ────────────────────────────────
//
// Jeder SynthNode kapselt eine NoteEventQueue, die als SPSC-Ringpuffer gebaut
// ist (siehe NoteEventQueue.swift) — korrekt nur, wenn tatsächlich genau ein
// Thread push() aufruft. Real rufen mehrere Threads in dieselbe AudioOutput-API:
//   – SceneKit-Render-Thread (SCNSceneRendererDelegate.renderer(_:updateAtTime:)
//     → HarmonyScene-Events → OutputCoordinator → noteOn/noteOff CH0/CH1/CH2)
//   – GameController-Handler-Thread (CH3 Chord-Tones, △ All-Notes-Off)
//   – Main Thread (Combine-Subscription auf AppSettings.audio → applyFXConfig*
//     → SynthNode.updateParams; außerdem ContentView-Button → stopAll())
// Das war vorher ein echter Datenrace auf NoteEventQueue.writeIndex, nicht nur
// ein Dokumentationsfehler.
//
// `commandQueue` ist die alleinige Serialisierungsgrenze: alle vier
// AudioOutput-Methoden sowie der SynthNode.updateParams()-Aufruf in
// applyEffectConfig* laufen ausschließlich auf dieser einen seriellen Queue.
// Damit gibt es pro NoteEventQueue wieder exakt einen Producer-Thread —
// unabhängig davon, von welchem Thread der jeweilige AudioOutput-Aufruf kam.
// Der Audio-Render-Thread (Consumer, in SynthNode.prepare()) ist unverändert:
// kein Lock, kein Dispatch, keine Allokation, kein Swift-Concurrency dort.
//
// Reihenfolgegarantie: Aufrufe vom selben Thread behalten ihre Reihenfolge
// (GCD serialisiert .async-Submits pro Thread in Submit-Reihenfolge). Über
// verschiedene Aufrufer-Threads hinweg (z. B. ein Render-Thread-noteOn versus
// ein zeitgleiches Main-Thread-paramUpdate) gilt Submit-Reihenfolge auf
// commandQueue — keine stärkere Garantie als vorher, aber jetzt racefrei statt
// Undefined Behavior. Bestehendes Verhalten (paramUpdate wirkt "for alle
// nachfolgenden noteOns derselben Batch", siehe SynthNode.VoicePool-Doku)
// bleibt für Aufrufe vom selben Thread unverändert.

final class AudioEngine: AudioOutput {

    private let engine = AVAudioEngine()

    // Einzige Serialisierungsgrenze für alle SynthNode-Queue-Schreibzugriffe —
    // siehe Typ-Kommentar oben. Plain serial DispatchQueue, kein Zielkonflikt
    // mit dem lock-freien Audio-Render-Pfad (der bleibt komplett unberührt).
    private let commandQueue = DispatchQueue(label: "com.harmonyengine3d.audioengine.commands")

    // MARK: – SynthNodes (alle vier Kanäle)

    private let synthChord     = SynthNode()   // CH 0 – Akkorde
    private let synthBass      = SynthNode()   // CH 1 – Bass
    private let synthMelody    = SynthNode()   // CH 2 – Melodie
    private let synthChordTone = SynthNode()   // CH 3 – Chord-Tones (Gamepad)

    // MARK: – Channel-Gain-Nodes
    //
    // Statischer Lautstärke-Fader pro Kanal. Kein Envelope.

    private let gainChord     = AVAudioMixerNode()
    private let gainBass      = AVAudioMixerNode()
    private let gainMelody    = AVAudioMixerNode()
    private let gainChordTone = AVAudioMixerNode()   // CH 3 – eigener Gain

    // MARK: – Delay-Ketten (3 Taps × 4 Kanäle)
    //
    // delay1/2/3SendX: AVAudioMixerNode vor dem Delay.
    //   outputVolume → Send-Pegel (wie viel Signal fließt in den Delay)
    //   pan          → Stereoposition des Signals vor dem Delay
    //
    // delay1/2/3X: AVAudioUnitDelay. wetDryMix = 100 % (ausschließlich Wet-Ausgang).

    private let delay1SendChord  = AVAudioMixerNode()
    private let delay2SendChord  = AVAudioMixerNode()
    private let delay3SendChord  = AVAudioMixerNode()
    private let delay1Chord      = AVAudioUnitDelay()
    private let delay2Chord      = AVAudioUnitDelay()
    private let delay3Chord      = AVAudioUnitDelay()

    // MARK: – Kompressor CH 1 (Bass)
    //
    // Position im Signalfluss: gainBass → compressorBass → [sumBass + delay-Sends]
    //
    // Nur CH1. Kein Einfluss auf andere Kanäle.
    //
    // AVAudioUnitDynamicsProcessor ist auf macOS via SPM nicht direkt zugänglich.
    // Stattdessen: AVAudioUnitEffect mit kAudioUnitSubType_DynamicsProcessor (AudioToolbox).
    // Parameter werden nach dem Attach via AudioUnitSetParameter gesetzt (setupGraph, Schritt 6).
    //
    // Parameter (Startwerte):
    //   threshold:      −20 dB   — greift bei mittlerer Lautstärke; lässt Transienten durch
    //   headRoom:         5 dB   — Standard-Headroom unter 0 dBFS
    //   expansionRatio:   1.0   — kein Expander/Gate
    //   attackTime:       0.020 s — 20 ms: Transienten bleiben erhalten
    //   releaseTime:      0.150 s — 150 ms: glatter Gain-Recovery
    //   masterGain:      +6 dB   — Make-up-Gain: kompensiert den mittleren Gain-Reduction-Pegel

    private let compressorBass: AVAudioUnitEffect = {
        let desc = AudioComponentDescription(
            componentType:         kAudioUnitType_Effect,
            componentSubType:      kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags:        0,
            componentFlagsMask:    0
        )
        return AVAudioUnitEffect(audioComponentDescription: desc)
    }()

    private let delay1SendBass   = AVAudioMixerNode()
    private let delay2SendBass   = AVAudioMixerNode()
    private let delay3SendBass   = AVAudioMixerNode()
    private let delay1Bass       = AVAudioUnitDelay()
    private let delay2Bass       = AVAudioUnitDelay()
    private let delay3Bass       = AVAudioUnitDelay()

    private let delay1SendMelody = AVAudioMixerNode()
    private let delay2SendMelody = AVAudioMixerNode()
    private let delay3SendMelody = AVAudioMixerNode()
    private let delay1Melody     = AVAudioUnitDelay()
    private let delay2Melody     = AVAudioUnitDelay()
    private let delay3Melody     = AVAudioUnitDelay()

    private let delay1SendChordTone = AVAudioMixerNode()   // CH 3
    private let delay2SendChordTone = AVAudioMixerNode()
    private let delay3SendChordTone = AVAudioMixerNode()
    private let delay1ChordTone     = AVAudioUnitDelay()
    private let delay2ChordTone     = AVAudioUnitDelay()
    private let delay3ChordTone     = AVAudioUnitDelay()

    // MARK: – Summierer (Dry-Signal + Delay-Taps → Reverb)

    private let sumChord     = AVAudioMixerNode()
    private let sumBass      = AVAudioMixerNode()
    private let sumMelody    = AVAudioMixerNode()
    private let sumChordTone = AVAudioMixerNode()   // CH 3

    // MARK: – Gemeinsame Echo-/Space-Send-Busse (S-07a, Vorbereitung fuer A3)
    //
    // Zwei gemeinsame Stereo-Sammelbusse fuer den spaeteren `EchoField`-Send
    // (S-07b/S-09) und `DeepSpace`-Send (S-08), siehe SYNTH_ARCHITECTURE_PLAN.md
    // Abschnitt 7.1. Beide Busse sind ab Runde 055 an `mainMixerNode`
    // angeschlossen, aber von KEINEM Kanal gespeist — ein vorbereiteter,
    // musikalisch inaktiver Graph-Rand ohne hoerbaren Effekt. Die bestehende
    // kanalgetrennte Legacy-FX-Kette (delay1/2/3X + reverbX) bleibt bis
    // S-07b/S-08 der alleinige aktive Klangpfad. Welcher Punkt im
    // Kanal-Signalfluss spaeter tatsaechlich hierher sendet, legt
    // `AudioGraphSendTopology.plan` deklarativ fest (siehe
    // AudioGraphTopology.swift) — fuer CH1/Bass nach Stephans
    // Option-A-Entscheidung (2026-07-30) VOR `compressorBass`.
    private let sharedEchoSendBus  = AVAudioMixerNode()
    private let sharedSpaceSendBus = AVAudioMixerNode()

    // MARK: – Gemeinsame Raumkette (W-03c)
    //
    // Ab Runde 072 wird `sharedSpaceSendBus` erstmals gespeist: die vier
    // SynthNodes sammeln ihren pro Stimme mit `spaceSendLevel` gewichteten
    // Send in `spaceSendBus` (Software), `deepSpaceReturn` zieht ihn durch die
    // W-02-Kette `AudioCoreDeepSpace` und gibt ihn stereo an
    // `sharedSpaceSendBus` zurueck. Warum der Send in Software und nicht als
    // Knotenabgriff entsteht — und wie der getestete Topologie-Deskriptor
    // `AudioGraphSendTopology` dabei eingehalten wird — steht vollstaendig in
    // `SpaceSendBus.swift`.
    //
    // Der Graph aendert sich dadurch minimal: `mainMixerNode` bekommt KEINEN
    // neuen Eingang, nur der seit S-07a eingangslose Sammelbus bekommt einen.
    // Die vier kanalgetrennten Legacy-FX-Ketten bleiben unveraendert aktiv;
    // dieser Slice ergaenzt einen Send, er ersetzt nichts.
    private let spaceSendBus = SpaceSendBus()
    private lazy var deepSpaceReturn = DeepSpaceReturnNode(bus: spaceSendBus)

    // MARK: – Vorlaeufiger Produkt-Sendpegel (W-03c)
    //
    // ACHTUNG, ausdruecklich VORLAEUFIG — dieselbe Rolle wie die Zweigpegel
    // der Raumkette (`AudioCoreDeepSpaceChainParameters`, je 0,5, ebenfalls
    // unveraendert vorlaeufig). Stephan hoert den Raum in dieser Runde zum
    // ersten Mal und entscheidet danach.
    //
    // Warum 0,5 — und warum das KEINE Klangentscheidung ist:
    //
    // 1. Der Wert muss groesser als 0 sein, sonst waere der Raum verdrahtet,
    //    aber unhoerbar, und die Runde nicht abnehmbar.
    // 2. 0,5 ist der einzige Wert des Bereichs 0...1, der keine Praeferenz
    //    ausdrueckt — dieselbe Begruendung, mit der W-02 die beiden
    //    Zweigpegel der Kette auf je 0,5 gesetzt hat.
    // 3. Gemessen (Offline-Harness, C4/Velocity 110, 48 kHz, Raumanteil als
    //    Differenzsignal wet − dry) liegt der Raum bei diesem Sendpegel
    //    23,7 dB unter dem Trockensignal (RMS; Peak 21,9 dB darunter). Er ist
    //    damit deutlich hoerbar und zugleich unzweifelhaft untergeordnet: bei
    //    der ersten Abnahme soll die Stimme beurteilbar bleiben und nicht vom
    //    Raum verdeckt werden.
    // 4. Er ist headroom-freundlich. Der Raum ist rein ADDITIV — er nimmt dem
    //    Trockensignal nichts weg, sondern legt sich darauf.
    //
    // Zur Einordnung fuer die spaetere Entscheidung: die Kette ist statisch
    // stark gedaempft (FDN-Ausgangsgain 0,125, Early-Reflection-Tapgains,
    // Zweigpegel je 0,5). Selbst bei Sendpegel 1,0 bleibt der Raum 17,7 dB
    // unter dem Trockensignal. Mehr Raum als das ist ueber diesen Regler
    // allein nicht erreichbar — dafuer muesste an den Zweigpegeln oder am
    // Ausgangsgain der Kette gedreht werden, und beides ist ausdruecklich
    // Stephans Entscheidung nach dem Hoeren.
    //
    // Gilt fuer alle vier Kanaele gleich. Eine Staffelung (z. B. weniger Raum
    // auf dem Bass) waere bereits eine Mischungsaussage und gehoert zu W-05
    // oder zu einer Stephan-Entscheidung.
    static let provisionalSpaceSendLevel: Float = 0.5

    // MARK: – Reverb-Nodes

    private let reverbChord     = AVAudioUnitReverb()
    private let reverbBass      = AVAudioUnitReverb()
    private let reverbMelody    = AVAudioUnitReverb()
    private let reverbChordTone = AVAudioUnitReverb()   // CH 3

    // MARK: – State

    private var isReady = false

    // MARK: – Config-Cache (verhindert redundante AU-Parameter-Updates)

    private var lastChordCfg:     ChannelFXConfig? = nil
    private var lastBassCfg:      ChannelFXConfig? = nil
    private var lastMelodyCfg:    ChannelFXConfig? = nil
    private var lastChordToneCfg: ChannelFXConfig? = nil

    // MARK: – Reverb-Preset-Cache (loadFactoryPreset nur bei Änderung)

    private var cachedReverbPreset = [ObjectIdentifier: Int]()

    // MARK: – Stimmtyp (W-03b1)
    //
    // Gilt für alle vier Kanäle gemeinsam und reist als Feld von SynthParams
    // über die bestehende commandQueue → NoteEventQueue → VoicePool.applyParams.
    // Kein eigener Serialisierungsweg, kein Graph-Eingriff: der Wechsel legt
    // im Rendercallback nur ein Tag zwischen zwei bereits vorgehaltenen Pools
    // um (siehe SynthNode.VoicePool).
    //
    // Nur vom Main Thread geschrieben (App-Layer, wie applyEffectConfig*).
    //
    // Bewusst `.legacy` als Startwert und NICHT der Produkt-Default: dies ist
    // der Zustand vor der ersten Konfiguration durch den App-Layer. Dieser
    // ruft `applyVoiceEngine(AppSettings.audio.voiceEngine)` vor dem ersten
    // `applyEffectConfig*` auf (siehe `HarmonyEngine3DApp.makeAudioOutput`),
    // also bevor ein einziger Ton gespielt werden kann. Der Produkt-Default
    // steht in `AppSettings.AudioConfig` — an genau einer Stelle.

    private var voiceEngine: SynthVoiceEngine = .legacy

    // MARK: – Performance-Makros (W-05)
    //
    // Wie `voiceEngine`: gilt für alle vier Kanäle gemeinsam und reist als
    // Feld von SynthParams über commandQueue → NoteEventQueue →
    // VoicePool.applyParams. Kein eigener Serialisierungsweg.
    //
    // Nur vom Main Thread geschrieben. Der CoreMIDI-Thread schreibt hier
    // NICHT — er füllt den `MIDIMacroCoalescer`, und erst dessen Flush ruft
    // auf dem Main Thread `applyMacroValues(_:)`. Siehe MIDIMacroMapping.swift.
    //
    // Startwert ist der neutrale Wert (alle vier auf 0): ohne CC-Eingang ist
    // der Klang damit unverändert gegenüber dem Stand vor W-05.

    private var currentMacros: AudioCoreMacroValues = .defaults

    /// Sorgt dafür, dass die Ankunfts-Meldung genau einmal pro Sitzung kommt.
    private var hasLoggedFirstMacroUpdate = false

    // MARK: – Debug

    var debugLogging = true

    private func dbg(_ msg: String) {
        guard debugLogging else { return }
        print(String(format: "[AE %9.4f] %@", CACurrentMediaTime(), msg))
    }

    // MARK: – Init

    init() { setupGraph() }

    // MARK: – Graph-Aufbau

    private func setupGraph() {

        // ── 1. Alle statischen Nodes registrieren ────────────────────────────
        let allNodes: [AVAudioNode] = [
            gainChord,  gainBass,  gainMelody,  gainChordTone,
            compressorBass,   // CH 1 – zwischen gainBass und Delay-Sends
            delay1SendChord,      delay2SendChord,      delay3SendChord,
            delay1Chord,          delay2Chord,          delay3Chord,
            delay1SendBass,       delay2SendBass,       delay3SendBass,
            delay1Bass,           delay2Bass,           delay3Bass,
            delay1SendMelody,     delay2SendMelody,     delay3SendMelody,
            delay1Melody,         delay2Melody,         delay3Melody,
            delay1SendChordTone,  delay2SendChordTone,  delay3SendChordTone,
            delay1ChordTone,      delay2ChordTone,      delay3ChordTone,
            sumChord,  sumBass,  sumMelody,  sumChordTone,
            reverbChord, reverbBass, reverbMelody, reverbChordTone,
            sharedEchoSendBus, sharedSpaceSendBus
        ]
        for node in allNodes { engine.attach(node) }

        // ── 2. Chord-Pfad (CH 0) ─────────────────────────────────────────────
        engine.connect(gainChord, to: [
            AVAudioConnectionPoint(node: sumChord,        bus: 0),
            AVAudioConnectionPoint(node: delay1SendChord, bus: 0),
            AVAudioConnectionPoint(node: delay2SendChord, bus: 0),
            AVAudioConnectionPoint(node: delay3SendChord, bus: 0)
        ], fromBus: 0, format: nil)
        engine.connect(delay1SendChord, to: delay1Chord,  format: nil)
        engine.connect(delay2SendChord, to: delay2Chord,  format: nil)
        engine.connect(delay3SendChord, to: delay3Chord,  format: nil)
        engine.connect(delay1Chord,     to: sumChord,     format: nil)
        engine.connect(delay2Chord,     to: sumChord,     format: nil)
        engine.connect(delay3Chord,     to: sumChord,     format: nil)
        engine.connect(sumChord,        to: reverbChord,           format: nil)
        engine.connect(reverbChord,     to: engine.mainMixerNode,  format: nil)

        // ── 3. Bass-Pfad (CH 1) ───────────────────────────────────────────────
        //
        // Signalfluss:
        //   gainBass → compressorBass → [sumBass (Dry) + delay1/2/3SendBass]
        //                                     ↓                  ↓
        //                                  sumBass ←── delays ───┘
        //                                     ↓
        //                                 reverbBass → mainMixerNode
        engine.connect(gainBass, to: compressorBass, format: nil)
        engine.connect(compressorBass, to: [
            AVAudioConnectionPoint(node: sumBass,        bus: 0),
            AVAudioConnectionPoint(node: delay1SendBass, bus: 0),
            AVAudioConnectionPoint(node: delay2SendBass, bus: 0),
            AVAudioConnectionPoint(node: delay3SendBass, bus: 0)
        ], fromBus: 0, format: nil)
        engine.connect(delay1SendBass, to: delay1Bass,  format: nil)
        engine.connect(delay2SendBass, to: delay2Bass,  format: nil)
        engine.connect(delay3SendBass, to: delay3Bass,  format: nil)
        engine.connect(delay1Bass,     to: sumBass,     format: nil)
        engine.connect(delay2Bass,     to: sumBass,     format: nil)
        engine.connect(delay3Bass,     to: sumBass,     format: nil)
        engine.connect(sumBass,        to: reverbBass,           format: nil)
        engine.connect(reverbBass,     to: engine.mainMixerNode, format: nil)

        // ── 4. Melody-Pfad (CH 2) ─────────────────────────────────────────────
        engine.connect(gainMelody, to: [
            AVAudioConnectionPoint(node: sumMelody,        bus: 0),
            AVAudioConnectionPoint(node: delay1SendMelody, bus: 0),
            AVAudioConnectionPoint(node: delay2SendMelody, bus: 0),
            AVAudioConnectionPoint(node: delay3SendMelody, bus: 0)
        ], fromBus: 0, format: nil)
        engine.connect(delay1SendMelody, to: delay1Melody,  format: nil)
        engine.connect(delay2SendMelody, to: delay2Melody,  format: nil)
        engine.connect(delay3SendMelody, to: delay3Melody,  format: nil)
        engine.connect(delay1Melody,     to: sumMelody,     format: nil)
        engine.connect(delay2Melody,     to: sumMelody,     format: nil)
        engine.connect(delay3Melody,     to: sumMelody,     format: nil)
        engine.connect(sumMelody,        to: reverbMelody,         format: nil)
        engine.connect(reverbMelody,     to: engine.mainMixerNode, format: nil)

        // ── 5. ChordTone-Pfad (CH 3) ──────────────────────────────────────────
        //
        // Vollständig unabhängiger Kanalzug — keine Kopplung zu CH 0 (Chord).
        engine.connect(gainChordTone, to: [
            AVAudioConnectionPoint(node: sumChordTone,        bus: 0),
            AVAudioConnectionPoint(node: delay1SendChordTone, bus: 0),
            AVAudioConnectionPoint(node: delay2SendChordTone, bus: 0),
            AVAudioConnectionPoint(node: delay3SendChordTone, bus: 0)
        ], fromBus: 0, format: nil)
        engine.connect(delay1SendChordTone, to: delay1ChordTone,  format: nil)
        engine.connect(delay2SendChordTone, to: delay2ChordTone,  format: nil)
        engine.connect(delay3SendChordTone, to: delay3ChordTone,  format: nil)
        engine.connect(delay1ChordTone,     to: sumChordTone,     format: nil)
        engine.connect(delay2ChordTone,     to: sumChordTone,     format: nil)
        engine.connect(delay3ChordTone,     to: sumChordTone,     format: nil)
        engine.connect(sumChordTone,        to: reverbChordTone,        format: nil)
        engine.connect(reverbChordTone,     to: engine.mainMixerNode,   format: nil)

        // ── 5b. Gemeinsame Echo-/Space-Send-Busse (S-07a) ────────────────────
        //
        // Beide Busse sind an mainMixerNode angeschlossen, aber in dieser
        // Runde von keinem Kanal gespeist — kein Kanal verbindet sich hier
        // hinein. Stiller, vorbereiteter Graph-Rand fuer S-07b/S-08.
        engine.connect(sharedEchoSendBus,  to: engine.mainMixerNode, format: nil)
        engine.connect(sharedSpaceSendBus, to: engine.mainMixerNode, format: nil)

        // ── 6. Kompressor CH1 — Startwerte ───────────────────────────────────
        //
        // Parameter via AudioUnitSetParameter mit Raw-IDs (SDK-versionsunabhängig).
        // Benannte Konstanten (kDynamicsProcessorParam_*) wurden in neueren SDKs umbenannt;
        // Raw-Integer-IDs aus AudioToolbox/AudioUnitParameters.h sind stabil:
        //   ID 0 – Threshold      → −20 dB   (Range: −40…+20)
        //   ID 1 – HeadRoom       →   5 dB   (Range: 0.1…40)
        //   ID 2 – ExpansionRatio →   1.0    (Range: 1…50; 1.0 = kein Gate)
        //   ID 4 – AttackTime     →   0.020 s (Range: 0.0001…0.2)
        //   ID 5 – ReleaseTime    →   0.150 s (Range: 0.01…3.0)
        //   ID 6 – MasterGain     →  +6.0 dB (Range: −40…+40)
        let au = compressorBass.audioUnit
        AudioUnitSetParameter(au, 0, kAudioUnitScope_Global, 0, -20.0,  0)  // Threshold
        AudioUnitSetParameter(au, 1, kAudioUnitScope_Global, 0,   5.0,  0)  // HeadRoom
        AudioUnitSetParameter(au, 2, kAudioUnitScope_Global, 0,   1.0,  0)  // ExpansionRatio
        AudioUnitSetParameter(au, 4, kAudioUnitScope_Global, 0, 0.020,  0)  // AttackTime
        AudioUnitSetParameter(au, 5, kAudioUnitScope_Global, 0, 0.150,  0)  // ReleaseTime
        AudioUnitSetParameter(au, 6, kAudioUnitScope_Global, 0,   6.0,  0)  // MasterGain

        // ── 8. Delay wetDryMix = 100 % (alle vier Kanäle) ────────────────────
        for delay in [delay1Chord,      delay2Chord,      delay3Chord,
                      delay1Bass,       delay2Bass,       delay3Bass,
                      delay1Melody,     delay2Melody,     delay3Melody,
                      delay1ChordTone,  delay2ChordTone,  delay3ChordTone] as [AVAudioUnitDelay] {
            delay.wetDryMix = 100.0
        }

        // ── 7. Defaults anwenden ─────────────────────────────────────────────
        applyEffectConfigChord(.chordDefaults)
        applyEffectConfigBass(.bassDefaults)
        applyEffectConfigMelody(.melodyDefaults)
        applyEffectConfigChordTone(.chordToneDefaults)

        // ── 8. Engine starten ────────────────────────────────────────────────
        do {
            try engine.start()
            print("[AudioEngine] gestartet. isRunning=\(engine.isRunning)")
        } catch {
            print("[AudioEngine] start() fehlgeschlagen: \(error.localizedDescription)")
            return
        }

        // ── 9. SynthNodes einhängen (nach engine.start(), echte sampleRate) ──
        let sr         = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let sampleRate = sr > 0 ? sr : 44100.0

        synthChord.prepare(sampleRate: sampleRate, spaceSendBus: spaceSendBus)
        engine.attach(synthChord.sourceNode)
        engine.connect(synthChord.sourceNode, to: gainChord, format: nil)

        synthBass.prepare(sampleRate: sampleRate, spaceSendBus: spaceSendBus)
        engine.attach(synthBass.sourceNode)
        engine.connect(synthBass.sourceNode, to: gainBass, format: nil)

        synthMelody.prepare(sampleRate: sampleRate, spaceSendBus: spaceSendBus)
        engine.attach(synthMelody.sourceNode)
        engine.connect(synthMelody.sourceNode, to: gainMelody, format: nil)

        // CH3: synthChordTone → gainChordTone (eigenständiger Kanalzug)
        synthChordTone.prepare(sampleRate: sampleRate, spaceSendBus: spaceSendBus)
        engine.attach(synthChordTone.sourceNode)
        engine.connect(synthChordTone.sourceNode, to: gainChordTone, format: nil)

        // ── 10. Gemeinsame Raumkette einhängen (W-03c) ───────────────────────
        //
        // Ebenfalls erst nach engine.start(), aus demselben Grund wie die
        // SynthNodes: die Kette wird für die echte Sample Rate bemessen.
        // Attach/Connect laufen hier auf dem Aufrufer-Thread des Graph-Aufbaus,
        // nie aus einem Rendercallback.
        deepSpaceReturn.prepare(sampleRate: sampleRate)
        engine.attach(deepSpaceReturn.sourceNode)
        engine.connect(deepSpaceReturn.sourceNode, to: sharedSpaceSendBus, format: nil)

        isReady = true
        print("[AudioEngine] Bereit. sampleRate=\(sampleRate)  4 unabhängige Kanäle: CH0=synthChord  CH1=synthBass  CH2=synthMelody  CH3=synthChordTone")
    }

    // MARK: – SynthParams-Mapping
    //
    // Leitet Klangparameter aus ChannelFXConfig an SynthNode weiter.
    // Die Mapping-Logik liegt ausschließlich hier — SynthNode/AudioCoreVoice werten
    // ChannelFXConfig nicht aus.
    //
    // Attack: quadratische Kurve (Slider 0…1 → 1…2001 ms).
    //   Musikalische Begründung: kurze Attacks (1–50 ms) sind klanglich entscheidend;
    //   eine lineare Skala gibt ihnen nur 2.5 % des Slider-Weges.
    //   Quadratisch: erste 22 % des Sliders decken 0–100 ms ab (statt 0–440 ms).
    //   Formel: attackMs = attack² × 2000 + 1
    //
    // Decay / Release: lineare Umrechnung (Slider in physikalischen Sekunden).
    //   Slider-Range ist bereits in echten Zeiteinheiten (s), keine Kurve nötig —
    //   Anzeige und Verhalten bleiben konsistent: "0.500s" = 500ms.
    //
    // Sustain: linear (0…1), perceptuell korrekt.
    //
    // filterCutoff / filterResonance / waveform / unisonVoices / unisonDetune / unisonSpread:
    //   direkt übergeben (keine Transformation nötig).
    //
    // pan (Block A): wirkt nicht via SynthParams, sondern direkt auf gainX.pan (Mixer-Layer).

    private func synthParams(from cfg: ChannelFXConfig) -> SynthParams {
        // Attack: quadratische Kurve — feine Auflösung im musikalisch wichtigen Kurzbereich.
        let attackMs = max(1.0, pow(cfg.attack, 2.0) * 2000.0 + 1.0)

        return SynthParams(
            waveform:        cfg.waveform,
            attackMs:        attackMs,
            decayMs:         max(1.0,  cfg.decay   * 1000.0),
            sustain:         max(0.0,  min(cfg.sustain, 1.0)),
            releaseMs:       max(50.0, cfg.release * 1000.0),
            maxVoices:       16,
            filterCutoff:    max(0.0,  min(cfg.filterCutoff,    1.0)),
            filterResonance: max(0.0,  min(cfg.filterResonance, 1.0)),
            unisonVoices:    max(1,    cfg.unisonVoices),
            unisonDetune:    max(0.0,  cfg.unisonDetune),
            unisonSpread:    max(0.0,  min(cfg.unisonSpread, 1.0)),
            voiceEngine:     voiceEngine,
            // Space-Send (W-03c): Basispegel und Kanalfader getrennt — siehe
            // SynthParams. `spaceSendChannelGain` ist derselbe lineare
            // Faderwert, der unten auf `gainX.outputVolume` geht; damit ist
            // der Send post-fader wie ein Abgriff hinter dem Kanal-Gain
            // (`AudioGraphSendTopology`: `postGain`).
            spaceSend:            AudioEngine.provisionalSpaceSendLevel,
            spaceSendChannelGain: linearVolume(cfg.channelVolume),
            // Performance-Makros (W-05): global, nicht Teil der ChannelFXConfig.
            macros:               currentMacros
        )
    }

    /// Übergibt einen SynthParams-Snapshot an einen Kanal — serialisiert über
    /// commandQueue, wie alle SynthNode-Queue-Schreibzugriffe (F-02).
    private func pushSynthParams(from cfg: ChannelFXConfig, to synth: SynthNode) {
        let params = synthParams(from: cfg)
        commandQueue.async { synth.updateParams(params) }
    }

    // MARK: – Stimmtyp umschalten (W-03b1)
    //
    // Der Wechsel reist als Feld im SynthParams-Snapshot. Weil der
    // `guard cfg != lastXCfg`-Cache unten sonst genau dieses Update schluckt
    // (die ChannelFXConfig hat sich ja nicht geändert), werden die vier
    // Snapshots hier direkt neu gebildet und gesendet — an der Cache-Logik
    // vorbei, aber über denselben commandQueue-Weg.
    //
    // Vor dem ersten applyEffectConfig* ist noch kein Kanal konfiguriert;
    // dann genügt das gesetzte Feld, weil der nächste applyEffectConfig* den
    // neuen Wert ohnehin mitträgt.

    func applyVoiceEngine(_ engine: SynthVoiceEngine) {
        guard engine != voiceEngine else { return }
        voiceEngine = engine
        dbg("voiceEngine → \(engine)")

        if let cfg = lastChordCfg     { pushSynthParams(from: cfg, to: synthChord) }
        if let cfg = lastBassCfg      { pushSynthParams(from: cfg, to: synthBass) }
        if let cfg = lastMelodyCfg    { pushSynthParams(from: cfg, to: synthMelody) }
        if let cfg = lastChordToneCfg { pushSynthParams(from: cfg, to: synthChordTone) }
    }

    // MARK: – Performance-Makros anwenden (W-05)
    //
    // Derselbe Bau wie `applyVoiceEngine` und aus demselben Grund: die vier
    // Snapshots werden direkt neu gebildet, weil der `guard cfg != lastXCfg`-
    // Cache in applyEffectConfig* genau dieses Update schlucken würde — die
    // ChannelFXConfig hat sich ja nicht geändert. Der Weg über commandQueue
    // bleibt derselbe, der SPSC-Vertrag damit unberührt.
    //
    // ── Warum GENAU VIER paramUpdate-Ereignisse je Aufruf ────────────────
    //
    // Eines pro SynthNode, weil jeder Kanal seine eigene NoteEventQueue hat.
    // Das ist zugleich der Multiplikator, der die CC-Flut aus Teil 3 des
    // Handoffs gefährlich macht: ein ungebremster CC-Strom von 127 Werten pro
    // Sekunde und Regler erzeugt hier 508 paramUpdates pro Sekunde, bei vier
    // gleichzeitig bewegten Reglern 2.032. Jedes davon lässt
    // `VoicePool.applyParams` im Audio-Callback über bis zu 16 Stimmen
    // laufen. Die Drosselung sitzt deshalb VOR dieser Methode, im
    // `MIDIMacroCoalescer` — hier wird bewusst nicht noch einmal gefiltert,
    // damit es genau eine Stelle mit dieser Verantwortung gibt.
    //
    // Nur vom Main Thread aufrufen.

    func applyMacroValues(_ macros: AudioCoreMacroValues) {
        guard macros != currentMacros else { return }
        currentMacros = macros

        // GENAU EINMAL pro Sitzung. Ausdrücklich kein Log pro Update: bei bis
        // zu 50 Ausgaben pro Sekunde wäre das eine zweite Flut, diesmal auf
        // stdout. Die eine Zeile beantwortet die Frage, die man am Instrument
        // wirklich hat — „kommt mein Regler überhaupt an?" — und schweigt
        // danach.
        if !hasLoggedFirstMacroUpdate {
            hasLoggedFirstMacroUpdate = true
            dbg("Makro-Eingang aktiv (erste CC-Zuweisung angekommen)")
        }

        if let cfg = lastChordCfg     { pushSynthParams(from: cfg, to: synthChord) }
        if let cfg = lastBassCfg      { pushSynthParams(from: cfg, to: synthBass) }
        if let cfg = lastMelodyCfg    { pushSynthParams(from: cfg, to: synthMelody) }
        if let cfg = lastChordToneCfg { pushSynthParams(from: cfg, to: synthChordTone) }
    }

    // MARK: – Volume-Mapping (logarithmisch)
    //
    // AVAudioMixerNode.outputVolume ist eine lineare Amplitude-Skala.
    // Lineares Mapping von UI-Wert (0…1) auf Amplitude ist psychoakustisch falsch:
    // Das Ohr arbeitet logarithmisch; 50 % linear klingt wie ca. −20 dB, nicht wie −6 dB.
    //
    // dB-basiertes Mapping: UI-Wert 0…1 → −60 dB … 0 dB → lineare Amplitude.
    //   volume = 0.0 → −60 dB → Amplitude ≈ 0 (praktisch stumm)
    //   volume = 0.5 → −30 dB → Amplitude ≈ 0.032 (halber Weg klingt wie −30 dB)
    //   volume = 1.0 →   0 dB → Amplitude = 1.0
    //
    // Kein Mapping-Bruch für bestehende Presets: Default-Werte (0.80, 0.85, 0.90)
    // liegen im Bereich −12 dB … −6 dB → praxisgerechte Arbeitspegel.
    //
    // Die UI zeigt weiterhin 0…100 % (keine Änderung an AppSettings oder PanelSlider).
    // Das Mapping liegt ausschließlich hier.

    private func linearVolume(_ v: Float) -> Float {
        let clamped: Float = max(0.0, min(v, 1.0))
        guard clamped > 0.0 else { return 0.0 }   // volume=0 → exakt stumm
        let minDb: Float = -60.0
        let db = minDb + (-minDb) * clamped        // −60 … 0 dB
        return pow(10.0, db / 20.0)
    }

    // MARK: – Effektkonfiguration

    func applyEffectConfigChord(_ cfg: ChannelFXConfig) {
        guard cfg != lastChordCfg else { return }
        lastChordCfg = cfg
        gainChord.outputVolume = linearVolume(cfg.channelVolume)
        gainChord.pan          = max(-1, min(cfg.pan, 1))
        applyFX(cfg,
                send1: delay1SendChord, delay1: delay1Chord,
                send2: delay2SendChord, delay2: delay2Chord,
                send3: delay3SendChord, delay3: delay3Chord,
                reverb: reverbChord)
        pushSynthParams(from: cfg, to: synthChord)
    }

    func applyEffectConfigBass(_ cfg: ChannelFXConfig) {
        guard cfg != lastBassCfg else { return }
        lastBassCfg = cfg
        gainBass.outputVolume = linearVolume(cfg.channelVolume)
        gainBass.pan          = max(-1, min(cfg.pan, 1))   // Bass sollte typischerweise zentriert bleiben
        applyFX(cfg,
                send1: delay1SendBass, delay1: delay1Bass,
                send2: delay2SendBass, delay2: delay2Bass,
                send3: delay3SendBass, delay3: delay3Bass,
                reverb: reverbBass)
        pushSynthParams(from: cfg, to: synthBass)
    }

    func applyEffectConfigMelody(_ cfg: ChannelFXConfig) {
        guard cfg != lastMelodyCfg else { return }
        lastMelodyCfg = cfg
        gainMelody.outputVolume = linearVolume(cfg.channelVolume)
        gainMelody.pan          = max(-1, min(cfg.pan, 1))
        applyFX(cfg,
                send1: delay1SendMelody, delay1: delay1Melody,
                send2: delay2SendMelody, delay2: delay2Melody,
                send3: delay3SendMelody, delay3: delay3Melody,
                reverb: reverbMelody)
        pushSynthParams(from: cfg, to: synthMelody)
    }

    func applyEffectConfigChordTone(_ cfg: ChannelFXConfig) {
        guard cfg != lastChordToneCfg else { return }
        lastChordToneCfg = cfg
        gainChordTone.outputVolume = linearVolume(cfg.channelVolume)
        gainChordTone.pan          = max(-1, min(cfg.pan, 1))
        applyFX(cfg,
                send1: delay1SendChordTone, delay1: delay1ChordTone,
                send2: delay2SendChordTone, delay2: delay2ChordTone,
                send3: delay3SendChordTone, delay3: delay3ChordTone,
                reverb: reverbChordTone)
        pushSynthParams(from: cfg, to: synthChordTone)
    }

    private func applyFX(_ cfg: ChannelFXConfig,
                          send1: AVAudioMixerNode, delay1: AVAudioUnitDelay,
                          send2: AVAudioMixerNode, delay2: AVAudioUnitDelay,
                          send3: AVAudioMixerNode, delay3: AVAudioUnitDelay,
                          reverb: AVAudioUnitReverb) {
        send1.outputVolume = max(0, min(cfg.delay1Mix, 1))
        send1.pan          = max(-1, min(cfg.delay1Pan, 1))
        delay1.delayTime   = Double(max(0.001, min(cfg.delay1Time, 2.0)))
        delay1.feedback    = max(0, min(cfg.delay1Feedback, 1)) * 100.0

        send2.outputVolume = max(0, min(cfg.delay2Mix, 1))
        send2.pan          = max(-1, min(cfg.delay2Pan, 1))
        delay2.delayTime   = Double(max(0.001, min(cfg.delay2Time, 2.0)))
        delay2.feedback    = max(0, min(cfg.delay2Feedback, 1)) * 100.0

        send3.outputVolume = max(0, min(cfg.delay3Mix, 1))
        send3.pan          = max(-1, min(cfg.delay3Pan, 1))
        delay3.delayTime   = Double(max(0.001, min(cfg.delay3Time, 2.0)))
        delay3.feedback    = max(0, min(cfg.delay3Feedback, 1)) * 100.0

        let key = ObjectIdentifier(reverb)
        if cachedReverbPreset[key] != cfg.reverbPreset {
            let preset = AVAudioUnitReverbPreset(rawValue: cfg.reverbPreset) ?? .largeHall
            reverb.loadFactoryPreset(preset)
            cachedReverbPreset[key] = cfg.reverbPreset
        }
        reverb.wetDryMix = max(0, min(cfg.reverbMix * 100.0, 100.0))
    }
}

// MARK: – AudioOutput-Konformanz

extension AudioEngine {

    /// Löst den Kanal-Index auf die zuständige SynthNode-Instanz auf.
    /// Reiner Lookup, kein Zugriff auf Queue-Zustand — sicher vom Aufrufer-Thread.
    private func synthNode(forChannel channel: Int) -> SynthNode? {
        switch channel {
        case 0: return synthChord
        case 1: return synthBass
        case 2: return synthMelody
        case 3: return synthChordTone
        default: return nil
        }
    }

    // Alle vier commandQueue.async-Aufrufe unten fangen bewusst nur die konkrete
    // SynthNode-Referenz ein, nicht `self` — vermeidet Sendable-Warnungen für
    // `AudioEngine` (nicht Sendable, viele weitere gecachte Properties, nicht
    // Teil dieses Slices) ohne die eigentliche Serialisierungsgrenze zu ändern.
    // dbg() läuft bewusst synchron auf dem Aufrufer-Thread (Log-Zeitpunkt =
    // Request-Zeitpunkt, nicht Ausführungszeitpunkt auf commandQueue).

    func noteOn(channel: Int, note: UInt8, velocity: UInt8) {
        guard isReady, let synth = synthNode(forChannel: channel) else { return }
        dbg("noteOn   ch=\(channel)  note=\(note)  vel=\(velocity)")
        commandQueue.async { synth.noteOn(note: note, velocity: velocity) }
    }

    func noteOff(channel: Int, note: UInt8) {
        guard isReady, let synth = synthNode(forChannel: channel) else { return }
        dbg("noteOff  ch=\(channel)  note=\(note)")
        commandQueue.async { synth.noteOff(note: note) }
    }

    func allNotesOff(channel: Int) {
        guard isReady, let synth = synthNode(forChannel: channel) else { return }
        dbg("allNotesOff  ch=\(channel)")
        commandQueue.async { synth.allNotesOff() }
    }

    func allNotesOff() {
        guard isReady else { return }
        dbg("allNotesOff  alle Kanäle")
        let synths = [synthChord, synthBass, synthMelody, synthChordTone]
        commandQueue.async {
            for synth in synths { synth.allNotesOff() }
        }
    }

    func applyFXConfig(_ cfg: ChannelFXConfig, channel: Int) {
        switch channel {
        case 0: applyEffectConfigChord(cfg)
        case 1: applyEffectConfigBass(cfg)
        case 2: applyEffectConfigMelody(cfg)
        case 3: applyEffectConfigChordTone(cfg)
        default: break
        }
    }
}
