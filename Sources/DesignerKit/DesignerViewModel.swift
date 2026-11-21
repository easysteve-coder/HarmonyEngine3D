import Foundation
import SwiftUI
import HarmonyShared
import HarmonyAuthoring

// MARK: – Layout-Node

struct LayoutNode: Identifiable {
    let id: String
    var name: String
    var midiNotes: [Int]
    var position: CGPoint
    var velocity: CGPoint = .zero
    /// Nur im HarmonyWeb-/Dokumentmodus relevant (Workspace-State, K-03) —
    /// im Legacy-`.txt`-Netzwerkmodus immer `false`. Ein gepinnter Node wird
    /// von `forceLayout` nicht mehr bewegt.
    var pinned: Bool = false
}

/// Minimale, UI-Framework-freie Kanteninformation fuer `forceLayout` — bewusst
/// nicht `EdgeData`, damit die reine Layout-Geometrie nicht mit der Frage
/// verwechselt wird, ob `EdgeData` gerade die musikalische Datenquelle ist
/// (im HarmonyWeb-/Dokumentmodus ist sie das seit K-03 nicht mehr).
private struct LayoutEdge {
    let source: String
    let target: String
    let weight: Float
}

// MARK: – Button-Mapping

struct ButtonMapping: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case off         = "—"
        case note        = "Note"
        case cc          = "CC"
        case networkPrev = "Netz ◁"
        case networkNext = "Netz ▷"
        case allNotesOff = "All Off"
        case toggleHelp  = "Hilfe"
        case editToggle  = "Edit/Play"
        case autopilot   = "Autopilot"
    }
    var kind:    Kind = .off
    var channel: Int  = 0      // 0-indexed
    var number:  Int  = 60     // note or CC number
    var value:   Int  = 100    // velocity or CC value
}

// MARK: – Persistiertes Layout

private struct SavedLayout: Codable {
    var name:      String
    var positions: [String: [Double]]
    var edges:     [SavedEdge]

    struct SavedEdge: Codable {
        var source: String
        var target: String
        var weight: Double
    }
}

// Layout-Dateien werden nach Netzwerk-Filename gespeichert (nicht Index),
// damit User-Netzwerke auch nach Hinzufügen weiterer Netzwerke korrekt geladen werden.
private func layoutFileURL(forFilename filename: String) -> URL? {
    guard let appSupport = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
    let dir = appSupport.appendingPathComponent("Harmony2D/layouts", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("\(filename).json")
}

private func loadSavedLayout(forFilename filename: String) -> SavedLayout? {
    guard let url = layoutFileURL(forFilename: filename),
          let data = try? Data(contentsOf: url),
          let layout = try? JSONDecoder().decode(SavedLayout.self, from: data) else { return nil }
    return layout
}

// MARK: – Chord-Typ und Grundton

private let majorScaleIntervals = [0, 2, 4, 5, 7, 9, 11]

private func rootNote(of name: String) -> Int {
    if name.hasPrefix("C#") || name.hasPrefix("Db") { return 1 }
    if name.hasPrefix("D#") || name.hasPrefix("Eb") { return 3 }
    if name.hasPrefix("F#") || name.hasPrefix("Gb") { return 6 }
    if name.hasPrefix("G#") || name.hasPrefix("Ab") { return 8 }
    if name.hasPrefix("A#") || name.hasPrefix("Bb") { return 10 }
    switch name.first {
    case "C": return 0;  case "D": return 2;  case "E": return 4
    case "F": return 5;  case "G": return 7;  case "A": return 9
    case "B": return 11; default:  return 0
    }
}

// MARK: – ViewModel

@MainActor
final class DesignerViewModel: ObservableObject {

    // ── Layout ────────────────────────────────────────────────────────────
    @Published var nodes:         [LayoutNode]  = []
    @Published var edges:         [EdgeData]    = []
    @Published var selectedId:    String?        = nil
    @Published var selectedEdge:  (source: String, target: String)? = nil
    @Published var networkIndex:  Int            = 0
    @Published var isLayoutReady: Bool           = false

    // ── Navigation ────────────────────────────────────────────────────────
    @Published var playerPosition: CGPoint = .zero
    @Published var activeChordId:  String? = nil

    // ── HarmonyWeb-Modus ──────────────────────────────────────────────────
    // Wenn document gesetzt ist, befindet sich DesignerKit im Web-Ansichtsmodus.
    // Kein Node-/Edge-/Layer-Edit-Zugriff auf das Web in K-02 — nur
    // Visualisierung, Validierung und Dokument-I/O (New/Open/Save/Save As).
    @Published private(set) var document:  HarmonyMapDocument? = nil
    @Published var activeLayer:            String              = "functional"
    @Published var selectedWebName:        String              = ""
    /// Zuletzt fehlgeschlagene Dokumentaktion (Open/Save/Save As) — für eine
    /// UI-Fehlermeldung, kein stilles Verschlucken.
    @Published var documentErrorMessage:   String?             = nil
    /// Selektierte Edge im Dokumentmodus (K-05) — getrennt von `selectedEdge`
    /// (Legacy-`.txt`-Modus, `EdgeData`-Tupel ohne stabile ID).
    @Published var selectedDocumentEdgeID: String?             = nil
    /// Layer, der aktuell im Layer-Manager bearbeitet wird (K-05).
    @Published var selectedLayerID:        String?             = nil
    @Published var showLayerManager:       Bool                = false

    // ── Workspace (K-03): 2D-Editorzustand getrennt vom musikalischen Draft ─
    // Positionen/Pins/Zoom/aktiver Layer für das aktuelle Dokument. Wird nie
    // in die Map-JSON geschrieben — eigener Sidecar via `HarmonyMapWorkspaceStore`.
    // Workspace-Änderungen setzen NIE `document.isDirty` (das beschreibt nur
    // Map-Draft-Mutationen).
    @Published private(set) var workspace: HarmonyMapWorkspaceState = HarmonyMapWorkspaceState()

    private let recentDocuments = RecentDocumentsStore()

    private var workspaceKey: WorkspaceKey? {
        guard let document else { return nil }
        return WorkspaceKey(origin: document.origin, mapID: document.draft.id)
    }

    /// Aktuell geladene HarmonyMap (Web-Ansichtsmodus). Gespiegelt aus
    /// `document.draft` — `document` bleibt die kanonische Quelle.
    var harmonyMap: HarmonyMap? { document?.draft }

    /// Statische Liste bekannter HarmonyWeb-Bundle-Templates.
    static let availableWebNames: [String] = [
        "harmony-web-c-diatonic",
        "harmony-web-c-center",
        "reference-core"
    ]

    /// true wenn ein Dokument geladen ist.
    var harmonyWebMode: Bool { document != nil }

    /// Kurzer Statustext für die Toolbar: Dateiname/Template/„Neu" + Dirty-
    /// Sternchen.
    var documentStatusText: String {
        guard let document else { return "" }
        switch document.origin {
        case .unsaved:
            return "Neu" + (document.isDirty ? "*" : "")
        case .file(let url):
            return url.lastPathComponent + (document.isDirty ? "*" : "")
        case .readOnlyTemplate(let name):
            return "\(name) (Vorlage)"
        }
    }

    var documentIsReadOnly: Bool { document?.isReadOnly ?? false }

    /// `true` wenn `save()` direkt möglich ist (normales Datei-Dokument).
    /// Für neue Dokumente und Bundle-Templates ist nur Save As vorgesehen.
    var canSaveDocument: Bool {
        guard let document else { return false }
        if case .file = document.origin { return true }
        return false
    }

    /// „N Fehler · M Warnungen" aus dem echten `HarmonyMapValidator`-Ergebnis
    /// des Dokuments (zusätzlich zu den bestehenden Ad-hoc-Prüfungen in
    /// `webValidationWarnings`).
    var documentDiagnosticsSummary: String {
        guard let document else { return "" }
        let errors   = document.diagnostics.errors.count
        let warnings = document.diagnostics.warnings.count
        if errors == 0 && warnings == 0 { return "OK" }
        return "\(errors) Fehler · \(warnings) Warnungen"
    }

    /// Alle Kanten der geladenen HarmonyMap, gefiltert auf sichtbare Knoten.
    /// Gibt alle Kanten zurück — Layer-Opacity wird in drawWebEdges() gesteuert.
    var webEdgesForDisplay: [HarmonyEdge] {
        guard let map = harmonyMap else { return [] }
        let visibleIds = Set(filteredNodes.map { $0.id })
        return map.edges.filter {
            visibleIds.contains($0.source) && visibleIds.contains($0.target)
        }
    }

    /// Layer-IDs der geladenen HarmonyMap (für den Layer-Picker).
    var availableLayers: [String] {
        harmonyMap?.layers.map { $0.id } ?? []
    }

    /// Validierungswarnungen für die aktuell geladene HarmonyMap.
    /// Prüft: doppelte Node-IDs, kaputte Referenzen, Namenskonvention.
    var webValidationWarnings: [String] {
        guard let map = harmonyMap else { return [] }
        var warnings: [String] = []

        // Doppelte Node-IDs (sollte durch HarmonyMapLoader bereits abgefangen sein)
        let nodeIDs = map.nodes.map { $0.id }
        let uniqueIDs = Set(nodeIDs)
        if nodeIDs.count != uniqueIDs.count {
            warnings.append("Doppelte Node-IDs vorhanden")
        }

        // Kaputte Kanten-Referenzen
        for edge in map.edges {
            if !uniqueIDs.contains(edge.source) {
                warnings.append("Kante \(edge.id): source '\(edge.source)' nicht in Nodes")
            }
            if !uniqueIDs.contains(edge.target) {
                warnings.append("Kante \(edge.id): target '\(edge.target)' nicht in Nodes")
            }
        }

        // Namenskonventions-Prüfung (ARCHITECTURE.md):
        // Schema: ^[A-G][#b]?(maj7|m7b5|dim7|m7|7|dim|maj|m)?$
        let pattern = "^[A-G][#b]?(maj7|m7b5|dim7|m7|7|dim|maj|m)?$"
        let regex = try? NSRegularExpression(pattern: pattern)
        for node in map.nodes {
            let range = NSRange(node.id.startIndex..., in: node.id)
            if regex?.firstMatch(in: node.id, range: range) == nil {
                warnings.append("Node '\(node.id)' verletzt Namenskonvention")
            }
        }

        return warnings
    }

    // ── Edit-Modus ────────────────────────────────────────────────────────
    @Published var editMode: Bool = false

    // ── UI-Panels ─────────────────────────────────────────────────────────
    @Published var showHelp:     Bool = false
    @Published var showSettings: Bool = false

    // ── MIDI ──────────────────────────────────────────────────────────────
    @Published var midiChannel: Int = 0 {
        didSet { MIDIManager.shared.chordChannel = midiChannel }
    }
    @Published var chordToneChannel: Int = 3 {
        didSet { MIDIManager.shared.chordToneChannel = chordToneChannel }
    }
    @Published var chordVelocity: Double = 88

    // ── Navigation-Settings ───────────────────────────────────────────────
    @Published var playerSpeed:   Double  = 280
    @Published var triggerRadius: Double  = 55

    // ── Darstellung ───────────────────────────────────────────────────────
    @Published var nodeScale: CGFloat = 1.0   // 0.5 … 2.0

    // ── Magnet ────────────────────────────────────────────────────────────
    @Published var magnetEnabled:      Bool    = true
    @Published var magnetStrength:     Double  = 0.28
    @Published var magnetRadius:       Double  = 120
    @Published var edgeMagnetEnabled:  Bool    = false
    @Published var edgeMagnetStrength: Double  = 0.18

    // ── Zoom ──────────────────────────────────────────────────────────────
    @Published var zoomScale: CGFloat = 1.0

    // ── Akkord-Filter ─────────────────────────────────────────────────────
    @Published var keyCenter:    Int  = -1   // -1 = alle, 0=C … 11=B
    @Published var showMaj:      Bool = true
    @Published var showMin:      Bool = true
    @Published var showMaj7:     Bool = true
    @Published var showMin7:     Bool = true
    @Published var showDom7:     Bool = true
    @Published var showHalfDim:  Bool = true
    @Published var showDim7:     Bool = true
    @Published var showSus:      Bool = true

    // ── Gamepad Button-Mappings ───────────────────────────────────────────
    @Published var mappingA:  ButtonMapping = ButtonMapping()   // ✕ Cross
    @Published var mappingB:  ButtonMapping = ButtonMapping()   // ○ Circle
    @Published var mappingX:  ButtonMapping = ButtonMapping()   // □ Square
    @Published var mappingL1: ButtonMapping = ButtonMapping()
    @Published var mappingR1: ButtonMapping = ButtonMapping()

    // ── Layout-Name ───────────────────────────────────────────────────────
    @Published var layoutName: String = ""

    // ── Autopilot ─────────────────────────────────────────────────────────
    @Published var autopilotActive:        Bool   = false
    @Published var autopilotBPM:           Double = 90 {
        didSet { if midiClockEnabled { MIDIManager.shared.startClock(bpm: autopilotBPM) } }
    }
    @Published var autopilotBeatsPerChord: Int    = 4
    /// 0 = folgt Kantenwichten, 1 = völlig zufällig
    @Published var autopilotRandomness:    Double = 0.25

    // ── MIDI Clock ────────────────────────────────────────────────────────
    @Published var midiClockEnabled: Bool = false {
        didSet {
            if midiClockEnabled { MIDIManager.shared.startClock(bpm: autopilotBPM) }
            else                { MIDIManager.shared.stopClock() }
        }
    }

    private var autopilotCurrentNodeId: String?  = nil
    private var autopilotChordElapsed:  Double   = 0

    /// Chord-Name des aktuellen Zielknotens
    var autopilotCurrentChord: String? { autopilotCurrentNodeId }

    private(set) var canvasSize: CGSize = CGSize(width: 1100, height: 760)
    private var gameLoopTimer: Timer? = nil
    private var gamepadSetUp:  Bool   = false

    // ── Gefilterte Knoten und Kanten ──────────────────────────────────────

    var filteredNodes: [LayoutNode] {
        nodes.filter { isNodeVisible($0) }
    }

    var filteredEdges: [EdgeData] {
        let visibleIds = Set(filteredNodes.map { $0.id })
        return edges.filter { visibleIds.contains($0.source) && visibleIds.contains($0.target) }
    }

    var visibleEdges: [EdgeData] {
        guard let sel = selectedId else { return filteredEdges }
        return filteredEdges.filter { $0.source == sel || $0.target == sel }
    }

    private func isNodeVisible(_ node: LayoutNode) -> Bool {
        let name = node.name
        // Key-Center-Filter
        if keyCenter >= 0 {
            let root      = rootNote(of: name)
            let diatonic  = Set(majorScaleIntervals.map { (keyCenter + $0) % 12 })
            if !diatonic.contains(root) { return false }
        }
        // Akkordtyp-Filter
        if name.contains("maj9") || name.contains("maj7") { return showMaj7 }
        if name.contains("m7b5")                          { return showHalfDim }
        if name.contains("dim7") || name.contains("dim")  { return showDim7 }
        if name.contains("m9")   || name.contains("m7")   { return showMin7 }
        if name.contains("sus")                            { return showSus }
        if name.hasSuffix("7")   || name.hasSuffix("9")   { return showDom7 }
        // Dreiklänge
        let isMinor = name.range(of: "^[A-G][#b]?m", options: .regularExpression) != nil
        return isMinor ? showMin : showMaj
    }

    // MARK: – Laden + Layout

    /// Lädt ein Legacy-`.txt`-Netzwerk in den Canvas. Läuft nur außerhalb des
    /// HarmonyWeb-/Dokumentmodus (Runde 037 / V-00a, Fable-5-Review Finding
    /// A9): ohne diesen Guard konnte ein aktives Dokument versehentlich durch
    /// Legacy-Netzwerkdaten überschrieben werden (Gamepad-D-Pad-Netzwerk-
    /// wechsel, `resetLayout()`), was `document` (weiterhin gesetzt) und den
    /// sichtbaren Canvas-Inhalt (jetzt Legacy-Nodes) auseinanderlaufen ließ.
    /// `exitHarmonyWebMode(in:)` setzt `document = nil`, bevor es `load(...)`
    /// aufruft — der Guard greift dort also nicht.
    func load(networkIndex idx: Int, in size: CGSize) {
        guard !harmonyWebMode else { return }
        NetworkParser.refreshUserNetworks()   // User-Ordner bei jedem Laden neu scannen

        networkIndex  = idx
        canvasSize    = size
        isLayoutReady = false
        activeChordId = nil
        MIDIManager.shared.stopCurrentChord()

        let net = NetworkParser.load(index: idx)
        let currentFilename = NetworkParser.definitions[
            max(0, min(idx, NetworkParser.definitions.count - 1))].filename

        let cx = size.width  / 2
        let cy = size.height / 2
        let r  = min(cx, cy) * 0.75
        let n  = net.chords.count
        nodes = net.chords.enumerated().map { (i, chord) in
            let angle: Double = (2 * Double.pi * Double(i)) / Double(Swift.max(1, n)) - .pi / 2
            let px: CGFloat   = cx + r * CGFloat(cos(angle))
            let py: CGFloat   = cy + r * CGFloat(sin(angle))
            return LayoutNode(id: chord.name, name: chord.name,
                              midiNotes: chord.midiNotes,
                              position: CGPoint(x: px, y: py))
        }

        if let saved = loadSavedLayout(forFilename: currentFilename) {
            nodes = nodes.map { node in
                var n = node
                if let pos = saved.positions[node.id] {
                    n.position = CGPoint(x: pos[0], y: pos[1])
                }
                return n
            }
            edges      = saved.edges.map { EdgeData(source: $0.source, target: $0.target, weight: Float($0.weight)) }
            layoutName = saved.name
            isLayoutReady = true
            if !editMode { startGameLoop() }
            if !gamepadSetUp { setupGamepadCallbacks(); gamepadSetUp = true }
        } else {
            edges      = net.edges
            layoutName = ""
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                let legacyEdges = await self.edges.map { LayoutEdge(source: $0.source, target: $0.target, weight: $0.weight) }
                let settled = forceLayout(nodes: await self.nodes,
                                          edges: legacyEdges,
                                          size:  size)
                await MainActor.run {
                    self.nodes         = settled
                    self.isLayoutReady = true
                    if !self.editMode { self.startGameLoop() }
                    if !self.gamepadSetUp { self.setupGamepadCallbacks(); self.gamepadSetUp = true }
                }
            }
        }
    }

    // MARK: – HarmonyWeb-Dokument laden

    /// Lädt eine HarmonyMap per Name als read-only Bundle-Template
    /// (`HarmonyMapDocumentStore.openBundledTemplate`) und wechselt in den
    /// Web-/Dokumentansichtsmodus. Bestehende .txt-Netzwerk-Ansicht wird
    /// deaktiviert. Bei Fehler: `document` bleibt unverändert, Web-Modus
    /// bleibt inaktiv falls noch keins geladen war.
    func loadHarmonyWeb(named name: String, in size: CGSize) {
        guard !name.isEmpty else { return }
        documentErrorMessage = nil
        do {
            let doc = try HarmonyMapDocumentStore.openBundledTemplate(named: name)
            selectedWebName = name
            applyDocument(doc, in: size)
        } catch {
            print("⚠️  DesignerKit: HarmonyWeb-Template '\(name)' konnte nicht geladen werden — \(error)")
            selectedWebName = ""
        }
    }

    /// Erzeugt ein neues, leeres, ungespeichertes Dokument (K-02 trifft
    /// bewusst keine musikalische Starter-Map-Entscheidung — siehe
    /// `HarmonyMapDocumentStore.newDocument()`) und wechselt in den
    /// Web-/Dokumentansichtsmodus.
    func newHarmonyWebDocument(in size: CGSize) {
        documentErrorMessage = nil
        selectedWebName = ""
        applyDocument(HarmonyMapDocumentStore.newDocument(), in: size)
    }

    /// Öffnet eine beliebige externe JSON-Datei als Dokument und wechselt
    /// in den Web-/Dokumentansichtsmodus. Bei Fehler bleibt der bisherige
    /// Zustand unverändert, `documentErrorMessage` wird gesetzt.
    func openHarmonyWebDocument(at url: URL, in size: CGSize) {
        documentErrorMessage = nil
        do {
            let doc = try HarmonyMapDocumentStore.openDocument(at: url)
            selectedWebName = ""
            applyDocument(doc, in: size)
            recentDocuments.record(url)
        } catch {
            documentErrorMessage = "Öffnen fehlgeschlagen: \(error)"
        }
    }

    /// Übernimmt ein geladenes/neues Dokument als aktuellen Zustand, lädt den
    /// passenden Workspace-Sidecar und baut die Canvas-Darstellung daraus
    /// auf. Nodes kommen aus `document.draft.nodes` + Workspace-Positionen —
    /// besteht bereits mindestens eine gespeicherte Position, wird die
    /// vorhandene Anordnung respektiert (kein automatisches Re-Layout, siehe
    /// K-03 Scope C). Nur für ein wirklich frisches Dokument ohne Sidecar
    /// läuft einmalig die bisherige Force-Layout-Strategie (asynchron), das
    /// Ergebnis wird direkt als Startzustand persistiert.
    private func applyDocument(_ doc: HarmonyMapDocument, in size: CGSize) {
        stopGameLoop()
        MIDIManager.shared.stopAll()
        activeChordId    = nil
        isLayoutReady    = false
        autopilotActive  = false

        // Stale Zustand aus einem vorherigen Dokument darf nicht in das neu
        // geladene Dokument hineinwirken (Runde 037 / V-00a, Fable-5-Review
        // Finding A4): ein Builder-Vorschlag oder eine laufende Simulation,
        // die gegen den ALTEN Draft berechnet wurden, dürfen weder auf den
        // neuen Draft angewendet noch als scheinbar noch gültig angezeigt
        // werden. Selektionen/Panels, die sich auf Objekte des alten
        // Dokuments beziehen, werden ebenfalls zurückgesetzt statt sich
        // zufällig auf gleichnamige IDs im neuen Dokument zu beziehen.
        builderDiff          = nil
        builderBlockedReason = nil
        showBuilderPanel     = false
        simulation           = nil
        showSimulationPanel  = false
        selectedId              = nil
        selectedEdge            = nil
        selectedDocumentEdgeID  = nil
        selectedLayerID         = nil
        showLayerManager        = false
        showIssueNavigator      = false
        documentErrorMessage    = nil

        let map = doc.draft
        canvasSize = size
        let key = WorkspaceKey(origin: doc.origin, mapID: map.id)
        let loadedWorkspace = HarmonyMapWorkspaceStore.load(for: key)

        let cx = size.width  / 2
        let cy = size.height / 2
        let r  = min(cx, cy) * 0.75
        let n  = map.nodes.count

        var hasAnyWorkspacePosition = false
        nodes = map.nodes.enumerated().map { (i, harmNode) in
            if let wp = loadedWorkspace.position(forNodeID: harmNode.id) {
                hasAnyWorkspacePosition = true
                return LayoutNode(id: harmNode.id, name: harmNode.id,
                                  midiNotes: harmNode.midiNotes,
                                  position: CGPoint(x: wp.x, y: wp.y),
                                  pinned: loadedWorkspace.isPinned(harmNode.id))
            }
            let angle: Double = (2 * Double.pi * Double(i)) / Double(Swift.max(1, n)) - .pi / 2
            let px: CGFloat   = cx + r * CGFloat(cos(angle))
            let py: CGFloat   = cy + r * CGFloat(sin(angle))
            return LayoutNode(id: harmNode.id, name: harmNode.id,
                              midiNotes: harmNode.midiNotes,
                              position: CGPoint(x: px, y: py),
                              pinned: loadedWorkspace.isPinned(harmNode.id))
        }

        // Kein EdgeData-Schattenmodell mehr für Dokumentkanten (K-03) — die
        // Canvas liest Web-Kanten direkt aus `document.draft.edges` über
        // `webEdgesForDisplay`. `edges` bleibt für den Legacy-.txt-Modus
        // reserviert.
        edges = []

        document    = doc
        workspace   = loadedWorkspace
        activeLayer = loadedWorkspace.activeLayer ?? map.layers.first?.id ?? "functional"
        zoomScale   = CGFloat(loadedWorkspace.zoom)
        editMode    = false   // Web-/Dokumentansicht startet nicht im Drag-Modus

        if hasAnyWorkspacePosition {
            isLayoutReady = true
        } else {
            let layoutEdges = map.edges.map { LayoutEdge(source: $0.source, target: $0.target, weight: $0.weight) }
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                let settled = forceLayout(nodes: await self.nodes, edges: layoutEdges, size: size)
                await MainActor.run {
                    self.nodes         = settled
                    self.isLayoutReady = true
                    // Kein startGameLoop() — Web-/Dokumentmodus ist reine Ansicht, kein Spieler-Cursor
                    self.persistAllNodePositions()
                }
            }
        }
    }

    // MARK: – Workspace: Persistenz, Pin, Zoom, Layer, Auto-Layout, Resize (K-03)

    func saveWorkspace() {
        guard let key = workspaceKey else { return }
        do {
            try HarmonyMapWorkspaceStore.save(workspace, for: key)
        } catch {
            print("⚠️  DesignerKit: Workspace-Sidecar konnte nicht gespeichert werden — \(error)")
        }
    }

    private func persistAllNodePositions() {
        for node in nodes {
            workspace.setPosition(WorkspacePoint(x: Double(node.position.x), y: Double(node.position.y)), forNodeID: node.id)
        }
        saveWorkspace()
    }

    func isPinned(_ id: String) -> Bool { workspace.isPinned(id) }

    /// Pin/Unpin für den übergebenen Node — reine Workspace-Mutation, keine
    /// Map-Draft-Änderung. Persistiert sofort (kleine, seltene Aktion).
    func togglePin(_ id: String) {
        guard harmonyWebMode else { return }
        workspace.togglePin(id)
        if let i = nodes.firstIndex(where: { $0.id == id }) {
            nodes[i].pinned = workspace.isPinned(id)
        }
        saveWorkspace()
    }

    /// Persistiert den aktuellen `zoomScale` in den Workspace. Aufrufer
    /// entscheiden den Zeitpunkt (z. B. Zoom-Buttons sofort, Pinch-Geste erst
    /// bei `onEnded`, um nicht jeden Frame zu schreiben).
    func persistZoomIfDocumentMode() {
        guard harmonyWebMode else { return }
        workspace.zoom = Double(zoomScale)
        saveWorkspace()
    }

    func persistActiveLayerIfDocumentMode() {
        guard harmonyWebMode else { return }
        workspace.activeLayer = activeLayer
        saveWorkspace()
    }

    /// Re-simuliert die Force-Layout-Anordnung für das aktuelle Dokument.
    /// Gepinnte Nodes bleiben unverändert (siehe `forceLayout`). Ergebnis
    /// wird vollständig in den Workspace persistiert.
    func autoLayoutDocument() {
        guard harmonyWebMode, let map = harmonyMap else { return }
        let layoutEdges = map.edges.map { LayoutEdge(source: $0.source, target: $0.target, weight: $0.weight) }
        let size = canvasSize
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let currentNodes = await self.nodes
            let settled = forceLayout(nodes: currentNodes, edges: layoutEdges, size: size)
            await MainActor.run {
                self.nodes = settled
                self.persistAllNodePositions()
            }
        }
    }

    /// Reagiert auf Geometrieänderungen (Fenster-Resize) im Dokumentmodus,
    /// ohne das Dokument neu zu laden oder zu ersetzen (K-02-Rest, siehe
    /// Codex-Ruecklaufnotiz Runde 029→030: der alte Resize-Pfad rief
    /// `loadHarmonyWeb(named:)` auf, ein No-op für externe/neue Dokumente mit
    /// leerem `selectedWebName`). Positionen bleiben erhalten und werden nur
    /// auf die neuen Canvas-Grenzen geklammert — kein automatisches
    /// Re-Layout bei jedem Resize (das bleibt der expliziten
    /// `autoLayoutDocument()`-Aktion vorbehalten).
    func relayoutDocumentCanvas(in size: CGSize) {
        guard harmonyWebMode else { return }
        canvasSize = size
        let pad: CGFloat = 20
        for i in nodes.indices {
            nodes[i].position.x = max(pad, min(size.width  - pad, nodes[i].position.x))
            nodes[i].position.y = max(pad, min(size.height - pad, nodes[i].position.y))
        }
    }

    // MARK: – Node-Authoring (K-04)
    //
    // Jede fachliche Node-Mutation läuft ausschließlich über einen
    // `HarmonyMapCommand` via `document.perform(_:)` — `document.draft` bleibt
    // die einzige musikalische Datenquelle. `performDocumentCommand(_:onSuccess:)`
    // ist der gemeinsame Erfolgs-/Fehlerpfad: übernimmt den Draft nur bei
    // Erfolg, ruft danach `onSuccess` (für Fälle, die die alte/neue ID noch
    // brauchen, z. B. Rename-Workspace-Migration) und erst danach
    // `syncNodesFromDraft()`, damit Migrationslogik vor dem generischen
    // Resync laufen kann.

    private func performDocumentCommand(_ command: HarmonyMapCommand, onSuccess: (() -> Void)? = nil) {
        guard var doc = document else { return }
        do {
            try doc.perform(command)
            document = doc
            invalidateStaleDraftDependentState()
            onSuccess?()
            syncNodesFromDraft()
            saveWorkspace()
            documentErrorMessage = nil
        } catch {
            documentErrorMessage = "Aktion fehlgeschlagen: \(error)"
        }
    }

    /// Setzt Zustand zurück, der gegen einen jetzt veralteten Draft berechnet
    /// wurde (Runde 037 / V-00a, Fable-5-Review Findings A4/A11): eine
    /// laufende `HarmonyGraphSimulation` hält eine eigene Map-Kopie und wird
    /// von keiner Draft-Mutation automatisch aktualisiert — nach jedem
    /// erfolgreichen Command, Undo oder Redo wird sie konservativ verworfen,
    /// statt mit stale Kandidaten/History weiterzulaufen. Ein noch offener
    /// Builder-Vorschlag bezieht sich ebenfalls auf den Draft-Stand VOR der
    /// Mutation (z. B. bereits vergebene IDs) — bleibt er stehen, könnte ein
    /// späteres Apply gegen einen inzwischen widersprüchlichen Draft laufen.
    /// Für V-00a reicht die konservative Lösung: beides auf `nil` setzen,
    /// statt automatisch neu aufzubauen.
    private func invalidateStaleDraftDependentState() {
        simulation = nil
        builderDiff = nil
        builderBlockedReason = nil
    }

    /// Baut `nodes: [LayoutNode]` aus `document.draft.nodes` neu auf.
    /// Bestehende Canvas-Position/Pin bleiben für weiterhin existierende
    /// Nodes erhalten (Lookup über die aktuelle `id`, s. Rename-Migration
    /// oben, die die `id` in `nodes` VOR diesem Aufruf bereits umbenennt).
    /// Nodes ohne bekannte Position (neu via Add/Duplicate, oder aus dem
    /// Workspace-Sidecar) bekommen eine deterministische Fallback-Position
    /// nahe dem Canvas-Mittelpunkt (Offset nach Node-Index, damit mehrere
    /// gleichzeitig neue Nodes nicht exakt übereinanderliegen). Entfernt
    /// abschließend verwaiste Workspace-Positionen/-Pins (z. B. nach Delete)
    /// und hebt die Auswahl auf, falls der selektierte Node nicht mehr
    /// existiert.
    private func syncNodesFromDraft() {
        guard let map = harmonyMap else { return }
        let existingByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let cx = canvasSize.width / 2, cy = canvasSize.height / 2

        nodes = map.nodes.enumerated().map { (idx, harmNode) in
            if let existing = existingByID[harmNode.id] {
                return LayoutNode(id: harmNode.id, name: harmNode.id, midiNotes: harmNode.midiNotes,
                                  position: existing.position, velocity: existing.velocity, pinned: existing.pinned)
            }
            if let wp = workspace.position(forNodeID: harmNode.id) {
                return LayoutNode(id: harmNode.id, name: harmNode.id, midiNotes: harmNode.midiNotes,
                                  position: CGPoint(x: wp.x, y: wp.y), pinned: workspace.isPinned(harmNode.id))
            }
            let offset = CGFloat(idx) * 18
            return LayoutNode(id: harmNode.id, name: harmNode.id, midiNotes: harmNode.midiNotes,
                              position: CGPoint(x: cx + offset, y: cy + offset))
        }

        for node in nodes {
            workspace.setPosition(WorkspacePoint(x: Double(node.position.x), y: Double(node.position.y)), forNodeID: node.id)
        }
        let currentIDs = Set(map.nodes.map { $0.id })
        workspace.positions = workspace.positions.filter { currentIDs.contains($0.key) }
        workspace.pinnedNodeIDs = workspace.pinnedNodeIDs.filter { currentIDs.contains($0) }
        if let sel = selectedId, !currentIDs.contains(sel) { selectedId = nil }

        // Edge-/Layer-Auswahl ebenfalls bereinigen — z. B. wenn ein Delete-Node
        // eine inzidente Edge mitentfernt hat, oder ein Delete-Layer die
        // aktuell im Inspector offene Layer-ID entfernt hat (K-05).
        let currentEdgeIDs = Set(map.edges.map { $0.id })
        if let selEdge = selectedDocumentEdgeID, !currentEdgeIDs.contains(selEdge) { selectedDocumentEdgeID = nil }
        let currentLayerIDs = Set(map.layers.map { $0.id })
        if let selLayer = selectedLayerID, !currentLayerIDs.contains(selLayer) { selectedLayerID = nil }
        if !currentLayerIDs.contains(activeLayer), let firstLayer = map.layers.first?.id {
            activeLayer = firstLayer
            workspace.activeLayer = firstLayer
        }
    }

    /// Migriert Workspace-Position/Pin/Selection von `oldID` auf `newID` —
    /// wird als `onSuccess`-Closure einer erfolgreichen `RenameNodeCommand`
    /// VOR `syncNodesFromDraft()` ausgeführt, damit der generische Resync
    /// die migrierte Position unter der neuen ID vorfindet statt eine
    /// Fallback-Position zu vergeben.
    private func migrateWorkspace(from oldID: String, to newID: String) {
        guard oldID != newID else { return }
        if let pos = workspace.position(forNodeID: oldID) {
            workspace.setPosition(pos, forNodeID: newID)
        }
        workspace.positions.removeValue(forKey: oldID)
        if workspace.isPinned(oldID) {
            workspace.pinnedNodeIDs.remove(oldID)
            workspace.pinnedNodeIDs.insert(newID)
        }
        if let i = nodes.firstIndex(where: { $0.id == oldID }) {
            nodes[i] = LayoutNode(id: newID, name: newID, midiNotes: nodes[i].midiNotes,
                                  position: nodes[i].position, velocity: nodes[i].velocity, pinned: nodes[i].pinned)
        }
        if selectedId == oldID { selectedId = newID }
    }

    /// Fügt einen neuen Node mit einem rein technischen Platzhalter-Default
    /// hinzu (Root C, Dur-Dreiklang, eine einzelne MIDI-Note 60) — bewusst
    /// KEINE musikalische Builder-Entscheidung, nur ein sofort editierbares,
    /// valides Objekt (Handoff-Vorgabe K-04 Scope A). ID wird deterministisch
    /// über `AuthoringIDGenerator` vergeben und selektiert, damit der Inspector
    /// den neuen Node sofort bearbeiten kann.
    func addNode() {
        guard harmonyWebMode, let map = harmonyMap else { return }
        let id = AuthoringIDGenerator.freeID(base: "new-node", existingIDs: Set(map.nodes.map { $0.id }))
        let node = HarmonyNode(id: id, root: 0, type: .maj, function: .tonic, midiNotes: [60])
        performDocumentCommand(AddNodeCommand(node: node)) {
            self.selectedId = id
        }
    }

    /// Dupliziert den selektierten Node (deterministische `-copy`/`-copy-2`-ID,
    /// siehe `AuthoringIDGenerator`/`DuplicateNodeCommand` — beide nutzen exakt
    /// denselben Algorithmus, daher ist die hier vorab berechnete ID
    /// garantiert identisch zu der, die der Command intern erzeugt). Platziert
    /// die Kopie leicht versetzt neben dem Original statt am Canvas-Mittelpunkt.
    func duplicateSelectedNode() {
        guard let sourceID = selectedId, let map = harmonyMap else { return }
        let newID = AuthoringIDGenerator.freeID(base: "\(sourceID)-copy", existingIDs: Set(map.nodes.map { $0.id }))
        performDocumentCommand(DuplicateNodeCommand(sourceNodeID: sourceID)) {
            if let sourceNode = self.nodes.first(where: { $0.id == sourceID }) {
                let offsetPos = CGPoint(x: sourceNode.position.x + 40, y: sourceNode.position.y + 40)
                self.workspace.setPosition(WorkspacePoint(x: Double(offsetPos.x), y: Double(offsetPos.y)), forNodeID: newID)
            }
            self.selectedId = newID
        }
    }

    /// Benennt den selektierten Node um. Workspace-Position/Pin/Selection
    /// wandern von der alten auf die neue ID (`migrateWorkspace`).
    func renameSelectedNode(to newID: String) {
        guard let oldID = selectedId else { return }
        performDocumentCommand(RenameNodeCommand(nodeID: oldID, newID: newID)) {
            self.migrateWorkspace(from: oldID, to: newID)
        }
    }

    /// Löscht den selektierten Node (+ inzidente Edges, im Command). Workspace-
    /// Position/Pin/Selection für die gelöschte ID werden von der generischen
    /// `syncNodesFromDraft()`-Aufräumlogik entfernt — keine Sonderbehandlung
    /// nötig.
    func deleteSelectedNode() {
        guard let id = selectedId else { return }
        performDocumentCommand(DeleteNodeCommand(nodeID: id))
    }

    /// Bearbeitet Root/Type/Function/MIDI/Tags/Layers/layout3D des
    /// selektierten Nodes über `UpdateNodeCommand` — nie direkte
    /// `document.draft`-Mutation.
    func updateSelectedNode(
        root: Int, type: ChordType, function: HarmonicFunction, midiNotes: [Int],
        tags: [String], layers: [String]?, layout3D: Layout3D?
    ) {
        guard let id = selectedId else { return }
        performDocumentCommand(UpdateNodeCommand(
            nodeID: id, root: root, type: type, function: function, midiNotes: midiNotes,
            tags: tags, layers: layers, layout3D: layout3D
        ))
    }

    // MARK: – Edge-Authoring (K-05)
    //
    // Wie Node-Authoring: jede fachliche Mutation läuft über einen
    // `HarmonyMapCommand` via `performDocumentCommand`. Edge-Rendering bleibt
    // `webEdgesForDisplay`-basiert (`HarmonyEdge`, seit K-03) — keine neue
    // `EdgeData`-Schattenkopie im Dokumentmodus.

    func selectDocumentEdge(_ id: String?) {
        selectedDocumentEdgeID = (selectedDocumentEdgeID == id) ? nil : id
    }

    /// Verbindet zwei existierende Nodes mit einer neuen Edge. Default-Werte
    /// (`relationTypes: [.commonTone]`, `directed: true`, `weight: 1.0`,
    /// keine Layer-Zuordnung) sind — wie `addNode()`s Platzhalter-Default in
    /// K-04 — bewusst nur ein sofort editierbares, valides Objekt, keine
    /// musikalische Entscheidung. Aufgerufen vom wiederverwendeten Tap-zu-
    /// Verbinden-Gesture (siehe `DesignerCanvasView`), das im Dokumentmodus
    /// jetzt über den Command-Pfad statt direkter `EdgeData`-Mutation läuft.
    func addEdge(from source: String, to target: String) {
        guard harmonyWebMode, let map = harmonyMap else { return }
        let id = AuthoringIDGenerator.freeID(base: "\(source)-\(target)", existingIDs: Set(map.edges.map { $0.id }))
        let edge = HarmonyEdge(id: id, source: source, target: target, relationTypes: [.commonTone], directed: true, layers: [])
        performDocumentCommand(AddEdgeCommand(edge: edge)) {
            self.selectedDocumentEdgeID = id
        }
    }

    func deleteSelectedEdge() {
        guard let id = selectedDocumentEdgeID else { return }
        performDocumentCommand(DeleteEdgeCommand(edgeID: id)) {
            self.selectedDocumentEdgeID = nil
        }
    }

    /// Bearbeitet source/target/directed/relationTypes/layers/weight/
    /// magnetProfile/bridgesTo der selektierten Edge über `UpdateEdgeCommand`.
    func updateSelectedEdge(
        source: String, target: String, directed: Bool, relationTypes: [RelationType],
        layers: [String], weight: Float, magnetProfile: MagnetProfile?, bridgesTo: String?
    ) {
        guard let id = selectedDocumentEdgeID else { return }
        performDocumentCommand(UpdateEdgeCommand(
            edgeID: id, source: source, target: target, directed: directed, relationTypes: relationTypes,
            layers: layers, weight: weight, magnetProfile: magnetProfile, bridgesTo: bridgesTo
        ))
    }

    // MARK: – Layer-Authoring (K-05)
    //
    // Layer-Solo/Overlay bleibt reiner Workspace-/UI-Zustand: `activeLayer`
    // existiert bereits seit vor K-03 (steuert nur die Opacity in
    // `drawWebEdges`/Sichtbarkeit) und wird über `HarmonyMapWorkspaceState.
    // activeLayer` persistiert (`persistActiveLayerIfDocumentMode()`) — keine
    // Map-JSON-Erweiterung. Add/Rename/Delete Layer halten `activeLayer` und
    // `selectedLayerID` konsistent (Rename migriert, Delete fällt auf den
    // ersten verbleibenden Layer zurück, `syncNodesFromDraft()` deckt beides
    // zusätzlich generisch ab, s. o.).

    /// Placeholder-Default (analog `addNode()`): auto-generierte ID, Name
    /// gleich der ID, ein neutraler RelationType — sofort editierbar.
    func addLayer() {
        guard harmonyWebMode, let map = harmonyMap else { return }
        let id = AuthoringIDGenerator.freeID(base: "new-layer", existingIDs: Set(map.layers.map { $0.id }))
        addLayer(id: id, name: id, relationTypes: [.commonTone])
    }

    /// Fügt einen Layer mit explizit vorgegebenen Werten hinzu (z. B. aus dem
    /// Layer-Manager-Formular, das der Nutzer vor dem Anlegen bereits
    /// ausgefüllt hat).
    func addLayer(id: String, name: String, relationTypes: [RelationType]) {
        guard harmonyWebMode else { return }
        let layer = HarmonyLayer(id: id, name: name, relationTypes: relationTypes)
        performDocumentCommand(AddLayerCommand(layer: layer)) {
            self.selectedLayerID = id
        }
    }

    func updateLayer(layerID: String, newID: String, name: String, relationTypes: [RelationType]) {
        performDocumentCommand(UpdateLayerCommand(layerID: layerID, newID: newID, name: name, relationTypes: relationTypes)) {
            if self.activeLayer == layerID { self.activeLayer = newID }
            if self.selectedLayerID == layerID { self.selectedLayerID = newID }
            self.persistActiveLayerIfDocumentMode()
        }
    }

    func deleteLayer(_ layerID: String) {
        performDocumentCommand(DeleteLayerCommand(layerID: layerID)) {
            if self.selectedLayerID == layerID { self.selectedLayerID = nil }
            // activeLayer-Fallback läuft bereits generisch in syncNodesFromDraft().
        }
    }

    // MARK: – Dokument-Undo/Redo (K-04)

    var canUndoDocument: Bool { document?.canUndo ?? false }
    var canRedoDocument: Bool { document?.canRedo ?? false }

    func undoDocument() {
        guard var doc = document else { return }
        do {
            try doc.undo()
            document = doc
            invalidateStaleDraftDependentState()
            syncNodesFromDraft()
            saveWorkspace()
            documentErrorMessage = nil
        } catch {
            documentErrorMessage = "Rückgängig fehlgeschlagen: \(error)"
        }
    }

    func redoDocument() {
        guard var doc = document else { return }
        do {
            try doc.redo()
            document = doc
            invalidateStaleDraftDependentState()
            syncNodesFromDraft()
            saveWorkspace()
            documentErrorMessage = nil
        } catch {
            documentErrorMessage = "Wiederholen fehlgeschlagen: \(error)"
        }
    }

    // MARK: – Issue-Navigator (K-06)
    //
    // Zeigt `document.diagnostics.issues` an und erlaubt Fokus per Klick.
    // `IssueFocusTarget.parse(objectPath:)` (HarmonyAuthoring, UI-frei)
    // ordnet den Validator-Pfad einem Node/Edge/Layer/globalen Ziel zu.

    @Published var showIssueNavigator: Bool = false

    /// Fokussiert das zu `issue` gehörige Objekt (öffnet Node-/Edge-
    /// Inspector oder Layer-Manager). Zeigt bereits existierende
    /// Fremdauswahl nicht gleichzeitig an (Node-/Edge-/Layer-Selektion sind
    /// gegenseitig exklusiv). Zeigt ein Objekt, das inzwischen nicht mehr
    /// existiert (z. B. zwischenzeitlich gelöscht), bleibt der Navigator
    /// offen und nichts wird selektiert — kein Crash, kein falsches Ziel.
    /// `.global`-Issues (Schema-/Sammlungsfehler ohne Einzelobjekt) ändern
    /// die Selektion bewusst nicht.
    func focusIssue(_ issue: HarmonyMapValidator.Issue) {
        guard let map = harmonyMap else { return }
        switch IssueFocusTarget.parse(objectPath: issue.objectPath) {
        case .node(let id):
            guard map.nodes.contains(where: { $0.id == id }) else { return }
            selectedDocumentEdgeID = nil
            showLayerManager = false
            selectedId = id
            showIssueNavigator = false
        case .edge(let id):
            guard map.edges.contains(where: { $0.id == id }) else { return }
            selectedId = nil
            showLayerManager = false
            selectedDocumentEdgeID = id
            showIssueNavigator = false
        case .layer(let id):
            guard map.layers.contains(where: { $0.id == id }) else { return }
            selectedId = nil
            selectedDocumentEdgeID = nil
            selectedLayerID = id
            showLayerManager = true
            showIssueNavigator = false
        case .global:
            break
        }
    }

    // MARK: – Export-Gate (K-06)
    //
    // Trennt Draft-Save (immer erlaubt, auch mit Validator-Errors — siehe
    // `saveDocument()`/`saveDocumentAs(to:)`, unverändert seit K-02) vom
    // Runtime-Export: der exportiert/schreibt nur, wenn `document.
    // validatedSnapshot()` nicht `nil` ist (keine Errors — Warnings blockieren
    // nicht). Kein `HarmonyEngine3D`-Runtime-Pfad, keine automatische
    // App-Integration — reine Daten-/Datei-Grenze.

    var canExportToRuntime: Bool { document?.validatedSnapshot() != nil }

    var exportGateStatusText: String {
        guard let document else { return "" }
        if document.validatedSnapshot() != nil {
            let warnings = document.diagnostics.warnings.count
            return warnings == 0 ? "Export bereit" : "Export bereit (\(warnings) Warnungen)"
        }
        return "Export blockiert (\(document.diagnostics.errors.count) Fehler)"
    }

    /// Liefert den validierten Snapshot als reinen Daten-Pfad (kein
    /// Dateischreiben) — `nil`, wenn der Draft Validator-Errors enthält.
    func exportValidatedMap() -> HarmonyMap? {
        document?.validatedSnapshot()?.map
    }

    /// Schreibt den validierten Snapshot atomisch nach `url` — exakt dieselbe
    /// kanonische `HarmonyMapCodec.encode`-Repräsentation wie jeder andere
    /// Save-Pfad, kein eigenes Exportformat. Ändert bewusst NICHT
    /// `document.origin`/`.isDirty` — Export ist kein „Speichern unter" für
    /// das Dokument selbst, sondern eine separate validierte Kopie. Blockiert
    /// strukturiert (Fehlertext statt stillem No-op) bei Validator-Errors.
    func exportDocumentAs(to url: URL) {
        guard let validated = document?.validatedSnapshot() else {
            documentErrorMessage = "Export blockiert: \(document?.diagnostics.errors.count ?? 0) Validator-Fehler müssen zuerst behoben werden"
            return
        }
        do {
            try HarmonyMapCodec.encode(validated.map).write(to: url, options: .atomic)
            documentErrorMessage = nil
        } catch {
            documentErrorMessage = "Export fehlgeschlagen: \(error)"
        }
    }

    // MARK: – Runtime-nahe 2D-Simulation (K-07)
    //
    // `HarmonyGraphSimulation` (HarmonyAuthoring) nutzt intern dieselbe
    // `HarmonyGraphEngine` wie die 3D-Runtime — keine eigene Traversierungs-/
    // Gewichts-/Layerlogik hier. Läuft nur auf einem `validatedSnapshot()`-
    // fähigen Draft (Errors blockieren, Warnings erlauben — derselbe Vertrag
    // wie das K-06-Export-Gate, hier auf die Simulation angewendet statt auf
    // einen Datei-Export).

    @Published var showSimulationPanel: Bool = false
    @Published private(set) var simulation: HarmonyGraphSimulation? = nil
    @Published var simulationSeed: UInt64 = 1
    @Published var simulationRangeScale: Float = 1.0

    var canRunSimulation: Bool { document?.validatedSnapshot() != nil }

    var simulationStatusText: String {
        canRunSimulation ? exportGateStatusText : "Simulation blockiert (\(document?.diagnostics.errors.count ?? 0) Fehler — siehe Issues)"
    }

    /// Startet eine neue Simulation ab `nodeID` mit dem aktuell aktiven
    /// Layer und `simulationSeed`. No-op, wenn der Draft Validator-Errors
    /// enthält (`canRunSimulation == false`).
    func startSimulation(from nodeID: String) {
        guard canRunSimulation, let map = harmonyMap else { return }
        simulation = HarmonyGraphSimulation(
            map: map, startNodeID: nodeID, layer: activeLayer, seed: simulationSeed, rangeScale: simulationRangeScale
        )
    }

    func stepSimulation() {
        guard canRunSimulation else { return }
        simulation?.step()
    }

    func resetSimulation() {
        guard canRunSimulation else { return }
        simulation?.reset()
    }

    /// Layerwechsel läuft über `HarmonyGraphSimulation.setLayer(_:)` (also
    /// über `HarmonyGraphEngine`s eigene Layerfilterung) — aktualisiert
    /// zusätzlich den Toolbar-`activeLayer`, damit beide synchron bleiben.
    func setSimulationLayer(_ layerID: String) {
        guard canRunSimulation else { return }
        simulation?.setLayer(layerID)
        activeLayer = layerID
    }

    func stopSimulation() {
        simulation = nil
    }

    // MARK: – Diatonischer Builder (K-08)
    //
    // Erster regelbasierter Builder: `DiatonicHarmonyBuilder.proposeDiff(for:config:)`
    // (HarmonyAuthoring, UI-frei) berechnet einen Vorschlags-Diff — reine
    // Funktion, keine Draft-Mutation. Anwenden läuft als EIN
    // `ApplyHarmonyBuilderDiffCommand` über `performDocumentCommand`, also
    // automatisch als ein einzelner Undo-Schritt (siehe `HarmonyMapDocument.
    // perform(_:)`: ein Command = ein Undo-Stack-Eintrag). Cancel verwirft
    // nur den lokal gehaltenen Diff, rührt den Draft nie an.

    @Published var showBuilderPanel: Bool = false
    @Published var builderKeyRoot: Int = 0
    @Published private(set) var builderDiff: HarmonyBuilderDiff? = nil
    /// Gesetzt, wenn `previewBuilderDiff()` mangels Layer nicht ausgeführt
    /// werden konnte (Runde 037 / V-00a, Builder-A1). `nil` sobald ein
    /// Vorschlag erfolgreich erzeugt wurde oder das Dokument einen Layer hat.
    @Published private(set) var builderBlockedReason: String? = nil

    /// `false`, wenn der Draft keinen einzigen Layer besitzt — der Builder
    /// würde dann zwangsläufig layerlose, für `HarmonyGraphEngine`
    /// untraversierbare Kanten vorschlagen (Fable-5-Review Runde 036,
    /// Finding A1). Neue Dokumente bekommen seit diesem Slice einen
    /// Default-Layer (`HarmonyMapDocumentStore.newDocument()`), aber ein
    /// Dokument kann seinen letzten Layer auch nachträglich löschen — dieser
    /// Guard bleibt daher unabhängig vom Default-Layer bestehen.
    var canRunBuilder: Bool {
        guard let map = harmonyMap else { return false }
        return !map.layers.isEmpty
    }

    /// Baut einen frischen Vorschlags-Diff für den aktuellen Draft. Nutzt
    /// `activeLayer` als Ziel-Layer, wenn er im Dokument tatsächlich
    /// existiert, sonst den ersten vorhandenen Layer — nie einen nicht-
    /// existenten Layer referenzieren (siehe `HarmonyBuilderConfig`-Doku).
    /// Hat das Dokument gar keinen Layer, wird sichtbar blockiert
    /// (`builderBlockedReason`) statt einen toten, layerlosen Diff zu
    /// erzeugen (Runde 037 / V-00a, Builder-A1).
    func previewBuilderDiff() {
        guard let map = harmonyMap else { return }
        guard !map.layers.isEmpty else {
            builderDiff = nil
            builderBlockedReason = "Builder benötigt mindestens einen Layer im Dokument — lege zuerst einen Layer an."
            return
        }
        builderBlockedReason = nil
        let layerID = map.layers.contains(where: { $0.id == activeLayer }) ? activeLayer : map.layers[0].id
        builderDiff = DiatonicHarmonyBuilder.proposeDiff(
            for: map, config: HarmonyBuilderConfig(keyRoot: builderKeyRoot, layerID: layerID)
        )
    }

    /// Wendet den aktuell vorgeschauten Diff als einen einzigen Dokument-
    /// Command an. No-op, wenn kein Diff vorliegt oder der Diff leer ist
    /// (nichts Neues vorzuschlagen — z. B. alle Stufen existieren bereits).
    func applyBuilderDiff() {
        guard let diff = builderDiff, !diff.isEmpty else { return }
        performDocumentCommand(ApplyHarmonyBuilderDiffCommand(diff: diff)) {
            self.builderDiff = nil
            self.showBuilderPanel = false
        }
    }

    /// Verwirft den vorgeschauten Diff. Der Draft wird nie berührt, weil
    /// `previewBuilderDiff()` ausschließlich eine reine Funktion aufruft —
    /// Cancel hat daher garantiert keine Draft-/Dirty-State-Nebenwirkung.
    func cancelBuilderDiff() {
        builderDiff = nil
        builderBlockedReason = nil
    }

    /// Speichert das aktuelle Dokument an seiner bestehenden Datei-URL.
    /// Wirft strukturiert (ohne Zieldatei oder read-only Template) statt
    /// still zu schreiben — Fehler landet in `documentErrorMessage`.
    func saveDocument() {
        guard var doc = document else { return }
        do {
            try HarmonyMapDocumentStore.save(&doc)
            document = doc
            documentErrorMessage = nil
        } catch {
            documentErrorMessage = "Speichern fehlgeschlagen: \(error)"
        }
    }

    /// Speichert das aktuelle Dokument (neu, normale Datei oder Bundle-
    /// Template) atomisch an `url` und macht daraus ggf. eine normale Datei.
    func saveDocumentAs(to url: URL) {
        guard var doc = document else { return }
        do {
            try HarmonyMapDocumentStore.saveAs(&doc, to: url)
            document = doc
            recentDocuments.record(url)
            documentErrorMessage = nil
        } catch {
            documentErrorMessage = "Speichern fehlgeschlagen: \(error)"
        }
    }

    /// Wechselt zurück in den normalen .txt-Netzwerk-Modus.
    func exitHarmonyWebMode(in size: CGSize) {
        document        = nil
        workspace       = HarmonyMapWorkspaceState()
        selectedWebName = ""
        load(networkIndex: networkIndex, in: size)
    }

    func select(_ id: String?) {
        selectedId   = (selectedId == id) ? nil : id
        selectedEdge = nil   // Kanten-Auswahl aufheben wenn Knoten gewählt
    }

    func moveNode(id: String, by delta: CGPoint) {
        guard let i = nodes.firstIndex(where: { $0.id == id }) else { return }
        let pad: CGFloat = 20
        nodes[i].position.x = max(pad, min(canvasSize.width  - pad, nodes[i].position.x + delta.x))
        nodes[i].position.y = max(pad, min(canvasSize.height - pad, nodes[i].position.y + delta.y))
        if harmonyWebMode {
            // Drag im Dokumentmodus ist eine reine Workspace-Operation und
            // pinnt den Node implizit, damit Auto-Layout ihn respektiert
            // (K-03 Scope C: „pinnt oder markiert den Knoten so, dass
            // Auto-Layout ihn respektiert"). Persistenz erfolgt bewusst am
            // Drag-Ende (siehe `DesignerCanvasView.dragGesture`), nicht bei
            // jedem einzelnen Delta.
            nodes[i].pinned = true
            workspace.setPosition(WorkspacePoint(x: Double(nodes[i].position.x), y: Double(nodes[i].position.y)), forNodeID: id)
            workspace.pinnedNodeIDs.insert(id)
        }
    }

    func positionOf(_ name: String) -> CGPoint {
        nodes.first { $0.id == name }?.position ?? .zero
    }

    // MARK: – Kante erstellen / entfernen

    // MARK: – Kanten: erstellen / auswählen / Gewicht / entfernen

    func toggleEdge(from source: String, to target: String) {
        if let _ = edgeIndex(source: source, target: target) {
            // Kante existiert → auswählen und Gewicht editieren
            selectedEdge = (source, target)
            selectedId   = nil
            print("🔗 Kante ausgewählt: \(source) – \(target)")
        } else {
            // Neue Kante mit Standardgewicht 0.8
            edges.append(EdgeData(source: source, target: target, weight: 0.8))
            selectedEdge = (source, target)
            selectedId   = nil
            print("🔗 Kante hinzugefügt: \(source) – \(target)")
        }
    }

    /// Gewicht der aktuell ausgewählten Kante (0…1)
    var selectedEdgeWeight: Float {
        get {
            guard let sel = selectedEdge,
                  let i   = edgeIndex(source: sel.source, target: sel.target)
            else { return 0.8 }
            return edges[i].weight
        }
        set {
            guard let sel = selectedEdge,
                  let i   = edgeIndex(source: sel.source, target: sel.target)
            else { return }
            edges[i] = EdgeData(source: edges[i].source,
                                target: edges[i].target,
                                weight: max(0.05, min(1.0, newValue)))
        }
    }

    func removeSelectedEdge() {
        guard let sel = selectedEdge,
              let i   = edgeIndex(source: sel.source, target: sel.target)
        else { return }
        print("🔗 Kante entfernt: \(sel.source) – \(sel.target)")
        edges.remove(at: i)
        selectedEdge = nil
    }

    func clearEdgeSelection() { selectedEdge = nil }

    private func edgeIndex(source: String, target: String) -> Int? {
        edges.firstIndex {
            ($0.source == source && $0.target == target) ||
            ($0.target == source && $0.source == target)
        }
    }

    // MARK: – Layout speichern / zurücksetzen

    private var currentNetworkFilename: String {
        let defs = NetworkParser.definitions
        guard networkIndex >= 0, networkIndex < defs.count else { return "network_\(networkIndex)" }
        return defs[networkIndex].filename
    }

    /// Speichert das Legacy-`.txt`-Netzwerklayout. Läuft nur außerhalb des
    /// HarmonyWeb-/Dokumentmodus (Runde 037 / V-00a, Finding A9) — im
    /// Dokumentmodus ist die Workspace-Persistenz (`saveWorkspace()`)
    /// zuständig, ein Legacy-Layout-Schreibzugriff auf Dokument-Nodes/-IDs
    /// wäre eine Zustandsverwechslung (Architekturreview 2026-07-26, P1).
    func saveLayout() {
        guard !harmonyWebMode else { return }
        let layout = SavedLayout(
            name: layoutName,
            positions: Dictionary(uniqueKeysWithValues:
                nodes.map { ($0.id, [Double($0.position.x), Double($0.position.y)]) }),
            edges: edges.map {
                SavedLayout.SavedEdge(source: $0.source, target: $0.target, weight: Double($0.weight))
            }
        )
        guard let url = layoutFileURL(forFilename: currentNetworkFilename),
              let data = try? JSONEncoder().encode(layout) else { return }
        try? data.write(to: url)
        print("💾 Layout gespeichert: \(currentNetworkFilename).json")
    }

    /// Setzt das Legacy-`.txt`-Netzwerklayout zurück und lädt es neu. Läuft
    /// nur außerhalb des HarmonyWeb-/Dokumentmodus (Runde 037 / V-00a,
    /// Finding A9) — siehe `saveLayout()`/`load(networkIndex:in:)`.
    func resetLayout() {
        guard !harmonyWebMode else { return }
        if let url = layoutFileURL(forFilename: currentNetworkFilename) {
            try? FileManager.default.removeItem(at: url)
        }
        layoutName = ""
        load(networkIndex: networkIndex, in: canvasSize)
    }

    var hasSavedLayout: Bool {
        guard let url = layoutFileURL(forFilename: currentNetworkFilename) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: – Edit / Play Modus

    /// Im Legacy-.txt-Netzwerkmodus schaltet dies zwischen Spielmodus und
    /// Edge-/Layout-Edit um (unverändert seit vor K-03). Im HarmonyWeb-/
    /// Dokumentmodus (K-03) aktiviert derselbe Button stattdessen nur das
    /// Node-Dragging (Workspace-Operation, siehe `moveNode`/`dragGesture`) —
    /// kein Edge-Edit, kein Spielmodus-Wechsel, kein `saveLayout()` (das
    /// schreibt ein `.txt`-Netzwerk-Sidecar-Format, das im Dokumentmodus
    /// nicht anwendbar ist; Workspace-Persistenz läuft separat über
    /// `saveWorkspace()`/`persist*`-Methoden).
    func toggleEditMode() {
        if editMode {
            if harmonyWebMode {
                saveWorkspace()
            } else {
                saveLayout()
                if isLayoutReady { startGameLoop() }
            }
            editMode   = false
            selectedId = nil
        } else {
            editMode = true
            stopGameLoop()
            MIDIManager.shared.stopAll()
            activeChordId = nil
        }
    }

    // MARK: – Game Loop

    func startGameLoop() {
        gameLoopTimer?.invalidate()
        if playerPosition == .zero {
            playerPosition = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        }
        gameLoopTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.tick() }
        }
    }

    func stopGameLoop() { gameLoopTimer?.invalidate(); gameLoopTimer = nil }

    @MainActor private func tick() {
        let dt:  CGFloat = 1.0 / 60.0
        let pad: CGFloat = 30

        if autopilotActive {
            tickAutopilot(dt: Double(dt))
            // Magnet stört den Autopiloten – ausschalten
        } else {
            let gp    = DesignerGamepad.shared
            let speed = CGFloat(playerSpeed) * (1.0 + CGFloat(gp.boost) * 1.5)
            playerPosition.x = max(pad, min(canvasSize.width  - pad,
                playerPosition.x + CGFloat(gp.moveX) * speed * dt))
            playerPosition.y = max(pad, min(canvasSize.height - pad,
                playerPosition.y + CGFloat(-gp.moveY) * speed * dt))
            if magnetEnabled     { applyMagnetism(pad: pad) }
            if edgeMagnetEnabled { applyEdgeMagnetism(pad: pad) }
        }

        detectChordTrigger()
    }

    @MainActor private func tickAutopilot(dt: Double) {
        guard !filteredNodes.isEmpty else { autopilotActive = false; return }

        // Sicherstellen dass ein Zielknoten gesetzt ist
        if autopilotCurrentNodeId == nil || filteredNodes.first(where: { $0.id == autopilotCurrentNodeId }) == nil {
            autopilotCurrentNodeId = filteredNodes.randomElement()?.id
            if let id = autopilotCurrentNodeId,
               let pos = filteredNodes.first(where: { $0.id == id })?.position {
                playerPosition = pos  // direkt zum ersten Knoten springen
            }
        }
        guard let targetId = autopilotCurrentNodeId,
              let target   = filteredNodes.first(where: { $0.id == targetId }) else { return }

        // Beat-Timing: nach chordDuration zum nächsten Knoten springen (distanzunabhängig)
        let chordDuration = 60.0 / autopilotBPM * Double(autopilotBeatsPerChord)
        autopilotChordElapsed += dt
        if autopilotChordElapsed >= chordDuration {
            autopilotChordElapsed -= chordDuration
            let nextId = pickNextNode(from: targetId)
            autopilotCurrentNodeId = nextId
            // Cursor direkt auf den neuen Knoten teleportieren → Abstände spielen keine Rolle
            if let nextPos = filteredNodes.first(where: { $0.id == nextId })?.position {
                playerPosition = nextPos
            }
        } else {
            // Weiche Annäherung an den Zielknoten während der laufenden Akkord-Phase
            let pad: CGFloat = 30
            let dx   = target.position.x - playerPosition.x
            let dy   = target.position.y - playerPosition.y
            let dist = sqrt(dx * dx + dy * dy)
            if dist > 1 {
                let speed = CGFloat(max(Double(dist) / max(0.01, chordDuration * 0.25), 400.0))
                let step  = min(dist, speed * CGFloat(dt))
                playerPosition.x = max(pad, min(canvasSize.width  - pad, playerPosition.x + (dx / dist) * step))
                playerPosition.y = max(pad, min(canvasSize.height - pad, playerPosition.y + (dy / dist) * step))
            }
        }
    }

    /// Wählt den nächsten Knoten anhand von Kantenwichten + Zufälligkeit.
    /// Hohe Kantenwichte = harmonisch nah = bevorzugt.
    /// `autopilotRandomness` = 0 → folgt Wichten; = 1 → rein zufällig.
    private func pickNextNode(from currentId: String) -> String {
        let visible = Set(filteredNodes.map { $0.id })

        // Direkte Nachbarn aus dem Graphen
        let neighbors: [(id: String, weight: Double)] = filteredEdges
            .compactMap { edge in
                let neighborId: String
                if edge.source == currentId      { neighborId = edge.target }
                else if edge.target == currentId { neighborId = edge.source }
                else                              { return nil }
                guard visible.contains(neighborId) else { return nil }
                return (neighborId, Double(edge.weight))
            }

        // Keine Nachbarn → zufälliger Sprung
        if neighbors.isEmpty {
            return filteredNodes.filter { $0.id != currentId }.randomElement()?.id ?? currentId
        }

        // Gewichtete Auswahl: Kantenwicht + Zufälligkeit mischen
        let r = autopilotRandomness
        let weighted = neighbors.map { (id: $0.id, w: (1.0 - r) * $0.weight + r * 0.5) }
        let total    = weighted.reduce(0.0) { $0 + $1.w }
        var roll     = Double.random(in: 0..<total)
        for item in weighted {
            roll -= item.w
            if roll <= 0 { return item.id }
        }
        return weighted.last?.id ?? currentId
    }

    /// Startet/stoppt den Legacy-Autopiloten. Läuft nur außerhalb des
    /// HarmonyWeb-/Dokumentmodus (Runde 037 / V-00a, Finding A9): der
    /// Autopilot traversiert über `filteredEdges`/`pickNextNode` — im
    /// Dokumentmodus ist `edges` immer leer (siehe K-03), der Autopilot
    /// würde dort nur zufällig zwischen Nodes springen und zusätzlich mit
    /// der K-07-Simulation um dieselbe "Abspiel"-Rolle konkurrieren.
    func toggleAutopilot() {
        guard !harmonyWebMode else { return }
        if autopilotActive {
            autopilotActive = false
        } else {
            guard !filteredNodes.isEmpty else { return }
            // Start vom aktiven Akkord, sonst zufällig
            autopilotCurrentNodeId = activeChordId ?? filteredNodes.randomElement()?.id
            autopilotChordElapsed  = 0
            autopilotActive        = true
            if gameLoopTimer == nil, isLayoutReady { startGameLoop() }
        }
    }

    // MARK: – Magnetismus

    private func applyMagnetism(pad: CGFloat) {
        var bestPull = CGPoint.zero
        var bestDist = CGFloat.infinity
        for node in filteredNodes {
            let dx = node.position.x - playerPosition.x
            let dy = node.position.y - playerPosition.y
            let dist = sqrt(dx*dx + dy*dy)
            let r = CGFloat(magnetRadius)
            if dist < r && dist < bestDist {
                bestDist = dist
                let t = 1.0 - dist / r
                bestPull = CGPoint(x: dx * t * CGFloat(magnetStrength),
                                   y: dy * t * CGFloat(magnetStrength))
            }
        }
        let cap: CGFloat = 30
        playerPosition.x = max(cap, min(canvasSize.width  - cap, playerPosition.x + bestPull.x))
        playerPosition.y = max(cap, min(canvasSize.height - cap, playerPosition.y + bestPull.y))
    }

    private func applyEdgeMagnetism(pad: CGFloat) {
        var bestPull = CGPoint.zero
        var bestDist = CGFloat.infinity
        let r = CGFloat(magnetRadius), str = CGFloat(edgeMagnetStrength)
        for edge in filteredEdges {
            guard let a = nodes.first(where: { $0.id == edge.source })?.position,
                  let b = nodes.first(where: { $0.id == edge.target })?.position else { continue }
            let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let len2 = ab.x*ab.x + ab.y*ab.y
            guard len2 > 1 else { continue }
            let t = Swift.max(0, Swift.min(1,
                ((playerPosition.x-a.x)*ab.x + (playerPosition.y-a.y)*ab.y) / len2))
            let nearest = CGPoint(x: a.x + t*ab.x, y: a.y + t*ab.y)
            let dx = nearest.x - playerPosition.x, dy = nearest.y - playerPosition.y
            let dist = sqrt(dx*dx + dy*dy)
            if dist < r && dist < bestDist {
                bestDist = dist
                let f = (1.0 - dist/r) * str
                bestPull = CGPoint(x: dx*f, y: dy*f)
            }
        }
        let cap: CGFloat = 30
        playerPosition.x = max(cap, min(canvasSize.width  - cap, playerPosition.x + bestPull.x))
        playerPosition.y = max(cap, min(canvasSize.height - cap, playerPosition.y + bestPull.y))
    }

    // MARK: – Chord-Auslösung

    private func detectChordTrigger() {
        var bestId:   String?  = nil
        var bestDist: CGFloat  = .infinity
        let r = CGFloat(triggerRadius)
        for node in filteredNodes {
            let dx = node.position.x - playerPosition.x
            let dy = node.position.y - playerPosition.y
            let dist = sqrt(dx*dx + dy*dy)
            if dist < r && dist < bestDist { bestDist = dist; bestId = node.id }
        }
        guard bestId != activeChordId else { return }
        activeChordId = bestId
        if let id = bestId, let node = nodes.first(where: { $0.id == id }) {
            MIDIManager.shared.playChord(node.midiNotes,
                velocity: UInt8(max(1, min(127, Int(chordVelocity)))))
        } else {
            MIDIManager.shared.stopCurrentChord()
        }
    }

    // MARK: – Button-Mapping ausführen

    private func executeMapping(_ mapping: ButtonMapping, pressed: Bool) {
        switch mapping.kind {
        case .off: break
        case .note:
            let ch  = UInt8(mapping.channel & 0x0F)
            let st  = pressed ? UInt8(0x90 | ch) : UInt8(0x80 | ch)
            let n   = UInt8(max(0, min(127, mapping.number)))
            let vel = pressed ? UInt8(max(1, min(127, mapping.value))) : 0
            MIDIManager.shared.sendRaw(st, n, vel)
        case .cc:
            if pressed { MIDIManager.shared.sendCC(channel: mapping.channel,
                                                    cc: mapping.number, value: mapping.value) }
        case .networkPrev:
            if pressed {
                let i = max(0, networkIndex - 1)
                if i != networkIndex { load(networkIndex: i, in: canvasSize) }
            }
        case .networkNext:
            if pressed {
                let i = min(NetworkParser.definitions.count - 1, networkIndex + 1)
                if i != networkIndex { load(networkIndex: i, in: canvasSize) }
            }
        case .allNotesOff:
            if pressed { MIDIManager.shared.stopAll(); activeChordId = nil }
        case .toggleHelp:
            if pressed { showHelp.toggle() }
        case .editToggle:
            if pressed { toggleEditMode() }
        case .autopilot:
            if pressed { toggleAutopilot() }
        }
    }

    // MARK: – Gamepad-Callbacks

    private func setupGamepadCallbacks() {
        let gp = DesignerGamepad.shared

        gp.onChordTone = { [weak self] sector, velocity in
            Task { @MainActor [weak self] in
                guard let s = self,
                      let id   = s.activeChordId,
                      let node = s.nodes.first(where: { $0.id == id }),
                      sector < node.midiNotes.count else { return }
                MIDIManager.shared.playChordTone(node.midiNotes[sector], velocity: velocity)
            }
        }
        gp.onNetworkPrev = { [weak self] in
            Task { @MainActor [weak self] in
                guard let s = self else { return }
                let i = max(0, s.networkIndex - 1)
                if i != s.networkIndex { s.load(networkIndex: i, in: s.canvasSize) }
            }
        }
        gp.onNetworkNext = { [weak self] in
            Task { @MainActor [weak self] in
                guard let s = self else { return }
                let i = min(NetworkParser.definitions.count - 1, s.networkIndex + 1)
                if i != s.networkIndex { s.load(networkIndex: i, in: s.canvasSize) }
            }
        }
        gp.onAllNotesOff = { [weak self] in
            Task { @MainActor [weak self] in MIDIManager.shared.stopAll(); self?.activeChordId = nil }
        }
        gp.onToggleHelp = { [weak self] in
            Task { @MainActor [weak self] in self?.showHelp.toggle() }
        }

        // Frei belegbare Tasten
        gp.onButtonA = { [weak self] pressed in
            Task { @MainActor [weak self] in self?.executeMapping(self?.mappingA ?? ButtonMapping(), pressed: pressed) }
        }
        gp.onButtonB = { [weak self] pressed in
            Task { @MainActor [weak self] in self?.executeMapping(self?.mappingB ?? ButtonMapping(), pressed: pressed) }
        }
        gp.onButtonX = { [weak self] pressed in
            Task { @MainActor [weak self] in self?.executeMapping(self?.mappingX ?? ButtonMapping(), pressed: pressed) }
        }
        gp.onL1 = { [weak self] pressed in
            Task { @MainActor [weak self] in self?.executeMapping(self?.mappingL1 ?? ButtonMapping(), pressed: pressed) }
        }
        gp.onR1 = { [weak self] pressed in
            Task { @MainActor [weak self] in self?.executeMapping(self?.mappingR1 ?? ButtonMapping(), pressed: pressed) }
        }
    }
}

// MARK: – Force-Directed Layout

private func forceLayout(nodes inputNodes: [LayoutNode],
                          edges: [LayoutEdge],
                          size: CGSize) -> [LayoutNode] {
    guard inputNodes.count > 1 else { return inputNodes }
    var nodes = inputNodes
    let n     = nodes.count
    let repulsion:  CGFloat = 14_000
    let springK:    CGFloat = 0.05
    let restLength: CGFloat = 210
    let damping:    CGFloat = 0.82
    let iterations: Int     = 400
    let padding:    CGFloat = 90

    for _ in 0..<iterations {
        var forces = Array(repeating: CGPoint.zero, count: n)
        for i in 0..<n {
            for j in (i+1)..<n {
                let dx = nodes[i].position.x - nodes[j].position.x
                let dy = nodes[i].position.y - nodes[j].position.y
                let dist2: CGFloat = Swift.max(1, dx*dx + dy*dy)
                let dist:  CGFloat = sqrt(dist2)
                let f = repulsion / dist2
                let fx = f*dx/dist; let fy = f*dy/dist
                forces[i].x += fx;  forces[i].y += fy
                forces[j].x -= fx;  forces[j].y -= fy
            }
        }
        let indexMap = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.id, $0) })
        for edge in edges {
            guard let si = indexMap[edge.source], let ti = indexMap[edge.target] else { continue }
            let dx = nodes[ti].position.x - nodes[si].position.x
            let dy = nodes[ti].position.y - nodes[si].position.y
            let dist: CGFloat = Swift.max(1, sqrt(dx*dx + dy*dy))
            let f: CGFloat = springK * (dist - restLength) * CGFloat(edge.weight)
            let fx = f*dx/dist; let fy = f*dy/dist
            forces[si].x += fx;  forces[si].y += fy
            forces[ti].x -= fx;  forces[ti].y -= fy
        }
        for i in 0..<n {
            // Gepinnte Nodes (K-03, Workspace-Pin) nehmen an der Abstoßung/
            // Federkraft weiterhin teil (andere Nodes weichen ihnen aus),
            // werden selbst aber nicht bewegt.
            guard !nodes[i].pinned else { continue }
            nodes[i].velocity.x = (nodes[i].velocity.x + forces[i].x) * damping
            nodes[i].velocity.y = (nodes[i].velocity.y + forces[i].y) * damping
            nodes[i].position.x += nodes[i].velocity.x
            nodes[i].position.y += nodes[i].velocity.y
            nodes[i].position.x = Swift.max(padding, Swift.min(size.width  - padding, nodes[i].position.x))
            nodes[i].position.y = Swift.max(padding, Swift.min(size.height - padding, nodes[i].position.y))
        }
    }
    return nodes
}
