import Foundation
import AVFoundation
import HarmonyAudioCore

// MARK: – DeepSpaceReturnNode
//
// W-03c (`.agent_handoff/latest_codex.md`, Runde 072): der Rueckweg des
// gemeinsamen Raums. Zieht den in `SpaceSendBus` gesammelten Send durch die
// in W-02 zusammengeschaltete `AudioCoreDeepSpace`-Kette und gibt das
// Ergebnis stereo an den Graph zurueck.
//
// Signalweg im Produktgraph (`AudioEngine.setupGraph`):
//
//   vier SynthNodes ──(SpaceSendBus, pro Stimme mit spaceSendLevel)──┐
//                                                                    ↓
//                      sourceNode → sharedSpaceSendBus → mainMixerNode
//                           (AudioCoreDeepSpace)
//
// `sharedSpaceSendBus` haengt seit S-07a (Runde 055) still an
// `mainMixerNode`. Dieser Slice speist ihn erstmals — und aendert am Graph
// sonst nichts: `mainMixerNode` bekommt keinen neuen Eingang, nur der bisher
// eingangslose Sammelbus.
//
// ── Warum ein AVAudioSourceNode und kein Effektknoten ─────────────────────
//
// AVAudioEngine kann eigenes Swift-DSP nur als Quelle (`AVAudioSourceNode`)
// einhaengen; fuer einen echten Effektknoten zwischen zwei Bussen braeuchte
// es eine registrierte AUv3-Komponente. Der Umweg lohnt hier nicht: der
// Send wird ohnehin pro Stimme gewichtet und entsteht deshalb in Software
// (Begruendung in `SpaceSendBus`), also liegt sein Eingang bereits neben
// dem Graph. Ein Effektknoten haette dieselbe Rechnung mit mehr Apparat
// gemacht.
//
// ── Realtime-Vertrag ──────────────────────────────────────────────────────
//
// Der Rendercallback alloziert nicht, sperrt nicht, nutzt keine Dispatch-/
// Task-/Actor-Ausfuehrung und schreibt nicht. Kette, Eingangspuffer und
// Knoten entstehen ausschliesslich in `prepare(sampleRate:)`, also vor dem
// ersten Callback. Kein Graph- oder Pool-Umbau aus dem Rendercallback:
// `AudioCoreDeepSpace.reset()` und `.setParameters(_:)` waeren seit W-03a
// zwar rendercallback-sicher, werden hier aber von keinem Pfad aufgerufen —
// die Kette laeuft ab `prepare` mit einem festen Parametersatz.
//
// ── Warum der Knoten nie `isSilence` meldet ───────────────────────────────
//
// Ein Hall hat nach dem letzten Eingangssample noch eine Fahne. Der Knoten
// meldet deshalb dauerhaft `false` und rechnet in jedem Block — auch wenn
// nichts klingt. Der Preis ist eine konstante Grundlast; der Gewinn ist,
// dass kein Zustandsautomat entscheiden muss, wann eine Fahne "zu Ende" ist.
// Bei stummem Eingang und ungestoertem Zustand liefert die Kette exakt
// `0.0` — der Beitrag zum Summenbus ist dann bitgenau neutral, was die
// Bit-Identitaet bei `spaceSend = 0` traegt.

final class DeepSpaceReturnNode: @unchecked Sendable {

    /// Gueltig nach `prepare(sampleRate:)`. Wird von
    /// `AudioEngine.setupGraph()` an die Engine gehaengt.
    private(set) var sourceNode: AVAudioSourceNode!

    private let bus: SpaceSendBus
    private var processor: SpaceProcessor?

    init(bus: SpaceSendBus) {
        self.bus = bus
    }

    // MARK: – Raumprozessor (Audio-Thread-exklusiv nach prepare())
    //
    // Eigene Klasse statt Feld auf `DeepSpaceReturnNode`, damit der
    // Rendercallback sie stark einfangen kann, ohne `self` einzufangen —
    // identisches Muster wie `SynthNode.VoicePool` (kein Referenzzyklus
    // Knoten → Closure → Knoten, kein ARC im Renderpfad).

    private final class SpaceProcessor {

        /// Die W-02-Kette. Zweigpegel unveraendert bei je 0,5 — ausdruecklich
        /// vorlaeufig, Stephan entscheidet nach dem Hoeren (siehe
        /// `AudioCoreDeepSpaceChainParameters`).
        var space: AudioCoreDeepSpace

        /// Eingangsblock, in `init` angelegt, nie im Callback.
        let input: UnsafeMutablePointer<Float>
        let capacity: Int
        let bus: SpaceSendBus

        init(sampleRate: Double, bus: SpaceSendBus) {
            self.bus = bus
            self.capacity = bus.capacity
            self.space = AudioCoreDeepSpace(sampleRate: sampleRate)
            self.input = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
            self.input.initialize(repeating: 0, count: capacity)
        }

        deinit {
            input.deinitialize(count: capacity)
            input.deallocate()
        }

        /// Ein Renderblock: Send abholen, durch die Kette schicken, additiv
        /// in die bereits genullten Ausgangspuffer schreiben.
        func render(intoL outputL: UnsafeMutablePointer<Float>,
                    intoR outputR: UnsafeMutablePointer<Float>,
                    frameCount: Int) {
            guard frameCount > 0, frameCount <= capacity else { return }
            bus.drain(into: input, frameCount: frameCount)
            space.render(input: input, intoL: outputL, intoR: outputR, frameCount: frameCount)
        }
    }

    // MARK: – prepare()
    //
    // Wird von `AudioEngine.setupGraph()` nach `engine.start()` aufgerufen,
    // mit derselben echten Sample Rate wie die vier `SynthNode`s.

    func prepare(sampleRate: Double) {
        let space = SpaceProcessor(sampleRate: sampleRate, bus: bus)
        processor = space

        print("[DeepSpaceReturnNode] prepare(). sampleRate=\(sampleRate)  capacity=\(bus.capacity) Frames")

        // Explizites Stereo-Format wie beim SynthNode: garantiert eine
        // Stereo-AudioBufferList im Callback.
        let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        sourceNode = AVAudioSourceNode(format: stereoFormat) { isSilence, _, frameCount, outputData in
            let fc  = Int(frameCount)
            let abl = UnsafeMutableAudioBufferListPointer(outputData)

            // Buffer nullen — `AudioCoreDeepSpace.render` schreibt additiv.
            for ch in 0..<abl.count {
                guard let data = abl[ch].mData?.assumingMemoryBound(to: Float.self) else { continue }
                for f in 0..<fc { data[f] = 0 }
            }

            if abl.count >= 2,
               let dataL = abl[0].mData?.assumingMemoryBound(to: Float.self),
               let dataR = abl[1].mData?.assumingMemoryBound(to: Float.self) {
                space.render(intoL: dataL, intoR: dataR, frameCount: fc)
            } else if let dataL = abl[0].mData?.assumingMemoryBound(to: Float.self) {
                // Mono-Fallback wie im SynthNode: beide Zeiger identisch.
                space.render(intoL: dataL, intoR: dataL, frameCount: fc)
            }

            isSilence.pointee = ObjCBool(false)
            return noErr
        }
    }
}
