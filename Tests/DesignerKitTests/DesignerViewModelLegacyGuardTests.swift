import XCTest
@testable import DesignerKit
import HarmonyShared
import HarmonyAuthoring

// MARK: – Runde 037 / V-00a: Legacy-Aktionen im Dokumentmodus (Finding A9)
//
// `load(networkIndex:in:)`, `saveLayout()`, `resetLayout()` und
// `toggleAutopilot()` schreiben/lesen Legacy-`.txt`-Netzwerkzustand
// (`nodes`/`edges` als Chunk-/Force-Layout-Daten, `autopilotActive` mit
// `filteredEdges`-Traversierung). Ohne Guard konnten sie ein offenes
// HarmonyWeb-Dokument in einen Mischzustand bringen (Architekturreview
// 2026-07-26, P1; Fable-5-Review Runde 036, Finding A9): `document` bleibt
// gesetzt, aber `nodes`/`edges` würden auf Legacy-Daten zeigen.
//
// Hinweis zu Nebeneffekten: Siehe `DesignerViewModelWorkspaceTests.swift` —
// dieselbe bekannte, bewusst in Kauf genommene Application-Support-Sidecar-
// Nebenwirkung gilt auch hier.

@MainActor
final class DesignerViewModelLegacyGuardTests: XCTestCase {

    private func makeDocumentViewModel() throws -> (vm: DesignerViewModel, tempURL: URL) {
        let nodeA = HarmonyNode(id: "n1", root: 0, type: .maj7, function: .tonic, midiNotes: [60, 64, 67, 71])
        let nodeB = HarmonyNode(id: "n2", root: 5, type: .dom7, function: .dominant, midiNotes: [65, 69, 72, 75])
        let edge  = HarmonyEdge(id: "e1", source: "n1", target: "n2", relationTypes: [.vToI], directed: true, layers: ["l1"])
        let layer = HarmonyLayer(id: "l1", name: "Layer 1", relationTypes: [.vToI])
        let map = HarmonyMap(schemaVersion: "1.0", id: "m-legacy-guard", name: "Test", layers: [layer], nodes: [nodeA, nodeB], edges: [edge])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("designerkit-legacy-guard-\(UUID().uuidString).json")
        try HarmonyMapCodec.encode(map).write(to: url)

        let vm = DesignerViewModel()
        vm.openHarmonyWebDocument(at: url, in: CGSize(width: 800, height: 600))
        return (vm, url)
    }

    // MARK: – load(networkIndex:in:)

    func test_load_isNoOpInDocumentMode() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }
        let nodeIDsBefore = Set(vm.nodes.map(\.id))
        let documentIDBefore = vm.harmonyMap?.id

        vm.load(networkIndex: 0, in: vm.canvasSize)

        XCTAssertEqual(vm.harmonyMap?.id, documentIDBefore, "Ein Legacy-Netzwerkladen darf ein offenes Dokument nicht ersetzen")
        XCTAssertEqual(Set(vm.nodes.map(\.id)), nodeIDsBefore, "Canvas-Nodes müssen die Dokument-Nodes bleiben, nicht Legacy-Chord-Nodes")
        XCTAssertTrue(vm.harmonyWebMode)
    }

    // MARK: – resetLayout() / saveLayout()

    func test_resetLayout_isNoOpInDocumentMode() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }
        let documentIDBefore = vm.harmonyMap?.id

        vm.resetLayout()

        XCTAssertEqual(vm.harmonyMap?.id, documentIDBefore, "resetLayout() darf im Dokumentmodus kein Legacy-Netzwerk nachladen")
        XCTAssertTrue(vm.harmonyWebMode)
    }

    func test_saveLayout_isNoOpInDocumentMode() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }
        let dirtyBefore = vm.document?.isDirty

        vm.saveLayout()

        XCTAssertEqual(vm.document?.isDirty, dirtyBefore, "saveLayout() darf den Dokument-Dirty-State nicht berühren")
    }

    // MARK: – toggleAutopilot()

    func test_toggleAutopilot_isNoOpInDocumentMode() throws {
        let (vm, url) = try makeDocumentViewModel()
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertFalse(vm.autopilotActive)
        vm.toggleAutopilot()

        XCTAssertFalse(vm.autopilotActive, "Der Legacy-Autopilot darf im Dokumentmodus nicht starten — er konkurriert sonst mit der K-07-Simulation")
    }

    // MARK: – applyDocument() setzt autopilotActive zurück

    func test_openingDocument_resetsStaleAutopilotActiveFlag() throws {
        // Simuliert ein stale "Autopilot läuft"-Flag aus dem Legacy-Modus
        // (Setzen direkt, ohne echten Legacy-Netzwerkload zu triggern — der
        // Guard-Test dafür ist `test_toggleAutopilot_isNoOpInDocumentMode`).
        // Das Flag darf nicht in den Dokumentmodus hinüberwirken, sonst
        // zeigt z. B. PlayerCursorView(isAutopilot:) einen Autopilot-Cursor,
        // obwohl der Game-Loop längst gestoppt ist.
        let vm = DesignerViewModel()
        vm.autopilotActive = true

        let nodeA = HarmonyNode(id: "n1", root: 0, type: .maj7, function: .tonic, midiNotes: [60, 64, 67, 71])
        let layer = HarmonyLayer(id: "l1", name: "Layer 1", relationTypes: [.vToI])
        let map = HarmonyMap(schemaVersion: "1.0", id: "m-autopilot-reset", name: "Test", layers: [layer], nodes: [nodeA], edges: [])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("designerkit-legacy-guard-autopilot-\(UUID().uuidString).json")
        try HarmonyMapCodec.encode(map).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        vm.openHarmonyWebDocument(at: url, in: vm.canvasSize)

        XCTAssertFalse(vm.autopilotActive, "applyDocument() muss ein stale Autopilot-Flag aus dem Legacy-Modus zurücksetzen")
    }
}
