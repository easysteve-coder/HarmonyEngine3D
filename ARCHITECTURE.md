# ARCHITECTURE – HarmonyEngine3D

**Stand:** 2026-04-05 (Grundgerüst) / **2026-07-29** (Abschnitt
„V1-Integrationsstand") | **Version:** 3.9.9

> **Review-Hinweis 2026-07-26, ergänzt 2026-07-29 (Runde 043 / V-03):**
> Dieses Dokument ist historisch gewachsen und beschreibt in weiten Teilen
> noch den Zwischenstand vor der Einführung von `WorldSession`,
> `InteractionRuntime`, dem v1-`HarmonyMap`-Modell, `HarmonyAuthoring`/
> `DesignerKit` (Construction Kit) und `RuntimeMapImportStore`. Diese Teile
> sind **historisch/veraltet** dort, wo sie dem Abschnitt
> „V1-Integrationsstand" widersprechen — der Abschnitt direkt unter
> „Projektziel" ist die aktuelle, autoritative Kurzfassung des Iststands.
> Für die Zielarchitektur und die operative Rev.-7-Slice-Reihenfolge gelten
> weiterhin `ARCHITECTURE_REVIEW_2026-07-26.md` und der Anfang von
> `ROADMAP.md`. Eine vollständige Neufassung dieses gesamten Dokuments ist
> weiterhin nicht Teil von V-03 (gezielte Synchronisierung, keine
> Neuerfindung) — siehe `README.md` für den aktuellen Setup-/Start-Weg.

---

## Projektziel

macOS-Instrument für Live-Performance (Mainstage): Der Spieler fliegt durch einen 3D-Akkordraum und erzeugt MIDI-Output oder internen Audio durch Annäherung an Chord-Knoten. Steuerung: PS5 DualSense Gamepad + Tastatur/Maus.

---

## V1-Integrationsstand (Runde 043 / V-03, Stand 2026-07-29)

> Diese Kurzfassung beschreibt den tatsächlichen aktuellen Produktpfad und
> ersetzt für die hier genannten Punkte ältere, abweichende Aussagen weiter
> unten in diesem Dokument. Sie ist bewusst knapp gehalten — Details stehen
> in den jeweiligen Quelldateien und in `ARCHITECTURE_REVIEW_2026-07-26.md`.

### SPM-Targets (Ist-Stand)

```
Package.swift
├── HarmonyShared        (Library)    – plattformfreie Modelle/Algorithmen
│                                       (HarmonyMap-Modell v1, HarmonyGraphEngine,
│                                        SeededRNG, AutopilotEngine, NetworkParser)
├── HarmonyAuthoring     (Library)    – Dokument-/Command-Modell fürs Construction
│                                       Kit (HarmonyMapDocument, Undo/Redo, I/O,
│                                       Builder). Haengt nur von HarmonyShared ab.
├── HarmonyEngine3D      (Executable) – macOS 3D-App. Haengt nur von HarmonyShared
│                                       ab — KEIN DesignerKit-/HarmonyAuthoring-
│                                       Import im Produktcode (Hard Stop).
├── DesignerKit          (Executable) – macOS 2D-Construction-Kit-Editor.
│                                       Haengt von HarmonyShared + HarmonyAuthoring ab.
├── HarmonySharedTests    (Test)
├── HarmonyEngine3DTests  (Test)      – haengt zusaetzlich von HarmonyAuthoring ab
│                                       (nur Testtarget, fuer einen Kit-Map-Fixture-
│                                       Nachweis; Produktcode bleibt frei davon)
├── HarmonyAuthoringTests (Test)
└── DesignerKitTests      (Test)
```

### Kanonischer HarmonyWeb-Produktpfad: `WorldSession`

Seit E-01 ist `WorldSession` die einzige Besitz-Instanz für eine validierte
`HarmonyMap` + aktiven Layer + `HarmonyGraphEngine` + `RuntimeHarmonik`.
Alle drei Map-Quellen laufen über denselben Pfad in `WorldSession` hinein:

- **Bundle-Maps** (`Sources/HarmonyShared/Resources/maps/*.json`) über
  `HarmonyMapLoader.load(named:)`.
- **Externe importierte Maps** (Runde 040/041 / V-01, V-01.1) über
  `RuntimeMapImportStore.load(fileName:)` aus
  `~/Library/Application Support/HarmonyEngine3D/HarmonyWeb/Maps` — der
  Ordner wird beim ersten Zugriff über `listImportedMaps()` im
  Default-Produktpfad automatisch und nicht-destruktiv angelegt.
  `RuntimeMapImportStore` ist reine Datei-/Codec-Schicht (nur `Foundation`
  + `HarmonyShared`), kein SceneKit, kein `AppSettings`-Zugriff.
- **Explore** (Default) nutzt weiterhin `NetworkParser`/`network_wholetone.txt`
  außerhalb von `WorldSession` — unverändert seit vor E-01.

`AppModel.effectiveHarmonyWebRequest(envOverride:selection:)` entscheidet
pro Start, welche Quelle geladen wird (`isExternal`-Flag steuert
`RuntimeMapImportStore` vs. `HarmonyMapLoader`); der
Developer-/Kompatibilitäts-Override
(`--map-preview`/`HE3D_MAP_PREVIEW`/`HE3D_MAP_NAME`) hat Vorrang und lädt
immer aus dem Bundle. Explore bleibt in allen Fällen der App-Default.

Ein `toChordNetwork`-Adapter existiert weiterhin für Legacy-/Kompatibilitäts-
zwecke, ist aber **nicht** Teil des HarmonyWeb-/externen Ladepfads (per
Test belegt, `KitToRuntimeImportTests`).

### `InteractionRuntime` — Chord/Bass/Cloud-Trigger

Seit E-06 ist die proximitätsbasierte Trigger-/Note-Lifecycle-Logik für
Chord-, Portal/Bass- und Cloud/Melody-Kanäle in `InteractionRuntime`
gebündelt — SceneKit-frei, testbar ohne 3D-Rendering. CH0-NoteOff wird
ausschließlich aus einem gebündelten `ChordOutputSnapshot` (Name + Noten
aus demselben Aktivierungszeitpunkt) gespeist, auch bei Kandidatenverlust
im selben Frame (Runde 038/039 / V-00b, V-00b.1) — verhindert hängende
Noten und stellt sicher, dass `OutputCoordinator.soundingChordName` korrekt
geleert werden kann. Musikalische Live-Entscheidungen (`MelodyEngine`,
`AutopilotEngine`) nutzen seit V-00b `SeededRNG` statt unseeded
`randomElement()`/`Float.random` — deterministisch bei gleichem Seed.

### Audio-/MIDI-Grenze

- `AudioOutput`-Protokoll (`noteOn`/`noteOff`/`allNotesOff`/`applyFXConfig`)
  mit zwei Implementierungen: `MIDIManager` (CoreMIDI Virtual Output) und
  `AudioEngine` (interner VA-Synth, 4 unabhängige `AVAudioEngine`-Kanäle).
  Auswahl über `AppSettings.audio.outputMode`, wirkt einmalig beim
  App-Start (`AppModel.makeAudioOutput()`), kein Live-Umschalten.
- `MIDIManager.shared` ist ausschließlich in `OutputCoordinator` und
  `AppModel` erlaubt; `FlightController`/`GamepadController` dürfen
  `sendCC` direkt für Sensor-Telemetrie nutzen (dokumentierte Ausnahme,
  siehe `CLAUDE.md`).
- Bekannte, unveränderte Strict-Concurrency-Warnungen (Swift 6,
  `-strict-concurrency=complete`): 480 Warnungen in denselben 11
  Bestandsdateien seit mehreren Runden (`AppSettings.swift`,
  `DesignerGamepad.swift`, `DesignerViewModel.swift`,
  `FlightController.swift`, `GamepadController.swift`,
  `HarmonyEngine3DApp.swift`, `MIDIManager.swift` in `DesignerKit` **und**
  `HarmonyEngine3D`, `NetworkParser.swift`, `OutputCoordinator.swift`,
  `SceneKitView.swift`). Kein neuer Warnungstyp seit Runde 040. Diese
  bestehenden Warnungen sind bekannt und nicht Teil eines aktuellen
  Behebungsauftrags.
### MIDI-Eingang (Runde 073 / W-04)

Seit W-04 ist die MIDI-Grenze zweiseitig. Der Eingang liegt in zwei Dateien:

- `MIDIInputRouting.swift` — CoreMIDI-frei: UMP-Dekodierung, Kanal-Politik,
  Quellenfilter/-auflösung, Notenbuchführung, Router auf `AudioOutput`,
  CC-Register. Vollständig ohne Gerät testbar.
- `MIDIInputManager.swift` — CoreMIDI: virtuelles Ziel
  „HarmonyEngine3D Input", Eingangsport plus Verbindung zu einer wählbaren
  externen Quelle, Gerätelistung, Reaktion auf An-/Abstecken. Eigener
  MIDI-Client; der Ausgang (`MIDIManager`) bleibt unberührt.

**Der Eingang ist ausschließlich ein weiterer `AudioOutput`-Aufrufer.** Er
schreibt nie selbst in eine `NoteEventQueue`. Bei `AudioEngine` legt jede
`AudioOutput`-Methode den Aufruf auf `commandQueue`; erst deren
Worker-Thread ruft `push()`. Der CoreMIDI-Thread wird dadurch kein zweiter
Producer, und der SPSC-Vertrag der Queue bleibt wörtlich unverändert (die
Verletzung dieses Vertrags war der F-02-Fehler). Preis dieses Weges: ein
`DispatchQueue.async` pro Ereignis im MIDI-Callback — dort vertretbar, im
Audio-Render-Thread verboten.

Die App verwendet die UMP-Variante der CoreMIDI-Empfangs-APIs
(`MIDIDestinationCreateWithProtocol` / `MIDIInputPortCreateWithProtocol`,
`MIDIProtocolID._1_0`). Die älteren `...WithBlock`-Varianten sind seit
macOS 11 deprecated. CoreMIDI löst dabei den Running Status auf; jedes
UMP-Wort trägt ein vollständiges Statusbyte.

**On-Off-Symmetrie extern gestarteter Noten.** Buchung im Notenbuch und der
zugehörige `AudioOutput`-Aufruf liegen in derselben kritischen Sektion.
Getrennt wären sie ein echter Race: CoreMIDI-Thread bucht, Main Thread
räumt auf und sendet `noteOff`, CoreMIDI-Thread sendet erst danach sein
`noteOn` — beide reihen in dieser Reihenfolge bei `commandQueue` ein und die
Note hinge für immer. Beim Trennen einer Quelle wird der Quellweg im selben
Atemzug gesperrt, in dem aufgeräumt wird; anschließend erst löst der Manager
die CoreMIDI-Verbindung. Ein `noteOn` wird dadurch entweder vollständig
gebucht und ausgegeben, oder verworfen, bevor es klingt — ein drittes
Zeitfenster gibt es nicht.

Die Buchführung ist **pro Eingangsweg getrennt** (virtuelles Ziel /
externe Quelle). Ein gemeinsames Buch würde beim Abziehen eines Keyboards
auch die Noten beenden, die eine DAW gerade hält.

**Grenze, bewusst offen:** verschwindet ein Sender, der über das *virtuelle
Ziel* schickt (DAW-Absturz mitten in einer Note), gibt es dafür kein
CoreMIDI-Ereignis — die Verbindung gehört dem Sender, nicht der App. Solche
Noten enden erst mit Panic (△ / UI-Knopf). Für die *externe Quelle* ist der
Fall abgedeckt.

**Kanal-Politik — vorläufig, Stephan-Entscheidung offen:** der Eingang hört
auf allen 16 MIDI-Kanälen. Kanal 1–4 bilden auf CH0–CH3 ab, 5–16 fallen auf
CH0 zurück. Ein stiller Kanalfilter wäre der undankbarste Fehlermodus.

**Control Changes:** werden empfangen und im `MIDIControlChangeRegistry`
mit dem jeweils letzten Wert je (Kanal, Controller) bereitgestellt, plus
Beobachter-Haken.

### CC → Performance-Makro (Runde 074 / W-05)

Seit W-05 hängt der Beobachter-Haken der Registry an
`MIDIMacroCoalescer` (`Sources/HarmonyEngine3D/MIDIMacroMapping.swift`).
Der vollständige Weg eines Reglerwerts:

```
CoreMIDI-Thread
  → MIDIInputRouter.handle            CC ins Register, kein Notenlock
  → MIDIControlChangeRegistry.record  Beobachter, synchron
  → MIDIMacroCoalescer.handle         Zuordnung, letzter Wert je Makro
  ──────────────────────── 20 ms Mindestpause ────────────────────────
Main Thread
  → MIDIMacroCoalescer.flush          nur bei echter Änderung
  → AudioEngine.applyMacroValues      vier SynthParams-Snapshots
  → commandQueue.async                ← einzige Serialisierungsgrenze
  ─────────────────────────────────────────────────────────────────────
commandQueue-Worker
  → SynthNode.updateParams → NoteEventQueue.push (.paramUpdate)
Audio-Thread
  → VoicePool.applyParams → AudioCoreAtmosphericVoice.setParameters
  → Modulationsmatrix (Makro als typisierte Quelle)
  → sieben AudioCoreParameterSmoother auf Audiorate
```

**Die Drossel ist der tragende Teil.** Jede Makro-Ausgabe erzeugt vier
`paramUpdate`-Ereignisse, eines je Kanal-`NoteEventQueue`. Ungedrosselt
wären das bei 127 CC-Werten pro Sekunde 508 Ereignisse, bei vier bewegten
Reglern 2.032 — jedes davon lässt `VoicePool.applyParams` über bis zu 16
Stimmen laufen, im Audio-Callback. Gemessen mit Drossel: 168 in beiden
Fällen. Bewusst Koaleszieren mit Mindestpause statt des 30-ms-Debounce der
Audio-Einstellungen: ein nachlaufendes Debounce gibt während eines
Reglerschwenks gar nichts aus, was für einen Performance-Regler das
Gegenteil von spielbar wäre.

**Wo die Zuordnung liegt und wo nicht:** die Abbildung CC → Makro liegt im
App-Layer (`MIDIMacroCCMapping`, persistiert in `AppSettings.midiInput`),
die Abbildung Makro → Klangziel als Routendaten in
`AudioCoreAtmosphericVoiceParameters.defaultModulationMatrix`. Kein
Controller-Mapping im Synth-Core (`SYNTH_ARCHITECTURE_PLAN.md` 10), und
kein Klangziel im App-Layer.

**Beide Zuordnungen sind vorläufig — Stephan-Entscheidung offen.**
Werksbelegung Motion CC 77, Color CC 74, Space CC 91, Focus CC 71. Die
Makro-Ziel-Zuordnung ist eine Näherung: von den sieben Modulationszielen
entspricht nur `spaceSend` einem Plan-Makro exakt, und weil alle Makros
unipolar bei 0 starten (Voraussetzung der Bit-Identität), kann jedes nur in
eine Richtung wirken. `color` trägt deshalb ein negatives Vorzeichen.

Eine CC-Nummer gehört immer nur einem Makro; eine unbelegte Nummer tut
nichts und ist kein Fehler.

**Eigener Ausgang ist nicht als Eingangsquelle wählbar:** bei
`outputMode == .midi` reicht der Eingang an den virtuellen Ausgang weiter;
wäre dieser zugleich wählbare Quelle, entstünde eine MIDI-Endlosschleife.
Eine von außen gepatchte Schleife (DAW verbindet Ausgang mit Eingang) kann
die App nicht verhindern.

- `bassHoldMode` (`MIDIConfig.bassHoldMode`) — Toggle-Semantik (Fable-5-Review
  Finding A12, Gate 10) ist seit Runde 062 entschieden und umgesetzt:
  schaltet man `bassHoldMode` während einer gehaltenen Bassnote aus, sendet
  `InteractionRuntime.updatePortal(_:)` ein Nachhol-`noteOff` für jede
  tatsächlich klingende Bassnote (`soundingBassNotesByKey`), außer für die
  Note des aktuell aktiven Portals — die bleibt wie im Trigger-Modus bis
  zum Verlassen klingen. Details: `ROADMAP.md` Gate 10,
  `.agent_handoff/latest_claude.md` Runde 062.

### V-02-Status: Live-Instrument-Smoke-Matrix

Boot-/Start-Smoke ist reproduzierbar grün (Explore, HarmonyWeb Bundle-Map,
HarmonyWeb externe importierte Map, jeweils über internen Synth und MIDI,
siehe `SMOKE_TEST_V1.md`, Runde 042). **Die echte Sustained-/Live-
Interaktions-Achse (durchgehende Tastatur-/Maus-/Gamepad-Interaktion über
eine längere Session, Ziel 30 Minuten) ist bisher NICHT bestanden oder
verifiziert** — in der bisherigen Headless-CLI-Verifikationsumgebung tickt
SceneKits Renderer-Update-Callback nach der Erstinitialisierung nicht
weiter, wodurch diese Achse dort nicht beobachtbar ist. Dieser manuelle
Live-Gate bleibt offen, bis entweder eine echte Vordergrund-Session
(idealerweise mit angeschlossenem DualSense) durchgeführt wird oder
Supervisor/Stephan explizit eine Ersatzverifikation akzeptiert. Details und
Checkliste: `RELEASE_CHECKLIST_V1.md`.

---

## SPM-Targets

```
Package.swift
├── HarmonyShared       (Library) – plattformfreie Datenmodelle + Algorithmen
├── HarmonyEngine3D     (Executable) – macOS 3D-App
└── DesignerKit         (Executable) – macOS 2D-Navigator (eigener App-Scope)
```

`HarmonyShared` hat keine Abhängigkeiten zu SceneKit, AppKit, SwiftUI oder CoreMIDI.
`HarmonyEngine3D` importiert `HarmonyShared`.
`DesignerKit` importiert `HarmonyShared`.

### HarmonyShared — aktueller Inhalt

**Bestehend:**
`ChordData`, `EdgeData`, `ChordNetwork`, `NetworkParser`, `AutopilotEngine`, `SeededRNG`
→ Bleibt unverändert. `.txt`-Netzwerke laufen weiter.

**v1-Netzwerkmodell (implementiert, 3.9.0):**
```
HarmonyNode         id, root, type, function, tags, midiNotes, layout3D?
HarmonyEdge         id, source, target, relationTypes, directed, layers, weight, magnetProfile?
HarmonyLayer        id, name, relationTypes
HarmonyMap          schemaVersion, id, name, layers, nodes, edges, layout?
MagnetProfile       preset: strong | medium | weak  (v1: Presets)
RelationType        V-I | ii-V | relMajMin | parallelMajMin | commonTone | tritSubst
HarmonyMapLoader    load(named:) → HarmonyMap?  |  toChordNetwork(_:layer:) → ChordNetwork
HarmonyGraphEngine  neighbors | transitions | weightedChoice | setLayer | recordVisit
```

Vollständige Definitionen + Implementierungsstand: `HarmonyNetwork_Spec_v1.md`.
Parallelstrategie: JSON-Format läuft parallel zu `.txt`; kein Altcode entfernt.

**Verfügbare HarmonyWebs (`Sources/HarmonyShared/Resources/maps/`)**

| Datei | Nodes | Edges | Layer | Status |
|---|---|---|---|---|
| `harmony-web-c-diatonic.json` | 14 | 29 | functional, modal | **aktiv** (Primäre Testwelt) |
| `harmony-web-c-center.json` | 8 | 22 | functional, modal | Archiv (frühere Testwelt) |
| `reference-core.json` | 7 | 11 | functional, modal | Archiv (Schema-Referenz) |

Aktive Testwelt wird in `HarmonyEngine3DApp.init()` über `mapName` ausgewählt.

**Erste Runtime-Hooks (3.9.0):**
- `OutputCoordinator.onGraphHook: ((String) -> Void)?` — feuert bei jedem `onChordActivated`,
  loggt Vorschlag, pflegt `recordVisit`-Kontext

**Zurückgebaut (3.9.1):**
- `HarmonyScene.graphSuggest` — temporärer ×2.0-Bias auf Chunk-Generierung entfernt.
  Harmonische Logik soll lokal auf bestehende Nodes wirken, nicht über neue Chunks.
  Folgemechanismus: Phase 4.3 (Magnetismus via RuntimeHarmonik).

---

## Schichtenmodell

```
┌─ App Layer ──────────────────────────────────────────────────────┐
│  HarmonyEngine3DApp   @main Entry-Point                         │
│  AppModel             Besitzer aller langlebigen Objekte;        │
│                       wählt AudioOutput-Implementierung;         │
│                       Combine: AppSettings.audio → AudioEngine  │
│  OutputCoordinator    Trigger → AudioOutput-Routing;            │
│                       Callbacks (BassToggle, NetworkNav, Help)  │
├─ UI / Renderer ──────────────────────────────────────────────────┤
│  ContentView          Root-SwiftUI-View, HUD, Overlay-Steuerung │
│  SceneKitView         NSViewRepresentable-Wrapper               │
│  HarmonyScene         SCNScene: Chunks, Nodes, Proximity, Render│
│  RuntimeHarmonik      Mittelschicht Graph → Raum [impl. 3.9.0] │
│                       Kandidatenselektion, HarmonicDecision,    │
│                       Kontext-Pflege — kein SceneKit, kein Audio│
│  TargetingOverlayModel  Lock-On HUD (Screen-Space-Projektion)   │
│  ControlsOverlay      PS5-Button-Diagramm (reine UI)            │
│  AudioMixerPanel      Live-Sounddesign-Konsole (Hotkey M)       │
├─ Input Layer ────────────────────────────────────────────────────┤
│  FlightController     Koordiniert Input + Physik + UI-State     │
│  InputProvider        Protokoll: thrustFwd/Bwd, lookX/Y, braking│
│  GamepadController    PS5/Xbox/MFi – konformiert InputProvider  │
│  (Tastatur + Maus)    macOS-lokal, direkt in FlightController   │
├─ Core (plattformfrei) ───────────────────────────────────────────┤
│  FlightPhysics        FlightState, InputState, Physik-Integr.  │
│  WorldGeneration      ChunkCoord, SeededRNG, Chunk-Inhalt       │
│  ProximityTracker     Nächste Chord-Knoten zur Spielerposition  │
│  TriggerEngine        Proximity-Zustandsautomat → MIDI-Events   │
│  MelodyEngine         6 Melodie-Presets, zustandsbehaftet       │
│  VoiceLeadingEngine   Oktavanpassung für glatte Stimmführung    │
│  ChordGenerator       48 Akkorde mit Theorie-Gewichtung         │
│  AutopilotEngine*     Graph-Traversierung (* in HarmonyShared)  │
│  NetworkParser*       Lädt Netzwerk-Definitionen aus Bundle     │
│  HarmonyGraphEngine*  Musikalische Übergänge, weightedChoice,  │
│                       Kontext-Modulation (* in HarmonyShared)   │
├─ Output Layer ───────────────────────────────────────────────────┤
│  AudioOutput          Protokoll: noteOn/noteOff/allNotesOff/    │
│                       applyFXConfig                             │
│  MIDIManager          CoreMIDI Virtual Output (Singleton,       │
│                       zustandsloser Byte-Sender)                │
│  AudioEngine          Interner VA-Synth: 4 unabhängige Kanäle, │
│                       je 3 Delays + Reverb (AVAudioEngine)      │
│  SynthNode            AVAudioSourceNode + VoicePool + Queue     │
│  SynthVoice           Einzelstimme: Oszillator + Biquad + ADSR │
│  NoteEventQueue       SPSC-Ringpuffer Main → Audio-Thread       │
├─ Konfiguration ──────────────────────────────────────────────────┤
│  AppSettings          ObservableObject-Singleton                │
│    FlightConfig         Physikparameter, Autopilot, Sensitivität│
│    MIDIConfig           Kanäle, Velocity, Gyro-CC, Bass-Mode   │
│    RenderConfig         Radien, Darstellungsoptionen            │
│    HarmonyConfig        Netzwerk, Keys, Chord-Typen, Energie   │
│    AudioConfig          OutputMode + 4× ChannelFXConfig        │
└──────────────────────────────────────────────────────────────────┘
```

---

## Datenfluss

```
GamepadController (Buttons, Gyro, Touchpad)
    │
    ├─ InputProvider-Protokoll ──► FlightController.buildInputState()
    │                                    │
    │                              FlightPhysics.update()
    │                                    │
    │                              FlightState (position, velocity, orientation)
    │                                    │
    │                              HarmonyScene ← SceneKitView (Kamera-Sync)
    │
    ├─ Sensor-CC direkt ──────────► MIDIManager.sendCC()   (Gyro, Touchpad)
    │
    └─ Callbacks ────────────────► OutputCoordinator (BassToggle, NetworkNav, Help)

HarmonyScene (Render Thread)
    │
    ├─ ProximityTracker ─────────► nahe Chord-Knoten
    │
    └─ TriggerEngine ────────────► Note-On / Note-Off Events
                                         │
                               OutputCoordinator
                                         │
                                   AudioOutput (Protokoll)
                                    ├── MIDIManager   (outputMode = .midi)
                                    └── AudioEngine   (outputMode = .internalAudio)

AppSettings.audio (Main Thread, Combine)
    │  debounce 30 ms
    └─► AudioEngine.applyEffectConfigX()
              │
              ├── gainX.outputVolume / gainX.pan   (AVAudioMixerNode)
              ├── delayNSendX.*                    (AVAudioMixerNode)
              ├── delayNX.*                        (AVAudioUnitDelay)
              ├── reverbX.*                        (AVAudioUnitReverb)
              └── SynthNode.updateParams()
                        │ (NoteEventQueue, lock-free)
                        └─► VoicePool.applyParams()  (Audio-Thread)
                                  ├── Live: filterCutoff/Resonance → alle aktiven Voices
                                  └── Live: sustain → alle Voices in Sustain-Stage
```

---

## Audio-Signalfluss (intern, pro Kanal)

Alle vier Kanäle (CH0–CH3) folgen exakt demselben Schema. Keine Cross-Channel-Verbindungen.

```
SynthNode.sourceNode   (AVAudioSourceNode, explizit stereo 32-Bit Float)
    │
    ▼
gainX                  outputVolume (0…1) + pan (−1…+1, Mixer-Layer)
    │
    ├──────────────────────────────────────────────────────► sumX  (Dry)
    ├──► delay1SendX (outputVolume = Send-Pegel, pan = Tap-Position)
    │        └──► delay1X  (wetDryMix=100 %)  ────────────► sumX
    ├──► delay2SendX
    │        └──► delay2X  (wetDryMix=100 %)  ────────────► sumX
    └──► delay3SendX
             └──► delay3X  (wetDryMix=100 %)  ────────────► sumX
                                                              │
                                                              ▼
                                                          reverbX  (preset, wetDryMix)
                                                              │
                                                              ▼
                                                      mainMixerNode → outputNode
```

### Gemeinsame Raumkette (W-03c, Runde 072)

Parallel zu den vier kanalgetrennten Legacy-FX-Ketten oben läuft ein
gemeinsamer Raum. Er ersetzt nichts — er kommt **additiv** dazu:

```
VoicePool (je Stimme)   Ausgang der Stimme × spaceSendLevel × spaceSendChannelGain
    │                   (Atmospheric Voice; die Legacy-Voice hat kein Send-Ziel)
    ▼
SpaceSendBus            Mono-Akkumulator in Software, alle vier Kanäle
    │
    ▼
DeepSpaceReturnNode     AVAudioSourceNode mit AudioCoreDeepSpace
    │                   (Pre-Delay → Early Reflections ∥ Diffusor → FDN-Tail)
    ▼
sharedSpaceSendBus ──► mainMixerNode
```

**Warum der Send in Software entsteht und nicht als Knotenabgriff hinter
`gainX`:** er ist pro Stimme gewichtet. `AudioCoreAtmosphericVoice
.spaceSendLevel` ist ein Modulationsziel und existiert nur innerhalb des
`VoicePool`, vor der Summierung; hinter `gainX` liegt nur noch die fertige
Kanalsumme. Der in `AudioGraphTopology.swift` festgeschriebene
Abgriffspunkt bleibt eingehalten: CH1 greift vor `compressorBass` ab
(Option A), und der Kanalfader wirkt über `SynthParams
.spaceSendChannelGain` — denselben linearen Wert, der auf
`gainX.outputVolume` geht — als Post-Fader-Send.

Schreiber (vier `SynthNode`-Callbacks) und Leser (`DeepSpaceReturnNode`)
laufen im selben Renderzyklus auf demselben Renderthread. Ihre Reihenfolge
ist von AVAudioEngine nicht zugesichert und für die Korrektheit auch nicht
nötig: `accumulate` addiert, `drain` liest und nullt in einem Zug, jeder
Block wird genau einmal verbraucht. Im ungünstigen Fall verschiebt sich der
Send um einen Block.

`sharedEchoSendBus` bleibt weiterhin ungespeist — `EchoField` folgt in S-09.

**Stereo-Entstehung:**
- `SynthNode.sourceNode` ist immer ein stereo ausgegebener Knoten (explizites stereoFormat). Das Ausgangssignal ist L=R (Mono-Oszillator) — das Stereo-Bild entsteht nicht im Oszillator selbst, sondern durch Unison-Spread (jede Unison-Voice erhält eine individuelle Constant-Power-Pan-Position) und durch die gepanten Delay-Sends downstream.
- Delay-Taps sind gepant (Tap1 links, Tap2 rechts, Tap3 Mitte) → Stereo-Breite im Delay-Pfad
- `gainX.pan` verschiebt den Gesamtkanal als Block im Stereofeld
- `AVAudioUnitReverb` verarbeitet inherent stereo

### Kanal-Defaults

| Kanal | Reverb | Mix | Delay-Charakter | Unison |
|-------|--------|-----|-----------------|--------|
| CH0 Chord | Large Hall (Preset 4) | 35 % | 70/90/140 ms, gepant ±50 % | 1 Stimme |
| CH1 Bass | Medium Hall (Preset 3) | 15 % | 30/40/70 ms, trocken | **2 Stimmen, ±8 Cent, Spread 0.25** — Stereo durch Unison-Spread im Synth |
| CH2 Melody | Cathedral (Preset 8) | 55 % | 120/160/250 ms, langer Feedback | 1 Stimme |
| CH3 Chord Tone | Medium Hall (Preset 3) | 25 % | 50/80/120 ms, sparsam | 1 Stimme |

---

## Synth-Architektur (interner VA-Synth)

```
SynthNode
├── NoteEventQueue      SPSC-Ringpuffer (Main → Audio-Thread, lock-free)
│     Events: .noteOn / .noteOff / .allOff / .paramUpdate(SynthParams)
│
└── VoicePool           Audio-Thread-exklusiv nach prepare()
      ├── voices: [SynthVoice]   (maxVoices=16, fixiert nach prepare())
      ├── params: SynthParams    (live via applyParams(), FIFO aus Queue)
      └── sampleRate: Double
```

### SynthVoice — DSP-Render-Kette (pro Sample, kein Heap)

```
Frequenz + detuneOffset (Cent)
    │
    ▼
Wellenform-Generator   (.sine / .saw / .square / .triangle)
    │  .saw/.square: PolyBLEP-Bandlimitierung
    │
    ▼
Biquad-Tiefpassfilter  (DF-II Transposed, coefficients aus calcBiquadLP())
    │  Cutoff: log 20…20 kHz | Resonanz: Q 0.5…20
    │
    ▼
ADSR-Hüllkurve         (Attack / Decay / Sustain / Release)
    │
    ▼
Constant-Power-Panning (panGainL / panGainR, berechnet bei configure())
    │
    ▼
output[L] += sample * panGainL
output[R] += sample * panGainR
```

### SynthParams — Parameter-Semantik

| Parameter | Live auf laufende Voices | Snapshot (ab nächster NoteOn) |
|-----------|--------------------------|-------------------------------|
| filterCutoff / filterResonance | ✅ | — |
| sustain | ✅ (Sustain-Stage) | — |
| attackMs / decayMs / releaseMs | — | ✅ |
| waveform | — | ✅ |
| unisonVoices / unisonDetune / unisonSpread | — | ✅ |

### Unison-Voice-Erzeugung

Bei `noteOn(note:velocity:)` spawnt `VoicePool` `unisonVoices` Stimmen:

```
t = i / (n−1)   für i ∈ [0, n−1]   (n=1 → t=0.5)

detuneOffset = (t − 0.5) × 2 × unisonDetune   [Cent]
voicePan     = (t − 0.5) × 2 × unisonSpread   [−1…+1]
gainScale    = 1 / n                            [konstante Gesamtlautstärke]
```

### SynthParams-Mapping (AudioEngine)

| ChannelFXConfig | → | SynthParams |
|-----------------|---|-------------|
| `attack` (0…1) | attack² × 2000 + 1 | `attackMs` (ms, quadratische Kurve) |
| `decay` (s) | × 1000 | `decayMs` (ms, linear) |
| `sustain` (0…1) | direkt | `sustain` |
| `release` (s) | × 1000 | `releaseMs` (ms, linear) |
| `filterCutoff` (0…1) | direkt | `filterCutoff` |
| `filterResonance` (0…1) | direkt | `filterResonance` |
| `waveform` | direkt | `waveform` |
| `unisonVoices` | direkt | `unisonVoices` |
| `unisonDetune` | direkt | `unisonDetune` |
| `unisonSpread` | direkt | `unisonSpread` |
| `pan` | → `gainX.pan` | (Mixer-Layer, nicht SynthParams) |

---

## Thread-Modell

| Thread | Verantwortlichkeit |
|--------|--------------------|
| Main Thread | SwiftUI-Updates, AppSettings-Mutationen, FlightController @Published, NoteEventQueue schreiben |
| SceneKit Render Thread | SCNScene-Lesen, Proximity-Checks, Kamera-Sync, Trigger-Logik |
| Audio Render Thread | NoteEventQueue lesen, VoicePool rendern, SynthVoice DSP |
| GCController Callback Thread | Gamepad-Input-Handler |

**Bridging Main → SceneKit:** Pending-Flags (`pendingEdgeRebuild`, `pendingNetworkReload`). SCNNode-Mutationen ausschließlich auf Render-Thread.

**Bridging Main → Audio:** `NoteEventQueue` (SPSC-Ringpuffer, lock-free). Keine Allokationen, kein Swift-Concurrency, kein AppSettings-Zugriff in der Render-Closure.

---

## Modul-Grenzen (Invarianten — Hard Stops)

Diese Regeln gelten für alle Phasen und dürfen nicht ohne explizite Freigabe gebrochen werden:

- `AppSettings.shared` ist **nicht** in Core-Dateien erlaubt:
  `MelodyEngine`, `VoiceLeadingEngine`, `ProximityTracker`, `TriggerEngine`, `WorldGeneration`, `SynthNode`, `SynthVoice`, `AudioEngine`
- `SceneKit`-Import ist **nur** in `HarmonyScene.swift` und `SceneKitView.swift` erlaubt
- `MIDIManager.shared` ist **nur** in `OutputCoordinator` und `AppModel` erlaubt
  (Ausnahme dokumentiert: `FlightController`/`GamepadController` für Sensor-CC)
- `SwiftUI`-Import ist **nicht** in Core-Dateien erlaubt
- Audio-Render-Closure: keine Heap-Allokation, kein Swift-Concurrency, kein AppSettings-Zugriff
- SceneKit-Graphmodifikationen **nur** auf dem Render-Thread (`renderer(_:updateAtTime:)`)
- Pan-Logik **nur** im Mixer-Layer (`gainX.pan` in AudioEngine) — kein Channel-Pan in SynthVoice/SynthNode
- Unison-Logik **nur** im Synth-Layer (SynthParams/VoicePool) — kein Unison-Code in AudioEngine oder darüber
- `ChannelFXConfig`-Zugriff **nur** in `AudioEngine` (Mapping via `synthParams(from:)`)
- `RuntimeHarmonik` ist **die einzige** Instanz, die `HarmonyGraphEngine` und `HarmonyScene` verbindet
- Keine Harmonieentscheidungen in `HarmonyScene` — sie rendert ausschließlich bereits entschiedene Zustände
- Keine Graphlogik (Traversierung, HarmonyLogic-Gewichtung, Kontext) außerhalb von `HarmonyGraphEngine` — HarmonyLogic bleibt vollständig in der GraphEngine gekapselt
- Keine Chunk-Generierungslogik in `RuntimeHarmonik` — Chunk-Inhalte bleiben von der Engine unbeeinflusst

---

## Key Types

### FlightState (FlightPhysics.swift)
```swift
struct FlightState {
    var position:    simd_float3
    var velocity:    simd_float3
    var orientation: simd_quatf   // Quaternion – kein Gimbal Lock, ermöglicht Loopings
}
```

### InputState (FlightPhysics.swift)
```swift
struct InputState {
    var forward, strafe, vertical: Float
    var yawDelta, pitchDelta:      Float
    var braking:                   Bool
}
```

### InputProvider (InputProvider.swift)
```swift
protocol InputProvider: AnyObject {
    var thrustFwd: Float { get }
    var thrustBwd: Float { get }
    var lookX:     Float { get }
    var lookY:     Float { get }
    var braking:   Bool  { get }
}
```
Sensor-Telemetrie (Gyro, Touchpad) ist bewusst **nicht** im Protokoll — sie ist kein Flug-Input.

### AudioOutput (AudioOutput.swift)
```swift
protocol AudioOutput: AnyObject {
    func noteOn(channel: Int, note: UInt8, velocity: UInt8)
    func noteOff(channel: Int, note: UInt8)
    func allNotesOff(channel: Int)
    func allNotesOff()
    func applyFXConfig(_ cfg: ChannelFXConfig, channel: Int)
}
```
Zwei Implementierungen: `MIDIManager` (CoreMIDI) und `AudioEngine` (interner Synth).
Wahl einmalig beim App-Start in `AppModel.makeAudioOutput()` — kein Runtime-Switching.

### SynthParams (SynthParams.swift)
```swift
struct SynthParams {
    var waveform:        Waveform  // .sine / .saw / .square / .triangle
    var attackMs:        Float     // ADSR Attack-Zeit (ms)
    var decayMs:         Float     // ADSR Decay-Zeit (ms)
    var sustain:         Float     // ADSR Sustain-Pegel (0…1)
    var releaseMs:       Float     // ADSR Release-Zeit (ms)
    var maxVoices:       Int       // Voice-Pool-Größe (fixiert nach prepare())
    var filterCutoff:    Float     // 0…1 → log. 20…20 kHz
    var filterResonance: Float     // 0…1 → Q 0.5…20
    var unisonVoices:    Int       // 1–3 Stimmen pro NoteOn
    var unisonDetune:    Float     // Verstimmung äußerster Stimmen (Cent)
    var unisonSpread:    Float     // Stereo-Verteilung der Stimmen (0…1)
}
```

### ChannelFXConfig (AppSettings.swift)
```swift
struct ChannelFXConfig {
    // Delay Taps 1–3: time, feedback, mix (send-pegel), pan
    // Reverb: preset (AVAudioUnitReverbPreset.rawValue), mix (0…1)
    // channelVolume: 0…1 → gainX.outputVolume
    // ADSR: attack (0…1 normiert), decay (s), sustain (0…1), release (s)
    // Filter: filterCutoff (0…1), filterResonance (0…1)
    // Wellenform: waveform (Waveform enum)
    // Pan: pan (−1…+1) → gainX.pan  [Mixer-Layer]
    // Unison: unisonVoices (1–3), unisonDetune (Cent), unisonSpread (0…1)  [Synth-Layer]
}
```

---

## AudioOutput-Auswahl

```
AppSettings.audio.outputMode
    ├── .midi          → MIDIManager.shared
    │                    CoreMIDI Virtual Output, zustandsloser Byte-Sender
    │                    CH0: noteOn/Off, CH1: Bass, CH2: Melodie, CH3: Chord-Tones
    │
    └── .internalAudio → AudioEngine()
                         4 unabhängige AVAudioEngine-Kanäle
                         SynthNode (VA-Synth, PolyBLEP, Biquad, ADSR, Unison)
                         Wird in AppModel gehalten; Combine-Subscription
                         für Live-Parameter-Updates (30 ms debounce)
```

Der MIDI-Eingang (Runde 073 / W-04) hängt am selben, gewählten
`AudioOutput` — er kennt den Modus nicht:

```
CoreMIDI-Thread
   ├── virtuelles Ziel "HarmonyEngine3D Input"   (DAWs, andere Programme)
   └── Eingangsport → gewählte externe Quelle    (Hardware-Controller)
                    │
                    ▼
            MIDIInputRouter  (Notenbuch je Weg, CC-Register)
                    │  ruft ausschließlich AudioOutput
                    ▼
        .midi → MIDIManager (MIDI-Thru)   |   .internalAudio → AudioEngine
                                                     │
                                          commandQueue (einziger Producer)
                                                     ▼
                                              NoteEventQueue (SPSC)
```

---

## AppSettings-Struktur

```
AppSettings (ObservableObject, Singleton)
├── flight:   FlightConfig    (thrustForce, maxSpeed, autopilot, magnet, gamepad*)
├── midi:     MIDIConfig      (velocity, channel, bassHoldMode, sensor*, gyro*, touchpad*)
├── midiInput: MIDIInputConfig (Eingang aktiv, gewählte Quelle: uniqueID + Name)
├── render:   RenderConfig    (chordRadius, portalRadius, cloudRadius, highQuality, visual*)
├── harmony:  HarmonyConfig   (networkIndex, keyCenter, enable*, energyLevel, trigger*)
└── audio:    AudioConfig
      ├── outputMode: OutputMode   (.midi / .internalAudio)
      ├── chord:     ChannelFXConfig   (CH0)
      ├── bass:      ChannelFXConfig   (CH1)
      ├── melody:    ChannelFXConfig   (CH2)
      └── chordTone: ChannelFXConfig   (CH3)
```

Alle Sub-Configs sind Value Types (`struct`). UserDefaults-Persistenz via `@Published`-Combine-Pipeline.
UI-State (`showSettingsPanel`, `showCockpitPanel`, `showControlsOverlay`) liegt **nicht** in AppSettings, sondern in `FlightController` (@Published).

---

## MIDI-Kanal-Mapping

| Kanal | Inhalt | Standard-Velocity |
|-------|--------|-------------------|
| 0 (CH0) | Akkorde (Chord) | 88 |
| 1 (CH1) | Bass | 80 |
| 2 (CH2) | Melodie | 0–88 (dynamisch) |
| 3 (CH3) | Chord-Tones (Gamepad linker Stick) | 50–127 (Stick-Magnitude) |

Sensor-CC (Gyro, Touchpad, Rotation) wird auf konfigurierbarem Kanal gesendet (`sensorMidiChannel`, Standard: 4).

**Eingang (Runde 073 / W-04, vorläufig):** eingehender MIDI-Kanal 1–4 spielt
CH0–CH3 in derselben Belegung, Kanal 5–16 spielt CH0. Velocity wird
übernommen; `noteOn` mit Velocity 0 gilt als `noteOff`.

---

## Gamepad-Layout (PS5 DualSense)

| Eingabe | Funktion |
|---------|----------|
| Linker Stick (4 Sektoren) | Chord-Tones: Root / Terz / Quinte / Septime (CH3) |
| Linker Stick (Magnitude) | Velocity 50–127 |
| L3 (Toggle) | Chord-Tone +1 Oktave |
| Rechter Stick | Yaw / Pitch (Blickrichtung) |
| R3 | Vollbremse |
| L2 / R2 | Schub rückwärts / vorwärts |
| L1 / R1 | Melodie-Preset zurück / vor |
| D-Pad oben | Bass-Mode Toggle |
| D-Pad links/rechts | Netzwerk wechseln |
| △ (Dreieck) | All Notes Off |
| OPTIONS (☰) | Steuerungsübersicht ein/aus |
| Touchpad (Swipe) | Netzwerk wechseln (alternativ) |
| Gyro | MIDI CC (Roll → CC74, Pitch → CC1) |
| Touchpad XY | MIDI CC (X → CC11, Y → CC71) |

---

## Welt-Generierung

- **Chunk-System:** Unendliche Welt via 3D-Gitter aus Chunks. Chunks werden bei Spielerannäherung geladen und bei Entfernung entladen.
- **SeededRNG:** Xorshift64-Pseudozufallsgenerator mit ChunkCoord als Seed → deterministische Welt (gleicher Seed = identische Welt). Diese Eigenschaft darf durch Refactoring nie gebrochen werden.
- **Deduplication:** Chord-Knoten werden zur Erstellungszeit dedupliziert. Orphan-Promotion verhindert Visibility-Flicker beim Chunk-Wechsel.
- **Kuratierte Modi:** Status Quo und Harmony Codex haben feste Positionen (kein Chunk-System).

---

## RuntimeHarmonik

**Implementiert seit:** 3.9.0 | **Datei:** `RuntimeHarmonik.swift` (HarmonyEngine3D)

Mittelschicht zwischen `HarmonyGraphEngine` (musikalische Logik) und `HarmonyScene` (Rendering).
Empfängt Akkord-Aktivierungs-Events, trifft strukturierte Entscheidungen, liefert `HarmonicDecision`.

**Verantwortung:**
- Konsumiert Vorschläge der `HarmonyGraphEngine` (`weightedChoice`) — die GraphEngine wendet HarmonyLogic an
- Pflegt Kontext (`recordVisit` → HarmonyLogic-Anpassung: ii-V-Boost, Rückkehr-Dämpfung)
- Filtert lokale Kandidaten (`LocalNode`-Liste von `HarmonyScene`) nach Akkordname
- Wählt deterministisch den nächstgelegenen Kandidaten (kleinste Distanz, kein Zufall)
- Liefert `HarmonicDecision` mit Vorschlag, ausgewähltem Node und Strategy-Klassifizierung
- Kein SceneKit. Kein AppSettings. Kein Audio. Kein SwiftUI.

**Aktuelle Strategy-Zustände:**

| Strategy | Bedeutung |
|---|---|
| `magnetismCandidate` | Vorschlag + passender lokaler Node vorhanden |
| `noCandidate` | Vorschlag vorhanden, aber kein passender Node im Raum |
| `noSuggestion` | GraphEngine liefert keinen Folgeakkord |

**Datentypen:**
- `LocalNode` — SceneKit-freie Darstellung eines Nodes (id, chordName, position, distance)
- `HarmonicDecision` — Ergebnis (currentChord, suggestedChord, selectedNodeID, selectedNodeDistance, strategy)

**Verdrahtung:** `OutputCoordinator.onGraphHook` → `AppModel` → `runtimeHarmonik.process()`.
`HarmonyScene` stellt `localChordNodes` bereit (Positionsberechnung dort, kein SceneKit außerhalb).

**Ausblick:** Magnetismus (Phase 4.3) konsumiert `HarmonicDecision.selectedNodeID` direkt.
Identitätswechsel bleibt Ausnahmefall für Sackgassen und Netzwerkwechsel.

> **Implementierungsstand (ab 3.9.3):** Harmonic Magnetism ist aktiv — `HarmonicDecision.selectedNodeID` wird in `HarmonyScene.applyHarmonicDecision()` in eine Weltposition (`magnetTargetPosition`) übersetzt und als `harmonicMagnetTarget` an `FlightController` übergeben. `MagnetProfile`-Feinabstimmung ausstehend.

---

## Code-Komponenten – Verantwortlichkeiten

Kurze Übersicht der zentralen Dateien: was sie tun, was sie bewusst **nicht** tun.

---

### HarmonyScene.swift
**Verantwortung:** Erzeugt und verwaltet die 3D-Welt (Chunk-System oder JSON-Web-Layout). Kennt die Positionen aller Nodes, berechnet Distanzen zur Spielerposition und setzt `magnetTargetPosition` aus einer eingehenden `HarmonicDecision`. Als Eventquelle liefert sie On/Off-Symmetrie: `chordOutputNotes`/`bassOutputNotes` snapshotten die tatsächlich oktavverschobenen MIDI-Noten bei Aktivierung; das Deaktivierungs-Event liest ausschließlich diesen Snapshot (Phase 3.9.1a) — nie aus der aktuellen `AppSettings`-Oktavlage rekonstruiert.

**Nicht zuständig für:** Harmonieentscheidungen, musikalische Logik, Netzwerk-Traversierung. Die Scene rendert bereits getroffene Entscheidungen — sie trifft keine eigenen.

---

### RuntimeHarmonik.swift
**Verantwortung:** Zentrale musikalische Entscheidungsinstanz. Konsumiert Akkord-Aktivierungen, pflegt den harmonischen Kontext (`recordVisit`), wertet `HarmonyGraphEngine` aus und liefert als Ergebnis eine `HarmonicDecision`.

**Nicht zuständig für:** Räumliche Positionierung, Rendering, SceneKit, Audio. Kennt Akkordnamen und Distanzen (`LocalNode`) — keine Weltkoordinaten im eigentlichen Sinne, nur skalare Abstände.

---

### HarmonyGraphEngine (HarmonyShared)
**Verantwortung:** Wertet das HarmonyModel (Network + Logic) aus. Berechnet kontextgewichtete Nachfolger (`weightedChoice`), pflegt harmonische Regeln (ii-V-Boost, Rückkehr-Dämpfung) und liefert Vorschläge.

**Nicht zuständig für:** Raumkoordinaten, SceneKit, MIDI, Rendering. Lebt in `HarmonyShared` und kennt keine Scene.

---

### FlightController.swift
**Verantwortung:** Koordiniert Flugphysik und Spielerbewegung. Liest `InputProvider`, führt `FlightPhysics.update()` aus, wendet `harmonicMagnetTarget` (Harmonic Magnetism) und proximity-basierten Nudge an.

**Nicht zuständig für:** Harmonieentscheidungen, Akkordlogik, MIDI-Output. Empfängt Ziele — entscheidet nicht, welche Ziele musikalisch sinnvoll sind.

---

### OutputCoordinator.swift
**Verantwortung:** Verbindet `HarmonyScene` (Trigger-Events) mit `AudioOutput` (MIDI/Audio). Leitet `onChordActivated`, `onBassNoteOn`, `onMelodyNote` etc. an die konfigurierte Ausgabe weiter. Hält `onGraphHook` als Einstiegspunkt für RuntimeHarmonik. Für alle vier Kanäle (CH0–CH3) reiner Durchreicher ohne eigenes Note-Tracking (seit Phase 3.9.1a auch für CH0/CH1) — Octave-Shift wird nicht mehr live neu angewendet, sondern kommt bereits aufgelöst von der Eventquelle.

**Nicht zuständig für:** Harmonieentscheidungen, Flugphysik, Rendering.

---

### HarmonicDebugModel.swift
**Verantwortung:** Passiver Datencontainer für das Debug-Radar. Wird ausschließlich vom AppModel beschrieben (immer auf dem Main Thread). Hält zwei Datenströme getrennt: kontinuierliche Positionsdaten (~10 Hz) und ereignisbasierte Entscheidungsdaten (bei Akkord-Aktivierung).

**Nicht zuständig für:** Jegliche Logik. Keine Entscheidungen, keine Berechnungen, kein SceneKit.

---

### HarmonicRadarView.swift
**Verantwortung:** Reine Debug-Visualisierung. Liest `HarmonicDebugModel` und stellt lokale Nodes, Spielerposition, Magnet-Ziel und letzte `HarmonicDecision` als Radar-Draufsicht dar.

**Nicht zuständig für:** Jegliche Logik. Kein SceneKit, keine Harmonieentscheidungen, kein AppSettings.

---

### HarmonyEngine3DApp.swift / AppModel
**Verantwortung:** App-Schicht. Erstellt alle langlebigen Objekte (`HarmonyScene`, `FlightController`, `OutputCoordinator`, `HarmonicDebugModel`), wählt den `AudioOutput` und verdrahtet alle Hooks:
- `onGraphHook` → RuntimeHarmonik → `applyHarmonicDecision` → `magnetTargetPosition`
- `onRadarSnapshot` → `HarmonicDebugModel` (kontinuierlich)

**Nicht zuständig für:** Harmonielogik, Rendering, Audio-DSP. Orchestriert — entscheidet und rendert nicht.

---

## Bekannte Restkopplungen

| Kopplung | Ort | Geplante Auflösung |
|----------|-----|--------------------|
| `GamepadController.shared` in `processSensors()` | `FlightController.swift` | Sensor-Telemetrie bewusst außerhalb InputProvider — kein Refactoring geplant |
| `MIDIManager.shared` in `FlightController`/`GamepadController` | Sensor-CC | Dokumentierte Ausnahme (CLAUDE.md) |
| `HarmonyScene` mixes Rendering + Proximity + WorldGen | `HarmonyScene.swift` | ChunkLogic Sub-Steps A+B erledigt (`ChunkLogic.swift`, `ChunkData`, `buildNodes`); vollständige Trennung (Phase 1 → HarmonyCore) folgt nach v1-Netzwerkmodell |
| ~~`graphSuggest`-Bias in `loadChunk`~~ | ~~`HarmonyScene.swift`~~ | **Behoben (3.9.1)** — entfernt; Chunk-Generierung wieder unbeeinflusst von GraphEngine |
| ~~CH0/CH1 Octave-Shift live in `OutputCoordinator` neu berechnet~~ | ~~`OutputCoordinator.swift`~~ | **Behoben (3.9.9, Phase 3.9.1a)** — Shift wird einmalig in `HarmonyScene` gesnapshottet; `OutputCoordinator` reiner Durchreicher, keine hängenden Noten mehr bei Shift-Änderung während eine Note klingt |
| ~~Nichtdeterministische Kandidatenauswahl bei Distanz-Gleichstand~~ | ~~`RuntimeHarmonik.swift`~~ | **Behoben (3.9.9, Phase 3.9.1b)** — stabiler Tie-Break nach `(distance, id)` |
| ~~Harmonischer Magnet framerate-abhängig (feste 85/15-Mischung)~~ | ~~`FlightController.swift`~~ | **Behoben (3.9.9, Phase 3.9.1c)** — zeitbasiert via `alpha = 1 - exp(-rate·dt)` |
| `ContentView` 1283 Zeilen | `ContentView.swift` | Refactoring in Sub-Views (geplant) |
| `FlightController` an `SCNNode` gebunden | `FlightController.swift` | FlightState/FlightPhysics ohne SCNNode (geplant) |
| Zwei MIDIManager-Implementierungen | HarmonyEngine3D + DesignerKit | Vereinheitlichung in HarmonyShared (geplant) |

---

## Offene Architektur-Aufgaben (priorisiert)

### Hoch
- **Invisible Chord Trigger:** Unsichtbare Knoten (opacity=0) triggern noch MIDI — Proximity-Check muss opacity prüfen
- **FlightPhysics entkoppeln:** `FlightController` noch an `SCNNode` gebunden; `FlightState`/`FlightPhysics`-Struct ohne SceneKit-Abhängigkeit

### Mittel
- **ChunkMap-Extraktion (teilweise erledigt):** Sub-Steps A+B abgeschlossen (`ChunkLogic.swift` mit `ChunkData`, `computeChunkData`, `buildNodes`). Vollständige Entkopplung (Phase 1 → HarmonyCore) folgt nach v1-Netzwerkmodell.
- **MIDIManager vereinheitlichen:** Zwei Implementierungen (3D + Designer) in HarmonyShared
- **AppSettings AudioConfig:** `ChannelFXConfig`-Kommentar zu `filterResonance` auf Q 0.5…20 aktualisieren

### Synth-Ausbau (geplant)
- **Envelope-gesteuerter Filter:** Zweiter ADSR-Block in `SynthVoice` moduliert Biquad-Cutoff unabhängig von Amp-Hüllkurve. Neue SynthParams-Felder: `filterEnvAttack/Decay/Sustain/Release/Depth`. Mixer-Sektion "FILTER ENV".

---

## DesignerKit (2D-Navigator)

Separater App-Scope. Läuft als eigenständige macOS-App im selben SPM-Package.

```
DesignerApp            @main Entry-Point
DesignerViewModel      State, Force-Layout, Autopilot-Navigation, MIDI-Clock
DesignerCanvasView     2D-Canvas (Chord-Netzwerk, Force-Layout-Visualisierung)
DesignerGamepad        Gamepad-Input für 2D-Navigation
MIDIManager            Eigene CoreMIDI-Implementierung (Vereinheitlichung geplant)
```

Teilt `HarmonyShared` (NetworkParser, AutopilotEngine, Datenmodelle) mit `HarmonyEngine3D`.

---

## Akkord-Namenskonvention

**Verbindlich für alle HarmonyWebs, `HarmonyNode.id`, `LocalNode.chordName`, RuntimeHarmonik-Vergleiche und Debug-Anzeige.**

### Grundtöne
Großbuchstabe: `C  D  E  F  G  A  B`

### Vorzeichen (direkt an den Grundton, kein Leerzeichen)
- Erniedrigung: kleines `b` → `Db  Eb  Gb  Ab  Bb`
- Erhöhung: `#` → `C#  D#  F#  G#  A#`

Keine alternativen Symbole: kein `♭`, kein `♯`, kein `es`/`is`.

### Akkordtypen (Suffix direkt an den Grundton)

| Typ | Suffix | Beispiele |
|---|---|---|
| Dur-Dreiklang | *(kein Suffix)* | `C`  `G`  `Bb` |
| Moll-Dreiklang | `m` | `Am`  `Dm`  `F#m` |
| Dur-Dreiklang (explizit) | `maj` | `Fmaj`  `Ebmaj` — nur wenn Dreikling in Septakkord-Kontext unklar |
| Dur-Septakkord | `maj7` | `Cmaj7`  `Fmaj7`  `Bbmaj7` |
| Dominant-Septakkord | `7` | `G7`  `A7`  `Db7` |
| Moll-Septakkord | `m7` | `Dm7`  `Am7`  `F#m7` |
| Halbvermindert | `m7b5` | `Bm7b5`  `Em7b5`  `C#m7b5` |
| Vollvermindert (Septakkord) | `dim7` | `Bdim7`  `F#dim7` |
| Vollvermindert (Dreiklang) | `dim` | `Bdim`  `Fdim` |

### Erweiterungen (falls gebraucht)
Direkt anhängen, kein Leerzeichen: `Cmaj9`  `G7sus4`  `Am11`

### Keine Leerzeichen in Namen. Namen sind case-sensitiv. Nie `Δ`, `ø`, `°`.

---

## Glossar – Harmonie-System

**HarmonyNetwork**
Eine vollständige Menge von Akkorden und den möglichen Verbindungen zwischen ihnen. Das Netzwerk beschreibt ausschließlich Struktur: welche Akkorde existieren, welche Übergänge möglich sind, ob eine Verbindung gerichtet ist und welches Gewicht sie trägt. Es bewertet nicht, ob ein Übergang musikalisch sinnvoll ist — das ist Aufgabe der HarmonyLogic. Wie das Netzwerk gespeichert oder übertragen wird (Datei, Format, Encoding), ist eine Implementierungsrealität, nicht Teil des Begriffs.

**HarmonyLogic**
Die musikalische Intelligenz eines Netzwerks. Sie legt fest, wie sinnvoll oder wahrscheinlich ein bestimmter Akkordwechsel ist — zum Beispiel, dass ein Dominantakkord typischerweise zur Tonika auflöst, oder dass nach einer ii-V-Bewegung häufig die I-Auflösung folgt. Die HarmonyLogic entscheidet nichts alleine — sie liefert die Bewertungsgrundlage für die HarmonyGraphEngine.

**HarmonyModel / HarmonyMap**
Die konkrete, geladene Instanz eines HarmonyNetwork im Arbeitsspeicher — die maschinenlesbare Form des gesamten Harmonie-Systems zu einem bestimmten Zeitpunkt. Sie enthält nicht nur die Struktur (welche Akkorde existieren, welche Übergänge möglich sind), sondern auch alle Metadaten, Layer-Definitionen und Magnetprofile, die für harmonische Berechnungen benötigt werden. Alle Komponenten, die harmonisch denken — HarmonyGraphEngine, RuntimeHarmonik, Autopilot — arbeiten ausschließlich auf dieser Instanz, nie auf Rohdaten.

**HarmonyGraphEngine**
Das Rechenwerk, das auf Grundlage der HarmonyLogic entscheidet, welcher Akkord als nächstes vorgeschlagen werden soll. Es kennt die gesamte Spielhistorie — welche Akkorde in welcher Reihenfolge aktiviert wurden — und passt seine Vorschläge entsprechend an: Eine klassische ii-V-Bewegung im Verlauf erhöht zum Beispiel die Wahrscheinlichkeit der I-Auflösung. Die Engine kennt ausschließlich Akkordnamen und Bewertungen — keinen Raum, keine Positionen, keine Entfernungen.

**ChordNode (Modell)**
Ein einzelner Akkord als reiner Datensatz: sein Name (z. B. „Cmaj7"), sein Grundton, sein Typ (Dur, Moll, Dominant …), seine harmonische Funktion (Tonika, Dominante …) und die genauen MIDI-Noten, die er enthält. Das ist die abstrakte Datenschicht — noch kein sichtbares Objekt in der 3D-Welt.

**ChordNode (Szene)**
Ein Akkord als physisch sichtbares, schwebendes Objekt in der 3D-Welt. Es reagiert auf Annäherung: Kommt der Spieler nahe genug heran, wird der Akkord ausgelöst — die Noten erklingen. Die sichtbare und klangliche Entsprechung des Datensatzes, der im Modell existiert.

**HarmonySpace / HarmonyScene**
Der gesamte dreidimensionale Raum, den der Spieler durchfliegt. Er enthält alle sichtbaren Akkord-Objekte, Verbindungslinien zwischen ihnen, Portale und Wolken. Die Scene ist das, was der Spieler sieht — und sie übersetzt abstrakte Musiktheorie in eine räumlich erfahrbare Umgebung.

**Runtime**
Das Verhalten des Systems während der Ausführung — im Gegensatz zu den statischen Daten, die das System beschreiben. Ein HarmonyNetwork legt fest, welche Übergänge möglich sind; HarmonyLogic legt fest, nach welchen Regeln sie bewertet werden; das HarmonyWeb fasst beides als Datei zusammen. Die Runtime ist das, was daraus beim tatsächlichen Spielen wird: konkrete Entscheidungen, Bewegungseinflüsse und musikalische Vorschläge, die sekündlich aus diesen Daten berechnet werden. DesignerKit zeigt die Datenstruktur eines HarmonyWebs — es hat keine Runtime; es gibt kein Spielgeschehen, keine Kontextgeschichte, keinen Spieler im Raum.

An der Runtime beteiligt sind vier Komponenten: `HarmonyGraphEngine` berechnet, welcher Akkord als nächstes musikalisch passt — auf Basis der aktuellen Spielhistorie und aller konfigurierten Kontextmechanismen. `RuntimeHarmonik` übersetzt diesen Vorschlag in eine räumliche Entscheidung: sie sucht im lokalen Node-Set den passenden Akkord und benennt das nächstgelegene Objekt als Ziel. `HarmonyScene` macht die Entscheidung sichtbar — sie setzt das Magnetfeld auf das genannte Objekt, verändert aber selbst nichts an der Auswahl. `FlightController` wendet den Magnetismus auf die Flugbewegung an.

Entscheidend: die Runtime verändert die Datenstruktur nicht. Die JSON-Datei bleibt beim Spielen unverändert. Was sich ändert, ist ausschließlich die Interpretation — welche Kante im Kontext der letzten Akkorde gerade die höchste Priorität hat, welches Objekt im Raum als nächstes Ziel gilt, wie stark der Spieler in eine Richtung gezogen wird.

**RuntimeHarmonik**
Die Schaltzentrale zwischen Musiktheorie und Spielraum. Immer wenn ein Akkord ausgelöst wird, wird RuntimeHarmonik aktiv: Sie fragt die HarmonyGraphEngine, welcher Akkord als nächstes musikalisch sinnvoll wäre, sucht in der Umgebung des Spielers nach einem passenden Akkord-Objekt und wählt das nächstgelegene aus. Das Ergebnis ist eine klare Empfehlung — die HarmonicDecision. RuntimeHarmonik entscheidet, handelt aber nicht selbst: Weder spielt sie Noten ab, noch bewegt sie die Kamera.

**HarmonicDecision**
Die Empfehlung, die RuntimeHarmonik nach jeder Akkord-Aktivierung ausspricht. Sie beantwortet drei Fragen gleichzeitig: Welcher Akkord wäre jetzt musikalisch sinnvoll? Welches konkrete Objekt im Raum entspricht diesem Akkord und liegt am nächsten? Wie ist die aktuelle Situation zu bewerten? Die Entscheidung ist unveränderlich — pro Akkord-Aktivierung entsteht eine neue.

Konkrete Inhalte:
- `suggestedChord` — Name des musikalisch empfohlenen Folgeakkords
- `selectedNodeID` — Kennung des nächstgelegenen passenden Objekts im Raum, das als Magnet-Ziel dient
- `selectedNodeDistance` — Entfernung zu diesem Objekt in Welt-Einheiten
- `strategy` — Einschätzung der Situation: alles passt / Vorschlag vorhanden aber kein Objekt in Reichweite / kein sinnvoller nächster Schritt (siehe Strategy)

**Strategy (HarmonicStrategy)**
Eine kurze Einschätzung, wie erfolgreich die aktuelle harmonische Entscheidung ausfällt — immer einer von drei Zuständen:
- `magnetismCandidate` — alles passt: ein musikalisch sinnvoller Akkord wurde gefunden und sein Objekt im Raum als Ziel gesetzt
- `noCandidate` — ein Akkord wäre sinnvoll, aber kein passendes Objekt ist gerade in der Nähe
- `noSuggestion` — das Netzwerk kennt für den zuletzt gespielten Akkord keinen sinnvollen nächsten Schritt

**Local Node Set**
Die Momentaufnahme aller Akkord-Objekte, die gerade im Raum um den Spieler herum geladen sind — jeweils mit ihrer aktuellen Entfernung. RuntimeHarmonik nutzt diese Liste, um aus den Vorschlägen der Harmonielogik das räumlich nächstgelegene passende Objekt auszuwählen. Die Liste kommt als reiner Datensatz, ohne jede Abhängigkeit zur 3D-Engine.

**Navigation / Traversal**
Zwei parallele Bewegungen gleichzeitig: Der Spieler fliegt physisch durch den Raum (Navigation), und das Harmoniesystem verfolgt die musikalische Abfolge der gespielten Akkorde (Traversal). Beide laufen unabhängig — der Spieler fliegt frei, und die Harmonielogik beobachtet dabei, welche Akkorde in welcher Reihenfolge aktiviert werden.

---

### Welt-Ebene

**Chunk**
Ein würfelförmiger Abschnitt der 3D-Welt. Die gesamte, theoretisch unendliche Welt ist in solche gleichgroßen Würfel eingeteilt. Was genau in einem Würfel liegt — ein Akkord-Objekt, ein Bass-Portal, eine Melodie-Wolke, oder gar nichts — ist vollständig durch seine Position in der Welt festgelegt. Es gibt keinen echten Zufall: Dieselbe Würfelposition ergibt immer denselben Inhalt.

**Chunk-System**
Das Verfahren, mit dem die 3D-Welt trotz potenziell unendlicher Größe effizient im Arbeitsspeicher gehalten wird. Immer nur die Würfel rund um den Spieler sind aktiv geladen. Bewegt sich der Spieler, werden neue Würfel vorne geladen und alte hinten entfernt. Um Leistungseinbrüche zu vermeiden, werden pro Einzelbild nur wenige neue Objekte hinzugefügt. Aktiv nur im Standard-Flugmodus — im Kuratierten Modus und im JSON-Web-Modus ist das System ausgeschaltet.

**SeededRNG**
Ein Zufallsgenerator, der bei gleicher Eingabe immer dasselbe Ergebnis liefert — kein echter Zufall. Die Eingabe ist die Position des jeweiligen Würfels in der Welt. Das garantiert: Dieselbe Welt entsteht immer wieder, egal in welcher Reihenfolge der Spieler sie erkundet. Dieses Prinzip ist ein bewusst geschütztes Merkmal des Systems — es darf durch Programmänderungen nie gebrochen werden.

**Kuratierter Modus**
Ein Sondermodus, in dem keine automatisch generierte Welt geladen wird, sondern eine handgefertigte Szene mit wenigen, absichtlich platzierten Objekten. Zwei Varianten: „Status Quo" (vier Akkorde in Dreiecks-Aufstellung, benannt nach der gleichnamigen Band) und „Harmony Codex" (24 Akkorde auf einer Kreisbahn, benannt nach dem Steven-Wilson-Album). Das Chunk-System ist dabei vollständig deaktiviert.

**JSON-Web-Modus**
Ein Entwicklungs- und Vorführmodus, in dem die 3D-Welt direkt aus einer Netzwerk-Datei (JSON-Format) aufgebaut wird, statt durch das prozedurale Chunk-System. Die Akkorde aus der Datei werden gleichmäßig auf einem Ring im Raum platziert. Die Netzwerkauswahl im Einstellungsfenster ist dabei ohne Wirkung. Beim aktuellen App-Start ist dieser Modus aktiv.

**Bass-Portal**
Ein ringförmiges Objekt in der Welt, das beim Durchfliegen einen Basston auslöst (MIDI-Kanal 1). Jedes Portal ist einem festen Tonwert zugeordnet, der sich aus seiner Position in der Welt ergibt. Der tatsächliche Trefferbereich ist eine unsichtbare Kugel um den Mittelpunkt des Rings — nicht der sichtbare Ring selbst. Diese Trennung ist bewusst: Das visuelle Erscheinungsbild und der auslösende Bereich sind voneinander unabhängig.

**Melodie-Wolke**
Ein Wolken-Objekt in der Welt, das beim Eintreten eine laufende Melodie startet (MIDI-Kanal 2). Die Melodie spielt, solange der Spieler im Wirkungsbereich der Wolke bleibt. Tonart und Melodieverhalten ergeben sich aus der Position der Wolke in der Welt. Verlässt der Spieler die Wolke, stoppt die Melodie sofort.

---

### Interaktion

**Trigger Zone**
Der unsichtbare Wirkungsbereich um ein Akkord-Objekt, bei dessen Betreten der Akkord ausgelöst wird — die Noten erklingen, und das Harmoniesystem wird informiert. Pro Kanal (Akkord, Bass, Melodie) ist immer höchstens ein Objekt gleichzeitig aktiv. Das Verlassen des Bereichs beendet die Noten sofort. Der Übergang von „inaktiv" zu „aktiv" ist eindeutig definiert und tritt nie für mehrere Objekte desselben Kanals gleichzeitig ein.

**Annäherungszone (Approach Zone)**
Ein größerer unsichtbarer Bereich um ein Objekt — dreimal so weit wie die Trigger Zone. Beim Eintreten passiert noch nichts Klangliches: Das Objekt beginnt zu leuchten, der Akkordname erscheint im Cockpit-Display, und die Einzeltöne des Akkords werden für den linken Gamepad-Stick vorbereitet. Ein frühes räumliches Signal: „Du näherst dich einem Akkord."

---

### Datentypen und Brücken

**LocalNode**
Eine vereinfachte Darstellung eines Akkord-Objekts, die vollständig ohne die 3D-Engine auskommt: nur Kennung, Akkordname, Position im Raum und aktuelle Entfernung zum Spieler. Dieser Typ ist die Schnittstelle zwischen dem 3D-System und der Harmonielogik — RuntimeHarmonik kann damit arbeiten, ohne selbst in die 3D-Engine eingreifen zu müssen.

**Layer (HarmonyLayer)**
Eine benannte Gruppe von Verbindungen im Netzwerk. Jede Verbindung zwischen zwei Akkorden kann zu einem oder mehreren Layern gehören — zum Beispiel „functional" für klassische Akkordverbindungen oder „modal" für modale Bezüge. Die Harmonielogik kann auf einen bestimmten Layer beschränkt werden: Dann berücksichtigt sie nur die Verbindungen dieser Gruppe. So lassen sich verschiedene harmonische Verhaltensweisen im selben Netzwerk unterbringen, ohne Daten zu duplizieren.

**onGraphHook**
Eine einzelne, klar definierte Übergabestelle zwischen zwei Systemebenen. Immer wenn ein Akkord ausgelöst wird, wird dieser Punkt durchlaufen und der Akkordname weitergegeben. Darüber erhält das Harmoniesystem die Information, dass ein neuer Akkord gespielt wurde. Die Verbindung wird beim App-Start eingerichtet — die beiden Seiten kennen sich nicht direkt, dieser Punkt ist das einzige Band zwischen ihnen.

---

### Technische Konzepte

**Pending Flag**
Ein Sicherheitsmechanismus für die Zusammenarbeit zwischen verschiedenen Teilen des Programms. Das Programm arbeitet gleichzeitig in mehreren Bereichen: einem für die Benutzeroberfläche, einem für die 3D-Darstellung. Die 3D-Engine darf nur von ihrem eigenen Zeichnungsprozess verändert werden. Wenn die Oberfläche eine Änderung anfordert (z. B. „lade ein neues Netzwerk"), wird sie nicht sofort ausgeführt, sondern als „ausstehend" vorgemerkt. Der Zeichnungsprozess erledigt die Änderung beim nächsten Durchlauf. Dieses Muster darf nicht umgangen werden.

**AudioOutput (Protokoll)**
Eine gemeinsame Schnittstelle, die festlegt, was ein Klangausgabe-System leisten muss: Noten starten, Noten stoppen, alle Noten auf einmal stoppen, Klangparameter setzen. Was konkret dahinter steckt, ist dem Rest des Systems gleichgültig. Es gibt zwei Implementierungen: MIDI (sendet Signale an externe Synthesizer und DAWs) und den internen Synthesizer. Die Wahl wird einmalig beim Start getroffen und kann zur Laufzeit nicht geändert werden. Der Rest des Systems spricht immer nur mit dieser Schnittstelle, nie direkt mit der konkreten Implementierung.

---

### Musiktheorie

**Voice Leading**
Eine musikalische Technik, die dafür sorgt, dass der Übergang zwischen zwei Akkorden möglichst fließend klingt. Die einzelnen Töne eines neuen Akkords werden in ihrer Oktavlage so angepasst, dass jeder Ton möglichst wenig Weg zum entsprechenden Ton des vorherigen Akkords hat. Das Ergebnis: Akkorde fließen ineinander über, statt zu springen. Kann im Einstellungsfenster aktiviert oder deaktiviert werden.

**Kontext-Modulation (Traversal Context)**
Die Fähigkeit der Harmonielogik, sich an die bisherige Spielhistorie anzupassen. Das System merkt sich, welche Akkorde in welcher Reihenfolge gespielt wurden. Das führt zu zwei Effekten: Klassische Akkordfolgen (z. B. ii-V) werden wahrscheinlicher, wenn ihre erste Hälfte bereits gespielt wurde — die I-Auflösung liegt dann gewissermaßen „in der Luft". Akkorde, die gerade erst gespielt wurden, werden kurzfristig unwahrscheinlicher, um Kreisbewegungen im Netzwerk zu vermeiden. Das Ergebnis klingt musikalisch kohärent, ohne starren Regeln zu folgen.

**Bewertungsmechanismen**
Der Oberbegriff für alle Verfahren, die möglichen Akkordübergängen unterschiedliches Gewicht geben — ohne dabei den bisherigen Spielverlauf zu berücksichtigen. Zu den Bewertungsmechanismen gehören: Kantengewichte (Grundgewicht eines Übergangs), Relation Types (musikalische Beziehungskategorie), Layer (strukturelle Filterung des gültigen Kantenraums) und stilistische Gewichtungen. Sie liefern stabile Grundtendenzen, die unabhängig davon gelten, was zuletzt gespielt wurde. Kontextmechanismen setzen auf dieser Grundbewertung auf.

**Kontextmechanismen**
Der Oberbegriff für alle Verfahren, die die Grundbewertung eines Übergangs anhand des bisherigen Spielverlaufs verändern. Ein Kontextmechanismus beobachtet den Akkordverlaufskontext und verschiebt Wahrscheinlichkeiten dynamisch: Klassische Akkordfolgen werden wahrscheinlicher, kürzlich gespielte Akkorde werden gedämpft. Im Unterschied zu Bewertungsmechanismen wirken Kontextmechanismen nicht dauerhaft — ihre Wirkung hängt vollständig davon ab, was im Verlauf steht.

**Kontexttiefe**
Die Anzahl zuvor aktivierter Akkorde, die bei einer Entscheidung berücksichtigt werden. Kontexttiefe 1 bedeutet: nur der unmittelbar vorherige Akkord fließt ein. Kontexttiefe 2 berücksichtigt die letzten zwei Akkorde — damit können Muster wie ii-V erkannt werden, bevor die erwartete I-Auflösung verstärkt wird. Eine höhere Kontexttiefe erhöht die musikalische Kohärenz, verlangt aber entsprechend mehr Spielhistorie, um wirksam zu werden.

**Akkordverlaufskontext**
Die tatsächlich gespeicherte Abfolge der zuletzt aktivierten Akkorde — die Grundlage, auf der alle Kontextmechanismen arbeiten. Enthält die Namen der letzten N Akkorde in zeitlicher Reihenfolge. Ohne diesen Verlauf wäre jede harmonische Entscheidung zustandslos: Der Akkordverlaufskontext ist das Gedächtnis des Harmoniesystems.

**Web-spezifische HarmonyLogic**
Bewertungs- und Kontextmechanismen gelten nicht automatisch für jedes HarmonyWeb in gleicher Weise. Ein funktionales Web (klassische tonale Harmonik, klare Auflösungstendenzen) braucht andere aktive Mechanismen als ein modales, ein Blues- oder ein riemannianisches Web. Die HarmonyLogic ist deshalb nicht als starre globale Einheitslogik gedacht, sondern als an das jeweilige Web angepasste musikalische Intelligenz: Welche Mechanismen aktiv sind, welche Gewichte sie tragen und welche Kontexttiefe sinnvoll ist, hängt vom HarmonyWeb ab — nicht vom System als Ganzem.

---

**Magnetismus (Phase 4.3)**
Ein Mechanismus, bei dem die harmonische Entscheidung eine subtile räumliche Wirkung entfaltet: Der empfohlene nächste Akkord zieht den Spieler leicht in seine Richtung. Stärke und Reichweite sollen später über vordefinierte Profile konfigurierbar werden. Der Kern des Mechanismus ist seit Version 3.9.3 aktiv — die Feinabstimmung der Profile steht noch aus.

> **Implementierungsstand (ab 3.9.3):** Die 3D-Szene setzt die Zielposition aus dem von RuntimeHarmonik ausgewählten Objekt, und der Flugcontroller wendet einen sanften Geschwindigkeitsschub in Richtung dieses Ziels an. Präzise Unterscheidung: dieser Mechanismus ist **Harmonic Magnetism** (ein Ziel, harmonisch bestimmt) — zu unterscheiden vom **Proximity Nudge** (mehrere Objekte gleichzeitig, rein geometrisch). Profil-Feinabstimmung steht noch aus.

**Harmonic Magnetism**
Die harmonisch gesteuerte Anziehungskraft auf den empfohlenen nächsten Akkord. Wenn RuntimeHarmonik ein passendes Akkord-Objekt in der Nähe gefunden hat, zieht es den Spieler sanft in seine Richtung — nicht als Zwang, sondern als Einladung. Es gibt immer genau ein aktives Ziel. Die Richtung ergibt sich aus einer HarmonicDecision, bei der ein passender Akkord im Raum vorhanden ist.

**Proximity Nudge**
Ein räumlicher Einfluss, der völlig unabhängig von der Harmonielogik wirkt: Akkord-Objekte in der Nähe des Spielers üben einen leichten Sog aus — allein aufgrund ihrer Entfernung. Dieser Mechanismus kennt keine Akkordnamen, keine Netzwerkverbindungen und keine harmonischen Entscheidungen. Mehrere Objekte können gleichzeitig wirken. Läuft parallel zum Harmonic Magnetism, hat aber einen anderen Ursprung und eine andere Wirkungsweise.

**Magnet Target**
Die genaue Position in der 3D-Welt, auf die der Harmonic Magnetism im Moment zieht. Sie ist kein gespeicherter Wert, sondern wird bei jeder Abfrage frisch berechnet: Die 3D-Szene ermittelt anhand der gespeicherten Node-ID, wo das ausgewählte Akkord-Objekt gerade im Raum steht. Ist das Objekt nicht mehr geladen, gibt es automatisch keinen Wert zurück — es muss nichts explizit gelöscht werden. Ist kein Magnet-Ziel aktiv — weil keine passende harmonische Entscheidung vorliegt — ist dieser Wert ebenfalls leer. Einzige gespeicherte Größe ist die Node-ID (`currentMagnetNodeID`); die Position ergibt sich daraus.

---

> **Klarstellung — zwei Einflusskräfte auf die Flugbewegung:**
> Der **Harmonic Magnetism** arbeitet zielbasiert — immer genau ein Ziel, harmonisch bestimmt durch RuntimeHarmonik. Der **Proximity Nudge** wirkt geometrisch — mehrere Objekte gleichzeitig, ausschließlich auf Basis von Entfernung. Beide Mechanismen können gleichzeitig aktiv sein und wirken unabhängig voneinander.

---

> `HarmonyNetwork` definiert Möglichkeiten — `HarmonyLogic` bewertet sie: Bewertungsmechanismen liefern Grundtendenzen, Kontextmechanismen modifizieren sie anhand des Akkordverlaufskontexts. Das `HarmonyModel` vereint Struktur und Logik zur konkreten Instanz eines HarmonyWeb — die GraphEngine wählt, RuntimeHarmonik übersetzt die Entscheidung in den Raum, und die Scene macht es erlebbar.

---

## Aktuell implementierte HarmonyLogic-Mechanismen

Dokumentiert den Stand der in `HarmonyGraphEngine` implementierten Bewertungs- und Kontextmechanismen.

### Bewertungsmechanismen (zustandslos)

**Kantengewichte**
Jeder Übergang zwischen zwei Akkorden besitzt ein Grundgewicht, das in der Netzwerkdefinition hinterlegt ist. Dieses Gewicht ist die Basisbewertung: Ein höher gewichteter Übergang wird häufiger vorgeschlagen als ein niedriger gewichteter — unabhängig davon, was zuletzt gespielt wurde. Kantengewichte sind der stabilste Bewertungsmechanismus; sie verändern sich nicht mit der Spielhistorie.
*Ebene: Grundbewertung.*

**Relation Types**
Jede Verbindung zwischen zwei Akkorden trägt eine oder mehrere semantische Kategorien: `V-I` (Dominante → Tonika), `ii-V` (Subdominante → Dominante), `relMajMin` (Parallel-Dur/Moll), `parallelMajMin`, `commonTone` (gemeinsamer Ton), `tritSubst` (Tritonussubstitution). Diese Kategorien beschreiben die musikalische Natur eines Übergangs. Die HarmonyGraphEngine kann auf bestimmte Relation Types filtern oder sie gezielt unterschiedlich gewichten.
*Ebene: Grundbewertung. Musikalische Eignung ist web-spezifisch.*

**Layer**
Verbindungen sind einem oder mehreren Layern zugeordnet — zum Beispiel `functional` (tonale Harmonik) oder `modal` (modale Bezüge). Die Harmonielogik kann auf einen bestimmten Layer beschränkt werden: Dann werden ausschließlich Verbindungen dieses Layers berücksichtigt. Layer ermöglichen es, im selben Netzwerk verschiedene harmonische Verhaltensweisen zu speichern, ohne Daten zu duplizieren.
*Ebene: Grundbewertung / Filterung. Welcher Layer aktiv ist, ist web-spezifisch.*

---

### Kontextmechanismen (verlaufsabhängig)

**ii-V-Boost**
Wenn der Akkordverlaufskontext eine klassische ii-V-Bewegung zeigt, wird die Wahrscheinlichkeit der erwarteten I-Auflösung erhöht. Der Mechanismus erkennt dieses Muster und verstärkt gezielt den Folgeschritt. Wirkt auf Kontexttiefe 2 (letzter + vorletzter Akkord).
*Ebene: Kontext. In einem modalen oder Blues-Web wäre dieser Boost gegebenenfalls nicht sinnvoll aktiv.*

**Rückkehr-Dämpfung**
Kürzlich gespielte Akkorde werden vorübergehend in ihrer Bewertung abgesenkt, um unmittelbare Schleifenbewegungen (A→B→A→B) zu vermeiden. Die Dämpfung klingt mit der Zeit ab — ein Akkord, der mehrere Schritte zurückliegt, ist nicht dauerhaft unattraktiv.
*Ebene: Kontext. In einem Riff-basierten Web, das Wiederholung ausdrücklich erwünscht, wäre dieser Mechanismus entsprechend zu gewichten.*

**Spannungserhalt / Spannungswechsel**
Nicht jede Entscheidung soll sofort die direkteste harmonische Auflösung erzwingen. Schwächere Alternativen können relativ attraktiver werden, um Spannung zu halten oder den harmonischen Verlauf interessant zu gestalten. Dieser Mechanismus arbeitet auf der Gewichtungsebene: Er verschiebt Wahrscheinlichkeiten, entscheidet aber nicht selbst.
*Ebene: Kontext / Gewichtungsmodifikation. Welche Spannung als sinnvoll gilt, ist web-spezifisch.*

---

> **Web-Spezifik — Grundsatz:**
> Nicht jeder Bewertungs- oder Kontextmechanismus ist für jedes HarmonyWeb gleichermaßen sinnvoll aktiviert. Ein funktionales Web (klassische Harmonik, klare Auflösungstendenzen) braucht andere aktive Mechanismen als ein modales, ein Blues- oder ein riemannianisches Web. Bewertungs- und Kontextmechanismen sind deshalb als web-spezifisch aktivierbare oder gewichtbare Bestandteile der HarmonyLogic zu verstehen — nicht als globale Einheitslogik, die pauschal auf alle Webs angewendet wird.

---

## Architektur – verständlich erklärt

**Was das System tut**

HarmonyEngine3D ist ein interaktives Musikinstrument: Der Spieler fliegt durch einen dreidimensionalen Raum, der aus Akkord-Objekten besteht, und erzeugt durch Annäherung an diese Objekte MIDI-Signale oder direkten Klang. Jeder Akkord im Raum ist nicht isoliert — er ist Teil eines Netzwerks, das musikalische Zusammenhänge beschreibt. Das Netzwerk kennt z. B. die klassische Verbindung von einem Spannungsakkord zu einem Auflösungsakkord und bewertet diese als wahrscheinlicher als zufällige Sprünge.

**Die Schichten und ihre Zuständigkeiten**

Das System ist in klar abgetrennte Schichten gegliedert. Jede Schicht hat eine einzige Hauptverantwortung und darf nur mit der Schicht direkt unter ihr sprechen. Keine Schicht übernimmt Aufgaben einer anderen.

Die **Eingabe-Schicht** nimmt alles entgegen, was der Spieler tut: Gamepad-Bewegungen, Tastendrücke, Gyro-Sensoren. Sie berechnet daraus die Flugphysik — Geschwindigkeit, Richtung, Bremsen — und stellt das Ergebnis als reinen Zustand bereit. Sie kennt weder die 3D-Welt noch den Klang.

Die **Renderer-Schicht** verwaltet die sichtbare Welt: den dreidimensionalen Raum, alle Akkord-Objekte, die Kamera und das visuelle Feedback. Sie misst permanent die Abstände zwischen Spieler und Akkord-Objekten und meldet, wenn ein Objekt nahe genug ist, um aktiviert zu werden. Sie entscheidet nicht, welcher Klang erklingt — sie registriert nur die Nähe.

Die **Harmonie-Schicht** verbindet das Akkord-Netzwerk mit dem Raum. Die harmonische Logik kennt die Musiktheorie und den bisherigen Verlauf aller gespielten Akkorde; RuntimeHarmonik übersetzt ihre Vorschläge in räumliche Aussagen: „Welcher existierende Akkord im Raum passt als nächster Schritt, und wie weit ist er entfernt?" Diese Schicht trifft Entscheidungen, verändert aber noch nichts im Raum.

> **Präzisierung (ab 3.9.3):** Die Entscheidung wird als **Harmonic Magnetism** wirksam — `HarmonyScene` setzt das Magnet-Ziel, `FlightController` zieht den Spieler subtil in diese Richtung. Davon zu unterscheiden ist der **Proximity Nudge**: ein geometrischer Einfluss, der unabhängig von der Harmonielogik aus der räumlichen Nähe mehrerer Nodes entsteht.

Die **Core-Schicht** enthält die algorithmischen Bausteine, die weder Darstellung noch Klang kennen: Weltgenerierung, Melodieerzeugung, Stimmführung und Physikberechnungen. Diese Bausteine sind absichtlich plattformfrei — sie laufen ohne Änderung auch auf iOS.

Die **Ausgabe-Schicht** empfängt fertige Noten-Ereignisse und leitet sie weiter — entweder als MIDI-Signal an externe Synthesizer und DAWs oder an den internen Synthesizer. Sie weiß nicht, warum ein Ton erklingt; sie sendet nur.

Die **App-Schicht** ist der unsichtbare Organisator: Sie erstellt beim Start alle Bausteine, verdrahtet sie miteinander und wählt die Audioausgabe. Im laufenden Betrieb tritt sie kaum in Erscheinung.

**Wie die Übergaben funktionieren**

Wenn der Spieler auf einen Akkord zufliegt, läuft folgendes ab: Die Renderer-Schicht stellt fest, dass der Abstand unterschritten wurde, und gibt ein Aktivierungs-Ereignis an den Koordinator weiter. Der Koordinator leitet die entsprechenden Noten-Befehle an die Ausgabe-Schicht — der Akkord klingt. Gleichzeitig informiert er die Harmonie-Schicht: „Dieser Akkord wurde gerade gespielt." Die Harmonie-Schicht fragt intern nach dem musikalisch wahrscheinlichsten nächsten Schritt, sucht den nächstgelegenen passenden Akkord im Raum und liefert eine strukturierte Entscheidung zurück. Diese Entscheidung wirkt bereits als Harmonic Magnetism: der empfohlene Akkord zieht den Spieler subtil an — nicht als Zwang, sondern als Einladung. Die Feinabstimmung der Magnetstärke über Profile steht noch aus.

Eingabe und Klang kommunizieren nie direkt miteinander. Der Gamepad-Controller übergibt seinen Zustand an die Flugphysik — nicht an den Synthesizer. Die Klang-Ausgabe empfängt fertige Ereignisse vom Koordinator — nicht vom Gamepad. Alle Übergaben sind einseitig und klar definiert.

**Die geteilte Datenbasis**

Konfigurationswerte — Physikparameter, MIDI-Kanäle, Klangfarben, Netzwerkauswahl — liegen in einem zentralen Objekt, das alle Schichten lesen, aber nur der App-Layer schreiben darf. Änderungen in der Benutzeroberfläche wirken sofort ohne Neustart. Die Datenmodelle für Akkorde und Netzwerke liegen in einem separaten, geteilten Paket, das auch vom Netzwerk-Designer-Tool verwendet wird.

**Warum diese Struktur?**

Ein Umbau der Klangausgabe berührt die Navigationslogik nicht. Ein neues Akkord-Netzwerk lässt sich laden, ohne den Synthesizer zu verändern. Die musikalische Entscheidungslogik lässt sich isoliert testen, ohne eine 3D-Szene zu starten. Diese Trennung macht das System wartbar, erweiterbar und auf künftige Plattformen — z. B. iOS — übertragbar.
