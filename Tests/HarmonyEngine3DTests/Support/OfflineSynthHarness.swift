import Foundation
import AVFoundation
@testable import HarmonyEngine3D

// MARK: – OfflineSynthHarness
//
// S-01 (`.agent_handoff/latest_codex.md`, Runde 045): deterministischer
// Offline-Render-Harness fuer den bestehenden Legacy-Synth. Treibt den
// ECHTEN heutigen `SynthNode`-Pfad (`AVAudioSourceNode` → `VoicePool` →
// `AudioCoreVoice` seit S-02b/Runde 047, Events via `NoteEventQueue`) ueber
// `AVAudioEngine.enableManualRenderingMode(.offline, …)`.
//
// Keine Audio-Hardware, kein Vordergrund-Fenster, kein System-Output.
//
// Graph-Entscheidung: `SynthNode.sourceNode` wird direkt mit
// `engine.mainMixerNode` verbunden — bewusst OHNE den Fader-/Delay-/
// Reverb-/Kompressor-Graph aus `AudioEngine.swift`. S-01 misst die
// Synth-Baseline; `AVAudioUnitReverb`/`AVAudioUnitDelay`-Presets und
// Hardwarezustand sollen diese Baseline nicht verfaelschen (siehe
// Handoff, Abschnitt "Wichtig").
//
// Threading: Der Testtreiber ruft `SynthNode.noteOn`/`noteOff`/
// `allNotesOff`/`updateParams` ausschliesslich vom XCTest-Testthread auf,
// synchron vor dem zugehoerigen `renderOffline`-Aufruf. Das erfuellt den
// SPSC-Vertrag von `NoteEventQueue` (genau ein Producer-Thread), ist aber
// KEIN Test des echten Multi-Producer-Falls (SceneKit-Render-Thread +
// GameController-Thread + Main-Thread, serialisiert ueber
// `AudioEngine.commandQueue`) — das bleibt ausserhalb des S-01-Scopes.

/// Ein Event, das an einer bestimmten Frame-Position in den echten
/// `SynthNode`-Rendercallback eingespeist wird.
///
/// `atFrame` ist die Frame-Position relativ zum Renderbeginn. Der Harness
/// erzwingt Frame-Genauigkeit, indem er `renderOffline` exakt an dieser
/// Grenze in einen neuen Chunk teilt: `SynthNode`s Rendercallback
/// verarbeitet alle Queue-Events vollstaendig in FIFO-Reihenfolge, BEVOR
/// der erste DSP-Sample eines Callbacks berechnet wird (siehe
/// `SynthNode.prepare()`). Ein Event, das unmittelbar vor dem Chunk ab
/// `atFrame` angewendet wird, wirkt daher exakt ab Frame `atFrame`.
struct OfflineSynthEvent {
    enum Kind {
        case noteOn(note: UInt8, velocity: UInt8)
        case noteOff(note: UInt8)
        case allNotesOff
        case paramUpdate(SynthParams)
    }

    let atFrame: Int
    let kind: Kind

    static func noteOn(atFrame: Int, note: UInt8, velocity: UInt8 = 100) -> OfflineSynthEvent {
        OfflineSynthEvent(atFrame: atFrame, kind: .noteOn(note: note, velocity: velocity))
    }

    static func noteOff(atFrame: Int, note: UInt8) -> OfflineSynthEvent {
        OfflineSynthEvent(atFrame: atFrame, kind: .noteOff(note: note))
    }

    static func allNotesOff(atFrame: Int) -> OfflineSynthEvent {
        OfflineSynthEvent(atFrame: atFrame, kind: .allNotesOff)
    }

    static func paramUpdate(atFrame: Int, params: SynthParams) -> OfflineSynthEvent {
        OfflineSynthEvent(atFrame: atFrame, kind: .paramUpdate(params))
    }
}

/// Ergebnis eines Offline-Renders: getrennte Float-Kanalpuffer (non-interleaved,
/// wie intern von AVAudioEngine verwendet).
struct OfflineRenderResult {
    let sampleRate: Double
    let frameCount: Int
    let left: [Float]
    let right: [Float]
}

enum OfflineSynthHarnessError: Error {
    case invalidFormat
    case manualRenderingSetupFailed(Error)
    case engineStartFailed(Error)
    case renderFailed(AVAudioEngineManualRenderingStatus)
    case bufferAllocationFailed
}

enum OfflineSynthHarness {

    /// Rendert `totalFrames` Frames des echten `SynthNode`-Pfads offline.
    ///
    /// - Parameters:
    ///   - sampleRate: Ziel-Samplerate (getestet: 44.1 kHz und 48 kHz).
    ///   - totalFrames: Gesamtlaenge des Renders in Frames.
    ///   - params: `SynthParams`-Snapshot fuer `SynthNode.prepare()`.
    ///   - events: Frame-genau plazierte Note-/Parameter-Events.
    ///   - maximumFrameCount: Obergrenze pro `renderOffline`-Aufruf (Manual-
    ///     Rendering-Vertrag). Chunks zwischen Event-Grenzen, die groesser
    ///     sind, werden intern weiter unterteilt.
    ///   - withSpaceSend: haengt zusaetzlich die gemeinsame Raumkette an
    ///     (W-03c): `SpaceSendBus` in den `SynthNode` und ein
    ///     `DeepSpaceReturnNode` parallel an `mainMixerNode`. Default `false`
    ///     — jeder bestehende Aufrufer misst unveraendert den reinen
    ///     Trockenpfad.
    ///
    ///     Der Return-Knoten haengt hier direkt am `mainMixerNode` statt an
    ///     `sharedSpaceSendBus`, aus demselben Grund, aus dem der Harness den
    ///     ganzen Fader-/Delay-/Reverb-Graph auslaesst (siehe
    ///     Typ-Dokumentation): gemessen werden soll die Kette, nicht der
    ///     Sammelbus davor. `sharedSpaceSendBus` ist ein `AVAudioMixerNode`
    ///     mit Pegel 1,0 und ohne weitere Eingaenge — er veraendert das
    ///     Signal nicht.
    static func render(sampleRate: Double,
                        totalFrames: Int,
                        params: SynthParams = .defaults,
                        events: [OfflineSynthEvent],
                        maximumFrameCount: AVAudioFrameCount = 4096,
                        withSpaceSend: Bool = false) throws -> OfflineRenderResult {

        guard totalFrames > 0 else {
            return OfflineRenderResult(sampleRate: sampleRate, frameCount: 0, left: [], right: [])
        }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw OfflineSynthHarnessError.invalidFormat
        }
        for event in events {
            precondition(event.atFrame >= 0 && event.atFrame <= totalFrames,
                         "OfflineSynthEvent.atFrame \(event.atFrame) liegt ausserhalb [0, \(totalFrames)]")
        }

        // ── Echter Produktpfad: SynthNode.prepare() baut den echten AVAudioSourceNode ──
        let spaceSendBus: SpaceSendBus? = withSpaceSend ? SpaceSendBus() : nil

        let synth = SynthNode()
        synth.prepare(sampleRate: sampleRate, params: params, spaceSendBus: spaceSendBus)

        let engine = AVAudioEngine()
        engine.attach(synth.sourceNode)
        // Bewusst direkt an mainMixerNode, siehe Typ-Dokumentation oben.
        engine.connect(synth.sourceNode, to: engine.mainMixerNode, format: format)

        // ── Optional: gemeinsame Raumkette (W-03c) ──────────────────────────
        var deepSpaceReturn: DeepSpaceReturnNode? = nil
        if let spaceSendBus {
            let returnNode = DeepSpaceReturnNode(bus: spaceSendBus)
            returnNode.prepare(sampleRate: sampleRate)
            engine.attach(returnNode.sourceNode)
            engine.connect(returnNode.sourceNode, to: engine.mainMixerNode, format: format)
            deepSpaceReturn = returnNode
        }
        // Haelt den Knoten ueber die Renderdauer am Leben, auch wenn der
        // Compiler die lokale Variable sonst frueher freigeben duerfte.
        defer { _ = deepSpaceReturn }

        do {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: maximumFrameCount)
        } catch {
            throw OfflineSynthHarnessError.manualRenderingSetupFailed(error)
        }

        do {
            try engine.start()
        } catch {
            throw OfflineSynthHarnessError.engineStartFailed(error)
        }
        defer { engine.stop() }

        guard let renderBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maximumFrameCount) else {
            throw OfflineSynthHarnessError.bufferAllocationFailed
        }

        var left  = [Float](); left.reserveCapacity(totalFrames)
        var right = [Float](); right.reserveCapacity(totalFrames)

        // Stabil nach atFrame sortieren: gleiche atFrame-Werte behalten die
        // Deklarationsreihenfolge (relevant z. B. fuer "paramUpdate unmittelbar
        // vor noteOn an derselben Grenze").
        let orderedEvents = events.enumerated().sorted { lhs, rhs in
            lhs.element.atFrame != rhs.element.atFrame
                ? lhs.element.atFrame < rhs.element.atFrame
                : lhs.offset < rhs.offset
        }.map { $0.element }

        func apply(_ event: OfflineSynthEvent) {
            switch event.kind {
            case .noteOn(let note, let velocity): synth.noteOn(note: note, velocity: velocity)
            case .noteOff(let note):               synth.noteOff(note: note)
            case .allNotesOff:                     synth.allNotesOff()
            case .paramUpdate(let newParams):      synth.updateParams(newParams)
            }
        }

        func renderChunk(_ frameCount: Int) throws {
            var remaining = frameCount
            while remaining > 0 {
                let chunk = min(remaining, Int(maximumFrameCount))
                let status = try engine.renderOffline(AVAudioFrameCount(chunk), to: renderBuffer)
                guard status == .success else {
                    throw OfflineSynthHarnessError.renderFailed(status)
                }
                guard let channelData = renderBuffer.floatChannelData else {
                    throw OfflineSynthHarnessError.bufferAllocationFailed
                }
                let rendered = Int(renderBuffer.frameLength)
                guard rendered > 0 else { break } // Sicherheitsnetz gegen Endlosschleife
                left.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: rendered))
                if renderBuffer.format.channelCount >= 2 {
                    right.append(contentsOf: UnsafeBufferPointer(start: channelData[1], count: rendered))
                } else {
                    right.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: rendered))
                }
                remaining -= rendered
            }
        }

        var currentFrame = 0
        var eventIndex = 0
        while currentFrame < totalFrames {
            while eventIndex < orderedEvents.count, orderedEvents[eventIndex].atFrame == currentFrame {
                apply(orderedEvents[eventIndex])
                eventIndex += 1
            }

            let nextBoundary = eventIndex < orderedEvents.count
                ? min(orderedEvents[eventIndex].atFrame, totalFrames)
                : totalFrames

            let chunkFrames = nextBoundary - currentFrame
            if chunkFrames > 0 {
                try renderChunk(chunkFrames)
            }
            currentFrame = nextBoundary
        }

        return OfflineRenderResult(sampleRate: sampleRate, frameCount: left.count, left: left, right: right)
    }
}
