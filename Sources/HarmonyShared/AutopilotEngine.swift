import simd

// MARK: – AutopilotEngine
//
// Reine Traversierungslogik für das Akkord-Netzwerk.
// Kein SceneKit, kein AppSettings, kein UI.
// Positionen werden als simd_float3 übergeben – Konvertierung obliegt dem Aufrufer.

public struct AutopilotEngine {

    // ── State ─────────────────────────────────────────────────────────────
    public private(set) var targetPosition:  simd_float3? = nil
    public private(set) var targetChordName: String       = ""
    public private(set) var visited:         [String]     = []

    private let visitedMax = 4

    // Deterministische Kantenauswahl (Runde 038 / V-00b, Fable-5-Review
    // Finding A3): die gewichtete Kandidatenauswahl nutzte bisher den
    // globalen, unseeded System-RNG (`Float.random`) statt `SeededRNG` —
    // damit war dieselbe Autopilot-Fahrt über Prozessstarts hinweg nicht
    // reproduzierbar. Default-Seed ist fix, damit `AutopilotEngine()`
    // (Bestandsaufrufer, `HarmonyScene.swift`) weiterhin ohne Parameter
    // konstruierbar bleibt, aber deterministisch.
    private var rng: SeededRNG

    public init(seed: UInt64 = 0xA070_7107_0000_0001) {
        rng = SeededRNG(seed: seed)
    }

    // ── Reset (Netzwerkwechsel, Autopilot deaktiviert) ────────────────────
    public mutating func reset() {
        targetPosition  = nil
        targetChordName = ""
        visited.removeAll()
    }

    // ── Haupt-Update (einmal pro Frame) ──────────────────────────────────
    //
    // positions:     Akkordname → Weltposition (je nur eine sichtbare Instanz)
    // edges:         Netzwerkkanten (source/target = Akkordname, weight)
    // passThruRadius: Schiff gilt als „angekommen" wenn closer als dieser Wert
    // maxReach:      Kandidaten weiter als dieser Wert werden ignoriert
    //
    // Gibt false zurück wenn kein Ziel gefunden wurde (leeres Netz o. Ä.).

    @discardableResult
    public mutating func update(
        cameraPos:      simd_float3,
        passThruRadius: Float,
        maxReach:       Float,
        edges:          [EdgeData],
        positions:      [String: simd_float3]
    ) -> Bool {
        guard !positions.isEmpty else { return false }

        // Kein Ziel → nächsten Akkord ansteuern
        guard let current = targetPosition else {
            if let n = nearest(in: positions, from: cameraPos) {
                targetPosition  = n.pos
                targetChordName = n.name
                return true
            }
            return false
        }

        // Noch nicht angekommen → nichts tun
        guard simd_distance(cameraPos, current) < passThruRadius else { return true }

        // Angekommen: welcher Akkord war das?
        let arrivedName = closestName(to: current, in: positions)

        if !arrivedName.isEmpty && visited.last != arrivedName {
            visited.append(arrivedName)
            if visited.count > visitedMax { visited.removeFirst() }
        }

        // Kandidaten aus Netzwerkkanten aufbauen
        func buildCandidates(excluding excl: [String]) -> [(pos: simd_float3, weight: Float)] {
            edges
                .filter { $0.source == arrivedName && !excl.contains($0.target) }
                .compactMap { edge -> (simd_float3, Float)? in
                    guard let pos = positions[edge.target] else { return nil }
                    guard simd_distance(pos, cameraPos) < maxReach else { return nil }
                    return (pos, edge.weight)
                }
        }

        var candidates = buildCandidates(excluding: visited)
        if candidates.isEmpty {
            // Kürzeres Gedächtnis: verhindert Ping-Pong bei kurzen Netzzyklen
            candidates = buildCandidates(excluding: Array(visited.suffix(2)))
        }

        if !candidates.isEmpty {
            let total = candidates.reduce(0) { $0 + $1.weight }
            var r = rng.f() * total
            for c in candidates {
                r -= c.weight
                if r <= 0 {
                    setTarget(c.pos, in: positions)
                    return true
                }
            }
            setTarget(candidates.last!.pos, in: positions)
        } else {
            // Kein Netzwerkkandidat → räumlicher Fallback, visited respektieren
            let excludeNames = Set(visited + [arrivedName])
            if let n = nearest(in: positions, from: cameraPos,
                               excludingPos: current, excludingNames: excludeNames) {
                setTarget(n.pos, in: positions)
            } else {
                return false
            }
        }
        return true
    }

    // ── Hilfsfunktionen ──────────────────────────────────────────────────

    private mutating func setTarget(_ pos: simd_float3, in positions: [String: simd_float3]) {
        targetPosition  = pos
        targetChordName = closestName(to: pos, in: positions)
    }

    private func closestName(to pos: simd_float3, in positions: [String: simd_float3]) -> String {
        positions
            .min { simd_distance($0.value, pos) < simd_distance($1.value, pos) }?
            .key ?? ""
    }

    private func nearest(
        in positions:       [String: simd_float3],
        from cameraPos:     simd_float3,
        excludingPos:       simd_float3? = nil,
        excludingNames:     Set<String>  = []
    ) -> (name: String, pos: simd_float3)? {
        positions
            .filter { entry in
                if excludingNames.contains(entry.key) { return false }
                if let excl = excludingPos,
                   simd_distance(entry.value, excl) <= 1.0 { return false }
                return true
            }
            .min { simd_distance($0.value, cameraPos) < simd_distance($1.value, cameraPos) }
            .map { ($0.key, $0.value) }
    }
}
