import SwiftUI
import AppKit
import Combine
import HarmonyShared

// MARK: – AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        print("✅ App aktiviert – Tastatur bereit")
    }
}

// MARK: – RuntimeWorldInfo
//
// Beschreibt, welche Welt gerade tatsächlich aktiv ist (Phase 3.9.2 – Modus-Wahrheit).
// Explore ist der Standard-Spielmodus (ChordNetwork aus NetworkParser).
// mapPreview ist HarmonyWeb — seit Runde 023 / E-03 ein normal über AppSettings
// wählbarer Produktpfad, nicht mehr nur der Entwickler-/Prüfmodus über
// --map-preview/HE3D_MAP_PREVIEW (der Flag-Pfad bleibt als vorrangiger
// Developer-/Kompatibilitäts-Override erhalten). Der Enum-Fallname `mapPreview`
// bleibt unverändert, um OutputCoordinator.swift (außerhalb des E-03-Scopes)
// nicht anfassen zu müssen — nur die Bedeutung/Sichtbarkeit ändert sich.
// Kein Live-Umschalter in dieser Runde – kind steht für die gesamte App-Laufzeit fest.

struct RuntimeWorldInfo {
    enum Kind: Equatable {
        case explore
        case mapPreview
    }

    let kind:        Kind
    let displayName: String
    let detail:      String
    let emoji:       String
    /// Aktiver Layer bei HarmonyWeb (Runde 023 / E-03) — nil bei Explore.
    let layer:       String?

    init(kind: Kind, displayName: String, detail: String, emoji: String, layer: String? = nil) {
        self.kind        = kind
        self.displayName = displayName
        self.detail      = detail
        self.emoji       = emoji
        self.layer       = layer
    }
}

// MARK: – AppModel
//
// Zentraler Besitzer aller langlebigen Objekte.
// Erstellt Scene, FlightController, TargetingModel und OutputCoordinator.
// OutputCoordinator ist private – ContentView hat keinen Zugriff darauf.
// ContentView erhält ausschließlich scene, flightController und targetingModel.

final class AppModel: ObservableObject {

    let scene:              HarmonyScene
    let flightController:   FlightController
    let targetingModel:     TargetingOverlayModel
    let worldInfo:          RuntimeWorldInfo         // 3.9.2: welche Welt ist tatsächlich aktiv

    // Privat: ContentView sieht weder OutputCoordinator noch AudioOutput.
    private let outputCoordinator: OutputCoordinator

    // MIDI-Eingang (Runde 073 / W-04). Oeffentlich, weil die Quellenauswahl in
    // den Einstellungen die Geraeteliste und den Verbindungszustand anzeigt —
    // ContentView bekommt damit den Eingang, aber weiterhin keinen AudioOutput.
    let midiInput: MIDIInputManager

    // Combine-Subscription: AppSettings.midiInput → MIDIInputManager.
    private var midiInputCancellable: AnyCancellable? = nil

    // Drossel zwischen CC-Eingang und Klangparametern (Runde 074 / W-05).
    // nil, wenn kein interner Synth aktiv ist — bei outputMode == .midi gibt
    // es keine Makros zu bewegen. Siehe MIDIMacroMapping.swift.
    private var macroCoalescer: MIDIMacroCoalescer? = nil

    // v1-Netzwerkmodell: GraphEngine gehalten, RuntimeHarmonik als strukturierte Mittelschicht.
    // RuntimeHarmonik empfängt Akkord-Events, pflegt Kontext und liefert HarmonicDecision.
    // Magnetismus und Identitätswechsel folgen in Phase 4.3.
    private let graphEngine:    HarmonyGraphEngine?
    private let runtimeHarmonik: RuntimeHarmonik?

    // Combine-Subscription: AppSettings.audio → AudioEngine (live, 30 ms debounce).
    // nil wenn outputMode == .midi (kein AudioEngine aktiv).
    private var audioConfigCancellable: AnyCancellable? = nil

    // MARK: – Audio-Output-Auswahl
    //
    // Einzige Stelle im gesamten Projekt, an der die konkrete AudioOutput-Implementierung
    // gewählt wird. Entscheidung basiert auf AppSettings.shared.audio.outputMode.
    // Wirkt beim App-Start; kein Runtime-Switching.
    //
    //   .midi          → MIDIManager.shared   (CoreMIDI Virtual Output, Standard)
    //   .internalAudio → AudioEngine()        (AVAudioUnitSampler, macOS-System-DLS)
    //
    private static func makeAudioOutput() -> any AudioOutput {
        switch AppSettings.shared.audio.outputMode {
        case .midi:
            return MIDIManager.shared

        case .internalAudio:
            // AudioEngine darf nicht auf AppSettings zugreifen.
            // App Layer wendet persistierte Konfiguration pro Kanal an.
            // setupGraph() initialisiert intern bereits mit ChannelFXConfig-Defaults;
            // diese Aufrufe überschreiben mit den persistierten (oder identischen) Werten.
            let ae  = AudioEngine()
            let cfg = AppSettings.shared.audio
            // Stimmtyp vor den Kanalkonfigurationen setzen: er reist als Feld
            // im SynthParams-Snapshot mit, den die vier Aufrufe unten senden
            // (W-03b1).
            ae.applyVoiceEngine(cfg.voiceEngine)
            ae.applyEffectConfigChord(cfg.chord)
            ae.applyEffectConfigBass(cfg.bass)
            ae.applyEffectConfigMelody(cfg.melody)
            ae.applyEffectConfigChordTone(cfg.chordTone)
            return ae
        }
    }

    /// Ermittelt aus Launch Arguments / Environment, ob der Developer-/
    /// Kompatibilitäts-Override für HarmonyWeb gesetzt ist (3.9.2 – Modus-
    /// Wahrheit; seit Runde 023 / E-03 nicht mehr der einzige Weg zu
    /// HarmonyWeb, siehe `effectiveHarmonyWebRequest()`).
    private static func mapPreviewRequest() -> (requested: Bool, mapName: String) {
        let args = CommandLine.arguments
        let env  = ProcessInfo.processInfo.environment
        let requested = args.contains("--map-preview") || env["HE3D_MAP_PREVIEW"] == "1"
        let mapName   = env["HE3D_MAP_NAME"] ?? "harmony-web-c-diatonic"
        return (requested, mapName)
    }

    /// Effektive HarmonyWeb-Anforderung für diesen Start (Runde 023 / E-03,
    /// um externe importierte Maps erweitert in Runde 040 / V-01). Vorrang:
    /// `--map-preview`/`HE3D_MAP_PREVIEW` (Developer-Override, Layer bleibt
    /// dabei bewusst hart `"functional"` wie bisher — unverändertes
    /// Verhalten für den bestehenden Flag-Pfad, lädt immer aus dem Bundle).
    /// Sonst: persistierte `AppSettings.worldSelection`, nur wenn
    /// `mode == .harmonyWeb` — Default bleibt Explore (Stephan-Entscheidung
    /// Option A). Innerhalb von HarmonyWeb hat `externalMapFileName`
    /// (gesetzt) Vorrang vor `harmonyWebMap` (Bundle-Katalog) — `isExternal`
    /// sagt dem Aufrufer, über welche Quelle `mapName` aufzulösen ist
    /// (`RuntimeMapImportStore.load(fileName:)` statt
    /// `HarmonyMapLoader.load(named:)`).
    ///
    /// `envOverride`/`selection` sind bewusst injizierbare Parameter mit
    /// Default aus den echten globalen Quellen (`mapPreviewRequest()`/
    /// `AppSettings.shared.worldSelection`) — reine, ohne globalen Zustand
    /// testbare Entscheidungslogik, ohne `AppSettings.shared` in Tests
    /// mutieren zu müssen (Debounce-Save würde sonst reale UserDefaults
    /// verändern). Internal statt private, damit `@testable import` zugreifen
    /// kann.
    static func effectiveHarmonyWebRequest(
        envOverride: (requested: Bool, mapName: String) = AppModel.mapPreviewRequest(),
        selection:   RuntimeWorldSelection = AppSettings.shared.worldSelection
    ) -> (requested: Bool, mapName: String, layer: String, isExternal: Bool) {
        if envOverride.requested {
            return (true, envOverride.mapName, "functional", false)
        }
        guard selection.mode == .harmonyWeb else {
            return (false, "", "", false)
        }
        if let externalFileName = selection.externalMapFileName {
            return (true, externalFileName, selection.harmonyWebLayer, true)
        }
        return (true, selection.harmonyWebMap.rawValue, selection.harmonyWebLayer, false)
    }

    init() {
        var _worldSession: WorldSession? = nil
        let s: HarmonyScene
        let worldInfo: RuntimeWorldInfo

        // Aktuell aktives NetworkParser-Netz – Basis für den Explore-Default
        // und den Fallback, falls ein angeforderter Map-Preview fehlschlägt.
        func exploreNetworkAndInfo() -> (ChordNetwork, RuntimeWorldInfo) {
            let idx = AppSettings.shared.harmony.networkIndex
            let def = NetworkParser.definitions[max(0, min(idx, NetworkParser.definitions.count - 1))]
            return (
                NetworkParser.load(index: idx),
                RuntimeWorldInfo(kind: .explore, displayName: def.name, detail: def.description, emoji: def.emoji)
            )
        }

        func buildExplore() -> (HarmonyScene, RuntimeWorldInfo) {
            let (network, info) = exploreNetworkAndInfo()
            return (HarmonyScene(network: network), info)
        }

        // Effektive HarmonyWeb-Anforderung (Runde 023 / E-03, um externe
        // importierte Maps erweitert in Runde 040 / V-01): Developer-Override
        // (--map-preview/HE3D_MAP_PREVIEW) hat Vorrang, sonst persistierte
        // AppSettings.worldSelection. WorldSession, GraphEngine und die 3D-Szene
        // sehen in jedem Fall denselben Layer (Phase 3.9.3b/c, seit Runde 020 / E-01
        // über WorldSession statt separat konstruierter Kopien). `isExternal`
        // wählt die Ladequelle: `RuntimeMapImportStore` (Application-Support-
        // Importordner) statt `HarmonyMapLoader` (Bundle) — beide liefern eine
        // bereits decodierte + validierte `HarmonyMap`, der restliche Pfad
        // (WorldSession/HarmonyScene) ist identisch und bleibt
        // `toChordNetwork`-frei.
        let request = AppModel.effectiveHarmonyWebRequest()
        let loadedHarmonyMap: HarmonyMap? = request.requested
            ? (request.isExternal
                ? RuntimeMapImportStore.load(fileName: request.mapName)
                : HarmonyMapLoader.load(named: request.mapName))
            : nil
        if request.requested, let harmonyMap = loadedHarmonyMap {
            do {
                // WorldSession (Runde 020 / E-01): einzige Ownership-Stelle für Map,
                // aktiven Layer, GraphEngine und RuntimeHarmonik im HarmonyWeb-Pfad.
                // HarmonyScene liest Map/Layer/allChords/allEdges direkt aus der Session
                // — HarmonyMapLoader.toChordNetwork ist hier nicht mehr die operative
                // Scene-Datenquelle (bleibt Legacy-/Kompatibilitätsrand für andere Zwecke).
                let session = try WorldSession(map: harmonyMap, activeLayer: request.layer)
                _worldSession = session
                worldInfo = RuntimeWorldInfo(
                    kind:        .mapPreview,
                    displayName: harmonyMap.id,
                    detail:      "\(harmonyMap.nodes.count) Nodes · \(harmonyMap.edges.count) Edges"
                        + (request.isExternal ? " (importiert)" : ""),
                    emoji:       request.isExternal ? "📂" : "🧪",
                    layer:       request.layer
                )
                s = HarmonyScene(worldSession: session)
                for warning in session.warnings {
                    print("ℹ️  WorldSession [\(harmonyMap.id)]: \(warning)")
                }

                // MARK: – [HarmonyTest] Observational Logging (v1 Network Model)
                // Rein beobachtend – kein Einfluss auf Laufzeitverhalten. Nur im HarmonyWeb-Pfad,
                // damit der Explore-Default nicht mit Testausgaben geflutet wird.
                // Seed 12345 → deterministisch reproduzierbar. Kein AppSettings-Zugriff.
                // Eigene, separate testEngine (nicht session.graphEngine) — rein beobachtend,
                // soll den operativen Verlauf der Session-GraphEngine nicht beeinflussen.
                print("[HarmonyTest] ✅ HarmonyWeb aktiv: \(harmonyMap.id) (\(harmonyMap.nodes.count) Nodes, \(harmonyMap.edges.count) Edges), Layer '\(request.layer)'")
                print("[HarmonyTest] Nodes: \(harmonyMap.nodes.map { $0.id })")

                let testEngine = HarmonyGraphEngine(map: harmonyMap, initialLayer: request.layer, seed: 12345)

                // Transition- und Neighbor-Abfrage für G7 (nur aussagekräftig, wenn die
                // gewählte Map/der gewählte Layer einen Node "G7" enthält — rein
                // beobachtend, kein Einfluss auf Laufzeitverhalten bei Nichttreffer).
                let trans = testEngine.transitions(from: "G7")
                print("[HarmonyTest] transitions(from: \"G7\"): \(trans.map { "\($0.id) → \($0.target)" })")

                let nbrs = testEngine.neighbors(of: "G7")
                print("[HarmonyTest] neighbors(of: \"G7\"): \(nbrs.map { $0.id })")

                // weightedChoice ohne Kontext (kein Verlauf)
                let choiceRaw = testEngine.weightedChoice(from: "G7")
                print("[HarmonyTest] weightedChoice(from: \"G7\") ohne Kontext: \(choiceRaw?.id ?? "nil")")

                // ii-V-Kontext: Dm7 → G7 im Verlauf → ii-V-Boost aktiv
                testEngine.recordVisit("Dm7")
                testEngine.recordVisit("G7")
                let choiceBoost = testEngine.weightedChoice(from: "G7")
                print("[HarmonyTest] weightedChoice(from: \"G7\") nach recordVisit(Dm7→G7) [ii-V-Boost]: \(choiceBoost?.id ?? "nil")")
            } catch {
                print("[Mode] ⚠️ HarmonyWeb '\(request.mapName)' — WorldSession-Konstruktion fehlgeschlagen"
                    + " (\(error)) – Fallback auf Explore")
                (s, worldInfo) = buildExplore()
            }
        } else {
            if request.requested {
                print("[Mode] ⚠️ HarmonyWeb '\(request.mapName)' konnte nicht geladen werden – Fallback auf Explore")
            }
            (s, worldInfo) = buildExplore()
        }
        self.worldInfo = worldInfo
        let fc  = FlightController()
        let tm  = TargetingOverlayModel()

        // graphEngine/runtimeHarmonik kommen jetzt aus derselben WorldSession
        // (Runde 020 / E-01) statt separat konstruiert zu werden — nil wenn
        // JSON-Laden/WorldSession-Konstruktion fehlschlug bzw. Explore aktiv ist.
        let _graphEngine:     HarmonyGraphEngine? = _worldSession?.graphEngine
        let _runtimeHarmonik: RuntimeHarmonik?     = _worldSession?.runtimeHarmonik

        self.scene              = s
        self.flightController   = fc
        self.targetingModel     = tm
        self.graphEngine        = _graphEngine
        self.runtimeHarmonik    = _runtimeHarmonik

        // InputProvider-Verdrahtung: GamepadController als konkrete Eingabequelle.
        // FlightController kennt von hier an nur das Protokoll, nicht die Klasse.
        fc.inputProvider = GamepadController.shared

        // AudioOutput einmalig erzeugen und Referenz halten (für Combine-Subscription).
        let audioOut = AppModel.makeAudioOutput()

        let coordinator = OutputCoordinator(
            scene:            s,
            flightController: fc,
            output:           audioOut,
            config: {
                OutputConfig(
                    chordOctaveShift: AppSettings.shared.midi.chordOctaveShift,
                    chordVelocity:    Int(AppSettings.shared.midi.chordVelocity),
                    bassVelocity:     Int(AppSettings.shared.midi.bassVelocity)
                )
            }
        )

        // App-level state mutations: AppSettings-Zugriff bleibt im App Layer.
        coordinator.onBassToggle = {
            DispatchQueue.main.async { AppSettings.shared.midi.bassHoldMode.toggle() }
        }
        // Netzwerkwechsel per D-Pad wirkt nur im Explore-Modus – im Map Preview
        // ignoriert HarmonyScene den networkIndex ohnehin (jsonWebMode-Guard in
        // loadNetwork), aber ein stiller No-Op hier verhindert zusätzlich, dass
        // AppSettings.harmony.networkIndex sich unbemerkt weiterdreht.
        let worldInfoForCoordinator = worldInfo
        coordinator.onNetworkPrev = {
            guard worldInfoForCoordinator.kind == .explore else {
                print("[Mode] Netzwerkwechsel im Map-Preview-Modus ignoriert")
                return
            }
            DispatchQueue.main.async {
                let n = NetworkParser.definitions.count
                AppSettings.shared.harmony.networkIndex = (AppSettings.shared.harmony.networkIndex - 1 + n) % n
            }
        }
        coordinator.onNetworkNext = {
            guard worldInfoForCoordinator.kind == .explore else {
                print("[Mode] Netzwerkwechsel im Map-Preview-Modus ignoriert")
                return
            }
            DispatchQueue.main.async {
                let n = NetworkParser.definitions.count
                AppSettings.shared.harmony.networkIndex = (AppSettings.shared.harmony.networkIndex + 1) % n
            }
        }
        coordinator.onToggleHelp = {
            DispatchQueue.main.async { fc.showControlsOverlay.toggle() }
        }

        // RuntimeHarmonik-Hook: Akkord-Aktivierung → strukturierte Entscheidung → räumliches Ziel.
        // localChordNodes: SceneKit-freie Snapshot aller geladenen Akkord-Nodes mit
        // Spieler-Distanz. RuntimeHarmonik wählt daraus den nächstgelegenen Kandidaten.
        //
        // HarmonicDecision wird erzeugt und direkt an HarmonyScene.applyHarmonicDecision()
        // übergeben: strategy == .magnetismCandidate → currentMagnetNodeID gesetzt,
        //            strategy == .noCandidate / .noSuggestion → currentMagnetNodeID = nil.
        // magnetInfluence ist ein computed property (currentMagnetNodeID → chordAnchorPositions[id]
        // + currentMagnetProfile) und wird nie direkt geschrieben — siehe HarmonyScene.swift.
        //
        // Magnetismus-Stärke ist seit Phase 4.2a/4.2b nicht mehr konstant: MagnetProfile.Preset
        // (Kantenstärke) und RelationType-Feldklassifikation (Kantencharakter, HarmonicMagnetFieldKind)
        // modulieren gemeinsam mit scoreBoost die effektiven Rate-/Winkelgeschwindigkeits-Multiplikatoren,
        // siehe RuntimeHarmonik.process(). Seit Runde 021 / E-02 zusätzlich Range/Falloff/Intensity
        // über HarmonicMagnetConfig — der App-Layer baut den Value-Snapshot aus
        // AppSettings.harmonicMagnet, RuntimeHarmonik selbst liest AppSettings nie.
        if let rh = _runtimeHarmonik {
            // onGraphHook: feuert bei Akkord-Aktivierung (ereignisbasiert).
            coordinator.onGraphHook = { [weak rh, weak s] chordName in
                let hm = AppSettings.shared.harmonicMagnet
                let magnetConfig = HarmonicMagnetConfig(
                    isEnabled:  hm.isEnabled,
                    intensity:  Float(hm.intensity),
                    rangeScale: Float(hm.rangeScale)
                )
                guard let decision = rh?.process(
                    currentChord: chordName,
                    localNodes:   s?.localChordNodes ?? [],
                    magnetConfig: magnetConfig
                ) else { return }
                s?.applyHarmonicDecision(decision)
            }
        }

        self.outputCoordinator = coordinator

        // MIDI-Eingang (Runde 073 / W-04): derselbe AudioOutput wie fuer die
        // Szene — der Eingang ist bewusst nur ein weiterer AudioOutput-Aufrufer
        // und laeuft damit ueber dieselbe Serialisierungsgrenze
        // (AudioEngine.commandQueue). Der SPSC-Vertrag der NoteEventQueue
        // bleibt dadurch unveraendert; siehe MIDIInputRouting.swift.
        let input = MIDIInputManager(output: audioOut)
        self.midiInput = input
        input.start(config: AppSettings.shared.midiInput)

        // CC → Makro (Runde 074 / W-05). Der Beobachter-Haken der Registry
        // stammt aus W-04 und wird hier zum ersten Mal benutzt.
        //
        // Nur bei internem Synth: bei outputMode == .midi gibt es keine
        // Atmospheric Voice, deren Makros sich bewegen liessen. Die CCs werden
        // dann weiterhin in der Registry mitgeschrieben, bewegen aber nichts —
        // und sie werden ausdruecklich NICHT als MIDI-Thru weitergereicht, wie
        // schon in W-04.
        var coalescer: MIDIMacroCoalescer? = nil
        if let ae = audioOut as? AudioEngine {
            let made = MIDIMacroCoalescer(
                mapping: AppSettings.shared.midiInput.macroCCMapping
            ) { [weak ae] values in
                // Flush laeuft auf dem Main Thread (mainQueueScheduler) —
                // dieselbe Seite, von der auch applyEffectConfig* kommt.
                ae?.applyMacroValues(values)
            }
            coalescer = made
            self.macroCoalescer = made
            // Der Beobachter wird SYNCHRON auf dem CoreMIDI-Thread gerufen.
            // `handle` fasst dort nur `pending` an und plant ggf. einen Flush
            // ein; es beruehrt weder AudioEngine noch die NoteEventQueue.
            input.router.controlChanges.setObserver { [weak made] change in
                made?.handle(change)
            }
        }

        // Quellenauswahl und CC-Zuordnung live nachziehen. Ohne Debounce:
        // beides aendert sich per Klick, nicht per Schieberegler.
        midiInputCancellable = AppSettings.shared.$midiInput
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak input, weak coalescer] cfg in
                input?.apply(config: cfg)
                coalescer?.setMapping(cfg.macroCCMapping)
            }

        // Combine: AppSettings.audio → AudioEngine live anwenden.
        // Nur aktiv wenn outputMode == .internalAudio; andernfalls bleibt nil.
        // 30 ms debounce: Slider-Bewegungen werden gebündelt (kein AU-Parameterflut).
        if let ae = audioOut as? AudioEngine {
            audioConfigCancellable = AppSettings.shared.$audio
                .dropFirst()
                .debounce(for: .milliseconds(30), scheduler: DispatchQueue.main)
                .sink { [weak ae] cfg in
                    ae?.applyVoiceEngine(cfg.voiceEngine)
                    ae?.applyEffectConfigChord(cfg.chord)
                    ae?.applyEffectConfigBass(cfg.bass)
                    ae?.applyEffectConfigMelody(cfg.melody)
                    ae?.applyEffectConfigChordTone(cfg.chordTone)
                }
        }
    }

    /// All-Notes-Off – wird als Closure an ContentView übergeben,
    /// damit ContentView keinen direkten Zugriff auf MIDIManager benötigt.
    ///
    /// Extern gestartete Noten enden dabei mit, weil sie im selben AudioOutput
    /// liegen; die Buchführung des MIDI-Eingangs wird nur nachgezogen, damit
    /// keine Karteileiche zurückbleibt (Runde 073 / W-04).
    var stopAllAction: () -> Void {
        { [weak self] in
            self?.outputCoordinator.stopAll()
            self?.midiInput.forgetExternalNotesAfterGlobalPanic()
        }
    }
}

// MARK: – Entry Point

@main
struct HarmonyEngine3DApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model = AppModel()

    // Beobachtet denselben UserDefaults-Key wie AppSettings.language.
    // didSet in AppSettings schreibt sofort (kein Debounce) → @AppStorage aktualisiert
    // synchron → body re-rendert → neue Locale wird in den View-Baum injiziert.
    // SwiftUI Text()-Views mit LocalizedStringKey lösen automatisch in der richtigen
    // Sprache auf (macOS 13+).
    @AppStorage("he3d.ui.language") private var languageRaw: String = "de"

    var body: some Scene {
        WindowGroup("HarmonyEngine 3D") {
            ContentView(
                scene:              model.scene,
                flightController:   model.flightController,
                targetingModel:     model.targetingModel,
                stopAllAction:      model.stopAllAction,
                worldInfo:          model.worldInfo,
                midiInput:          model.midiInput
            )
            .frame(minWidth: 1024, minHeight: 768)
            .environment(\.locale, Locale(identifier: languageRaw))
        }
        .defaultSize(width: 1280, height: 800)
    }
}
