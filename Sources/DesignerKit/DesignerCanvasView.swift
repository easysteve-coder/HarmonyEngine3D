import SwiftUI
import AppKit
import UniformTypeIdentifiers
import HarmonyShared
import HarmonyAuthoring

// MARK: – Hauptview

struct DesignerCanvasView: View {

    @StateObject private var vm = DesignerViewModel()
    @State private var baseZoom: CGFloat = 1.0

    // ── Drag-State (Edit-Modus) ───────────────────────────────────────────
    @State private var lastDragTranslation: CGSize = .zero
    @State private var draggingId: String? = nil

    // ── Tastatur-Monitor ──────────────────────────────────────────────────
    @State private var keyMonitor: Any? = nil

    // ── Node-Rename (K-04) ───────────────────────────────────────────────
    @State private var isRenamingNode = false
    @State private var renameFieldText = ""

    // ── Node-Inspector (K-04) ────────────────────────────────────────────
    @State private var inspectorRoot: Int = 0
    @State private var inspectorType: ChordType = .maj
    @State private var inspectorFunction: HarmonicFunction = .tonic
    @State private var inspectorMidiNotesText: String = ""
    @State private var inspectorTagsText: String = ""
    @State private var inspectorLayers: Set<String> = []
    @State private var inspectorLayout3DEnabled: Bool = false
    @State private var inspectorLayoutX: String = "0"
    @State private var inspectorLayoutY: String = "0"
    @State private var inspectorLayoutZ: String = "0"
    @State private var inspectedNodeID: String? = nil

    // ── Edge-Inspector (K-05) ────────────────────────────────────────────
    @State private var edgeSource: String = ""
    @State private var edgeTarget: String = ""
    @State private var edgeDirected: Bool = true
    @State private var edgeRelationTypes: Set<RelationType> = []
    @State private var edgeLayers: Set<String> = []
    @State private var edgeWeightText: String = "1.0"
    @State private var edgeMagnetPreset: MagnetProfile.Preset? = nil
    @State private var edgeBridgesToText: String = ""
    @State private var inspectedEdgeID: String? = nil

    // ── Layer-Manager (K-05) ─────────────────────────────────────────────
    @State private var layerNewID: String = ""
    @State private var layerNewName: String = ""
    @State private var layerNewRelationTypes: Set<RelationType> = []

    // ── Simulation (K-07) ────────────────────────────────────────────────
    @State private var simulationStartNodeID: String = ""
    @State private var simulationSeedText: String = "1"

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if vm.harmonyWebMode && !vm.webValidationWarnings.isEmpty {
                webValidationBar
            }
            GeometryReader { geo in
                ZStack {
                    Color(red: 0.05, green: 0.06, blue: 0.12)

                    if vm.isLayoutReady {
                        // ── Karten-Inhalt (skalierbar) ──────────────────────
                        Group {
                            Canvas { ctx, _ in
                                if vm.harmonyWebMode {
                                    drawWebEdges(ctx: ctx)
                                } else {
                                    drawEdges(ctx: ctx)
                                    drawMagnetRings(ctx: ctx)
                                    drawTriggerRings(ctx: ctx)
                                }
                            }
                            ForEach(vm.filteredNodes) { node in
                                NodeView(node: node,
                                         isSelected:    vm.selectedId    == node.id,
                                         isHighlighted: isHighlighted(node.id),
                                         isActive:      vm.activeChordId == node.id,
                                         editMode:      vm.editMode,
                                         scale:         vm.nodeScale)
                                .position(node.position)
                                .onTapGesture {
                                    if vm.editMode, let sel = vm.selectedId, sel != node.id {
                                        if vm.harmonyWebMode {
                                            // K-05: Tap-zu-Verbinden läuft im Dokumentmodus über
                                            // AddEdgeCommand statt direkter EdgeData-Mutation.
                                            vm.addEdge(from: sel, to: node.id)
                                        } else {
                                            vm.toggleEdge(from: sel, to: node.id)
                                        }
                                        vm.selectedId = nil
                                    } else {
                                        vm.select(node.id)
                                    }
                                }
                                .gesture(vm.editMode ? dragGesture(for: node.id) : nil)
                                .cursor(vm.editMode ? .openHand : .arrow)
                            }
                        }
                        .scaleEffect(vm.zoomScale, anchor: .center)

                        // ── Gamepad-Cursor (außerhalb von scaleEffect!) ──────
                        // playerPosition ist in Canvas-Koordinaten → in Screen-Koordinaten umrechnen
                        let cx = geo.size.width  / 2
                        let cy = geo.size.height / 2
                        PlayerCursorView(isAutopilot: vm.autopilotActive)
                            .position(CGPoint(
                                x: cx + (vm.playerPosition.x - cx) * vm.zoomScale,
                                y: cy + (vm.playerPosition.y - cy) * vm.zoomScale
                            ))

                    } else {
                        ProgressView("Netzwerk wird geladen…")
                            .foregroundStyle(.white)
                    }
                }
                .onTapGesture {
                    // Klick auf Hintergrund → Auswahl aufheben
                    if vm.editMode {
                        vm.select(nil)
                        vm.clearEdgeSelection()
                    }
                }
                .onAppear {
                    vm.load(networkIndex: vm.networkIndex, in: geo.size)
                    setupKeyMonitor()
                }
                .onDisappear {
                    if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
                }
                .onChange(of: vm.networkIndex) { idx in vm.load(networkIndex: idx, in: geo.size) }
                .onChange(of: geo.size) { size in
                    let delta = abs(size.width - vm.canvasSize.width)
                              + abs(size.height - vm.canvasSize.height)
                    if delta > 4 {
                        if vm.harmonyWebMode {
                            // K-02-Rest (Codex-Ruecklaufnotiz Runde 029→030): kein
                            // loadHarmonyWeb(named:) mehr — das war für externe/neue
                            // Dokumente mit leerem selectedWebName ein No-op und hätte
                            // sie beim Resize durch ein Bundle-Template ersetzen können.
                            vm.relayoutDocumentCanvas(in: size)
                        } else {
                            vm.load(networkIndex: vm.networkIndex, in: size)
                        }
                    }
                }
                // ── Pinch to zoom ──────────────────────────────────────────
                .gesture(MagnificationGesture()
                    .onChanged { val in
                        vm.zoomScale = (baseZoom * val).clamped(to: 0.25...4.0)
                    }
                    .onEnded { _ in
                        baseZoom = vm.zoomScale
                        vm.persistZoomIfDocumentMode()
                    }
                )
            }

            activeChordBar
        }
        .background(Color(red: 0.05, green: 0.06, blue: 0.12))
        .preferredColorScheme(.dark)
        .overlay(alignment: .trailing) {
            // Priorität: Settings > Issue-Navigator > Simulation > Builder >
            // Layer-Manager > Edge-Inspector > Node-Inspector — jeweils nur
            // ein Panel gleichzeitig (UI klein halten, K-04/K-05/K-06/K-07/
            // K-08). `focusIssue(_:)` schließt den Navigator bei
            // erfolgreichem Fokus selbst, damit das Zielpanel im nächsten
            // Render sichtbar wird.
            if vm.showSettings {
                settingsPanel
            } else if vm.harmonyWebMode, vm.showIssueNavigator {
                issueNavigator
            } else if vm.harmonyWebMode, vm.showSimulationPanel {
                simulationPanel
            } else if vm.harmonyWebMode, vm.showBuilderPanel {
                builderPanel
            } else if vm.harmonyWebMode, vm.showLayerManager {
                layerManager
            } else if vm.harmonyWebMode, let edgeID = vm.selectedDocumentEdgeID {
                edgeInspector(for: edgeID)
            } else if vm.harmonyWebMode, let sel = vm.selectedId {
                nodeInspector(for: sel)
            }
        }
        .overlay(alignment: .center) {
            if vm.showHelp { helpOverlay }
        }
        .alert("Dokumentfehler", isPresented: Binding(
            get: { vm.documentErrorMessage != nil },
            set: { if !$0 { vm.documentErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { vm.documentErrorMessage = nil }
        } message: {
            Text(vm.documentErrorMessage ?? "")
        }
    }

    // MARK: – Tastatur-Monitor (⌘E, Tab, ⌘N/⌘O/⌘S/⇧⌘S für K-02-Dokument-I/O)

    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak vm] event in
            guard let vm else { return event }
            // ⌘E → Edit/Play umschalten
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers == "e" {
                Task { @MainActor in vm.toggleEditMode() }
                return nil
            }
            // Tab → Einstellungen
            if event.keyCode == 48,
               !event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.shift) {
                Task { @MainActor in vm.showSettings.toggle() }
                return nil
            }
            // ⌘N → Neues HarmonyWeb-Dokument
            if event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.shift),
               event.charactersIgnoringModifiers == "n" {
                Task { @MainActor in vm.newHarmonyWebDocument(in: vm.canvasSize) }
                return nil
            }
            // ⌘O → HarmonyWeb-Dokument öffnen…
            if event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.shift),
               event.charactersIgnoringModifiers == "o" {
                Task { @MainActor in presentOpenPanel() }
                return nil
            }
            // ⌘S → Speichern (nur im Dokumentmodus)
            if event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.shift),
               event.charactersIgnoringModifiers == "s",
               vm.harmonyWebMode {
                Task { @MainActor in vm.saveDocument() }
                return nil
            }
            // ⇧⌘S → Speichern unter… (nur im Dokumentmodus)
            if event.modifierFlags.contains(.command),
               event.modifierFlags.contains(.shift),
               event.charactersIgnoringModifiers == "s",
               vm.harmonyWebMode {
                Task { @MainActor in presentSavePanel() }
                return nil
            }
            // ⌘Z → Rückgängig (nur im Dokumentmodus)
            if event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.shift),
               event.charactersIgnoringModifiers == "z",
               vm.harmonyWebMode {
                Task { @MainActor in vm.undoDocument() }
                return nil
            }
            // ⇧⌘Z → Wiederholen (nur im Dokumentmodus)
            if event.modifierFlags.contains(.command),
               event.modifierFlags.contains(.shift),
               event.charactersIgnoringModifiers == "z",
               vm.harmonyWebMode {
                Task { @MainActor in vm.redoDocument() }
                return nil
            }
            return event
        }
    }

    // MARK: – Dokument-I/O: NSOpenPanel / NSSavePanel (K-02)

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "HarmonyWeb-Dokument öffnen"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in vm.openHarmonyWebDocument(at: url, in: vm.canvasSize) }
        }
    }

    private func presentSavePanel() {
        let panel = NSSavePanel()
        panel.title = "HarmonyWeb-Dokument speichern unter"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = defaultSaveFileName()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in vm.saveDocumentAs(to: url) }
        }
    }

    private func defaultSaveFileName() -> String {
        vm.harmonyMap?.name ?? "HarmonyWeb"
    }

    /// Export-Gate (K-06): schreibt nur, wenn `vm.canExportToRuntime` —
    /// `vm.exportDocumentAs(to:)` blockiert selbst strukturiert, falls der
    /// Draft zwischenzeitlich invalide wurde, aber der Panel-Titel macht die
    /// Absicht schon vorher klar (kein Save-As-Alias).
    private func presentExportPanel() {
        let panel = NSSavePanel()
        panel.title = "Validierten HarmonyWeb-Export speichern"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = defaultSaveFileName() + "-export"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in vm.exportDocumentAs(to: url) }
        }
    }

    // MARK: – Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {
            Text("2D Navigator")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            // Edit / Play Modus (im Dokumentmodus: Node-Drag an/aus statt Edit/Play)
            Button { vm.toggleEditMode() } label: {
                HStack(spacing: 5) {
                    Image(systemName: vm.editMode ? "pencil.circle.fill" : "play.circle.fill")
                    Text(vm.harmonyWebMode ? (vm.editMode ? "Drag" : "Ansicht") : (vm.editMode ? "Edit" : "Play"))
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(vm.editMode ? Color.orange : Color.green)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background((vm.editMode ? Color.orange : Color.green).opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(vm.harmonyWebMode ? "Node-Drag umschalten  ⌘E" : "Edit/Play umschalten  ⌘E")

            // Aktiver Akkord
            if let id = vm.activeChordId {
                HStack(spacing: 6) {
                    Circle().fill(Color.cyan).frame(width: 8, height: 8)
                    Text(id)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.cyan)
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.cyan.opacity(0.12))
                .clipShape(Capsule())
            }

            Spacer()

            // Zoom-Buttons
            HStack(spacing: 2) {
                Button {
                    vm.zoomScale = max(0.25, vm.zoomScale / 1.25); baseZoom = vm.zoomScale
                    vm.persistZoomIfDocumentMode()
                } label: {
                    Image(systemName: "minus.magnifyingglass").foregroundStyle(.white.opacity(0.7))
                }.buttonStyle(.plain)
                Text("\(Int(vm.zoomScale * 100))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 38)
                Button {
                    vm.zoomScale = min(4.0, vm.zoomScale * 1.25); baseZoom = vm.zoomScale
                    vm.persistZoomIfDocumentMode()
                } label: {
                    Image(systemName: "plus.magnifyingglass").foregroundStyle(.white.opacity(0.7))
                }.buttonStyle(.plain)
                Button {
                    vm.zoomScale = 1.0; baseZoom = 1.0
                    vm.persistZoomIfDocumentMode()
                } label: {
                    Image(systemName: "arrow.uturn.backward").foregroundStyle(.white.opacity(0.45))
                }.buttonStyle(.plain).help("Zoom zurücksetzen")
            }

            Divider().frame(height: 16).background(Color.white.opacity(0.2))

            if vm.harmonyWebMode {
                // ── HarmonyWeb-Modus: Web-Picker + Layer-Toggle ──────────
                Picker("HarmonyWeb", selection: $vm.selectedWebName) {
                    ForEach(DesignerViewModel.availableWebNames, id: \.self) { name in
                        Text("🌐 \(name)").tag(name)
                    }
                }
                .pickerStyle(.menu).frame(width: 240).tint(.cyan)
                .onChange(of: vm.selectedWebName) { name in
                    // Geo-Größe liegt im VM — canvasSize verwenden
                    vm.loadHarmonyWeb(named: name, in: vm.canvasSize)
                }

                if vm.availableLayers.count > 1 {
                    Picker("Layer", selection: $vm.activeLayer) {
                        ForEach(vm.availableLayers, id: \.self) { layer in
                            Text(layer).tag(layer)
                        }
                    }
                    .pickerStyle(.segmented).frame(width: 160)
                    .onChange(of: vm.activeLayer) { _ in vm.persistActiveLayerIfDocumentMode() }
                }

                // ── Workspace: Drag/Pin/Auto-Layout (K-03) ───────────────
                if vm.editMode, let sel = vm.selectedId {
                    Button {
                        vm.togglePin(sel)
                    } label: {
                        Image(systemName: vm.isPinned(sel) ? "pin.fill" : "pin")
                            .foregroundStyle(vm.isPinned(sel) ? Color.orange : Color.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help(vm.isPinned(sel) ? "Node lösen" : "Node fixieren (Auto-Layout ignoriert ihn)")
                }
                Button {
                    vm.autoLayoutDocument()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.cyan.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Auto-Layout (fixierte Nodes bleiben unverändert)")

                // ── Node-Authoring: Add/Duplicate/Rename/Delete + Undo/Redo (K-04) ─
                Button {
                    vm.addNode()
                } label: {
                    Image(systemName: "plus.circle").foregroundStyle(.green.opacity(0.85))
                }
                .buttonStyle(.plain)
                .help("Node hinzufügen")

                if let sel = vm.selectedId {
                    Button {
                        vm.duplicateSelectedNode()
                    } label: {
                        Image(systemName: "doc.on.doc").foregroundStyle(.cyan.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .help("Node duplizieren")

                    if isRenamingNode {
                        TextField("Neue ID", text: $renameFieldText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                            .onSubmit {
                                vm.renameSelectedNode(to: renameFieldText)
                                isRenamingNode = false
                            }
                        Button {
                            vm.renameSelectedNode(to: renameFieldText)
                            isRenamingNode = false
                        } label: {
                            Image(systemName: "checkmark.circle").foregroundStyle(.green.opacity(0.85))
                        }.buttonStyle(.plain)
                        Button {
                            isRenamingNode = false
                        } label: {
                            Image(systemName: "xmark.circle").foregroundStyle(.white.opacity(0.5))
                        }.buttonStyle(.plain)
                    } else {
                        Button {
                            renameFieldText = sel
                            isRenamingNode = true
                        } label: {
                            Image(systemName: "pencil.circle").foregroundStyle(.cyan.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                        .help("Node umbenennen")
                    }

                    Button {
                        vm.deleteSelectedNode()
                        isRenamingNode = false
                    } label: {
                        Image(systemName: "trash").foregroundStyle(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Node löschen (rückgängig via ⌘Z)")
                }

                Button {
                    vm.undoDocument()
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .foregroundStyle(vm.canUndoDocument ? .white.opacity(0.75) : .white.opacity(0.2))
                }
                .buttonStyle(.plain)
                .disabled(!vm.canUndoDocument)
                .help("Rückgängig  ⌘Z")

                Button {
                    vm.redoDocument()
                } label: {
                    Image(systemName: "arrow.uturn.forward.circle")
                        .foregroundStyle(vm.canRedoDocument ? .white.opacity(0.75) : .white.opacity(0.2))
                }
                .buttonStyle(.plain)
                .disabled(!vm.canRedoDocument)
                .help("Wiederholen  ⇧⌘Z")

                // ── Edge-Auswahl + Delete (K-05) ─────────────────────────
                // Kein Canvas-Hit-Testing auf Kantenlinien (UI klein halten)
                // — Auswahl läuft über eine kompakte ID-Picker-Liste statt
                // Klick-Genauigkeit auf einer dünnen Linie zu verlangen.
                if let map = vm.harmonyMap, !map.edges.isEmpty {
                    Picker("Edge", selection: Binding(
                        get: { vm.selectedDocumentEdgeID ?? "" },
                        set: { vm.selectedDocumentEdgeID = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("—").tag("")
                        ForEach(map.edges, id: \.id) { edge in
                            Text("\(edge.source)→\(edge.target)").tag(edge.id)
                        }
                    }
                    .pickerStyle(.menu).frame(width: 140).tint(.white)

                    if vm.selectedDocumentEdgeID != nil {
                        Button {
                            vm.deleteSelectedEdge()
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .help("Edge löschen (rückgängig via ⌘Z)")
                    }
                }

                // ── Layer-Manager (K-05) ─────────────────────────────────
                Button {
                    if !vm.showLayerManager { resetLayerForm() }
                    vm.showLayerManager.toggle()
                } label: {
                    Image(systemName: "square.3.layers.3d").foregroundStyle(.cyan.opacity(0.85))
                }
                .buttonStyle(.plain)
                .help("Layer verwalten")

                // ── Issue-Navigator (K-06) ───────────────────────────────
                if let doc = vm.document, !doc.diagnostics.issues.isEmpty {
                    Button {
                        vm.showIssueNavigator.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("\(doc.diagnostics.errors.count)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        }
                        .foregroundStyle(doc.diagnostics.errors.isEmpty ? Color.orange.opacity(0.85) : Color.red.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                    .help("Issues anzeigen (\(doc.diagnostics.errors.count) Fehler, \(doc.diagnostics.warnings.count) Warnungen)")
                }

                // ── Export-Gate (K-06) ───────────────────────────────────
                Button {
                    presentExportPanel()
                } label: {
                    Image(systemName: "shippingbox")
                        .foregroundStyle(vm.canExportToRuntime ? Color.green.opacity(0.85) : Color.white.opacity(0.25))
                }
                .buttonStyle(.plain)
                .help(vm.exportGateStatusText)

                // ── Simulation (K-07) ────────────────────────────────────
                Button {
                    vm.showSimulationPanel.toggle()
                } label: {
                    Image(systemName: "play.circle")
                        .foregroundStyle(vm.canRunSimulation ? Color.cyan.opacity(0.85) : Color.white.opacity(0.25))
                }
                .buttonStyle(.plain)
                .help(vm.simulationStatusText)

                // ── Diatonischer Builder (K-08) ──────────────────────────
                Button {
                    vm.showBuilderPanel.toggle()
                } label: {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(vm.canRunBuilder ? Color.purple.opacity(0.85) : Color.white.opacity(0.25))
                }
                .buttonStyle(.plain)
                .help(vm.canRunBuilder ? "Diatonischen Builder öffnen" : "Builder benötigt mindestens einen Layer im Dokument")

                // ── Dokumentstatus + Save/Save As (K-02) ─────────────────
                HStack(spacing: 6) {
                    if vm.documentIsReadOnly {
                        Image(systemName: "lock.fill").font(.system(size: 10))
                            .foregroundStyle(.orange.opacity(0.8))
                    }
                    Text(vm.documentStatusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                    Text(vm.documentDiagnosticsSummary)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())

                Button {
                    vm.saveDocument()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundStyle(vm.canSaveDocument ? .cyan.opacity(0.85) : .white.opacity(0.25))
                }
                .buttonStyle(.plain)
                .disabled(!vm.canSaveDocument)
                .help("Speichern  ⌘S")

                Button {
                    presentSavePanel()
                } label: {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .foregroundStyle(.cyan.opacity(0.85))
                }
                .buttonStyle(.plain)
                .help("Speichern unter…  ⇧⌘S")

                Button {
                    vm.exitHarmonyWebMode(in: vm.canvasSize)
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.cyan.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("HarmonyWeb-Ansicht beenden")

            } else {
                // ── Normaler Netzwerk-Modus ──────────────────────────────
                Picker("Netzwerk", selection: $vm.networkIndex) {
                    ForEach(NetworkParser.definitions, id: \.index) { def in
                        Text("\(def.emoji) \(def.name)").tag(def.index)
                    }
                }
                .pickerStyle(.menu).frame(width: 220).tint(.white)

                // HarmonyWeb-Modus aktivieren
                Button {
                    let firstName = DesignerViewModel.availableWebNames.first ?? ""
                    vm.loadHarmonyWeb(named: firstName, in: vm.canvasSize)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                        Text("Web")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.cyan.opacity(0.8))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.cyan.opacity(0.10))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("HarmonyWeb-Ansicht")

                // ── Dokument: Neu / Öffnen… (K-02) ───────────────────────
                Button {
                    vm.newHarmonyWebDocument(in: vm.canvasSize)
                } label: {
                    Image(systemName: "doc.badge.plus").foregroundStyle(.cyan.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Neues HarmonyWeb-Dokument  ⌘N")

                Button {
                    presentOpenPanel()
                } label: {
                    Image(systemName: "folder").foregroundStyle(.cyan.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("HarmonyWeb-Dokument öffnen…  ⌘O")
            }

            Text(vm.harmonyWebMode
                 ? "\(vm.nodes.count) Nodes · \(vm.harmonyMap?.edges.count ?? 0) Kanten"
                 : "\(vm.nodes.count) · \(vm.edges.count)")
                .font(.system(size: 11))
                .foregroundStyle(vm.harmonyWebMode ? Color.cyan.opacity(0.5) : Color.white.opacity(0.4))

            // Settings + Help
            Button { vm.showSettings.toggle() } label: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(vm.showSettings ? Color.cyan : Color.white.opacity(0.6))
            }.buttonStyle(.plain)
            Button { vm.showHelp.toggle() } label: {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.white.opacity(0.6))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(Color(red: 0.08, green: 0.09, blue: 0.18))
    }

    // MARK: – Aktiver Akkord Bar

    private var activeChordBar: some View {
        HStack(spacing: 12) {
            if let id = vm.activeChordId,
               let node = vm.nodes.first(where: { $0.id == id }) {
                Circle().fill(chordColor(id)).frame(width: 12, height: 12)
                Text(id)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("MIDI: \(node.midiNotes.map(String.init).joined(separator: " "))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                let neighbors = vm.edges
                    .filter  { $0.source == id || $0.target == id }
                    .map     { $0.source == id ? $0.target : $0.source }.sorted()
                Text("→ \(neighbors.joined(separator: "  "))")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
            } else if vm.editMode, let edge = vm.selectedEdge {
                // ── Kanten-Gewicht editieren ──────────────────────────────
                Image(systemName: "slider.horizontal.3").foregroundStyle(.orange.opacity(0.9))
                Text("\(edge.source) – \(edge.target)")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
                Text(String(format: "%.2f", vm.selectedEdgeWeight))
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(.orange)
                Slider(value: Binding(
                    get: { Double(vm.selectedEdgeWeight) },
                    set: { vm.selectedEdgeWeight = Float($0) }
                ), in: 0.05...1.0)
                .tint(.orange)
                .frame(width: 160)
                Spacer()
                Button(role: .destructive) { vm.removeSelectedEdge() } label: {
                    Label("Entfernen", systemImage: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .tint(.red)
                Button { vm.clearEdgeSelection() } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            } else if vm.editMode, let sel = vm.selectedId {
                Image(systemName: "line.diagonal").foregroundStyle(.yellow.opacity(0.8))
                Text("→ Tippe einen anderen Knoten, um eine Kante zu \(sel) zu zeichnen / löschen")
                    .font(.system(size: 12)).foregroundStyle(.yellow.opacity(0.8))
                Spacer()
                Text("Gleichem Knoten tippen = Auswahl aufheben")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.3))
            } else if vm.autopilotActive {
                Image(systemName: "play.circle.fill").foregroundStyle(.green)
                Text(vm.autopilotCurrentChord.map { "Autopilot  ▶  \($0)" } ?? "Autopilot")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.green)
                Spacer()
                let dur = 60.0 / vm.autopilotBPM * Double(vm.autopilotBeatsPerChord)
                Text("Zufall \(Int(vm.autopilotRandomness * 100))%  ·  \(String(format: "%.1f", dur))s / Akkord  ·  Tab Einstellungen")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.22))
            } else {
                Image(systemName: vm.editMode ? "pencil" : "gamecontroller")
                    .foregroundStyle(.white.opacity(0.3))
                Text(vm.editMode
                     ? "Edit: Knoten ziehen · Tippen = Knoten auswählen (dann 2. Knoten = Kante)"
                     : "Rechter Stick: Cursor  ·  Linker Stick: Chord-Töne  ·  R2: Boost")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.35))
                Spacer()
                Text(vm.editMode
                     ? "⌘E Play  ·  Tab Einstellungen"
                     : "D-Pad ◁▷ Netzwerk  ·  △ All Notes Off  ·  ☰ Hilfe  ·  Tab Einstellungen")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.22))
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 36)
        .background(Color(red: 0.07, green: 0.08, blue: 0.18))
    }

    // MARK: – Web-Validierungsbar

    private var webValidationBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 12))
                ForEach(vm.webValidationWarnings, id: \.self) { warning in
                    Text(warning)
                        .font(.system(size: 11))
                        .foregroundStyle(.yellow.opacity(0.9))
                    if warning != vm.webValidationWarnings.last {
                        Text("·").foregroundStyle(.yellow.opacity(0.4))
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 28)
        .background(Color(red: 0.20, green: 0.15, blue: 0.05))
    }

    // MARK: – Settings Panel

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Einstellungen")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button { vm.showSettings = false } label: {
                    Image(systemName: "xmark").foregroundStyle(.white.opacity(0.5))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)

            Divider().background(Color.white.opacity(0.1))

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── MIDI ──────────────────────────────────────────────
                    settingsSection("MIDI") {
                        settingsRow("Akkorde CH") {
                            Picker("", selection: $vm.midiChannel) {
                                ForEach(0..<16) { i in Text("CH \(i+1)").tag(i) }
                            }.pickerStyle(.menu).frame(width: 80).tint(.white)
                        }
                        settingsRow("Chord-Töne CH") {
                            Picker("", selection: $vm.chordToneChannel) {
                                ForEach(0..<16) { i in Text("CH \(i+1)").tag(i) }
                            }.pickerStyle(.menu).frame(width: 80).tint(.white)
                        }
                        settingsSlider("Velocity", value: $vm.chordVelocity,
                                       range: 1...127, unit: "", decimals: 0)
                    }

                    // ── Navigation ────────────────────────────────────────
                    settingsSection("Navigation") {
                        settingsSlider("Geschwindigkeit", value: $vm.playerSpeed,
                                       range: 80...600, unit: " px/s", decimals: 0)
                        settingsSlider("Trigger-Radius", value: $vm.triggerRadius,
                                       range: 20...150, unit: " px", decimals: 0)
                    }

                    // ── Darstellung ───────────────────────────────────────
                    settingsSection("Darstellung") {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Knoten-Größe")
                                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.8))
                                Spacer()
                                Text(String(format: "%.1fx", vm.nodeScale))
                                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(.cyan)
                            }
                            Slider(value: $vm.nodeScale, in: 0.5...2.0).tint(.cyan)
                        }
                        HStack(spacing: 6) {
                            ForEach([0.7, 1.0, 1.3, 1.6], id: \.self) { s in
                                Button("\(Int(s * 100))%") { vm.nodeScale = s }
                                    .buttonStyle(.bordered).font(.system(size: 10))
                            }
                        }
                    }

                    // ── Zoom ──────────────────────────────────────────────
                    settingsSection("Zoom") {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Zoom")
                                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.8))
                                Spacer()
                                Text("\(Int(vm.zoomScale * 100))%")
                                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(.cyan)
                            }
                            Slider(value: $vm.zoomScale, in: 0.25...4.0) { _ in
                                baseZoom = vm.zoomScale
                            }.tint(.cyan)
                        }
                        HStack(spacing: 6) {
                            ForEach([50, 100, 150, 200], id: \.self) { pct in
                                Button("\(pct)%") { vm.zoomScale = CGFloat(pct)/100; baseZoom = vm.zoomScale }
                                    .buttonStyle(.bordered).font(.system(size: 10))
                            }
                        }
                    }

                    // ── Knoten-Magnet ──────────────────────────────────────
                    settingsSection("Knoten-Magnet") {
                        settingsToggle("Aktiv", isOn: $vm.magnetEnabled)
                        settingsSlider("Stärke", value: $vm.magnetStrength,
                                       range: 0...1, unit: "", decimals: 2)
                            .disabled(!vm.magnetEnabled).opacity(vm.magnetEnabled ? 1 : 0.4)
                        settingsSlider("Radius", value: $vm.magnetRadius,
                                       range: 40...300, unit: " px", decimals: 0)
                            .disabled(!vm.magnetEnabled).opacity(vm.magnetEnabled ? 1 : 0.4)
                    }

                    // ── Kanten-Magnet ──────────────────────────────────────
                    settingsSection("Kanten-Magnet") {
                        settingsToggle("Aktiv", isOn: $vm.edgeMagnetEnabled)
                        settingsSlider("Stärke", value: $vm.edgeMagnetStrength,
                                       range: 0...1, unit: "", decimals: 2)
                            .disabled(!vm.edgeMagnetEnabled).opacity(vm.edgeMagnetEnabled ? 1 : 0.4)
                    }

                    // ── Akkord-Filter ──────────────────────────────────────
                    settingsSection("Akkord-Filter") {
                        settingsRow("Tonales Zentrum") {
                            Picker("", selection: $vm.keyCenter) {
                                Text("Alle").tag(-1)
                                ForEach(Array(zip(0..<12, ["C","Db","D","Eb","E","F","F#","G","Ab","A","Bb","B"])),
                                        id: \.0) { i, n in Text(n).tag(i) }
                            }.pickerStyle(.menu).frame(width: 70).tint(.white)
                        }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                            settingsToggle("Dur",         isOn: $vm.showMaj)
                            settingsToggle("Moll",        isOn: $vm.showMin)
                            settingsToggle("Maj7",        isOn: $vm.showMaj7)
                            settingsToggle("Moll7",       isOn: $vm.showMin7)
                            settingsToggle("Dom7",        isOn: $vm.showDom7)
                            settingsToggle("Halbverm.",   isOn: $vm.showHalfDim)
                            settingsToggle("Verm.",       isOn: $vm.showDim7)
                            settingsToggle("Sus",         isOn: $vm.showSus)
                        }
                        Text("\(vm.filteredNodes.count) / \(vm.nodes.count) Akkorde sichtbar")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                    }

                    // ── Autopilot ─────────────────────────────────────────
                    settingsSection("Autopilot") {
                        settingsSlider("BPM", value: $vm.autopilotBPM,
                                       range: 40...240, unit: " BPM", decimals: 0)
                        settingsRow("Beats / Akkord") {
                            Stepper("\(vm.autopilotBeatsPerChord)",
                                    value: $vm.autopilotBeatsPerChord, in: 1...16)
                                .font(.system(size: 12))
                        }
                        settingsSlider("Zufall", value: $vm.autopilotRandomness,
                                       range: 0...1, unit: "", decimals: 2)
                        Text("0 = folgt Kantenwichten · 1 = rein zufällig")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.3))
                        // MIDI Clock
                        settingsRow("MIDI Clock") {
                            Toggle("", isOn: $vm.midiClockEnabled)
                                .labelsHidden()
                                .tint(.orange)
                        }
                        if vm.midiClockEnabled {
                            Text("Sendet 0xFA/0xF8/0xFC an alle MIDI-Empfänger")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange.opacity(0.6))
                        }
                        // Play / Stop
                        HStack(spacing: 10) {
                            Button {
                                vm.toggleAutopilot()
                            } label: {
                                Label(vm.autopilotActive ? "Stop" : "▶ Play",
                                      systemImage: vm.autopilotActive ? "stop.fill" : "play.fill")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .buttonStyle(.bordered)
                            .tint(vm.autopilotActive ? .red : .green)
                            .disabled(vm.editMode || vm.filteredNodes.isEmpty || vm.harmonyWebMode)
                            .help(vm.harmonyWebMode ? "Im Dokumentmodus nicht verfügbar — siehe Simulation (K-07)" : "")

                            if vm.autopilotActive, let cur = vm.autopilotCurrentChord {
                                Text("▶ \(cur)")
                                    .font(.system(size: 12, weight: .bold)).foregroundStyle(.green)
                            }
                        }
                    }

                    // ── Gamepad-Tasten ────────────────────────────────────
                    settingsSection("Gamepad-Tasten") {
                        buttonMappingRow("✕ Cross",   mapping: $vm.mappingA)
                        buttonMappingRow("○ Circle",  mapping: $vm.mappingB)
                        buttonMappingRow("□ Square",  mapping: $vm.mappingX)
                        buttonMappingRow("L1",        mapping: $vm.mappingL1)
                        buttonMappingRow("R1",        mapping: $vm.mappingR1)
                    }

                    // ── Benutzer-Netzwerke ────────────────────────────────
                    settingsSection("Eigene Netzwerke") {
                        Text("Eigene .txt-Dateien im Netzwerk-Ordner ablegen.\nBeim Laden des nächsten Netzwerks werden sie automatisch erkannt.")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                        if let folder = NetworkParser.userNetworkFolder {
                            Button {
                                NSWorkspace.shared.open(folder)
                            } label: {
                                Label("Netzwerk-Ordner öffnen", systemImage: "folder")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.bordered)
                            .help(folder.path)
                        }
                        let userCount = NetworkParser.definitions.count - 13   // 13 = Anzahl eingebaut
                        if userCount > 0 {
                            Text("\(userCount) eigene\(userCount == 1 ? "s" : "") Netzwerk\(userCount == 1 ? "" : "e") geladen")
                                .font(.system(size: 10))
                                .foregroundStyle(.green.opacity(0.75))
                        }
                        Text("Format: `chord C 60 64 67` / `neighbor C Am 0.9`\nMetadaten: `# name:`, `# emoji:`, `# description:`")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // ── Layout ────────────────────────────────────────────
                    settingsSection("Layout") {
                        Text("Im Edit-Modus (⌘E) Knoten verschieben\nund tippen = Kante zeichnen/löschen.\nBeim Wechsel zu Play wird automatisch\ngespeichert.")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Button {
                                vm.saveLayout()
                            } label: {
                                Label("Speichern", systemImage: "square.and.arrow.down")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.bordered)
                            .disabled(vm.harmonyWebMode)
                            .help(vm.harmonyWebMode ? "Im Dokumentmodus nicht verfügbar — Workspace speichert automatisch" : "Layout manuell speichern")

                            Button {
                                vm.resetLayout()
                            } label: {
                                Label("Zurücksetzen", systemImage: "arrow.counterclockwise")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.orange)
                            }
                            .buttonStyle(.bordered)
                            .disabled(vm.harmonyWebMode)
                            .help(vm.harmonyWebMode ? "Im Dokumentmodus nicht verfügbar" : "Auf Force-Directed Layout zurücksetzen")
                        }
                        if vm.hasSavedLayout {
                            Label("Layout gespeichert", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.green.opacity(0.8))
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 280)
        .background(Color(red: 0.08, green: 0.09, blue: 0.18))
        .overlay(Rectangle().frame(width: 1).foregroundStyle(Color.white.opacity(0.1)), alignment: .leading)
    }

    // MARK: – Settings Helpers

    @ViewBuilder
    private func settingsSection<Content: View>(_ title: String,
                                                @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .tracking(1.5)
            content()
        }
    }

    @ViewBuilder
    private func settingsRow<Content: View>(_ label: String,
                                             @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(.white.opacity(0.8))
            Spacer()
            content()
        }
    }

    @ViewBuilder
    private func settingsToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
            Spacer()
            Toggle("", isOn: isOn).toggleStyle(.switch).tint(.cyan).labelsHidden()
        }
    }

    private func midiNoteName(_ n: Int) -> String {
        let names = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        return "\(names[n % 12])\(n / 12 - 1)"
    }

    private func buttonMappingRow(_ label: String, mapping: Binding<ButtonMapping>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 60, alignment: .leading)
                Picker("", selection: mapping.kind) {
                    ForEach(ButtonMapping.Kind.allCases, id: \.self) { k in
                        Text(k.rawValue).tag(k)
                    }
                }.pickerStyle(.menu).tint(.white).frame(maxWidth: .infinity)
            }
            if mapping.wrappedValue.kind == .note || mapping.wrappedValue.kind == .cc {
                HStack(spacing: 8) {
                    Text("CH").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).frame(width: 18)
                    Picker("", selection: mapping.channel) {
                        ForEach(0..<16) { i in Text("\(i+1)").tag(i) }
                    }.pickerStyle(.menu).tint(.white).frame(width: 55)
                    Text(mapping.wrappedValue.kind == .note ? "Note" : "CC")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                    Stepper(value: mapping.number, in: 0...127) {
                        let n = mapping.wrappedValue.number
                        Text(mapping.wrappedValue.kind == .note ? midiNoteName(n) : "\(n)")
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.cyan)
                    }
                }
                if mapping.wrappedValue.kind == .note {
                    HStack(spacing: 8) {
                        Text("Vel").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).frame(width: 28)
                        Stepper(value: mapping.value, in: 1...127) {
                            Text("\(mapping.wrappedValue.value)")
                                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.cyan)
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Text("Wert").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).frame(width: 28)
                        Stepper(value: mapping.value, in: 0...127) {
                            Text("\(mapping.wrappedValue.value)")
                                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.cyan)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func settingsSlider(_ label: String, value: Binding<Double>,
                                 range: ClosedRange<Double>, unit: String,
                                 decimals: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 13)).foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text(decimals == 0
                     ? "\(Int(value.wrappedValue))\(unit)"
                     : String(format: "%.\(decimals)f\(unit)", value.wrappedValue))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.cyan)
            }
            Slider(value: value, in: range).tint(.cyan)
        }
    }

    // MARK: – Node-Inspector (K-04)
    //
    // Bearbeitet Root/Type/Function/MIDI/Tags/Layers/layout3D des
    // selektierten Nodes. Änderungen laufen ausschließlich über
    // `vm.updateSelectedNode(...)` (also einen `HarmonyMapCommand`), nie über
    // direkte `document.draft`-Mutation. Alle Felder sind lokaler `@State`,
    // der bei Auswahlwechsel neu synchronisiert wird (`syncInspectorFields`)
    // — ein einzelner „Anwenden"-Command pro Bearbeitungssession statt eines
    // Commands pro Tastenanschlag (würde sonst den Undo-Stack fluten).

    @ViewBuilder
    private func nodeInspector(for nodeID: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Node: \(nodeID)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button { vm.select(nil) } label: {
                    Image(systemName: "xmark").foregroundStyle(.white.opacity(0.5))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)

            Divider().background(Color.white.opacity(0.1))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    settingsSection("Diagnose") {
                        Text(vm.documentDiagnosticsSummary)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.cyan.opacity(0.85))
                    }

                    settingsSection("Root (0–11)") {
                        Stepper(value: $inspectorRoot, in: 0...11) {
                            Text("\(inspectorRoot)").font(.system(size: 13, design: .monospaced)).foregroundStyle(.cyan)
                        }
                    }

                    settingsSection("Type") {
                        Picker("", selection: $inspectorType) {
                            ForEach(ChordType.allCases, id: \.self) { t in
                                Text(t.rawValue).tag(t)
                            }
                        }.pickerStyle(.menu).tint(.white)
                    }

                    settingsSection("Function") {
                        Picker("", selection: $inspectorFunction) {
                            ForEach(HarmonicFunction.allCases, id: \.self) { f in
                                Text(f.rawValue).tag(f)
                            }
                        }.pickerStyle(.menu).tint(.white)
                    }

                    settingsSection("MIDI Notes (kommagetrennt)") {
                        TextField("z. B. 60,64,67", text: $inspectorMidiNotesText)
                            .textFieldStyle(.roundedBorder)
                    }

                    settingsSection("Tags (kommagetrennt)") {
                        TextField("z. B. bright,intro", text: $inspectorTagsText)
                            .textFieldStyle(.roundedBorder)
                    }

                    if !vm.availableLayers.isEmpty {
                        settingsSection("Layer-Zugehörigkeit") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(vm.availableLayers, id: \.self) { layer in
                                    Toggle(layer, isOn: Binding(
                                        get: { inspectorLayers.contains(layer) },
                                        set: { isOn in
                                            if isOn { inspectorLayers.insert(layer) } else { inspectorLayers.remove(layer) }
                                        }
                                    ))
                                    .toggleStyle(.checkbox)
                                    .font(.system(size: 12))
                                }
                            }
                        }
                    }

                    settingsSection("layout3D (optional)") {
                        Toggle("gesetzt", isOn: $inspectorLayout3DEnabled).toggleStyle(.checkbox).font(.system(size: 12))
                        if inspectorLayout3DEnabled {
                            HStack(spacing: 6) {
                                TextField("x", text: $inspectorLayoutX).frame(width: 50)
                                TextField("y", text: $inspectorLayoutY).frame(width: 50)
                                TextField("z", text: $inspectorLayoutZ).frame(width: 50)
                            }.textFieldStyle(.roundedBorder)
                        }
                    }

                    Button {
                        applyInspectorChanges(nodeID: nodeID)
                    } label: {
                        Text("Anwenden").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(16)
            }
        }
        .frame(width: 280)
        .background(Color(red: 0.08, green: 0.09, blue: 0.18))
        .overlay(Rectangle().frame(width: 1).foregroundStyle(Color.white.opacity(0.1)), alignment: .leading)
        .onAppear { syncInspectorFields(nodeID: nodeID) }
        .onChange(of: nodeID) { newID in syncInspectorFields(nodeID: newID) }
    }

    private func syncInspectorFields(nodeID: String) {
        guard let node = vm.harmonyMap?.nodes.first(where: { $0.id == nodeID }) else { return }
        inspectedNodeID = nodeID
        inspectorRoot = node.root
        inspectorType = node.type
        inspectorFunction = node.function
        inspectorMidiNotesText = node.midiNotes.map(String.init).joined(separator: ",")
        inspectorTagsText = node.tags.joined(separator: ",")
        inspectorLayers = Set(node.layers ?? [])
        if let l3d = node.layout3D {
            inspectorLayout3DEnabled = true
            inspectorLayoutX = String(l3d.x)
            inspectorLayoutY = String(l3d.y)
            inspectorLayoutZ = String(l3d.z)
        } else {
            inspectorLayout3DEnabled = false
            inspectorLayoutX = "0"; inspectorLayoutY = "0"; inspectorLayoutZ = "0"
        }
    }

    private func applyInspectorChanges(nodeID: String) {
        let midiNotes = inspectorMidiNotesText
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let tags = inspectorTagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let layout3D: Layout3D? = inspectorLayout3DEnabled
            ? Layout3D(x: Float(inspectorLayoutX) ?? 0, y: Float(inspectorLayoutY) ?? 0, z: Float(inspectorLayoutZ) ?? 0)
            : nil
        let layers: [String]? = inspectorLayers.isEmpty ? nil : Array(inspectorLayers).sorted()

        vm.updateSelectedNode(
            root: inspectorRoot, type: inspectorType, function: inspectorFunction, midiNotes: midiNotes,
            tags: tags, layers: layers, layout3D: layout3D
        )
    }

    // MARK: – Edge-Inspector (K-05)
    //
    // Bearbeitet source/target/directed/relationTypes/layers/weight/
    // magnetProfile/bridgesTo der selektierten Edge über `UpdateEdgeCommand`
    // (via `vm.updateSelectedEdge`) — dieselbe „Anwenden pro Session"-
    // Strategie wie der Node-Inspector.

    @ViewBuilder
    private func edgeInspector(for edgeID: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Edge: \(edgeID)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button { vm.selectedDocumentEdgeID = nil } label: {
                    Image(systemName: "xmark").foregroundStyle(.white.opacity(0.5))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)

            Divider().background(Color.white.opacity(0.1))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    settingsSection("Source / Target") {
                        Picker("", selection: $edgeSource) {
                            ForEach(vm.nodes.map(\.id), id: \.self) { Text($0).tag($0) }
                        }.pickerStyle(.menu).tint(.white)
                        Picker("", selection: $edgeTarget) {
                            ForEach(vm.nodes.map(\.id), id: \.self) { Text($0).tag($0) }
                        }.pickerStyle(.menu).tint(.white)
                    }

                    settingsSection("Gerichtet") {
                        Toggle("directed", isOn: $edgeDirected).toggleStyle(.checkbox).font(.system(size: 12))
                    }

                    settingsSection("RelationTypes") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(RelationType.allCases, id: \.self) { rt in
                                Toggle(rt.rawValue, isOn: Binding(
                                    get: { edgeRelationTypes.contains(rt) },
                                    set: { isOn in
                                        if isOn { edgeRelationTypes.insert(rt) } else { edgeRelationTypes.remove(rt) }
                                    }
                                )).toggleStyle(.checkbox).font(.system(size: 12))
                            }
                        }
                    }

                    settingsSection("Gewicht (> 0)") {
                        TextField("z. B. 0.8", text: $edgeWeightText).textFieldStyle(.roundedBorder)
                    }

                    settingsSection("MagnetPreset (optional)") {
                        Picker("", selection: $edgeMagnetPreset) {
                            Text("keins").tag(MagnetProfile.Preset?.none)
                            ForEach(MagnetProfile.Preset.allCases, id: \.self) { p in
                                Text(p.rawValue).tag(MagnetProfile.Preset?.some(p))
                            }
                        }.pickerStyle(.menu).tint(.white)
                    }

                    if !vm.availableLayers.isEmpty {
                        settingsSection("Layer") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(vm.availableLayers, id: \.self) { layer in
                                    Toggle(layer, isOn: Binding(
                                        get: { edgeLayers.contains(layer) },
                                        set: { isOn in
                                            if isOn { edgeLayers.insert(layer) } else { edgeLayers.remove(layer) }
                                        }
                                    )).toggleStyle(.checkbox).font(.system(size: 12))
                                }
                            }
                        }
                    }

                    settingsSection("bridgesTo (optional)") {
                        TextField("Node-ID", text: $edgeBridgesToText).textFieldStyle(.roundedBorder)
                    }

                    Button {
                        applyEdgeInspectorChanges(edgeID: edgeID)
                    } label: {
                        Text("Anwenden").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(16)
            }
        }
        .frame(width: 280)
        .background(Color(red: 0.08, green: 0.09, blue: 0.18))
        .overlay(Rectangle().frame(width: 1).foregroundStyle(Color.white.opacity(0.1)), alignment: .leading)
        .onAppear { syncEdgeInspectorFields(edgeID: edgeID) }
        .onChange(of: edgeID) { newID in syncEdgeInspectorFields(edgeID: newID) }
    }

    private func syncEdgeInspectorFields(edgeID: String) {
        guard let edge = vm.harmonyMap?.edges.first(where: { $0.id == edgeID }) else { return }
        inspectedEdgeID = edgeID
        edgeSource = edge.source
        edgeTarget = edge.target
        edgeDirected = edge.directed
        edgeRelationTypes = Set(edge.relationTypes)
        edgeLayers = Set(edge.layers)
        edgeWeightText = String(edge.weight)
        edgeMagnetPreset = edge.magnetProfile?.preset
        edgeBridgesToText = edge.bridgesTo ?? ""
    }

    private func applyEdgeInspectorChanges(edgeID: String) {
        let weight = Float(edgeWeightText) ?? 1.0
        let magnetProfile = edgeMagnetPreset.map { MagnetProfile(preset: $0) }
        let bridgesTo = edgeBridgesToText.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil : edgeBridgesToText.trimmingCharacters(in: .whitespaces)

        vm.updateSelectedEdge(
            source: edgeSource, target: edgeTarget, directed: edgeDirected,
            relationTypes: Array(edgeRelationTypes), layers: Array(edgeLayers).sorted(),
            weight: weight, magnetProfile: magnetProfile, bridgesTo: bridgesTo
        )
    }

    // MARK: – Issue-Navigator (K-06)
    //
    // Zeigt `document.diagnostics.issues` (aktueller `HarmonyMapValidator`-
    // Stand, nach jeder Command-Mutation/Undo/Redo automatisch aktuell, da
    // `document` ein `@Published`-Wert ist). Klick auf ein Issue ruft
    // `vm.focusIssue(_:)` auf — Fokus-Logik lebt im ViewModel, dieses Panel
    // ist reine Anzeige.

    @ViewBuilder
    private var issueNavigator: some View {
        let issues = vm.document?.diagnostics.issues ?? []
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Issues")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button { vm.showIssueNavigator = false } label: {
                    Image(systemName: "xmark").foregroundStyle(.white.opacity(0.5))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 4)

            Text(vm.documentDiagnosticsSummary)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 16).padding(.bottom, 12)

            Divider().background(Color.white.opacity(0.1))

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if issues.isEmpty {
                        Text("Keine Issues")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
                            .padding(16)
                    }
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                        Button {
                            vm.focusIssue(issue)
                        } label: {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(issue.severity == .error ? Color.red.opacity(0.85) : Color.orange.opacity(0.85))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(issue.code)
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.9))
                                    Text(issue.objectPath)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.5))
                                    Text(issue.message)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.75))
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        Divider().background(Color.white.opacity(0.05))
                    }
                }
            }
        }
        .frame(width: 280)
        .background(Color(red: 0.08, green: 0.09, blue: 0.18))
        .overlay(Rectangle().frame(width: 1).foregroundStyle(Color.white.opacity(0.1)), alignment: .leading)
    }

    // MARK: – Simulation (K-07)
    //
    // Runtime-nahe 2D-Simulation über `HarmonyGraphSimulation`
    // (`HarmonyAuthoring`) — Traversierung/Layerfilterung/History/effektive
    // Gewichte kommen ausschließlich aus `HarmonyGraphEngine`, keine eigene
    // Logik hier. Bei Validator-Errors blockiert `vm.canRunSimulation` Start/
    // Step/Reset; die Statuszeile verweist auf Issues/Export-Gate
    // (`vm.simulationStatusText`, teilt sich den Text mit dem K-06-Export-
    // Gate-Status).

    @ViewBuilder
    private var simulationPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Simulation")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button { vm.showSimulationPanel = false } label: {
                    Image(systemName: "xmark").foregroundStyle(.white.opacity(0.5))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 4)

            Text(vm.simulationStatusText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(vm.canRunSimulation ? .cyan.opacity(0.85) : .orange.opacity(0.85))
                .padding(.horizontal, 16).padding(.bottom, 12)

            Divider().background(Color.white.opacity(0.1))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !vm.canRunSimulation {
                        Text("Behebe zuerst die Validator-Fehler (Issues-Panel), um die Simulation zu starten.")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                    } else if let sim = vm.simulation {
                        settingsSection("Aktuell") {
                            Text(sim.currentNodeID)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.cyan)
                        }
                        settingsSection("Layer") {
                            Picker("", selection: Binding(
                                get: { sim.activeLayer },
                                set: { vm.setSimulationLayer($0) }
                            )) {
                                ForEach(vm.availableLayers, id: \.self) { Text($0).tag($0) }
                            }.pickerStyle(.menu).tint(.white)
                        }
                        settingsSection("Seed") {
                            Text("\(sim.seed)").font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.7))
                        }
                        settingsSection("History") {
                            Text(sim.history.joined(separator: " → "))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        HStack {
                            Button("Step") { vm.stepSimulation() }.buttonStyle(.borderedProminent)
                            Button("Reset") { vm.resetSimulation() }.buttonStyle(.bordered)
                            Button("Stop") { vm.stopSimulation() }.buttonStyle(.bordered)
                        }

                        settingsSection("Kandidaten") {
                            VStack(alignment: .leading, spacing: 8) {
                                if sim.candidates.isEmpty {
                                    Text("Keine ausgehenden Kanten").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                                }
                                ForEach(Array(sim.candidates.enumerated()), id: \.offset) { _, candidate in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(candidate.transition.targetNode.id)
                                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(.white.opacity(0.9))
                                        Text("\(candidate.transition.edge.relationTypes.map(\.rawValue).joined(separator: "+"))"
                                             + " · \(candidate.fieldKind.rawValue)"
                                             + " · \(candidate.magnetPreset?.rawValue ?? "–")"
                                             + " · range=\(String(format: "%.1f", candidate.effectiveRange))"
                                             + " · weight=\(String(format: "%.3f", candidate.transition.effectiveWeight))")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.white.opacity(0.55))
                                    }
                                    Divider().background(Color.white.opacity(0.05))
                                }
                            }
                        }
                    } else {
                        settingsSection("Start-Node") {
                            Picker("", selection: $simulationStartNodeID) {
                                ForEach(vm.nodes.map(\.id), id: \.self) { Text($0).tag($0) }
                            }.pickerStyle(.menu).tint(.white)
                        }
                        settingsSection("Seed") {
                            TextField("Seed", text: $simulationSeedText).textFieldStyle(.roundedBorder)
                        }
                        Button("Simulation starten") {
                            vm.simulationSeed = UInt64(simulationSeedText) ?? 1
                            let start = simulationStartNodeID.isEmpty ? (vm.nodes.first?.id ?? "") : simulationStartNodeID
                            guard !start.isEmpty else { return }
                            vm.startSimulation(from: start)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.nodes.isEmpty)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 280)
        .background(Color(red: 0.08, green: 0.09, blue: 0.18))
        .overlay(Rectangle().frame(width: 1).foregroundStyle(Color.white.opacity(0.1)), alignment: .leading)
    }

    // MARK: – Diatonischer Builder (K-08)
    //
    // Zeigt einen Vorschlags-Diff (`DiatonicHarmonyBuilder`, HarmonyAuthoring
    // — UI-frei) vor Apply an: Anzahl Nodes/Edges, Begründung je Vorschlag,
    // Warnungen (z. B. bereits existierende IDs, fehlender Ziel-Layer). Apply
    // läuft als ein einziger Dokument-Command (`vm.applyBuilderDiff()`,
    // genau ein Undo-Schritt); Cancel/Schließen verwirft den Diff ohne
    // jede Draft-Mutation (`vm.cancelBuilderDiff()`).

    private static let builderKeyNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    @ViewBuilder
    private var builderPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Diatonischer Builder")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    vm.cancelBuilderDiff()
                    vm.showBuilderPanel = false
                } label: {
                    Image(systemName: "xmark").foregroundStyle(.white.opacity(0.5))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)

            Divider().background(Color.white.opacity(0.1))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    settingsSection("Tonart") {
                        Picker("", selection: $vm.builderKeyRoot) {
                            ForEach(0..<12, id: \.self) { pitchClass in
                                Text(Self.builderKeyNames[pitchClass]).tag(pitchClass)
                            }
                        }.pickerStyle(.menu).tint(.white)
                    }
                    Text("Erzeugt die sieben diatonischen Stufenakkorde in Dur/Ionian plus stufenweise Nachbarschafts-Kanten.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))

                    Button("Vorschlag erzeugen") { vm.previewBuilderDiff() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!vm.canRunBuilder)

                    if let reason = vm.builderBlockedReason {
                        Text(reason)
                            .font(.system(size: 11))
                            .foregroundStyle(.orange.opacity(0.85))
                    }

                    if let diff = vm.builderDiff {
                        Divider().background(Color.white.opacity(0.1))

                        settingsSection("Diff") {
                            Text("\(diff.proposedNodes.count) Nodes, \(diff.proposedEdges.count) Edges")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.cyan)
                        }

                        if !diff.warnings.isEmpty {
                            settingsSection("Warnungen") {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(Array(diff.warnings.enumerated()), id: \.offset) { _, warning in
                                        Text(warning.description)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.orange.opacity(0.85))
                                    }
                                }
                            }
                        }

                        if !diff.proposedNodes.isEmpty {
                            settingsSection("Vorgeschlagene Nodes") {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(diff.proposedNodes.enumerated()), id: \.offset) { _, proposed in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(proposed.node.id)
                                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(.white.opacity(0.9))
                                            Text(proposed.rationale)
                                                .font(.system(size: 10))
                                                .foregroundStyle(.white.opacity(0.5))
                                        }
                                    }
                                }
                            }
                        }

                        if !diff.proposedEdges.isEmpty {
                            settingsSection("Vorgeschlagene Edges") {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(diff.proposedEdges.enumerated()), id: \.offset) { _, proposed in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(proposed.edge.source) – \(proposed.edge.target)")
                                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(.white.opacity(0.9))
                                            Text(proposed.rationale)
                                                .font(.system(size: 10))
                                                .foregroundStyle(.white.opacity(0.5))
                                        }
                                    }
                                }
                            }
                        }

                        HStack {
                            Button("Apply") { vm.applyBuilderDiff() }
                                .buttonStyle(.borderedProminent)
                                .disabled(diff.isEmpty)
                            Button("Cancel") { vm.cancelBuilderDiff() }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 280)
        .background(Color(red: 0.08, green: 0.09, blue: 0.18))
        .overlay(Rectangle().frame(width: 1).foregroundStyle(Color.white.opacity(0.1)), alignment: .leading)
    }

    // MARK: – Layer-Manager (K-05)
    //
    // Add/Rename/Update/Delete für `HarmonyLayer` — Layer-Solo/Overlay
    // selbst (welcher Layer aktuell „solo" sichtbar ist) bleibt der
    // bestehende `vm.activeLayer`/Layer-Picker in der Toolbar (Workspace-
    // Zustand seit vor K-03), dieses Panel verwaltet nur den Layer-Katalog.

    @ViewBuilder
    private var layerManager: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Layer verwalten")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button { vm.showLayerManager = false } label: {
                    Image(systemName: "xmark").foregroundStyle(.white.opacity(0.5))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)

            Divider().background(Color.white.opacity(0.1))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    settingsSection("Bestehende Layer") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(vm.harmonyMap?.layers ?? [], id: \.id) { layer in
                                HStack {
                                    Text("\(layer.name) (\(layer.id))")
                                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                                    Spacer()
                                    Button {
                                        vm.selectedLayerID = layer.id
                                        layerNewID = layer.id
                                        layerNewName = layer.name
                                        layerNewRelationTypes = Set(layer.relationTypes)
                                    } label: {
                                        Image(systemName: "pencil").foregroundStyle(.cyan.opacity(0.8))
                                    }.buttonStyle(.plain)
                                    Button {
                                        vm.deleteLayer(layer.id)
                                    } label: {
                                        Image(systemName: "trash").foregroundStyle(.red.opacity(0.8))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    Divider().background(Color.white.opacity(0.1))

                    settingsSection(vm.selectedLayerID == nil ? "Neuer Layer" : "Layer bearbeiten: \(vm.selectedLayerID ?? "")") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("ID", text: $layerNewID).textFieldStyle(.roundedBorder)
                            TextField("Name", text: $layerNewName).textFieldStyle(.roundedBorder)
                            Text("RelationTypes").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                            ForEach(RelationType.allCases, id: \.self) { rt in
                                Toggle(rt.rawValue, isOn: Binding(
                                    get: { layerNewRelationTypes.contains(rt) },
                                    set: { isOn in
                                        if isOn { layerNewRelationTypes.insert(rt) } else { layerNewRelationTypes.remove(rt) }
                                    }
                                )).toggleStyle(.checkbox).font(.system(size: 12))
                            }

                            HStack {
                                Button {
                                    if let existing = vm.selectedLayerID {
                                        vm.updateLayer(layerID: existing, newID: layerNewID, name: layerNewName, relationTypes: Array(layerNewRelationTypes))
                                    } else {
                                        vm.addLayer(id: layerNewID, name: layerNewName, relationTypes: Array(layerNewRelationTypes))
                                    }
                                    resetLayerForm()
                                } label: {
                                    Text(vm.selectedLayerID == nil ? "Layer hinzufügen" : "Änderungen anwenden")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)

                                if vm.selectedLayerID != nil {
                                    Button("Abbrechen") { resetLayerForm() }
                                        .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 280)
        .background(Color(red: 0.08, green: 0.09, blue: 0.18))
        .overlay(Rectangle().frame(width: 1).foregroundStyle(Color.white.opacity(0.1)), alignment: .leading)
        // Synct das Bearbeitungsformular auch, wenn `selectedLayerID` von
        // außerhalb dieses Panels gesetzt wird (z. B. `vm.focusIssue(_:)`
        // aus dem Issue-Navigator, K-06) — nicht nur über den Pencil-Button.
        .onChange(of: vm.selectedLayerID) { newID in
            guard let id = newID, let layer = vm.harmonyMap?.layers.first(where: { $0.id == id }) else { return }
            layerNewID = layer.id
            layerNewName = layer.name
            layerNewRelationTypes = Set(layer.relationTypes)
        }
    }

    /// Setzt das Formular in den „Neuer Layer"-Zustand zurück, vorbefüllt
    /// mit einer sofort editierbaren, gültigen Platzhalter-ID (analog zum
    /// Node-/Edge-Add-Default aus K-04/K-05) statt leerer Felder.
    private func resetLayerForm() {
        vm.selectedLayerID = nil
        let existingIDs = Set(vm.harmonyMap?.layers.map { $0.id } ?? [])
        layerNewID = AuthoringIDGenerator.freeID(base: "new-layer", existingIDs: existingIDs)
        layerNewName = layerNewID
        layerNewRelationTypes = [.commonTone]
    }

    // MARK: – Help Overlay

    private var helpOverlay: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Steuerung – 2D Navigator")
                .font(.system(size: 16, weight: .bold)).foregroundStyle(.white).padding(.bottom, 4)
            Group {
                helpRow("Rechter Stick",   "Cursor bewegen")
                helpRow("R2",              "Speed Boost (×2.5)")
                helpRow("Linker Stick",    "Chord-Töne (Root/Terz/Quinte/Septime)")
                helpRow("D-Pad ◁ ▷",      "Netzwerk wechseln")
                helpRow("Touchpad Swipe", "Netzwerk wechseln (DualSense)")
                helpRow("△  Dreieck",      "All Notes Off")
                helpRow("☰  OPTIONS",      "Dieses Overlay")
                helpRow("Pinch / ⊖ ⊕",    "Zoom")
                helpRow("⌘E",              "Edit / Play umschalten (speichert Layout)")
                helpRow("Tab",             "Einstellungen öffnen/schließen")
                helpRow("Edit: 1. Tippen", "Knoten auswählen (gelb = aktiv)")
                helpRow("Edit: 2. Tippen", "Kante zeichnen / löschen")
            }
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .padding(40)
        .onTapGesture { vm.showHelp = false }
    }

    private func helpRow(_ key: String, _ desc: String) -> some View {
        HStack(spacing: 16) {
            Text(key)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.cyan).frame(width: 160, alignment: .leading)
            Text(desc).font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: – Canvas: Kanten

    private func drawEdges(ctx: GraphicsContext) {
        let sel = vm.selectedEdge
        for edge in vm.visibleEdges {
            let a = vm.positionOf(edge.source)
            let b = vm.positionOf(edge.target)
            guard a != .zero, b != .zero else { continue }

            let isSelectedEdge = sel.map {
                ($0.source == edge.source && $0.target == edge.target) ||
                ($0.source == edge.target && $0.target == edge.source)
            } ?? false
            let isNodeActive = vm.selectedId == edge.source || vm.selectedId == edge.target

            var path = Path()
            path.move(to: a); path.addLine(to: b)

            if isSelectedEdge {
                // Ausgewählte Kante: orange, dicker, Gewicht sichtbar
                ctx.stroke(path, with: .color(.orange.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                // Gewichts-Label in der Mitte der Kante
                let mid  = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                let label = String(format: "%.2f", edge.weight)
                ctx.draw(Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.orange),
                         at: mid, anchor: .center)
            } else {
                let alpha = isNodeActive ? Double(edge.weight) * 0.85 + 0.15
                                         : Double(edge.weight) * 0.35 + 0.15
                let width = isNodeActive ? Double(edge.weight) * 3.0 + 1.0
                                         : Double(edge.weight) * 1.5 + 0.8
                ctx.stroke(path, with: .color(.white.opacity(alpha)),
                           style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
    }

    // MARK: – Canvas: HarmonyWeb-Kanten

    /// Zeichnet Kanten einer geladenen HarmonyMap mit vollem Semantik-Feedback:
    /// - RelationType → Farbe
    /// - directed → Pfeilspitze am Zielknoten
    /// - Layer-Zugehörigkeit → Opacity (aktiver Layer = voll, anderer = gedimmt)
    private func drawWebEdges(ctx: GraphicsContext) {
        let nodeR: CGFloat = 44 * vm.nodeScale   // halber Knotendurchmesser (48 * scale)

        for edge in vm.webEdgesForDisplay {
            let a = vm.positionOf(edge.source)
            let b = vm.positionOf(edge.target)
            guard a != .zero, b != .zero else { continue }

            let inActiveLayer = edge.layers.contains(vm.activeLayer)
            let opacity: Double = inActiveLayer ? 1.0 : 0.18
            let baseColor = webEdgeColor(edge.relationTypes)
            let color = baseColor.opacity(opacity)
            let lineWidth: CGFloat = CGFloat(edge.weight) * 2.5 + 0.8

            // Kante
            var path = Path()
            path.move(to: a)
            path.addLine(to: b)
            ctx.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            // Pfeilspitze (nur bei gerichteten Kanten)
            if edge.directed {
                drawArrowhead(ctx: ctx, from: a, to: b, nodeRadius: nodeR, color: color)
            }

            // Gewichts-Label für ausgewählten Knoten (an Kantenmitte)
            if let sel = vm.selectedId,
               (edge.source == sel || edge.target == sel) {
                let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                let label = String(format: "%.2f", edge.weight)
                ctx.draw(Text(label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(baseColor.opacity(max(0.5, opacity))),
                         at: mid, anchor: .center)
            }
        }
    }

    /// Zeichnet eine gefüllte Pfeilspitze am Endpunkt einer Kante.
    /// Rückt vom Zielknoten-Mittelpunkt um `nodeRadius` zurück, damit die Spitze
    /// an der Knotenkontur endet und nicht dahinter verschwindet.
    private func drawArrowhead(ctx: GraphicsContext,
                               from: CGPoint, to: CGPoint,
                               nodeRadius: CGFloat, color: Color) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > nodeRadius * 2 else { return }   // Kante zu kurz für Pfeil

        let ux = dx / len
        let uy = dy / len
        // Pfeilspitze liegt an der Knotenkontur
        let tip = CGPoint(x: to.x - ux * nodeRadius, y: to.y - uy * nodeRadius)
        let arrowLen:   CGFloat = 13
        let arrowWidth: CGFloat = 6
        let base = CGPoint(x: tip.x - ux * arrowLen, y: tip.y - uy * arrowLen)

        var arrow = Path()
        arrow.move(to: tip)
        arrow.addLine(to: CGPoint(x: base.x - uy * arrowWidth, y: base.y + ux * arrowWidth))
        arrow.addLine(to: CGPoint(x: base.x + uy * arrowWidth, y: base.y - ux * arrowWidth))
        arrow.closeSubpath()
        ctx.fill(arrow, with: .color(color))
    }

    /// Mappt RelationTypes auf Kantenfarben:
    /// vToI          → Gold        (V-I,              auffällig)
    /// iiToV         → Orange      (ii-V,             klar)
    /// relMajMin     → Teal        (tonale Parallele, weich)
    /// parallelMajMin→ Grünblau    (Modal Interchange, moderat)
    /// commonTone    → Blaugrau    (dezent)
    /// tritSubst     → Violett     (Tritonussubstitution)
    private func webEdgeColor(_ types: [RelationType]) -> Color {
        guard let primary = types.first else { return .white }
        switch primary {
        case .vToI:           return Color(hue: 0.12, saturation: 0.90, brightness: 1.00)
        case .iiToV:          return Color(hue: 0.07, saturation: 0.80, brightness: 0.95)
        case .relMajMin:      return Color(hue: 0.47, saturation: 0.60, brightness: 0.85)
        case .parallelMajMin: return Color(hue: 0.50, saturation: 0.55, brightness: 0.80)
        case .commonTone:     return Color(hue: 0.60, saturation: 0.40, brightness: 0.70)
        case .tritSubst:      return Color(hue: 0.78, saturation: 0.70, brightness: 0.85)
        }
    }

    // MARK: – Canvas: Magnet-Radius

    private func drawMagnetRings(ctx: GraphicsContext) {
        guard vm.magnetEnabled || vm.edgeMagnetEnabled else { return }
        let r = CGFloat(vm.magnetRadius)
        for node in vm.nodes {
            let pos  = node.position
            let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
            ctx.stroke(Path(ellipseIn: rect),
                       with: .color(Color.white.opacity(0.04)),
                       style: StrokeStyle(lineWidth: 0.5, dash: [6, 6]))
        }
    }

    // MARK: – Canvas: Trigger-Radius

    private func drawTriggerRings(ctx: GraphicsContext) {
        let r = CGFloat(vm.triggerRadius)
        for node in vm.nodes {
            let pos      = node.position
            let isActive = vm.activeChordId == node.id
            let color    = isActive ? Color.cyan.opacity(0.60) : Color.white.opacity(0.09)
            let lineW: CGFloat = isActive ? 1.5 : 0.5
            let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
            ctx.stroke(Path(ellipseIn: rect),
                       with: .color(color),
                       style: StrokeStyle(lineWidth: lineW, dash: isActive ? [] : [4, 3]))
        }
    }

    // MARK: – Drag-Gesture (Edit-Modus)

    private func dragGesture(for nodeId: String) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { val in
                if draggingId != nodeId {
                    draggingId = nodeId
                    lastDragTranslation = .zero
                }
                let dx = (val.translation.width  - lastDragTranslation.width)  / vm.zoomScale
                let dy = (val.translation.height - lastDragTranslation.height) / vm.zoomScale
                vm.moveNode(id: nodeId, by: CGPoint(x: dx, y: dy))
                lastDragTranslation = val.translation
            }
            .onEnded { _ in
                // Persistenz am Drag-Ende, nicht bei jedem Delta (K-03).
                if vm.harmonyWebMode { vm.saveWorkspace() }
                draggingId = nil
                lastDragTranslation = .zero
            }
    }

    // MARK: – Highlight-Logik

    private func isHighlighted(_ id: String) -> Bool {
        guard let sel = vm.selectedId else { return true }
        if id == sel { return true }
        if vm.harmonyWebMode {
            return vm.webEdgesForDisplay.contains { ($0.source == sel && $0.target == id)
                                                  || ($0.target == sel && $0.source == id) }
        }
        return vm.edges.contains { ($0.source == sel && $0.target == id)
                                || ($0.target == sel && $0.source == id) }
    }
}

// MARK: – Spieler-Cursor

struct PlayerCursorView: View {
    var isAutopilot: Bool = false
    private let outerR: CGFloat = 20
    private let innerR: CGFloat = 5

    private var accent: Color { isAutopilot ? .green : .cyan }
    private var totalSize: CGFloat { outerR * 2 + (isAutopilot ? 16 : 0) }

    var body: some View {
        // Canvas garantiert (0,0) = oben links, Mitte = (size/2, size/2)
        Canvas { ctx, size in
            let cx = size.width  / 2
            let cy = size.height / 2

            // Äußerer Pulsring (nur Autopilot)
            if isAutopilot {
                let pulseRect = CGRect(x: cx - outerR - 8, y: cy - outerR - 8,
                                       width: (outerR + 8) * 2, height: (outerR + 8) * 2)
                ctx.stroke(Path(ellipseIn: pulseRect),
                           with: .color(accent.opacity(0.25)), lineWidth: 8)
            }

            // Äußerer Ring
            let ringRect = CGRect(x: cx - outerR, y: cy - outerR,
                                   width: outerR * 2, height: outerR * 2)
            ctx.stroke(Path(ellipseIn: ringRect),
                       with: .color(accent.opacity(0.45)), lineWidth: 1.5)

            // Fadenkreuz-Linien — exakt zentriert auf (cx, cy)
            var cross = Path()
            cross.move(to:    CGPoint(x: cx - outerR + 4, y: cy))
            cross.addLine(to: CGPoint(x: cx - innerR - 2, y: cy))
            cross.move(to:    CGPoint(x: cx + innerR + 2, y: cy))
            cross.addLine(to: CGPoint(x: cx + outerR - 4, y: cy))
            cross.move(to:    CGPoint(x: cx, y: cy - outerR + 4))
            cross.addLine(to: CGPoint(x: cx, y: cy - innerR - 2))
            cross.move(to:    CGPoint(x: cx, y: cy + innerR + 2))
            cross.addLine(to: CGPoint(x: cx, y: cy + outerR - 4))
            ctx.stroke(cross, with: .color(accent.opacity(0.8)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

            // Zentraler Punkt (Auge)
            let dotRect = CGRect(x: cx - innerR, y: cy - innerR,
                                  width: innerR * 2, height: innerR * 2)
            ctx.fill(Path(ellipseIn: dotRect),
                     with: .color(isAutopilot ? accent : .white))
        }
        .frame(width: totalSize, height: totalSize)
        .shadow(color: accent.opacity(0.6), radius: 4)
    }
}

// MARK: – Chord-Knoten-View

struct NodeView: View {
    let node:          LayoutNode
    let isSelected:    Bool
    let isHighlighted: Bool
    let isActive:      Bool
    var editMode:      Bool    = false
    var scale:         CGFloat = 1.0

    private var diameter: CGFloat { 96 * scale }

    // Ausgewählt im Edit-Modus = bereit zum Verbinden
    private var readyToConnect: Bool { editMode && isSelected }

    var body: some View {
        ZStack {
            // Pulsring wenn "bereit zum Verbinden"
            if readyToConnect {
                Circle()
                    .stroke(Color.yellow.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .frame(width: diameter + 20, height: diameter + 20)
            }
            if isActive {
                Circle()
                    .fill(chordColor(node.name).opacity(0.30))
                    .frame(width: diameter + 28, height: diameter + 28)
            }
            Circle()
                .fill(chordColor(node.name))
                .frame(width: diameter, height: diameter)
                .shadow(color: readyToConnect  ? .yellow.opacity(0.9) :
                               isActive        ? .cyan.opacity(0.9)   :
                               isSelected      ? .white.opacity(0.6)  : .clear,
                        radius: readyToConnect ? 18 : isActive ? 16 : 10)
                .overlay(Circle()
                    .stroke(readyToConnect     ? Color.yellow :
                            editMode           ? Color.orange.opacity(0.7) :
                            isActive           ? Color.cyan :
                            isSelected         ? Color.white : Color.white.opacity(0.25),
                            lineWidth: (isActive || isSelected || editMode) ? 2.5 : 1.0))
                .opacity(isHighlighted ? 1.0 : 0.28)
            Text(node.name)
                .font(.system(size: labelSize(node.name), weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center).lineLimit(2)
                .frame(width: diameter - 8)
                .opacity(isHighlighted ? 1.0 : 0.45)
            // Hinweis: Knoten ausgewählt → tippen zum Verbinden
            if readyToConnect {
                Text("→ verbinden")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.yellow.opacity(0.9))
                    .offset(y: diameter / 2 + 12)
            }
        }
    }
    private func labelSize(_ name: String) -> CGFloat {
        let base: CGFloat = name.count <= 3 ? 18 : name.count <= 5 ? 15 : 13
        return base * scale
    }
}

// MARK: – Akkord-Farbe

func chordColor(_ name: String) -> Color {
    if name.contains("maj7") || name.contains("maj9") { return Color(hue: 0.13, saturation: 0.75, brightness: 0.85) }
    if name.contains("m7b5")                          { return Color(hue: 0.75, saturation: 0.70, brightness: 0.75) }
    if name.contains("dim7")                          { return Color(hue: 0.85, saturation: 0.65, brightness: 0.60) }
    if name.contains("m9")  || name.contains("m7")   { return Color(hue: 0.60, saturation: 0.65, brightness: 0.80) }
    if name.contains("sus4")                          { return Color(hue: 0.45, saturation: 0.55, brightness: 0.80) }
    if name.hasSuffix("7")  || name.contains("9")    { return Color(hue: 0.05, saturation: 0.75, brightness: 0.90) }
    if name.hasSuffix("6")                            { return Color(hue: 0.30, saturation: 0.55, brightness: 0.80) }
    return Color(hue: 0.55, saturation: 0.40, brightness: 0.75)
}

// MARK: – Hilfserweiterungen

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private extension View {
    @ViewBuilder
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}
