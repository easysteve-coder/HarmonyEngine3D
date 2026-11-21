import Foundation

// MARK: – SpaceSendBus
//
// W-03c (`.agent_handoff/latest_codex.md`, Runde 072): der Software-Sammelbus
// zwischen den vier `SynthNode`-Renderpfaden und der gemeinsamen
// `AudioCoreDeepSpace`-Kette (`DeepSpaceReturnNode`).
//
// ── Warum ein Softwarebus und kein reiner AVAudioNode-Abgriff ──────────────
//
// Der Space-Send ist PRO STIMME gewichtet: `AudioCoreAtmosphericVoice`
// exponiert `spaceSendLevel` als eigenes Modulationsziel (siehe dort,
// "Sonderfall unter den sieben Modulationszielen"). Dieser Wert existiert nur
// innerhalb des `VoicePool`, vor der Summierung der Stimmen. Ein Abgriff auf
// Graphebene — also hinter `gainX` — koennte ihn prinzipiell nicht mehr
// anwenden, weil dort nur noch die fertige Kanalsumme liegt.
//
// Der Send entsteht deshalb dort, wo die einzelne Stimme noch sichtbar ist,
// und wird ueber diesen Bus an die eine gemeinsame Raumkette gereicht.
//
// ── Verhaeltnis zu `AudioGraphSendTopology` ────────────────────────────────
//
// Der in S-07a getestete Topologie-Deskriptor bleibt eingehalten:
//
//   – CH1/Bass `preChannelDynamics`: der Send entsteht vor `compressorBass`
//     und laeuft nicht durch ihn. Stephans Option-A-Entscheidung vom
//     2026-07-30 ist damit erfuellt — sogar strenger als gefordert, weil der
//     Abgriff noch vor dem Kanal-Gain liegt.
//   – CH0/CH2/CH3 `postGain`: der Kanalfader wirkt trotzdem auf den Send.
//     `AudioEngine` reicht denselben linearen Faderwert, den es auf
//     `gainX.outputVolume` setzt, als `SynthParams.spaceSendChannelGain` in
//     den Pool; der Send ist dadurch post-fader wie ein Abgriff hinter dem
//     Gain. Nicht uebernommen wird die Pan-Position von `gainX` — die Kette
//     ist mono-in (siehe `AudioCoreDeepSpace`, "Mono-Eingang"), eine
//     Pan-Position waere dort ohne Bedeutung.
//
// ── Threading und Realtime-Vertrag ─────────────────────────────────────────
//
// Schreiber sind die vier `SynthNode`-Rendercallbacks, Leser ist der
// Rendercallback des `DeepSpaceReturnNode`. Alle fuenf laufen im selben
// Renderzyklus auf dem einen Renderthread der `AVAudioEngine` — es gibt keine
// parallele Knotenausfuehrung, deshalb kein Lock und kein Atomic.
//
// Die Reihenfolge innerhalb des Zyklus ist von AVAudioEngine nicht
// zugesichert, und der Bus ist bewusst so gebaut, dass sie egal ist:
// `accumulate` addiert, `drain` liest und nullt in einem Zug. Wird der
// Return-Knoten vor den Stimmen gezogen, verschiebt sich der Send um genau
// einen Block (bei 48 kHz und 256 Frames rund 5 ms) — bei einem Hallsend
// unhoerbar. Wird er danach gezogen, ist die Verzoegerung null. In beiden
// Faellen wird jeder Block genau einmal verbraucht: kein doppelter, kein
// verlorener Block.
//
// Weder `accumulate` noch `drain` allozieren, sperren oder schreiben. Der
// Puffer wird ausschliesslich in `init` angelegt.

final class SpaceSendBus: @unchecked Sendable {

    /// Obergrenze der Blockgroesse, die dieser Bus traegt. Deutlich ueber
    /// jeder realen Hardware-IO-Puffergroesse und gleich dem
    /// `maximumFrameCount` des Offline-Harness. Ein groesserer Block laesst
    /// den Send fuer genau diesen Block aus (siehe `SynthNode`), statt den
    /// Puffer im Rendercallback zu vergroessern.
    static let frameCapacity = 4096

    let capacity: Int

    /// Mono-Akkumulator. `AudioCoreDeepSpace` ist mono-in/stereo-out; ein
    /// Stereo-Akkumulator wuerde an beiden Zweigen der Kette wieder
    /// zusammenfallen (siehe dort) und nur Speicher kosten.
    private let accumulator: UnsafeMutablePointer<Float>

    init(capacity: Int = SpaceSendBus.frameCapacity) {
        self.capacity = max(1, capacity)
        accumulator = UnsafeMutablePointer<Float>.allocate(capacity: self.capacity)
        accumulator.initialize(repeating: 0, count: self.capacity)
    }

    deinit {
        accumulator.deinitialize(count: capacity)
        accumulator.deallocate()
    }

    // MARK: – Schreiben (Audio-Thread, aus SynthNode.VoicePool)

    /// Mischt den Stereo-Ausgang EINER Stimme mono-gefaltet und mit einer
    /// linearen Pegelrampe in den Sammelbus.
    ///
    /// Die Rampe laeuft von `gainStart` (Sendpegel am Ende des vorherigen
    /// Blocks) nach `gainEnd` (Sendpegel am Ende dieses Blocks).
    /// `AudioCoreAtmosphericVoice.spaceSendLevel` wird nur einmal pro Block
    /// fortgeschrieben; ein blockkonstanter Faktor wuerde bei modulierter
    /// Sendtiefe an jeder Blockgrenze eine Stufe erzeugen. Die Rampe kostet
    /// eine Addition pro Sample und beseitigt sie.
    func accumulate(left: UnsafePointer<Float>,
                    right: UnsafePointer<Float>,
                    gainStart: Float,
                    gainEnd: Float,
                    frameCount: Int) {
        guard frameCount > 0, frameCount <= capacity else { return }
        guard gainStart.isFinite, gainEnd.isFinite else { return }

        let step = (gainEnd - gainStart) / Float(frameCount)
        var gain = gainStart
        for frame in 0..<frameCount {
            // Mono-Faltung mit 0,5: identisch zu der Mittelung, die
            // `AudioCoreDeepSpaceFDNTail.process` intern ohnehin vornimmt.
            accumulator[frame] += (left[frame] + right[frame]) * 0.5 * gain
            gain += step
        }
    }

    // MARK: – Lesen (Audio-Thread, aus DeepSpaceReturnNode)

    /// Uebergibt den akkumulierten Block an den Aufrufer und nullt ihn.
    ///
    /// Kopieren statt Zeiger herausreichen ist Absicht: der Verbrauch ist
    /// damit ein einziger, nicht teilbarer Schritt, und der Aufrufer kann den
    /// Eingang nicht versehentlich zweimal lesen. Die Kopie kostet einen
    /// Durchlauf ueber den Block und faellt gegenueber der Raumkette nicht
    /// ins Gewicht.
    ///
    /// Passt der Block nicht in die Kapazitaet, liefert der Bus Stille — das
    /// Gegenstueck zur Auslassung auf der Schreibseite.
    func drain(into destination: UnsafeMutablePointer<Float>, frameCount: Int) {
        guard frameCount > 0 else { return }
        guard frameCount <= capacity else {
            for frame in 0..<frameCount { destination[frame] = 0 }
            return
        }
        for frame in 0..<frameCount {
            destination[frame] = accumulator[frame]
            accumulator[frame] = 0
        }
    }
}
