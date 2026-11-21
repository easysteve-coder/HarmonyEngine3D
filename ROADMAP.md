# HarmonyEngine3D — Konsolidierte Roadmap

> **Einzige autoritative Planungsquelle.**
> `TODO.md`, `HarmonyEngine3D_Roadmap.md`, `ROADMAP_3.9.8_NEXT_ROUNDS.md` und die Roadmap-Abschnitte
> aus `HarmonyNetwork_Design.md` sind in diesem Dokument aufgegangen. Konzeptdokumente
> (`HarmonyNetwork_Design.md`, `ARCHITECTURE.md`) und Bestandsaufnahmen (`REVIEW_3.9.8.md`,
> `CODEX_REVIEW_3.9.8.md`, `SYNTHESE_3.9.8.md`) bleiben als Fachquellen erhalten,
> legen aber keine Reihenfolge mehr fest.

Stand: 2026-11-21 (Rev. 8) | Entwicklung: Claude | Zweitmeinung: Codex | Richtung: Stephan Schmitt

---

## Produktrichtung Rev. 8 (Owner 21.11.2026)

> **Diese Sektion bestimmt ab 21.11.2026 die Reihenfolge.** Die Rev.-7-Sektion
> darunter bleibt als Verlauf und Detailquelle; ihre offenen Punkte gehen in
> R8-0 bis R8-6 auf. Grundlage: Architekturanalyse 21.11.2026 (Claude) mit
> Zweitmeinung Codex (`.agent_handoff/codex-hinweise.md`, privat).

### Zielbild

HarmonyEngine3D wird eine **nichtlineare, vom Flug gesteuerte DAW im Raum**:
Objekte in der Welt tragen vorher eingefüllten Inhalt (Akkorde wie bisher,
dazu Samples, Loops, MIDI-Pattern, Instrument-Auslöser, Effektzonen). Der
Flug startet, mischt und moduliert sie, auf Wunsch quantisiert auf ein
musikalisches Raster. Ein **Construction Kit** (DesignerKit/HarmonyAuthoring)
baut diese Klangwelten auf demselben Datenmodell.

### Owner-Entscheidungen 21.11.2026

1. **Lizenz:** GPLv3 wie FIRSTofFIFTH und Planarium. Code aus beiden darf
   übernommen werden (Herkunft in `THIRD-PARTY-NOTICES.md`). Öffentliches
   Repository auf GitHub wie bei den Schwesterprojekten.
2. **Tempo: alles, jeweils optional.** Festes Tempo pro Welt, Einfluss des
   Flugs auf das Tempo, Folgen einer externen MIDI-Clock (und Senden). Ohne
   aktiviertes Tempo bleibt das heutige freie Spiel erhalten.
3. **Live-Quantisierung** der Auslösungen auf das Raster (Wert pro Objekt,
   „aus“ möglich).
4. **AU-Instrumente und -Effekte** wie in den Schwesterprojekten; der eigene
   Synth wird ein Instrument unter mehreren.
5. **Optik durchgängig im Studiogerät-Stil** („Gebürstetes Studiogerät“,
   Vertrag Planarium `docs/GESTALTUNG.md`, Muster FoF
   `Docs/GUI_DESIGN_SYSTEM.md`): Bedienflächen und Anmutung der 3D-Welt.
6. **RealityKit statt SceneKit, sofern ältere Macs mitkommen.** Erst Probe
   (R8-5a), dann Entscheidung mit Messwerten.

### Befundlage (Kurzfassung, Stand HEAD `cc14212`)

- Untere Module (`HarmonyShared`, `HarmonyAuthoring`, `HarmonyAudioCore`)
  tragen. Die App-Schicht ist gewachsen: `HarmonyScene.swift` 2.727 Zeilen,
  zwei Weltmodelle (`.txt`-Netze und HarmonyWeb-JSON), doppelter
  `MIDIManager` im DesignerKit, fest je Kanal verdrahtete Effekte in
  `AudioEngine`.
- Thread-Grenzen: Render-Thread liest `AppSettings` live, während Main
  schreibt; L1/R1 mutieren `interactionRuntime` von Main; Flight-/MIDI-
  Snapshot liest im `willSet` den alten Wert; mehrere Fenster erzeugen
  mehrere Taktgeber.
- Noten: Off löst alle Stimmen gleicher Tonhöhe (Quellen ohne Identität);
  Panic und MIDI-Eingang können sich überholen; Ring ohne atomare Indizes,
  Off/Panic bei Überlauf verlierbar; `SpaceSendBus` ohne belegten
  Rendervertrag.
- Zeit: kein musikalisches Tempo; Auslösung im Bildtakt, nicht sampelgenau.

### Reihenfolge

| Schritt | Inhalt | Nachweis |
|---|---|---|
| **R8-0 Fundament** | ein Simulations-Owner (eine Uhr, ein Fenster mit Welt); pro Frame eine unveränderliche Settings-Kopie; alle Szenenänderungen über die Render-Befehlswarteschlange (Gamepad, Presets, Stick); Notenbuch mit Quellenidentität vor beiden Ausgängen, Panic als ein Schnitt über alle Quellen; Ring mit atomarem SPSC-Vertrag und garantiert zustellbarem Off/Panic; `SpaceSendBus` mit eindeutigem Besitzer | TSan-Lauf der betroffenen Ziele; Gegenproben: zwei Quellen gleicher Ton, Note-On um Panic herum, voller Ring, vier Synth-Knoten am Raum-Send |
| **R8-1 Aufräumen** | `HarmonyScene` nach Verantwortung zerlegen (Weltprojektion, Frame-Ablauf, Interaktion, Materialien); `.txt`-Weltmodell in HarmonyWeb überführen oder stilllegen; `MIDIManager` vereinheitlichen | Bitgleichheit der Welt bei gleichem Seed; bestehende Suite grün |
| **R8-2 Klangkern mit Zeit** | eigenes Modul: Transport, Tempo (fest/Flug/extern, optional), Takt, Quantisierung, sampelgenauer Planer; die Szene liefert nur noch Absichten („Objekt X starten/stoppen/modulieren“) | Offline-Render: Auslösung auf Rasterpunkt sampelgenau; Tempowechsel ohne Sprung; MIDI-Clock senden/folgen |
| **R8-3 Kanalzüge und AU-Hosting** | Kanalzug = Instrument + Effektkette + Pegel/Pan; AU-Suche, Laden, Plugin-Fenster, Zustand im Preset; eigener Synth als Instrument; Vorlage Planarium `PlanariumAudio` | Laden/Entladen jedes Wegs ohne hängende Note; Zustand übersteht Speichern/Laden |
| **R8-4 Klangobjekte und Construction Kit** | Schema-Erweiterung in `HarmonyShared` (Sample, Loop, Pattern, Instrument-Auslöser, Effektzone); Sample-/Loop-Wiedergabe (Vorlage FoF `AudioLoop`); Bearbeitung im DesignerKit | Datei-Rundreise verlustfrei; Loop startet quantisiert und läuft taktfest |
| **R8-5 Grafik und Optik** | a) RealityKit-Probe auf macOS 12/13 und Intel-iMac (Bildrate, Bloom/Post-Processing, Materialien); b) Entscheidung SceneKit-Aufwertung oder Umstieg; c) Studiogerät-Stil für alle Bedienflächen, Pilotmodul zuerst | Vorher/Nachher-Bilder; Bildratenmessung auf dem ältesten Zielrechner |

R8-5c (Bedienflächen) hängt nicht an R8-0 bis R8-4 und kann bei Bedarf
vorgezogen werden. R8-5a ist eine Probe ohne Produktumbau.

### Offene Punkte für Stephan

- **Plattformuntergrenze:** Das Paket verlangt macOS 13; der Intel-iMac läuft
  auf macOS 12.7.6. Für „ältere Macs“ wäre macOS 12 wie Planarium nötig.
  RealityKit bietet unter macOS 12/13 nur `ARView` mit eigenen
  Metal-Materialien und Post-Processing; `RealityView` und der eingebaute
  Partikelemitter verlangen neuere Systeme (vor R8-5a zu verifizieren).
- Bisher offene Hörentscheidungen bleiben offen: Kanalpolitik des
  MIDI-Eingangs, Makro-Semantik, Raumpegel, Poolgrößen.

---

## Strategische Leitlinie

> Das System hat eine klanglich funktionierende Audio-Basis (reiner Synth pro
> Kanal, kein Sampler). Der Command-Transport zur Audio-Queue muss in F-02
> technisch abgesichert werden. Die strategische Produktfrage bleibt:
> **„Welche Musik versteht dieses Instrument?"**

Alle folgenden Schritte ordnen sich dieser Frage unter.

---

## Operative Roadmap ab Rev. 7

> **Diese Sektion bestimmt die Ausführungsreihenfolge.**
> Die ausführlichen älteren Phasenbeschreibungen bleiben als Fach- und
> Detailbacklog erhalten, sind aber wegen ihres historischen Status nicht mehr
> sequenziell abzuarbeiten.
>
> Vollständige Begründung, Findings, Zielarchitektur, Construction-Kit-Konzept
> und Akzeptanzkriterien:
> `ARCHITECTURE_REVIEW_2026-07-26.md`.

### Ziel V1

V1 ist ein spielbares macOS-HarmonyWeb-Instrument plus ein 2D Construction
Kit für genau dasselbe Datenmodell.

Erforderlich:

- DesignerKit kann HarmonyWebs neu anlegen, öffnen, bearbeiten, validieren,
  speichern und verlustfrei wieder öffnen.
- Die 3D-App lädt dieselbe Datei ohne semantische Degradierung über
  `ChordNetwork`.
- Map, Layer, Graphkontext und RuntimeHarmonik besitzen eine gemeinsame
  Ownership.
- MIDI und interner Synth halten On/Off-Symmetrie und einen korrekten
  Audio-Command-Producer-Vertrag ein.
- Clean Checkout, Tests, normaler Build und Strict Build sind reproduzierbar.

Nicht Teil von V1:

- Multi-Web-Navigation und Identitätswechsel;
- iPhone;
- vollständige Art Direction;
- web-spezifische generative HarmonyLogic;
- komplette Legacy-`.txt`-Migration.

### Milestone M0 — Verträge und reproduzierbare Basis

| Slice | Inhalt | Gate / DoD |
|---|---|---|
| **F-01** — **erledigt (3.9.9, Runde 015)** | `HarmonySharedTests`; Decode-/Layer-/Graph-/Determinismus-Tests; Graphhistorie auf konkrete Transitionen korrigieren | `swift test`, normaler Build, Strict Build grün; keine dirty Map-/Designer-Datei anfassen |
| **F-02** — **erledigt (3.9.9, Runde 016)** | Verletzten SPSC-Vertrag der `NoteEventQueue` korrigieren; genau einen Producer oder echtzeitgerechte MPSC-/Serialisierungsgrenze herstellen | Audio-Renderthread lock-/allokationsfrei; Note-Off/All-Off dürfen bei Overflow nicht still verloren gehen |
| **F-03** — **erledigt (3.9.9, Runde 017)** | `HarmonyMapCodec` + öffentlicher strukturierter `HarmonyMapValidator`; striktes Decode; kanonischer Roundtrip | Engine und Kit nutzen dieselben Diagnosecodes |
| **F-04** — **erledigt (3.9.9, Runde 019)** | Bestätigte dirty/untracked Produktdateien gezielt baseline-fähig machen; Bundle-Maps validieren; Doku synchronisieren | Entscheidung Stephan, welche vorhandenen Dateien zum Produkt gehören — Stephan hat am 2026-07-27 entschieden: kompletter damaliger dirty/untracked-Bestand gehört zur Baseline |

### Milestone M1 — Kanonischer HarmonyWeb-Produktpfad

| Slice | Inhalt | Gate / DoD |
|---|---|---|
| **E-01** — **erledigt (3.9.9, Runde 020)** | `WorldSession`: validierte Map, aktiver Layer, GraphEngine und RuntimeHarmonik aus einer Hand; direkter Map-Pfad | Scene und Runtime sehen dieselben Nodes/Edges; `toChordNetwork` nur Legacy-Adapter |
| **E-02** — **erledigt (3.9.9, Runde 021)** | Phase 4.2c korrigiert: eigene Magnet-Settings; Range aus Preset-Mapping ableiten; weicher Falloff; Value-Config | Kein erfundenes JSON-Feld `MagnetProfile.range`; RuntimeHarmonik bleibt AppSettings-/SceneKit-frei |
| **E-03** — **erledigt (3.9.9, Runde 023)** | HarmonyWeb ohne Environment-Flag als normaler Modus; Bundle-Auswahl; sichtbarer Layer-/Modusstatus | Stephan-Entscheidung Option A (2026-07-27): Explore bleibt Default, HarmonyWeb normal wählbar, `reference-core` initiale Map. Externe Datei-Auswahl bewusst nicht Teil dieses Slices (Sandbox-Entscheidung) |
| **E-04** — **erledigt (3.9.9, Runde 024)** | `InputSnapshot`; Renderthread als alleiniger Besitzer von `FlightState`; HUD-Snapshots | Keine Main-Thread-Mutation des FlightState |
| **E-05** — **erledigt (3.9.9, Runde 025)** | atomare Render-Commands und immutable Config-Snapshots statt Pending-Bool-Gruppen | Render-Kommandos werden vollständig oder gar nicht konsumiert |
| **E-06** — **erledigt (3.9.9, Runde 027)** | `InteractionRuntime` schrittweise aus `HarmonyScene` extrahieren: Chord, danach Bass/Cloud | Scene rendert; Runtime liefert OutputEvents und RenderEffects. E-06a (Runde 026): Chord-Proximity + Chord-Trigger. E-06b (Runde 027): Portal-/Bass- und Cloud-/Melody-Kanal — Chord+Bass+Cloud laufen jetzt vollständig über `InteractionRuntime` |

### Milestone M2 — HarmonyWeb Construction Kit V1 — **vollständig abgeschlossen (3.9.9, Runde 035)**

| Slice | Inhalt | Gate / DoD |
|---|---|---|
| **K-01** — **erledigt (3.9.9, Runde 028)** | neues `HarmonyAuthoring`-Target; `HarmonyMapDocument`; Dirty-State; Commands; Undo/Redo; validierter Snapshot | Kein paralleles musikalisches Datenmodell — `HarmonyMap` bleibt die einzige musikalische Datenwahrheit |
| **K-02** — **erledigt (3.9.9, Runde 029)** | New/Open/Save/Save As; beliebige URLs; atomisches Schreiben; Bundle-Maps als Read-only-Templates | Save-Reopen-Roundtrip grün |
| **K-03** — **erledigt (3.9.9, Runde 030)** | Canvas auf kanonisches Dokument umstellen; `EdgeData`-Kopie entfernen; Workspace-Sidecar; Drag/Pin/Layout/Zoom | Web-Edit verändert den Draft, nicht ein Legacy-Sidecar |
| **K-04** — **erledigt (3.9.9, Runde 031)** | Node Add/Duplicate/Rename/Delete + vollständiger Inspector | Rename aktualisiert Referenzen atomar; Undo/Redo |
| **K-05** — **erledigt (3.9.9, Runde 032)** | Edge-/Layer-Authoring inklusive RelationTypes, Gerichtetheit, Gewicht, MagnetPreset und Layerverwaltung | referenzsichere Mutationen; Live-Validation |
| **K-06** — **erledigt (3.9.9, Runde 033)** | Issue-Navigator und Export-Gate; Draft-Save erlaubt, Runtime-Export nur ohne Errors | Engine und Kit akzeptieren dieselbe Datei |
| **K-07** — **erledigt (3.9.9, Runde 034)** | Runtime-nahe 2D-Simulation mit echter GraphEngine, Layer, Seed, History und effektiven Gewichten | Keine nachgebaute Parallel-HarmonyLogic |
| **K-08** — **erledigt (3.9.9, Runde 035)** | erster regelbasierter diatonischer Builder als Diff mit Apply/Cancel/Undo | weitere Builder jeweils eigene Slices |

### Zwischenschritt — Fable-5-Code-/Produktreview vor M3 — **abgeschlossen (Runde 036)**

Vor dem produktiven Start von M3 hat Claude Fable 5 einen Architektur-/
Produkt-/Risiko-Review von M1+M2 durchgeführt (Runde 036). Urteil: **M3-Go
mit Auflagen** — kein Rewrite, aber vier Kit-Konsistenzprobleme (Builder
erzeugt bei layerlosem Dokument tote Kanten; stale Builder-/Simulation-State
bei Dokumentwechsel; Legacy-Aktionen im Dokumentmodus; `DeleteLayerCommand`
setzt Node-Layer fälschlich auf `[]` statt `nil`) sollen vor V-01 behoben
werden. Vollständiger Befund inkl. M3-Slice-Empfehlung, Risiko-Review und
offener Stephan-Entscheidungen: `.agent_handoff/latest_claude.md` (Runde 036).

### Milestone M3 — V1-Integration und Releasefähigkeit

| Slice | Inhalt | Gate / DoD |
|---|---|---|
| **V-00a** — **erledigt (Runde 037)** | Kit-Konsistenz-Fixes vor V-01: Default-Layer `functional` für neue Dokumente, Builder blockiert statt layerlose Kanten zu erzeugen, Builder-/Simulation-State-Invalidierung bei Dokument-/Draft-Wechsel, Legacy-Aktions-Guards im Dokumentmodus, `DeleteLayerCommand`-Node-Layer-Semantik | `Neu -> Builder -> Apply -> validierter Snapshot -> Graph traversiert` ist testbar grün; keine Runtime-Integration, keine Audio-/Synth-/MIDI-Änderung, keine Map-JSON-Schema-Änderung |
| **V-00b** — **erledigt (Runde 038)** | Engine-Symmetrie/Determinismus-Fixes vor V-02: CH0-NoteOff ausschließlich aus dem Output-Snapshot (auch bei Kandidatenverlust im aktuellen Frame), `MelodyEngine`/`AutopilotEngine` auf `SeededRNG` statt unseeded `randomElement()`/`Float.random`, deterministische Candidate-/Tie-Break-Reihenfolge (`resolveChordPositionMap`, sortierte Kandidatenlisten) | CH0-NoteOff kann bei Kandidatenverlust nicht mehr verloren gehen und nutzt immer die ursprünglich gesendeten Noten; gleicher Seed liefert gleiche Melody-/Autopilot-Sequenz; bestehende Tests bleiben grün. `bassHoldMode`-Toggle-Semantik (Fable-A12) bleibt bewusst offenes Stephan-Gate, nicht Teil dieses Slices |
| **V-00b.1** — **erledigt (Runde 039)** | Kleiner Supervisor-Nachlauf zu V-00b: CH0-Output-Snapshot (`InteractionRuntime`) trägt jetzt Name UND Noten aus demselben Aktivierungszeitpunkt (`ChordOutputSnapshot`), nicht mehr nur die Noten | `chordDeactivated` nach Kandidatenverlust trägt den ursprünglich aktivierten Chord-Namen; `OutputCoordinator`s bestehender `soundingChordName == chord.name`-Check kann das HUD wieder sauber leeren |
| **V-01** — **erledigt (Runde 040)** | Kit-zu-Engine-Vertikalslice: einfacher Application-Support-Importordner (`~/Library/Application Support/HarmonyEngine3D/HarmonyWeb/Maps`) für extern importierte HarmonyMap-JSON-Dateien, ladbar über `RuntimeMapImportStore`/`WorldSession` (kein `toChordNetwork`); Bundle-Maps und Explore-Default bleiben unverändert wählbar | Kit-nahe Map -> Export in den Importordner -> `RuntimeMapImportStore` -> `WorldSession` testbar grün; Nodes/Edges/Layer/RelationTypes/Gewicht/MagnetProfile/MIDI-Noten/`layout3D` bleiben erhalten; ungültige Dateien crashen nicht; `--map-preview`/`HE3D_MAP_PREVIEW` bleibt vorrangig |
| **V-01.1** — **erledigt (Runde 041)** | Supervisor-Pflicht-Nachlauf zu V-01: `RuntimeMapImportStore.listImportedMaps()` legt den Importordner im Default-Produktpfad (`directory: nil`, z. B. `ContentView`s WELT-Abschnitt) jetzt selbst automatisch und nicht-destruktiv an (`ensureImportDirectoryExists`), statt unsichtbar fehlend zu bleiben | Fehlender Produkt-Importordner wird bei Bedarf angelegt; bestehende Dateien bleiben erhalten; explizit von Tests injizierte fehlende Testverzeichnisse werden weiterhin NICHT automatisch angelegt; V-01-Funktionalität (externe Maps, Bundle-Maps, Explore-Default, Developer-Override) bleibt unverändert |
| **V-02** — **teilweise (Runde 042)** | Smoke-Matrix: MIDI/Synth × Tastatur/DualSense × Explore/HarmonyWeb; 30-Minuten-Session | Boot-Matrix (Explore, HarmonyWeb Bundle-Map, HarmonyWeb externe Map × interner Synth/MIDI) reproduzierbar gruen, keine Crashes/State-Divergenz. Sustained-/Live-Interaktions-Achse (Tastatur-/Maus-Trigger, DualSense, 30-Min-Session ohne haengende Note) in der Headless-CLI-Umgebung nicht abschliessend pruefbar (SceneKit-Renderloop tickt dort nicht ueber die Erstinitialisierung hinaus) — siehe `SMOKE_TEST_V1.md` fuer Details und Ersatzverifikations-Vorschlag; DualSense zusaetzlich `skipped: hardware unavailable` (gepaart, aber nicht verbunden) |
| **V-03** — **erledigt als Doku-Slice (Runde 043)** | Neues `README.md` (Setup/Start/HarmonyWeb-Bundle/-externe Maps), `ARCHITECTURE.md` gezielt um Abschnitt „V1-Integrationsstand" synchronisiert (Targets, `WorldSession`, `RuntimeMapImportStore`, `InteractionRuntime`, Audio-/MIDI-Grenze, V-02-Status), neue `RELEASE_CHECKLIST_V1.md` (automatische + manuelle Gates, Blocker-/Skip-Konvention), `SETUP.md` als historisch markiert | Clean Checkout ist anhand `README.md` onboardbar. **Keine Aussage "releasefähig"**: das manuelle V-02-Live-/30-Minuten-Gate bleibt explizit offen (`RELEASE_CHECKLIST_V1.md` M10, `ARCHITECTURE.md` „V1-Integrationsstand" → V-02-Status) und braucht eine echte Session oder eine Stephan-/Supervisor-Akzeptanzentscheidung, bevor V1 als releasefähig gelten kann |

**Gate 10 (Fable-A12) — erledigt (Runde 062).** Stephan hat am 2026-08-01
entschieden: Nachhol-`noteOff` soll gesendet werden. Schaltet man
`bassHoldMode` während einer gehaltenen Bass-Note aus, sendet
`InteractionRuntime.updatePortal(_:)` jetzt für jede tatsächlich klingende
Bassnote ein Nachhol-`bassNoteOff` — mit Ausnahme der Note des gerade aktiven
Portals, die wie im Trigger-Modus bis zum Verlassen klingen bleibt. Ist kein
Portal aktiv, werden alle klingenden Noten freigegeben. Die Erkennung nutzt
eine neue, explizit gepflegte Menge tatsächlich klingender Noten
(`soundingBassNotesByKey`) statt des bestehenden `bassOutputNotesByKey`-
Snapshots, dessen Einträge beim `noteOff` nicht entfernt werden und sonst
Geister-Offs für längst verstummte Noten erzeugt hätten. Trigger-Modus-
Verhalten (`bassHoldMode == false` durchgehend) bleibt unverändert. Details:
`.agent_handoff/latest_claude.md`, Runde 062.

**Finding 062-01 — erledigt (Runde 063).** Zweite, ältere Quelle hängender
Bassnoten geschlossen: beim Entladen eines Chunks bekam bisher nur eine
Note des gerade aktiven Portals ihr `noteOff` — eine im Hold-Modus
klingende Note eines bereits verlassenen, nicht aktiven Portals blieb beim
Entladen ihres Chunks unerreichbar liegen (nur Panic konnte sie noch
beenden). `InteractionRuntime.removeBassOutputNote(forKey:)` liefert die
entfernte Note jetzt nur noch zurück, wenn sie tatsächlich noch klang
(`soundingBassNotesByKey`), nicht mehr den reinen `bassOutputNotesByKey`-
Snapshot; `HarmonyScene.unloadChunk` sendet das Off entsprechend für jede
tatsächlich klingende Note, unabhängig davon, ob das Portal aktiv war.
Details: `.agent_handoff/latest_claude.md`, Runde 063.

### Audio-Track A - Atmospheric Synth und Space Engine

Stephan hat die Klangrichtung gesetzt: ein eigenstaendiger,
Absynth-inspirierter atmosphaerischer Synth mit grossen Hall- und
Delayraeumen. Gemeint ist Wellenform-Morphing, tiefe Modulation und
langsame Klangentwicklung, nicht ein 1:1-Klon oder die Uebernahme
proprietaerer Presets, Assets, UI oder Algorithmen.

Der vollstaendige Planungsentwurf steht in
`SYNTH_ARCHITECTURE_PLAN.md`. Er beschreibt:

- `HarmonyAudioCore` als testbaren Swift/Accelerate-DSP-Kern;
- Erhalt von `AudioOutput`, `OutputCoordinator`, `AudioEngine.commandQueue`
  und dem lock-/allokationsfreien Rendervertrag;
- eine Atmospheric Voice mit Morph-Oszillatoren, Texture Source,
  Modulationsmatrix, Makros, Filter und Shaping;
- gemeinsame `EchoField`-/`DeepSpace`-Send-Busse;
- versionierte Presets, Offline-Rendering, Audio-Metriken und Performance-
  Gates;
- Play View plus vertiefenden Synth Lab;
- spaetere, getrennte Slices fuer Harmony-Modulation, per-Ball-3D-Audio,
  Granular und Shimmer.

Status: **SYNTH-00, S-01, S-02a, S-02b, S-03, S-04a, S-04a-fix, S-04b,
S-05a, S-05b, S-06, S-07a, S-07b, S-08a, S-08a-fix, S-08b, S-08b-fix,
S-08c, Runde 064, Runde 065, W-01 (Runde 066), W-02 (Runde 067) und W-03a
abgeschlossen (Runde 068).**

**Verdrahtungskette W-01 bis W-05** (von Stephan am 2026-08-02 freigegeben,
Ziel: den Synth hoer- und einstellbar machen):

| Slice | Inhalt | Status |
|---|---|---|
| **W-01** | Atmospheric Voice zusammensetzen | **erledigt (Runde 066)** |
| **W-02** | DeepSpace-Kette zusammenschalten: Early Reflections → Diffusor → FDN-Tail | **erledigt (Runde 067)** |
| **W-03a** | FDN-Tail vollstaendig renderthread-sicher machen (Vorbereitung der Verdrahtung) | **erledigt (Runde 068)** |
| **W-03b1** | Umschaltmechanik Legacy/Atmospheric, Legacy bleibt Default (**Deep Review**) | **erledigt (Runde 070)** |
| **W-03b2** | Default auf Atmospheric kippen, S-01-Baseline umziehen (**Deep Review**) | **erledigt (Runde 071)** |
| **W-03c** | DeepSpace-Kette an den `sharedSpaceSendBus` (**Deep Review**) | **erledigt (Runde 072)** |
| **W-04** | MIDI-Eingang: virtuelles Ziel plus externe Quellen, Noten und CC (**Deep Review**) | **erledigt (Runde 073)** |
| **W-05** | CC-Mapping auf Parameter, zuerst die vier Makros | **erledigt (Runde 074)** |

Seit W-03b2 (Runde 071) ist der Synth hoerbar, seit W-03c (Runde 072) auch
der Raum; die Verdrahtung ist damit abgeschlossen. Seit W-04 (Runde 073) ist
er ueber MIDI spielbar. Seit W-05 (Runde 074) ist er am Controller
einstellbar — **die Verdrahtungskette W-01 bis W-05 ist damit vollstaendig
abgeschlossen.**

**W-05-Ergebnis (Runde 074):** Die vier Performance-Makros waren bis dahin
nirgends verdrahtet — die Stimme reichte sie zwar in die Modulationsmatrix,
aber es fuehrte keine Route dorthin und kein Weg brachte einen Wert hinein.
Beides ist geschlossen: vier Makrorouten in der Default-Matrix (vorlaeufig,
Begruendung und Abweichung von `SYNTH_ARCHITECTURE_PLAN.md` 6.5 am Code) und
`SynthParams.macros` ueber den bestehenden Command-Pfad. Die Risikostelle
CC-Flut ist gemessen entschaerft: statt 508 bzw. 2.032 `paramUpdate`-
Ereignissen pro Sekunde (ein bzw. vier bewegte Regler) 168, mit
Koaleszieren auf 20 ms Mindestpause statt eines nachlaufenden Debounce.
Offen fuer Stephan: die vier Default-CC-Nummern, die Richtung von `color`
und die Makro-Ziel-Zuordnung insgesamt — alles erst am Instrument
entscheidbar.

**W-04-Ergebnis (Runde 073):** Die Warnung zum SPSC-Vertrag hat getragen —
und sie war nicht der einzige Fallstrick. Der Eingang ist ausschliesslich
ein weiterer `AudioOutput`-Aufrufer und laeuft ueber
`AudioEngine.commandQueue`; der CoreMIDI-Thread wird dadurch kein zweiter
Producer, an `NoteEventQueue` ist keine Zeile geaendert. Zwei echte Fehler
wurden waehrend der Runde gefunden und behoben, beide im Anti-Haenger-Pfad:
eine Ordnungsinversion zwischen Buchung und Ausgabe (haette `noteOff` vor
`noteOn` bei `commandQueue` einreihen koennen — Note haengt fuer immer,
vom Supervisor gemeldet) und ein gemeinsames Notenbuch fuer beide
Eingangswege (Kabel raus am Keyboard haette DAW-Noten mitgerissen). Beide
sind durch Konstruktion geschlossen: Buchung und Ausgabe unter einem Lock,
Sperren des Quellwegs im selben Atemzug wie das Aufraeumen, getrennte
Buecher je Weg. Gegenprobe durchgefuehrt: mit der alten Konstruktion
schlagen die neuen Nebenlaeufigkeitstests an.

Die Kanal-Politik des Eingangs ist **vorlaeufig** und braucht eine
Stephan-Entscheidung: gehoert wird auf allen 16 Kanaelen, Kanal 1-4 spielen
CH0-CH3, 5-16 fallen auf CH0. Alternative waere ein fester eigener
Eingangskanal ohne Uebersprechen mit den vom Spiel selbst gespielten Noten.

**CPU-Budget der W-Kette** (Stephan-Freigabe 2026-08-02, verbindlich):
Referenzmaschine MacBook Pro / Apple M1 Pro, Metrik Echtzeitfaktor offline
und single-threaded, gemessen als Maximum pro Block statt Durchschnitt.
Ziel >= 10x Echtzeit fuer die volle Kette bei voller Polyphonie (16 Stimmen,
vier Kanal-FX-Ketten, ein `DeepSpace`, ein `EchoField`), harte Untergrenze
>= 5x. Das Gesamt-Gate greift ab W-03b; W-01 hatte nur den Messauftrag.

**W-01-Ergebnis (Runde 066):** `AudioCoreAtmosphericVoice` plus
`AudioCoreAtmosphericVoiceParameters` verbinden die seit S-04a einzeln
getesteten Bausteine erstmals zu einer spielbaren Stimme — Quelle A /
Quelle B / Textur → Mixer → SVF → Waveshaper → Amp-Huelle → Pan → L/R.
Alle sieben Modulationsziele wirken nachweisbar (ein Test pro Ziel);
`spaceSend` wird nur nach aussen sichtbar gemacht und in der Stimme
bewusst nicht angewendet (das tut W-03). Modulation laeuft auf einer festen
internen Kontrollrate von 32 Samples und wird danach auf Audiorate
geglaettet; die Kontrollperiode haengt an einem stimmeigenen Zaehler und
nicht an `frameCount`, wodurch derselbe Render in beliebig geschnittenen
Bloecken bit-identisch bleibt. Renderpfad per SIL als allokationsfrei
belegt. Gemessene Kosten einer Stimme (48 kHz, M1 Pro): Median 59,3
ns/Sample = 351x Echtzeit, schlechtester Einzelblock 132,4 ns/Sample =
157x; hochgerechnet auf 16 Stimmen 21,9x (Median) bzw. 9,8x (schlechtester
Block). Reine Core-Schicht, noch nicht verdrahtet, kein bestehender Klang
veraendert; 23 neue Tests, 629/629 Gesamttests gruen.

**W-02-Ergebnis (Runde 067):** `AudioCoreDeepSpace` plus
`AudioCoreDeepSpaceChainParameters` schalten die drei seit S-08a/S-08b/S-08c
einzeln getesteten Raumbausteine erstmals zusammen. Topologie exakt wie
beauftragt: Eingang → Pre-Delay → parallel (Early Reflections | Diffusor →
FDN-Tail) → Summe → Stereo. Das Pre-Delay liegt jetzt VOR der Aufteilung und
verzoegert beide Zweige gleich; die Early-Reflection-Stufe bekommt dafuer
`preDelaySeconds = 0` uebergeben (der Baustein selbst bleibt unveraendert).
Die Zweigpegel sind **vorlaeufig** auf je 0,5 gesetzt — gleiche Gewichtung
ist die einzige Wahl ohne Klangaussage; Stephan entscheidet ab W-03.
Renderpfad zur Laufzeit als allokationsfrei gemessen (0 Allokationen ueber
1.024.000 Samples, interponierter `malloc`-Zaehler). Gemessene Kosten der
Raumkette (48 kHz, M1 Pro, 256er Bloecke): Median 248,9 ns/Sample = 83,7x
Echtzeit, p99 71,8x, schlechtester Block 52,2x. **16 Stimmen plus eine
Raumkette gemeinsam gemessen (nicht hochgerechnet): Median 17,2x, p99 15,4x,
schlechtester Block 12,1x** — Ziel >= 10x eingehalten, harte Untergrenze 5x
mit grossem Abstand. Reine Core-Schicht, noch nicht verdrahtet; 25 neue
Tests, 654/654 Gesamttests gruen.
Zwei geerbte Allokationspfade in `AudioCoreDeepSpaceFDNTail` blieben per
Auftrag offen: `reset()` (2 Allokationen pro Aufruf, seit S-08b-fix bekannt)
und **neu gefunden** `setParameters(_:)` (4 Allokationen pro Aufruf aus dem
`Set<Int>` der Primzahlwahl in `recomputeLineState()`). Beide in W-03a
geschlossen.

**W-03a-Ergebnis (Runde 068):** die beiden offenen Allokationspfade sind zu,
und die Gegenprobe hat einen dritten Fall gefunden, den weder der
Instruktions-Scan noch der Aufruflisten-Scan finden konnte: **aufgeschobene
Allokationen, die nicht in der verursachenden Funktion anfallen, sondern in
der naechsten.** `modPhase = modulationPhaseOffsets` in
`init`/`prepare`/`reset` teilt den Puffer der Konstante statt ihn zu
kopieren; die Copy-on-Write-Kopie wurde erst im ersten `process`-Aufruf
danach faellig — also im Rendercallback (1 je `reset()`). Dazu die faule
`static let`-Initialisierung zweier nur im Renderpfad benutzter
Gewichtstabellen (2 einmalig je Prozess, im allerersten `process`-Aufruf).
Beide behoben. Damit gilt fuer die gesamte Kette derselbe Vertrag wie fuer
die Atmospheric Voice: `process`, `render`, `setParameters(_:)` und `reset()`
duerfen aus dem Rendercallback laufen, nur `init`/`prepare(sampleRate:)`
nicht. Klang bit-identisch zu `b7f26d1` (getrennte Kompilation beider
Quellstaende, 61.022 Werte, identische SHA-1), 3 neue Tests, 657/657
Gesamttests gruen, kein bestehender Test angepasst.
Der Allokationsnachweis ist ab W-03a dreiteilig: Instruktions-Scan,
**demangelter** Aufruflisten-Scan (in rohem SIL heisst `Set` `Sh`) und
Laufzeitmessung, die ausdruecklich die ersten Samples nach
`init`/`prepare`/`reset` mitmisst statt nur den eingeschwungenen Zustand.

**W-03b1-Ergebnis (Runde 070):** `SynthNode.VoicePool` haelt beide
Stimmtypen jetzt gleichzeitig vor — `[AudioCoreVoice]` und
`[AudioCoreAtmosphericVoice]`, beide in Poolgroesse, beide in `prepare()`
aufgebaut; ein `SynthVoiceEngine`-Tag sagt, welcher rendert. Der Renderpfad
verzweigt einmal pro Block und laeuft danach in einer monomorphen Schleife
ueber ein Array eines konkreten Structs: kein existentielles Boxing, kein
Payload-Enum mit Kopie je Zugriff, keine generische Spezialisierung, auf die
man sich verlassen muesste. Im SIL des gesamten Kompilats stehen **null**
`witness_method`, `open_existential_addr` und `alloc_existential_box`.
Der Wechsel reist als Feld von `SynthParams` ueber den bestehenden
Snapshot-/Command-Pfad und legt beide Pools hart still, bevor er das Tag
umlegt — kein Pool-/Graphaufbau im Rendercallback, keine haengende Note im
abgewaehlten Pool. **Der Default bleibt `.legacy`; der Klang ist bei
Default-Einstellung bit-identisch zu `13e5eaf`** (roher
`Float.bitPattern`-Vergleich gegen einen separaten Klon, zwei Sample-Raten x
fuenf Szenarien inklusive Voice-Stealing, Unison, Live-Parameter-Sweeps und
Extremwerten). Die S-01-Baseline blieb unveraendert gruen, kein
Erwartungswert wurde angefasst. 12 neue Tests, 669/669 Gesamttests gruen.

**W-03b2-Ergebnis (Runde 071) — ab hier ist der Synth hoerbar.** Der
Produkt-Default steht auf der Atmospheric Voice (Stephan-Entscheidung
2026-08-02). Er liegt an genau einer Stelle: `AppSettings.AudioConfig
.voiceEngine`, samt Fallback in `load()`. Ein bereits persistierter Wert
gewinnt weiterhin — wer bewusst "Klassisch" gewaehlt hat, bekommt nicht
ungefragt eine andere Stimme.

`SynthParams.defaults.voiceEngine` bleibt bewusst `.legacy`. Das ist kein
halber Default-Wechsel, sondern eine Trennung: `SynthParams` ist der
Kanal-Snapshot, den die `AudioEngine` bildet, und sein Default ist der
neutrale Vorkonfigurationswert vor der ersten Konfiguration — ausserdem der
Anker des Bit-Identitaets-Nachweises, dessen Szenariofolge unveraendert
gegen `13e5eaf` uebersetzbar bleiben muss. Im App-Start ist die Abfolge
belegt: die vier `prepare()`-Zeilen zeigen `voiceEngine=legacy`, 150 ms
davor bzw. danach steht `voiceEngine → atmospheric`, und der erste `noteOn`
faellt erst danach — es klingt nie eine Note auf dem abgewaehlten Pool.

Die S-01-`OfflineSynthBaselineTests` waehlen den Legacy-Pfad jetzt
ausdruecklich und blieben **ohne jede Anpassung eines Erwartungswertes**
gruen (8/8); die Legacy-Pruefsumme ist unveraendert `0x86a4b146fd9f13e9`.
Neu daneben `AtmosphericSynthBaselineTests` (11 Tests) als eigene Baseline
des neuen Pfads: Determinismus auch ueber Voice-Stealing und Unison,
Note-On/Off, All-Off, beide Sample-Raten, Parameterextreme ohne
NaN/Infinity, festgehaltene Referenzmetriken (Peak 0,10232, RMS 0,02956,
Centroid 2034 Hz gegen 305 Hz beim Legacy-Referenzton) und eine harte
Pegelgrenze unterhalb Vollausschlag. 680/680 Gesamttests gruen.

Hoerprobe am Produktpfad (rein sachlich, keine Klangwertung — die faellt
Stephan): zwei Akkorde mit Produkt-Defaults liefern Peak −8,5 dBFS und RMS
−21,8 dBFS gegen −8,9 / −21,5 dBFS auf dem Legacy-Pfad, also kein
Lautheitssprung durch den Default-Wechsel. Kein Sample >= 0,95, kein
nicht-endliches Sample, DC vernachlaessigbar, Peak im letzten 200-ms-Fenster
exakt 0. Knacks-Indikator (groesste Sprungstelle gegen das 99,99-Perzentil
aller Sprungstellen) 1,30 gegen 1,23 beim Legacy-Pfad — keine isolierte
Diskontinuitaet. Bei 44,1 / 48 / 96 kHz gleich; **96 kHz ist die Rate, die
das Geraet real faehrt** — beide Baselines testen 44,1 und 48 kHz, diese
Luecke ist bekannt und gemeldet. *(In Runde 072 geschlossen, siehe unten.)*

**W-03c-Ergebnis (Runde 072) — ab hier ist auch der Raum hoerbar. Die
Verdrahtung des Audio-Tracks ist abgeschlossen.** Der seit S-07a stille
`sharedSpaceSendBus` wird erstmals gespeist: die vier `SynthNode`s sammeln
ihren pro Stimme mit `spaceSendLevel` gewichteten Send in einem
Software-Sammelbus (`SpaceSendBus`), `DeepSpaceReturnNode` zieht ihn durch
die W-02-Kette `AudioCoreDeepSpace` und gibt ihn stereo an den Sammelbus
zurueck.

Die zentrale Entwurfsentscheidung: der Send entsteht in Software und nicht
als Knotenabgriff hinter `gainX`. Grund ist der Slice-Auftrag selbst — der
Send ist PRO STIMME gewichtet, und `spaceSendLevel` existiert nur innerhalb
des `VoicePool`, vor der Summierung der Stimmen. Ein Abgriff auf Graphebene
koennte ihn prinzipiell nicht mehr anwenden. Der in S-07a getestete
Topologie-Deskriptor bleibt trotzdem eingehalten: CH1 greift vor
`compressorBass` ab (Stephans Option A, hier sogar strenger als gefordert,
weil der Abgriff noch vor dem Kanal-Gain liegt), und der Kanalfader wirkt
ueber `SynthParams.spaceSendChannelGain` — derselbe lineare Wert, der auf
`gainX.outputVolume` geht — als Post-Fader-Send. Am Graph selbst aendert
sich minimal etwas: `mainMixerNode` bekommt keinen neuen Eingang, nur der
bisher eingangslose Sammelbus bekommt einen.

Gate 1, der Kern: **bei `spaceSend = 0` ist der Ausgang bit-identisch zu
`4278cf6`, fuer beide Stimmtypen.** Zwei getrennte Nachweise. Erstens eine
Szenario-Pruefsumme des Atmospheric-Trockenpfads ueber 44,1/48/96 kHz mit
Unison, Voice-Stealing, Live-Parametern und All-Off: `0xd6fe9a8b93774ce7`,
erzeugt vor der ersten geaenderten Codezeile und danach unveraendert. Sie
sichert den Umbau ab, der die Atmospheric-Stimmen jetzt ueber einen
Zwischenpuffer rendern laesst. Zweitens ein Vergleich des VOLL verdrahteten
Graphen gegen den Graphen ohne Raum, Bit fuer Bit gleich — fuer beide
Stimmtypen, alle drei Raten, und zusaetzlich bei Kanalfader 0 sowie fuer
die Legacy-Stimme bei vollem Sendpegel (sie hat kein Space-Send-Ziel und
speist den Raum nicht).

Gate 2: der Raumanteil liegt bei Produkt-Sendpegel 23,7 dB unter dem
Trockensignal (gemessen als Differenzsignal `wet − dry`, moeglich weil der
Trockenpfad bitgleich ist), skaliert monoton mit dem Sendpegel und traegt
dort weiter, wo die Stimme laengst verstummt ist. Nach `allNotesOff` faellt
er innerhalb seiner Abklingzeit unter die Stille-Schwelle (Peak im letzten
200-ms-Fenster eines 12-s-Renders: 4,4e−11). Der Raum wird bewusst NICHT
hart zurueckgesetzt — das waere ein hoerbarer Schnitt; kein Command im
Rendercallback loest `reset()` aus.

Der Sendpegel **0,5 ist ausdruecklich VORLAEUFIG**, wie die Zweigpegel der
Kette. Einordnung fuer die Entscheidung: die Kette ist statisch stark
gedaempft (FDN-Ausgangsgain 0,125, Early-Reflection-Tapgains, Zweigpegel je
0,5) — selbst bei Sendpegel 1,0 bleibt der Raum 17,7 dB unter dem
Trockensignal. Mehr Raum ist ueber diesen Regler allein nicht erreichbar.

**96-kHz-Luecke geschlossen, ohne Befund.** Beide Baseline-Suiten haben
einen eigenen 96-kHz-Test bekommen (eigener Test statt erweiterter
Ratenliste, damit kein bestehender Erwartungswert und kein bestehender
Testname angefasst wird). Beide vergleichen zusaetzlich Klangfarbe und
Pegel gegen 44,1 kHz. Ergebnis: Legacy Peak 0,10540 / Centroid 310,8 Hz
gegen 0,10546 / 305,0 Hz bei 44,1 kHz; Atmospheric 0,10228 / 2005 Hz gegen
0,10232 / 2034 Hz. **Kein Problem, das es bei 44,1/48 kHz nicht gibt.**

**Korrektur an der W-03b1-Aussage oben:** "im SIL des gesamten Kompilats
null `witness_method`" ist zu weit gefasst. Derselbe Scan liefert in Runde
071 fuenf Vorkommen — alle ausserhalb des Renderpfads: String-Interpolation
in `SynthNode.prepare()` und `NoteEventQueue.push` (beides bekannte
Nicht-Renderpfade) sowie synthetisierte Protocol-Witness-Thunks der
`Equatable`/`Hashable`/`RawRepresentable`/`Codable`-Konformanzen von
`Waveform`, `SynthVoiceEngine` und `NoteEvent.Kind`. Die inhaltliche
Aussage haelt und ist jetzt praeziser belegt: in allen neun
`VoicePool`-Funktionen und in der 395 Zeilen langen Render-Closure steht
**kein** `witness_method`, `open_existential_addr` oder
`alloc_existential_box`; `_allocateBufferUninitialized` kommt ausschliesslich
in `VoicePool.init` vor. Ursache der zu weiten Aussage: die
Instruktions-Regex des Scanners trifft nur zeilenanfaengliche Vorkommen,
nicht `%59 = witness_method`.

**CPU-Befund aus Runde 070, relevant fuer W-03b2 und W-03c:** ein Kanal mit
16 klingenden Atmospheric-Stimmen laeuft bei Median 22,5x / p99 19,5x /
schlechtester Block 16,9x — Ziel >= 10x deutlich eingehalten. **Vier Kanaele
mit je 16 gleichzeitig klingenden Stimmen (64 Stimmen, pessimistischer
Vollausbau) liegen dagegen bei Median 5,6x / p99 5,3x / schlechtester Block
5,1x** — oberhalb der harten Untergrenze 5x, aber klar unterhalb des Ziels
10x, und das noch OHNE die DeepSpace-Kette aus W-03c. Zum Vergleich
dieselbe Messung mit der Legacy-Stimme: 28,2x / 24,2x / 21,1x. Der Fall ist
im realen Spiel unwahrscheinlich (die vier Kanaele sind nicht gleichzeitig
voll polyphon), aber er ist der Fall, den das Budget meint. Vor W-03c ist
entweder eine Messung der realistischen Stimmverteilung oder eine
Begrenzung der Polyphonie zu klaeren — Stephan-Entscheidung, nicht
Coder-Entscheidung.

**CPU mit Raum, gemessen in Runde 072** (M1 Pro, 48 kHz, 256er Bloecke,
vier Kanaele, Realtime-Faktor Median / p99 / schlechtester Block):

| Bezugslast | ohne Raum | mit Raum |
|---|---|---|
| leer (nur Grundlast) | 711 / 610 / 97x | 96 / 78 / 49x |
| 8 Stimmen (2 je Kanal) | 42,3 / 37,7 / 22,4x | 30,3 / 26,8 / 19,0x |
| 16 Stimmen (4 je Kanal) | 21,9 / 19,9 / 17,0x | 18,0 / 16,3 / 12,5x |
| 24 Stimmen (6 je Kanal) | 14,7 / 13,3 / 10,6x | 12,8 / 11,4 / 9,6x |
| 32 Stimmen (8 je Kanal) | 11,1 / 10,2 / 9,0x | 10,0 / 8,5 / 6,9x |
| 48 Stimmen (12 je Kanal) | 7,3 / 6,4 / 5,8x | 6,7 / 5,9 / 4,7x |
| 64 Stimmen (Vollausbau) | 5,5 / 5,0 / 4,5x | 5,2 / 4,7 / 2,9x |

**Bezugslast ausdruecklich benannt:** realistisch klingen etwa 10 Stimmen
gleichzeitig, mit ueberlappenden Release-Fahnen 20-25. In diesem Bereich
liegt die Kette MIT Raum bei Median 12,8-30x und schlechtestem Block
9,6-19x — das Ziel >= 10x ist im Median klar, in der Spitze knapp
eingehalten. Der Raum kostet dort 15-25 % der Reserve; seine reine
Grundlast ist mit 96x vernachlaessigbar (rund 1 % eines Kerns).

Der Vollausbau 64 faellt mit Raum im schlechtesten Block auf 2,9x und damit
unter die harte Untergrenze — er tat das aber schon ohne Raum knapp (4,5x)
und ist unveraendert die offene Poolgroessen-Frage aus Finding W-03b1-01,
kein Befund dieses Slices.

Stephan hat die drei SYNTH-00-Fundamentgates am 2026-07-29 bestaetigt
(eigener Swift/Accelerate-DSP-Kern, Wavetable-Morph+Textur vor Granular,
bestehende Defaults bis zur Klangabnahme unveraendert). S-01 liefert einen
Offline-Render-Harness gegen den echten `SynthNode`-Pfad plus
Baseline-Metriken/-Tests. S-02a legt das neue Target `HarmonyAudioCore`
als reine, testbare DSP-Schicht an (Value-Modelle, feste Render-API,
Legacy-Oszillator/ADSR/Filter/Pan behavior-nah zu der frueheren
`SynthVoice`). S-02b (Deep-Review-pflichtig) schaltet den aktiven
`SynthNode`-Renderpfad jetzt tatsaechlich auf `HarmonyAudioCore` um:
`VoicePool` rendert Stimmen ueber `AudioCoreVoice` statt der alten,
jetzt entfernten `SynthVoice`-Duplikat-DSP; Voice-Stealing, Unison-
Verteilung, Live-Filter/-Sustain, Audio-Graph, `NoteEventQueue`,
`AudioEngine.commandQueue` und Output-Vertrag bleiben unveraendert. Die
S-01-Offline-Baseline bleibt gruen innerhalb bestehender Toleranzen
(Details: `SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 14, Audio Milestone A1).
S-03 legt ein versioniertes Audio-Presetmodell samt Validator, vier
Legacy-Factory-Presets, atomischem User-Store (Application Support) und
verlustfreier `ChannelFXConfig`-Migration an (`Sources/HarmonyEngine3D/
AudioPreset/`) — reine Daten-/Persistenzinfrastruktur, noch keine aktive
Preset-Auswahl und kein Runtime-/Default-Wechsel im Produkt. S-04a
(Audio Milestone A2, Source A) legt eine kleine prozedurale Factory-
Wavetable-Bank (`warmOdd`/`brightFull`, je 7 bandlimitierte Mip-Stufen)
und einen phasenkonsistenten `AudioCoreMorphOscillator` in
`HarmonyAudioCore` an — reine DSP-Infrastruktur, noch nicht in
`AudioCoreVoice`/`SynthNode` verdrahtet, kein Klang-/Default-Wechsel
(Details: `SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 14, Audio Milestone A2).
S-04a-fix behebt einen vom Supervisor-Review gefundenen Randfall: eine
nicht-endliche Phase (`.nan`/`.infinity`) konnte in
`AudioCoreWavetable.sample(phase:)` bzw. nach
`AudioCoreMorphOscillator.resetPhase(to:)` in eine trappende
`Double -> Int`-Konvertierung laufen; beide Stellen fallen jetzt
kontrolliert auf Phase `0` zurueck, vier neue Regressionstests decken den
Pfad ab. S-04b (Audio Milestone A2, Source B/Texture C/Mixmodi) ergaenzt
`AudioCoreSourceB` (zweite, unabhaengige Morph-Oszillator-Quelle mit
Transposition/Feinstimmung/eigener Phase), `AudioCoreTextureSource`
(deterministische gefaerbte Rauschquelle mit explizitem xorshift64-Zustand
und stabiler One-Pole-Farbfilterung) und `AudioCoreMixer` (feste Mixmodi:
linearer Mix, Ringmodulation, reduzierte patchgraph-freie
Phasenmodulationsvariante) — weiterhin reine `HarmonyAudioCore`-DSP-
Infrastruktur, noch nicht in `AudioCoreVoice`/`SynthNode` verdrahtet, kein
Klang-/Default-Wechsel. S-05a (Audio Milestone A2, Amp-/Mod-Huelle und
LFOs) ergaenzt einen eigenstaendigen ADSR-Huellkurven-Baustein
(`AudioCoreEnvelope`, wiederverwendbar fuer Amp- UND Mod-Rolle als getrennte
Instanzen/Parameterprofile) und einen LFO-Baustein mit Sine/Triangle/
Sample-and-Hold/geglaettetem Random (`AudioCoreLFO`, Frequenz bewusst auf
0…200 Hz begrenzt) — weiterhin reine `HarmonyAudioCore`-DSP-Infrastruktur,
noch keine Modulationsmatrix/Makros, noch nicht in
`AudioCoreVoice`/`SynthNode` verdrahtet. S-05b (Audio Milestone A2, feste
Modulationsmatrix und vier Performance-Makros) ergaenzt die vier stabilen
Makros Motion/Color/Space/Focus (`AudioCoreMacroID`/`AudioCoreMacroValues`),
eine feste interne Zielmenge (`AudioCoreModulationTarget`), typisierte
Source-Referenzen auf Makro/LFO-Slot/Huellenrolle
(`AudioCoreModulationSource`) und eine feste Modulationsmatrix mit
hoechstens 16 deterministisch akkumulierenden Routen
(`AudioCoreModulationMatrix`/`AudioCoreModulationRoute`) sowie einen
wiederverwendbaren One-Pole-Glaettungsbaustein
(`AudioCoreParameterSmoother`) — weiterhin reine `HarmonyAudioCore`-Daten-/
DSP-Infrastruktur, noch nicht in `AudioCoreVoice`/`SynthNode`/Presets/UI
verdrahtet. S-06 (Filter/Shaping) ergaenzt einen stabilen
State-Variable-Filter (Lowpass/Bandpass/Highpass, Zero-Delay-Feedback-
Topologie), einen einfachen Ein-Pol-Send-Highpass fuer spaetere Echo-/
Hall-Sends und einen zustandslosen `tanh`-Waveshaper mit Pegelkompensation
(`AudioCoreStateVariableFilter`, `AudioCoreSendHighpass`,
`AudioCoreWaveshaper`) — weiterhin reine `HarmonyAudioCore`-DSP-
Infrastruktur, noch nicht in `AudioCoreVoice`/`SynthNode`/Presets/UI
verdrahtet, kein Klang-/Default-Wechsel. S-07a (Audio Milestone A3,
Space-Engine-Vorbereitung) bereitet `AudioEngine.setupGraph()` auf
gemeinsame Echo-/Space-Send-Busse vor: zwei neue, an `mainMixerNode`
angeschlossene, aber von keinem Kanal gespeiste `AVAudioMixerNode`-Busse
(`sharedEchoSendBus`/`sharedSpaceSendBus`) sowie ein reiner, hardware-
unabhaengiger Topologie-Deskriptor (`AudioGraphTopology.swift`), der
Stephans Option-A-Entscheidung fuer den CH1-Kompressor kodiert (Send-
Abgriff vor `compressorBass`, nicht danach). Die vier bestehenden
kanalgetrennten Legacy-FX-Ketten inkl. CH1-Kompressor bleiben
unveraendert aktiv und alleiniger Klangpfad; noch kein `EchoField`/
`DeepSpace`-DSP, kein Default-Klangwechsel. Das offene V-02-DualSense-/
30-Minuten-Gate bleibt davon unveraendert. S-07b migriert die heutigen
Drei-Tap-Delay-Settings in ein neues, eigenstaendiges `EchoFieldPreset`-
Modell (`Sources/HarmonyEngine3D/AudioPreset/EchoFieldPreset.swift` +
Validator/Codec/Factory/Migration): exakt vier benannte Tap-Slots
(`tap1`…`tap4`), Tap 1-3 feldgenau aus `ChannelFXConfig`/`AudioSynthPreset`
migrierbar (zwei unabhaengige, konsistente Migrationspfade), Tap 4
deterministisch neutral/stumm. Reine Daten-/Presetinfrastruktur — kein
`EchoField`-DSP, keine Verbindung an `sharedEchoSendBus`, keine
`AudioEngine`-/`AppSettings`-/UI-Aenderung, kein Klang-/Default-Wechsel.
S-08a legt den ersten `DeepSpace`-Baustein an
(`Sources/HarmonyAudioCore/AudioCoreDeepSpaceEarlyReflections.swift`,
`AudioCoreDeepSpaceDiffuser.swift`, `AudioCoreDeepSpaceParameters.swift`):
sieben feste, deterministische Early-Reflection-Taps mit endlicher
FIR-Impulsantwort und ein vierstufiger Schroeder-Allpass-Diffusor je
Kanal, beide reine, entkoppelte `HarmonyAudioCore`-DSP-Bausteine analog zu
SVF/Send-Highpass/Waveshaper aus S-06. Weder ein FDN-Tail noch eine
Verbindung an `sharedSpaceSendBus` sind Teil dieses Slices. Details inkl.
eines waehrend der Umsetzung gefundenen und korrigierten
Allpass-DSP-Fehlers: `SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 14, Audio
Milestone A3.
S-08a-fix schliesst einen im Supervisor-Deep-Review von S-08a gefundenen
Randfall (Finding S-08a-01): `AudioCoreDeepSpaceParameters` klemmte nur im
`init`, direkte Feldmutation nach der Konstruktion umging die Klemmung
ueber `setParameters(_:)` vollstaendig — verifizierter Trap (SIGTRAP) in
`AudioCoreDeepSpaceEarlyReflections.recomputeTapDelays()` bei
nicht-endlichem `size`/`preDelaySeconds` sowie ein Diffusor-Runaway bei
`diffusion > 1`. `setParameters(_:)` baut den Parametersatz jetzt bei
beiden Typen ueber den bestehenden `init`-Klemmpfad neu auf, zusaetzlich
ein redundanter Endlichkeits-Guard direkt vor der trappenden
`Double -> Int`-Konvertierung — dasselbe zweistufige Muster wie
S-04a-fix. Details: `SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 14, Audio
Milestone A3.
S-08b hat zwei Teile. Teil 1 schliesst Finding S-08a-02: `safeSampleRate`
klemmte bisher nur nach unten, eine endliche, aber absurd grosse Sample
Rate (`1e300`) liess Pufferlaengen-Konvertierungen in beiden bestehenden
`DeepSpace`-Typen trappen. `AudioCoreDeepSpaceParameters.maxSampleRate`
(1.000.000 Hz) plus eine gemeinsame `safeSampleRate(_:)`-Funktion sind
jetzt die eine Klemmstelle fuer die gesamte `DeepSpace`-Familie statt einer
Kopie pro Typ. Teil 2 ist der modulationsfreie FDN-Tail
(`AudioCoreDeepSpaceFDNParameters.swift`, `AudioCoreDeepSpaceFDNMatrix.swift`,
`AudioCoreDeepSpaceFDNTail.swift`): acht Delaylinien mit auf Primzahlen
gerundeten, paarweise teilerfremden Laengen, eine energieerhaltende
Ordnung-8-Hadamard-Feedback-Matrix, ein Ein-Pol-Tiefpass je Linie fuer
frequenzabhaengige Daempfung und ein RT60-basierter Rundlauf-Gain je Linie
— fuer jedes endliche `decay` streng unter 1, keine Selbstoszillation
moeglich. Weiterhin reine, entkoppelte `HarmonyAudioCore`-DSP-
Infrastruktur, kein Zusammenschalten mit Early Reflections/Diffusor, keine
Send-Bus-Verbindung. Die Delaymodulation ist bewusst als S-08c
nachgeschoben (eigener Risikoblock mit eigenen Artefakt-/
Determinismusgates). Details: `SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 14,
Audio Milestone A3.
S-08b-fix schliesst Finding S-08b-01 (Supervisor-Deep-Review von S-08b):
`AudioCoreDeepSpaceFDNTail.process` alloziierte pro Sample auf dem Heap
(zwei lokale Arrays plus ein drittes in `AudioCoreDeepSpaceFDNMatrix.apply`),
und der Dateikommentar rechtfertigte das mit einer falschen Aussage ueber
die Bestandstypen. Drei feste Scratch-Puffer (angelegt in `init`/
`prepare(sampleRate:)`), eine puffer-schreibende Matrixform
(`apply(_:into:)`) und ein flacher Delay-Speicher mit festem Offset je
Linie statt `[[Float]]` machen den Renderpfad jetzt allokationsfrei — per
SIL belegt (0x `_allocateBufferUninitialized` in `process` und in der
inline-spezialisierten `apply(_:into:)`). Bit-Identitaet zu Commit
`4c49ed9` per deterministischem FNV-1a-Checksum-Regressionstest
nachgewiesen. Reine Ausfuehrungsform-Aenderung, keine Aenderung an
Linienlaengen/Gains/RT60-Formel/Daempfung/Matrixwerten. Details:
`SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 14, Audio Milestone A3.
S-08c ergaenzt den zuvor modulationsfreien FDN-Tail um langsame,
dekorrelierte Delaymodulation im Feedbackpfad
(`SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 7.3): zwei neue Parameter
`modulationDepth`/`modulationRate` (Default `modulationDepth = 0` — kein
Verhaltenswechsel fuer bestehende Aufrufer), acht per Kronecker-Folgen
(goldener/silberner Schnitt) dekorrelierte Modulationsverlaeufe je
Delaylinie, lineare Interpolation der fraktionalen Leseposition (als
Konvexkombination beweisbar amplitudenbeschraenkt, haelt das bestehende
S-08b-Stabilitaetsargument unveraendert), und eine bei Init/Prepare fest
bemessene Kapazitaetsreserve statt Laufzeitklemmung der Leseposition. Bei
Modulationstiefe 0 laeuft der textuell unveraenderte S-08b-fix-Lesepfad —
bit-identisch zu Commit `01085ba`, per bestehendem und neuem
Checksum-Regressionstest belegt. `process` bleibt allokationsfrei, erneut
per SIL belegt. Details: `SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 14, Audio
Milestone A3.
Runde 064 raeumt zwei kleine, zusammengehoerige Korrekturen auf
unverdrahtetem `DeepSpace`-Core-Code auf: die harte `±1`-Ausgangsklemmung
in `AudioCoreDeepSpaceEarlyReflections.process(_:)` ist entfernt
(Stephan-Entscheidung 1 vom 2026-08-01 — Diffusor/FDN-Tail klemmen nicht,
der Baustein ist fuer einen Send-Bus gebaut, Begrenzung gehoert ans Ende
der Kette), der Normalfall (Eingang <= 1,0) bleibt bit-identisch. Zusaetzlich
bekommt `safeSampleRate` eine Untergrenze (`minSampleRate = 100 Hz`) gegen
degenerierenden Phasenlauf im FDN-Tail unterhalb von ca. 0,7 Hz
(S-08c-Review-Beobachtung) — eine rein technische Sicherheitsgrenze.
Details: `SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 14, Audio Milestone A3.

### Audio-Track B — Klangvokabular

Von Stephan am 2026-08-02 freigegeben; nachgetragen in Runde 071 aus
`.agent_handoff/checkpoint.md`. **Wird erst NACH W-05 aktiviert** — bis
dahin gilt der Timing-Vorbehalt unten.

Der Supervisor hat den Ist-Zustand gegen den Code geprueft, statt die
Wunschliste ungeprueft zu uebernehmen:

| Zutat | Ist-Zustand (verifiziert) |
|---|---|
| Velocity als Modulationsquelle | **fehlt** — `AudioCoreModulationSource` kennt nur `macro`, `lfo`, `envelope` |
| Oszillator-Hardsync | **fehlt** — kein Treffer im Quellbaum |
| PWM / Pulsweite | **fehlt** — kein Treffer |
| Ensemble/Chorus | **fehlt** — nur eine Kommentarerwaehnung im FDN-Tail |
| Per-Stimme-Drift | **fehlt** — der seeded xorshift existiert nur in der Texturquelle |
| SVF-Selbstoszillation | **nein** — `q = 0.5 + resonance * 19.5`, also max. Q 20 und `k = 1/Q = 0,05`. Die Daempfung ist klein, aber ungleich null: der Filter klingelt lang und faellt ab, er schwingt nicht selbst. Echte Selbstoszillation braucht `k -> 0` |
| Klassische Wellenformen | **Korrektur zur Vorlage:** Saegezahn, Rechteck und Dreieck existieren bereits als PolyBLEP-bandlimitierte Formen in `AudioCoreWaveform`/`AudioCoreVoice` — aber nur im LEGACY-Pfad. Die Wavetable-Bank des Morph-Oszillators kennt nur `warmOdd` und `brightFull`. Die Arbeit ist Portierung/Erweiterung, nicht Neuschreiben |

**Freigegebene Reihenfolge (Stephan):**

1. **Filtermodi erweitern** — Ladder-Topologie neben dem SVF, plus echte
   Selbstoszillation. Groesste Einzelwirkung, weil der Filtercharakter die
   Identitaet praegt.
2. **Wellenformsatz in der Wavetable-Bank plus PWM.** PWM ist ein
   kontinuierlicher Parameter, kein Tabellen-Morph — braucht einen eigenen
   Weg.
3. **Ensemble/Chorus.** Ein bis zwei kurz modulierte Delays; verglichen mit
   dem FDN ein winziges Modul mit grosser Wirkung auf Flaechen.
4. **Per-Stimme-Drift**, seeded pro Stimme — kollidiert nicht mit der
   Determinismus-Anforderung, wenn es wie die Texturquelle aufgebaut ist.
5. **Velocity als Modulationsquelle** in der Matrix.
6. Optional, nachgetragen: **Oszillator-Hardsync**.

Danach eine **Voicing-Runde, in der Stephan die Presets baut, nicht der
Coder.** Genau dafuer ist die CC-Steuerung aus W-05 gedacht.

**Timing-Vorbehalt, von Stephan mitgetragen:** Diese Liste wird erst nach
W-05 aktiviert. Sie entstand, bevor Stephan den Synth gehoert hatte; nach
W-03b2 (Grundstimme, seit Runde 071 hoerbar) und W-03c (Raum) wird er die
Prioritaeten vermutlich anders setzen als die Liste vermutet. Die
Reihenfolge ist freigegeben, aber nicht in Stein.

**Rahmen, unveraendert:** Charakter nachbauen ist legitim, proprietaere
Algorithmen, Presets oder Namen zu uebernehmen nicht — dieselbe Linie wie
beim Absynth-Vorbild. Die relevanten Filtertopologien sind Lehrbuchwissen,
genau wie die bereits verwendeten Schroeder-Allpaesse und die Jot-FDN. Und:
Klassiker sind Nebenprodukt, nicht Ziel. Das Produkt bleibt ein
atmosphaerischer Spatial Synth fuer ein 3D-Harmonieinstrument.

### Entscheidungen, die nicht F-01 bis F-03 blockieren

1. Welche aktuellen dirty/untracked Dateien gehören zur Produkt-Baseline?
2. Wird HarmonyWeb nach E-03 Default oder zunächst normal auswählbarer Modus?
3. Wie werden proximity- und harmonic-Magnet fachlich arbitriert?
4. Bleibt das 2D-Workspace-Layout Sidecar oder wird es später portabel im
   Schema versioniert?
5. Welche Art Direction gilt für den V1-Polish?

### Nach V1

UI-Funktionsaudit, Art Direction, Expressive Control, Touchpad-Melodie,
web-spezifisches `HarmonyLogicProfile`, Multi-Layer-Livewechsel,
Multi-Web-Navigation, Spatial Index nach Messung, vollständige
Swift-6-Konformität und iPhone.

---

## Historische Gesamtübersicht bis Rev. 6

Das Projekt hat **drei parallele Streams**. Tech- und Konzept-Stream vereinigen sich in Stufe 3. Der Content-Stream läuft dauerhaft parallel und ist organisatorisch getrennt:

```
TECH-STREAM                         KONZEPT-STREAM          CONTENT-STREAM
(Architektur / Extraktion)          (Harmonisches Netzmodell) (HarmonyWeb Authoring)

Stufe 1 – Technische Basis          Stufe K – Konzeptarbeit   ← dauerhaft parallel
  Phase 0: Tech-Schulden              K1: Beziehungssprache     Neuer HarmonyWeb-Claude
  Phase 1: HarmonyCore                K2: Abstraktes Modell     HarmonyWebs erstellen
                                      K3: Magnetphysik          HarmonyLogic pflegen
                                      K4: Formatentscheidung    Kein Code-Zugriff
                                      K5: JSON-Schema

         ▼                                    ▼                  ▼ (unabhängig)
         └──────────── Stufe 2 ───────────────┘
                   Netzwerkmodell implementieren
                   (erfordert beide Streams ✓)

                        ▼
               Stufe 3 – Construction Kit
               (Editor, Validator, Importer)

                        ▼
              Stufe 3.9 – Reparatur & Fundament   ◀── HIER STEHT DAS PROJEKT
              (hörbare Fehler, Modus-Wahrheit,
               Anker/Render-Trennung)

                        ▼
              Stufe 4 – 3D-Raumintegration
              (semantische Koordinaten, Magnetlogik,
               UI-Konsolidierung, Expressive Control,
               Art Direction)

                        ▼
              Stufe 5 – Ausbau & Plattform
              (Multi-Layer, Multi-Web Navigation)
```

> **Hinweis zum Stand (Rev. 6):** Die Stufen sind nicht streng sequenziell abgearbeitet worden.
> Teile von Stufe 2 (GraphEngine), 3.3 (Runtime-Importer) und 4.3 (RuntimeHarmonik) existieren
> bereits im Code, während Stufe 1 und 1.5 offen sind. Stufe 3.9 räumt die Folgen dieser
> Reihenfolge auf. Die Statusspalte in der Meilenstein-Tabelle ist entsprechend korrigiert.

---

## Erledigte Phasen ✅

| Phase | Inhalt | Ergebnis |
|---|---|---|
| OutputCoordinator | App Layer trennt Events von Ausgabe | `OutputCoordinator.swift` |
| AudioOutput-Protokoll | `noteOn / noteOff / allNotesOff` | `AudioOutput.swift` |
| AudioEngine Architektur | SynthNode + AVAudioEngine-Graph | `AudioEngine.swift` |
| Sampler entfernt | Reines Synth-Modell; SF2/Sampler vollständig rückgebaut | Phase 3E |
| Ambient-Raum | 3-Tap-Delay + Reverb pro Kanal | Graph vollständig |
| SynthNode | SPSC-Queue, 16 Voices, ADSR, Oldest-Stealing | `SynthNode.swift`, `SynthVoice.swift` |
| SynthNode Stabilisierung | Oldest-Stealing, 2. Harmonische, Pitch-Fix, Klick-Fix | Phase 3E |
| MIDIManager bereinigt | Thread-Safety, doppelte Implementierung konsolidiert | `MIDIManager.swift` |
| AppSettings Sub-Configs | FlightConfig, MIDIConfig, RenderConfig, HarmonyConfig, AudioConfig | teilweise |
| InputProvider-Protokoll | `GamepadController` conformt | teilweise |
| K1 Beziehungssprache | 6 RelationTypes final: V-I, ii-V, relMajMin, parallelMajMin, commonTone, tritSubst | `HarmonyNetwork_Spec_v1.md` |
| K2 Datenmodell | HarmonyNode, HarmonyEdge, MagnetProfile, HarmonyLayer, HarmonyMap definiert | `HarmonyNetwork_Spec_v1.md` |
| K4 Formatentscheidung | JSON, schemaVersion "1.0", Layout optional im Node | `HarmonyNetwork_Spec_v1.md` |

> **Zurückgezogen in Rev. 6:** Der Eintrag „Eventpfade symmetrisch" stand hier bis Rev. 5 als erledigt.
> Der Review 3.9.8 hat das widerlegt: `noteOff` wird aus der *aktuellen* Oktavverschiebung rekonstruiert
> statt aus der tatsächlich gesendeten Note. Ein Octave-Shift über gehaltenen Noten erzeugt hängende Noten.
> Die Invariante On/Off-Symmetrie ist damit **derzeit verletzt**. Reparatur: Phase 3.9.1a.

---

## Invarianten (gelten für alle Phasen, unveränderlich)

- System ist nach jedem abgeschlossenen Schritt **buildbar und lauffähig**
- Keine Logik in HarmonyScene (Zielzustand nach Phase 1)
- Kein `MIDIManager`-Zugriff außerhalb von `OutputCoordinator`
- Kein `AppSettings.shared` in HarmonyCore (nach Phase 1)
- Render-Closure des Synth: keine Allokationen, kein Swift-Concurrency
- `SeededRNG` bleibt deterministisch: gleicher Seed = identische Welt
  - **Gilt auch für Laufzeit-Entscheidungen.** Eine Auswahl über eine `Dictionary`-Iteration ist *nicht*
    deterministisch — Swift seedet den Hash pro Prozessstart neu. Tie-Breaks müssen explizit
    über einen stabilen Schlüssel aufgelöst werden. *(derzeit verletzt → Phase 3.9.1b)*
- Netzwerk erzeugt Möglichkeiten — Navigation wählt daraus (strikte Trennung)
- **On/Off-Symmetrie:** Jedes klangerzeugende Objekt liefert symmetrisches `noteOn`/`noteOff` — gleiche Note, gleiche Oktavverschiebung. Kein `allNotesOff` als Ersatz für fehlendes `noteOff`. *(derzeit verletzt → Phase 3.9.1a)*
- **Logischer Anker ≠ Render-Position:** Trigger, Distanzen, Kandidatenwahl, Notes und Fades rechnen ausschließlich auf unveränderlichen Ankerpositionen. Animierte Render-Positionen dürfen niemals musikalische Ereignisse auslösen. *(ab Phase 3.9.3a)*
- **CH3-Mapping:** Der aktive Akkord liefert CH3 nur die Mapping-Tabelle (nearestChordNotes), nicht das Trigger-Ereignis selbst. Eventquelle bleibt der Input Layer.
- Keine temporären Workarounds ohne dokumentierten Abbauplan

---

## Verantwortlichkeiten der Schichten

*(Prüfschablone für jeden Fix und jede neue Funktion)*

### Input Layer
Liefert nur Eingabezustände und Rohereignisse.
Keine Harmonielogik. Keine Audioausgabe. Keine Rekonstruktion musikalischer Zustände.

### Eventquelle / HarmonyCore
Erzeugt vollständige musikalische Ereignisse.
Definiert, welche Note wann beginnt und wann endet.
Muss On/Off-Symmetrie liefern.
Darf keine Audio-, UI- oder Renderlogik enthalten.

### OutputCoordinator
Übersetzt musikalische Ereignisse 1:1 in `AudioOutput`-Aufrufe.
Kein Note-Tracking. Kein Erraten fehlender Off-Ereignisse. Keine musikalische Logik.

### AudioEngine / Output Layer
Routet nur `noteOn` / `noteOff` / `allNotesOff`.
Keine Harmonie- oder Timinglogik. Keine Entscheidung, welche Note gespielt oder beendet wird.

### SynthNode
Erzeugt nur Klang.
ADSR, Polyphonie, Voice-Stealing und Klangparameter leben hier.
Keine Kenntnis über Objekte, Trigger, Proximity oder Netzwerk.

### HarmonyScene
Nur SceneKit-Darstellung und Kopplung an den Render-Thread.
Keine Businesslogik im Zielzustand nach Phase 1.

### Verbotene Vermischungen

- Kein Note-Tracking im `OutputCoordinator`
- Kein Erfinden fehlender `noteOff`-Events außerhalb der Eventquelle
- Keine musikalische Logik in `AudioEngine`
- Keine Klangentscheidungen in `HarmonyCore`
- Keine Businesslogik in `HarmonyScene` nach Phase 1
- Kein kanalabhängiger Sonderweg ohne explizite Designentscheidung und Dokumentation

---

---

# STUFE 1 — Technische Basis

> Ziel: Saubere, risikoarme Grundlage vor aller Kernarbeit.
> **Wird vollständig abgeschlossen bevor Stufe 2 beginnt.**
> Konzept-Stream (Stufe K) kann parallel laufen.

---

## Phase 0 — Technische Schulden abbauen

**Priorität: JETZT | Risiko: niedrig–mittel | Voraussetzung: –**

### 0.1 MIDIManager: Thread-Safety
- `activeChordNotes`, `activeBassNote` ohne Synchronisierung von `DispatchQueue.global(qos: .userInteractive)` erreichbar
- Fix: NSLock oder serielle Queue
- Datei: `MIDIManager.swift` (HarmonyEngine3D)

### 0.2 Main-Thread-Korrektur: TargetingOverlayModel
- `updateTargets()` schreibt vom SceneKit-Render-Thread auf `@Published`-Properties
- Fix: Schreibzugriff in `DispatchQueue.main.async`
- Keine Funktionsänderung
- Datei: `SceneKitView.swift` (Coordinator.updateTargets)

### 0.3 MIDIManager: Doppelimplementierung vereinheitlichen
- `HarmonyEngine3D/MIDIManager.swift` und `DesignerKit/MIDIManager.swift` divergieren
- Fix: gemeinsame Version in `HarmonyShared` oder eigenem Modul
- Voraussetzung für Phase 7 (iPhone)

### 0.4 AudioConfig: Persistenz vervollständigen und tote Felder entfernen
- `masterVolume` noch nicht in UserDefaults persistiert
- `samplerEnabled` und `synthEnabled` sind nach dem Sampler-Rückbau bedeutungslos —
  prüfen ob entfernbar; `outputMode` allein ist vermutlich ausreichend
- Fix: aktiv genutzte Felder persistieren; tote Felder entfernen; bestehende Keys nicht umbenennen
- Datei: `AppSettings.swift`

### 0.5 HALC-Startup-Transient *(optional, kein Blocker)*
- `HALC_ProxyIOContext: skipping cycle due to overload` bei AudioEngine-Start
- Selbstlimitierend (< 500 ms), kein Datenverlust
- Optionaler Fix: ~200 ms Verzögerung bei AudioEngine-Init
- Erst angehen wenn Startup-Last wächst

### 0.6 AudioEngine: CH3-Kanalzug vervollständigen

**Priorität: HOCH | Risiko: niedrig | Voraussetzung: –**

- CH3 erhält eigenen vollständigen Signalpfad:
  `gainChordTone` → Delay-Sends → eigene Delays → `sumChordTone` → `reverbChordTone`
- `applyFXConfig(_, channel: 3)` wird voll funktionsfähig
- Ziel: 4 Synths → 4 vollständige, gleichwertige Audiokanäle
- Dateien: `AudioEngine.swift`, `AudioMixerPanel.swift`, `AppSettings.swift`

### 0.7 Synth-Ausbau

**Priorität: HOCH | Risiko: niedrig | Voraussetzung: 0.6**

- `SynthParams` erweitern: Wellenform wählbar (sine, saw, square, triangle)
- Filter-Parameter: `filterCutoff`, `filterResonance` (bereits reserviert in `SynthParams`)
- ADSR vollständig per Kanal steuerbar
- Klangparameter verbleiben vollständig in der Synth-Schicht — keine Logik in AudioEngine
- Dateien: `SynthParams.swift`, `SynthNode.swift`, `SynthVoice.swift`, ggf. `AudioMixerPanel.swift`

### 0.8 AudioClock — Stabile Zeitbasis

**Priorität: MITTEL | Risiko: niedrig | Voraussetzung: 0.6**

> Reine Infrastruktur. Keine Integration in bestehende Systeme.

- `AudioClock`-Klasse: BPM verwalten, kontinuierliche Zeitbasis, Tick-Erzeugung
- Zeitbasis ist audio-getrieben (kein `Timer`) — stabil gegenüber Frame-Drops
- Öffentliche API:
  - `currentTime: Double` — absolute Zeit in Sekunden
  - `beatPhase: Double` — Position im aktuellen Beat (0…1)
  - `onTick: (() -> Void)?` — Callback pro Beat (Main-Thread-Dispatch)
  - `bpm: Double` — setzbar, wirkt beim nächsten Beat
- Instanz in `AppModel` halten — keine Verbindung zu Melody, Chord oder Proximity
- Clock läuft unabhängig von UI und SceneKit
- Datei: `AudioClock.swift` (neues File in HarmonyEngine3D)

### 0.9 K3-Fix: Opacity-Check in ProximityTracker

**Priorität: HOCH | Risiko: niedrig | Voraussetzung: –**

- `ProximityTracker` schließt Nodes mit `opacity ≤ 0` aus der Proximity-Berechnung aus
- Unsichtbare Nodes können aktuell Akkord-Trigger auslösen — funktionaler Fehler, kein kosmetisches Problem
- Fix: Opacity-Filterung vor der Distanzberechnung; `HarmonyScene` übergibt aktuellen Opacity-Wert der Nodes
- Dateien: `ProximityTracker.swift`, `HarmonyScene.swift`

### 0.10 minimal.sf2 entfernen

**Priorität: NIEDRIG | Risiko: trivial | Voraussetzung: –**

- `minimal.sf2` liegt seit Phase 3E (Sampler-Rückbau) ungenutzt im Bundle
- Entfernen reduziert Bundle-Größe, eliminiert toten Ressourcen-Eintrag
- Datei: `Sources/HarmonyEngine3D/Resources/` + ggf. verbleibende Referenzen prüfen

### 0.11 SETUP.md aktualisieren

**Priorität: NIEDRIG | Risiko: trivial | Voraussetzung: Phase 0 abgeschlossen**

- `SETUP.md` spiegelt nicht den aktuellen Build- und Einrichtungsprozess wider
- Aktualisierung auf aktuellen Stand: Xcode-Version, SPM-Targets, Startschritte
- Kein Code — reine Dokumentationspflege

---

## Phase 1 — HarmonyCore extrahieren

**Priorität: HÖCHSTE | Risiko: mittel | Voraussetzung: Phase 0**

> `HarmonyScene` wird reiner SceneKit-Renderer.
> Businesslogik gehört in ein eigenes, testbares `HarmonyCore`-Modul.
> Die Zielarchitektur beschreibt den Zustand **nach Phase 1** — nicht den aktuellen Stand.
> Aktuell enthält `HarmonyScene` noch Proximity-, Trigger- und Melodie-Logik.
> System bleibt nach jeder Teilphase lauffähig.

**Zielzustand Package.swift:**
```
HarmonyShared     (AutopilotEngine, NetworkParser, EdgeData, ChordData)
HarmonyCore       (ProximityTracker, TriggerEngine, MelodyEngine, WorldGeneration)
HarmonyEngine3D   (SceneKit-Renderer, SwiftUI, FlightController, App Layer)
DesignerKit       (unverändert)
```

### 1a — Proximity + Trigger
- `ProximityTracker.swift` → HarmonyCore (kein SceneKit, kein AppSettings)
- `TriggerEngine.swift` → HarmonyCore
- HarmonyScene empfängt Events via Closures, löst sie nicht mehr selbst aus
- Dateien: `HarmonyScene.swift`, `ProximityTracker.swift`, `TriggerEngine.swift`

### 1b — MelodyEngine
- `MelodyPreset` + Ablauflogik → `MelodyEngine.swift` in HarmonyCore
- Kein SceneKit-Bezug, keine `AppSettings`-Direktzugriffe
- Dateien: `HarmonyScene.swift`, `MelodyEngine.swift`

### 1c — WorldGeneration
- `ChunkCoord`, `SeededRNG`, Chunk-Aufbaulogik → `WorldGeneration.swift` in HarmonyCore
- SeededRNG-Determinismus-Invariante muss erhalten bleiben
- Dateien: `HarmonyScene.swift`, `WorldGeneration.swift`

### 1d — HarmonyScene intern aufteilen

> Nach Extraktion der Businesslogik (1a–1c) enthält HarmonyScene noch mehrere Verantwortlichkeiten.
> Diese werden in separate Dateien extrahiert — HarmonyScene bleibt als reiner SceneKit-Renderer.

- `ChunkManager.swift` — Chunk-Load/Unload, SCNNode-Verwaltung, Seeding
- `TriggerCoordinator.swift` — Proximity-State-Maschinen, Trigger-Callbacks
- `HarmonyScene.swift` — nur noch: SCNScene-Setup, Node-Rendering, Pending-Flag-Handling
- Pending-Flag-Pattern (`pendingReload`, `pendingNetwork`, `pendingEdgeRebuild`) wird beibehalten
- Die 20+ `AppSettings.shared`-Direktzugriffe in HarmonyScene werden durch Parameter/Callbacks ersetzt
- Dateien: `HarmonyScene.swift` → `HarmonyScene.swift` + `ChunkManager.swift` + `TriggerCoordinator.swift`

### 1e — ContentView aufteilen

> ContentView (1.256 Zeilen) enthält Settings-Panel, HUD, Cockpit-Display und Overlay-Steuerung.
> Reine SwiftUI-Arbeit, kein Refactor-Risiko. Muss vor Phase 4.5/4.6 abgeschlossen sein.

- `SettingsPanel.swift` — Settings-Drawer, alle `@AppSettings`-gebundenen Controls
- `CockpitHUD.swift` — Live-HUD (Akkordanzeige, Velocity, Telemetrie)
- `OverlayController.swift` — ControlsOverlay, TargetingSystem, HarmonicRadarView
- `ContentView.swift` bleibt als schlanke Root-Kompositions-View — nur Koordination, keine Logik
- Keine Funktionsänderung — reine Extraktion
- Datei: `ContentView.swift` → 4 Dateien

**Ergebnis Phase 1:**
- HarmonyCore ist vollständig testbar (kein SceneKit, kein UIKit, kein MIDI)
- HarmonyScene enthält nach 1d ausschließlich SceneKit-Rendering und Pending-Flag-Handling
- ContentView ist nach 1e in saubere Sub-Views aufgeteilt (SettingsPanel, CockpitHUD, OverlayController)
- `AppSettings.shared` wird nicht mehr direkt aus HarmonyCore oder HarmonyScene gelesen
- Codebase ist bereit für Unit-Tests (Phase 1.5) und Netzwerkmodell-Implementierung (Phase 2)

---

## Phase 1.5 — Stabilisierung und Testabdeckung

**Priorität: HOCH | Risiko: niedrig | Voraussetzung: Phase 1**

> Phase 1.5 macht den erreichten Architekturstand messbar und belastbar.
> Kein neues Feature, kein weiterer Umbau. Nur: testen was da ist, und stabilisieren was noch wackelt.
> Muss abgeschlossen sein, bevor Phase 2 (Netzwerkmodell) beginnt.

### 1.5a — Unit Tests für HarmonyCore

- HarmonyCore ist nach Phase 1 vollständig SceneKit-frei und damit direkt unit-testbar
- Mindest-Abdeckung für kritische Module:
  - `AutopilotEngine` — Traversierungslogik, Gewichtungen
  - `HarmonyGraphEngine` — `neighbors()`, `transitions()`, `weightedChoice()`
  - `RuntimeHarmonik` — Kandidatenselektion, HarmonicDecision-Typen
  - `ProximityTracker` — Distanzberechnung, Opacity-Filter (nach 0.9)
  - `TriggerEngine` — Zustandsautomat (enter / stay / leave)
  - `MelodyEngine` — Preset-Ausgabe, Skalenbindung
- Framework: Swift Testing (nativ) oder XCTest
- Kein 100%-Coverage-Zwang — Ziel: Regressionsschutz für kritische Kernpfade
- Neues Target: `HarmonyCoreTests` in `Package.swift`

**Ergänzung Rev. 6 — Pflichttests für die Fixes aus Stufe 3.9:**

Der Testplan aus `ROADMAP_3.9.8_NEXT_ROUNDS.md` ist hier aufgegangen — er hätte ein zweites
Test-Target angelegt. Stattdessen wird 1.5a erweitert:

| Test | Sichert ab | Phase |
|---|---|---|
| MIDI sent-note snapshot: On/Off-Symmetrie bei Octave-Shift | 3.9.1a | Invariante On/Off-Symmetrie |
| Runtime tie-break: Distanz, dann ID | 3.9.1b | Invariante Determinismus |
| `HarmonyGraphEngine`: directed / undirected, Layer-Filter, History | 3.9.3c | – |
| Validator: harte Fehler und Warnings | 3.9.3d | – |
| JSON-zu-Legacy: symmetrischer undirected Export bzw. dokumentierter Verlust | 3.9.3c | – |

> **Vorziehen:** 1.5a ist in Rev. 5 hinter Phase 1 eingeplant. Die Tests zu 3.9.1a und 3.9.1b
> werden **mit ihrem jeweiligen Fix** angelegt, nicht danach — sonst sichert nichts die beiden
> Invarianten, die nachweislich schon einmal unbemerkt gebrochen sind. Das Test-Target darf
> dafür vorgezogen werden, sofern es ohne Reibung anlegbar ist.

### 1.5b — FlightController von SCNNode entkoppeln

- `cameraNode: SCNNode` als Property in `FlightController` erzeugt SceneKit-Abhängigkeit im Input Layer
- Fix: Position und Rotation werden als `SIMD3<Float>` bzw. `simd_float4x4` übergeben — kein SCNNode-Besitz im Input Layer
- FlightController verbleibt im Input Layer — keine Schichtverschiebung
- Pending-Flag-Pattern und Position-Updates müssen sauber als Callbacks übergeben werden
- Dateien: `FlightController.swift`, `FlightPhysics.swift`, Callback-Schnittstelle in `HarmonyScene.swift`

---

---

# STUFE K — Konzeptarbeit Harmonisches Netzmodell

> **Parallel zu Stufe 1 durchführbar.**
> Kein Code. Ergebnis: Planungsdokumente, die Stufe 2 und 3 ermöglichen.
> Basis: `HarmonyNetwork_Design.md` (lebt weiter als Fachquelle).

---

## K1 — Beziehungssprache festlegen

**Status: erledigt — v1-Entscheidung getroffen (HarmonyNetwork_Spec_v1.md)**

6 Kerntypen für v1, IDs stabil:
`V-I`, `ii-V`, `relMajMin`, `parallelMajMin`, `commonTone`, `tritSubst`

Abstoßung: nicht in v1. `bridge`-Kanten: werden geparst, aber in v1 ignoriert.
Mehrfachbedeutung: ja, `relationTypes: [RelationType]` (Array pro Kante).

---

## K2 — Abstraktes Datenmodell

**Status: erledigt — v1-Entscheidung getroffen (HarmonyNetwork_Spec_v1.md)**

Finale Typen für v1 definiert: `HarmonyNode`, `HarmonyEdge`, `MagnetProfile`, `HarmonyLayer`, `HarmonyMap`.
ID: freies String-Format (z. B. `"Cmaj7"`). `layout3D`: optional, nil = Tonnetz-berechnet.
`HarmonicFunction`: tonic / subdominant / dominant / ambiguous. Tags: frei in v1.

---

## K3 — Magnetphysik-Dokument

**Status: bewusst auf v2 verschoben**

> Die Magnetphysik (räumliche Anziehungskraft, Kraftfelder, Pilot-Override) ist nicht Teil der
> v1-Implementierung. `MagnetProfile` wird in v1 bereits im Datenmodell mitgeführt (3 Presets:
> strong / medium / weak) — aber die Laufzeit-Physik (FlightController-Integration) kommt erst in v2.

Ausstehende Entscheidungen bleiben dokumentiert für v2:
- Krafttypen (linear / inverseSq / sogZone / none)
- Abstoßung (opt-in via `magnetProfile`)
- Gravitationszentren: explizit oder aus Kanten abgeleitet
- Progressions-Gedächtnis: N Akkorde rückwärts (Empfehlung: 4)

---

## K4 — Formatentscheidung

**Status: erledigt — JSON mit `schemaVersion: "1.0"` festgelegt**

Format: JSON. Schema-Version: `"1.0"` (String, kein Semver).
Semantische Daten und Layout-Daten: gemeinsam im Node (`layout3D` optional).
Ablageort: `Sources/HarmonyShared/Resources/maps/*.json`.

---

## K5 — JSON-Schema + Beispieldatei

**Status: in Arbeit — nächster Implementierungsschritt**

Schema vollständig definiert in `HarmonyNetwork_Spec_v1.md`.
Referenzmap: 7 Knoten (C-Dur-Diatonik + Db7 als Tritonussubstitut), 11 Kanten, 2 Layer.
Stand: funktionale Kreise vollständig (Cmaj7 → Fmaj7 → G7 → Cmaj7, Am7 → Dm7 → G7 → Cmaj7).
Datei: `Sources/HarmonyShared/Resources/maps/reference-core.json`

---

---

# STUFE 2 — Netzwerkmodell implementieren

> **Zielzustand:** Stufe 1 (Phase 0 + 1) und Stufe K (K1–K5) vollständig abgeschlossen.
>
> **v1-Abweichung (dokumentiert und freigegeben):** Die v1-Implementierung startet mit einem
> bewusst engen Scope in `HarmonyShared` — ohne vollständigen HarmonyCore-Umbau, ohne
> Magnetphysik (K3 → v2). Ziel ist Validierung des Modells in der Praxis.
> Das ist kein Regelbruch, sondern eine dokumentierte pragmatische Entscheidung für v1.

---

## Phase 2 — Explizites Harmonie-Netzwerkmodell

**Risiko: mittel | Nutzen: sehr hoch**

> Harmonie wird Datenstruktur, nicht mehr Nebenprodukt der Weltgenerierung.

### 2.1 Kerntypen in HarmonyShared (v1) / HarmonyCore (v2+)

**v1:** Neue Typen leben in `HarmonyShared` — pragmatisch, kein neues Modul nötig.
**v2+:** Wenn HarmonyCore als eigenes Modul existiert, werden die Typen dorthin migriert.

```
HarmonyNode      id, root, type, function, tags, midiNotes, layout3D?
HarmonyEdge      id, source, target, relationTypes, weight, directed, layers, magnetProfile?
MagnetProfile    preset: strong | medium | weak  (v1: Presets, keine Overrides)
HarmonyLayer     id, name, relationTypes
HarmonyMap       schemaVersion, id, name, layers, nodes, edges, layout?
HarmonicFunction tonic | subdominant | dominant | ambiguous
RelationType     V-I | ii-V | relMajMin | parallelMajMin | commonTone | tritSubst
```

Vollständige Swift-Definitionen: `HarmonyNetwork_Spec_v1.md`, Abschnitt 2.

### 2.2 GraphEngine

**v1:** Konkrete Klasse `HarmonyGraphEngine` — eine Implementierung, kein Protokoll.
Begründung: Verhalten testen, nicht Abstraktion um der Abstraktion willen.

**v2+:** `protocol HarmonyGraph` als Abstraktion wenn mehrere Implementierungen entstehen.

```
HarmonyGraphEngine (class)
    neighbors(of:)        -> [HarmonyNode]
    transitions(from:)    -> [HarmonyEdge]
    weightedChoice(from:) -> HarmonyNode?   // deterministisch via SeededRNG
    setLayer(_:)
    recordVisit(_:)
```

`weightedChoice`: deterministisch (SeededRNG, optionaler Seed). Kontext-Modulation:
ii-V-Boost (×1.5), Rückkehr-Dämpfung (×0.4), Spannungserhalt (×1.3 für schwache Kanten).

### 2.3 Trennung: Möglichkeiten vs. Entscheidung

- `HarmonyGraphEngine` definiert Möglichkeiten (valide Übergänge + Gewichte)
- Autopilot / Navigation wählt daraus — eigene Schicht, kein Mischen

---

---

# STUFE 3 — Network Construction Kit

> **Voraussetzung: Stufe 2**
> Der Gamechanger: Harmonieräume werden gezielt gebaut, nicht zufällig generiert.

---

## Phase 3.1 — Editor-Umbau (DesignerKit)

**DesignerKit wird zur führenden Authoring-Oberfläche.**

- `DesignerViewModel` verwaltet `HarmonyMapDocument`
- `DesignerCanvasView` zeigt Nodes und Edges aus JSON
- Laden und Speichern als JSON (K5-Schema)
- Noch keine Automatismen, nur korrektes strukturelles Authoring

### 3.2 — Validierungsschicht

- IDs eindeutig?
- Kanten zeigen nur auf existierende Nodes?
- RelationType-Werte gültig?
- MagnetProfile vollständig?

Ohne diese Schicht entstehen stille Fehler, die im Flug schwer zu diagnostizieren sind.

### 3.3 — Runtime-Importer

- Engine liest JSON-Map, baut `HarmonyGraph` zur Laufzeit
- Parallelbetrieb mit bestehendem `ChordGenerator` während Übergangsphase
- Erst wenn Importer stabil: ChordGenerator deaktivieren

### 3.4 — Erste Referenzmap

- Klein, musikalisch klar: Dur/Moll-Grundakkorde + Dominanten
- 3 Beziehungstypen: `V-I`, `ii-V`, `relMajMin`
- Prüft: trägt das Schema? Ist das JSON handhabbar? Ist der Editor benutzbar?

### 3.5 — Regelbasierte Konstruktion *(Network Builder)*

```
protocol HarmonyNetworkBuilder {
    func buildNetwork(config: HarmonyConfig) -> HarmonyGraph
}
```

Beispiel-Regeln:
- Funktionale Harmonie (T–S–D)
- Voice-Leading-Distanz als Kantengewicht
- Modale Wechsel
- Pivot-Chords

Mehrere Builder kombinierbar. Kuratierte Netze (Codex, Status Quo) bleiben als spezialisierte Builder.

---

---

# STUFE 3.9 — Reparatur und Fundament

> **Hier steht das Projekt (Stand 2026-07-14).**
> Quelle: `SYNTHESE_3.9.8.md` — Zusammenführung aus `REVIEW_3.9.8.md` (Claude) und
> `CODEX_REVIEW_3.9.8.md` (Codex). Die dort belegten Befunde sind hier in Phasen überführt.
> Diese Stufe war in Rev. 5 nicht vorgesehen. Sie ist nötig, weil Teile von Stufe 2–4 gebaut
> wurden, bevor Stufe 1 und 1.5 abgeschlossen waren.

**Leitentscheidung:**

> Stabile semantische Anker plus reaktive lokale Visualisierung.

**Nicht-Ziele dieser Stufe:**

- Kein großer Concurrency-Umbau als Startpunkt → Phase 5.8
- Keine Materialisierung bei `.noCandidate` — gestrichen, siehe `SYNTHESE_3.9.8.md` §5.3
- Keine Grafik-Offensive ohne Art-Direction-Entscheidung → Phase 4.7
- Keine neue Theoriephase vor den hörbaren Fixes

---

## Phase 3.9.1 — Hörbare Fehler und Determinismus

**Priorität: HOCH | Risiko: niedrig | Voraussetzung: –**

> Das Instrument darf keine hängenden Noten erzeugen, keine zufälligen Kandidaten wählen
> und nicht frame-rate-abhängig steuern. Alle vier Punkte sind am Code verifiziert.

### 3.9.1a — MIDI On/Off-Symmetrie reparieren

Stellt die in Rev. 5 fälschlich als erledigt geführte Invariante tatsächlich her.

- Pro klingendem Objekt die **tatsächlich gesendeten** MIDI-Noten speichern
- `noteOff` ausschließlich aus diesem Snapshot senden — nie aus der aktuellen Oktavlage rekonstruieren
- `allNotesOff` bleibt Panic-/Reset-Pfad, kein Ersatz für fehlende Off-Events

> **Schichtenkorrektur gegenüber `SYNTHESE_3.9.8.md`:** Die Synthese nennt als Zieldatei u. a.
> `OutputCoordinator.swift`. Das widerspricht den Schichtenregeln dieses Dokuments
> („Kein Note-Tracking im OutputCoordinator", „Kein Erraten fehlender Off-Ereignisse").
> Verbindlich ist die Schichtenregel: Der Note-Snapshot gehört in die **Eventquelle**,
> die laut Zuständigkeitstabelle die On/Off-Symmetrie zu liefern hat.
> Der `OutputCoordinator` bleibt ein 1:1-Übersetzer ohne Gedächtnis.

- Dateien: Eventquelle (Trigger-/Chord-Pfad in `HarmonyScene.swift`), ggf. neuer Hilfstyp
- **Nicht** `OutputCoordinator.swift` erweitern

**Akzeptanz:**
- Octave-Shift über gehaltenen Noten erzeugt keine hängenden Noten
- Bass, Chord, Melody und CH3 senden Off für exakt die Notes, die vorher On bekommen haben
- Gilt auch bei Layer-/Chord-Wechsel und Panic

### 3.9.1b — Deterministische Kandidatenauswahl

- Kandidatenliste vor der Auswahl stabil nach `(distance, id)` sortieren
- Falschen Kommentar zur Dictionary-Stabilität entfernen — `RuntimeHarmonik.swift:111`
- Dateien: `RuntimeHarmonik.swift`

**Akzeptanz:**
- Gleicher Seed und gleiche Position erzeugen über Prozessstarts hinweg denselben Kandidaten
- Gleich weit entfernte Nodes werden reproduzierbar über die ID aufgelöst

### 3.9.1c — Harmonischen Magnet zeitbasiert machen

Der Proximity-Magnet (`FlightController.swift:316`) rechnet bereits korrekt mit `dt`.
Nur der harmonische Magnet (`:291–297`) tut es nicht.

- Feste 85/15-Frame-Mischung ersetzen durch `alpha = 1 - exp(-rate * dt)`
- Maximale Winkelgeschwindigkeit begrenzen
- NaN- und Zero-Length-Guards als Stabilitätsfix, nicht als Kosmetik
- Dateien: `FlightController.swift`, `AppSettings.swift` nur falls Parameter persistiert werden

**Akzeptanz:**
- Magnetwirkung fühlt sich bei 60 Hz und 120 Hz gleich an
- Freier Flug gegen den Magneten bleibt möglich — Pilot-Override-Prinzip aus 4.2 gilt

### 3.9.1d — Trigger-Hysterese und Spawn-Sicherheit

- Entry- und Exit-Radius als getrennte Werte; Entry < halbe minimale Nachbardistanz
- Aktiver Trigger bleibt gelockt, bis Exit überschritten ist
- Spawn außerhalb aktiver Trigger oder `unarmed` bis zur ersten Bewegung
- Dateien: `ProximityTracker.swift`, `HarmonyScene.swift`

**Akzeptanz:**
- Kein Flattern zwischen zwei gleich nahen Nodes
- App-Start löst nicht automatisch aus

> **Prüfpunkt-Status (aktualisiert nach manuellem App-Start-Test in Runde 005):**
> Der Sofort-Trigger bei t=0 ist bestätigt ausgeschlossen — `triggersArmed`/`armReferencePos`
> verhindert bei stillstehender Kamera zuverlässig jeden Trigger-Übergang.
> **Neuer Befund:** In der JSON-Web-Preview (Kamera 0/30/240, nächster Node ~67 Einheiten
> entfernt, innerhalb `magnetRadius` = 155) zieht der bestehende Harmonic-Magnet
> (`FlightController.applyMagneticForce`, unabhängig von Spieler-/Autopilot-Eingabe) die
> Kamera bereits ab Frame 1 aktiv an. Diese Bewegung ist "echt" im Sinne der 3.9.1d-Logik und
> überschreitet `triggerArmDistance` (5 Einheiten) dadurch bereits nach ca. 1 Sekunde — ein
> Akkord löst dann doch automatisch aus, nur zeitlich verzögert statt sofort. Reproduziert mit
> `HE3D_MAP_PREVIEW=1`, Autopilot sowohl an als auch aus. Kein Fehler in der 3.9.1d-Logik
> selbst (sie gated korrekt auf echte Positionsänderung) — aber die Akzeptanz „App-Start löst
> nicht automatisch aus" ist im Zusammenspiel mit dem passiven Magnet-Pull nur für die ersten
> ~1s erfüllt, nicht dauerhaft. Nicht in Runde 005 behoben (außerhalb des Auftrags), zur
> Entscheidung an Stephan/Codex zurückgegeben. Siehe `SYNTHESE_3.9.8.md` §7.2.
>
> **Behoben in Runde 007 (Codex-Handoff HE3D-CX-2026-07-14-007):** Der proximity-basierte
> Magnet (`FlightController.applyMagneticForce`, Velocity-Nudge-Mechanismus) wirkt jetzt nur
> noch, wenn im aktuellen Frame echter Pilot-Translationsinput vorliegt (WASD/QE bzw.
> Gamepad-Schub — reine Blick-/Stick-Rotation und Bremsen zählen bewusst nicht). Ohne Input
> bleibt die Kamera bewegungslos, `triggersArmed` wird nicht scharf, kein Trigger löst aus.
> Der separate harmonische Richtungskorrektur-Mechanismus (`harmonicMagnetTarget`, nur bei
> `speed > 0.5` aktiv) ist unverändert. Autopilot-Pfad unverändert (early guard bleibt).
> Akzeptanz „App-Start löst nicht automatisch aus" damit erfüllt.

---

## Phase 3.9.2 — Modus-Wahrheit wiederherstellen

**Priorität: HOCH | Risiko: niedrig | Voraussetzung: –**

> Die App startet wieder als spielbares Instrument, nicht als versehentliches JSON-Testlayout.
> Beide Reviews kommen hier unabhängig zum selben Urteil.

- Startmodus bewusst festlegen: Explore als Default **oder** sichtbarer Umschalter
- JSON-Map-Ansicht als eigener Modus kennzeichnen, falls sie sichtbar bleibt
- HUD an die tatsächlich aktive Welt koppeln — keine Legacy-Netzwerkdaten bei aktiver JSON-Map
- Debug-/Preview-Funktionalität sichtbar vom Spielmodus trennen
- Dateien: `HarmonyEngine3DApp.swift`, `ContentView.swift`, `HarmonyScene.swift`, ggf. `AppSettings.swift`

**Akzeptanz:**
- Beim Start ist erkennbar, ob Explore-, Map- oder Testmodus aktiv ist
- UI und interne Szene widersprechen sich nicht
- Entwickler können JSON-Maps weiterhin prüfen; Musiker landen nicht ungefragt in der Testansicht

> **Umsetzung (3.9.9):** Default ist Explore (`NetworkParser.load(index: AppSettings.shared.harmony.networkIndex)`,
> kein `HarmonyMap` geladen). JSON-Map-Preview nur explizit per `--map-preview` /
> `HE3D_MAP_PREVIEW=1` (+ optional `HE3D_MAP_NAME`). HUD zeigt `RuntimeWorldInfo`
> statt hart verdrahtetem `NetworkParser`-Eintrag; D-Pad-Netzwerkwechsel ist im
> Preview-Modus ein No-Op mit Logmeldung. Kein Live-Umschalter — bewusst nicht
> Teil dieser Runde (siehe Auftrag).
>
> **Build-Reparatur (Runde 006):** Der 3.9.2-Commit war nicht clean-build-fähig —
> `ContentView.swift`/`HarmonyEngine3DApp.swift` hatten beim `git add` versehentlich
> nie gestagete Radar-/Debug-Nebenarbeit (`HarmonicDebugModel`/`HarmonicRadarView`)
> mitgenommen. Aus beiden Dateien wieder entfernt — das eigentliche 3.9.2-Verhalten
> (Explore-Default, Preview-Flag, HUD-Kopplung, D-Pad-No-Op) ist davon nicht berührt.

---

## Phase 3.9.3 — Semantisches Fundament

**Priorität: HOCH | Risiko: mittel | Voraussetzung: 3.9.1, 3.9.2**

> Graph, Raum und musikalische Semantik beschreiben dieselbe Welt.

### 3.9.3a — Anker/Render-Trennung einführen

Die zentrale Designentscheidung der Synthese. Löst gleichzeitig drei Risiken des
Kammer-Konzepts (Trigger durch Eigenbewegung, Orientierungsverlust, fehleranfällige Fades).

- Pro Node eine **immutable Ankerposition** — Quelle: `layout3D` bzw. Phase 4.1
- Trigger, Distanz und Kandidatenwahl ausschließlich auf Ankerpositionen
- Render-Position = Anker + animierter Offset
- Active-State, Notes und Fades an Node-ID/Anker koppeln
- Dateien: `HarmonyScene.swift`, `RuntimeHarmonik.swift`, ggf. neue Typen für Anchor/RenderState

**Akzeptanz:**
- Render-Bewegung kann keine musikalischen Trigger auslösen
- Die mentale Landkarte des Spielers bleibt stabil

> **Umsetzung Runde 008 (Codex-Handoff HE3D-CX-2026-07-14-008):** `HarmonyScene` führt
> `chordAnchorPositions: [String: simd_float3]` als SceneKit-freie Anker-Registry ein
> (Key = dieselbe Node-ID wie `chordNodes`/`chordDataMap`). Gesetzt beim Platzieren an
> allen vier Erzeugungspfaden (`buildNodes(from:)` für den Chunk-Betrieb, `buildJsonWebLayout`,
> `buildCuratedLayout`, `buildHarmonyCodexLayout`), gelöscht in `unloadChunk(_:)`. Alle
> musikalischen Positionsleser umgestellt: `magnetTargetPosition`, `localChordNodes`,
> `applyHarmonicDecision` (Distanzlog), `updateChordProximity` (Kandidaten), `updateChordVisibility`
> (Waisen-Distanz), `buildChordPositionMap` (Autopilot). Render-Position (`SCNNode.position`/
> `simdWorldPosition`) bleibt für Sichtbarkeit (`opacity`) und Rendering bestehen, ist aber keine
> Quelle mehr für Trigger/Kandidatenwahl/Magnetziel/Autopilot. `renderPosition == anchorPosition`
> für diese Runde — animierter Offset ist nicht Teil des Scopes. Bass-Portale
> (`bassPortalPositions`) und Edge-Line-Rendering unverändert. `RuntimeHarmonik` bleibt
> SceneKit-frei. Kein Morphing, kein Radar, keine 3.9.3b/3.9.3c-Arbeit in dieser Runde.
>
> **Abschluss Runde 009 (Codex-Handoff HE3D-CX-2026-07-14-009):** Schichtentrennung
> vervollständigt — `SCNNode.position` wird jetzt explizit aus `chordAnchorPositions +
> chordRenderOffsets` abgeleitet, statt beim Erzeugen direkt auf die Ankerposition gesetzt
> zu werden. Neue Registry `chordRenderOffsets: [String: simd_float3]` (Default `.zero`,
> aktuell nirgends auf einen Nicht-Null-Wert gesetzt) plus drei kleine Helfer
> (`chordRenderPosition(for:)`, `applyChordRenderPosition(key:)`, `setChordRenderOffset(_:for:)`
> — Letzterer aktuell ungenutzt, Infrastruktur für künftiges Morphing ab Phase 3.9.4). Alle vier
> Erzeugungspfade rufen nach dem Registrieren von Anchor + Offset `applyChordRenderPosition(key:)`
> auf; `unloadChunk(_:)` räumt `chordRenderOffsets` zusammen mit `chordAnchorPositions` auf.
> Zusätzliche Härtung aus dem 008-Review: `applyHarmonicDecision` hat den defensiven Fallback
> `chordAnchorPositions[nodeID] ?? node.simdWorldPosition` entfernt — fehlt der Anker, wird
> Magnetismus jetzt sauber gecleart und geloggt, ohne je auf Render-Position zurückzugreifen.
> `renderPosition == anchorPosition` bleibt sichtbar unverändert (Offset überall `.zero`),
> manuell verifiziert per JSON-Web-Preview (identische Trigger-Sequenz/Distanzen wie vor 009).
> Kein Morphing, kein Radar, keine 3.9.3b/3.9.3c-Arbeit. **3.9.3a ist damit vollständig
> abgeschlossen.**

### 3.9.3b — Layer-Mitgliedschaft explizit modellieren

- Nodes wissen, in welchen Layern sie sinnvoll aktiv sind
- Isolierte Nodes werden **nicht** durch Scheinverbindungen repariert — ausblenden,
  deaktivieren oder als bewusst isoliert validieren
- Dateien: `HarmonyShared`-Typen, `HarmonyMapLoader.swift`, Map-JSONs

**Akzeptanz:**
- `Bbmaj7` / `Ebmaj7` werden in der functional layer nicht blind verbunden
- Layer-Wechsel verändert sichtbar und logisch dieselbe Welt

> **Umsetzung Runde 010 (Codex-Handoff HE3D-CX-2026-07-14-010):** `HarmonyNode` bekommt
> ein optionales `layers: [String]?` (fehlt in bestehenden Maps → weiterhin dekodierbar).
> Neue `HarmonyMap`-Extension `activeNodeIDs(in:)` / `isNode(_:activeIn:)`: ist `node.layers`
> gesetzt, gilt das als explizite Mitgliedschaft; fehlt es, wird die Mitgliedschaft aus
> `HarmonyEdge.layers` abgeleitet (Node als source **oder** target, unabhängig von `directed`).
> `HarmonyScene.buildJsonWebLayout` baut jetzt nur noch die im aktiven Layer aktiven Nodes
> (`jsonWebLayer`, default `"functional"`, aus `HarmonyEngine3DApp` durchgereicht). Verifiziert:
> `harmony-web-c-diatonic` liefert 12 von 14 Nodes im functional-Preview — `Bbmaj7`/`Ebmaj7`
> (nur modal angebunden) werden korrekt übersprungen und geloggt (`[JsonWebLayout] ... 2 Node(s)
> außerhalb des Layers übersprungen`). **3.9.3b ist damit abgeschlossen.**

### 3.9.3c — Verlustfreien Map-Pfad vorbereiten

`HarmonyMapLoader.toChordNetwork()` (`:55–61`) verwirft `directed`, `layers`, `relationType`
und `magnet`. GraphEngine und Legacy-Autopilot sehen dadurch verschiedene Welten.

- Kurzfristig: undirected Edges im Legacy-Export symmetrisch behandeln, Semantikverlust warnen
- Langfristig: Autopilot und Navigation direkt auf `HarmonyMap` / `HarmonyGraphEngine`
- Dateien: `HarmonyMapLoader.swift`, `AutopilotEngine.swift`

**Akzeptanz:**
- Directed, undirected, layer, relationType und magnet gehen nicht still verloren
- GraphEngine und Raum widersprechen sich nicht

> **Umsetzung Runde 010:** `toChordNetwork(_:layer:)` exportiert bei gesetztem Layer nur noch
> Nodes/Kanten, die tatsächlich im Layer aktiv sind (`activeNodeIDs(in:)`), statt "alle Nodes +
> gefilterte Kanten". Ungerichtete Kanten werden symmetrisch als zwei `EdgeData`-Einträge
> exportiert (Legacy-`EdgeData` kennt kein `directed`; ohne Duplikat wäre eine ungerichtete
> Kante nur in einer Richtung navigierbar — Autopilot traversiert ausschließlich source→target).
> Neue `warnAboutSemanticLoss(...)`: warnt einmalig, aggregiert (nicht pro Kante), wenn
> `relationTypes`, Mehrfach-Layer-Zugehörigkeit oder `magnetProfile` beim Export verloren gehen.
> Verifiziert per Map-Preview-Log: `toChordNetwork('harmony-web-c-diatonic', Layer 'functional')
> verliert beim Export: relationTypes, layers (Mehrfachzugehörigkeit), magnetProfile
> (24 betroffene Kante(n))`. Direktpfad auf `HarmonyMap`/`HarmonyGraphEngine` (langfristig,
> ohne Legacy-Zwischenschicht) bleibt vorbereitet, aber nicht erzwungen — `AutopilotEngine.swift`
> unverändert. **3.9.3c ist damit abgeschlossen.**

### 3.9.3d — Validator erweitern

Ergänzt Phase 3.2 um die im Review fehlenden Invarianten:

- MIDI-Wertebereich; nicht-leere Note-Listen; finite positive Gewichte
- doppelte Layer- und Relation-Namen; existierender initial layer; leere Layer
- gerichtete Erreichbarkeit; isolierte Nodes pro Layer
- Layout-Strategie und Koordinatenkonsistenz

**Akzeptanz:**
- Fehlerhafte Maps scheitern früh mit klarer Diagnose
- Warnings unterscheiden bewusstes Design von stillen Datenfehlern

> **Umsetzung Runde 010:** `HarmonyMapLoader.validate` deutlich gehärtet — neue harte Prüfungen:
> doppelte Layer-IDs, `midiNotes` nicht leer, MIDI-Werte `0...127`, explizite `node.layers`-
> Referenzen existieren, `layout3D`-Koordinaten finite (falls vorhanden), Edge-`relationTypes`
> nicht leer, `weight.isFinite && weight > 0`, Layer-`relationTypes` nicht leer, sowie global
> isolierte Nodes (keine einzige Kante im gesamten Graph — offensichtlich inkonsistent).
> Zwei neue Warning-Klassen (ℹ️, kein Fehler): leere Layer (keine aktiven Nodes, keine Kanten)
> und Nodes, die explizit in einem Layer aktiv markiert sind, dort aber keine Kante haben
> (bewusster Sonderfall, keine defekte Map). Alle drei ausgelieferten Maps (`harmony-web-c-
> diatonic`, `harmony-web-c-center`, `reference-core`) laden weiterhin unverändert erfolgreich —
> keine der neuen harten Prüfungen bricht bestehende Daten. **3.9.3d ist damit abgeschlossen.**

---

## Phase 3.9.4 — Reaktive Nachbarschaft *(erster spielbarer Raum-Prototyp)*

**Priorität: MITTEL | Risiko: mittel | Voraussetzung: 3.9.3a**

> Aus der stabilen Semantik wird wieder ein lebendiger Raum.
> Konkretisiert Phase 4.3 — ersetzt sie nicht.

### 3.9.4a — Impuls und Nachbarschafts-Antwort

- Aktiver Akkord als Impulsquelle; verändert nur Render-Offsets, Farben, Licht, Kantenintensität
- Sichtbare Nachbarn gewichtet nach Relation, Layer und Distanz
- **Obergrenze für gleichzeitig aktive Nachbarn** — kontrolliert hohen Knotengrad
- Dateien: `HarmonyScene.swift`, `RuntimeHarmonik.swift`, ggf. Material-/Edge-Hilfstypen

> **Umsetzung Runde 010 — erste Fassung:** Bei jeder Akkord-Aktivierung (`chordTriggerEngine`-
> Transition) ruft `updateChordProximity` neu `triggerHarmonicImpulse(from:)` auf. Nur im
> JSON-Web-Modus aktiv (echtes Graph-/Layer-Wissen aus `jsonWebMap`) — ohne Map-Info stabiler
> No-op, wie gefordert. Gewichtung der Nachbarn aus Graph (Kante vorhanden im aktiven Layer,
> `directed`/`undirected` wie in `HarmonyGraphEngine.activeEdges` behandelt) × `edge.weight`
> (Relation) × Distanzdämpfung (`weight / (1 + dist/100)`); deterministische Sortierung bei
> Gleichstand (Score absteigend, dann Node-Key aufsteigend). Harte Obergrenze
> `impulseMaxNeighbors = 4`. Reaktion ist ausschließlich `chordRenderOffsets` (linear
> zerfallende Amplitude, `impulseDecayDuration = 0.9s`, `impulseMaxOffset = 6` Einheiten,
> angewendet via `applyChordRenderPosition`/`setChordRenderOffset` aus 3.9.3a/Runde 009) —
> keine Materialfarbe/Licht/Kantenintensität in dieser ersten Fassung, um nicht mit den
> bestehenden Emission-Systemen (Highlight, Approach-Glow) zu kollidieren. `updateProximity`
> bekommt dafür ein `deltaTime`-Argument (aus `SceneKitView.Coordinator`s bereits vorhandenem
> `dt`), rein für den Zerfall — keine musikalische Logik liest `deltaTime`. Verifiziert per
> temporärem Debug-Log (vor dem Commit entfernt): Aktivierung von `A7` löst `Dm7` (Score 0.23,
> passend zur V-I-Kante) aus, Aktivierung von `Cmaj7` löst `Em7`/`Fmaj7`/`Am7`/`G7` aus (4 von
> 4 möglichen Kanten, an der Obergrenze gekappt). Trigger-Sequenz/Distanzen im Live-Test
> unverändert gegenüber Runde 009 — Impulse beeinflussen nachweislich nie Trigger/Kandidatenwahl.

> **Runde 011 — abgerundet (Kandidatenbetonung):** `HarmonyScene` bekommt einen eigenen,
> render-only Zustand `chordCandidateGlow: [String: CandidateGlow]` (Amplitude 0…1, zerfällt
> linear über `impulseDecayDuration` — derselbe Zeitpfad wie die Impulse). `applyHarmonicDecision`
> ruft `applyCandidateGlow(candidates:)`: Kandidaten, die in der neuen Entscheidung nicht mehr
> vorkommen, werden sofort auf den Approach-Glow-Basiswert zurückgesetzt (`resetChordApproachGlow`,
> pragmatisch wiederverwendet als generischer „Emission neutral" -Helfer); der beste Kandidat
> bekommt volle Amplitude 1.0, weitere Kandidaten `0.15 + 0.45 × (score / bestScore)`. Pro Frame
> zerfällt `chordCandidateGlow` in `updateCandidateGlow(deltaTime:)` (Collect-then-Mutate, siehe
> 3.9.4-Hygiene unten) und schreibt `mat.emission.contents` der Akkordkugel — denselben Pfad wie
> `setChordHighlighted`/`setChordApproachGlow`, aber zeitlich nach der Annäherungs-Aktualisierung
> im selben Frame aufgerufen, sodass Kandidaten-Glow sichtbar Vorrang vor dem Approach-Glow hat,
> ohne dessen Zustand dauerhaft zu überschreiben (Reset bei Ablauf/neuer Entscheidung stellt den
> Approach-Glow-Basiswert wieder her). Bewusst **nicht** an `morphingIntensity` gekoppelt — der
> Glow ist keine Positionsverschiebung und soll die Entscheidung auch bei deaktiviertem Morphing
> lesbar halten (im Auftrag als zulässige, zu begründende Abweichung vorgesehen). Kanten-Intensität
> (`showNetworkEdges`) wurde bewusst **nicht** umgesetzt: `rebuildEdgeLines()` baut die Kanten-
> Geometrie nur bei strukturellen Änderungen neu (kein Pro-Frame-Update, keine pro-Kante
> Referenzhaltung) — eine flüssig ein-/ausblendende Kandidatenkante hätte eine zusätzliche
> Kanten-Referenzierung nach Node-Paar erfordert, was über „pragmatisch" hinausgegangen wäre.
> Node-Kandidatenbetonung deckt die Lesbarkeits-Anforderung vollständig ab. 3.9.4a gilt damit
> als abgeschlossen — Materialfarbe/Licht als weitere Ausbaustufen bleiben zurückgestellt.

### 3.9.4b — Gewichtete Kandidatenliste

- `HarmonicDecision` von Einzelvorschlag auf gewichtete Kandidatenliste erweitern
- Vorhandene `transitions(from:)`-Information nutzen
- Dateien: `RuntimeHarmonik.swift`

> **Umsetzung Runde 011:** `HarmonyGraphEngine` bekommt `weightedTransitions(from:)` — dieselbe
> Kontext-Modulation (ii-V-Boost, Rückkehr-Dämpfung, Spannungserhalt) wie `weightedChoice(from:)`,
> aber ohne RNG, als `[WeightedTransition]` (Kante + Zielknoten + `effectiveWeight`).
> `weightedChoice(from:)` selbst wurde auf diese neue API umgestellt (Verhalten bit-identisch,
> keine Duplikat-Logik mehr). `RuntimeHarmonik.process(...)` baut daraus `HarmonicCandidate`
> (`nodeID`, `chordName`, `distance`, `harmonicWeight`, `distanceWeight`, `score`): pro
> Graph-Übergang wird der nächstgelegene lokale Node mit passendem Akkordnamen gesucht,
> `harmonicWeight = effectiveWeight / Summe aller effectiveWeights` (Anteil 0…1),
> `distanceWeight = 1 / (1 + distance)`, `score = harmonicWeight × distanceWeight`. Deterministische
> Sortierung (score absteigend, dann distance aufsteigend, dann nodeID aufsteigend), harte
> Obergrenze `maxCandidates = 4` — bewusst identisch zu `impulseMaxNeighbors` (3.9.4a/Runde 010),
> damit Kandidaten-Glow und Nachbarschafts-Impuls im Raum zusammenpassen. `selectedNodeID`/
> `suggestedChord` sind jetzt der beste Kandidat (`candidates.first`) statt eines separaten
> RNG-Vorschlags aus `weightedChoice(from:)` — das macht die Auswahl vollständig deterministisch
> und konsistent mit der sichtbaren Kandidatenliste. `weightedChoice(from:)` bleibt als API
> unverändert nutzbar (z. B. `HarmonyEngine3DApp`-Testcode), wird aber im RuntimeHarmonik-
> Entscheidungspfad nicht mehr aufgerufen. Verifiziert per Map-Preview-Log: `A7 → [Dm7@0.00276]`,
> `Cmaj7 → [Em7@0.00141, Fmaj7@0.00122, Am7@0.00106, G7@0.00095]` — Reihenfolge plausibel
> (passend zu den 4 Cmaj7-Kanten aus Runde 010) und deterministisch über mehrere Läufe.

### 3.9.4c — Optionales Morphing als reiner Render-Effekt

- `morphingIntensity: Double` im Bereich `0.0 ... 1.0`, Default initial `0.0` oder sehr niedrig
- Render-Offset aus Nachbarschafts-Reaktion × Intensität; harte Obergrenze für Node-Versatz
- Trigger, Distanzen, Kandidatenwahl, Notes und Fades bleiben an den Ankern
- `morphingSpeed` / `morphingDamping` **nicht** in der ersten Umsetzung
- Dateien: `AppSettings.swift`, Settings-/Debug-UI, `HarmonyScene.swift`

**Akzeptanz:**
- Der Raum reagiert musikalisch, ohne Trigger-Logik zu verschieben
- Bei `morphingIntensity = 0.0` ist das Verhalten exakt stabil und klassisch
- Bei höherer Intensität bewegen sich nur Render-Positionen, nie logische Anker

> **Entscheidung am Spielgefühl, nicht vorab:** Ob Morphing über einen dezenten Wert
> hinaus sinnvoll ist, wird nach 3.9.4a/b im Spieltest entschieden.

> **Umsetzung Runde 011:** `RenderConfig.morphingIntensity: Double` (0.0…1.0, Default 0.0),
> persistiert unter `he3d.morphIntensity`, beim Laden auf 0…1 geklammert. Schlanker Slider
> (`settingsSliderF`, 2 Nachkommastellen) im bestehenden Abschnitt „RENDERING" — keine neue
> Panel-Architektur. `updateHarmonicImpulses` multipliziert den Render-Offset jedes Impulses
> mit `Float(AppSettings.shared.render.morphingIntensity)`; der Amplituden-Zerfall selbst läuft
> unabhängig vom Regler weiter, damit ein späteres Hochregeln ohne Neuauslösung sofort wirkt.
> Verifiziert per temporärem Debug-Log (vor Commit entfernt): bei `morphingIntensity = 0.0` ist
> `offsetLen` in jedem Frame exakt `0.0`; bei `0.6` zerfällt `offsetLen` sichtbar von ~0.88 auf
> ~0.05 über die erwartete Impulsdauer. Kein `morphingSpeed`/`morphingDamping`.

---

---

# STUFE 4 — 3D-Raumintegration

> **Voraussetzung: Stufe 3 (Referenzmap und Runtime-Importer stabil) + Stufe 3.9**

---

## Phase 4.1 — Semantische 3D-Koordinaten

Jeder Node bekommt eine Position aus harmonischer Bedeutung (Tonnetz-Einbettung):

| Achse | Bedeutung |
|---|---|
| XZ-Ebene | Quintenzirkel-Position (Ring) |
| Y | Akkordtyp-Ebene (maj7=+2, m7=0, dom7=−1, dim=−2) |
| Radius | Funktionale Spannung (Tonika innen, Dominante außen) |

Strategie: **Hybrid** — Semantische Koordinaten als Startpunkt, optionale Force-Directed-Relaxierung für Überlappungen, manuelle Überschreibung via `layout3D`.

Chunk-Integration:
- Chunks werden nicht mehr zufällig befüllt
- Node-Positionen kommen aus `layout3D` der Map

> **Verhältnis zu Phase 3.9.3a (Rev. 6):** Die hier erzeugten semantischen Koordinaten **sind**
> die Ankerpositionen der Anker/Render-Trennung. Phase 4.1 wird durch das Anker-Konzept nicht
> ersetzt, sondern ist dessen Voraussetzung: Ohne stabiles globales Layout gibt es nichts,
> woran der Spieler sich orientiert. Das reaktive Verhalten aus 3.9.4 lebt ausschließlich
> in den Render-Offsets darüber.

> **Umsetzung Runde 012 — Phase 4.1a (Teilslice, nicht ganz 4.1):** Neue, SceneKit-freie
> `SemanticHarmonyLayout` (HarmonyShared): `position(for: HarmonyNode) -> simd_float3` —
> `node.layout3D` gewinnt immer (Autoren-Kontrolle), sonst deterministischer Fallback aus
> `root`/`function`/`type`, ohne externen Zustand oder RNG. XZ-Winkel aus `(root * 7) % 12`
> (Quintenzirkel-Reihenfolge; `root` ist in den vorhandenen Maps ein volles MIDI-Notennummer,
> die Formel arbeitet aber mod 12, Oktave spielt keine Rolle). Radius aus `function`:
> `tonic 0.55×`, `subdominant 0.85×`, `ambiguous 1.00×`, `dominant 1.15×` von `baseRadius = 150`
> (nah am bisherigen Ring-Radius 180, damit bestehende Trigger-Radien weiter grob passen). Y aus
> `type`: `maj7 +18`, `maj +14`, `m7`/`min 0`, `sus4 −6`, `dom7 −12`, `m7b5 −24`, `dim7 −30`
> (rein visuelle Staffelung, keine musikalische Bedeutung). `HarmonyScene.buildJsonWebLayout`
> nutzt diese Funktion jetzt statt des Index-Rings; Anker/Render-Invariante bleibt erhalten
> (`chordAnchorPositions` aus der Layout-Funktion, `chordRenderOffsets = .zero`,
> `applyChordRenderPosition` bleibt einziger Render-Schreibpfad). Log zeigt jetzt die
> Layout-Quelle (`N mit layout3D`, `N semantischer Fallback`) statt eines Radius-Werts.
> Kamera-Reset nutzt eine einfache Bounding-Box über die Anker statt einer festen Position
> (siehe `HarmonyScene.cameraPosition(forAnchors:)`) — bewusst keine echte Look-at-Berechnung,
> die Kamera behält nach dem Reset weiterhin Identitäts-Orientierung (Blick entlang -Z).
> Verifiziert: alle 12 aktiven Nodes aus `harmony-web-c-diatonic` (functional Layer) liegen an
> unterschiedlichen Positionen (kein Kollisionsfall in dieser Map — Nodes mit gleichem `root`
> unterscheiden sich immer in `function` oder `type` und damit in Radius/Y), Layer-Filter
> unverändert (12/14, `Bbmaj7`/`Ebmaj7` draußen). Keine der drei vorhandenen Maps wurde
> geändert — `reference-core.json` war bereits dirty, `harmony-web-c-center.json` und
> `harmony-web-c-diatonic.json` sind untracked; alle drei bewusst nicht angefasst (siehe
> Auftrag: keine ungefragten Änderungen an User-/Fremd-Dateien im Arbeitsbaum). Der semantische
> Fallback trägt die functional Preview vollständig ohne manuelle `layout3D`-Werte. **Offen für
> 4.1 insgesamt:** Force-Directed-Relaxierung, Chunk-Integration (klassischer Chunk-Betrieb
> nutzt weiterhin `WorldGeneration`, nicht `layout3D`) — 4.1 bleibt daher "teilweise", nicht
> "erledigt".

### Phase 4.2 — Erste Magnetlogik im Flug

Aus K3 (Magnetphysik) abgeleitet, erstmals praktisch umgesetzt:

- Kraftfelder beeinflussen `FlightState`
- Kleiner Typen-Satz zuerst: `V-I` (starke Anziehung), `relMajMin` (symmetrisch), `commonTone3` (sanft)
- Pilot-Override-Prinzip: Magnetismus ist Suggestion, kein Zwang
- Schrittweise weitere Krafttypen aktivieren

> **Umsetzung Runde 013 — Phase 4.2a (Teilslice):** `HarmonicCandidate` (RuntimeHarmonik)
> trägt jetzt zusätzlich `magnetPreset`/`magnetRateMultiplier`/`magnetAngularSpeedMultiplier`,
> abgeleitet aus `WeightedTransition.edge.magnetProfile?.preset`. Preset-Basis:
> `weak` → rate 0.70 / angular 0.75, `medium`/nil → 1.00 / 1.00, `strong` → 1.30 / 1.20.
> Zusätzlicher `scoreBoost` (0.85...1.15) aus `harmonicWeight` (nicht dem rohen `score` —
> dessen `distanceWeight`-Anteil ist bei realistischen Distanzen zu klein, um als
> Multiplikator zu taugen) moduliert beide Basiswerte moderat. Neuer SceneKit-freier
> Werttyp `HarmonicMagnetInfluence` (target/rateMultiplier/maxAngularSpeedMultiplier/
> score/preset) bündelt Position + Einfluss in einem Wert — `HarmonyScene.magnetInfluence`
> (computed, wie `magnetTargetPosition`) kombiniert live `chordAnchorPositions[id]` mit dem
> in `applyHarmonicDecision()` gesetzten `currentMagnetProfile`. `FlightController` ersetzt
> `harmonicMagnetTarget: simd_float3?` durch `harmonicMagnetInfluence: HarmonicMagnetInfluence?`;
> effektive Rate/Winkelgeschwindigkeit = Basis (`harmonicMagnetRateBase` 9.75 / `...MaxAngularSpeedBase`
> 3.0 rad/s, unverändert aus 3.9.1c) × Multiplikatoren, geklammert auf Rate 3...16 und
> Winkelgeschwindigkeit 1...5 rad/s. Ohne `magnetProfile` (medium/nil-Pfad, Multiplikator ≈1.0)
> bleibt das Verhalten nahezu identisch zu vorher. Proximity-Magnet (`magnetTarget`) und
> Autopilot unverändert. **Offen für 4.2 insgesamt:** die übrigen K3-Krafttypen
> (`relMajMin`, `commonTone3` als eigene Feldtypen) und eine UI/Settings-Anbindung der
> Magnet-Parameter sind nicht Teil dieses Slices.
>
> **Umsetzung Runde 014 — Phase 4.2b (Teilslice):** `HarmonicCandidate` trägt jetzt
> zusätzlich `relationTypes: [RelationType]` und `magnetFieldKind: HarmonicMagnetFieldKind`
> (neuer SceneKit-freier Enum: `dominantResolution`/`preDominantMotion`/`substitution`/
> `relative`/`commonTone`/`generic`), deterministisch aus `edge.relationTypes` klassifiziert
> (Priorität: V-I → ii-V → tritSubst → relMajMin → commonTone → generic-Fallback). Hinweis:
> Code/JSON-v1 nutzt `commonTone`, nicht `commonTone3` — Letzteres war nur Konzeptsprache.
> Feld-Basismultiplikatoren (`dominantResolution` 1.15/1.10, `preDominantMotion` 1.08/1.05,
> `substitution` 1.00/1.15, `relative` 0.90/0.85, `commonTone` 0.78/0.75, `generic` 0.85/0.80)
> modulieren die MagnetProfile-Preset-Basis aus Runde 013 zusätzlich (multiplikativ, nicht
> ersetzend) — Preset bleibt primäre Stärke der Kante, RelationType beschreibt den
> Feldcharakter. Effektive Werte weiterhin durch die bestehenden FlightController-Clamps
> (Rate 3...16, Winkelgeschwindigkeit 1...5 rad/s) begrenzt; `FlightController` selbst bleibt
> unverändert und kennt weiterhin keine `HarmonyMap`/`HarmonyGraphEngine`/`RelationType`.
> `HarmonicMagnetInfluence` bleibt die einzige Übergabe an den `FlightController`, jetzt um
> `fieldKind`/`relationTypes` für Debug/HUD erweitert. **Offen für 4.2 insgesamt:** UI/Settings-
> Anbindung der Magnet-Basisparameter und der noch nicht ausgewertete,
> intern aus dem Preset abgeleitete Range-Wert.

### Phase 4.3 — Runtime-Harmonieintegration *(lokal, nicht-generativ)*

**Voraussetzung: 4.1 + 4.2 | Konzeptuelle Grundlage für alle weiteren Ausbaustufen**

> Harmonische Logik wirkt auf bestehende Nodes — nicht durch neue Generierung.
> Ursache und Wirkung müssen lokal und unmittelbar erfahrbar sein.

**Grundprinzip:**
- Harmonische Entscheidungen der `HarmonyGraphEngine` beeinflussen den bestehenden Raum
- Keine zeitlich verzögerte Wirkung durch entfernte oder neue Node-Erzeugung
- Funktional passende Akkorde befinden sich in der Regel bereits im lokalen Umfeld

**Primärer Mechanismus — Magnetismus (Standard):**
- `HarmonyGraphEngine` liefert Vorschläge für nächste sinnvolle Akkorde
- Diese Vorschläge erhöhen die **magnetische Anziehung** passender Nodes im lokalen Umfeld
- Begriffliche Abgrenzung: `edge.weight` ist Graphgewicht (Auswahllogik im Netz);
  **magnetische Priorisierung** ist räumliche Anziehungskraft auf bereits vorhandene Nodes —
  beides existiert parallel, darf nicht vermischt werden
- Passende Nachbarn werden durch stärkere Magnetfelder bevorzugt
- Kein Eingriff in Chunk-Logik oder Node-Erzeugung

**Sekundärer Mechanismus — Identitätswechsel (Ausnahme):**
- Kein Standardmechanismus — nur unter streng definierten Sonderfällen:
  - kein geeigneter Kandidat im lokalen Umfeld vorhanden
  - Netzwerkwechsel oder Layer-Wechsel wird vorbereitet
  - lokale harmonische Sackgasse (kein valider Nachfolger erreichbar)
- **Nicht** für gewöhnliche funktionale Progressionen (z. B. ii–V–I):
  G7 oder Cmaj7 befinden sich nach Dm7 in der Regel bereits im lokalen Umfeld —
  Magnetismus reicht. Identitätswechsel als Alltagsmechanismus würde die Ausnahme zur Regel machen.
- Nur wenige, lokal begrenzte Nodes betroffen
- Position bleibt stabil; semantische Eigenschaften (Akkord-ID, MIDI, Magnetfeld) wechseln
- Kein visuelles Teleportieren

**Zuständigkeiten:**

| Schicht | Aufgabe |
|---|---|
| `HarmonyGraphEngine` | Berechnet „was ist musikalisch sinnvoll" — kennt keine Positionen, keine Raumstruktur |
| `RuntimeHarmonik` *(eigene Komponente)* | Empfängt Vorschläge, entscheidet: Magnetismus oder Identitätswechsel — keine SceneKit-Aufrufe |
| `HarmonyScene` | Macht bereits entschiedene Änderungen sichtbar — keine Entscheidungslogik |

> `HarmonyScene` darf nicht zur Sammelstelle für Harmonieentscheidungen werden.
> Die Entscheidung (welcher Mechanismus, welcher Node) gehört in `RuntimeHarmonik`.
> `HarmonyScene` rendert nur das Ergebnis.

Die beiden Mechanismen sind konzeptionell unabhängig und werden getrennt implementiert.

**Abgrenzung:**
- Keine Änderung der bestehenden Chunk-Logik in diesem Schritt
- Keine neue Node-Generierung als harmonischer Mechanismus
- Magnetismus und Identitätswechsel sind getrennte Konzepte mit getrennter Implementierung

> **Umsetzungsstand und Konkretisierung (Rev. 6):**
> `RuntimeHarmonik.swift` und `HarmonyScene.applyHarmonicDecision()` existieren bereits,
> die Entscheidung endet aber in einer einzigen Wirkung (`currentMagnetNodeID`). Die räumliche
> Konsequenz fehlt. **Phase 3.9.4 konkretisiert diesen Mechanismus** — sie ersetzt 4.3 nicht.
>
> Der **Identitätswechsel** (Sekundärmechanismus) bleibt konzeptionell bestehen, wird aber
> vorerst **nicht** gebaut: Die naheliegende Umsetzung über den `.noCandidate`-Fall wurde
> als Materialisierungs-Konzept geprüft und verworfen — Lifecycle, Bounds und Caching wären
> Aufwand ohne belegten Nutzen. Siehe `SYNTHESE_3.9.8.md` §5.3.
> `RuntimeHarmonik.swift:121–124` bleibt bis dahin unbenutzt.

---

### Phase 4.4 — UI-Konsolidierung (Funktions-Audit)

**Priorität: HOCH | Risiko: niedrig | Voraussetzung: 4.3, 1e**

> Die strukturelle Aufteilung von ContentView ist in Phase 1e bereits erledigt.
> Phase 4.4 ist der funktionale Audit — keine Strukturarbeit mehr, nur Inhaltsdurchsicht.

**Ziel:** Systematische Durchsicht aller sichtbaren UI-Elemente. Alles, was nicht
genutzt wird, dessen Funktion unklar ist oder das redundant zur tatsächlichen Spielmechanik
steht, wird entfernt oder zusammengeführt.

**Umfang:**
- Audit aller Panels und Controls: SettingsPanel, CockpitHUD, OverlayController, AudioMixerPanel
- Entscheidung pro Element: behalten / entfernen / zusammenführen
- Kein Feature-Abbau — nur UI-Kohärenz
- Ergebnis: dokumentierte Liste erledigter und bewusst behaltener Elemente

---

### Phase 4.5 — Expressive Control: Spannungssteuerung

**Priorität: MITTEL | Risiko: mittel | Voraussetzung: 4.3, 4.4**

> Erste expressive Ebene: der Spieler beeinflusst nicht nur, wo er ist,
> sondern in welche harmonische Richtung er sich bewegt.

**Ziel:** Der linke Joystick steuert harmonische Spannung — d. h. eine Gewichtungsachse
zwischen entspannten und spannungsreichen Kanten. Volle Spannung (Stick oben) priorisiert
dominantische und chromatische Bewegungen; volle Entspannung (Stick unten) bevorzugt
tonische und relMajMin-Verbindungen. Mittellage: keine Beeinflussung (neutrales Verhalten).

**Technische Basis:**
- `HarmonyGraphEngine.weightedChoice()` erhält einen Spannungsparameter
- Joystick-Y-Achse wird als kontinuierlicher Wert (−1 … +1) aus `FlightController` geliefert
- Keine Hardcodierung einzelner RelationTypes — Spannung ist eine skalare Achse über alle Kanten

**Warum jetzt:** Der linke Joystick ist nach dem Gamepad-Ausbau verfügbar. MelodyEngine
und Touchpad (4.6) profitieren von einer etablierten Spannungslogik als Vorstufe.

**Abhängigkeit:** 4.3 (RuntimeHarmonik liefert gewichtete Übergänge), 4.4 (UI bereinigt,
kein paralleles Aufräumen während Implementierung)

#### Offene Designentscheidung (verbindlich vor Implementierung)

Die Spannungsachse ist konzeptionell definiert, aber noch nicht ausreichend spezifiziert
für eine Implementierung. Vor Beginn der Umsetzung müssen drei Fragen verbindlich
geklärt werden:

1. **Wo greift die Spannungsmodulation ein?**
   Vor den Kontextmechanismen (ii-V-Boost, Rückkehr-Dämpfung, Spannungserhalt),
   nach ihnen — oder als eigenständiger Layer, der unabhängig von beiden läuft?
   Die Reihenfolge bestimmt, ob Spannung die Kontextlogik überschreibt oder nur ergänzt.

2. **Wie wirkt die Modulation?**
   Multiplikativ auf Kantengewichte (z. B. ×1.5 für dominantische Kanten bei hoher Spannung),
   additiv, oder relationstyp-spezifisch unterschiedlich — d. h. V-I reagiert anders auf
   Spannung als commonTone?

3. **Ist die Achse linear oder nichtlinear?**
   Eine logarithmische Kurve würde kleine Joystick-Auslenkungen feiner steuerbar machen;
   linear ist einfacher zu implementieren und zu debuggen.

> **Ohne Klärung dieser drei Punkte darf Phase 4.5 nicht implementiert werden.**

---

### Phase 4.6 — Melodic Interaction: Touchpad-Melodiegenerierung

**Priorität: MITTEL | Risiko: mittel | Voraussetzung: 4.5, 1b**

> Zweite expressive Ebene: das Touchpad des Controllers wird zur melodischen Eingabe.

**Ziel:** Das Touchpad des PS5-Controllers löst melodische Phrasen aus oder steuert
melodische Parameter auf Basis der aktuellen harmonischen Position. Die MelodyEngine
(aus Phase 1b, bereits in HarmonyCore) wird damit erstmals als Live-Instrument erfahrbar.

**Mögliche Ausprägungen** *(Entscheidung vor Implementierung)*:
- Touchpad-Position (X/Y) steuert Melodiemuster (z. B. oben = hoch/schnell, unten = tief/langsam)
- Tap löst eine einzelne Phrase aus (single-shot)
- Gedrückthalten = Looping-Phrase, Loslassen = Ende

**Warum jetzt:** MelodyEngine existiert bereits und ist von SceneKit entkoppelt (nach 1b).
Spannungssteuerung (4.5) etabliert das Muster expressiver Joystick/Touchpad-Eingaben.
Touchpad-Infrastruktur (`GamepadController`) ist vorhanden.

**Abhängigkeit:** 4.5 (Spannungslogik als Vorstufe), 1b (MelodyEngine in HarmonyCore),
4.4 (UI-Basis bereinigt)

#### Erwartetes Interaktionsmodell (aktuelle Hypothese)

Das Touchpad wird als zweidimensionale Spieloberfläche interpretiert. Die X-Achse steuert
die Bewegung entlang einer Tonleiter — horizontales Streichen von links nach rechts durchläuft
die Skala aufwärts, von rechts nach links abwärts. Die Y-Achse steuert die Intervallstruktur:
eine niedrige Y-Position (Finger unten) ergibt kleine Intervallschritte (Sekunden, chromatisch
nah), eine hohe Y-Position (Finger oben) ergibt größere Sprünge (Terzen, Quarten und mehr).

Das Ergebnis: horizontales Streichen erzeugt melodische Bewegung, die vertikale Fingerposition
bestimmt den Charakter dieser Bewegung — ob die Melodie schrittweise läuft oder springt.

Diese Hypothese ist der Ausgangspunkt für die Designentscheidung, nicht die finale Spezifikation.

#### Offene Designentscheidung (verbindlich vor Implementierung)

Folgende Punkte müssen vor der Implementierung verbindlich geklärt werden:

1. **Spielmodus:**
   One-shot (ein Tap löst eine abgeschlossene Phrase aus), kontinuierlich (Melodie läuft
   solange der Finger aufliegt), oder hybrid (Tap = Phrase, Halten = Loop)?

2. **Skalenbindung:**
   Strikt an den aktuell aktiven Akkord gebunden (nur Akkordtöne), an das HarmonyWeb
   und seine Skala gebunden (diatonisch), oder frei mit nachträglicher Korrektur
   (enharmonische Quantisierung auf nächsten Skalenton)?

3. **Mapping:**
   Feste Zuordnung X/Y-Koordinate zu einem Ton, oder kontextabhängig dynamisch —
   d. h. das Mapping verschiebt sich wenn der aktive Akkord wechselt?

Mehrere Modi sind wahrscheinlich sinnvoll — die finale Entscheidung ist UX-getrieben,
nicht rein technisch. Wer das spielt, muss es lernen können. Komplexität im Mapping
ist kein Qualitätsmerkmal.

> **Ohne Klärung dieser drei Punkte darf Phase 4.6 nicht implementiert werden.**

---

### Phase 4.7 — Art Direction und visuelle Identität

**Priorität: MITTEL | Risiko: niedrig | Voraussetzung: Art-Direction-Entscheidung durch Stephan**

> Neu in Rev. 6. Grafik hatte in diesem Dokument bisher keinen Platz — obwohl „die Grafik sieht
> billig aus" einer der Auslöser des Reviews 3.9.8 war. Beide Reviews sind sich einig:
> **Effektliste ohne entschiedene Identität ist Blindflug.**

**4.7a — Richtungsentscheidung *(Stephan, blockierend)***

Eine Richtung auswählen:

- Instrumentenraum
- Weltraumkarte
- Konzertvisualisierung
- Editor-/Analysewerkzeug
- eine andere klare Richtung

**4.7b — Danach technische Grafikschritte**

- IBL / Lighting Environment *(derzeit: flacher Hintergrund, kein HDR)*
- HDR / Bloom — Voraussetzung dafür, dass ein Impuls aus 3.9.4a als echter Lichtblitz liest
- Fog / Tiefenstaffelung
- Kanten- und Node-Materialien auf Lesbarkeit trimmen
- SSAO, DoF, Motion Blur **nur**, wenn sie zur gewählten Richtung passen — nicht pauschal

**Akzeptanz:**
- Grafik verbessert Lesbarkeit und Spielgefühl
- Keine Effekte, die Navigation oder musikalische Orientierung verschlechtern

---

---

# STUFE 5 — Ausbau

> **Kein Hard-Prerequisite auf exakt ein Schritt — parallel möglich sobald Stufe 4 stabil ist.**

---

## Phase 5.1 — Buch-inspirierte Map-Familien

- **Callipari**: Topologische Familien (Kreise, Pyramiden, Sterne, Brücken, Ketten) als Layout-Tags
- **Harmony Codex**: Regelbasierte Progressions-Kanten (diatonisch, Sekundärdominanten, modale Mischung)
- Ergebnis: kuratierte Map-Bibliothek im Bundle

### Phase 5.2 — Multi-Layer-Netzwerke

Dieselben Nodes, wechselbarer Kantensatz:

| Layer | Kanten-Semantik |
|---|---|
| `functional` | ii-V-I, V-I, secDom |
| `modal` | relMajMin, modalMix, commonTone3 |
| `chromatic` | chromaticMed, tritSubst, symDim |
| `voiceLeading` | commonTone2+3 optimiert |

Pilot schaltet Layer im Flug (z. B. D-Pad links/rechts, neues Mapping).

### Phase 5.3 — AppSettings finalisieren

> Der Großteil der AppSettings-Bereinigung ist bereits in Phase 1/1d erledigt:
> Phase 1 entfernt `AppSettings.shared` aus HarmonyCore, Phase 1d aus HarmonyScene.
> Phase 5.3 macht den abschließenden letzten Pass auf verbleibende Aufrufstellen.

- Verbleibende `AppSettings.shared`-Zugriffe außerhalb des UI-Layers identifizieren und entfernen
- UI-State: `@Published`-Properties in `FlightController` bleiben erhalten, aber klar von AppSettings getrennt
- Alle UserDefaults-Keys stabil (keine Umbenennung)
- Dateien: `AppSettings.swift`, verbleibende Aufrufstellen (nach Phase 1/1d voraussichtlich deutlich unter 54)

### Phase 5.4 — Input Layer finalisieren

> SCNNode-Entkopplung von FlightController ist bereits in Phase 1.5b abgeschlossen.
> Phase 5.4 adressiert die verbleibenden Input-Layer-Aufgaben.

- `GamepadController`-Init aus `FlightController.init()` in App Layer verlagern
- `TouchInputProvider: InputProvider` für iOS vorbereitet
- Voraussetzung: 1.5b (FlightController von SCNNode entkoppelt)
- Dateien: `GamepadController.swift`, `FlightController.swift`

### Phase 5.5 — Ambient Audio *(optional, klanglich)*

- Shimmer/Glimmer via `preReverbMixer` (Einhängepunkt bereits vorhanden)
- `AVAudioUnitTimePitch` (+1 Oktave) einbinden
- Nur wenn Audio als Engpass wahrgenommen wird — kein Hard-Block

### Phase 5.6 — Multi-Map-Verknüpfung *(v2+, nicht Teil von v1)*

**Risiko: mittel–hoch | Voraussetzung: Stufe 3 stabil (Referenzmap + Importer)**

> Verbindungen zwischen verschiedenen `HarmonyMap`-Dateien — Navigation über Map-Grenzen hinweg.

- **Map-übergreifende Bridge-Kanten:** Kante referenziert `{ mapID, nodeID }` statt nur `nodeID`
- **Namespacing:** Node-IDs werden zu `mapID::nodeID` qualifiziert; verhindert Kollisionen bei identischen IDs in verschiedenen Maps
- **Ladestrategie:** Ziel-Map wird lazy geladen wenn eine Bridge-Kante traversiert wird; Validierung prüft Existenz der Ziel-Node vor dem Traversieren
- **HarmonyGraphEngine-Erweiterung:** Engine erhält einen `MapRegistry`-Kontext; kennt mehrere Maps gleichzeitig
- **Konfliktbehandlung:** Bei identischen Node-IDs in verschiedenen Maps gewinnt die explizit qualifizierte `mapID::nodeID`-Referenz — keine implizite Auflösung
- **v1-Kompatibilität:** `bridgesTo` ist im JSON-Schema bereits reserviert (wird in v1 geparst, aber ignoriert) — kein Breaking Change beim Upgrade

Nicht Bestandteil von v1. Erfordert stabiles Einzel-Map-Modell als Fundament.

### Phase 5.7 — Multi-Web Navigation *(konzeptionell, kein kurzfristiges Feature)*

**Risiko: hoch | Voraussetzung: 5.2 (Multi-Layer stabil), 5.6 (Bridge-Kanten-Mechanismus)**

> Der Spieler wechselt zur Laufzeit zwischen verschiedenen HarmonyWebs —
> nicht nur zwischen Layern innerhalb einer Map.

**Ziel:** Navigation über Map-Grenzen hinweg wird musikalisch erfahrbar. Übergänge zwischen
einem diatonischen Web (z. B. `harmony-web-c-diatonic`) und einem modalen oder Barock-Web
finden über Pivot-Akkorde oder Bridge-Kanten statt — nicht als harter Schnitt.

**Abgrenzung zu 5.6:**
Phase 5.6 definiert den technischen Mechanismus (Bridge-Kanten, Namespacing, MapRegistry).
Phase 5.7 definiert die Nutzererfahrung: wie fühlt sich ein Web-Wechsel während des Flugs an,
wie wird er angezeigt, was passiert mit dem aktuellen Akkordkontext?

**Offene Designfragen** *(zu klären vor Implementierung)*:
- Wechsel: automatisch (durch Bridge-Traversal) oder manuell (Spieler-Geste)?
- Übergangsmechanismus: harter Schnitt / Fade / Pivot-Akkord-Brücke?
- Kontextübergabe: wird der Akkordverlaufskontext in das neue Web mitgenommen?
- Anzeige: wie erfährt der Spieler, dass ein Web-Wechsel stattgefunden hat?

**Warum nicht früher:** Diese Phase setzt ein vollständig stabiles Einzel-Web-System voraus
(Stufe 4 + 5.1–5.6). Ohne das wären Web-Wechsel ein Feature auf wackeligem Fundament.

---

### Phase 5.8 — Render/Input-State-Trennung *(eigenständiges Architekturprojekt)*

**Priorität: MITTEL | Risiko: hoch | Voraussetzung: Stufe 3.9 abgeschlossen, Spielbarkeit belastbar**

> Neu in Rev. 6. Herkunft: `CODEX_REVIEW_3.9.8.md` Finding 1.
> **Bewusste Einordnung nach hinten.** Codex hat diesen Umbau als Priorität 1 vorgeschlagen.
> Widerspruch mit Begründung — siehe `SYNTHESE_3.9.8.md` §4:
> Der strict-concurrency Build läuft durch, der Umbau kostet Wochen und erzeugt null
> wahrnehmbare Veränderung. An einem Projekt, das steht, weil das Fliegen keinen Spaß macht,
> ist das die falsche erste Maßnahme.
>
> **Die Trennlinie ist hörbar vs. architektonisch:** Hängende Noten, nichtdeterministische
> Auswahl und ein davonlaufender Magnet sind hörbar → Stufe 3.9. Ein sauberes Snapshot-Modell
> ist es nicht → hier.
>
> Der einzige Teil des Komplexes, der sofort muss, ist das sent-note tracking → Phase 3.9.1a.

**Ausgangslage:** Pending-Flags werden über Combine vom Main Thread geschrieben und im Render
Loop gelesen. `pendingNetwork`, curated Flags und Dateiname bilden zusammen einen
nicht-atomaren Befehl. `SCNView.projectPoint` wird aus dem Render-Kontext gerufen
(`SceneKitView.swift:140`), obwohl es eine Main-Actor-Operation ist.

**5.8a — Render/Input-State trennen**
- `FlightState` render-only
- Input-Snapshots immutable in den Renderloop geben
- UI bekommt Value-Snapshots statt Live-Zugriff auf Renderzustand
- Überschneidet sich mit **1.5b** (FlightController von SCNNode entkoppeln) — dort mit erledigen

**5.8b — Command Queue**
- UI- und App-Kommandos als atomare Render-Kommandos übergeben
- Keine halb gesetzten Pending-Flags

**5.8c — App-/Render-Config-Snapshots**
- `AppSettings` nicht live aus Renderkontexten lesen — Konfiguration als Snapshot übernehmen
- Überschneidet sich mit **5.3** (AppSettings finalisieren) und dem Hard Stop
  „Kein `AppSettings.shared` in Core"

**Akzeptanz:**
- Strict-concurrency Warnings werden gezielt reduziert
- **Keine wahrnehmbare Funktionsänderung ohne Regressionstest** — 1.5a muss vorher stehen

---

---

# STUFE 6 — Plattform

**Risiko: hoch (Aufwand) | Voraussetzung: Stufe 1–5**

## Phase 6 — iPhone-Target

- Neues SPM Executable `HarmonyiOS`
- `HarmonyCore` unverändert wiederverwendet
- `AudioEngine` läuft bereits auf iOS ohne Änderung
- Neues SwiftUI-UI für iPhone
- `TouchInputProvider` übernimmt Steuerung
- `MIDIManager` bleibt optional

---

---

# CONTENT STREAM — HarmonyWeb Authoring

> **Dauerhaft parallel zur Engine-Entwicklung.**
> Kein gemeinsames Sprint-Scheduling mit Tech- oder Impl-Phasen.
> Kein Code-Zugriff. Kein Eingriff in Architektur oder Implementierung.

---

## Organisatorische Trennung

Der Content-Stream ist ein eigenständiger Arbeitsstrang, der von einem spezialisierten
Claude-Instanz (HarmonyWeb-Claude) betrieben wird. Stephan koordiniert zwischen Engine-Claude
und HarmonyWeb-Claude — beide kommunizieren nicht direkt.

**HarmonyWeb-Claude arbeitet ausschließlich mit:**
- JSON-Dateien in `Sources/HarmonyShared/Resources/maps/`
- Musiktheoretischem Fachwissen (Harmonielehre, Stimmführung, Stilistik)
- Der dokumentierten Akkord-Namenskonvention und dem HarmonyNetwork_Spec_v1.md-Schema

**HarmonyWeb-Claude arbeitet nie mit:**
- Swift-Quellcode
- Architektur- oder Implementierungsentscheidungen
- Dateien außerhalb des maps/-Ordners und der Dokumentation

---

## Aufgaben des Content-Streams

### Laufend: HarmonyWebs erstellen

Überführung der bestehenden `.txt`-Netzwerke in vollständige HarmonyWebs:

| Datei | Ziel-Web | Musikalischer Charakter |
|---|---|---|
| `network_bach.txt` | `harmony-web-d-minor-baroque.json` | d-Moll, Barock-Kadenzformeln, Neapolitaner, Picardische Terz |
| `network_modal.txt` | `harmony-web-modal.json` | Vier Modi (D-Dorisch, A-Mixolydisch, F-Lydisch, E-Phrygisch) |
| `network_quinten.txt` | `harmony-web-circle-of-fifths.json` | Rock/Pop, Dreiklänge, 24-Tonarten |
| `network_blues.txt` | `harmony-web-blues.json` | Blues 12-Bar, dominante Feldharmonik |
| `network.txt` | `harmony-web-c-jazz.json` | Jazz-Erweiterung von C-Dur |

Bereits überführt: `harmony-web-c-diatonic.json` (v3.9.6).

### Laufend: HarmonyLogic pflegen

Zu jedem HarmonyWeb: Überprüfung und Verbesserung von
- RelationType-Klassifikation pro Kante (korrekt? vollständig?)
- Layer-Zuordnung (functional / modal — ist die Trennung musikalisch sinnvoll?)
- Gewichten (plausibel verteilt? spiegeln musikalische Stärke wider?)
- MagnetProfile (strong / medium / weak — vorbereitet für spätere Aktivierung in K3/4.2)

### Validierungspflicht

Jedes HarmonyWeb muss den Viewer-Validierungscheck (DesignerKit) bestehen:
- Keine Namenskonvention-Verletzungen
- Keine doppelten Node-IDs
- Keine ungültigen Kantenreferenzen

Kein Web kommt in den Bundle, das Warnungen erzeugt.

---

## Schnittstelle zur Engine-Entwicklung

Der Content-Stream liefert fertige `.json`-Dateien. Die Engine konsumiert sie ohne
Rückfragen — vorausgesetzt, das Schema (HarmonyNetwork_Spec_v1.md) wird eingehalten.

Wenn das Schema sich ändert (Breaking Change in schemaVersion), informiert Engine-Claude
HarmonyWeb-Claude über Stephan. Bestehende Webs werden dann migriert, bevor neue entstehen.

---

---

## Historischer sequenzieller Gesamtplan bis Rev. 6

> Nicht mehr operativ. Die Ausführungsreihenfolge steht seit Rev. 7 am
> Dokumentanfang.

```
JETZT (Rev. 6 — Stufe 3.9 Reparatur)                   CONTENT STREAM
  │
  ├── Phase 3.9.1 (Hörbare Fehler: On/Off, Determinismus,          ┐
  │                Magnet, Trigger-Hysterese)                       │ dauerhaft
  │         + Tests aus 1.5a für 3.9.1a/3.9.1b vorziehen            │ parallel
  ▼                                                                 │ (eigener
Phase 3.9.2 (Modus-Wahrheit: Explore-Default / Umschalter, HUD)     │  Claude)
  │                                                                 │
  ▼                                                                 │ HarmonyWebs
Phase 3.9.3 (Fundament: Anker/Render, Layer, Map-Pfad, Validator)   │ erstellen +
  │         ◀── verzahnt mit 1.5a (Tests) ──▶                       │ HarmonyLogic
  ▼                                                                 │ pflegen
Phase 3.9.4 (Reaktive Nachbarschaft — erster spielbarer Prototyp)   │
  │                                                                 │
  ▼                                                                 │
─────────── ab hier Plan aus Rev. 5, unverändert gültig ─────────── │
  │                                                                 │
  ├── Phase 0 (Tech-Schulden 0.1–0.11)  ─── parallel ──▶ K5 JSON-Schema
  ▼                                                                 │
Phase 1 (HarmonyCore: 1a–1c) → 1d/1e (Scene- + ContentView-Split)   │
  │                                                                 │
  ▼                                                                 │
Phase 1.5 (Rest-Tests + FlightController-Entkopplung)               │
  │                                                                 │
  ▼                                                                 │
Phase 2 (Netzwerkmodell)  → 3.1–3.5 (Construction Kit)              │
  │                                                                 │
  ▼                                                                 │
Phase 4.1–4.2 (Semantische Koordinaten = Anker + Magnetlogik)       │
  │                                                                 │
  ▼                                                                 │
Phase 4.3 (Runtime-Harmonieintegration)  ◀── konkretisiert durch 3.9.4
  │                                                                 │
  ▼                                                                 │
Phase 4.4 (UI-Konsolidierung) → 4.5 (Expressive Control)            │
  │                              → 4.6 (Melodic Interaction)        │
  ▼                                                                 │
Phase 4.7 (Art Direction ◀ Entscheidung Stephan, dann Grafik)       │
  │                                                                 │
  ├── Phase 5.1 (Buch-Maps)                                         │
  ├── Phase 5.2 (Multi-Layer)                                       │
  ├── Phase 5.3 (AppSettings final)                                 │
  ├── Phase 5.4 (Input Layer final)                                 │
  ├── Phase 5.5 (Ambient Audio, optional)                           │
  ├── Phase 5.6 (Multi-Map-Verknüpfung, technisch)                  │
  ├── Phase 5.7 (Multi-Web Navigation, konzeptionell)  ◀────────────┘
  └── Phase 5.8 (Render/Input-State-Trennung, Architekturprojekt)
  │
  ▼
Phase 6 (iPhone)
```

**Erste konkrete Implementierungsrunde** *(klein und abschließbar halten)*:

1. Phase 3.9.1a — sent-note tracking in der Eventquelle
2. Phase 3.9.1b — deterministischer Runtime tie-break
3. Phase 3.9.1c — `dt`-basierter harmonischer Magnet
4. Minimaltests für 1 und 2, falls das Test-Target ohne Reibung anlegbar ist

Danach: Build, kurzer manueller Spieltest, Doku-Update.

---

## Historischer Statuskatalog bis Rev. 6

> Detailbacklog und Herkunftsnachweis. Bei Status- oder Reihenfolgekonflikten
> gilt die operative Rev.-7-Roadmap am Dokumentanfang.

> **Statuskorrekturen in Rev. 6:** Mehrere Phasen sind teilweise gebaut, obwohl sie als „offen"
> geführt wurden — die Umsetzung ist der Planreihenfolge vorausgeeilt. Die Spalte ist entsprechend
> auf `teilweise` gesetzt, mit Angabe was fehlt. Das ist der Kern des Problems, das Stufe 3.9 löst.

| # | Phase | Inhalt | Stream | Status | Risiko | Voraussetzung |
|---|---|---|---|---|---|---|
| **3.9.1a** | **Fix** | **MIDI On/Off-Symmetrie (sent-note snapshot)** | **Tech** | **erledigt (3.9.9)** | **niedrig** | **–** |
| **3.9.1b** | **Fix** | **Deterministischer Tie-Break (distance, id)** | **Tech** | **erledigt (3.9.9)** | **trivial** | **–** |
| **3.9.1c** | **Fix** | **Harmonischer Magnet zeitbasiert (`dt`)** | **Tech** | **erledigt (3.9.9) — `dt`-Fix + Wiring aktiv** | **niedrig** | **–** |
| **3.9.1d** | **Fix** | **Trigger-Hysterese + Spawn-Sicherheit** | **Tech** | **erledigt (3.9.9)** | **niedrig** | **–** |
| **3.9.2** | **UX** | **Modus-Wahrheit (Explore-Default / Umschalter, HUD)** | **UI** | **erledigt (3.9.9)** | **niedrig** | **–** |
| **3.9.3a** | **Impl** | **Anker/Render-Trennung** | **Impl** | **erledigt (3.9.9, Runde 009)** | **mittel** | **3.9.1** |
| **3.9.3b** | **Impl** | **Layer-Mitgliedschaft explizit** | **Impl** | **erledigt (3.9.9, Runde 010)** | **niedrig** | **3.9.3a** |
| **3.9.3c** | **Impl** | **Verlustfreier Map-Pfad (`toChordNetwork` ablösen)** | **Impl** | **erledigt (3.9.9, Runde 010)** | **mittel** | **–** |
| **3.9.3d** | **Impl** | **Validator erweitern** | **Impl** | **erledigt (3.9.9, Runde 010)** | **niedrig** | **3.2** |
| **3.9.4a** | **Impl** | **Impuls + Nachbarschafts-Antwort** | **Impl** | **erledigt (3.9.9, Runde 010/011)** | **mittel** | **3.9.3a** |
| **3.9.4b** | **Impl** | **Gewichtete Kandidatenliste in `HarmonicDecision`** | **Impl** | **erledigt (3.9.9, Runde 011)** | **niedrig** | **3.9.4a** |
| **3.9.4c** | **Impl** | **Optionales Morphing (Render-Offset, `morphingIntensity`)** | **Impl** | **erledigt (3.9.9, Runde 011)** | **mittel** | **3.9.4a** |
| 0.1 | Tech | MIDIManager Thread-Safety | Tech | offen | niedrig | – |
| 0.2 | Tech | Main-Thread-Fix TargetingOverlay | Tech | offen | niedrig | – |
| 0.3 | Tech | MIDIManager vereinheitlichen | Tech | offen | mittel | – |
| 0.4 | Tech | AudioConfig Persistenz | Tech | offen | niedrig | – |
| 0.5 | Tech | HALC-Startup-Transient | Tech | optional | niedrig | – |
| 0.6 | Tech | CH3-Kanalzug vervollständigen | Tech | offen | niedrig | – |
| 0.7 | Tech | Synth-Ausbau (Wellenform, Filter) | Tech | offen | niedrig | 0.6 |
| 0.8 | Tech | AudioClock (Zeitbasis, BPM, Ticks) | Tech | offen | niedrig | 0.6 |
| 0.9 | Tech | K3-Fix: Opacity-Check ProximityTracker | Tech | offen | niedrig | – |
| 0.10 | Tech | minimal.sf2 entfernen | Tech | offen | trivial | – |
| 0.11 | Doku | SETUP.md aktualisieren | Tech | offen | trivial | Phase 0 |
| 1a | Tech | Proximity + Trigger → HarmonyCore | Tech | offen | mittel | 0 |
| 1b | Tech | MelodyEngine → HarmonyCore | Tech | offen | mittel | 1a |
| 1c | Tech | WorldGeneration → HarmonyCore | Tech | offen | mittel | 1b |
| 1d | Tech | HarmonyScene intern aufteilen (ChunkManager, TriggerCoordinator) | Tech | offen | mittel | 1a–1c |
| 1e | Tech | ContentView aufteilen (SettingsPanel, CockpitHUD, Overlay) | Tech | offen | niedrig | – |
| 1.5a | QS | Unit Tests HarmonyCore | Tech | offen | niedrig | 1 |
| 1.5b | Tech | FlightController von SCNNode entkoppeln | Tech | offen | mittel | 1d |
| K1 | Konzept | Beziehungssprache (Tabelle final) | Konzept | **erledigt** | niedrig | – |
| K2 | Konzept | Abstraktes Datenmodell | Konzept | **erledigt** | niedrig | K1 |
| K3 | Konzept | Magnetphysik-Dokument | Konzept | **→ v2** | niedrig | K2 |
| K4 | Konzept | Formatentscheidung (JSON) | Konzept | **erledigt** | niedrig | K2 |
| K5 | Konzept | JSON-Schema + Beispieldatei | Konzept | **in Arbeit** | niedrig | K4 |
| 2 | Impl | Netzwerkmodell (Typen + Graph-API) | Impl | **teilweise** — Typen + `HarmonyGraphEngine` existieren; ohne Tests (1.5a) | mittel | 1, K5 |
| 3.1 | Impl | Editor-Umbau DesignerKit | Impl | **teilweise** — DesignerKit integriert | mittel | 2 |
| 3.2 | Impl | Validierungsschicht | Impl | **teilweise** — `validate()` gehärtet (3.9.3d, Runde 010); Tests (1.5a) weiterhin offen | niedrig | 3.1 |
| 3.3 | Impl | Runtime-Importer | Impl | **teilweise** — `HarmonyMapLoader` layer-konsistent, Legacy-Verlust dokumentiert (3.9.3c, Runde 010); Direktpfad auf `HarmonyMap` weiterhin offen | mittel | 3.2 |
| 3.4 | Impl | Erste Referenzmap | Impl | **teilweise** — `reference-core`, `harmony-web-c-*` vorhanden | niedrig | 3.3 |
| 3.5 | Impl | Regelbasierte Builder | Impl | offen | mittel | 3.4 |
| 4.1 | Impl | Semantische 3D-Koordinaten *(= Anker für 3.9.3a)* | Impl | **teilweise (Runde 012)** — JSON-Web-Preview nutzt `SemanticHarmonyLayout`/`layout3D`; Force-Relaxierung + Chunk-Integration offen | mittel | 3.4 |
| 4.2 | Impl | Magnetlogik im Flug | Impl | **teilweise (Runde 014)** — `HarmonicMagnetInfluence` wertet `MagnetProfile`-Preset + moderaten Score-Boost (4.2a) und `RelationType`-Feldklassifikation (4.2b) aus; UI-Anbindung + preset-abgeleiteter Range-Falloff offen | mittel | 4.1, K3 |
| 4.3 | Impl | Runtime-Harmonieintegration (Magnetismus + Identitätswechsel) | Impl | **teilweise** — `RuntimeHarmonik` existiert, räumliche Wirkung fehlt → 3.9.4; Identitätswechsel zurückgestellt | mittel | 4.1, 4.2 |
| 4.4 | UI | UI-Konsolidierung (Funktions-Audit) | UI | offen | niedrig | 4.3, 1e |
| 4.5 | Impl | Expressive Control: Spannungssteuerung (Joystick) | Impl | offen | mittel | 4.3, 4.4 |
| 4.6 | Impl | Melodic Interaction: Touchpad-Melodiegenerierung | Impl | offen | mittel | 4.5, 1b |
| **4.7** | **UI** | **Art Direction + Grafik (IBL/HDR/Bloom/Fog)** | **UI** | **offen** | **niedrig** | **Entscheidung Stephan** |
| 5.1 | Impl | Buch-inspirierte Map-Familien | Impl | offen | niedrig | 4.3 |
| 5.2 | Impl | Multi-Layer-Netzwerke | Impl | offen | mittel | 4.2 |
| 5.3 | Tech | AppSettings finalisieren (letzter Pass) | Tech | offen | niedrig | 1, 1d |
| 5.4 | Tech | Input Layer finalisieren | Tech | offen | niedrig | 1.5b, 5.3 |
| 5.5 | Impl | Ambient Audio | optional | offen | niedrig | 1 |
| 5.6 | Impl | Multi-Map-Verknüpfung (Bridge-Kanten, technisch) | Impl | offen | mittel–hoch | 3 stabil |
| 5.7 | Konzept | Multi-Web Navigation (UX, konzeptionell) | Konzept | offen | hoch | 5.2, 5.6 |
| **5.8** | **Tech** | **Render/Input-State-Trennung (Command Queue, Snapshots)** | **Tech** | **offen** | **hoch** | **3.9, 1.5a** |
| 6 | Plattform | iPhone-Target | Plattform | offen | hoch | 5 |

---

## Offene Designentscheidungen

*(Müssen vor dem jeweiligen Meilenstein entschieden sein)*

| Entscheidung | Zu entscheiden vor | Optionen | Empfehlung |
|---|---|---|---|
| **Art Direction** | **4.7** | **Instrumentenraum / Weltraumkarte / Konzertvisualisierung / Editor** | **offen — nur Stephan** |
| ~~Startmodus~~ | 3.9.2 | Explore als Default / sichtbarer Umschalter | **entschieden (3.9.9): Default Explore + expliziter Preview-Start, kein Live-Umschalter** |
| ~~Morphing-Default~~ | 3.9.4c | `0.0` / niedriger Wert | **entschieden (Runde 011): `0.0`** — Regler manuell hochregelbar, kein Auto-Wert |
| ~~Obergrenze sichtbarer Nachbarn~~ | 3.9.4a | fester Wert / aus Knotengrad abgeleitet | **entschieden (Runde 011): fester Wert `4`** (`RuntimeHarmonik.maxCandidates`, konsistent mit `impulseMaxNeighbors`) |
| **Identitätswechsel überhaupt bauen?** | **nach 3.9.4** | **v2 / streichen** | **offen — 4.3 bleibt konzeptionell** |
| JSON-Schema-Version | K4 | `"1.0"` / Semver | `"1.0"` |
| Semantik + Layout: getrennte Blöcke? | K5 | ein Block / zwei Blöcke | getrennt |
| Gravitationszentren: explizit oder aus Kanten | K3 | implizit / explizit | explizit |
| Abstoßung aktivieren | K3 | opt-in / immer aus | opt-in |
| Layer-Umschaltung im Flug | 5.2 | D-Pad / Menü | D-Pad |
| Progressions-Gedächtnis N | 4.2 | 3 / 4 / 5 Akkorde | 4 |
| Callipari-Topologie: Pflichtfeld oder Tag? | 5.1 | Pflicht / optional | optionaler Tag |
| Spannungsachse: linear oder kurvenförmig? | 4.5 | linear / quadratisch | offen |
| Touchpad-Melodie: one-shot oder loop? | 4.6 | one-shot / loop / beide | offen |
| Web-Wechsel: automatisch oder manuell? | 5.7 | auto (Bridge) / manuell (Geste) | offen |
| Kontextübergabe bei Web-Wechsel | 5.7 | Reset / übernehmen / Pivot | offen |

---

*Dieses Dokument ersetzt die Roadmap-Abschnitte in `TODO.md` und `HarmonyEngine3D_Roadmap.md`.*
*`HarmonyNetwork_Design.md` und `ARCHITECTURE.md` bleiben als Fachquellen erhalten.*

---

### Änderungen in Rev. 6 (2026-07-14)

`ROADMAP_3.9.8_NEXT_ROUNDS.md` ist vollständig hier aufgegangen und wurde gelöscht.
Diese Roadmap ist wieder die einzige Quelle für Reihenfolge und Scope.

| Was | Wo |
|---|---|
| Neue Stufe 3.9 — Reparatur und Fundament (Runden 1–3, 5 der NEXT_ROUNDS) | Stufe 3.9 |
| Runde 4 (Tests) — **zusammengeführt**, statt zweitem Test-Target | Phase 1.5a |
| Runde 6 (Grafik) — neue Phase, Grafik hatte bisher keinen Platz | Phase 4.7 |
| Runde 7 (Concurrency) — als eigenes Projekt nach hinten eingeordnet | Phase 5.8 |
| Pakete A–I der NEXT_ROUNDS — in die Phasen 3.9.1–3.9.4 überführt | Stufe 3.9 |

**Inhaltliche Korrekturen, die beim Einarbeiten nötig waren:**

1. **„Eventpfade symmetrisch" aus den erledigten Phasen zurückgezogen** — durch den
   Octave-Shift-Bug widerlegt. Die Invariante gilt weiter, ist aber derzeit verletzt.
2. **Note-Tracking-Ort korrigiert.** Die NEXT_ROUNDS nannten `OutputCoordinator.swift`
   als Zieldatei für 3.9.1a. Das verletzt die Schichtenregel dieses Dokuments
   („Kein Note-Tracking im OutputCoordinator"). Verbindlich: Der Snapshot gehört in die
   Eventquelle. Siehe Phase 3.9.1a.
3. **Determinismus-Invariante geschärft** — sie galt bisher nur für `SeededRNG`/Weltgenerierung.
   Der Tie-Break-Befund zeigt, dass sie auch für Laufzeit-Entscheidungen gelten muss.
4. **Anker-Invariante neu aufgenommen** — logischer Anker ≠ Render-Position.
5. **Statusspalte korrigiert** — Phasen 2, 3.1–3.4, 4.2, 4.3 auf `teilweise`.
   Die Umsetzung war der Planreihenfolge vorausgeeilt; das war als „offen" nicht sichtbar.
6. **Phase 4.1 nicht ersetzt, sondern als Voraussetzung geklärt** — die semantischen
   Koordinaten *sind* die Anker. Der Kammer-Vorschlag aus `REVIEW_3.9.8.md` §7 ist damit
   in seiner ursprünglichen Form (globales Layout ersetzen) hinfällig.
