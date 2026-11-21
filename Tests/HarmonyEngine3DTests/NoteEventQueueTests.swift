import XCTest
@testable import HarmonyEngine3D

// MARK: – NoteEventQueueTests
//
// Deckt den Ringpuffer-Vertrag von NoteEventQueue ab: FIFO-Reihenfolge, Verhalten
// bei Wrap-Around, sowie das Runde-016/F-02-Verhalten bei Overflow (Event wird
// verworfen, aber zählbar über `droppedEventCount` — nicht kommentarlos).
//
// Bewusst NICHT getestet: SynthNode/AudioEngine (echte Audio-Hardware/
// AVAudioEngine-Graph-Konstruktion; siehe Rücklauf-Begründung in
// .agent_handoff/latest_claude.md). NoteEventQueue/NoteEvent sind reines
// Foundation, ohne AVFoundation-Abhängigkeit — deshalb hier direkt testbar.

final class NoteEventQueueTests: XCTestCase {

    private func event(_ kind: NoteEvent.Kind, note: UInt8 = 0) -> NoteEvent {
        NoteEvent(kind: kind, note: note, velocity: 64)
    }

    func test_pushPop_preservesFIFOOrder() {
        let queue = NoteEventQueue()

        XCTAssertTrue(queue.push(event(.noteOn, note: 60)))
        XCTAssertTrue(queue.push(event(.noteOn, note: 62)))
        XCTAssertTrue(queue.push(event(.noteOff, note: 60)))

        XCTAssertEqual(queue.pop()?.kind, .noteOn)
        XCTAssertEqual(queue.pop()?.note, 62)
        XCTAssertEqual(queue.pop()?.kind, .noteOff)
        XCTAssertNil(queue.pop())
    }

    func test_pop_onEmptyQueue_returnsNil() {
        let queue = NoteEventQueue()
        XCTAssertNil(queue.pop())
    }

    func test_overflow_dropsEventButCountsIt() {
        let queue = NoteEventQueue()

        // Nutzbare Kapazität eines N-Slot-Ringpuffers mit diesem Full-Check ist
        // N-1 (der letzte Slot bleibt reserviert, um voll von leer zu unterscheiden).
        // NoteEventQueue.capacity ist intern 64 — hier bewusst ohne Kenntnis der
        // genauen Zahl: so lange pushen, bis push() zum ersten Mal fehlschlägt.
        var successfulPushes = 0
        while queue.push(event(.noteOn, note: UInt8(successfulPushes % 128))) {
            successfulPushes += 1
            if successfulPushes > 10_000 { XCTFail("Ringpuffer läuft nie über — Test-Annahme verletzt"); return }
        }

        XCTAssertGreaterThan(successfulPushes, 0)
        XCTAssertEqual(queue.droppedEventCount, 1)

        // Weiterer Push bei vollem Puffer: weiterhin false, Zähler steigt weiter —
        // Overflow ist zählbar, nicht nur ein einmaliges Ereignis.
        XCTAssertFalse(queue.push(event(.noteOff, note: 60)))
        XCTAssertEqual(queue.droppedEventCount, 2)
    }

    func test_wrapAround_preservesFIFOOrderAcrossRingBoundary() {
        let queue = NoteEventQueue()

        // Puffer bis knapp vor voll füllen, wieder leeren, erneut füllen — deckt
        // den Wrap-Around von writeIndex/readIndex ab (kein fixer Kapazitätswert
        // im Test, siehe test_overflow_dropsEventButCountsIt).
        var capacityMinusOne = 0
        while queue.push(event(.noteOn, note: 0)) { capacityMinusOne += 1 }
        for _ in 0..<capacityMinusOne { _ = queue.pop() }
        XCTAssertNil(queue.pop())

        XCTAssertTrue(queue.push(event(.noteOn, note: 10)))
        XCTAssertTrue(queue.push(event(.noteOn, note: 20)))
        XCTAssertTrue(queue.push(event(.noteOff, note: 10)))

        XCTAssertEqual(queue.pop()?.note, 10)
        XCTAssertEqual(queue.pop()?.note, 20)
        XCTAssertEqual(queue.pop()?.kind, .noteOff)
        XCTAssertNil(queue.pop())
    }

    func test_paramUpdateEvent_carriesParams() {
        let queue = NoteEventQueue()
        var params = SynthParams.defaults
        params.filterCutoff = 0.42

        XCTAssertTrue(queue.push(NoteEvent(kind: .paramUpdate, note: 0, velocity: 0, params: params)))
        let popped = queue.pop()
        XCTAssertEqual(popped?.kind, .paramUpdate)
        XCTAssertEqual(popped?.params.filterCutoff, 0.42)
    }
}
