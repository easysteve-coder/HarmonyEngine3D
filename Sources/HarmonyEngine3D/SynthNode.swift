import Foundation
import AVFoundation
import HarmonyAudioCore

// MARK: – SynthNode
//
// Virtuell-analoger Synthesizer-Kern für einen Audio-Kanal.
//
// Aufbau:
//   AVAudioSourceNode (sourceNode)  ← Audio-Graph-Knoten, an Engine angehängt
//   VoicePool                       ← zwei gleichzeitig vorgehaltene Pools à N Stimmen
//                                      (AudioCoreVoice und AudioCoreAtmosphericVoice,
//                                      HarmonyAudioCore), exklusiv auf Audio-Thread.
//                                      Es rendert immer nur einer — welcher, sagt
//                                      SynthParams.voiceEngine (W-03b1). Der
//                                      Produkt-Default ist seit W-03b2
//                                      .atmospheric und kommt aus AppSettings.
//   NoteEventQueue                  ← SPSC-Ringpuffer, Main Thread → Audio-Thread
//
// Threading (korrigiert, Runde 016 / F-02):
//   noteOn / noteOff / allNotesOff / updateParams  → aufrufbar von jedem Thread,
//     schreiben aber nur dann sicher in NoteEventQueue, wenn der Aufrufer bereits
//     auf AudioEngine.commandQueue läuft — SynthNode selbst serialisiert nicht.
//     AudioEngine ist die alleinige Serialisierungsgrenze (einziger erlaubter
//     Aufrufer dieser vier Methoden ist commandQueue). Vorher fälschlich als
//     "Main Thread" dokumentiert — real riefen der SceneKit-Render-Thread
//     (Akkord-/Bass-/Melodie-Events) und der GameController-Handler-Thread
//     (CH3) direkt in dieselbe Queue, parallel zum Main-Thread-paramUpdate via
//     Combine — ein echter Datenrace auf writeIndex, kein reines Doku-Problem.
//   Render-Closure                                 → Audio-Thread → liest Events, rendert Voices
//   Kein Lock im Audio-Pfad (lock-free via SPSC-Queue, OSMemoryBarrier).
//   Keine Heap-Allokation in der Render-Closure.
//   Kein Swift Concurrency, kein AppSettings-Zugriff.
//
// Polyphonie, ADSR und Live-Parameter:
//   Eigenschaften des SynthNode (via SynthParams), nicht der AudioEngine.
//   Die Engine übergibt SynthParams beim prepare()-Aufruf und interpretiert ihn nicht.
//   maxVoices: bestimmt die Größe des Voice-Pools (fixiert nach prepare()).
//   Filter Cutoff/Resonance + Sustain: LIVE — updateParams() wirkt sofort auf aktive Voices.
//   Attack/Decay/Release + Waveform: Snapshot — wirken ab nächster NoteOn.
//
// Integration:
//   AudioEngine.setupGraph() hängt sourceNode nach engine.start() in den Graph.
//   Jeder der vier Kanäle (Chord, Bass, Melody, ChordTone) hat eine eigene Instanz.

// @unchecked Sendable: SynthNode selbst synchronisiert nichts — die Sicherheit
// kommt ausschließlich aus dem Aufrufer-Vertrag "nur von AudioEngine.commandQueue
// aufzurufen" (siehe Threading-Dokumentation oben). Der Compiler kann diesen
// Vertrag nicht prüfen; er wird strukturell erzwungen (AudioEngine ist die
// einzige Stelle, die SynthNode-Referenzen hält und ihre Methoden aufruft, immer
// über commandQueue). Ermöglicht `commandQueue.async { synth.noteOn(...) }` ohne
// `self`-Capture in AudioEngine (siehe dort) — kein Sendable-Zwang auf AudioEngine
// selbst, keine breite Swift-6-Bereinigung.
final class SynthNode: @unchecked Sendable {

    // MARK: – Öffentlicher Audio-Graph-Knoten
    //
    // Gültig nach prepare(). Wird von AudioEngine.setupGraph() an die Engine angehängt.

    private(set) var sourceNode: AVAudioSourceNode!

    // MARK: – Interne Komponenten

    private let queue = NoteEventQueue()

    // pool: nil bis prepare(). Wird in prepare() mit den übergebenen SynthParams aufgebaut.
    private var pool: VoicePool!

    // MARK: – VoicePool (Audio-Thread-exklusiv nach prepare())
    //
    // Voice-Arrays und SynthParams werden ausschließlich vom Audio-Thread modifiziert.
    // Main Thread kommuniziert ausschließlich via NoteEventQueue.
    //
    // ── Zwei Stimmtypen, ein Renderpfad (W-03b1) ──────────────────────────────
    //
    // Der Pool hält BEIDE Stimmtypen gleichzeitig vor — `legacyVoices` und
    // `atmosphericVoices`, beide in Poolgröße, beide in `init` aufgebaut. Es
    // rendert immer nur genau einer; `activeEngine` sagt welcher. Die
    // Begründung dieser Bauform gegenüber Protokoll-Boxing, Payload-Enum und
    // generischer Spezialisierung steht vollständig in `SynthVoiceEngine.swift`.
    //
    // Für den Renderpfad heißt das: eine Verzweigung PRO BLOCK auf ein
    // Int-Tag, danach eine monomorphe Schleife über ein Array eines konkreten
    // Structs. Kein Existential, keine Witness Table, keine Allokation, keine
    // Umkonfiguration von Pools aus dem Rendercallback heraus — der Wechsel
    // flippt nur das Tag (siehe `switchEngine`).
    //
    // ── Invariante: höchstens ein Pool klingt ────────────────────────────────
    //
    // `switchEngine` bringt BEIDE Pools hart auf `idle`, bevor es das Tag
    // umlegt. Daraus folgt: der inaktive Pool enthält nie eine aktive Stimme.
    // `noteOff`, `allNotesOff`, `isSilent` und `render` dürfen sich deshalb
    // ausschließlich auf den aktiven Pool beziehen, ohne eine Note im anderen
    // Pool hängen zu lassen.
    //
    // ── Space-Send pro Stimme (W-03c) ────────────────────────────────────────
    //
    // Die Atmospheric Voice exponiert `spaceSendLevel` — wie viel SIE in den
    // gemeinsamen Raum schicken will (Modulationsziel, siehe
    // AudioCoreAtmosphericVoice). Der Wert existiert nur hier, vor der
    // Summierung der Stimmen; deshalb entsteht der Send in diesem Pool und
    // nicht im Audiograph (vollständige Begründung in SpaceSendBus.swift).
    //
    // Umsetzung: jede aktive Atmospheric-Stimme rendert in einen
    // Zwischenpuffer; von dort geht ihr Signal unverändert in die
    // Kanalsumme UND gewichtet in den Sammelbus.
    //
    // Der Umweg über den Zwischenpuffer verändert die Kanalsumme nicht: der
    // Puffer wird vor jeder Stimme genullt, die Stimme addiert hinein, und
    // das Ergebnis wird in derselben Stimmreihenfolge auf die Summe addiert.
    // Es sind dieselben Additionen in derselben Reihenfolge wie beim direkten
    // Rendern in die Summe — bitgenau, nicht nur numerisch nahe. Nachgewiesen
    // in `DeepSpaceSendTests`.
    //
    // Der Legacy-Pfad bleibt vollständig unberührt: die Legacy-Voice hat kein
    // Space-Send-Ziel, rendert weiterhin direkt in die Summe und speist den
    // Raum nicht.

    private final class VoicePool {

        // Seit S-02b rendert der Pool ueber `AudioCoreVoice`
        // (`HarmonyAudioCore`) statt einer zweiten DSP-Kopie. `SynthParams`
        // bleibt das App-seitige Parametermodell; die Core-Uebersetzung
        // passiert punktuell ueber `SynthParams.audioCoreParameters`
        // (`AudioCoreMapping.swift`).
        var legacyVoices: [AudioCoreVoice]

        // Zweiter, gleich großer Pool (W-03b1). Wird in `init` vollständig
        // aufgebaut und danach nie neu alloziert.
        var atmosphericVoices: [AudioCoreAtmosphericVoice]

        // Welcher der beiden Pools rendert. Ausschließlich auf dem
        // Audio-Thread gelesen und geschrieben (aus applyParams heraus).
        private(set) var activeEngine: SynthVoiceEngine

        // SynthParams: hält ADSR und maxVoices. Einmalig beim init gesetzt,
        // danach nur noch über applyParams() aus der Render-Closure aktualisiert.
        var params: SynthParams

        // Gecachte Core-Parameter der Atmospheric Voice. Wird ausschließlich in
        // `init` und `applyParams` neu gebildet — also nie pro Sample und nie
        // pro Block, sondern nur beim Verarbeiten eines paramUpdate-Events.
        private var atmosphericParams: AudioCoreAtmosphericVoiceParameters

        // sampleRate: einmalig von prepare() gesetzt, danach unveränderlich.
        let sampleRate: Double

        // Monoton steigender Zähler für Voice-Stealing (Audio-Thread-exklusiv).
        private var voiceTimestamp: UInt64 = 0

        // MARK: – Space-Send (W-03c)

        // Gemeinsamer Sammelbus zur DeepSpace-Kette. `nil` heißt "dieser Kanal
        // speist keinen Raum" — der Fall im Offline-Harness und in allen
        // Baseline-Tests, die den Trockenpfad messen.
        private let spaceSendBus: SpaceSendBus?

        // Zwischenpuffer für genau EINE Stimme, in `init` angelegt und nie im
        // Rendercallback. Zwei getrennte Kanäle, weil die Stimme stereo
        // schreibt.
        private let scratchL: UnsafeMutablePointer<Float>
        private let scratchR: UnsafeMutablePointer<Float>
        private let scratchCapacity: Int

        // Sendpegel jeder Atmospheric-Stimme am Ende des vorherigen Blocks —
        // Startwert der Pegelrampe dieses Blocks (siehe
        // SpaceSendBus.accumulate). Feste Länge = Poolgröße, in `init`
        // angelegt.
        private var previousSendLevels: [Float]

        // sampleRate ist hier bewusst ein init-Parameter (vorher nachträglich
        // gesetzt): die Atmospheric Voice ist ratenabhängig aufgebaut und
        // braucht die echte Rate schon bei ihrer Konstruktion.
        //
        // Runde-068-Lehre (aufgeschobene Allokation durch faule `static let`-
        // Initialisierung): dieser init berührt bewusst ALLE lazy Statics, die
        // der Renderpfad später anfassen kann — `AudioCoreWavetableBank`
        // (über den Voice-init), `AudioCoreAtmosphericVoiceParameters.defaults`
        // und `.defaultModulationMatrix` (über das Parameter-Mapping). Damit
        // ist ihr `swift_once` garantiert vor dem ersten Rendercallback
        // abgeschlossen, außerhalb des Audio-Threads.
        init(params: SynthParams, sampleRate: Double, spaceSendBus: SpaceSendBus?) {
            self.params = params
            self.sampleRate = sampleRate
            self.activeEngine = params.voiceEngine
            let count = max(1, params.maxVoices)
            self.legacyVoices = [AudioCoreVoice](repeating: AudioCoreVoice(), count: count)
            self.atmosphericParams = params.atmosphericVoiceParameters
            self.atmosphericVoices = [AudioCoreAtmosphericVoice](
                repeating: AudioCoreAtmosphericVoice(sampleRate: sampleRate, parameters: self.atmosphericParams),
                count: count
            )

            self.spaceSendBus = spaceSendBus
            self.previousSendLevels = [Float](repeating: 0, count: count)
            // Kapazität immer anlegen, auch ohne Bus: der Renderpfad der
            // Atmospheric Voice läuft dann durch denselben Zwischenpuffer und
            // damit durch dieselbe Arithmetik. Ein zweiter, nur im Test
            // benutzter Renderpfad würde genau den Nachweis entwerten, den die
            // Baselines liefern sollen.
            self.scratchCapacity = SpaceSendBus.frameCapacity
            self.scratchL = UnsafeMutablePointer<Float>.allocate(capacity: scratchCapacity)
            self.scratchR = UnsafeMutablePointer<Float>.allocate(capacity: scratchCapacity)
            self.scratchL.initialize(repeating: 0, count: scratchCapacity)
            self.scratchR.initialize(repeating: 0, count: scratchCapacity)
        }

        deinit {
            scratchL.deinitialize(count: scratchCapacity)
            scratchR.deinitialize(count: scratchCapacity)
            scratchL.deallocate()
            scratchR.deallocate()
        }

        /// Poolgröße. Beide Arrays sind per Konstruktion gleich groß.
        var voiceCount: Int { legacyVoices.count }

        // MARK: – Parameter-Update (Audio-Thread, aus Render-Closure)
        //
        // Übernimmt neue SynthParams synchron im Event-Loop des Render-Callbacks.
        //
        // ── Determinismus-Garantie ────────────────────────────────────────────
        //
        // Die Render-Closure verarbeitet alle queued Events in strikter FIFO-Reihenfolge
        // (Schritt 1), bevor der erste DSP-Sample berechnet wird (Schritt 2).
        // Daraus folgt:
        //   – applyParams() setzt VoicePool.params atomar und vollständig, bevor
        //     irgendein noteOn in derselben Queue-Batch die Params liest.
        //   – Ein paramUpdate, der im Main Thread vor einem noteOn in die Queue
        //     geschrieben wurde (FIFO garantiert durch NoteEventQueue), gilt auch
        //     für dieses noteOn — im selben Render-Callback.
        //   – Kein teilweiser oder halb-wirksamer Zustand: die Zuweisung ist ein
        //     einzelner Struct-Wert-Schreibzugriff, kein Multi-Step-Update.
        //
        // ── Alleiniger Schreiber ──────────────────────────────────────────────
        //
        // VoicePool.params wird ausschließlich hier und ausschließlich auf dem
        // Audio-Thread geschrieben. Kein Lock nötig.
        //
        // ── Live-Parameter vs. Snapshot-Semantik ─────────────────────────────
        //
        // Filter (Cutoff/Resonance): LIVE auf laufende Voices.
        //   Analog-Verhalten: Filter-Sweep wirkt sofort auf alle klingenden Noten.
        //   Neue Biquad-Koeffizienten werden auf alle aktiven Voices übertragen.
        //   Filter-State (S1/S2) wird NICHT zurückgesetzt → kein Knack-Artefakt
        //   bei glattem Sweep. Der State konvergiert innerhalb weniger Samples.
        //
        // Sustain-Level: LIVE auf Voices in Sustain-Stage.
        //   Volume-Regelung eines gehaltenen Tons wirkt sofort.
        //
        // Attack/Decay/Release: Snapshot-Semantik (by design).
        //   Rationale: Bei einer gehaltenen Note sind A/D bereits abgelaufen;
        //   eine rückwirkende Rate-Änderung wäre ohne klanglich sinnvollen Effekt.
        //   Release wird beim NoteOff angewendet — der dann aktuelle Wert aus params
        //   ist zu diesem Zeitpunkt bereits korrekt (nächstes noteOn übernimmt neue Rate).
        //
        // Waveform: Snapshot-Semantik (by design).
        //   Waveform-Wechsel mid-note klingt mechanisch; Änderung ab nächster NoteOn
        //   ist das erwartete Verhalten.
        //
        // maxVoices: kein Effekt (Voice-Array nach prepare() fixiert).

        func applyParams(_ newParams: SynthParams) {
            let prevCutoff    = params.filterCutoff
            let prevResonance = params.filterResonance
            let prevSustain   = params.sustain
            let prevEngine    = params.voiceEngine
            params = newParams

            // ── Live-Filter: Biquad-Koeffizienten sofort auf alle aktiven Voices ──
            //
            // Nur wenn sich Cutoff oder Resonanz tatsächlich geändert haben,
            // um unnötige trig()-Berechnungen pro Frame zu vermeiden.
            if newParams.filterCutoff != prevCutoff || newParams.filterResonance != prevResonance {
                let (b0, b1, b2, a1, a2) = AudioCoreVoice.calcBiquadLowpassCoefficients(
                    cutoff:     newParams.filterCutoff,
                    resonance:  newParams.filterResonance,
                    sampleRate: sampleRate
                )
                for i in 0..<legacyVoices.count where legacyVoices[i].isActive {
                    // filterS1/S2 werden NICHT zurückgesetzt: kontinuierlicher State
                    // konvergiert bei glattem Sweep innerhalb weniger Samples.
                    legacyVoices[i].updateLowpassCoefficients(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2)
                }
            }

            // ── Live-Sustain: Sofort auf alle Voices in Sustain-Stage ────────
            if newParams.sustain != prevSustain {
                let clamped = max(0.0, min(newParams.sustain, 1.0))
                for i in 0..<legacyVoices.count {
                    // applySustainIfInSustain() greift intern nur, wenn stage == .sustain.
                    legacyVoices[i].applySustainIfInSustain(level: clamped)
                }
            }

            // ── Atmospheric: neuer Parametersatz auf klingende Stimmen ───────
            //
            // Gegenstück zum Live-Filter oben. `setParameters` der Atmospheric
            // Voice lässt den laufenden Klangzustand (Phasen, Filterzustand,
            // Hüllenstand) unberührt und gleitet über die eigenen Smoother —
            // deshalb genügt hier ein Aufruf statt getrennter Filter-/
            // Sustain-Pfade. Der Vergleich verhindert Arbeit, wenn sich am
            // abgebildeten Satz nichts geändert hat.
            let newAtmosphericParams = newParams.atmosphericVoiceParameters
            if newAtmosphericParams != atmosphericParams {
                atmosphericParams = newAtmosphericParams
                for i in 0..<atmosphericVoices.count where atmosphericVoices[i].isActive {
                    atmosphericVoices[i].setParameters(newAtmosphericParams)
                }
            }

            // ── Stimmtyp-Wechsel ─────────────────────────────────────────────
            //
            // Zuletzt, damit ein Wechsel nicht mit einem Parameterupdate
            // desselben Events um die Reihenfolge konkurriert: erst wirken die
            // neuen Parameter auf den bisherigen Pool, dann wird umgeschaltet
            // (und dabei ohnehin alles stillgelegt).
            if newParams.voiceEngine != prevEngine {
                switchEngine(to: newParams.voiceEngine)
            }
        }

        // MARK: – Stimmtyp-Wechsel (Audio-Thread, aus Render-Closure)
        //
        // Baut NICHTS auf: beide Pools existieren seit `init`. Der Wechsel
        // besteht aus einem kontrollierten All-Off und dem Umlegen des Tags.
        //
        // Warum hartes Stilllegen statt `triggerRelease()`: eine Stimme des
        // abgewählten Pools würde nicht mehr gerendert und käme deshalb nie
        // aus ihrer Release-Phase heraus — sie bliebe für immer `isActive`
        // und würde bei einem Rückwechsel mitten im Ton wieder auftauchen.
        // Genau das ist die hängende Note, die Gate 6 ausschließt. Der harte
        // Weg ist zugleich der einzige, der die Pool-Invariante herstellt
        // ("der inaktive Pool enthält nie eine aktive Stimme").
        //
        // Der Preis ist ein abrupter Schnitt statt eines Ausklingens. Das ist
        // bewusst und entspricht der Handoff-Vorgabe "kein Umschalten mitten
        // im Ton": ein Stimmtyp-Wechsel ist kein musikalischer Vorgang,
        // sondern eine Konfigurationsänderung.
        //
        // Allokationsfrei: `AudioCoreVoice()` ist ein reiner Skalar-Struct
        // (kein Referenzfeld), die Zuweisung ist ein Store. Die Atmospheric
        // Voice wird über ihr eigenes, in W-01 als allokationsfrei belegtes
        // `reset()` stillgelegt — nicht neu konstruiert.
        private func switchEngine(to newEngine: SynthVoiceEngine) {
            guard newEngine != activeEngine else { return }
            silenceAllVoices()
            activeEngine = newEngine
        }

        /// Bringt BEIDE Pools sofort auf `idle` — kein Release, kein Ausklingen.
        private func silenceAllVoices() {
            for i in 0..<legacyVoices.count {
                legacyVoices[i] = AudioCoreVoice()
            }
            for i in 0..<atmosphericVoices.count {
                atmosphericVoices[i].reset()
                // Mit der Stimme verstummt auch ihr Sendanteil; der
                // Rampenstart des nächsten Blocks darf nicht auf dem alten
                // Pegel stehenbleiben.
                previousSendLevels[i] = 0
            }
        }

        // MARK: – Event-Verarbeitung (Audio-Thread)

        func noteOn(note: UInt8, velocity: UInt8) {
            // ── Unison-Voice-Erzeugung ────────────────────────────────────────
            //
            // Für jede Unison-Voice wird eine eigene AudioCoreVoice mit individuellem
            // Detune-Offset (Cent) und Stereo-Pan-Position erzeugt.
            //
            // Anzahl: max. min(unisonVoices, voicePool-Größe), mindestens 1.
            // gainScale: 1/sqrt(n) → energie-normierte Gesamtlautstärke unabhängig von Voice-Anzahl.
            //
            // Detune-Verteilung (symmetrisch um 0, in Cent):
            //   t ∈ [0,1] normiert (Voice-Index). n=1 → t=0.5 (kein Offset).
            //   detuneOffset = (t − 0.5) · 2 · unisonDetune
            //   Beispiel n=3, detune=10: −10 / 0 / +10 Cent.
            //
            // Spread-Verteilung (Stereo-Pan-Position):
            //   voicePan = (t − 0.5) · 2 · unisonSpread
            //   Beispiel n=3, spread=0.5: −0.5 / 0 / +0.5 Pan-Position.
            //   WICHTIG: Zu große Stereo-Breite im Bass kann zu instabilem Low-End führen.
            //   Bass-Empfehlung: spread ≤ 0.35.

            let n         = max(1, min(params.unisonVoices, voiceCount))
            // gainScale: 1/sqrt(n) statt 1/n.
            // Begründung: Unison-Stimmen sind unkorreliert (verschiedene Frequenzen durch Detune).
            // Für unkorrellierte Signale gilt: konstante Energie bei Summe ↔ Amplitude × 1/sqrt(n).
            // Mit 1/n (Amplitude-Normierung) wäre das Signal um 3 dB zu leise bei n=2.
            // Mit 1/sqrt(n) (Energie-Normierung) bleibt die wahrgenommene Lautstärke konstant
            // unabhängig von der Unison-Stimmanzahl.
            let gainScale = 1.0 / sqrtf(Float(n))

            // Der Stimmtyp verzweigt EINMAL, nicht pro Unison-Stimme: beide
            // Zweige laufen danach in einer monomorphen Schleife über ein
            // Array eines konkreten Structs.
            switch activeEngine {
            case .legacy:      noteOnLegacy(note: note, velocity: velocity, unisonCount: n, gainScale: gainScale)
            case .atmospheric: noteOnAtmospheric(note: note, velocity: velocity, unisonCount: n, gainScale: gainScale)
            }
        }

        /// Detune- und Pan-Offset einer Unison-Stimme. Stimmtyp-unabhängig —
        /// der eine Teil der Unison-Logik, der sich ohne dynamischen Dispatch
        /// teilen lässt (reine Skalar-Arithmetik, kein Voice-Zugriff).
        private func unisonOffsets(index i: Int, count n: Int) -> (detuneCents: Float, pan: Float) {
            let t: Float = n > 1 ? Float(i) / Float(n - 1) : 0.5
            return ((t - 0.5) * 2.0 * params.unisonDetune,
                    (t - 0.5) * 2.0 * params.unisonSpread)
        }

        private func noteOnLegacy(note: UInt8, velocity: UInt8, unisonCount n: Int, gainScale: Float) {
            // Core-Parameter einmal pro noteOn uebersetzen (Snapshot-Semantik,
            // identisch fuer alle Unison-Stimmen dieses NoteOns).
            let coreParams = params.audioCoreParameters

            for i in 0..<n {
                voiceTimestamp &+= 1

                let (detuneOffset, voicePan) = unisonOffsets(index: i, count: n)

                // 1. Freie Voice bevorzugen
                if let idx = legacyVoices.firstIndex(where: { !$0.isActive }) {
                    legacyVoices[idx].configure(note:            note,
                                                velocity:         velocity,
                                                sampleRate:       sampleRate,
                                                parameters:       coreParams,
                                                activationOrder:  voiceTimestamp,
                                                detuneCents:      detuneOffset,
                                                panPosition:      voicePan,
                                                gainScale:        gainScale)
                    continue
                }

                // 2. Voice-Stealing: älteste aktive Stimme (kleinster activationOrder-Wert).
                //    Gestohlene Voice bekommt voiceTimestamp → nächste Iteration findet sie nicht.
                var stealIdx = 0
                var minOrder = legacyVoices[0].activationOrder
                for j in 1..<legacyVoices.count {
                    if legacyVoices[j].activationOrder < minOrder {
                        minOrder = legacyVoices[j].activationOrder
                        stealIdx = j
                    }
                }
                legacyVoices[stealIdx].configure(note:           note,
                                                 velocity:        velocity,
                                                 sampleRate:      sampleRate,
                                                 parameters:      coreParams,
                                                 activationOrder: voiceTimestamp,
                                                 detuneCents:     detuneOffset,
                                                 panPosition:     voicePan,
                                                 gainScale:       gainScale)
            }
        }

        // Strukturgleich zum Legacy-Zweig — bewusst ausgeschrieben statt über
        // eine generische Funktion geteilt (Begründung in
        // `SynthVoiceEngine.swift`, Punkt 3).
        //
        // Ein Unterschied ist beabsichtigt: die Suche nach der freien Stimme
        // läuft hier über einen Index-Loop statt über `firstIndex(where:)`.
        // Das Closure-Argument würde jedes Element BY VALUE binden — bei
        // `AudioCoreAtmosphericVoice` also den vollständigen Struct samt
        // ARC-Retain/Release auf die enthaltenen Wavetable-Puffer, pro Element
        // und pro NoteOn. Über den Subscript bleibt der Zugriff geborgt.
        private func noteOnAtmospheric(note: UInt8, velocity: UInt8, unisonCount n: Int, gainScale: Float) {
            for i in 0..<n {
                voiceTimestamp &+= 1

                let (detuneOffset, voicePan) = unisonOffsets(index: i, count: n)

                // 1. Freie Voice bevorzugen
                var targetIdx = -1
                for j in 0..<atmosphericVoices.count where !atmosphericVoices[j].isActive {
                    targetIdx = j
                    break
                }

                // 2. Voice-Stealing: älteste aktive Stimme (kleinster activationOrder-Wert).
                if targetIdx < 0 {
                    targetIdx = 0
                    var minOrder = atmosphericVoices[0].activationOrder
                    for j in 1..<atmosphericVoices.count {
                        if atmosphericVoices[j].activationOrder < minOrder {
                            minOrder = atmosphericVoices[j].activationOrder
                            targetIdx = j
                        }
                    }
                }

                atmosphericVoices[targetIdx].configure(note:            note,
                                                       velocity:        velocity,
                                                       sampleRate:      sampleRate,
                                                       parameters:      atmosphericParams,
                                                       activationOrder: voiceTimestamp,
                                                       detuneCents:     detuneOffset,
                                                       panPosition:     voicePan,
                                                       gainScale:       gainScale)

                // Rampenstart des Space-Sends auf den Basiswert der frisch
                // konfigurierten Stimme setzen (W-03c). Ohne diese Zeile
                // würde der Send einer neuen Note vom Restwert der zuvor auf
                // diesem Platz liegenden Stimme aus anrampen — bei
                // Voice-Stealing ein hörbar falscher Anfangswert.
                previousSendLevels[targetIdx] = atmosphericVoices[targetIdx].spaceSendLevel
            }
        }

        // noteOff/allNotesOff/isSilent/render beziehen sich ausschließlich auf
        // den aktiven Pool — zulässig wegen der Pool-Invariante (der inaktive
        // Pool enthält nie eine aktive Stimme, siehe `switchEngine`).

        func noteOff(note: UInt8) {
            switch activeEngine {
            case .legacy:
                for i in 0..<legacyVoices.count where legacyVoices[i].note == note && legacyVoices[i].isActive {
                    legacyVoices[i].triggerRelease()
                }
            case .atmospheric:
                for i in 0..<atmosphericVoices.count
                where atmosphericVoices[i].note == note && atmosphericVoices[i].isActive {
                    atmosphericVoices[i].triggerRelease()
                }
            }
        }

        func allNotesOff() {
            switch activeEngine {
            case .legacy:
                for i in 0..<legacyVoices.count {
                    legacyVoices[i].triggerRelease()
                }
            case .atmospheric:
                for i in 0..<atmosphericVoices.count {
                    atmosphericVoices[i].triggerRelease()
                }
            }
        }

        // MARK: – DSP-Render (Audio-Thread)
        //
        // Addiert alle aktiven Voices gewichtet in den linken und rechten Output-Buffer.
        // Jede Voice trägt mit eigenen panGainL/panGainR zur Stereo-Verteilung bei.
        // Kein Heap-Zugriff, keine Allokation.

        func render(intoL bufL: UnsafeMutablePointer<Float>,
                    intoR bufR: UnsafeMutablePointer<Float>,
                    frameCount: Int) {
            // Eine Verzweigung pro Block, danach monomorphe Schleife.
            switch activeEngine {
            case .legacy:
                for i in 0..<legacyVoices.count {
                    guard legacyVoices[i].isActive else { continue }
                    legacyVoices[i].render(intoL: bufL, intoR: bufR, frameCount: frameCount)
                }
            case .atmospheric:
                if frameCount <= scratchCapacity {
                    renderAtmosphericViaScratch(intoL: bufL, intoR: bufR, frameCount: frameCount)
                } else {
                    // Sicherheitsnetz für einen Block jenseits der
                    // Pufferkapazität (auf realer Hardware nicht erreichbar,
                    // SpaceSendBus.frameCapacity liegt weit über jeder
                    // IO-Puffergröße): direkt in die Summe rendern. Das
                    // Trockensignal bleibt korrekt, nur der Space-Send fällt
                    // für genau diesen Block aus. Eine Vergrößerung des
                    // Puffers wäre eine Allokation im Rendercallback.
                    for i in 0..<atmosphericVoices.count {
                        guard atmosphericVoices[i].isActive else { continue }
                        atmosphericVoices[i].render(intoL: bufL, intoR: bufR, frameCount: frameCount)
                        previousSendLevels[i] = atmosphericVoices[i].spaceSendLevel
                    }
                }
            }
        }

        /// Atmospheric-Renderpfad über den Zwischenpuffer: Kanalsumme wie
        /// bisher, zusätzlich der pro Stimme gewichtete Space-Send.
        ///
        /// Der Sendweg ist bewusst als Ganzes übersprungen, wenn kein Bus
        /// angeschlossen ist oder der Kanalfader auf 0 steht — er wäre dann
        /// rechnerisch wirkungslos. Die Kanalsumme läuft in jedem Fall durch
        /// dieselben Additionen.
        private func renderAtmosphericViaScratch(intoL bufL: UnsafeMutablePointer<Float>,
                                                 intoR bufR: UnsafeMutablePointer<Float>,
                                                 frameCount: Int) {
            let channelGain = params.spaceSendChannelGain
            let bus = channelGain > 0 ? spaceSendBus : nil

            for i in 0..<atmosphericVoices.count {
                guard atmosphericVoices[i].isActive else { continue }

                for f in 0..<frameCount {
                    scratchL[f] = 0
                    scratchR[f] = 0
                }

                let previousLevel = previousSendLevels[i]
                atmosphericVoices[i].render(intoL: scratchL, intoR: scratchR, frameCount: frameCount)
                let currentLevel = atmosphericVoices[i].spaceSendLevel
                previousSendLevels[i] = currentLevel

                for f in 0..<frameCount {
                    bufL[f] += scratchL[f]
                    bufR[f] += scratchR[f]
                }

                if let bus, previousLevel > 0 || currentLevel > 0 {
                    bus.accumulate(left: scratchL, right: scratchR,
                                   gainStart: previousLevel * channelGain,
                                   gainEnd: currentLevel * channelGain,
                                   frameCount: frameCount)
                }
            }
        }

        // Index-Loop statt `allSatisfy`: das Closure-Argument würde jedes
        // Element by value binden (bei der Atmospheric Voice inklusive
        // ARC-Verkehr auf den Wavetable-Puffern).
        var isSilent: Bool {
            switch activeEngine {
            case .legacy:
                for i in 0..<legacyVoices.count where legacyVoices[i].isActive { return false }
                return true
            case .atmospheric:
                for i in 0..<atmosphericVoices.count where atmosphericVoices[i].isActive { return false }
                return true
            }
        }
    }

    // MARK: – Initialisierung

    init() {}

    // MARK: – prepare()
    //
    // Wird von AudioEngine.setupGraph() nach engine.start() aufgerufen.
    // Die sampleRate kommt von engine.outputNode.outputFormat(forBus:0).sampleRate.
    // Nach prepare() ist sourceNode gültig und kann an die Engine gehängt werden.

    /// - Parameter spaceSendBus: Sammelbus zur gemeinsamen DeepSpace-Kette
    ///   (W-03c). `nil` heißt "dieser Kanal speist keinen Raum" — Default,
    ///   damit der Offline-Harness und alle Baseline-Tests unverändert den
    ///   reinen Trockenpfad messen.
    func prepare(sampleRate: Double, params: SynthParams = .defaults, spaceSendBus: SpaceSendBus? = nil) {
        // Baut BEIDE Voice-Pools auf (W-03b1) — bewusst hier und nicht beim
        // Umschalten: der Rendercallback darf keinen Pool aufbauen. Ebenso die
        // Zwischenpuffer des Space-Sends (W-03c).
        pool = VoicePool(params: params, sampleRate: sampleRate, spaceSendBus: spaceSendBus)

        // ── Frequenz-Verifikation der AudioCoreVoice-Formel ───────────────────
        // Formel: 440.0 * pow(2.0, (note - 69.0) / 12.0)
        // Erwartungswerte (gleichstufige Stimmung, A4 = 440 Hz):
        let f60 = 440.0 * pow(2.0, (60.0 - 69.0) / 12.0)   // C4
        let f69 = 440.0 * pow(2.0, (69.0 - 69.0) / 12.0)   // A4
        let f72 = 440.0 * pow(2.0, (72.0 - 69.0) / 12.0)   // C5
        print(String(format: "[SynthNode] Formel-Check: MIDI60→%.2fHz (erw.261.63)  MIDI69→%.2fHz (erw.440.00)  MIDI72→%.2fHz (erw.523.25)",
                     f60, f69, f72))
        print("[SynthNode] prepare(). sampleRate=\(sampleRate)  voices=\(params.maxVoices)  ADSR=\(params.attackMs)/\(params.decayMs)/\(params.sustain)/\(params.releaseMs)ms  voiceEngine=\(params.voiceEngine)")

        let q = queue   // stark captured
        let p = pool!   // stark captured (pool gesetzt, bevor sourceNode entsteht)

        // Explizites Stereo-Format: garantiert stereo AudioBufferList in der Render-Closure.
        // Ohne explizites Format verhandelt AVAudioEngine das Format mit den Downstream-Nodes.
        // Mit explizit gesetztem Format ist abl.count immer 2 — panning der Delay-Sends
        // und stereo-Verarbeitung in AVAudioUnitDelay/AVAudioUnitReverb sind garantiert.
        //
        // Signalfluss im Kanal:
        //   sourceNode (stereo, L=R) → gainX → delay1/2/3SendX (gepant) → delays (stereo)
        //                                    → sumX (stereo: L≠R durch Panning) → reverb (stereo)
        //
        // Render-Closure läuft auf dem Audio-Thread:
        //   – q und p werden stark captured (stabil, kein weak/unowned nötig)
        //   – kein [weak self] → kein ARC im Render-Pfad
        //   – keine Swift-Allokationen, kein Concurrency, kein AppSettings-Zugriff
        //   – Mono-Oszillator (Kanal 0) wird auf alle Ausgangskanäle kopiert (L=R an Source)
        //   – Stereo-Breite entsteht durch Delay-Panning downstream

        let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        sourceNode = AVAudioSourceNode(format: stereoFormat) { isSilence, _, frameCount, outputData in
            let fc  = Int(frameCount)
            let abl = UnsafeMutableAudioBufferListPointer(outputData)

            // ── 1. Events verarbeiten (lock-free, FIFO) ──────────────────────
            //
            // Alle Queue-Events werden vollständig in FIFO-Reihenfolge abgearbeitet,
            // bevor ein einziger DSP-Sample berechnet wird (Schritt 2).
            //
            // Bedeutung für paramUpdate:
            //   Ein paramUpdate in dieser Batch aktualisiert VoicePool.params sofort.
            //   Alle nachfolgenden noteOns derselben Batch lesen bereits die neuen Params.
            //   Es gibt keinen Zustand, in dem params halb-wirksam oder zeitversetzt ist.
            //   (Siehe applyParams() für vollständige Determinismus-Dokumentation.)
            while let event = q.pop() {
                switch event.kind {
                case .noteOn:      p.noteOn(note: event.note, velocity: event.velocity)
                case .noteOff:     p.noteOff(note: event.note)
                case .allOff:      p.allNotesOff()
                case .paramUpdate: p.applyParams(event.params)
                }
            }

            // ── 2. Buffer nullen ──────────────────────────────────────────────
            let silent = p.isSilent
            for ch in 0..<abl.count {
                guard let data = abl[ch].mData?.assumingMemoryBound(to: Float.self) else { continue }
                for f in 0..<fc { data[f] = 0 }
            }

            // ── 3. Stereo-Render ──────────────────────────────────────────────
            //
            // Jede Voice schreibt ihr Signal gewichtet in den linken (L) und rechten (R)
            // Buffer. Panning und Unison-Spread entstehen durch individuelle panGainL/R
            // pro Voice (berechnet bei configure() — kein Overhead hier).
            //
            // Format-Garantie: stereoFormat setzt abl.count = 2.
            // Mono-Fallback bleibt als Sicherheitsnetz (sollte nicht auftreten).
            if !silent {
                if abl.count >= 2,
                   let dataL = abl[0].mData?.assumingMemoryBound(to: Float.self),
                   let dataR = abl[1].mData?.assumingMemoryBound(to: Float.self) {
                    p.render(intoL: dataL, intoR: dataR, frameCount: fc)
                } else if let dataL = abl[0].mData?.assumingMemoryBound(to: Float.self) {
                    // Mono-Fallback: beide Buffer-Pointer identisch (dual-mono)
                    p.render(intoL: dataL, intoR: dataL, frameCount: fc)
                }
            }

            isSilence.pointee = ObjCBool(silent)
            return noErr
        }
    }

    // MARK: – Öffentliche API (nur von AudioEngine.commandQueue aufzurufen → NoteEventQueue)

    func noteOn(note: UInt8, velocity: UInt8) {
        queue.push(NoteEvent(kind: .noteOn, note: note, velocity: velocity))
    }

    func noteOff(note: UInt8) {
        queue.push(NoteEvent(kind: .noteOff, note: note, velocity: 0))
    }

    func allNotesOff() {
        queue.push(NoteEvent(kind: .allOff, note: 0, velocity: 0))
    }

    /// Übergibt neue SynthParams an den Audio-Thread via Queue (lock-free).
    ///
    /// Live-Verhalten (wirkt sofort auf laufende Voices):
    ///   – filterCutoff / filterResonance: Biquad-Koeffizienten werden auf alle aktiven Voices übertragen.
    ///   – sustain: Sustain-Level aller Voices in Sustain-Stage wird aktualisiert.
    ///
    /// Snapshot-Semantik (wirkt ab nächster NoteOn):
    ///   – attackMs / decayMs / releaseMs: Raten beim nächsten configure() berechnet.
    ///   – waveform: ab nächster NoteOn.
    ///
    /// Sofort wirksam mit kontrolliertem All-Off:
    ///   – voiceEngine: schaltet zwischen den beiden vorgehaltenen Pools um.
    ///     Beide Pools werden dabei hart stillgelegt — ein Wechsel schneidet
    ///     klingende Noten ab, statt sie im abgewählten Pool hängen zu lassen
    ///     (siehe VoicePool.switchEngine).
    ///
    /// maxVoices-Änderungen haben keine Wirkung (Voice-Array ist nach prepare() fixiert).
    func updateParams(_ params: SynthParams) {
        queue.push(NoteEvent(kind: .paramUpdate, note: 0, velocity: 0, params: params))
    }
}
