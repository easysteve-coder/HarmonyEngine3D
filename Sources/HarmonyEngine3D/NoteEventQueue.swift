import Foundation
import Darwin

// MARK: – NoteEvent

/// Kompaktes Ereignis für den SPSC-Ringpuffer.
/// Wird vom Producer geschrieben und vom Audio-Thread (Consumer) gelesen.
/// Pure Value Type – kein Heap-Zugriff bei Kopie.
///
/// Producer-Identität (korrigiert, Runde 016 / F-02): NICHT "der Main Thread" —
/// noteOn/noteOff kommen real vom SceneKit-Render-Thread (HarmonyScene-Events) und
/// vom GameController-Handler-Thread (CH3/Gamepad), paramUpdate vom Main Thread
/// (Combine). `AudioEngine.commandQueue` ist die alleinige Serialisierungsgrenze,
/// die diese Aufrufer-Threads auf einen einzigen logischen Producer pro Queue
/// abbildet — siehe `AudioEngine.swift`. `push()`/`pop()` selbst bleiben SPSC-korrekt
/// nur unter dieser Voraussetzung: „ein Producer" heißt „ein Thread ruft push() auf",
/// nicht „ein bestimmter benannter Thread".
///
/// Das `params`-Feld ist nur für `.paramUpdate`-Events relevant.
/// Bei allen anderen Kinds enthält es `.defaults` (Null-Overhead, da struct).

struct NoteEvent {
    enum Kind: UInt8 {
        case noteOn      = 1
        case noteOff     = 2
        case allOff      = 3
        case paramUpdate = 4   // Synth-Parameter-Update (Audio-Thread liest SynthParams)
    }
    let kind:     Kind
    let note:     UInt8
    let velocity: UInt8
    let params:   SynthParams   // nur für .paramUpdate relevant, sonst .defaults

    /// Standard-Init mit optionalem params-Default.
    init(kind: Kind, note: UInt8, velocity: UInt8, params: SynthParams = .defaults) {
        self.kind     = kind
        self.note     = note
        self.velocity = velocity
        self.params   = params
    }
}

// MARK: – NoteEventQueue
//
// SPSC-Ringpuffer (Single Producer / Single Consumer).
//
// ── Invarianten ───────────────────────────────────────────────────────────────
//   Producer (genau ein Thread — AudioEngine.commandQueue, siehe NoteEvent-Doku
//             oben): schreibt writeIndex, liest readIndex.
//   Consumer (Audio-Thread):                                schreibt readIndex, liest writeIndex.
//   Jeder Index wird ausschließlich von einer Seite geschrieben → kein Lock.
//   Zugriffsmuster: Producer schreibt buffer[writeIndex], dann writeIndex.
//                   Consumer liest buffer[readIndex], dann readIndex.
//   WICHTIG: Ruft mehr als ein Thread push() für dieselbe Queue auf, ist diese
//   Invariante verletzt (Datenrace auf writeIndex) — push() selbst erzwingt das
//   nicht. Die Einhaltung ist Aufgabe des Aufrufers (`AudioEngine`).
//
// ── Korrektheit auf ARM64 / x86_64 ───────────────────────────────────────────
//   OSMemoryBarrier() ist eine Full Barrier:
//     – auf ARM64 (Apple Silicon): dmb ish — stellt store→store und load→load Ordnung sicher.
//     – auf x86_64 (Intel Mac):    mfence oder lock xchg — gleichwertig.
//   Reihenfolge je Operation:
//     push:  [1] OSMemoryBarrier() → Load-Acquire für readIndex
//            [2] Schreibe buffer[writeIndex]
//            [3] OSMemoryBarrier() → Store-Release vor writeIndex-Update
//            [4] Schreibe writeIndex
//     pop:   [1] OSMemoryBarrier() → Load-Acquire für writeIndex
//            [2] Lese buffer[readIndex]
//            [3] OSMemoryBarrier() → Store-Release vor readIndex-Update
//            [4] Schreibe readIndex
//   Der Consumer sieht buffer[writeIndex] garantiert nach dem Producer-writeIndex-Update.
//   Der Producer sieht readIndex garantiert nach dem Consumer-readIndex-Update.
//
// ── Deprecation-Hinweis ───────────────────────────────────────────────────────
//   OSMemoryBarrier() ist seit macOS 12 als deprecated markiert.
//   Funktional korrekt auf allen aktuellen Apple-Plattformen.
//   Geplanter Ersatz: swift-atomics (ManagedAtomic<Int>,
//   .acquiringAndReleasing / .releasing / .acquiring Ordnungen).
//   In Swift 6: Synchronization.Atomic als stdlib-Alternative.
//
// ── Kapazität ─────────────────────────────────────────────────────────────────
//   64 Events — ausreichend für alle realistischen Burst-Szenarien.
//   Ein Akkord-Wechsel erzeugt max. 2×4 = 8 Events.
//   Bei Overflow wird das Event verworfen, aber (Runde 016 / F-02) nicht mehr
//   kommentarlos: `droppedEventCount` zählt jeden Drop, und ein Drop von
//   `.noteOff`/`.allOff` wird zusätzlich sofort geloggt (siehe push()). Kein
//   Lossless-Hard-Guarantee — das würde eine Producer-seitige Verschiebung von
//   readIndex erfordern und die Consumer-Alleinschreiberschaft auf readIndex
//   verletzen (siehe Invarianten oben). Stattdessen: Overflow bleibt sichtbar,
//   die Alleinschreiberschaft je Index bleibt unangetastet.

final class NoteEventQueue {

    private static let capacity = 64

    // Pre-allokierter Puffer – keine Heap-Allokation im Render-Pfad.
    private var buffer = [NoteEvent](
        repeating: NoteEvent(kind: .allOff, note: 0, velocity: 0),
        count: capacity
    )

    // writeIndex: ausschließlich vom Producer geschrieben.
    // readIndex:  ausschließlich vom Consumer (Audio-Thread) geschrieben.
    private var writeIndex: Int = 0
    private var readIndex:  Int = 0

    // droppedEventCount: nur vom Producer geschrieben (wie writeIndex) — kein
    // neuer Cross-Thread-Zugriff, keine zusätzliche Synchronisation nötig.
    private(set) var droppedEventCount: Int = 0

    // MARK: – Producer-API (genau ein Thread — siehe Invarianten oben)

    /// Schreibt ein Event in den Puffer.
    /// Gibt false zurück wenn der Puffer voll ist (Event wird verworfen).
    /// Overflow ist nie kommentarlos: `droppedEventCount` wird gezählt, und ein
    /// verworfenes `.noteOff`/`.allOff` wird sofort sichtbar geloggt.
    @discardableResult
    func push(_ event: NoteEvent) -> Bool {
        let next = (writeIndex + 1) % Self.capacity

        // Load-Acquire: Consumer könnte readIndex gerade vorgerückt haben —
        // sicherstellt, dass wir den aktuellen Wert sehen, nicht einen veralteten.
        OSMemoryBarrier()
        guard next != readIndex else {
            droppedEventCount += 1
            if event.kind == .noteOff || event.kind == .allOff {
                print("⚠️ NoteEventQueue: Puffer voll — \(event.kind) verworfen (insgesamt \(droppedEventCount) verworfene Events)")
            }
            return false   // Puffer voll
        }

        buffer[writeIndex] = event

        // Store-Release: buffer[writeIndex]-Schreibzugriff muss für den Consumer
        // sichtbar sein, bevor writeIndex selbst weiterrückt.
        OSMemoryBarrier()
        writeIndex = next
        return true
    }

    // MARK: – Consumer-API (Audio-Thread)

    /// Liest das nächste Event aus dem Puffer.
    /// Gibt nil zurück wenn der Puffer leer ist.
    func pop() -> NoteEvent? {
        // Load-Acquire: Producer könnte writeIndex gerade vorgerückt haben —
        // sicherstellt, dass wir den aktuellen Wert sehen, nicht einen veralteten.
        OSMemoryBarrier()
        guard readIndex != writeIndex else { return nil }

        let event = buffer[readIndex]

        // Store-Release: buffer[readIndex]-Lesezugriff abschließen, bevor
        // readIndex weiterrückt und der Producer den Slot als frei betrachtet.
        OSMemoryBarrier()
        readIndex = (readIndex + 1) % Self.capacity
        return event
    }
}
