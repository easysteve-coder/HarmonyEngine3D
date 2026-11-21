# HarmonyNetwork — Implementierungsspezifikation v1

> **Für den Implementierungs-Chat.**
> Dieses Dokument beschreibt vollständig, was gebaut werden soll, wie die bestehende Codebasis
> aufgebaut ist, und welche Einschränkungen für v1 gelten.
> Kein Brainstorming mehr — konkret und umsetzbar.

Stand: 2026-04-05 | Supervision: ChatGPT | Design: Stephan Schmitt + Claude

---

## Projektziel (Einzeiler)

Ein **Instrument zur Navigation durch harmonische Räume** — Akkorde sind Nodes,
Beziehungen sind gerichtete Kräfte, Musik entsteht durch Bewegung im Netzwerk.

---

## Bestehende Codebasis — was du kennen musst

### Modulstruktur (SPM)

```
HarmonyShared     — ChordData, EdgeData, ChordNetwork, NetworkParser, AutopilotEngine
HarmonyEngine3D   — App, AudioEngine, HarmonyScene, OutputCoordinator, FlightController, ...
DesignerKit       — eigenständige App (2D-Editor, derzeit noch ohne Netzwerkmodell)
```

### Aktuelles Netzwerkformat (`.txt`, wird ERSETZT)

Bestehendes Format in `Sources/HarmonyShared/Resources/*.txt`:
```
chord Cmaj7 60 64 67 71
chord G7    67 71 74 77
neighbor G7 Cmaj7 1.0
```

`NetworkParser.parse(_:)` liest dieses Format.
`ChordGenerator.generate()` erzeugt 48 Akkorde algorithmisch als Fallback.

**Das neue JSON-Format wird parallel eingeführt. Das `.txt`-Format bleibt vorerst aktiv.**

### Datentypen in HarmonyShared (aktuell)

```swift
public struct ChordData   { let name: String; let midiNotes: [Int] }
public struct EdgeData     { let source: String; let target: String; let weight: Float }
public struct ChordNetwork { let chords: [ChordData]; let edges: [EdgeData] }
```

Diese Typen werden weiterhin intern verwendet. Das neue Modell ergänzt sie — ersetzt sie nicht in v1.

### Wie HarmonyScene das Netzwerk nutzt

- `HarmonyScene(network: ChordNetwork)` — bekommt das Netzwerk beim Init
- `chordDataMap: [String: ChordData]` — Dictionary für schnellen Lookup
- `onChordActivated: ((ChordData) -> Void)?` — Callback wenn Spieler Akkord betritt
- `onChordDeactivated: ((ChordData) -> Void)?` — Callback beim Verlassen
- Navigation basiert auf Proximity (Spieler fliegt durch 3D-Raum)
- Chunks werden befüllt mit Nodes aus dem Netzwerk

### OutputCoordinator

Einzige Verbindung zwischen HarmonyScene-Events und AudioOutput.
- CH0: Akkorde (noteOn/noteOff per voiced note)
- CH1: Bass
- CH2: Melodie
- CH3: Chord-Tones (Gamepad-Input)
- Invariante: symmetrisches noteOn/noteOff — gleiche Note, gleicher OctaveShift

### AudioEngine

4 vollständige Kanäle: synthChord, synthBass, synthMelody, synthChordTone.
Kein AppSettings-Zugriff. Kein Singleton. Reiner Event-Router.

---

## Was gebaut wird — Überblick

```
Stufe K (Konzept, bereits entschieden):
  K1: RelationTypes ✓
  K2: Datenmodell   ✓ (dieses Dokument)
  K3: Magnetphysik  → v2
  K4: JSON          ✓
  K5: Referenzmap   → jetzt bauen

Stufe 2 (Implementierung):
  2.1  HarmonyNode / HarmonyEdge / MagnetProfile / HarmonyMap — Swift-Typen in HarmonyShared
  2.2  HarmonyMapLoader — JSON → Swift-Typen
  2.3  HarmonyGraphEngine — neighbors, transitions, weightedChoice (+ Kontext)
  2.4  Referenzmap — reference-core.json
  2.5  Integration in AppModel (Loader aufrufen, ChordNetwork erzeugen)
```

**v1 ist fertig, wenn:** Man durch `reference-core.json` navigieren kann und
`weightedChoice` musikalisch nachvollziehbare Übergänge liefert.

---

## 1. RelationTypes (v1 — fix, nicht erweitern)

```swift
public enum RelationType: String, Codable {
    case vToI           = "V-I"
    case iiToV          = "ii-V"
    case relMajMin      = "relMajMin"
    case parallelMajMin = "parallelMajMin"
    case commonTone     = "commonTone"
    case tritSubst      = "tritSubst"
}
```

| Typ | Gerichtet | Stärke | Beschreibung |
|---|---|---|---|
| `V-I` | ja | stark | Dominant → Tonika; stärkste tonale Kraft |
| `ii-V` | ja | stark | Supertonica → Dominant; klassische Vorbereitung |
| `relMajMin` | nein | mittel | C-Dur ↔ a-Moll; Paralleltonart |
| `parallelMajMin` | nein | mittel | C-Dur ↔ c-Moll; gleichnamige Tonart |
| `commonTone` | nein | schwach | ≥ 2 gemeinsame Töne; Voice-Leading |
| `tritSubst` | quasi-sym. | mittel | Gb7 ↔ C7; Tritonussubstitution |

Repulsion: **nicht in v1**. Kein `attraction: false`. Kein Abstoßungs-Mechanismus.

---

## 2. Swift-Datenmodell (HarmonyShared)

### HarmonyNode

```swift
public struct HarmonyNode: Codable, Identifiable {
    public let id:       String              // Pflicht: z. B. "Gmaj7"
    public let root:     Int                 // Pflicht: MIDI-Grundton (0–127)
    public let type:     ChordType           // Pflicht
    public let function: HarmonicFunction   // Pflicht
    public let midiNotes: [Int]             // Pflicht: 3–5 MIDI-Noten
    public let tags:     [String]           // Optional: ["diatonic", "pivot"]
    public let layout3D: Layout3D?          // Optional: nil = Tonnetz-berechnet
}

public enum ChordType: String, Codable {
    case maj7, m7, dom7, m7b5, dim7, maj, min, sus4
}

public enum HarmonicFunction: String, Codable {
    case tonic, subdominant, dominant, ambiguous
}

public struct Layout3D: Codable {
    public let x: Float
    public let y: Float
    public let z: Float
}
```

### HarmonyEdge

```swift
public struct HarmonyEdge: Codable, Identifiable {
    public let id:            String          // Pflicht: z. B. "G7-Cmaj7"
    public let source:        String          // Pflicht: Node-ID
    public let target:        String          // Pflicht: Node-ID
    public let relationTypes: [RelationType] // Pflicht: mind. 1
    public let directed:      Bool           // Pflicht
    public let layers:        [String]       // Pflicht: mind. 1 Layer-ID
    public let weight:        Float          // Optional, default 1.0
    public let magnetProfile: MagnetProfile? // Optional
    public let bridgesTo:     String?        // Optional: Layer-ID (v1: wird geparst aber ignoriert)
}
```

### MagnetProfile

```swift
public struct MagnetProfile: Codable {
    public enum Preset: String, Codable { case strong, medium, weak }
    public let preset: Preset
    // v1: keine overrides — Preset reicht
}
```

Preset-Mapping (intern, nicht im JSON):
- `strong`: range 25, strength 1.0
- `medium`: range 15, strength 0.6
- `weak`:   range 8,  strength 0.3

### HarmonyLayer

```swift
public struct HarmonyLayer: Codable, Identifiable {
    public let id:            String
    public let name:          String
    public let relationTypes: [RelationType]   // welche Typen in diesem Layer sichtbar
}
```

### HarmonyMap (Top-Level)

```swift
public struct HarmonyMap: Codable {
    public let schemaVersion: String      // Pflicht: "1.0"
    public let id:            String      // Pflicht: Datei-Identifier
    public let name:          String      // Pflicht: Anzeigename
    public let layers:        [HarmonyLayer]
    public let nodes:         [HarmonyNode]
    public let edges:         [HarmonyEdge]
    public let layout:        MapLayout?  // Optional, getrennt
}

public struct MapLayout: Codable {
    public let strategy: String           // "tonnetz" | "manual"
    // nodeOverrides: in v1 nicht benötigt
}
```

---

## 3. JSON-Schema v1

### Vollständiges Beispiel (ursprüngliche Referenzmap — 7 Kanten)

> Die produktive `reference-core.json` hat inzwischen 11 Kanten (4 weitere funktionale
> Kanten ergänzt: G7→Am7, Am7→Dm7, Cmaj7→Fmaj7-functional, Fmaj7→G7).
> Das untenstehende Beispiel zeigt den Ursprungszustand als Minimaldokumentation des Schemas.

```json
{
  "schemaVersion": "1.0",
  "id": "reference-core",
  "name": "Core Functional (C-Dur)",
  "layers": [
    {
      "id": "functional",
      "name": "Functional",
      "relationTypes": ["V-I", "ii-V"]
    },
    {
      "id": "modal",
      "name": "Modal",
      "relationTypes": ["relMajMin", "commonTone"]
    }
  ],
  "nodes": [
    { "id": "Cmaj7",  "root": 60, "type": "maj7",  "function": "tonic",       "midiNotes": [60, 64, 67, 71] },
    { "id": "Am7",    "root": 69, "type": "m7",    "function": "tonic",       "midiNotes": [69, 72, 76, 79] },
    { "id": "Fmaj7",  "root": 65, "type": "maj7",  "function": "subdominant", "midiNotes": [65, 69, 72, 76] },
    { "id": "G7",     "root": 67, "type": "dom7",  "function": "dominant",    "midiNotes": [67, 71, 74, 77] },
    { "id": "Dm7",    "root": 62, "type": "m7",    "function": "subdominant", "midiNotes": [62, 65, 69, 72] },
    { "id": "Em7",    "root": 64, "type": "m7",    "function": "tonic",       "midiNotes": [64, 67, 71, 74] },
    { "id": "Db7",    "root": 61, "type": "dom7",  "function": "dominant",    "midiNotes": [61, 65, 68, 71] }
  ],
  "edges": [
    { "id": "G7-Cmaj7",    "source": "G7",    "target": "Cmaj7",  "relationTypes": ["V-I"],      "directed": true,  "layers": ["functional"], "weight": 1.0,  "magnetProfile": { "preset": "strong" } },
    { "id": "Dm7-G7",      "source": "Dm7",   "target": "G7",     "relationTypes": ["ii-V"],     "directed": true,  "layers": ["functional"], "weight": 0.95, "magnetProfile": { "preset": "strong" } },
    { "id": "Cmaj7-Am7",   "source": "Cmaj7", "target": "Am7",    "relationTypes": ["relMajMin"],"directed": false, "layers": ["modal"],      "weight": 0.85, "magnetProfile": { "preset": "medium" } },
    { "id": "Fmaj7-Dm7",   "source": "Fmaj7", "target": "Dm7",    "relationTypes": ["relMajMin"],"directed": false, "layers": ["modal"],      "weight": 0.80, "magnetProfile": { "preset": "medium" } },
    { "id": "Em7-Cmaj7",   "source": "Em7",   "target": "Cmaj7",  "relationTypes": ["commonTone"],"directed": false,"layers": ["modal"],      "weight": 0.65, "magnetProfile": { "preset": "weak" }   },
    { "id": "Db7-Cmaj7",   "source": "Db7",   "target": "Cmaj7",  "relationTypes": ["tritSubst"], "directed": true, "layers": ["functional"], "weight": 0.85, "magnetProfile": { "preset": "medium" } },
    { "id": "Cmaj7-Fmaj7", "source": "Cmaj7", "target": "Fmaj7",  "relationTypes": ["commonTone"],"directed": false,"layers": ["modal"],      "weight": 0.70, "magnetProfile": { "preset": "weak" }   }
  ],
  "layout": {
    "strategy": "tonnetz"
  }
}
```

**Datei-Ablageort:** `Sources/HarmonyShared/Resources/maps/reference-core.json`

---

## 4. HarmonyMapLoader

```swift
public enum HarmonyMapLoader {

    /// Lädt eine Map aus dem Bundle (HarmonyShared)
    public static func load(named filename: String) -> HarmonyMap? {
        // HINWEIS: SPM .process("Resources") legt .json-Dateien auf macOS an der
        // Bundle-Wurzel ab — subdirectory: "maps" würde nil liefern. Nicht hinzufügen.
        guard
            let url  = Bundle.module.url(forResource: filename, withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else {
            print("⚠️  HarmonyMapLoader: \(filename).json nicht gefunden")
            return nil
        }
        do {
            return try JSONDecoder().decode(HarmonyMap.self, from: data)
        } catch {
            print("⚠️  HarmonyMapLoader: Dekodierungsfehler: \(error)")
            return nil
        }
    }

    /// Konvertiert HarmonyMap → ChordNetwork (Kompatibilität mit bestehendem System)
    public static func toChordNetwork(_ map: HarmonyMap, layer: String? = nil) -> ChordNetwork {
        let chords = map.nodes.map { ChordData(name: $0.id, midiNotes: $0.midiNotes) }
        let edges: [EdgeData] = map.edges
            .filter { layer == nil || $0.layers.contains(layer!) }
            .map { EdgeData(source: $0.source, target: $0.target, weight: $0.weight) }
        return ChordNetwork(chords: chords, edges: edges)
    }
}
```

---

## 5. HarmonyGraphEngine

```swift
public final class HarmonyGraphEngine {

    private let map:          HarmonyMap
    private var activeLayer:  String
    private var history:      [String] = []   // max. 2 Einträge (letzte Nodes)
    private var rng:          SeededRNG        // deterministisch wenn Seed gesetzt

    public init(map: HarmonyMap, initialLayer: String = "functional", seed: UInt64? = nil) {
        self.map         = map
        self.activeLayer = initialLayer
        self.rng         = SeededRNG(seed: seed ?? UInt64(Date().timeIntervalSince1970))
    }

    // MARK: – API

    public func neighbors(of nodeID: String) -> [HarmonyNode] {
        activeEdges(from: nodeID).compactMap { edge in
            let targetID = edge.source == nodeID ? edge.target : edge.source
            return map.nodes.first { $0.id == targetID }
        }
    }

    public func transitions(from nodeID: String) -> [HarmonyEdge] {
        activeEdges(from: nodeID)
    }

    /// Wählt den nächsten Node basierend auf gewichteter Zufallsauswahl + Kontext.
    /// Deterministisch wenn mit Seed initialisiert.
    public func weightedChoice(from nodeID: String) -> HarmonyNode? {
        let candidates = transitions(from: nodeID)
        guard !candidates.isEmpty else { return nil }

        // Effektive Gewichte berechnen (Basis × Kontext-Modulation)
        let weighted = candidates.map { edge -> (HarmonyEdge, Float) in
            let targetID = edge.source == nodeID ? edge.target : edge.source
            return (edge, effectiveWeight(edge: edge, targetID: targetID))
        }

        // Gewichtete Zufallsauswahl
        let total = weighted.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return nil }
        var pick  = Float(rng.nextDouble()) * total
        for (edge, w) in weighted {
            pick -= w
            if pick <= 0 {
                let targetID = edge.source == nodeID ? edge.target : edge.source
                return map.nodes.first { $0.id == targetID }
            }
        }
        return map.nodes.first { $0.id == weighted.last!.0.target }
    }

    public func setLayer(_ layerID: String) {
        guard map.layers.contains(where: { $0.id == layerID }) else { return }
        activeLayer = layerID
        print("🎛  Layer gewechselt → \(layerID)")
    }

    public func recordVisit(_ nodeID: String) {
        history.append(nodeID)
        if history.count > 2 { history.removeFirst() }
    }

    // MARK: – Kontext-Modulation

    // Regel 1 — ii-V-Boost:
    //   Wenn letzter Schritt eine ii-V-Kante war → V-I-Kante × 1.5
    //
    // Regel 2 — Rückkehr-Dämpfung:
    //   Wenn Zielknoten in den letzten 2 Schritten besucht → × 0.4
    //
    // Regel 3 — Spannungserhalt:
    //   Wenn 2 aufeinanderfolgende starke Kanten (V-I, ii-V) → schwache Kanten × 1.3

    private func effectiveWeight(edge: HarmonyEdge, targetID: String) -> Float {
        var weight = edge.weight

        // Regel 1
        if edge.relationTypes.contains(.vToI),
           let prevEdge = lastEdge(), prevEdge.relationTypes.contains(.iiToV) {
            weight *= 1.5
            // debugLog("ii-V-Boost auf \(edge.id)")
        }

        // Regel 2
        if history.contains(targetID) {
            weight *= 0.4
            // debugLog("Rückkehr-Dämpfung auf \(targetID)")
        }

        // Regel 3
        let isWeak   = edge.relationTypes.allSatisfy { $0 == .commonTone || $0 == .relMajMin || $0 == .parallelMajMin }
        let lastWasStrong = lastEdge()?.relationTypes.contains(where: { $0 == .vToI || $0 == .iiToV }) == true
        let prevWasStrong = prevEdge()?.relationTypes.contains(where: { $0 == .vToI || $0 == .iiToV }) == true
        if isWeak && lastWasStrong && prevWasStrong {
            weight *= 1.3
            // debugLog("Spannungserhalt-Boost auf \(edge.id)")
        }

        return max(weight, 0)
    }

    // MARK: – Hilfsmethoden

    private func activeEdges(from nodeID: String) -> [HarmonyEdge] {
        map.edges.filter { edge in
            edge.layers.contains(activeLayer) &&
            (edge.source == nodeID || (!edge.directed && edge.target == nodeID))
        }
    }

    private func lastEdge() -> HarmonyEdge? {
        guard history.count >= 1 else { return nil }
        let from = history.count >= 2 ? history[history.count - 2] : history[0]
        let to   = history.last!
        return map.edges.first { ($0.source == from && $0.target == to) ||
                                 (!$0.directed && $0.source == to && $0.target == from) }
    }

    private func prevEdge() -> HarmonyEdge? {
        guard history.count >= 2 else { return nil }
        let from = history[0]
        let to   = history[1]
        return map.edges.first { ($0.source == from && $0.target == to) ||
                                 (!$0.directed && $0.source == to && $0.target == from) }
    }
}
```

**Wichtig:** `SeededRNG` existiert bereits in der Codebasis. Verwenden, nicht neu implementieren.

---

## 6. Integration in AppModel

```swift
// In AppModel.init():

// Neue Map laden (parallel zum bestehenden ChordNetwork)
if let harmonyMap = HarmonyMapLoader.load(named: "reference-core") {
    let graphEngine = HarmonyGraphEngine(map: harmonyMap, initialLayer: "functional")
    let network     = HarmonyMapLoader.toChordNetwork(harmonyMap, layer: "functional")
    let s = HarmonyScene(network: network)
    // graphEngine-Referenz in AppModel halten für später
}
```

**Aktueller Stand (nach erster Runtime-Integration):**
`graphEngine` ist instanziiert, gehalten und über zwei minimale Hooks verdrahtet:

- `OutputCoordinator.onGraphHook`: wird bei jedem `onChordActivated`-Event aufgerufen —
  loggt Vorschlag, ruft `recordVisit` auf (Kontext-Pflege)
- `HarmonyScene.graphSuggest`: Closure in `loadChunk` — verstärkt den empfohlenen Akkord
  im Chunk-Pool mit ×2.0-Bias (temporär; wird durch Phase-4.3-Magnetismus ersetzt)

Die Proximity-Navigation läuft weiterhin über das bisherige System. Die Engine beeinflusst
bislang nur die Wahrscheinlichkeitsverteilung bei der Chunk-Generierung.

---

## 7. Package.swift — neue Ressource

In `HarmonyShared`-Target:
```swift
resources: [
    .process("Resources"),       // bestehend
    // maps/-Ordner liegt unter Resources/maps/
]
```

Ordnerstruktur:
```
Sources/HarmonyShared/Resources/
  maps/
    reference-core.json          ← neu
  network.txt                    ← bestehend, bleibt
  network_jazz.txt               ← bestehend, bleibt
  ...
```

---

## 8. Validierung (Loader-seitig, nicht DesignerKit)

Beim Laden prüfen:
- Alle `edge.source` und `edge.target` zeigen auf existierende Node-IDs
- Alle `edge.layers` referenzieren existierende Layer-IDs
- Keine doppelten Node-IDs
- Keine doppelten Edge-IDs
- `schemaVersion == "1.0"` (hard check — kein stilles Weiterlaufen bei Mismatch)

Bei Fehler: `nil` zurückgeben + Fehlermeldung, Fallback auf `ChordGenerator.generate()`.

---

## 9. DesignerKit — v1-Scope (minimal)

**Für v1 genügt manuelle JSON-Erstellung.** DesignerKit wird noch NICHT für das
neue Format umgebaut.

Vorbereitung für spätere Integration:
- `HarmonyMap`, `HarmonyNode`, `HarmonyEdge` in `HarmonyShared` (shared zwischen beiden Targets)
- DesignerKit kann diese Typen importieren wenn es soweit ist
- Kein eigener DesignerKit-Code in diesem Schritt

---

## 10. v1-Constraints (unveränderlich)

| Feature | v1 | Später |
|---|---|---|
| Layer-Wechsel | nur explizit (D-Pad) | + Bridge-Kanten |
| bridgesTo | wird geparst, nicht genutzt | aktiv in v2 |
| Repulsion | nicht vorhanden | `attraction: false` |
| MagnetProfile | 3 Presets | vollparametrisch |
| Context History | 2 Schritte | 4 Schritte |
| weightedChoice | deterministisch (SeededRNG) | opt. probabilistisch |
| DesignerKit | manuelle JSON-Erstellung | visueller Editor |
| AudioClock | keine Integration | nach v1 |
| Melodie-Quantisierung | keine | nach v1 |

---

## 11. Schnittstelle weight vs. magnetProfile (NICHT vermischen)

| Eigenschaft | System | Bedeutung |
|---|---|---|
| `edge.weight` | GraphEngine / `weightedChoice` | Auswahlwahrscheinlichkeit (logisch) |
| `magnetProfile.preset` | FlightController / Physik | Räumliche Anziehungskraft (physikalisch) |

`weight` entscheidet, welcher Akkord als nächstes kommt.
`magnetProfile` entscheidet, wie stark der Spieler in diese Richtung gezogen wird.
Diese beiden Systeme arbeiten unabhängig voneinander.

---

## 12. Checkliste „v1 fertig"

- [x] `HarmonyNode`, `HarmonyEdge`, `HarmonyLayer`, `HarmonyMap` in HarmonyShared
- [x] `HarmonyMapLoader.load(named:)` + `toChordNetwork(_:layer:)` funktionsfähig
- [x] `reference-core.json` im Bundle, wird geladen ohne Fehler
- [x] `HarmonyGraphEngine` instanziierbar, `weightedChoice` gibt sinnvolle Ergebnisse
- [x] Validierung schlägt an bei defekten Edge-Referenzen
- [x] AppModel instanziiert GraphEngine + erste Runtime-Verdrahtung (onGraphHook, graphSuggest)
- [x] Bestehende `.txt`-Netzwerke laufen weiterhin ohne Änderung

---

## Architektur-Invarianten (aus ROADMAP.md)

- System ist nach jedem Schritt **buildbar und lauffähig**
- `SeededRNG` bleibt deterministisch: gleicher Seed = identische Welt
- Netzwerk erzeugt Möglichkeiten — Navigation wählt daraus (strikte Trennung)
- Kein `AppSettings.shared` in HarmonyCore/HarmonyShared
- Render-Closure des Synth: keine Allokationen, kein Swift-Concurrency
- **On/Off-Symmetrie:** gleiche Note auf noteOn und noteOff
- **CH3-Mapping:** aktiver Akkord liefert nur Mapping-Tabelle, nicht das Trigger-Ereignis

---

*Dieses Dokument ersetzt kein ARCHITECTURE.md oder ROADMAP.md — es ist die konkrete
Implementierungsgrundlage für den nächsten Entwicklungsschritt.*
