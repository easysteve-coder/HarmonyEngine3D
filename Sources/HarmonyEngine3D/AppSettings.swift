import Foundation
import Combine
import CoreGraphics

// MARK: – Sub-Config-Strukturen
//
// Jede Komponente greift nur noch auf den Sub-Config-Block zu,
// den sie tatsächlich benötigt. Keine flachen Einzelproperties mehr.

// ── Flugphysik + Navigation ───────────────────────────────────────────────

struct FlightConfig {
    var maxSpeed:               Double = 144
    var thrustForce:            Double = 165
    var invertPitch:            Bool   = false
    var gamepadYawSensitivity:  Double = 1.2
    var gamepadPitchSensitivity: Double = 1.5
    var autopilotEnabled:       Bool   = false
    var autopilotSpeed:         Double = 0.55
    var magnetStrength:         Double = 1.7     // 0 … 3.0
    var magnetRadius:           Double = 155.0   // Meter
}

// ── MIDI-Output, Sensoren, Velocities ────────────────────────────────────

struct MIDIConfig {
    var chordVelocity:    Double = 88
    var bassVelocity:     Double = 110  // erhöht von 80: Unison-gainScale (1/sqrt(2)) reduziert Amplitude; 110 kompensiert
    var melodyVelMax:     Double = 88
    var melodyTempo:      Double = 1.0
    var chordOctaveShift: Int    = 0
    var bassOctaveShift:  Int    = 0
    var bassHoldMode:     Bool   = false
    // Sensoren (Gyro + Touchpad → CC)
    var sensorEnabled:    Bool   = false
    var gyroEnabled:      Bool   = true
    var gyroRollCC:       Int    = 74
    var gyroPitchCC:      Int    = 1
    var gyroSensitivity:  Double = 1.0
    var touchpadEnabled:  Bool   = true
    var touchpadXCC:      Int    = 11
    var touchpadYCC:      Int    = 71
    var rotationEnabled:  Bool   = false
    var rotationCC:       Int    = 73
    var sensorMidiChannel: Int   = 4
}

// ── Darstellung (SceneKit-Renderer) ──────────────────────────────────────

struct RenderConfig {
    var chordRadius:          Double = 31.0
    var portalRadius:         Double = 64.0
    var cloudRadius:          Double = 44.0
    var highQualityRendering: Bool   = true
    var chordColorMode:       Int    = 1
    var chordVisualMode:      Int    = 0
    var showNetworkEdges:     Bool   = false
    // Easter Theme: ersetzt alle Chord-/Portal-/Cloud-Visuals durch Ostereier, Möhren und Osterglocken.
    // Überschreibt chordVisualMode vollständig. Logik, Hitboxen und Positionen bleiben unverändert.
    var easterTheme:          Bool   = false
    // Morphing-Intensität (Phase 3.9.4c) — reiner Render-Multiplikator für die
    // Nachbarschafts-Impulse aus Runde 010 (HarmonyScene.updateHarmonicImpulses).
    // 0.0 = keine Morphing-Auslenkung. Wirkt ausschließlich auf chordRenderOffsets,
    // nie auf Trigger/Distanz/Anker. Die Kandidaten-Glow-Betonung aus Runde 011
    // (chordCandidateGlow) ist bewusst NICHT an diesen Wert gekoppelt — sie ist
    // keine Positionsverschiebung, siehe HarmonyScene.applyCandidateGlow.
    var morphingIntensity:    Double = 0.0   // 0.0 … 1.0
}

// ── Harmonik + Weltgenerierung ────────────────────────────────────────────

struct HarmonyConfig {
    var chordTrigger:   Double = 100.0
    var portalTrigger:  Double = 100.0
    var cloudTrigger:   Double = 100.0
    var chordDensity:   Double = 70
    var portalDensity:  Double = 30
    var cloudDensity:   Double = 30
    var keyCenter:      Int    = -1
    var voiceLeadingEnabled: Bool = true
    var energyLevel:    Double = 0.35
    var networkIndex:   Int    = 0
    // Akkord-Typen
    var enableMaj7:  Bool = true
    var enableM7:    Bool = true
    var enableDom7:  Bool = true
    var enableM7b5:  Bool = true
    var enableDim7:  Bool = false
    var enableMaj9:  Bool = true
    var enable9:     Bool = true
    var enableSus4:  Bool = false
    var enable6:     Bool = false
    var enableM9:    Bool = false
}

// ── Runtime-Weltwahl (Runde 023 / E-03) ───────────────────────────────────
//
// Persistierter Startmodus (Explore/HarmonyWeb) + HarmonyWeb-Map/-Layer.
// Getrennt von HarmonyConfig.networkIndex (bleibt reine Explore-
// Netzwerkauswahl). Siehe RuntimeWorldSelection.swift für die Werttypen.
// AppModel.init() liest diesen Block; der bestehende --map-preview/
// HE3D_MAP_PREVIEW-Override bleibt vorrangiger Developer-Pfad.

// ── Harmonischer Magnet (Runde 021 / E-02) ────────────────────────────────
//
// Getrennt von FlightConfig.magnetStrength/magnetRadius (proximity-basierter
// Magnet, unverändert). RuntimeHarmonik liest diese Werte nie direkt — der
// App-Layer baut daraus einen HarmonicMagnetConfig-Value-Snapshot und
// übergibt ihn pro RuntimeHarmonik.process()-Aufruf (siehe
// HarmonyEngine3DApp.onGraphHook). intensity/rangeScale entsprechen
// HarmonicMagnetConfig, werden aber erst dort geklammert — hier nur die
// UI-/Persistenz-Rohwerte.

struct HarmonicMagnetSettings {
    var isEnabled:  Bool   = true
    var intensity:  Double = 1.0    // 0…1, siehe HarmonicMagnetConfig
    var rangeScale: Double = 1.0    // 0.25…4.0, siehe HarmonicMagnetConfig
}

// ── Audio Engine ─────────────────────────────────────────────────────────

/// Persistierter Output-Modus. Wirkt ab nächstem App-Start.
/// Auswahl findet ausschließlich in AppModel.makeAudioOutput() statt.
enum OutputMode: Int {
    case midi          = 0   // CoreMIDI Virtual Output (Standard)
    case internalAudio = 1   // AVAudioUnitSampler, macOS-lokal
}

/// Effekt- und Lautstärkekonfiguration eines Audio-Kanals.
///
/// Delays: drei parallele Taps (1=früh, 2=mittel, 3=diffus).
///   delayNTime:     Sekunden, 0.001 … 2.0 (AVAudioUnitDelay-Limit)
///   delayNFeedback: 0…1 → feedback 0…100 %
///   delayNMix:      0…1 → delay1/2/3SendX.outputVolume (Send-Pegel vor dem Delay)
///   delayNPan:      -1…+1 → delay1/2/3SendX.pan (Stereoposition vor dem Delay)
///
/// Reverb:
///   reverbPreset: AVAudioUnitReverbPreset.rawValue
///     0=smallRoom 1=mediumRoom 2=largeRoom 3=mediumHall 4=largeHall
///     5=plate 6=mediumChamber 7=largeChamber 8=cathedral 9=largeRoom2
///   reverbMix: 0…1 → wetDryMix 0…100
struct ChannelFXConfig {
    // Delay Tap 1
    var delay1Time:        Float
    var delay1Feedback:    Float
    var delay1Mix:         Float
    var delay1Pan:         Float
    // Delay Tap 2
    var delay2Time:        Float
    var delay2Feedback:    Float
    var delay2Mix:         Float
    var delay2Pan:         Float
    // Delay Tap 3
    var delay3Time:        Float
    var delay3Feedback:    Float
    var delay3Mix:         Float
    var delay3Pan:         Float
    // Reverb
    var reverbPreset:      Int
    var reverbMix:         Float
    // Volume
    var channelVolume:     Float   // 0…1 → gainX.outputVolume
    // ADSR (vollständig steuerbar, Mapping in AudioEngine.applyEffectConfigX)
    var attack:            Float   // 0…1 normiert → attackMs = attack × 2000 ms
    var decay:             Float   // 0.001…2.0 s → decayMs in SynthParams
    var sustain:           Float   // 0…1 → SynthParams.sustain
    var release:           Float   // 0.1…4.0 s → releaseMs in SynthParams
    // Filter (Biquad-Tiefpassfilter in AudioCoreVoice, seit S-02b)
    var filterCutoff:      Float   // 0…1 normiert → logarithmisch 20…20.000 Hz
    var filterResonance:   Float   // 0…1 → Q 0.5…20
    // Wellenform (Waveform.rawValue)
    var waveform:          Waveform  // .sine / .saw / .square / .triangle
    // Dry-Pan (Mixer-Ebene — wirkt auf gainX.pan in AudioEngine)
    var pan:               Float   // -1.0 (links) … 0.0 (Mitte) … +1.0 (rechts)
    // Unison (Synth-Ebene — mehrere verstimmte Stimmen pro NoteOn)
    var unisonVoices:      Int     // 1 = kein Unison, 2–3 = breiterer Klang
    var unisonDetune:      Float   // Verstimmung der äußersten Stimmen in Cent (0…20)
    var unisonSpread:      Float   // Stereo-Verteilung der Stimmen (0 = Mono, 1 = volle Breite)
}

extension ChannelFXConfig {

    /// Chord – Raum, verbindend. largeHall. Sinus-Standard.
    static let chordDefaults = ChannelFXConfig(
        delay1Time: 0.07, delay1Feedback: 0.30, delay1Mix: 0.20, delay1Pan: -0.50,
        delay2Time: 0.09, delay2Feedback: 0.35, delay2Mix: 0.25, delay2Pan: +0.50,
        delay3Time: 0.14, delay3Feedback: 0.20, delay3Mix: 0.15, delay3Pan:  0.00,
        reverbPreset: 4,  reverbMix: 0.35,
        channelVolume: 0.85,
        attack: 0.02, decay: 0.10, sustain: 0.70, release: 2.0,
        filterCutoff: 1.0, filterResonance: 0.0, waveform: .sine,
        pan: 0.0,
        unisonVoices: 1, unisonDetune: 0.0, unisonSpread: 0.0
    )

    /// Bass – Fundament, trocken, stabil. mediumHall.
    /// Unison: 2 Stimmen, ±8 Cent, Spread 0.25 — fetterer Klang ohne instabiles Low-End.
    /// WICHTIG: Spread bewusst moderat halten (≤ 0.35). Zu breiter Bass destabilisiert den Mix.
    static let bassDefaults = ChannelFXConfig(
        delay1Time: 0.03, delay1Feedback: 0.10, delay1Mix: 0.05, delay1Pan: -0.15,
        delay2Time: 0.04, delay2Feedback: 0.15, delay2Mix: 0.05, delay2Pan: +0.15,
        delay3Time: 0.07, delay3Feedback: 0.08, delay3Mix: 0.03, delay3Pan:  0.00,
        reverbPreset: 3,  reverbMix: 0.15,
        channelVolume: 0.80,
        attack: 0.005, decay: 0.08, sustain: 0.65, release: 2.5,
        filterCutoff: 1.0, filterResonance: 0.0, waveform: .sine,
        pan: 0.0,           // Bass sollte typischerweise zentriert bleiben
        unisonVoices: 2, unisonDetune: 8.0, unisonSpread: 0.25
    )

    /// Melody – groß, schwebend, hero. Cathedral.
    static let melodyDefaults = ChannelFXConfig(
        delay1Time: 0.12, delay1Feedback: 0.45, delay1Mix: 0.30, delay1Pan: -0.30,
        delay2Time: 0.16, delay2Feedback: 0.55, delay2Mix: 0.35, delay2Pan: +0.30,
        delay3Time: 0.25, delay3Feedback: 0.35, delay3Mix: 0.20, delay3Pan:  0.00,
        reverbPreset: 8,  reverbMix: 0.55,
        channelVolume: 0.90,
        attack: 0.05, decay: 0.12, sustain: 0.60, release: 2.5,
        filterCutoff: 1.0, filterResonance: 0.0, waveform: .sine,
        pan: 0.0,
        unisonVoices: 1, unisonDetune: 0.0, unisonSpread: 0.0
    )

    /// Chord-Tones (CH3 / Linker Stick) – kurz, direkt, perkussiv. mediumHall.
    static let chordToneDefaults = ChannelFXConfig(
        delay1Time: 0.05, delay1Feedback: 0.20, delay1Mix: 0.12, delay1Pan: -0.40,
        delay2Time: 0.08, delay2Feedback: 0.28, delay2Mix: 0.15, delay2Pan: +0.40,
        delay3Time: 0.12, delay3Feedback: 0.15, delay3Mix: 0.08, delay3Pan:  0.00,
        reverbPreset: 3,  reverbMix: 0.25,
        channelVolume: 0.80,
        attack: 0.005, decay: 0.05, sustain: 0.50, release: 1.5,
        filterCutoff: 1.0, filterResonance: 0.0, waveform: .sine,
        pan: 0.0,
        unisonVoices: 1, unisonDetune: 0.0, unisonSpread: 0.0
    )
}

// Synthesized Equatable: alle Felder sind primitive Typen (Int, Float) plus
// Waveform (UInt8-Enum, Equatable). Ermöglicht guard cfg != lastXCfg-Caches in AudioEngine.
extension ChannelFXConfig: Equatable {}

struct AudioConfig {
    var outputMode:    OutputMode = .midi
    // Stimmtyp des internen Synths (W-03b1). Global, nicht pro Kanal: es ist
    // ein Instrument mit vier Kanaelen, kein Rack aus vier Instrumenten.
    //
    // Default `.atmospheric` seit W-03b2 (Stephan-Entscheidung 2026-08-02):
    // die Atmospheric Voice ist die beim Start aktive Stimme. Der
    // Legacy-Pfad bleibt ueber genau diese Einstellung waehlbar und klingt
    // dann unveraendert.
    //
    // Diese Zeile ist der Produkt-Default. `SynthParams.voiceEngine` traegt
    // bewusst weiterhin `.legacy` — das ist der neutrale Vorkonfigurations-
    // wert eines Kanal-Snapshots, kein Produkt-Default (Begruendung dort).
    var voiceEngine:   SynthVoiceEngine = .atmospheric
    var samplerEnabled: Bool  = true
    var synthEnabled:   Bool  = true
    var masterVolume:   Float = 0.85
    // Kanalgetrennte Effektkonfiguration – alle vier Kanäle unabhängig
    var chord:      ChannelFXConfig = .chordDefaults
    var bass:       ChannelFXConfig = .bassDefaults
    var melody:     ChannelFXConfig = .melodyDefaults
    var chordTone:  ChannelFXConfig = .chordToneDefaults   // CH3 Linker Stick
}

// MARK: – AppSettings
//
// Singleton. Hält ausschließlich die fünf Sub-Configs als @Published Properties.
// Persistenz: UserDefaults, Präfix "he3d." – alle Keys unverändert.
// Debounced Auto-Save: 500 ms nach der letzten Änderung.
//
// UI-Zustand (showSettingsPanel, showCockpitPanel, showControlsOverlay)
// wurde in FlightController verlagert.

final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    private static let ud = UserDefaults.standard
    private var saveCancellable: AnyCancellable?

    @Published var flight         = FlightConfig()
    @Published var midi           = MIDIConfig()
    @Published var render         = RenderConfig()
    @Published var harmony        = HarmonyConfig()
    @Published var harmonicMagnet = HarmonicMagnetSettings()
    @Published var worldSelection = RuntimeWorldSelection()
    @Published var audio          = AudioConfig()
    // MIDI-Eingang (Runde 073 / W-04) — bewusst getrennt von `midi` oben:
    // `MIDIConfig` beschreibt ausschliesslich den AUSGANG (Velocities,
    // Oktavlagen, Sensor-CCs). Der Eingang hat eine eigene Lebensdauer
    // (Geraete kommen und gehen) und eine eigene Auswahlsemantik.
    @Published var midiInput      = MIDIInputConfig()

    // Anzeigesprache – sofort in UserDefaults geschrieben (didSet), damit
    // HarmonyEngine3DApp via @AppStorage die neue Locale ohne Debounce erhält.
    @Published var language: AppLanguage = .german {
        didSet { Self.ud.set(language.rawValue, forKey: K.language) }
    }

    private init() {
        load()
        saveCancellable = objectWillChange
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.save() }
    }

    // MARK: – UserDefaults Keys (unverändert gegenüber vorheriger Version)

    private enum K {
        // Flight
        static let maxSpeed     = "he3d.maxSpeed";    static let thrustForce  = "he3d.thrustForce"
        static let invertPitch  = "he3d.invertPitch"
        static let gamepadYaw   = "he3d.gamepadYaw";  static let gamepadPitch = "he3d.gamepadPitch"
        static let autopilot    = "he3d.autopilot";   static let autopilotSpd = "he3d.autopilotSpd"
        static let magnetStr    = "he3d.magnetStr";   static let magnetRad    = "he3d.magnetRad"
        // MIDI
        static let chordVel     = "he3d.chordVel";    static let bassVel      = "he3d.bassVel"
        static let melodyVel    = "he3d.melodyVel";   static let melodyTempo  = "he3d.melodyTempo"
        static let chordOct     = "he3d.chordOct";    static let bassOct      = "he3d.bassOct"
        static let bassHold     = "he3d.bassHold"
        static let sensorEnabled  = "he3d.sensorEnabled"
        static let gyroEnabled    = "he3d.gyroEnabled"; static let gyroRollCC   = "he3d.gyroRollCC"
        static let gyroPitchCC    = "he3d.gyroPitchCC"; static let gyroSens     = "he3d.gyroSens"
        static let touchpadEnabled = "he3d.touchpadEnabled"
        static let touchpadXCC    = "he3d.touchpadXCC"; static let touchpadYCC  = "he3d.touchpadYCC"
        static let rotEnabled     = "he3d.rotEnabled";  static let rotCC        = "he3d.rotCC"
        static let sensorCh       = "he3d.sensorCh"
        // Sprache
        static let language     = "he3d.ui.language"
        // Render
        static let chordRadius  = "he3d.chordRadius";  static let portalRadius = "he3d.portalRadius"
        static let cloudRadius  = "he3d.cloudRadius"
        static let hqRender     = "he3d.hqRender"
        static let colorMode    = "he3d.colorMode";    static let visualMode   = "he3d.visualMode"
        static let netEdges     = "he3d.netEdges";     static let easterTheme  = "he3d.easterTheme"
        static let morphIntens  = "he3d.morphIntensity"
        // Harmony
        static let chordTrigger = "he3d.chordTrigger"; static let portalTrigger = "he3d.portalTrigger"
        static let cloudTrigger = "he3d.cloudTrigger"
        static let chordDensity = "he3d.chordDensity"; static let portalDensity = "he3d.portalDensity"
        static let cloudDensity = "he3d.cloudDensity"
        static let keyCenter    = "he3d.keyCenter"
        static let voiceLead    = "he3d.voiceLead"
        static let energy       = "he3d.energy"
        static let netIndex     = "he3d.netIndex"
        // Harmonischer Magnet (Runde 021 / E-02) — getrennt von magnetStr/magnetRad oben
        static let harmMagnetEnabled     = "he3d.harmonicMagnet.enabled"
        static let harmMagnetIntensity   = "he3d.harmonicMagnet.intensity"
        static let harmMagnetRangeScale  = "he3d.harmonicMagnet.rangeScale"
        // Runtime-Weltwahl (Runde 023 / E-03) — getrennt von netIndex oben (Explore-only)
        static let worldMode          = "he3d.world.mode"
        static let worldHarmonyWebMap = "he3d.world.harmonyWebMap"
        static let worldHarmonyWebLayer = "he3d.world.harmonyWebLayer"
        // Runde 040 / V-01: leerer String == kein externes Map-Override
        // (Optional<String> hat kein natives UserDefaults-Pendant).
        static let worldExternalMapFileName = "he3d.world.externalMapFileName"
        // Audio – Output-Modus
        static let outputMode = "he3d.outputMode"
        // Audio – Stimmtyp des internen Synths (W-03b1)
        static let voiceEngine = "he3d.audio.voiceEngine"
        // MIDI-Eingang (Runde 073 / W-04). uniqueID 0 == keine externe Quelle
        // gewaehlt (kMIDIInvalidUniqueID ist 0, Optional<Int32> hat kein
        // natives UserDefaults-Pendant — gleiches Muster wie
        // worldExternalMapFileName oben).
        static let midiInEnabled    = "he3d.midiInput.enabled"
        static let midiInSourceID   = "he3d.midiInput.sourceUniqueID"
        static let midiInSourceName = "he3d.midiInput.sourceName"
        // CC -> Performance-Makro (Runde 074 / W-05). -1 == nicht zugeordnet.
        static let macroCCMotion = "he3d.midiInput.macroCC.motion"
        static let macroCCColor  = "he3d.midiInput.macroCC.color"
        static let macroCCSpace  = "he3d.midiInput.macroCC.space"
        static let macroCCFocus  = "he3d.midiInput.macroCC.focus"
        // Audio – ChannelFXConfig: Keys werden in load/save via Prefix-Interpolation gebildet.
        // Schema: "he3d.audio.[chord|bass|melody].[prog|bankMSB|bankLSB|
        //          d1.time|d1.fb|d1.mix|d1.pan|d2.*|d3.*|rev.preset|rev.mix]"
        // Harmony chord types
        static let enMaj7 = "he3d.enMaj7"; static let enM7   = "he3d.enM7"
        static let enDom7 = "he3d.enDom7"; static let enM7b5 = "he3d.enM7b5"
        static let enDim7 = "he3d.enDim7"; static let enMaj9 = "he3d.enMaj9"
        static let en9    = "he3d.en9";    static let enSus4 = "he3d.enSus4"
        static let en6    = "he3d.en6";    static let enM9   = "he3d.enM9"
    }

    // MARK: – Persistenz

    private func load() {
        let ud = Self.ud
        func d(_ key: String, _ def: Double) -> Double { ud.object(forKey: key) != nil ? ud.double(forKey: key)   : def }
        func b(_ key: String, _ def: Bool)   -> Bool   { ud.object(forKey: key) != nil ? ud.bool(forKey: key)    : def }
        func i(_ key: String, _ def: Int)    -> Int    { ud.object(forKey: key) != nil ? ud.integer(forKey: key) : def }

        if let raw = ud.string(forKey: K.language),
           let lang = AppLanguage(rawValue: raw) { language = lang }

        flight.maxSpeed               = d(K.maxSpeed,    144)
        flight.thrustForce            = d(K.thrustForce, 165)
        flight.invertPitch            = b(K.invertPitch, false)
        flight.gamepadYawSensitivity  = d(K.gamepadYaw,  1.2)
        flight.gamepadPitchSensitivity = d(K.gamepadPitch, 1.5)
        flight.autopilotEnabled       = b(K.autopilot,   false)
        flight.autopilotSpeed         = d(K.autopilotSpd, 0.55)
        flight.magnetStrength         = d(K.magnetStr,   1.7)
        flight.magnetRadius           = d(K.magnetRad,   155.0)

        midi.chordVelocity    = d(K.chordVel,  88)
        midi.bassVelocity     = d(K.bassVel,   110)
        midi.melodyVelMax     = d(K.melodyVel, 88)
        midi.melodyTempo      = d(K.melodyTempo, 1.0)
        midi.chordOctaveShift = i(K.chordOct,  0)
        midi.bassOctaveShift  = i(K.bassOct,   0)
        midi.bassHoldMode     = b(K.bassHold,  false)
        midi.sensorEnabled    = b(K.sensorEnabled,  false)
        midi.gyroEnabled      = b(K.gyroEnabled,    true)
        midi.gyroRollCC       = i(K.gyroRollCC,     74)
        midi.gyroPitchCC      = i(K.gyroPitchCC,    1)
        midi.gyroSensitivity  = d(K.gyroSens,       1.0)
        midi.touchpadEnabled  = b(K.touchpadEnabled, true)
        midi.touchpadXCC      = i(K.touchpadXCC,    11)
        midi.touchpadYCC      = i(K.touchpadYCC,    71)
        midi.rotationEnabled  = b(K.rotEnabled,     false)
        midi.rotationCC       = i(K.rotCC,          73)
        midi.sensorMidiChannel = i(K.sensorCh,      4)

        render.chordRadius          = d(K.chordRadius,  31.0)
        render.portalRadius         = d(K.portalRadius, 64.0)
        render.cloudRadius          = d(K.cloudRadius,  44.0)
        render.highQualityRendering = b(K.hqRender,     true)
        render.chordColorMode       = i(K.colorMode,    1)
        render.chordVisualMode      = i(K.visualMode,   0)
        render.showNetworkEdges     = b(K.netEdges,     false)
        render.easterTheme          = b(K.easterTheme,  false)
        render.morphingIntensity    = min(max(d(K.morphIntens, 0.0), 0.0), 1.0)

        harmony.chordTrigger  = d(K.chordTrigger,  100.0)
        harmony.portalTrigger = d(K.portalTrigger, 100.0)
        harmony.cloudTrigger  = d(K.cloudTrigger,  100.0)
        harmony.chordDensity  = d(K.chordDensity,  70)
        harmony.portalDensity = d(K.portalDensity, 30)
        harmony.cloudDensity  = d(K.cloudDensity,  30)
        harmony.keyCenter     = i(K.keyCenter,     -1)
        harmony.voiceLeadingEnabled = b(K.voiceLead, true)
        harmony.energyLevel   = d(K.energy,        0.35)
        harmony.networkIndex  = i(K.netIndex,      0)

        harmonicMagnet.isEnabled  = b(K.harmMagnetEnabled,    true)
        harmonicMagnet.intensity  = d(K.harmMagnetIntensity,  1.0)
        harmonicMagnet.rangeScale = d(K.harmMagnetRangeScale, 1.0)

        if let raw = ud.string(forKey: K.worldMode), let mode = RuntimeWorldMode(rawValue: raw) {
            worldSelection.mode = mode
        }
        if let raw = ud.string(forKey: K.worldHarmonyWebMap), let map = HarmonyWebMapCatalog(rawValue: raw) {
            worldSelection.harmonyWebMap = map
        }
        if let raw = ud.string(forKey: K.worldHarmonyWebLayer) {
            worldSelection.harmonyWebLayer = raw
        }
        if let raw = ud.string(forKey: K.worldExternalMapFileName), !raw.isEmpty {
            worldSelection.externalMapFileName = raw
        }
        audio.outputMode  = OutputMode(rawValue: i(K.outputMode, 0)) ?? .midi
        // Fallback = Produkt-Default (W-03b2). Ein bereits persistierter Wert
        // gewinnt weiterhin: wer bewusst auf "Klassisch" gestellt hat,
        // bekommt durch den Default-Wechsel nicht ungefragt eine andere
        // Stimme.
        audio.voiceEngine = SynthVoiceEngine(rawValue: i(K.voiceEngine, SynthVoiceEngine.atmospheric.rawValue)) ?? .atmospheric

        // MIDI-Eingang (Runde 073 / W-04): die Auswahl ueberlebt einen
        // Neustart auch dann, wenn das Geraet gerade nicht da ist — sie wird
        // erst beim Verbinden gegen die reale Geraeteliste aufgeloest
        // (MIDIInputSourceResolver).
        midiInput.isEnabled = b(K.midiInEnabled, true)
        let storedSourceID  = i(K.midiInSourceID, 0)
        midiInput.selectedSourceUniqueID = storedSourceID == 0 ? nil : Int32(truncatingIfNeeded: storedSourceID)
        midiInput.selectedSourceName     = ud.string(forKey: K.midiInSourceName) ?? ""

        // CC -> Makro (Runde 074 / W-05). Kodierung und Klemmung liegen in
        // MIDIMacroCCMapping (dort auch begruendet und getestet); hier steht
        // nur der UserDefaults-Zugriff. Der Initialisierer loest zusaetzlich
        // Doppelbelegungen deterministisch auf — eine von Hand veraenderte
        // plist kann die Eindeutigkeit also nicht brechen.
        func cc(_ key: String, _ fallback: UInt8?) -> UInt8? {
            MIDIMacroCCMapping.controller(
                fromStored: i(key, MIDIMacroCCMapping.storedValue(for: fallback)))
        }
        midiInput.macroCCMapping = MIDIMacroCCMapping(
            motion: cc(K.macroCCMotion, MIDIMacroCCMapping.defaults[.motion]),
            color:  cc(K.macroCCColor,  MIDIMacroCCMapping.defaults[.color]),
            space:  cc(K.macroCCSpace,  MIDIMacroCCMapping.defaults[.space]),
            focus:  cc(K.macroCCFocus,  MIDIMacroCCMapping.defaults[.focus])
        )

        // ChannelFXConfig: Keys via Prefix-Interpolation "he3d.audio.[kanal].[feld]"
        func loadFX(_ prefix: String, _ def: ChannelFXConfig) -> ChannelFXConfig {
            let base = "he3d.audio.\(prefix)"
            func f(_ s: String, _ v: Float) -> Float { Float(d("\(base).\(s)", Double(v))) }
            func n(_ s: String, _ v: Int)   -> Int   { i("\(base).\(s)", v) }
            return ChannelFXConfig(
                delay1Time:        f("d1.time",      def.delay1Time),
                delay1Feedback:    f("d1.fb",        def.delay1Feedback),
                delay1Mix:         f("d1.mix",       def.delay1Mix),
                delay1Pan:         f("d1.pan",       def.delay1Pan),
                delay2Time:        f("d2.time",      def.delay2Time),
                delay2Feedback:    f("d2.fb",        def.delay2Feedback),
                delay2Mix:         f("d2.mix",       def.delay2Mix),
                delay2Pan:         f("d2.pan",       def.delay2Pan),
                delay3Time:        f("d3.time",      def.delay3Time),
                delay3Feedback:    f("d3.fb",        def.delay3Feedback),
                delay3Mix:         f("d3.mix",       def.delay3Mix),
                delay3Pan:         f("d3.pan",       def.delay3Pan),
                reverbPreset:      n("rev.preset",   def.reverbPreset),
                reverbMix:         f("rev.mix",      def.reverbMix),
                channelVolume:     f("vol",           def.channelVolume),
                attack:            f("attack",        def.attack),
                decay:             f("decay",         def.decay),
                sustain:           f("sustain",       def.sustain),
                release:           f("release",       def.release),
                filterCutoff:      f("filt.cutoff",   def.filterCutoff),
                filterResonance:   f("filt.res",      def.filterResonance),
                waveform:          Waveform(rawValue: UInt8(n("waveform", Int(def.waveform.rawValue)))) ?? .sine,
                pan:               f("pan",            def.pan),
                unisonVoices:      n("unison.voices",  def.unisonVoices),
                unisonDetune:      f("unison.detune",  def.unisonDetune),
                unisonSpread:      f("unison.spread",  def.unisonSpread)
            )
        }

        audio.chord     = loadFX("chord",     .chordDefaults)
        audio.bass      = loadFX("bass",      .bassDefaults)
        audio.melody    = loadFX("melody",    .melodyDefaults)
        audio.chordTone = loadFX("chordTone", .chordToneDefaults)

        harmony.enableMaj7    = b(K.enMaj7, true)
        harmony.enableM7      = b(K.enM7,   true)
        harmony.enableDom7    = b(K.enDom7, true)
        harmony.enableM7b5    = b(K.enM7b5, true)
        harmony.enableDim7    = b(K.enDim7, false)
        harmony.enableMaj9    = b(K.enMaj9, true)
        harmony.enable9       = b(K.en9,    true)
        harmony.enableSus4    = b(K.enSus4, false)
        harmony.enable6       = b(K.en6,    false)
        harmony.enableM9      = b(K.enM9,   false)
    }

    private func save() {
        let ud = Self.ud
        ud.set(flight.maxSpeed,               forKey: K.maxSpeed)
        ud.set(flight.thrustForce,            forKey: K.thrustForce)
        ud.set(flight.invertPitch,            forKey: K.invertPitch)
        ud.set(flight.gamepadYawSensitivity,  forKey: K.gamepadYaw)
        ud.set(flight.gamepadPitchSensitivity, forKey: K.gamepadPitch)
        ud.set(flight.autopilotEnabled,       forKey: K.autopilot)
        ud.set(flight.autopilotSpeed,         forKey: K.autopilotSpd)
        ud.set(flight.magnetStrength,         forKey: K.magnetStr)
        ud.set(flight.magnetRadius,           forKey: K.magnetRad)

        ud.set(midi.chordVelocity,    forKey: K.chordVel)
        ud.set(midi.bassVelocity,     forKey: K.bassVel)
        ud.set(midi.melodyVelMax,     forKey: K.melodyVel)
        ud.set(midi.melodyTempo,      forKey: K.melodyTempo)
        ud.set(midi.chordOctaveShift, forKey: K.chordOct)
        ud.set(midi.bassOctaveShift,  forKey: K.bassOct)
        ud.set(midi.bassHoldMode,     forKey: K.bassHold)
        ud.set(midi.sensorEnabled,    forKey: K.sensorEnabled)
        ud.set(midi.gyroEnabled,      forKey: K.gyroEnabled)
        ud.set(midi.gyroRollCC,       forKey: K.gyroRollCC)
        ud.set(midi.gyroPitchCC,      forKey: K.gyroPitchCC)
        ud.set(midi.gyroSensitivity,  forKey: K.gyroSens)
        ud.set(midi.touchpadEnabled,  forKey: K.touchpadEnabled)
        ud.set(midi.touchpadXCC,      forKey: K.touchpadXCC)
        ud.set(midi.touchpadYCC,      forKey: K.touchpadYCC)
        ud.set(midi.rotationEnabled,  forKey: K.rotEnabled)
        ud.set(midi.rotationCC,       forKey: K.rotCC)
        ud.set(midi.sensorMidiChannel, forKey: K.sensorCh)

        ud.set(render.chordRadius,          forKey: K.chordRadius)
        ud.set(render.portalRadius,         forKey: K.portalRadius)
        ud.set(render.cloudRadius,          forKey: K.cloudRadius)
        ud.set(render.highQualityRendering, forKey: K.hqRender)
        ud.set(render.chordColorMode,       forKey: K.colorMode)
        ud.set(render.chordVisualMode,      forKey: K.visualMode)
        ud.set(render.showNetworkEdges,     forKey: K.netEdges)
        ud.set(render.easterTheme,          forKey: K.easterTheme)
        ud.set(render.morphingIntensity,    forKey: K.morphIntens)

        ud.set(harmony.chordTrigger,  forKey: K.chordTrigger)
        ud.set(harmony.portalTrigger, forKey: K.portalTrigger)
        ud.set(harmony.cloudTrigger,  forKey: K.cloudTrigger)
        ud.set(harmony.chordDensity,  forKey: K.chordDensity)
        ud.set(harmony.portalDensity, forKey: K.portalDensity)
        ud.set(harmony.cloudDensity,  forKey: K.cloudDensity)
        ud.set(harmony.keyCenter,     forKey: K.keyCenter)
        ud.set(harmony.voiceLeadingEnabled, forKey: K.voiceLead)
        ud.set(harmony.energyLevel,   forKey: K.energy)
        ud.set(harmony.networkIndex,  forKey: K.netIndex)

        ud.set(harmonicMagnet.isEnabled,  forKey: K.harmMagnetEnabled)
        ud.set(harmonicMagnet.intensity,  forKey: K.harmMagnetIntensity)
        ud.set(harmonicMagnet.rangeScale, forKey: K.harmMagnetRangeScale)

        ud.set(worldSelection.mode.rawValue,          forKey: K.worldMode)
        ud.set(worldSelection.harmonyWebMap.rawValue, forKey: K.worldHarmonyWebMap)
        ud.set(worldSelection.harmonyWebLayer,        forKey: K.worldHarmonyWebLayer)
        ud.set(worldSelection.externalMapFileName ?? "", forKey: K.worldExternalMapFileName)
        ud.set(harmony.enableMaj7,    forKey: K.enMaj7)
        ud.set(harmony.enableM7,      forKey: K.enM7)
        ud.set(harmony.enableDom7,    forKey: K.enDom7)
        ud.set(harmony.enableM7b5,    forKey: K.enM7b5)
        ud.set(harmony.enableDim7,    forKey: K.enDim7)
        ud.set(harmony.enableMaj9,    forKey: K.enMaj9)
        ud.set(harmony.enable9,       forKey: K.en9)
        ud.set(harmony.enableSus4,    forKey: K.enSus4)
        ud.set(harmony.enable6,       forKey: K.en6)
        ud.set(harmony.enableM9,      forKey: K.enM9)

        // AudioConfig – Output-Modus und Stimmtyp
        ud.set(audio.outputMode.rawValue,  forKey: K.outputMode)
        ud.set(audio.voiceEngine.rawValue, forKey: K.voiceEngine)

        // MIDI-Eingang (Runde 073 / W-04)
        ud.set(midiInput.isEnabled,                          forKey: K.midiInEnabled)
        ud.set(Int(midiInput.selectedSourceUniqueID ?? 0),   forKey: K.midiInSourceID)
        ud.set(midiInput.selectedSourceName,                 forKey: K.midiInSourceName)
        // Kodierung siehe MIDIMacroCCMapping.storedValue(for:).
        ud.set(MIDIMacroCCMapping.storedValue(for: midiInput.macroCCMapping[.motion]), forKey: K.macroCCMotion)
        ud.set(MIDIMacroCCMapping.storedValue(for: midiInput.macroCCMapping[.color]),  forKey: K.macroCCColor)
        ud.set(MIDIMacroCCMapping.storedValue(for: midiInput.macroCCMapping[.space]),  forKey: K.macroCCSpace)
        ud.set(MIDIMacroCCMapping.storedValue(for: midiInput.macroCCMapping[.focus]),  forKey: K.macroCCFocus)

        // ChannelFXConfig: Keys via Prefix-Interpolation (konsistent mit load())
        func saveFX(_ cfg: ChannelFXConfig, _ prefix: String) {
            let base = "he3d.audio.\(prefix)"
            ud.set(Double(cfg.delay1Time),         forKey: "\(base).d1.time")
            ud.set(Double(cfg.delay1Feedback),     forKey: "\(base).d1.fb")
            ud.set(Double(cfg.delay1Mix),          forKey: "\(base).d1.mix")
            ud.set(Double(cfg.delay1Pan),          forKey: "\(base).d1.pan")
            ud.set(Double(cfg.delay2Time),         forKey: "\(base).d2.time")
            ud.set(Double(cfg.delay2Feedback),     forKey: "\(base).d2.fb")
            ud.set(Double(cfg.delay2Mix),          forKey: "\(base).d2.mix")
            ud.set(Double(cfg.delay2Pan),          forKey: "\(base).d2.pan")
            ud.set(Double(cfg.delay3Time),         forKey: "\(base).d3.time")
            ud.set(Double(cfg.delay3Feedback),     forKey: "\(base).d3.fb")
            ud.set(Double(cfg.delay3Mix),          forKey: "\(base).d3.mix")
            ud.set(Double(cfg.delay3Pan),          forKey: "\(base).d3.pan")
            ud.set(cfg.reverbPreset,               forKey: "\(base).rev.preset")
            ud.set(Double(cfg.reverbMix),          forKey: "\(base).rev.mix")
            ud.set(Double(cfg.channelVolume),      forKey: "\(base).vol")
            ud.set(Double(cfg.attack),             forKey: "\(base).attack")
            ud.set(Double(cfg.decay),              forKey: "\(base).decay")
            ud.set(Double(cfg.sustain),            forKey: "\(base).sustain")
            ud.set(Double(cfg.release),            forKey: "\(base).release")
            ud.set(Double(cfg.filterCutoff),       forKey: "\(base).filt.cutoff")
            ud.set(Double(cfg.filterResonance),    forKey: "\(base).filt.res")
            ud.set(Int(cfg.waveform.rawValue),     forKey: "\(base).waveform")
            ud.set(Double(cfg.pan),                forKey: "\(base).pan")
            ud.set(cfg.unisonVoices,               forKey: "\(base).unison.voices")
            ud.set(Double(cfg.unisonDetune),       forKey: "\(base).unison.detune")
            ud.set(Double(cfg.unisonSpread),       forKey: "\(base).unison.spread")
        }

        saveFX(audio.chord,     "chord")
        saveFX(audio.bass,      "bass")
        saveFX(audio.melody,    "melody")
        saveFX(audio.chordTone, "chordTone")
    }

    // MARK: – Publisher: Chunk-relevante Properties
    //
    // Exakt dieselben Properties wie vorher – nur jetzt über sub-config map+removeDuplicates.
    // energyLevel, networkIndex und andere nicht-rebuild-relevante Properties
    // lösen keinen Rebuild aus.

    var chunkRebuildPublisher: AnyPublisher<Void, Never> {
        let rp: [AnyPublisher<Void, Never>] = [
            // RenderConfig
            $render.map { $0.chordRadius }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            $render.map { $0.portalRadius }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            $render.map { $0.cloudRadius }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            $render.map { $0.highQualityRendering }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            $render.map { $0.chordColorMode }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            $render.map { $0.chordVisualMode }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            $render.map { $0.easterTheme }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            // HarmonyConfig
            $harmony.map { $0.chordDensity }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            $harmony.map { $0.portalDensity }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            $harmony.map { $0.cloudDensity }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            $harmony.map { $0.keyCenter }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            $harmony.map { $0.enableMaj7 }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            $harmony.map { $0.enableM7 }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            $harmony.map { $0.enableDom7 }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            $harmony.map { $0.enableM7b5 }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            $harmony.map { $0.enableDim7 }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            $harmony.map { $0.enableMaj9 }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            $harmony.map { $0.enable9 }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            $harmony.map { $0.enableSus4 }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            $harmony.map { $0.enable6 }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            $harmony.map { $0.enableM9 }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
        ]
        return Publishers.MergeMany(rp)
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}
