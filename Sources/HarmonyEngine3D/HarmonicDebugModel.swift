import Foundation
import simd

// MARK: – HarmonicDebugModel
//
// Schreibgeschützte Datenbrücke zwischen AppModel (App Layer) und HarmonicRadarView (UI).
//
// Ausschließlich vom AppModel beschrieben — immer auf dem Main Thread via DispatchQueue.main.
// UI-Komponenten (HarmonicRadarView) lesen nur; sie schreiben niemals in dieses Modell.
//
// Zwei Aktualisierungspfade:
//
//   1. Kontinuierlich (via HarmonyScene.onRadarSnapshot, ~10 Hz):
//      localNodes, playerPosition, magnetTarget
//      → Zeigt aktuellen lokalen Zustand unabhängig von Akkord-Events.
//
//   2. Ereignisbasiert (via OutputCoordinator.onGraphHook, bei Akkord-Aktivierung):
//      lastDecision, activeChord
//      → Letzte bekannte RuntimeHarmonik-Entscheidung bleibt bis zum nächsten Akkord sichtbar.
//
// Kein SceneKit, kein AppSettings, keine Harmonielogik, keine Physik.
// Rein passiver Datenbehälter. Niemals für Entscheidungen verwenden.

final class HarmonicDebugModel: ObservableObject {

    // ── Ereignisbasiert (letzter bekannter RuntimeHarmonik-Output) ────────
    @Published var lastDecision:   HarmonicDecision? = nil
    @Published var activeChord:    String            = ""

    // ── Kontinuierlich aktualisiert (~10 Hz, Render-Thread → Main Thread) ─
    @Published var localNodes:     [LocalNode]       = []
    @Published var playerPosition: simd_float3       = .zero
    @Published var magnetTarget:   simd_float3?      = nil
}
