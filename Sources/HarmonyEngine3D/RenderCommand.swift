import Foundation
import simd
import HarmonyShared

// MARK: – RenderCommand
//
// Atomarer Wert-Typ für Render-relevante Änderungen, die Main-/UI-/Combine-
// Code an den Renderthread übergibt (Runde 025 / E-05). Ersetzt lose
// Pending-Bool-/Tuple-Gruppen in HarmonyScene.swift (vormals pendingReload,
// pendingLightingUpdate, pendingNetwork/pendingNetworkIsCurated/
// pendingNetworkFilename, pendingEdgeRebuild, pendingVisibility,
// pendingCameraReset) — jeder Command trägt seinen vollständigen Wert
// selbst, statt sich auf mehrere getrennt gesetzte Felder zu verlassen, die
// theoretisch "zerrissen" (inkonsistent) gelesen werden könnten. Reine
// Trigger ohne Nutzdaten (reload/lightingUpdate/edgeRebuild/
// visibilityRebuild) bleiben payload-lose Cases — sie hatten nie ein
// Mehrfeld-Inkonsistenzproblem, nur ein Thread-Safety-Problem, das die
// gelockte RenderCommandQueue unten löst.

enum RenderCommand {
    case switchNetwork(ChordNetwork, isCurated: Bool, filename: String)
    case reload
    case lightingUpdate
    case edgeRebuild
    case visibilityRebuild
    case cameraReset(simd_float3)
}

// MARK: – RenderCommandQueue
//
// Kleine, lockgeschützte FIFO-Inbox für RenderCommand-Werte. enqueue(_:) ist
// von jedem Thread sicher aufrufbar — sowohl von Main-Thread-Combine-Sinks
// als auch von Render-Thread-internen Kaskaden (z. B. reloadAllChunks() löst
// .visibilityRebuild aus). drain() liefert alle seit dem letzten Aufruf
// angesammelten Commands FIFO-geordnet und leert die Queue atomar in einem
// Schritt — "vollständig oder gar nicht" statt einzelner, für sich genommen
// unsynchronisierter Flag-Lese-/Schreibzugriffe.

final class RenderCommandQueue {
    private var commands: [RenderCommand] = []
    private let lock = NSLock()

    func enqueue(_ command: RenderCommand) {
        lock.lock()
        commands.append(command)
        lock.unlock()
    }

    func drain() -> [RenderCommand] {
        lock.lock()
        let drained = commands
        commands.removeAll()
        lock.unlock()
        return drained
    }
}
