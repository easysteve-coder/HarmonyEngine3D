import XCTest
@testable import HarmonyEngine3D

// MARK: – MelodyEngineTests
//
// Runde 038 / V-00b, Fable-5-Review Finding A3: `tick()` wählte den nächsten
// Ton bei mehreren gleich nahen Kandidaten bisher über den globalen,
// unseeded System-RNG (`randomElement()`). Diese Tests belegen, dass die
// Notenauswahl jetzt über `SeededRNG` deterministisch reproduzierbar ist.

final class MelodyEngineTests: XCTestCase {

    // MARK: – Helpers

    /// Baut eine MelodyEngine mit registrierter Wolke und liefert die
    /// resultierende Notensequenz über `count` Ticks. `energyLevel < 0.95`
    /// und ein bereits gesetzter `lastNote` (ab dem zweiten Tick) treiben
    /// den "close.filter"-Zweig an, der die seeded Auswahl nutzt.
    private func tickSequence(seed: UInt64, count: Int) -> [Int] {
        var engine = MelodyEngine(seed: seed)
        engine.addCloud(key: "cloud", root: 60)

        var notes: [Int] = []
        var now: TimeInterval = 0
        for _ in 0..<count {
            now += 0.5
            if let t = engine.tick(cloudKey: "cloud", proximity: 0.6, tempo: 1.0, velMax: 100, energyLevel: 0.5, now: now) {
                notes.append(t.note)
            }
        }
        return notes
    }

    // MARK: – Determinismus

    func test_tick_sameSeed_producesIdenticalSequence() {
        let seqA = tickSequence(seed: 42, count: 20)
        let seqB = tickSequence(seed: 42, count: 20)

        XCTAssertFalse(seqA.isEmpty)
        XCTAssertEqual(seqA, seqB, "Gleicher Seed muss dieselbe Notensequenz liefern")
    }

    func test_tick_differentSeed_canProduceDifferentSequence() {
        let seqA = tickSequence(seed: 1, count: 30)
        let seqB = tickSequence(seed: 987_654_321, count: 30)

        XCTAssertNotEqual(seqA, seqB, "Unterschiedliche Seeds sollten ueber genug Ticks unterschiedliche Sequenzen liefern")
    }

    // MARK: – Default-Init bleibt deterministisch

    func test_defaultInit_isDeterministicAcrossInstances() {
        // MelodyEngine() (Bestandsaufrufer, InteractionRuntime.swift) nutzt
        // den Default-Seed — zwei unabhaengig konstruierte Instanzen ohne
        // expliziten Seed muessen trotzdem identisch reagieren.
        var a = MelodyEngine()
        var b = MelodyEngine()
        a.addCloud(key: "cloud", root: 60)
        b.addCloud(key: "cloud", root: 60)

        var seqA: [Int] = []
        var seqB: [Int] = []
        var now: TimeInterval = 0
        for _ in 0..<15 {
            now += 0.5
            if let t = a.tick(cloudKey: "cloud", proximity: 0.6, tempo: 1.0, velMax: 100, energyLevel: 0.5, now: now) { seqA.append(t.note) }
            if let t = b.tick(cloudKey: "cloud", proximity: 0.6, tempo: 1.0, velMax: 100, energyLevel: 0.5, now: now) { seqB.append(t.note) }
        }
        XCTAssertEqual(seqA, seqB)
    }

    // MARK: – Bestehendes Verhalten bleibt unveraendert

    func test_tick_pickedNote_alwaysWithinAllowedStepFromLastNote() {
        var engine = MelodyEngine(seed: 7)
        engine.addCloud(key: "cloud", root: 60)
        var now: TimeInterval = 0
        var lastNote: Int? = nil
        for _ in 0..<25 {
            now += 0.5
            guard let t = engine.tick(cloudKey: "cloud", proximity: 0.6, tempo: 1.0, velMax: 100, energyLevel: 0.5, now: now) else { continue }
            if let last = lastNote {
                // maxStep bei energyLevel 0.5 ist 6 (siehe MelodyEngine.tick) —
                // die seeded Auswahl darf diese bestehende musikalische Regel
                // nicht verletzen.
                XCTAssertLessThanOrEqual(abs(t.note - last), 6)
            }
            lastNote = t.note
        }
    }
}
