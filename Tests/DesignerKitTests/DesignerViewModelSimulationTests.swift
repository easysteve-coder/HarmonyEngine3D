import XCTest
@testable import DesignerKit
import HarmonyShared
import HarmonyAuthoring

// MARK: – Hinweis zu Nebeneffekten
//
// Siehe `DesignerViewModelWorkspaceTests.swift` — dieselbe bekannte,
// bewusst in Kauf genommene Application-Support-Sidecar-Nebenwirkung gilt
// auch hier.

@MainActor
final class DesignerViewModelSimulationTests: XCTestCase {

    private func makeDocumentViewModel(extraLayer: Bool = false) throws -> (vm: DesignerViewModel, tempURL: URL) {
        let nodeA = HarmonyNode(id: "n1", root: 0, type: .maj7, function: .tonic, midiNotes: [60, 64, 67, 71])
        let nodeB = HarmonyNode(id: "n2", root: 5, type: .dom7, function: .dominant, midiNotes: [65, 69, 72, 75])
        let nodeC = HarmonyNode(id: "n3", root: 2, type: .m7, function: .subdominant, midiNotes: [62, 65, 69, 72])
        let edge1 = HarmonyEdge(id: "e1", source: "n1", target: "n2", relationTypes: [.vToI], directed: true, layers: ["l1"])
        let edge2 = HarmonyEdge(id: "e2", source: "n2", target: "n3", relationTypes: [.commonTone], directed: true, layers: ["l1"])
        var layers = [HarmonyLayer(id: "l1", name: "Layer 1", relationTypes: [.vToI, .commonTone])]
        if extraLayer {
            layers.append(HarmonyLayer(id: "l2", name: "Layer 2", relationTypes: [.commonTone]))
        }
        let map = HarmonyMap(schemaVersion: "1.0", id: "m-simulation", name: "Test", layers: layers, nodes: [nodeA, nodeB, nodeC], edges: [edge1, edge2])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("designerkit-simulation-\(UUID().uuidString).json")
        try HarmonyMapCodec.encode(map).write(to: url)

        let vm = DesignerViewModel()
        vm.openHarmonyWebDocument(at: url, in: CGSize(width: 800, height: 600))
        vm.activeLayer = "l1"
        return (vm, url)
    }

    // MARK: – Gate: Errors blockieren, Warnings erlauben

    func test_startSimulation_blockedByValidatorErrors() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        // n2 löschen entfernt e1 (n1-n2) UND e2 (n2-n3) — n1 und n3 verlieren
        // dadurch ihre jeweils einzige Kante und werden global isoliert.
        vm.selectedId = "n2"
        vm.deleteSelectedNode()
        XCTAssertFalse(vm.canRunSimulation, "Vorbedingung: Draft ist jetzt invalide")

        vm.startSimulation(from: "n1")

        XCTAssertNil(vm.simulation, "Simulation darf bei Validator-Errors nicht starten")
    }

    func test_startSimulation_notBlockedByWarningsOnly() throws {
        let (vm, url) = try makeDocumentViewModel(extraLayer: true)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(vm.document?.diagnostics.errors.isEmpty ?? false)
        XCTAssertFalse(vm.document?.diagnostics.warnings.isEmpty ?? true, "Vorbedingung: nur Warnings (leerer l2-Layer)")

        vm.startSimulation(from: "n1")

        XCTAssertNotNil(vm.simulation, "Warnings dürfen die Simulation nicht blockieren")
    }

    // MARK: – Step aktualisiert Current/History

    func test_stepSimulation_updatesCurrentNodeAndHistory() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.startSimulation(from: "n1")
        XCTAssertEqual(vm.simulation?.currentNodeID, "n1")

        vm.stepSimulation()

        XCTAssertEqual(vm.simulation?.currentNodeID, "n2", "n1 hat nur eine ausgehende Kante zu n2")
        XCTAssertEqual(vm.simulation?.history, ["n1", "n2"])
    }

    func test_stepSimulation_blockedByValidatorErrors() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.startSimulation(from: "n1")
        XCTAssertNotNil(vm.simulation)

        // n3 löschen macht den Draft nicht invalide (n1<->n2 bleibt
        // verbunden) — für einen belastbaren Blockade-Nachweis muss n2
        // gelöscht werden (isoliert n1 UND n3, siehe
        // test_startSimulation_blockedByValidatorErrors).
        vm.selectedId = "n2"
        vm.deleteSelectedNode()
        XCTAssertFalse(vm.canRunSimulation, "Vorbedingung: Draft ist jetzt invalide")

        // Seit Runde 037 / V-00a invalidiert JEDE Draft-Mutation eine
        // laufende Simulation konservativ (Finding A7/A9, Fable-5-Review
        // Runde 036) — die Simulation ist hier bereits nil, bevor
        // stepSimulation() überhaupt aufgerufen wird. Vorher blieb die
        // Simulation eingefroren auf dem letzten Stand stehen, obwohl sie
        // eine eigene, jetzt veraltete Map-Kopie hielt.
        XCTAssertNil(vm.simulation, "Simulation muss nach jeder Draft-Mutation invalidiert werden, nicht nur eingefroren bleiben")

        vm.stepSimulation()

        XCTAssertNil(vm.simulation, "step() darf auf einer bereits invalidierten Simulation keine neue Instanz aufbauen")
    }

    // MARK: – Runde 037 / V-00a: Simulation wird bei JEDER Draft-Mutation invalidiert (Finding A7/A9)

    func test_validDraftMutation_stillInvalidatesRunningSimulation() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.startSimulation(from: "n1")
        XCTAssertNotNil(vm.simulation)

        // n3 löschen lässt den Draft valide (n1<->n2 bleibt verbunden über
        // e1) — die Simulation muss trotzdem invalidiert werden, weil sie
        // eine eigene Map-Kopie hält, die den gelöschten Node nicht kennt.
        vm.selectedId = "n3"
        vm.deleteSelectedNode()
        XCTAssertTrue(vm.canRunSimulation, "Vorbedingung: Draft bleibt valide")

        XCTAssertNil(vm.simulation, "Eine valide Draft-Mutation darf eine laufende Simulation trotzdem nicht ungeprüft weiterlaufen lassen")
    }

    func test_undoDocument_invalidatesRunningSimulation() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.selectedId = "n3"
        vm.deleteSelectedNode()
        vm.startSimulation(from: "n1")
        XCTAssertNotNil(vm.simulation)

        vm.undoDocument()

        XCTAssertNil(vm.simulation, "Undo muss eine laufende Simulation invalidieren — sie könnte sich sonst auf einen inzwischen wieder anderen Draft-Stand beziehen")
    }

    func test_redoDocument_invalidatesRunningSimulation() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.selectedId = "n3"
        vm.deleteSelectedNode()
        vm.undoDocument()
        vm.startSimulation(from: "n1")
        XCTAssertNotNil(vm.simulation)

        vm.redoDocument()

        XCTAssertNil(vm.simulation, "Redo muss eine laufende Simulation ebenso invalidieren wie ein normaler Command")
    }

    // MARK: – Layerwechsel aktualisiert Kandidaten

    func test_setSimulationLayer_updatesCandidatesAndActiveLayer() throws {
        let nodeA = HarmonyNode(id: "n1", root: 0, type: .maj7, function: .tonic, midiNotes: [60, 64, 67, 71])
        let nodeB = HarmonyNode(id: "n2", root: 5, type: .dom7, function: .dominant, midiNotes: [65, 69, 72, 75])
        let nodeC = HarmonyNode(id: "n3", root: 2, type: .m7, function: .subdominant, midiNotes: [62, 65, 69, 72])
        let l1 = HarmonyLayer(id: "l1", name: "Layer 1", relationTypes: [.vToI])
        let l2 = HarmonyLayer(id: "l2", name: "Layer 2", relationTypes: [.commonTone])
        let e1 = HarmonyEdge(id: "e1", source: "n1", target: "n2", relationTypes: [.vToI], directed: true, layers: ["l1"])
        let e2 = HarmonyEdge(id: "e2", source: "n1", target: "n3", relationTypes: [.commonTone], directed: true, layers: ["l2"])
        let map = HarmonyMap(schemaVersion: "1.0", id: "m-layer-sim", name: "Test", layers: [l1, l2], nodes: [nodeA, nodeB, nodeC], edges: [e1, e2])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("designerkit-layer-sim-\(UUID().uuidString).json")
        try HarmonyMapCodec.encode(map).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let vm = DesignerViewModel()
        vm.openHarmonyWebDocument(at: url, in: CGSize(width: 800, height: 600))
        vm.activeLayer = "l1"
        vm.startSimulation(from: "n1")

        XCTAssertEqual(vm.simulation?.candidates.map { $0.transition.targetNode.id }, ["n2"])

        vm.setSimulationLayer("l2")

        XCTAssertEqual(vm.simulation?.candidates.map { $0.transition.targetNode.id }, ["n3"])
        XCTAssertEqual(vm.activeLayer, "l2")
    }

    // MARK: – Seed/Reset deterministisch

    func test_resetSimulation_sameSeed_reproducesSequence() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.simulationSeed = 123
        vm.startSimulation(from: "n1")
        vm.stepSimulation()
        let firstNode = vm.simulation?.currentNodeID

        vm.resetSimulation()

        XCTAssertEqual(vm.simulation?.currentNodeID, "n1")
        vm.stepSimulation()
        XCTAssertEqual(vm.simulation?.currentNodeID, firstNode)
    }

    // MARK: – ViewModel zeigt effektive Gewichte aus der Simulation

    func test_simulationCandidates_exposeEffectiveWeightsAndPreviewFields() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.startSimulation(from: "n1")

        guard let candidate = vm.simulation?.candidates.first else {
            return XCTFail("Erwartete mindestens einen Kandidaten")
        }
        XCTAssertGreaterThan(candidate.transition.effectiveWeight, 0)
        XCTAssertEqual(candidate.transition.edge.relationTypes, [.vToI])
        XCTAssertEqual(candidate.fieldKind, HarmonicMagnetPreview.fieldKind(for: [.vToI]))
    }

    // MARK: – Runde 037 / V-00a: Dokumentwechsel invalidiert Simulation (Finding A4)

    func test_openingNewDocument_invalidatesRunningSimulationAndClosesPanel() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }
        vm.showSimulationPanel = true
        vm.startSimulation(from: "n1")
        XCTAssertNotNil(vm.simulation)

        let node2 = HarmonyNode(id: "other", root: 2, type: .m7, function: .subdominant, midiNotes: [62, 65, 69, 72])
        let layer2 = HarmonyLayer(id: "l2", name: "Layer 2", relationTypes: [.commonTone])
        let map2 = HarmonyMap(schemaVersion: "1.0", id: "m-sim-second", name: "Second", layers: [layer2], nodes: [node2], edges: [])
        let url2 = FileManager.default.temporaryDirectory
            .appendingPathComponent("designerkit-simulation-second-\(UUID().uuidString).json")
        try HarmonyMapCodec.encode(map2).write(to: url2)
        defer { try? FileManager.default.removeItem(at: url2) }

        vm.openHarmonyWebDocument(at: url2, in: vm.canvasSize)

        XCTAssertNil(vm.simulation, "Eine Simulation aus dem ersten Dokument darf im zweiten nicht weiterlaufen")
        XCTAssertFalse(vm.showSimulationPanel, "Simulations-Panel darf nach Dokumentwechsel nicht offen bleiben")
    }
}
