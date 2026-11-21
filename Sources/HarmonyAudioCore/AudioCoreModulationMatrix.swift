// MARK: – AudioCoreModulationMatrix
//
// S-05b (`.agent_handoff/latest_codex.md`, Runde 053), Scope B: feste,
// testbare Modulationsmatrix des Atmospheric-Synth-Fundaments
// (`SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 6.4). Haelt ausschliesslich die
// statische Routenbeschreibung (`AudioCoreModulationRoute`) — der laufende
// Modulationszustand (Makro-/LFO-/Huellenwerte) wird pro Auswertung als
// `AudioCoreModulationSourceValues` von aussen uebergeben, nicht von der
// Matrix selbst gehalten.
//
// Noch NICHT in `AudioCoreVoice`/`SynthNode`/Presets/UI verwendet (Nicht-
// Scope S-05b).
//
// Realtime-Vertrag: `evaluate(sources:)` alloziiert nicht (fester
// `Array`-Speicher aus dem Initialisierer, feste `AudioCoreModulationTargetValues`-
// Struct als Ergebnis statt `Dictionary`), sperrt nicht, nutzt keine
// Dispatch-/Task-/Actor-Ausfuehrung und schreibt nicht (kein `print`).

public struct AudioCoreModulationMatrix: Sendable, Equatable {

    /// Feste Obergrenze aktiver Routen — Handoff-Vorgabe S-05b.
    public static let maxRouteCount = 16

    /// Deterministische Reihenfolge: exakt die uebergebene Reihenfolge,
    /// hoechstens auf `maxRouteCount` Eintraege gekuerzt.
    public let routes: [AudioCoreModulationRoute]

    /// Baut die Matrix aus einer Routenliste. Mehr als `maxRouteCount`
    /// Routen werden deterministisch auf die ersten `maxRouteCount` Eintraege
    /// in der uebergebenen Reihenfolge gekuerzt — kein Zufall, kein
    /// stiller Datenverlust ausserhalb dieser dokumentierten Regel.
    public init(routes: [AudioCoreModulationRoute]) {
        self.routes = Array(routes.prefix(AudioCoreModulationMatrix.maxRouteCount))
    }

    /// Matrix ohne Routen — der leere Fall ist definiert: jede Auswertung
    /// liefert `AudioCoreModulationTargetValues()` (alle Ziele `0`).
    public static let empty = AudioCoreModulationMatrix(routes: [])

    /// Wertet alle aktivierten Routen in fester Reihenfolge aus, summiert
    /// mehrere Routen auf dasselbe Ziel deterministisch (Source-Wert *
    /// Amount, additiv akkumuliert) und klemmt jedes Ziel abschliessend auf
    /// `AudioCoreModulationTargetValues.range`. Deaktivierte Routen werden
    /// uebersprungen. Gleiche `sources`/`routes` liefern immer dasselbe
    /// Ergebnis.
    public func evaluate(sources: AudioCoreModulationSourceValues) -> AudioCoreModulationTargetValues {
        var result = AudioCoreModulationTargetValues()

        for route in routes {
            guard route.isEnabled else { continue }
            let sourceValue = sources[route.source]
            let contribution = sourceValue * route.amount
            guard contribution.isFinite else { continue }
            result[route.target] += contribution
        }

        result.clampAndSanitize()
        return result
    }
}
