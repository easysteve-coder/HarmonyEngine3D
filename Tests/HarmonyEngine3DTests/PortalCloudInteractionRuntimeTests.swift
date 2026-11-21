import XCTest
import simd
@testable import HarmonyEngine3D

// MARK: – PortalCloudInteractionRuntimeTests
//
// Runde 027 / E-06b, Scope D: deckt die Portal-/Bass- und Cloud-/Melody-
// Erweiterung von InteractionRuntime ab. Reine Value-/Runtime-Tests, keine
// SceneKit-/HarmonyScene-Instanziierung (siehe Begründung in
// InteractionRuntimeTests.swift). Melody-Tick-Tests nutzen ausschließlich
// die deterministischen Zweige von MelodyEngine.tick(...) (Round-Robin bei
// `lastNote < 0` oder `energyLevel >= 0.95`) — der `.randomElement()`-Zweig
// (aktive Referenznote + energyLevel < 0.95) ist bewusst nicht getestet, da
// nicht deterministisch reproduzierbar.

final class PortalCloudInteractionRuntimeTests: XCTestCase {

    // MARK: – Shared Helpers

    private func renderEffects(_ actions: [InteractionAction]) -> [InteractionRenderEffect] {
        actions.compactMap { if case .renderEffect(let e) = $0 { return e }; return nil }
    }

    private func outputEvents(_ actions: [InteractionAction]) -> [InteractionOutputEvent] {
        actions.compactMap { if case .outputEvent(let e) = $0 { return e }; return nil }
    }

    private func hasPortalHighlighted(_ effects: [InteractionRenderEffect], key: String, active: Bool) -> Bool {
        effects.contains {
            if case .setPortalHighlighted(let k, let a) = $0 { return k == key && a == active }
            return false
        }
    }

    private func hasCloudHighlighted(_ effects: [InteractionRenderEffect], key: String, active: Bool) -> Bool {
        effects.contains {
            if case .setCloudHighlighted(let k, let a) = $0 { return k == key && a == active }
            return false
        }
    }

    private func bassNoteOn(_ actions: [InteractionAction]) -> Int? {
        outputEvents(actions).compactMap { if case .bassNoteOn(let n) = $0 { return n }; return nil }.first
    }

    private func bassNoteOff(_ actions: [InteractionAction]) -> Int? {
        outputEvents(actions).compactMap { if case .bassNoteOff(let n) = $0 { return n }; return nil }.first
    }

    private func bassNoteOffs(_ actions: [InteractionAction]) -> [Int] {
        outputEvents(actions).compactMap { if case .bassNoteOff(let n) = $0 { return n }; return nil }
    }

    private func bassNoteOns(_ actions: [InteractionAction]) -> [Int] {
        outputEvents(actions).compactMap { if case .bassNoteOn(let n) = $0 { return n }; return nil }
    }

    private func melodyNoteOffs(_ actions: [InteractionAction]) -> [Int] {
        outputEvents(actions).compactMap { if case .melodyNoteOff(let n) = $0 { return n }; return nil }
    }

    private func melodyNoteOn(_ actions: [InteractionAction]) -> (note: Int, velocity: UInt8)? {
        outputEvents(actions).compactMap { if case .melodyNoteWithVelocity(let n, let v) = $0 { return (n, v) }; return nil }.first
    }

    // MARK: – Portal/Bass Helpers

    private func portalCandidate(_ key: String, at position: simd_float3, bassNote: Int? = 60) -> PortalInteractionCandidate {
        PortalInteractionCandidate(key: key, position: position, bassNote: bassNote)
    }

    private func portalConfig(entryRadius: Float = 10, exitRadius: Float = 15, approachRadius: Float = 45,
                               triggersArmed: Bool = true, bassHoldMode: Bool = false, bassOctaveShift: Int = 0) -> PortalInteractionConfig {
        PortalInteractionConfig(entryRadius: entryRadius, exitRadius: exitRadius, approachRadius: approachRadius,
                                 triggersArmed: triggersArmed, bassHoldMode: bassHoldMode, bassOctaveShift: bassOctaveShift)
    }

    private func portalInput(_ candidates: [PortalInteractionCandidate], config: PortalInteractionConfig) -> PortalInteractionInput {
        PortalInteractionInput(candidates: candidates, cameraPosition: .zero, config: config)
    }

    // MARK: – Portal/Bass: Approach

    func test_portalApproach_producesGlowAndNearestEvent() {
        var runtime = InteractionRuntime()
        let actions = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -20), bassNote: 40)], config: portalConfig()))

        XCTAssertTrue(renderEffects(actions).contains {
            if case .setPortalApproachGlow(let key, let proximity) = $0 { return key == "P1" && proximity > 0 }
            return false
        })
        guard case .nearestPortal(let bassNote, let proximity)? = outputEvents(actions).first else {
            return XCTFail("erwartet .nearestPortal")
        }
        XCTAssertEqual(bassNote, 40)
        XCTAssertGreaterThan(proximity, 0)
    }

    func test_portalApproachChange_resetsOldGlowFirst() {
        var runtime = InteractionRuntime()
        _ = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -20))], config: portalConfig()))

        let actions = runtime.updatePortal(portalInput([
            portalCandidate("P1", at: simd_float3(0, 0, -1000)),
            portalCandidate("P2", at: simd_float3(0, 0, -20)),
        ], config: portalConfig()))

        let effects = renderEffects(actions)
        guard case .resetPortalApproachGlow(let key) = effects.first! else {
            return XCTFail("erwartet .resetPortalApproachGlow als erste Action")
        }
        XCTAssertEqual(key, "P1")
    }

    // MARK: – Portal/Bass: Trigger

    func test_portalEntry_activatesHighlightAndBassNoteOnWithOctaveShiftClamp() {
        var runtime = InteractionRuntime()
        let actions = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -5), bassNote: 120)], config: portalConfig(bassOctaveShift: 20)))

        XCTAssertTrue(hasPortalHighlighted(renderEffects(actions), key: "P1", active: true))
        XCTAssertEqual(bassNoteOn(actions), 127)   // 120 + 20*12, geklammert auf 127
        XCTAssertEqual(runtime.portalActiveKey, "P1")
    }

    func test_portalExit_deactivatesHighlightAndBassNoteOffFromSnapshot() {
        var runtime = InteractionRuntime()
        let cfg = portalConfig(entryRadius: 10, exitRadius: 15, approachRadius: 45)
        _ = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -5), bassNote: 40)], config: cfg))
        XCTAssertEqual(runtime.portalActiveKey, "P1")

        let actions = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -20), bassNote: 40)], config: cfg))

        XCTAssertNil(runtime.portalActiveKey)
        XCTAssertTrue(hasPortalHighlighted(renderEffects(actions), key: "P1", active: false))
        XCTAssertEqual(bassNoteOff(actions), 40)
    }

    func test_bassHoldMode_preventsAutoOffOnExit() {
        var runtime = InteractionRuntime()
        _ = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -5))], config: portalConfig(bassHoldMode: true)))
        XCTAssertEqual(runtime.portalActiveKey, "P1")

        let actions = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -20))], config: portalConfig(bassHoldMode: true)))

        // Trigger deaktiviert weiterhin (Highlight geht aus), nur das Auto-Off bleibt aus.
        XCTAssertNil(runtime.portalActiveKey)
        XCTAssertTrue(hasPortalHighlighted(renderEffects(actions), key: "P1", active: false))
        XCTAssertNil(bassNoteOff(actions))
    }

    func test_bassNoteOff_unaffectedByOctaveShiftChangeBetweenOnAndOff() {
        var runtime = InteractionRuntime()
        let activateActions = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -5), bassNote: 40)], config: portalConfig(bassOctaveShift: 1)))
        guard let onNote = bassNoteOn(activateActions) else { return XCTFail("erwartet bassNoteOn") }
        XCTAssertEqual(onNote, 52)   // 40 + 12

        // bassOctaveShift ändert sich, während die Bass-Note noch klingt.
        let deactivateActions = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -20), bassNote: 40)], config: portalConfig(bassOctaveShift: 3)))
        guard let offNote = bassNoteOff(deactivateActions) else { return XCTFail("erwartet bassNoteOff") }

        XCTAssertEqual(offNote, onNote)
    }

    func test_portalCandidateWithoutBassNote_activatesHighlightButFiresNoBassNoteOn() {
        // Original-Semantik: ein Portal ohne bekannte Bass-Note kann trotzdem
        // zum Trigger werden (Highlight geht an), nur onBassNoteOn bleibt aus.
        var runtime = InteractionRuntime()
        let actions = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -5), bassNote: nil)], config: portalConfig()))

        XCTAssertTrue(hasPortalHighlighted(renderEffects(actions), key: "P1", active: true))
        XCTAssertNil(bassNoteOn(actions))
    }

    // MARK: – Gate 10 (Runde 062): Nachhol-noteOff bei bassHoldMode-Aus
    //
    // `bassOutputNotesByKey` bleibt bewusst NICHT die Datenquelle für den
    // Nachhol-Off (Snapshot, Einträge überleben `noteOff`) — die Tests hier
    // sichern konkret die Fallgrube aus dem Handoff ab (Gate 4/"Geister-Offs")
    // zusätzlich zu den funktionalen Kernfällen.

    func test_gate10_bassHoldModeTurnedOff_sendsCatchUpOffForHeldNoteAfterPortalLeft() {
        var runtime = InteractionRuntime()
        let holdCfg = portalConfig(bassHoldMode: true)

        _ = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -5), bassNote: 40)], config: holdCfg))
        let leaveActions = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -20), bassNote: 40)], config: holdCfg))
        XCTAssertTrue(bassNoteOffs(leaveActions).isEmpty, "Hold-Modus: Note bleibt beim Verlassen klingen")

        let actions = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -20), bassNote: 40)], config: portalConfig(bassHoldMode: false)))

        XCTAssertEqual(bassNoteOffs(actions), [40])
    }

    func test_gate10_bassHoldModeTurnedOff_keepsActivePortalNoteSoundingUntilLeft() {
        var runtime = InteractionRuntime()
        _ = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -5), bassNote: 40)], config: portalConfig(bassHoldMode: true)))
        XCTAssertEqual(runtime.portalActiveKey, "P1")

        let toggleOffActions = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -5), bassNote: 40)], config: portalConfig(bassHoldMode: false)))
        XCTAssertTrue(bassNoteOffs(toggleOffActions).isEmpty, "aktives Portal bekommt kein Off beim Moduswechsel")
        XCTAssertEqual(runtime.portalActiveKey, "P1")

        let leaveActions = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -20), bassNote: 40)], config: portalConfig(bassHoldMode: false)))
        XCTAssertEqual(bassNoteOffs(leaveActions), [40], "Off kommt erst beim tatsächlichen Verlassen")
    }

    func test_gate10_bassHoldModeTurnedOff_sendsOffForEveryHangingNoteExactlyOnce() {
        var runtime = InteractionRuntime()
        let holdCfg = portalConfig(bassHoldMode: true)

        _ = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -5), bassNote: 40)], config: holdCfg))
        _ = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -20), bassNote: 40)], config: holdCfg))
        _ = runtime.updatePortal(portalInput([portalCandidate("P2", at: simd_float3(0, 0, -5), bassNote: 50)], config: holdCfg))
        _ = runtime.updatePortal(portalInput([portalCandidate("P2", at: simd_float3(0, 0, -20), bassNote: 50)], config: holdCfg))

        let actions = runtime.updatePortal(portalInput([], config: portalConfig(bassHoldMode: false)))

        XCTAssertEqual(bassNoteOffs(actions), [40, 50], "je klingender Note genau ein Off, deterministisch nach Key sortiert")
    }

    func test_gate10_noGhostOff_forNoteAlreadyOffInTriggerMode() {
        var runtime = InteractionRuntime()
        let triggerCfg = portalConfig(bassHoldMode: false)

        _ = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -5), bassNote: 40)], config: triggerCfg))
        let leaveActions = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -20), bassNote: 40)], config: triggerCfg))
        XCTAssertEqual(bassNoteOffs(leaveActions), [40], "Off ist bereits im Trigger-Modus geflossen")

        // bassOutputNotesByKey["P1"] == 40 bleibt stehen (Snapshot-Falle aus
        // dem Handoff) — der Nachhol-Off darf sich NICHT darauf stützen.
        _ = runtime.updatePortal(portalInput([], config: portalConfig(bassHoldMode: true)))
        let actions = runtime.updatePortal(portalInput([], config: portalConfig(bassHoldMode: false)))

        XCTAssertTrue(bassNoteOffs(actions).isEmpty, "keine Geister-Offs für eine längst verstummte Note")
    }

    func test_gate10_bassHoldModeToggled_withoutPortalActivity_isIdempotentAndProducesNoOffs() {
        var runtime = InteractionRuntime()

        _ = runtime.updatePortal(portalInput([], config: portalConfig(bassHoldMode: false)))
        _ = runtime.updatePortal(portalInput([], config: portalConfig(bassHoldMode: true)))
        let a1 = runtime.updatePortal(portalInput([], config: portalConfig(bassHoldMode: false)))
        let a2 = runtime.updatePortal(portalInput([], config: portalConfig(bassHoldMode: false)))
        _ = runtime.updatePortal(portalInput([], config: portalConfig(bassHoldMode: true)))
        let a3 = runtime.updatePortal(portalInput([], config: portalConfig(bassHoldMode: false)))

        XCTAssertTrue(bassNoteOffs(a1).isEmpty)
        XCTAssertTrue(bassNoteOffs(a2).isEmpty, "wiederholtes Aus ohne Portalaktivität darf nicht erneut feuern")
        XCTAssertTrue(bassNoteOffs(a3).isEmpty)
    }

    func test_gate10_symmetryBalance_overMixedSequence_offsNeverExceedOnsAndNoNoteStaysUnwantedlySounding() {
        var runtime = InteractionRuntime()
        var onCount  = 0
        var offCount = 0

        func step(_ candidates: [PortalInteractionCandidate], bassHoldMode: Bool) {
            let actions = runtime.updatePortal(portalInput(candidates, config: portalConfig(bassHoldMode: bassHoldMode)))
            onCount  += bassNoteOns(actions).count
            offCount += bassNoteOffs(actions).count
        }

        step([portalCandidate("P1", at: simd_float3(0, 0, -5),  bassNote: 40)], bassHoldMode: true)
        step([portalCandidate("P1", at: simd_float3(0, 0, -20), bassNote: 40)], bassHoldMode: true)   // haengt
        step([portalCandidate("P2", at: simd_float3(0, 0, -5),  bassNote: 50)], bassHoldMode: true)
        step([portalCandidate("P2", at: simd_float3(0, 0, -20), bassNote: 50)], bassHoldMode: true)   // haengt
        step([], bassHoldMode: false)   // Nachhol-Off für beide

        XCTAssertEqual(onCount, 2)
        XCTAssertEqual(offCount, 2)
        XCTAssertLessThanOrEqual(offCount, onCount)

        // Kein Portal aktiv -> ein weiterer Aus-Zyklus darf nichts mehr auslösen.
        step([], bassHoldMode: true)
        step([], bassHoldMode: false)
        XCTAssertEqual(offCount, 2, "keine Note bleibt ungewollt klingend / kein doppeltes Off")
    }

    func test_gate10_deterministic_sameInputSequenceProducesSameActionSequence() {
        func runSequence() -> [Int] {
            var runtime = InteractionRuntime()
            let holdCfg = portalConfig(bassHoldMode: true)
            _ = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -5),  bassNote: 40)], config: holdCfg))
            _ = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -20), bassNote: 40)], config: holdCfg))
            _ = runtime.updatePortal(portalInput([portalCandidate("P2", at: simd_float3(0, 0, -5),  bassNote: 50)], config: holdCfg))
            _ = runtime.updatePortal(portalInput([portalCandidate("P2", at: simd_float3(0, 0, -20), bassNote: 50)], config: holdCfg))
            let final = runtime.updatePortal(portalInput([], config: portalConfig(bassHoldMode: false)))
            return bassNoteOffs(final)
        }

        let run1 = runSequence()
        let run2 = runSequence()
        XCTAssertEqual(run1, run2)
        XCTAssertEqual(run1, [40, 50])
    }

    // MARK: – Cloud/Melody Helpers

    private func cloudCandidate(_ key: String, at position: simd_float3) -> CloudInteractionCandidate {
        CloudInteractionCandidate(key: key, position: position)
    }

    private func cloudConfig(entryRadius: Float = 10, exitRadius: Float = 15, approachRadius: Float = 45,
                              triggersArmed: Bool = true, melodyTempo: Double = 1.0, melodyVelMax: Float = 88,
                              energyLevel: Float = 1.0, now: TimeInterval) -> CloudInteractionConfig {
        CloudInteractionConfig(entryRadius: entryRadius, exitRadius: exitRadius, approachRadius: approachRadius,
                                triggersArmed: triggersArmed, melodyTempo: melodyTempo, melodyVelMax: melodyVelMax,
                                energyLevel: energyLevel, now: now)
    }

    private func cloudInput(_ candidates: [CloudInteractionCandidate], config: CloudInteractionConfig) -> CloudInteractionInput {
        CloudInteractionInput(candidates: candidates, cameraPosition: .zero, config: config)
    }

    // MARK: – Cloud/Melody: Approach

    func test_cloudApproach_producesGlowAndNearestEvent() {
        var runtime = InteractionRuntime()
        let actions = runtime.updateCloud(cloudInput([cloudCandidate("C1", at: simd_float3(0, 0, -20))], config: cloudConfig(now: 1)))

        XCTAssertTrue(renderEffects(actions).contains {
            if case .setCloudApproachGlow(let key, let proximity) = $0 { return key == "C1" && proximity > 0 }
            return false
        })
        guard case .nearestCloud(let name, let proximity)? = outputEvents(actions).first else {
            return XCTFail("erwartet .nearestCloud")
        }
        XCTAssertEqual(name, "Melodie")
        XCTAssertGreaterThan(proximity, 0)
    }

    func test_cloudApproachChange_resetsOldGlowFirst() {
        var runtime = InteractionRuntime()
        _ = runtime.updateCloud(cloudInput([cloudCandidate("C1", at: simd_float3(0, 0, -20))], config: cloudConfig(now: 1)))

        let actions = runtime.updateCloud(cloudInput([
            cloudCandidate("C1", at: simd_float3(0, 0, -1000)),
            cloudCandidate("C2", at: simd_float3(0, 0, -20)),
        ], config: cloudConfig(now: 1.1)))

        let effects = renderEffects(actions)
        guard case .resetCloudApproachGlow(let key) = effects.first! else {
            return XCTFail("erwartet .resetCloudApproachGlow als erste Action")
        }
        XCTAssertEqual(key, "C1")
    }

    // MARK: – Cloud/Melody: Trigger + Tick

    func test_cloudTriggerEntry_activatesHighlight() {
        var runtime = InteractionRuntime()
        runtime.addCloud(key: "C1", root: 60)

        let actions = runtime.updateCloud(cloudInput([cloudCandidate("C1", at: simd_float3(0, 0, -5))], config: cloudConfig(now: 1)))

        XCTAssertTrue(hasCloudHighlighted(renderEffects(actions), key: "C1", active: true))
        XCTAssertEqual(runtime.cloudActiveKey, "C1")
    }

    func test_cloudTick_firstNoteAfterActivation_isDeterministicRoundRobin() {
        // lastNote < 0 nach Aktivierung -> Round-Robin-Zweig (deterministisch),
        // resetCloudIndex() setzt den Index auf 0 -> erste Note ist notes[0].
        var runtime = InteractionRuntime()
        runtime.addCloud(key: "C1", root: 60)
        _ = runtime.updateCloud(cloudInput([cloudCandidate("C1", at: simd_float3(0, 0, -5))], config: cloudConfig(now: 1)))

        let actions = runtime.updateCloud(cloudInput([cloudCandidate("C1", at: simd_float3(0, 0, -5))], config: cloudConfig(now: 11)))

        guard let tick = melodyNoteOn(actions) else { return XCTFail("erwartet melodyNoteWithVelocity") }
        XCTAssertEqual(tick.note, 60)   // buildScale(root: 60, "Dorian Penta")[0] == 60
    }

    func test_cloudTick_firesPreviousNoteOffBeforeNewNoteOn() {
        var runtime = InteractionRuntime()
        runtime.addCloud(key: "C1", root: 60)
        _ = runtime.updateCloud(cloudInput([cloudCandidate("C1", at: simd_float3(0, 0, -5))], config: cloudConfig(now: 1)))
        _ = runtime.updateCloud(cloudInput([cloudCandidate("C1", at: simd_float3(0, 0, -5))], config: cloudConfig(now: 11)))

        // energyLevel: 1.0 (>= 0.95) erzwingt weiterhin den deterministischen
        // Round-Robin-Zweig statt des `.randomElement()`-Zweigs.
        let actions = runtime.updateCloud(cloudInput([cloudCandidate("C1", at: simd_float3(0, 0, -5))], config: cloudConfig(now: 21)))

        let offIndex = actions.firstIndex { action in
            if case .outputEvent(.melodyNoteOff(let note)) = action { return note == 60 }
            return false
        }
        let onIndex = actions.firstIndex { action in
            if case .outputEvent(.melodyNoteWithVelocity) = action { return true }
            return false
        }
        guard let o = offIndex, let n = onIndex else { return XCTFail("erwartet beide Events") }
        XCTAssertLessThan(o, n, "melodyNoteOff für den Vorgängerton muss vor melodyNoteWithVelocity feuern")
    }

    func test_cloudTriggerExit_firesHighlightOffAndMelodyNoteOff() {
        var runtime = InteractionRuntime()
        runtime.addCloud(key: "C1", root: 60)
        let cfg = cloudConfig(entryRadius: 10, exitRadius: 15, approachRadius: 45, now: 1)
        _ = runtime.updateCloud(cloudInput([cloudCandidate("C1", at: simd_float3(0, 0, -5))], config: cfg))
        _ = runtime.updateCloud(cloudInput([cloudCandidate("C1", at: simd_float3(0, 0, -5))], config: cloudConfig(entryRadius: 10, exitRadius: 15, approachRadius: 45, now: 11)))

        let actions = runtime.updateCloud(cloudInput([cloudCandidate("C1", at: simd_float3(0, 0, -1000))], config: cloudConfig(entryRadius: 10, exitRadius: 15, approachRadius: 45, now: 21)))

        XCTAssertNil(runtime.cloudActiveKey)
        XCTAssertTrue(hasCloudHighlighted(renderEffects(actions), key: "C1", active: false))
        XCTAssertTrue(melodyNoteOffs(actions).contains(60))
    }

    func test_leavingCloudBelow008Proximity_stopsLastNoteExactlyOnce() {
        var runtime = InteractionRuntime()
        runtime.addCloud(key: "C1", root: 60)
        let entryCfg = cloudConfig(entryRadius: 10, exitRadius: 15, approachRadius: 45, now: 1)
        _ = runtime.updateCloud(cloudInput([cloudCandidate("C1", at: simd_float3(0, 0, -5))], config: entryCfg))
        _ = runtime.updateCloud(cloudInput([cloudCandidate("C1", at: simd_float3(0, 0, -5))], config: cloudConfig(entryRadius: 10, exitRadius: 15, approachRadius: 45, now: 11)))
        XCTAssertEqual(runtime.cloudActiveKey, "C1")

        // dist=12: noch im Exit-Radius (Hysterese hält aktiv), aber
        // triggerProximity (bezogen auf entryRadius=10) fällt auf 0 <= 0.08.
        let farCfg = cloudConfig(entryRadius: 10, exitRadius: 15, approachRadius: 45, now: 11.1)
        let actions = runtime.updateCloud(cloudInput([cloudCandidate("C1", at: simd_float3(0, 0, -12))], config: farCfg))

        XCTAssertEqual(runtime.cloudActiveKey, "C1")   // bleibt aktiv (Hysterese)
        XCTAssertTrue(melodyNoteOffs(actions).contains(60))

        // Zweiter Aufruf bei weiterhin niedriger Proximity darf NICHT erneut feuern (stop() ist idempotent).
        let secondActions = runtime.updateCloud(cloudInput([cloudCandidate("C1", at: simd_float3(0, 0, -12))], config: cloudConfig(entryRadius: 10, exitRadius: 15, approachRadius: 45, now: 11.2)))
        XCTAssertTrue(melodyNoteOffs(secondActions).isEmpty)
    }

    // MARK: – Melody-Preset-API

    func test_melodyPresetAPI_returnsNameAndCycles() {
        var runtime = InteractionRuntime()
        let initialName = runtime.currentMelodyPresetName
        runtime.addCloud(key: "C1", root: 60)

        let nextName = runtime.nextMelodyPreset()
        XCTAssertNotEqual(nextName, initialName)
        XCTAssertEqual(runtime.currentMelodyPresetName, nextName)

        let prevName = runtime.prevMelodyPreset()
        XCTAssertEqual(prevName, initialName)
        XCTAssertEqual(runtime.currentMelodyPresetName, initialName)
    }

    // MARK: – Reset-API (spiegelt reloadAllChunks/unloadChunk)

    func test_resetAll_clearsChordPortalAndCloudState() {
        var runtime = InteractionRuntime()
        runtime.addCloud(key: "C1", root: 60)
        _ = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -5))], config: portalConfig()))
        _ = runtime.updateCloud(cloudInput([cloudCandidate("C1", at: simd_float3(0, 0, -5))], config: cloudConfig(now: 1)))
        XCTAssertNotNil(runtime.portalActiveKey)
        XCTAssertNotNil(runtime.cloudActiveKey)

        runtime.resetAll()

        XCTAssertNil(runtime.portalActiveKey)
        XCTAssertNil(runtime.cloudActiveKey)
    }

    func test_removeBassOutputNote_clearsAndReturnsSnapshot() {
        var runtime = InteractionRuntime()
        _ = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -5), bassNote: 40)], config: portalConfig()))

        let removed = runtime.removeBassOutputNote(forKey: "P1")

        XCTAssertEqual(removed, 40)
        XCTAssertNil(runtime.bassOutputNote(forKey: "P1"))
    }

    func test_clearActivePortalTrigger_doesNotAffectCloudState() {
        var runtime = InteractionRuntime()
        runtime.addCloud(key: "C1", root: 60)
        _ = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -5))], config: portalConfig()))
        _ = runtime.updateCloud(cloudInput([cloudCandidate("C1", at: simd_float3(0, 0, -5))], config: cloudConfig(now: 1)))

        runtime.clearActivePortalTrigger()

        XCTAssertNil(runtime.portalActiveKey)
        XCTAssertEqual(runtime.cloudActiveKey, "C1")
    }

    // MARK: – Finding 062-01 (Runde 063): haengende Note beim Chunk-Entladen
    //
    // `HarmonyScene.unloadChunk` ist SceneKit und wird hier nicht instanziiert
    // (siehe Begründung oben). Die Nachweisführung läuft stattdessen auf
    // Runtime-Ebene: `simulateUnloadChunk` bildet exakt die neue
    // `unloadChunk`-Logik nach (`removeBassOutputNote` gefolgt vom bedingten
    // `clearActivePortalTrigger`) — das ist der einzige Ort, an dem
    // `HarmonyScene` überhaupt Verhalten hinzufügt; alle Entscheidungen fallen
    // in `InteractionRuntime`.

    @discardableResult
    private func simulateUnloadChunk(_ runtime: inout InteractionRuntime, key: String) -> Int? {
        let unloadedBassOutputNote = runtime.removeBassOutputNote(forKey: key)
        if runtime.portalActiveKey == key {
            runtime.clearActivePortalTrigger()
        }
        return unloadedBassOutputNote
    }

    func test_finding062_01_kernfall_holdModeNoteStillSoundingAfterLeaving_getsOffOnChunkUnload() {
        var runtime = InteractionRuntime()
        let holdCfg = portalConfig(bassHoldMode: true)
        _ = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -5), bassNote: 40)], config: holdCfg))
        let leaveActions = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -20), bassNote: 40)], config: holdCfg))
        XCTAssertTrue(bassNoteOffs(leaveActions).isEmpty, "Hold-Modus: Note klingt nach dem Verlassen weiter")
        XCTAssertNotEqual(runtime.portalActiveKey, "P1", "P1 ist nicht mehr das aktive Portal")

        let off = simulateUnloadChunk(&runtime, key: "P1")

        XCTAssertEqual(off, 40, "genau ein bassNoteOff für die noch klingende Note")
    }

    func test_finding062_01_aktivesPortalEntladen_genauEinOffNichtZwei() {
        var runtime = InteractionRuntime()
        let holdCfg = portalConfig(bassHoldMode: true)
        _ = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -5), bassNote: 40)], config: holdCfg))
        XCTAssertEqual(runtime.portalActiveKey, "P1")

        let off = simulateUnloadChunk(&runtime, key: "P1")

        XCTAssertEqual(off, 40, "genau ein Off für das aktive, entladene Portal")
        XCTAssertNil(runtime.portalActiveKey, "Trigger ist beim Entladen sauber zurückgesetzt")
    }

    func test_finding062_01_triggerModus_offBereitsGeflossen_keinZweitesOffBeimEntladen() {
        var runtime = InteractionRuntime()
        let triggerCfg = portalConfig(bassHoldMode: false)
        _ = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -5), bassNote: 40)], config: triggerCfg))
        let leaveActions = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -20), bassNote: 40)], config: triggerCfg))
        XCTAssertEqual(bassNoteOffs(leaveActions), [40], "Off ist bereits im Trigger-Modus geflossen")

        let off = simulateUnloadChunk(&runtime, key: "P1")

        XCTAssertNil(off, "kein zweites Off für eine bereits verstummte Note (Geister-Off-Gegentest)")
    }

    func test_finding062_01_nieGetriggertesPortalEntladen_keinOff() {
        var runtime = InteractionRuntime()
        // P1 taucht nur als Approach-/Kandidat auf, ohne je den Trigger-Radius
        // zu erreichen — nie aktiviert, daher nie in soundingBassNotesByKey.
        _ = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -40), bassNote: 40)], config: portalConfig()))
        XCTAssertNil(runtime.portalActiveKey)

        let off = simulateUnloadChunk(&runtime, key: "P1")

        XCTAssertNil(off, "kein Off für ein nie getriggertes Portal")
    }

    func test_finding062_01_zusammenspielMitGate10_entladenesPortalBekommtKeinZweitesNachholOff() {
        var runtime = InteractionRuntime()
        let holdCfg = portalConfig(bassHoldMode: true)
        _ = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -5),  bassNote: 40)], config: holdCfg))
        _ = runtime.updatePortal(portalInput([portalCandidate("P1", at: simd_float3(0, 0, -20), bassNote: 40)], config: holdCfg))
        _ = runtime.updatePortal(portalInput([portalCandidate("P2", at: simd_float3(0, 0, -5),  bassNote: 50)], config: holdCfg))
        let switchActions = runtime.updatePortal(portalInput([portalCandidate("P2", at: simd_float3(0, 0, -20), bassNote: 50)], config: holdCfg))
        XCTAssertTrue(bassNoteOffs(switchActions).isEmpty, "beide Portale haengen im Hold-Modus")

        // P1 haengt (nicht aktiv), P2 haengt (nicht aktiv) — P1 wird entladen.
        let unloadOff = simulateUnloadChunk(&runtime, key: "P1")
        XCTAssertEqual(unloadOff, 40, "Off fliesst beim Entladen von P1")

        // bassHoldMode aus: nur noch P2 darf ein Nachhol-Off bekommen.
        let toggleActions = runtime.updatePortal(portalInput([], config: portalConfig(bassHoldMode: false)))
        XCTAssertEqual(bassNoteOffs(toggleActions), [50], "P1 ist bereits entladen/beendet, kein zweites Off für 40")
    }

    func test_finding062_01_symmetriebilanz_ueberGemischteSequenzMitEntladen() {
        var runtime = InteractionRuntime()
        var onCount  = 0
        var offCount = 0

        func step(_ candidates: [PortalInteractionCandidate], bassHoldMode: Bool) {
            let actions = runtime.updatePortal(portalInput(candidates, config: portalConfig(bassHoldMode: bassHoldMode)))
            onCount  += bassNoteOns(actions).count
            offCount += bassNoteOffs(actions).count
        }

        step([portalCandidate("P1", at: simd_float3(0, 0, -5),  bassNote: 40)], bassHoldMode: true)
        step([portalCandidate("P1", at: simd_float3(0, 0, -20), bassNote: 40)], bassHoldMode: true)   // P1 haengt
        step([portalCandidate("P2", at: simd_float3(0, 0, -5),  bassNote: 50)], bassHoldMode: true)
        step([portalCandidate("P2", at: simd_float3(0, 0, -20), bassNote: 50)], bassHoldMode: true)   // P2 haengt

        if let off = simulateUnloadChunk(&runtime, key: "P1") { offCount += 1; XCTAssertEqual(off, 40) }
        step([], bassHoldMode: false)   // Nachhol-Off nur noch für P2

        XCTAssertEqual(onCount, 2)
        XCTAssertEqual(offCount, 2)
        XCTAssertLessThanOrEqual(offCount, onCount, "niemals mehr Offs als Ons")

        // Entladen von P1 nach seinem eigenen Off darf kein weiteres Off mehr auslösen.
        let repeatedUnload = simulateUnloadChunk(&runtime, key: "P1")
        XCTAssertNil(repeatedUnload, "P1 ist bereits beendet, kein Doppel-Off durch erneutes Entladen")
    }
}
