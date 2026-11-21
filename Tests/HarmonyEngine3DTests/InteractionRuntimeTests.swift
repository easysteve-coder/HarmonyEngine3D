import XCTest
import simd
import HarmonyShared
@testable import HarmonyEngine3D

// MARK: – InteractionRuntimeTests
//
// Runde 026 / E-06a, Scope C: deckt die SceneKit-freie Chord-Proximity-/
// Trigger-Extraktion ab. Reine Value-/Runtime-Tests, keine SceneKit-/
// HarmonyScene-Instanziierung (HarmonyScene baut echte SCNNode-Geometrie im
// Konstruktor — es existiert im gesamten Testbestand kein leichter Weg, eine
// Instanz ohne diese Kosten zu erzeugen; wie im Handoff als Ausweg
// vorgesehen sind die Runtime-Tests hier entsprechend umfassender statt
// einem separaten HarmonyScene-Adapter-Test).

final class InteractionRuntimeTests: XCTestCase {

    // MARK: – Helpers

    private func candidate(_ key: String, at position: simd_float3, notes: [Int] = [60, 64, 67], visible: Bool = true) -> ChordInteractionCandidate {
        ChordInteractionCandidate(key: key, position: position, chord: ChordData(name: key, midiNotes: notes), visible: visible)
    }

    private func config(entryRadius: Float = 10, exitRadius: Float = 15, approachRadius: Float = 45,
                         triggersArmed: Bool = true, voiceLeadingEnabled: Bool = false, chordOctaveShift: Int = 0) -> ChordInteractionConfig {
        ChordInteractionConfig(entryRadius: entryRadius, exitRadius: exitRadius, approachRadius: approachRadius,
                                triggersArmed: triggersArmed, voiceLeadingEnabled: voiceLeadingEnabled, chordOctaveShift: chordOctaveShift)
    }

    private func input(_ candidates: [ChordInteractionCandidate], config cfg: ChordInteractionConfig) -> ChordInteractionInput {
        ChordInteractionInput(candidates: candidates, cameraPosition: .zero, config: cfg)
    }

    private func renderEffects(_ actions: [InteractionAction]) -> [InteractionRenderEffect] {
        actions.compactMap { if case .renderEffect(let e) = $0 { return e }; return nil }
    }

    private func outputEvents(_ actions: [InteractionAction]) -> [InteractionOutputEvent] {
        actions.compactMap { if case .outputEvent(let e) = $0 { return e }; return nil }
    }

    private func activatedChord(_ actions: [InteractionAction]) -> ChordData? {
        outputEvents(actions).compactMap { if case .chordActivated(let c) = $0 { return c }; return nil }.first
    }

    private func deactivatedChord(_ actions: [InteractionAction]) -> ChordData? {
        outputEvents(actions).compactMap { if case .chordDeactivated(let c) = $0 { return c }; return nil }.first
    }

    private func hasHighlighted(_ effects: [InteractionRenderEffect], key: String, active: Bool) -> Bool {
        effects.contains {
            if case .setHighlighted(let k, let a) = $0 { return k == key && a == active }
            return false
        }
    }

    // MARK: – Approach

    func test_nearestVisibleCandidateWithinApproachRadius_producesApproachGlowAndNearestEvent() {
        var runtime = InteractionRuntime()
        let actions = runtime.updateChord(input([candidate("A", at: simd_float3(0, 0, -20))], config: config()))

        let effects = renderEffects(actions)
        guard let glow = effects.compactMap({ effect -> (String, Float)? in
            if case .setApproachGlow(let key, let proximity) = effect { return (key, proximity) }
            return nil
        }).first else { return XCTFail("erwartet .setApproachGlow") }
        XCTAssertEqual(glow.0, "A")
        XCTAssertGreaterThan(glow.1, 0)

        guard case .nearestChord(let name, let proximity)? = outputEvents(actions).first else {
            return XCTFail("erwartet .nearestChord")
        }
        XCTAssertEqual(name, "A")
        XCTAssertGreaterThan(proximity, 0)
    }

    func test_noCandidates_producesEmptyNearestEvent() {
        var runtime = InteractionRuntime()
        let actions = runtime.updateChord(input([], config: config()))

        guard case .nearestChord(let name, let proximity)? = outputEvents(actions).first else {
            return XCTFail("erwartet .nearestChord")
        }
        XCTAssertEqual(name, "")
        XCTAssertEqual(proximity, 0)
    }

    func test_approachKeyChange_resetsOldApproachGlowFirst() {
        var runtime = InteractionRuntime()
        _ = runtime.updateChord(input([candidate("A", at: simd_float3(0, 0, -20))], config: config()))

        // A verlässt den Approach-Radius, B tritt ein -> Approach wechselt zu B.
        let actions = runtime.updateChord(input([
            candidate("A", at: simd_float3(0, 0, -1000)),
            candidate("B", at: simd_float3(0, 0, -20)),
        ], config: config()))

        let effects = renderEffects(actions)
        guard case .resetApproachGlow(let key) = effects.first! else {
            return XCTFail("erwartet .resetApproachGlow als erste Action")
        }
        XCTAssertEqual(key, "A")
    }

    // MARK: – Trigger Entry/Exit/Hysterese

    func test_enteringEntryRadius_activatesChordAndHighlights() {
        var runtime = InteractionRuntime()
        let actions = runtime.updateChord(input([candidate("A", at: simd_float3(0, 0, -5))], config: config()))

        XCTAssertTrue(hasHighlighted(renderEffects(actions), key: "A", active: true))
        guard let activated = activatedChord(actions) else { return XCTFail("erwartet .chordActivated") }
        XCTAssertEqual(activated.name, "A")
        XCTAssertEqual(activated.midiNotes, [60, 64, 67])
        XCTAssertEqual(runtime.activeKey, "A")
    }

    func test_hysteresis_staysActiveBetweenEntryAndExitRadius() {
        var runtime = InteractionRuntime()
        let cfg = config(entryRadius: 10, exitRadius: 15, approachRadius: 45)
        _ = runtime.updateChord(input([candidate("A", at: simd_float3(0, 0, -5))], config: cfg))
        XCTAssertEqual(runtime.activeKey, "A")

        // Zwischen Entry (10) und Exit (15) -> hält den aktiven Trigger.
        let actions = runtime.updateChord(input([candidate("A", at: simd_float3(0, 0, -12))], config: cfg))

        XCTAssertEqual(runtime.activeKey, "A")
        XCTAssertNil(deactivatedChord(actions))
    }

    func test_leavingExitRadius_deactivatesChordAndUnhighlights() {
        var runtime = InteractionRuntime()
        let cfg = config(entryRadius: 10, exitRadius: 15, approachRadius: 45)
        _ = runtime.updateChord(input([candidate("A", at: simd_float3(0, 0, -5))], config: cfg))
        XCTAssertEqual(runtime.activeKey, "A")

        let actions = runtime.updateChord(input([candidate("A", at: simd_float3(0, 0, -20))], config: cfg))

        XCTAssertNil(runtime.activeKey)
        XCTAssertTrue(hasHighlighted(renderEffects(actions), key: "A", active: false))
        guard let deactivated = deactivatedChord(actions) else { return XCTFail("erwartet .chordDeactivated") }
        XCTAssertEqual(deactivated.name, "A")
    }

    // MARK: – triggersArmed

    func test_triggersArmedFalse_preventsActivation() {
        var runtime = InteractionRuntime()
        let actions = runtime.updateChord(input([candidate("A", at: simd_float3(0, 0, -5))], config: config(triggersArmed: false)))

        XCTAssertNil(runtime.activeKey)
        XCTAssertNil(activatedChord(actions))
    }

    func test_triggersArmedBecomesFalse_deactivatesActiveChordCleanly() {
        var runtime = InteractionRuntime()
        _ = runtime.updateChord(input([candidate("A", at: simd_float3(0, 0, -5))], config: config(triggersArmed: true)))
        XCTAssertEqual(runtime.activeKey, "A")

        let actions = runtime.updateChord(input([candidate("A", at: simd_float3(0, 0, -5))], config: config(triggersArmed: false)))

        XCTAssertNil(runtime.activeKey)
        guard let deactivated = deactivatedChord(actions) else {
            return XCTFail("erwartet .chordDeactivated bei triggersArmed=false")
        }
        XCTAssertEqual(deactivated.name, "A")
    }

    // MARK: – On/Off-Symmetrie

    func test_onOffSymmetry_survivesConfigChangeBetweenActivationAndDeactivation() {
        var runtime = InteractionRuntime()
        let activateCfg = config(voiceLeadingEnabled: false, chordOctaveShift: 1)
        let activateActions = runtime.updateChord(input([candidate("A", at: simd_float3(0, 0, -5), notes: [60, 64, 67])], config: activateCfg))
        guard let activated = activatedChord(activateActions) else { return XCTFail("erwartet chordActivated") }
        XCTAssertEqual(activated.midiNotes, [72, 76, 79])

        // Octave-Shift UND VoiceLeading ändern sich, während der Akkord noch klingt.
        let changedCfg = config(voiceLeadingEnabled: true, chordOctaveShift: 3)
        let deactivateActions = runtime.updateChord(input([candidate("A", at: simd_float3(0, 0, -20), notes: [60, 64, 67])], config: changedCfg))
        guard let deactivated = deactivatedChord(deactivateActions) else { return XCTFail("erwartet chordDeactivated") }

        XCTAssertEqual(deactivated.midiNotes, activated.midiNotes)
        XCTAssertEqual(deactivated.name, activated.name)
    }

    func test_octaveShiftClampsToValidMidiRange() {
        var runtime = InteractionRuntime()
        // Shift 20 Oktaven nach oben -> muss auf 127 geklammert werden.
        let actions = runtime.updateChord(input([candidate("A", at: simd_float3(0, 0, -5), notes: [120])], config: config(chordOctaveShift: 20)))
        guard let activated = activatedChord(actions) else { return XCTFail("erwartet chordActivated") }
        XCTAssertEqual(activated.midiNotes, [127])
    }

    // MARK: – VoiceLeading

    func test_voiceLeadingEnabled_pullsNotesTowardReferenceOctave() {
        var runtime = InteractionRuntime()
        _ = runtime.updateChord(input([candidate("Low", at: simd_float3(0, 0, -5), notes: [36, 40, 43])], config: config(voiceLeadingEnabled: true)))

        // "Low" verlässt Exit-Radius, "High" (hohe Oktave) tritt ein -> ein Wechsel.
        let actions = runtime.updateChord(input([
            candidate("Low",  at: simd_float3(0, 0, -1000), notes: [36, 40, 43]),
            candidate("High", at: simd_float3(0, 0, -5),    notes: [84, 88, 91]),
        ], config: config(voiceLeadingEnabled: true)))

        guard let activated = activatedChord(actions) else { return XCTFail("erwartet chordActivated fuer High") }
        XCTAssertNotEqual(activated.midiNotes, [84, 88, 91])
    }

    func test_voiceLeadingDisabled_leavesNotesUnchanged() {
        var runtime = InteractionRuntime()
        _ = runtime.updateChord(input([candidate("Low", at: simd_float3(0, 0, -5), notes: [36, 40, 43])], config: config(voiceLeadingEnabled: false)))

        let actions = runtime.updateChord(input([
            candidate("Low",  at: simd_float3(0, 0, -1000), notes: [36, 40, 43]),
            candidate("High", at: simd_float3(0, 0, -5),    notes: [84, 88, 91]),
        ], config: config(voiceLeadingEnabled: false)))

        guard let activated = activatedChord(actions) else { return XCTFail("erwartet chordActivated fuer High") }
        XCTAssertEqual(activated.midiNotes, [84, 88, 91])
    }

    // MARK: – Reset-/Unload-API (spiegelt reloadAllChunks/unloadChunk)

    func test_resetAll_clearsActiveKeyAndApproach() {
        var runtime = InteractionRuntime()
        _ = runtime.updateChord(input([candidate("A", at: simd_float3(0, 0, -5))], config: config()))
        XCTAssertNotNil(runtime.activeKey)

        runtime.resetAll()

        XCTAssertNil(runtime.activeKey)
        XCTAssertNil(runtime.lastApproachKey)
    }

    func test_outputNotes_surviveResetAll_forSymmetricDeactivationLookup() {
        // resetAll() räumt bewusst NICHT die Output-Notes auf (identisch zum
        // bisherigen Verhalten: chordOutputNotes wurde beim Reload nie
        // geleert) — HarmonyScene liest outputNotes(forKey:) VOR resetAll()
        // für das synthetische Deactivation-Event.
        var runtime = InteractionRuntime()
        _ = runtime.updateChord(input([candidate("A", at: simd_float3(0, 0, -5), notes: [60, 64, 67])], config: config(chordOctaveShift: 1)))
        let key = runtime.activeKey!
        XCTAssertEqual(runtime.outputNotes(forKey: key), [72, 76, 79])

        runtime.resetAll()

        XCTAssertEqual(runtime.outputNotes(forKey: key), [72, 76, 79])
    }

    func test_removeOutputNotes_clearsAndReturnsSnapshot() {
        var runtime = InteractionRuntime()
        _ = runtime.updateChord(input([candidate("A", at: simd_float3(0, 0, -5), notes: [60, 64, 67])], config: config()))
        let key = runtime.activeKey!

        let removed = runtime.removeOutputNotes(forKey: key)

        XCTAssertEqual(removed, [60, 64, 67])
        XCTAssertNil(runtime.outputNotes(forKey: key))
    }

    func test_clearActiveTrigger_resetsOnlyTrigger_notApproach() {
        var runtime = InteractionRuntime()
        _ = runtime.updateChord(input([candidate("A", at: simd_float3(0, 0, -5))], config: config()))
        XCTAssertNotNil(runtime.activeKey)
        XCTAssertNotNil(runtime.lastApproachKey)

        runtime.clearActiveTrigger()

        XCTAssertNil(runtime.activeKey)
        XCTAssertNotNil(runtime.lastApproachKey)
    }

    func test_clearApproach_onlyClearsWhenKeyMatches() {
        var runtime = InteractionRuntime()
        _ = runtime.updateChord(input([candidate("A", at: simd_float3(0, 0, -5))], config: config()))
        XCTAssertEqual(runtime.lastApproachKey, "A")

        runtime.clearApproach(ifEquals: "B")
        XCTAssertEqual(runtime.lastApproachKey, "A")

        runtime.clearApproach(ifEquals: "A")
        XCTAssertNil(runtime.lastApproachKey)
    }

    // MARK: – Runde 038 / V-00b: CH0-NoteOff-Symmetrie aus Snapshot (Fable A2)

    func test_candidateVanishesFromList_stillFiresNoteOffFromSnapshot() {
        var runtime = InteractionRuntime()
        _ = runtime.updateChord(input([candidate("A", at: simd_float3(0, 0, -5), notes: [60, 64, 67])], config: config(chordOctaveShift: 1)))
        XCTAssertEqual(runtime.activeKey, "A")
        XCTAssertEqual(runtime.outputNotes(forKey: "A"), [72, 76, 79])

        // "A" verschwindet komplett aus der Kandidatenliste — kein Kandidat
        // mit key "A" existiert mehr in diesem Frame (z. B. Sichtbarkeits-/
        // Reihenfolgewechsel ohne geordneten Unload). Vorher fiel das
        // gesamte NoteOff aus, weil es an `byKey[old]` gekoppelt war.
        let actions = runtime.updateChord(input([], config: config()))

        XCTAssertNil(runtime.activeKey)
        guard let deactivated = deactivatedChord(actions) else {
            return XCTFail("erwartet chordDeactivated auch ohne Kandidat in der aktuellen Liste")
        }
        XCTAssertEqual(deactivated.midiNotes, [72, 76, 79], "NoteOff muss die urspruenglich gesendeten (oktavverschobenen) Noten aus dem Snapshot nutzen, nicht die unverschobenen chord.midiNotes")
        XCTAssertEqual(deactivated.name, "A", "chordDeactivated muss den urspruenglich aktivierten Namen tragen, nicht \"\" — sonst kann OutputCoordinator soundingChordName nicht leeren (Runde 039 / V-00b.1)")
    }

    func test_candidateVanishesFromList_doesNotFireDoubleOff() {
        var runtime = InteractionRuntime()
        _ = runtime.updateChord(input([candidate("A", at: simd_float3(0, 0, -5))], config: config()))

        let firstFrame = runtime.updateChord(input([], config: config()))
        XCTAssertNotNil(deactivatedChord(firstFrame))

        let secondFrame = runtime.updateChord(input([], config: config()))
        XCTAssertNil(deactivatedChord(secondFrame), "Ein bereits deaktivierter Trigger darf kein zweites Mal chordDeactivated feuern")
    }

    func test_configChangeAndCandidateVanish_combined_stillUsesOriginalSnapshot() {
        // Kombiniert Octave-Shift-Wechsel (bestehende Symmetrie-Garantie)
        // mit Kandidatenverlust (neue Garantie) im selben Off-Frame.
        var runtime = InteractionRuntime()
        let activateActions = runtime.updateChord(input([candidate("A", at: simd_float3(0, 0, -5), notes: [60, 64, 67])], config: config(chordOctaveShift: 2)))
        guard let activated = activatedChord(activateActions) else { return XCTFail("erwartet chordActivated") }
        XCTAssertEqual(activated.midiNotes, [84, 88, 91])

        let changedCfg = config(chordOctaveShift: 5)
        let deactivateActions = runtime.updateChord(input([], config: changedCfg))

        guard let deactivated = deactivatedChord(deactivateActions) else { return XCTFail("erwartet chordDeactivated") }
        XCTAssertEqual(deactivated.midiNotes, activated.midiNotes)
        XCTAssertEqual(deactivated.name, activated.name)
    }

    // MARK: – Runde 039 / V-00b.1: Snapshot traegt Name UND Noten aus demselben Activate

    func test_candidateVanishesFromList_deactivatedChordNameMatchesOriginalActivation() {
        var runtime = InteractionRuntime()
        let activateActions = runtime.updateChord(input([candidate("Fmaj7", at: simd_float3(0, 0, -5), notes: [65, 69, 72, 76])], config: config()))
        guard let activated = activatedChord(activateActions) else { return XCTFail("erwartet chordActivated") }
        XCTAssertEqual(activated.name, "Fmaj7")

        // Kandidat verschwindet komplett — Name kann nicht mehr aus der
        // aktuellen Kandidatenliste rekonstruiert werden, muss also aus
        // demselben Snapshot wie die Noten kommen.
        let deactivateActions = runtime.updateChord(input([], config: config()))
        guard let deactivated = deactivatedChord(deactivateActions) else { return XCTFail("erwartet chordDeactivated") }

        XCTAssertEqual(deactivated.name, "Fmaj7", "Deactivation nach Kandidatenverlust muss den urspruenglich aktivierten Namen tragen, nicht \"\"")
        XCTAssertEqual(deactivated.midiNotes, activated.midiNotes)
    }

    func test_configChangeAndCandidateVanish_nameSurvivesToo() {
        // Wie test_configChangeAndCandidateVanish_combined_stillUsesOriginalSnapshot,
        // aber mit explizitem Fokus auf den Namen statt nur die Noten.
        var runtime = InteractionRuntime()
        let activateActions = runtime.updateChord(input([candidate("G7", at: simd_float3(0, 0, -5), notes: [67, 71, 74, 77])], config: config(voiceLeadingEnabled: false, chordOctaveShift: 1)))
        guard let activated = activatedChord(activateActions) else { return XCTFail("erwartet chordActivated") }

        let changedCfg = config(voiceLeadingEnabled: true, chordOctaveShift: 4)
        let deactivateActions = runtime.updateChord(input([], config: changedCfg))
        guard let deactivated = deactivatedChord(deactivateActions) else { return XCTFail("erwartet chordDeactivated") }

        XCTAssertEqual(deactivated.name, "G7")
        XCTAssertEqual(deactivated.name, activated.name)
        XCTAssertEqual(deactivated.midiNotes, activated.midiNotes)
    }

    func test_outputSnapshot_isCorrectlyCleanedUp_afterDeactivationAndAfterRemoval() {
        // Snapshot (Name + Noten) bleibt nach normaler Deaktivierung
        // erhalten (identisch zum bisherigen Notes-only-Verhalten, siehe
        // test_outputNotes_surviveResetAll_forSymmetricDeactivationLookup),
        // wird aber bei removeOutputNotes(forKey:) vollstaendig entfernt.
        var runtime = InteractionRuntime()
        let cfg = config(entryRadius: 10, exitRadius: 15, approachRadius: 45)
        _ = runtime.updateChord(input([candidate("A", at: simd_float3(0, 0, -5), notes: [60, 64, 67])], config: cfg))
        let key = runtime.activeKey!

        _ = runtime.updateChord(input([candidate("A", at: simd_float3(0, 0, -20))], config: cfg))
        XCTAssertNil(runtime.activeKey, "Vorbedingung: A wurde ueber Exit-Radius deaktiviert")
        XCTAssertEqual(runtime.outputNotes(forKey: key), [60, 64, 67], "Notes-Snapshot bleibt nach normaler Deaktivierung fuer Reload-/Reset-Lookups erhalten")

        let removed = runtime.removeOutputNotes(forKey: key)

        XCTAssertEqual(removed, [60, 64, 67])
        XCTAssertNil(runtime.outputNotes(forKey: key), "Nach removeOutputNotes(forKey:) darf kein Rest-Snapshot (weder Noten noch Name) mehr vorhanden sein")
    }

    // MARK: – Harmonic Impulse Ordering

    func test_triggerHarmonicImpulse_firesAfterChordActivatedEvent() {
        var runtime = InteractionRuntime()
        let actions = runtime.updateChord(input([candidate("A", at: simd_float3(0, 0, -5))], config: config()))

        let activatedIndex = actions.firstIndex { if case .outputEvent(.chordActivated) = $0 { return true }; return false }
        let impulseIndex = actions.firstIndex { if case .renderEffect(.triggerHarmonicImpulse) = $0 { return true }; return false }

        guard let a = activatedIndex, let i = impulseIndex else {
            return XCTFail("erwartet beide Actions")
        }
        XCTAssertLessThan(a, i, "triggerHarmonicImpulse muss nach chordActivated feuern (identisch zum bisherigen Ablauf)")
    }
}
