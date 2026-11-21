# HarmonyEngine3D - Atmospheric Synth and Space Engine Plan

Status: Planungsentwurf, 2026-07-29

Dieser Plan beschreibt den Ausbau des internen Klangerzeugers zu einem
eigenstaendigen atmosphaerischen Instrument mit grossen Hall- und
Delayraeumen. Die Klangrichtung ist von der Idee komplexer, lebendiger
Software-Synthese inspiriert, insbesondere von Wellenform-Morphing,
mehrstufiger Modulation und langen zeitlichen Entwicklungen.

Der Plan ist ausdruecklich kein Auftrag, NI Absynth technisch, visuell oder
inhaltlich zu kopieren. Es werden weder proprietaere Presets, Wellenformen,
Samples, Bedienkonzepte, Namen noch Quellcode uebernommen.

## 1. Ergebnisbild

HarmonyEngine3D soll nicht wie ein einfacher General-MIDI-Ersatz klingen.
Der interne Synth soll selbst ein Teil des Instruments sein:

- Akkorde oeffnen breite, langsam atmende Klangraeume.
- Bass bleibt koerperlich, zentriert und harmonisch lesbar.
- Melodien koennen leuchten, schweben und sich ueber Zeit verwandeln.
- einzelne Chord-Tones reagieren direkt und bleiben spielbar.
- Hall und Delay bilden einen zusammenhaengenden Raum statt vier isolierter
  Effektketten.
- vier Performance-Makros erlauben musikalische Veraenderung ohne
  Synthesizer-Fachwissen.
- ein tiefer Editor bleibt fuer Sounddesign verfuegbar, ist aber nicht die
  erste Bedienebene.

Arbeitstitel fuer das System: **Harmony Spatial Synth**. Das ist kein
Produktname und keine Markenentscheidung.

## 2. Klangliche Leitlinien

### 2.1 Vier Klangsaeulen

1. **Evolving**
   Ein Klang darf sich waehrend einer gehaltenen Note deutlich entwickeln.
   Wellenform, Filter, Pegel, Panorama und Raumanteil sollen langsam und
   kontrolliert moduliert werden koennen.

2. **Harmonic clarity**
   Auch bei grossen Raeumen muessen Grundton, Akkordfunktion und Stimmfuehrung
   erkennbar bleiben. Tiefe Frequenzen werden nicht unkontrolliert in lange
   Feedback-Schleifen geschickt.

3. **Spatial depth**
   Tiefe entsteht aus Pre-Delay, fruehen Reflexionen, Diffusion, moduliertem
   Nachhall und gefiltertem Feedback. Ein hoher Wet-Wert allein gilt nicht als
   grosser Raum.

4. **Playable motion**
   Bewegung muss musikalisch bedienbar sein. Die erste Performance-Ebene
   besteht aus wenigen Makros; komplexe Modulationsrouten liegen dahinter.

### 2.2 Rollen der vier bestehenden Kanaele

Die Namen sind interne Designlabels, keine festgelegten Presetnamen.

| Kanal | Rolle | Klangziel | Raumverhalten |
|---|---|---|---|
| CH0 Chord | Aether | weich, breit, evolvierend | tiefer Hall, moderates Echo |
| CH1 Bass | Ground | stabil, fokussiert, obertonreich steuerbar | wenig Tiefbass im Send, kurzer Early-Anteil |
| CH2 Melody | Signal | praesent, beweglich, farbig | deutliches Echo, langer Hall |
| CH3 Chord Tone | Spark | direkt, artikuliert, expressiv | kurzer Raum, optional langer Send |

## 3. Heutiger Bestand

Der Bestand ist kein Wegwerfprototyp. Folgende Teile sind tragfaehig:

- `AudioOutput` und `OutputCoordinator` trennen musikalische Events vom
  konkreten Audio-Backend.
- `AudioEngine.commandQueue` stellt einen einzelnen Producer fuer die
  lockfreien `NoteEventQueue`-Instanzen her.
- vier getrennte `SynthNode`-Instanzen entsprechen den vier musikalischen
  Kanaelen.
- `SynthVoice` besitzt bereits PolyBLEP-Wellenformen, ADSR, Filter,
  Unison und Voice-Stealing.
- Parameteraenderungen erreichen den Audio-Thread geordnet als
  `.paramUpdate`.
- der Audio-Renderpfad ist lock- und allokationsfrei angelegt.
- der bestehende Mixer ermoeglicht Live-Aenderungen und Persistenz.
- CH1 (Bass) hat zusaetzlich einen fest verdrahteten Kompressor
  (`AVAudioUnitDynamicsProcessor` via `AudioUnitSetParameter`-Rohwerte)
  zwischen `gainBass` und den Delay-Sends/`sumBass`. Kein anderer Kanal hat
  ein aequivalentes Element. Jede Neuordnung des Signalflusses (Abschnitt
  7.1) muss explizit festlegen, wo dieser Kompressor im neuen Graph sitzt
  (vor oder nach dem gemeinsamen Space-/Echo-Send) — sonst geht ein
  bestehendes, klanglich wirksames Element beim Umbau unbemerkt verloren
  oder wirkt plötzlich auf den gemeinsamen Raum statt nur auf CH1.

Die wesentlichen Grenzen:

- pro Voice existiert nur ein einfacher Oszillator-Typ; es gibt kein
  Wellenform-Morphing, keine Operator-Kombination und keine Klangquelle fuer
  Textur oder Rauschen.
- die Modulation beschraenkt sich im Wesentlichen auf ADSR und statische
  Parameter.
- `ChannelFXConfig` mischt Synthese-, Kanal- und Effektparameter in einem
  Typ.
- jeder Kanal besitzt drei eigene `AVAudioUnitDelay`-Instanzen und ein
  eigenes Factory-Preset-Reverb. Das ist kontrollierbar, erzeugt aber keinen
  gemeinsamen akustischen Raum.
- `AVAudioUnitReverb` stellt hier Preset-Auswahl plus Wet/Dry bereit; zentrale
  Raumparameter wie Groesse, Diffusion, Modulation, Freeze und kontrollierte
  lange Decays sind nicht Teil des aktuellen Produktmodells.
- ein versioniertes Synth-Presetformat und eine Factory-/User-Bank fehlen.
- echte 3D-Audiopositionen gehen am heutigen
  `noteOn(channel:note:velocity:)`-Vertrag verloren. Ein Chord-Event traegt
  keine Ball-ID oder Weltposition bis in den Audio-Layer.
- es gibt noch keinen reproduzierbaren Offline-Audio-Render als
  Regressionstest.

## 4. Zielarchitektur

### 4.1 Schichten

```text
InteractionRuntime / Gamepad
            |
            v
OutputCoordinator -> AudioOutput
            |
            v
AudioEngine host + commandQueue
            |
            +--> Channel 0 SynthHost --+
            +--> Channel 1 SynthHost --+--> dry channel mixer --> master
            +--> Channel 2 SynthHost --+
            +--> Channel 3 SynthHost --+
                       |       |
                       |       +--> EchoField send --+
                       +----------> DeepSpace send --+--> returns --> master

HarmonyAudioCore
  VoiceEngine
  Oscillators / Wavetables / Noise
  Envelopes / LFOs / Modulation Matrix
  Filters / Shaper
  EchoField DSP
  DeepSpace DSP
  Preset model and validation
```

### 4.2 Neues Target `HarmonyAudioCore`

Empfehlung: ein neues SwiftPM-Library-Target, das nur die DSP- und
Presetlogik enthaelt.

Erlaubte Abhaengigkeiten:

- Swift Standard Library und Foundation fuer Value-Modelle/Codec;
- Apple Accelerate fuer vDSP/vektorisierte DSP-Operationen.

Nicht erlaubt:

- SwiftUI;
- SceneKit;
- `AppSettings`;
- `RuntimeHarmonik`;
- `MIDIManager`;
- Singletons;
- direkter Zugriff auf `AVAudioEngine`.

AVFAudio bleibt im `HarmonyEngine3D`-Host. Damit kann derselbe DSP-Kern
offline in Tests und realtime im `AVAudioSourceNode` gerendert werden.

**Konkrete Zuordnung heutiger Dateien zu den Zielschichten** (Stand
SYNTH-00-Audit, 2026-07-29):

| Heutige Datei | Zielschicht | Begruendung |
|---|---|---|
| `SynthVoice.swift` (Oszillator, Filter, ADSR, PolyBLEP) | `HarmonyAudioCore` | reine Sample-fuer-Sample-DSP, kein AVFAudio-Typ, schon heute alloc-/lockfrei |
| `SynthParams.swift` (Value-Typ) | `HarmonyAudioCore` | reiner Value-Snapshot, keine Abhaengigkeit |
| `NoteEventQueue.swift` (SPSC-Ringpuffer + `NoteEvent`) | `HarmonyAudioCore` | kennt weder AVFAudio noch AppSettings, ist der bestehende Producer/Consumer-Vertrag |
| `SynthNode.swift` — die `VoicePool`-Logik (Voice-Auswahl, Voice-Stealing, Event-Dispatch) | `HarmonyAudioCore` | reine Steuerlogik ueber Voices, kein AVAudioSourceNode-Wissen noetig |
| `SynthNode.swift` — `sourceNode`-Aufbau (`AVAudioSourceNode`, Render-Closure-Wiring) | `HarmonyEngine3D`-Host | haelt den AVFAudio-Typ; ruft aber nur `pool.render(...)` im Core auf — dünne Bruecke |
| `AudioEngine.swift` (Graph-Aufbau, `commandQueue`, `synthParams(from:)`-Mapping, Kanal-Fader/Delay/Reverb-Nodes, Kompressor) | `HarmonyEngine3D`-Host | AVAudioEngine-Graph-Besitz bleibt vertragsgemaess im App-Target (Abschnitt 4.3) |
| `AudioOutput.swift`, `OutputCoordinator.swift` | unveraendert, bleiben Grenze | `HarmonyAudioCore` kennt diese Typen nicht; der Host bindet sie weiterhin |

Diese Tabelle ist die praktische Grundlage fuer S-02a/S-02b (Abschnitt 14) —
sie sagt konkret, welcher heutige Code in den neuen Core wandert und
welcher im App-Target bleibt, statt das nur abstrakt zu benennen.

### 4.3 Bestehende Grenzen bleiben erhalten

- `OutputCoordinator` bleibt ein 1:1-Eventuebersetzer und entscheidet keinen
  Klang.
- `AudioEngine` baut und besitzt den AVAudioEngine-Graph, entscheidet aber
  keine Harmonik.
- der neue DSP-Kern kennt weder Akkordfunktionen noch RelationTypes.
- musikalisch motivierte Klangmodulation wird spaeter ueber einen typisierten
  Value-Snapshot eingespeist, nicht durch Imports in den DSP-Kern.
- MIDI-Ausgabe bleibt parallel funktionsfaehig.

## 5. Realtime-Vertrag

Der Audio-Renderthread darf:

- vorbereitete Arrays und feste Voice-/Modulator-Pools lesen und schreiben;
- primitive Value-Snapshots anwenden;
- deterministische DSP-Funktionen ausfuehren.

Der Audio-Renderthread darf nicht:

- Speicher allokieren;
- Locks nehmen;
- Dispatch oder Swift-Concurrency starten;
- Dateien, Presets oder UserDefaults lesen;
- loggen;
- UI-/Scene-/Map-Zustand abfragen;
- den AVAudioEngine-Graph umbauen.

Weitere verbindliche Regeln:

- Tabellen, Delaylines und FFT-/vDSP-Setups werden ausserhalb des
  Rendercallbacks vorbereitet.
- Parameter werden geglaettet, damit Reglerbewegungen keine Klicks erzeugen.
- strukturelle Presetwechsel werden als vollstaendiger Snapshot uebergeben.
- Note-On, Note-Off, All-Off und Panic behalten die bestehende
  On/Off-Symmetrie.
- Queue-Overflow darf All-Off/Note-Off nicht unsichtbar verschlucken.
- Voice-Stealing muss ein kontrolliertes kurzes Release oder einen
  entklickten Wechsel verwenden.
- NaN, Infinity, Denormals und instabile Feedbackwerte werden an jeder
  externen Parametergrenze abgefangen.

## 6. Synthese-Engine

### 6.1 Erste eigenstaendige Voice

Die erste Ausbaustufe soll drei Klangquellen besitzen:

1. **Source A: Morph Oscillator**
   Bandlimitierte Wavetable-Familie mit kontinuierlichem Morphing zwischen
   zwei Spektren.

2. **Source B: Morph Oscillator**
   Unabhaengige zweite Familie, Transposition, Feinstimmung und Phase.

3. **Source C: Texture**
   gefaerbtes Rauschen und einfache resonante Textur. Granularwiedergabe
   folgt erst spaeter, damit Dateizugriff, Sampleverwaltung und zusaetzliche
   Realtime-Risiken nicht in den ersten Klangkern geraten.

Misch- und Interaktionsmodi der ersten Version:

- linearer Mix A/B/C;
- Ringmodulation A x B;
- sanfte Phasen- oder Frequenzmodulation in begrenzter Tiefe;
- Waveshaper nach dem Mix.

Nicht fuer die erste Version:

- freie modulare Patchkabel;
- beliebige Audio-Rate-Modulationsgraphen;
- Sampleimport;
- granularer Dateibrowser;
- exakte Nachbildung fremder Synthesemodule.

### 6.2 Wavetables

- Factory-Wavetables werden aus eigenen harmonischen Spektren erzeugt oder
  als eigenstaendige, lizenzierte Projektassets abgelegt.
- pro Tabelle existieren bandlimitierte Mip-Stufen gegen Aliasing.
- Morphing interpoliert phasenkonsistent.
- Tabellen und Mip-Auswahl werden vor dem Rendern vorbereitet.
- der bestehende PolyBLEP-Oszillator bleibt als Legacy-/Fallback-Engine
  erhalten, bis Klang- und Performance-Gates bestanden sind.

### 6.3 Filter und Shaping

Erste Zielausstattung:

- stabiler State-Variable-Filter mit Lowpass, Bandpass und Highpass;
- optionaler zweiter einfacher Highpass vor dem Raum-Send, besonders fuer
  Bass;
- Drive/Waveshaper mit kompensiertem Ausgangspegel;
- Keytracking und Envelope Amount;
- parameter-geglaettete Cutoff-/Resonanzwerte.

Eine aufwendige nichtlineare Ladder-Simulation oder Oversampling wird erst
nach Messung hinzugefuegt.

### 6.4 Huelle, LFO und Modulationsmatrix

Erste Zielausstattung:

- Amp-ADSR;
- Mod-ADSR;
- drei LFOs mit Sine, Triangle, Sample-and-Hold und geglaettetem Random;
- feste Modulationsmatrix mit zunaechst maximal 16 Routen;
- bipolarer Amount pro Route;
- per-Voice- und globaler Modulatorstatus klar getrennt;
- optionales One-Shot und Key-Sync pro LFO;
- Tempo-Sync erst nach einem belastbaren `AudioClock`.

Spaetere Ausbaustufe:

- grafische mehrsegmentige Huelle;
- Loop-/Sustain-Segmente;
- freie Kurven;
- Audio-Rate-Modulation ausgewaehlter Ziele.

### 6.5 Performance-Makros

Vier stabile Makros bilden die erste Spielebene:

| Makro | Primaere Wirkung |
|---|---|
| Motion | LFO-/Huellen-Tiefe, Morphbewegung |
| Color | Spektrum, Filter, Shaping |
| Space | Echo-/Hall-Sends, Decay innerhalb sicherer Grenzen |
| Focus | Stereo-Breite, Transienten, Dry/Wet-Balance |

Ein Preset definiert, welche internen Ziele ein Makro bewegt. Die Makros
selbst bleiben in der UI und in Controller-Mappings stabil.

**Stand nach W-05 (Runde 074) — die Tabelle oben ist noch nicht erfuellt.**
Die Makros sind verdrahtet und am Controller bedienbar, aber die vier
Routen in `AudioCoreAtmosphericVoiceParameters.defaultModulationMatrix`
sind eine Naeherung dieser Tabelle, keine Umsetzung. Von den sieben
`AudioCoreModulationTarget`-Zielen entspricht nur `spaceSend` einem
Plan-Makro exakt; LFO-/Huellen-Tiefe, Stereo-Breite, Transienten und
Dry/Wet gibt es als Ziele gar nicht. Zwei Grenzen der festen Matrix
stecken dahinter:

1. Ein Makro legt einen STATISCHEN Beitrag auf ein Ziel. "Motion =
   LFO-Tiefe" waere Quelle x Quelle und braeuchte eine Matrixerweiterung.
2. Alle Makros sind unipolar `0...1` mit Default `0` — Voraussetzung
   dafuer, dass der Klang ohne CC-Eingang bit-identisch bleibt. Ein Makro
   kann vom Basiswert aus also nur in EINE Richtung wirken.

Die aktuelle vorlaeufige Belegung steht am Code und in `ARCHITECTURE.md`.
Ob die Tabelle oben spaeter durch neue Modulationsziele erfuellt oder
angepasst wird, ist eine Klangentscheidung durch Stephan.

## 7. Space Engine

### 7.1 Routing

Empfehlung: zwei gemeinsame Stereo-Send-Busse statt vier vollstaendig
isolierter Raumketten.

```text
channel dry -------------------------------> master
channel Echo send -> EchoField ------------> master
channel Space send -> DeepSpace -----------> master
```

**Entschieden (Stephan, 2026-07-30, Option A):** der bestehende
CH1-Kompressor (Abschnitt 3) bleibt konservativ vor dem Space-/Echo-Send —
er wirkt weiterhin nur auf den CH1-Dry-Anteil, wie heute. Der CH1-Feed in
die kuenftigen gemeinsamen Sends greift VOR dem Kompressor ab und wird
nicht komprimiert. Umsetzung als deklarativer Topologie-Plan in S-07a
(`AudioGraphTopology.swift`, Abschnitt 14) — die tatsaechliche
`AVAudioNode`-Verkabelung des CH1-Sends folgt erst in S-07b/S-09.

Vorteile:

- alle Kanaele stehen im selben akustischen Raum;
- wesentlich weniger duplizierter Effektzustand;
- Bass kann separat hochpassgefiltert in den Raum geschickt werden;
- gemeinsame Freeze-/Morph-Aktionen sind musikalisch moeglich;
- CPU-Budget wird fuer Qualitaet statt vierfache Duplizierung genutzt.

### 7.2 `EchoField`

Ziel:

- vier Stereo-Taps;
- 1 ms bis 4 s pro Tap;
- Cross-Feedback und Ping-Pong;
- Hoch-/Tiefpass im Feedback;
- Diffusion vor oder in der Feedbackschleife;
- leichte Zeitmodulation;
- Ducking durch das trockene Eingangssignal;
- Freeze mit sicher begrenztem Feedback;
- freier Zeitmodus zuerst, Tempo-Sync nach `AudioClock`.

Die aktuelle Drei-Tap-Konfiguration wird in einem Migrationspreset
verlustarm abgebildet.

### 7.3 `DeepSpace`

Empfohlene erste Eigenentwicklung: algorithmischer modulierter
Feedback-Delay-Network-Hall.

Bausteine:

- Pre-Delay;
- getrennte Early Reflections;
- Eingangs-Diffusoren;
- mindestens acht unterschiedlich lange Delaylines;
- orthogonale Feedback-Matrix;
- frequenzabhaengige Daempfung;
- langsame, decorrelierte Delaymodulation;
- Stereo-Ausgangsmatrix;
- Tail von kurzen Raeumen bis zu sehr langen Flaechen;
- Freeze mit kontrolliertem Input-Crossfade;
- Send-Highpass und Return-EQ.

Shimmer ist ein spaeteres Modul. Ein Pitch-Shifter in der Feedbackschleife
erhoeht CPU-, Latenz- und Stabilitaetsrisiko deutlich und soll nicht die
Grundqualitaet des Halls verdecken.

### 7.4 Factory-Fallback

Der heutige AVAudioUnit-Reverb-/Delay-Pfad bleibt bis zur Abnahme der neuen
Busse als umschaltbarer Legacy-Pfad erhalten. Ein Graphwechsel erfolgt nie
aus dem Rendercallback und nie waehrend klingender Noten ohne kontrolliertes
Crossfade/All-Off.

## 8. 3D-Audio und HarmonyWeb

Ein `AVAudioEnvironmentNode` kann eine 3D-Hoerumgebung mit Listener,
Distanzdaempfung und Reverb darstellen. Der aktuelle Eventvertrag liefert
dem Audio-Layer jedoch nur Kanal, MIDI-Note und Velocity. Damit ist nicht
bekannt, welcher Harmony-Ball die Note erzeugt hat und wo er liegt.

Deshalb gilt:

- Synth V1 und Space V1 arbeiten kanalweit in Stereo.
- echte per-Ball-Positionierung ist ein eigener spaeterer Slice.
- dieser Slice benoetigt eine stabile `SoundSourceID` plus
  Weltpositions-Snapshots an der Output-Grenze.
- Chord-Voice-Leading und Note-Off-Symmetrie duerfen durch Positionswechsel
  nicht aufgebrochen werden.
- ein Harmony-Ball ist nicht automatisch eine eigene Synthinstanz.
  Stimmen koennen innerhalb eines Kanalhosts raeumlich verteilt werden.

## 9. Presetmodell

### 9.1 Versioniertes Format

Vorgeschlagene Value-Typen:

```text
SynthPreset
  schemaVersion
  id
  name
  author
  engineVersion
  sources
  filter
  envelopes
  lfos
  modulationRoutes
  macroMappings
  voice

SpacePreset
  schemaVersion
  echoField
  deepSpace
  master

InstrumentScene
  schemaVersion
  channelPresetIDs[4]
  channelSends[4]
  spacePresetID
  macroValues
```

Regeln:

- `Codable`, striktes Decoding und strukturierte Validierung;
- Factory-Presets im Bundle;
- User-Presets in Application Support;
- atomisches Speichern;
- unbekannte neuere Schema-Version blockiert mit Diagnose;
- Migrationen sind explizite Funktionen, keine stillen Default-Fuellungen;
- Presetwechsel veraendert keine HarmonyMap.

### 9.2 Migration aus dem Bestand

Jede heutige `ChannelFXConfig`-Voreinstellung bekommt ein Legacy-Preset.
So bleiben Chord-, Bass-, Melody- und ChordTone-Klang erreichbar. Erst ein
spaeterer Produktentscheid darf neue Factory-Presets zum Default machen.

## 10. Bedienkonzept

### 10.1 Zwei Ebenen

**Play View**

- Preset/Scene-Auswahl;
- vier Performance-Makros;
- Kanalpegel und Mute/Solo/Panic;
- Echo- und Space-Send pro Kanal;
- klare Pegel-/Aktivitaetsanzeige.

**Synth Lab**

- Tabs: Sources, Shape, Modulation, Space, Routing;
- ein Kanal gleichzeitig im Fokus;
- Modulationsrouten als Quelle, Ziel, Amount;
- keine vier vollstaendigen Synth-Editoren nebeneinander;
- Preset Save/Save As/Compare/Reset;
- immer sichtbarer Panic-Befehl.

Der heutige `AudioMixerPanel` bleibt zunaechst bestehen. Seine direkte
Bindung an `AppSettings.audio` wird erst nach Vorliegen des neuen
Preset-/Snapshotmodells schrittweise ersetzt.

### 10.2 Controller

**Stand nach W-04 (Runde 073):** Der MIDI-Eingang steht. Die App hat ein
virtuelles Ziel „HarmonyEngine3D Input" und kann sich zusaetzlich mit einer
waehlbaren externen Quelle verbinden. Noten spielen den aktiven
`AudioOutput` — bei internem Synth also die Atmospheric Voice. Control
Changes werden empfangen und im `MIDIControlChangeRegistry` je (Kanal,
Controller) mit dem letzten Wert bereitgehalten, samt Beobachter-Haken.

**W-04 bildet ausdruecklich nichts auf Parameter ab.** Der Registry-Zugriff
ist genau der Abholpunkt, an dem W-05 die vier Performance-Makros anhaengt.

**Erledigt in W-05 (Runde 074):** der Beobachter-Haken der Registry haengt
an `MIDIMacroCoalescer`; die Zuordnung CC → Makro liegt im App-Layer und
ist einstellbar, die Zuordnung Makro → Klangziel als Routendaten in der
Modulationsmatrix. Der Grundsatz unten ist damit eingehalten: kein
Controller-Mapping im Synth-Core. Zwischen beidem sitzt eine Drossel mit
20 ms Mindestpause, ohne die ein Reglerschwenk `commandQueue` und
`NoteEventQueue` fluten wuerde (gemessen: 2.032 statt 168
`paramUpdate`-Ereignisse pro Sekunde bei vier bewegten Reglern). Details
in `ARCHITECTURE.md`, Abschnitt „CC → Performance-Makro".
Damit gilt der Grundsatz unten bereits heute: kein Controller-Mapping liegt
im Synth-Core.

Empfohlene spaetere Zuordnung:

- vier Makros auf vorhandene expressive Achsen/Modifier;
- Panic bleibt unveraendert erreichbar;
- kein Controller-Mapping wird im Synth-Core hardcodiert;
- Controller- und UI-Werte werden in derselben normalisierten
  Parametergrenze zusammengefuehrt.

## 11. Harmony-getriebene Klangbewegung

Die Klangengine darf Harmony nicht interpretieren. Eine spaetere Bridge kann
bereits entschiedene musikalische Werte als Snapshot liefern, zum Beispiel:

- harmonische Spannung 0...1;
- Bewegungsintensitaet 0...1;
- Relation-Kategorie als vorher aufgeloester Value;
- Entfernung/Annaeherung;
- aktiver Layer als ID;
- Impulsstaerke.

Moegliche Ziele sind Makros oder dedizierte Modulationsquellen. Die konkrete
Zuordnung ist Klang- und Spielgefuehlentscheidung durch Stephan. Sie ist
nicht Teil des Synth-Fundaments.

## 12. Technische Optionen

| Option | Vorteil | Risiko | Empfehlung |
|---|---|---|---|
| Eigener Swift/Accelerate-DSP-Kern | volle Kontrolle, offline testbar, keine neue Lizenz | mehr Entwicklungsarbeit | erste Wahl |
| AudioKit/Soundpipe-Abhaengigkeit | schneller Zugriff auf viele DSP-Bloecke | Dependency-, API-, Lizenz- und Integrationsrisiko | nur nach Spike/Entscheid |
| Audio-Unit-Extension als Kern | Plugin-Wiederverwendung moeglich | hoher Packaging-/Host-Aufwand | nicht fuer Synth V1 |
| Nur Apple Factory Audio Units | schneller Ausbau | begrenzte Klangidentitaet und Parametrisierung | Legacy-/Fallback-Pfad |
| Convolution-Hall | reale Raumimpulse, reproduzierbar | IR-Assets, Speicher, weniger morphbar | spaetere Zusatzoption |
| Algorithmischer FDN-Hall | lange modulierbare Raeume, Freeze, geringe Assets | DSP-Tuning erforderlich | DeepSpace V1 |

## 13. Test- und Messstrategie

### 13.1 Reine DSP-Tests

- gleiche Events + gleicher Seed + gleiches Preset ergeben identische
  Samplefolgen innerhalb definierter Float-Toleranz;
- Oszillator-Pitch, Phase und Bandlimit-Auswahl;
- ADSR-/LFO-Zeitverhalten bei 44,1 und 48 kHz;
- Filterstabilitaet ueber den gesamten Parameterbereich;
- Modulationsmatrix-Clamping und Routenzahl;
- Voice-Stealing und Release;
- Delay-Zeit, Feedback, Freeze und Tail-Ende;
- Reverb-Stabilitaet, endliche Samples und Energiekontrolle;
- Preset-Roundtrip, striktes Decoding und Migration.

### 13.2 Offline-Audio-Golden-Metriken

Keine fragilen kompletten WAV-Bitvergleiche als einziges Gate. Pro
Referenzrender werden robuste Messwerte gespeichert:

- Peak und RMS;
- DC-Offset;
- spektraler Schwerpunkt in Zeitfenstern;
- Tail-Energie und ungefaehre Decay-Zeit;
- Stereo-Korrelation;
- Anzahl nicht-endlicher Samples;
- Stille nach All-Off plus definierter maximaler Tail-Zeit.

Kurze Referenzdateien duerfen nur mit klarer Lizenz und bewusstem
Review-Update eingecheckt werden.

### 13.3 Host-/Integrationstests

- bestehende CH0-CH3-On/Off-Symmetrie;
- Panic/All-Off unter Last;
- Parameterupdate vor/nach Note-On;
- Presetwechsel mit klingenden Stimmen;
- Legacy-/Neuer-Engine-Umschaltung;
- interner Synth und MIDI bleiben unabhaengig;
- Explore, Bundle-HarmonyWeb und externe Map.

### 13.4 Performance

Erster Messstandard:

- 44,1 und 48 kHz;
- Buffer 128 und 256 Frames;
- alle vier Kanaele aktiv;
- realistische 32 logische Stimmen plus definierter Worst Case;
- p95-Renderzeit unter 50 Prozent der Buffer-Deadline;
- kein einzelner Rendercallback ueber 80 Prozent im freigegebenen
  Stresstest;
- keine Allokation und kein Lock im Callback;
- Degradationsstrategie fuer hohe Last: zuerst Unison-/Qualitaetsstufe,
  niemals Note-Off/Panic verlieren.

Das konkrete Referenz-Mac-Modell und die finale maximale Polyphonie werden
vor dem Performance-Gate von Stephan festgelegt.

## 14. Umsetzungsslices

Die Slices sind klein zu halten. Ein Slice mit Realtime-, Audio-Graph- oder
On/Off-Aenderung braucht Deep Review.

### Audio Milestone A0 - Planung

| Slice | Inhalt | Gate |
|---|---|---|
| **SYNTH-00** | Bestandsanalyse, Zielbild, Architektur, Slices und offene Entscheidungen | dieses Dokument fachlich/technisch reviewed; kein Produktcode |

### Audio Milestone A1 - Messbares Fundament

| Slice | Inhalt | Gate |
|---|---|---|
| **S-01** — **erledigt (Runde 045)** | Offline-Render-Harness und Audio-Metriken fuer den bestehenden Synth | reproduzierbare Renderfolge; keine Klangveraenderung |

**S-01-Ergebnis (Runde 045):** `Tests/HarmonyEngine3DTests/Support/OfflineSynthHarness.swift`
treibt den echten `SynthNode`-`AVAudioSourceNode`-Rendercallback ueber
`AVAudioEngine.enableManualRenderingMode(.offline, …)` — kein Mock, keine
DSP-Duplikation, keine Audio-Hardware. `SynthNode.sourceNode` haengt dabei
bewusst nur an `engine.mainMixerNode`, ohne den Fader-/Delay-/Reverb-/
Kompressor-Graph aus `AudioEngine.swift`, damit die Synth-Baseline nicht
durch `AVAudioUnit*`-Presets verfaelscht wird. Events (`noteOn`/`noteOff`/
`allNotesOff`/`paramUpdate`) werden frame-genau an `renderOffline`-
Chunkgrenzen eingespeist — `SynthNode`s Rendercallback verarbeitet die
`NoteEventQueue` vollstaendig FIFO vor dem ersten DSP-Sample eines
Callbacks, ein Chunk-Split an `atFrame` ist daher frame-exakt. Der
Testtreiber ist bewusst single-threaded (ein Producer-Thread), das erfuellt
den SPSC-Vertrag von `NoteEventQueue`, ist aber KEIN Test des echten
Multi-Producer-Falls (SceneKit-/GameController-/Main-Thread ueber
`AudioEngine.commandQueue`, siehe F-02).

`Tests/HarmonyEngine3DTests/Support/OfflineSynthMetrics.swift` berechnet
Peak, RMS, DC-Offset, Anzahl nicht-endlicher Samples, Gesamt-/Tail-Energie,
ersten/letzten Frame oberhalb einer dokumentierten Stille-Schwelle
(1e-4), Stereo-Korrelation (Pearson, `nil` als dokumentierte Ersatzmetrik
bei fehlender Kanalvarianz) und spektralen Schwerpunkt (Hann-gefensterte
`vDSP.DiscreteFourierTransform`, `nil` bei zu kurzem Restsignal).

`Tests/HarmonyEngine3DTests/OfflineSynthBaselineTests.swift` deckt Scope C
vollstaendig ab: Determinismus (bitgenau identische Samples bei
wiederholtem Render), Note-On liefert endliche/hoerbare Ausgabe, Note-
Off/All-Off fuehrt nach Release + Sicherheitsfenster zu Stille, 44,1 und
48 kHz, Unison/Stereo-Spread erzeugt hoerbar unterschiedliche L/R-Kanaele,
ein Legacy-Referenzrender (C4/Velocity 100, Default-`SynthParams`, 300 ms
gehalten + Release) mit empirisch gemessenen, mit dieser Codebasis noch
nie zuvor genutzten Accelerate/vDSP-Metriken und begruendeten Toleranzen
(peakAbsolute ≈0.105, rms ≈0.035, spektraler Schwerpunkt ≈305 Hz — 5-10 %
relative Toleranz je Metrik), sowie vier Wellenformen an ADSR-/Filter-/
Unison-Extremwerten ohne NaN/Infinity. 8 neue Tests, 369/369 Gesamttests
gruen. Keine Produktcode-Aenderung unter `Sources/` oder `Package.swift` —
reiner Testtarget-Zuwachs.
| **S-02a** — **erledigt (Runde 046)** | `HarmonyAudioCore`-Target mit Value-Modellen, fester Render-API und Legacy-Oszillator/ADSR | Core ohne AVFAudio/SwiftUI/SceneKit; Unit Tests |
| **S-02b** — **erledigt (Runde 047)** | bestehende SynthVoice-Funktion behavior-nah ueber den Core hosten | **Deep Review (Realtime-Vertrag).** Der Rendercallback wechselt seine DSP-Quelle bei laufendem Betrieb — genau der in Abschnitt 5 verbotene Fall eines unkontrollierten Wechsels, wenn er nicht sauber gegated wird. A/B-Metriken innerhalb festgelegter Toleranzen; Legacy-Fallback; kein Graphwechsel waehrend klingender Noten ohne kontrolliertes Crossfade/All-Off |
| **S-03** — **erledigt (Runde 048)** | versioniertes Presetmodell, Validator, Factory-/User-Store und Legacy-Migration | Roundtrip, atomisches Save, keine Default-Aenderung |

**S-02a-Ergebnis (Runde 046):** neues SwiftPM-Target `HarmonyAudioCore`
(`Sources/HarmonyAudioCore/`) plus `HarmonyAudioCoreTests`
(`Tests/HarmonyAudioCoreTests/`), noch nicht von `HarmonyEngine3D`
verdrahtet (per Grep verifiziert — kein `HarmonyAudioCore`-Verweis im
Produktcode). Vier Dateien:

- `AudioCoreWaveform.swift`: identische Fallmenge zu `Waveform`.
- `AudioCoreADSRStage.swift`: identische Fallmenge zu `ADSRStage`.
- `AudioCoreSynthParameters.swift`: Value-Modell mit denselben Feldern und
  Defaults wie `SynthParams`. `maxVoices`/`unisonVoices`/`unisonDetune`/
  `unisonSpread` sind Teil des Modells, werden aber von `AudioCoreVoice`
  selbst nicht ausgewertet — Pool-/Unison-Verteilung bleibt S-02b.
- `AudioCoreVoice.swift`: einzelne Stimme, behavior-nahe Portierung von
  `SynthVoice` (Frequenzformel, alle vier Wellenformen inkl. PolyBLEP/2.
  Harmonische/Amp-Skalierungen, ADSR-Raten-Formel, Biquad-Tiefpass nach
  Bristow-Johnson inkl. Bypass-Fall, Constant-Power-Pan) — identische
  Formeln, kein Copy-Paste-Import, weil der Core `HarmonyEngine3D` nicht
  importieren darf. `render(intoL:intoR:frameCount:)` schreibt additiv in
  vom Aufrufer bereitgestellte `UnsafeMutablePointer<Float>`-Puffer, keine
  Heap-Allokation/Lock/Dispatch/Task/Actor/Print im Renderpfad.

Kein Voice-Pool, kein Voice-Stealing, keine Unison-Verteilung ueber mehrere
Stimmen — bewusst auf eine einzelne `AudioCoreVoice` beschraenkt (Handoff
erlaubte diese Verengung ausdruecklich). Das bleibt S-02b zusammen mit der
eigentlichen Umschaltung von `SynthNode`/`VoicePool` auf den Core.

11 neue Tests (`HarmonyAudioCoreTests`) decken Defaults, Frequenzformel
(inkl. Detune-Verhaeltnis), ADSR-Stage-Timing bei 44.1/48 kHz (Attack-/
Decay-Sample-Zaehlung, ±1 % Toleranz), NoteOff→Release→Idle bei beiden
Sampleraten, alle vier Wellenformen endlich, Filter-Bypass-Identitaet,
Filter-Extremwerte finite/stabil, Stereo-Pan Center/Links/Rechts (ueber
tatsaechliche Render-RMS-Verhaeltnisse, nicht interne Felder), Determinismus
und einen Baseline-Vergleich des Default-C4-Renders gegen die S-01-Legacy-
Referenzmetriken (peakAbsolute/rms, ±10 % Toleranz — engerer Vergleich als
S-01 selbst moeglich, weil dieselbe Grundformel ohne Mixer/Unison misst).
380/380 Gesamttests gruen (369 bestehend + 11 neu). Strict-Concurrency-
Build: identisches Warnungsprofil zu Runde 041/045 (480 Warnungen,
dieselben 11 Bestandsdateien, keine `HarmonyAudioCore`-Datei betroffen).
Clean-HEAD-Build/-Test gruen (`Package.swift` und neues Target geaendert).

**S-02b-Ergebnis (Runde 047):** `HarmonyEngine3D` haengt jetzt von
`HarmonyAudioCore` ab. `SynthNode.VoicePool` (`Sources/HarmonyEngine3D/
SynthNode.swift`) rendert seine Stimmen ueber `[AudioCoreVoice]` statt
`[SynthVoice]` — die alte `SynthVoice.swift` (duplizierte DSP-Formel,
`ADSRStage`-Enum) wurde vollstaendig entfernt, nachdem eine Grep-Pruefung
bestaetigt hat, dass kein anderer Ort im Repo diese Typen referenziert.

- **Mapping:** `Sources/HarmonyEngine3D/AudioCoreMapping.swift` uebersetzt
  `Waveform -> AudioCoreWaveform` und `SynthParams -> AudioCoreSynthParameters`
  (alle elf Felder). Lebt bewusst im App-Target — der Core darf
  `HarmonyEngine3D` weiterhin nicht importieren.
- **Core-Erweiterung:** `AudioCoreVoice` bekam drei kleine, fachlich
  benannte Ergaenzungen fuer die Pool-Integration: `note` ist jetzt
  read-only public (fuer NoteOff-Matching), `updateLowpassCoefficients(...)`
  uebertraegt neue Biquad-Koeffizienten ohne den Filter-State
  (`filterS1`/`filterS2`) zurueckzusetzen, `applySustainIfInSustain(...)`
  kapselt die Sustain-Live-Update-Bedingung (wirkt nur, wenn `stage ==
  .sustain`) direkt im Core statt im Aufrufer.
- **Voice-Pool-Migration:** `VoicePool.noteOn()`/`noteOff()`/`applyParams()`/
  `render()` in `SynthNode.swift` rufen jetzt `AudioCoreVoice`-Methoden auf.
  Voice-Stealing (aelteste `activationOrder`), Unison-Verteilung
  (Detune-/Pan-Spread pro Stimmen-Index, `gainScale = 1/√n`), Live-Filter
  (sofort auf aktive Stimmen, State bleibt erhalten), Live-Sustain (nur
  Sustain-Stage) und `maxVoices`-Fixierung nach `prepare()` sind unveraendert
  — nur die einzelne Stimmen-Implementierung wurde ausgetauscht.
  `AVAudioSourceNode`-Erzeugung, Buffer-Nulling und Event-FIFO-Verarbeitung
  in der Render-Closure sind unangetastet.
- **Realtime-Vertrag:** `AudioCoreVoice.render()`/`configure()`/
  `triggerRelease()`/`updateLowpassCoefficients()`/`applySustainIfInSustain()`
  alloziieren nicht, sperren nicht, nutzen keine Dispatch-/Task-/Actor-
  Ausfuehrung, keine Dateizugriffe, kein `print` — der Rendercallback bleibt
  ab `prepare()` durchgehend auf dem Core, keine Laufzeitumschaltung
  waehrend klingender Noten (der Callback wird nur einmalig in `prepare()`
  gebaut).
- **A/B-Nachweis:** alle acht `OfflineSynthBaselineTests` (S-01) bleiben
  unveraendert gruen, inklusive des engsten Tests
  (`test_legacyReferenceRender_matchesDocumentedBaselineMetrics`,
  peakAbsolute/rms/spektraler Schwerpunkt innerhalb der bestehenden
  Toleranzen) und des Unison-/Stereo-Tests. Keine Toleranzanpassung noetig.
- **Neue/erweiterte Tests:** `AudioCoreMappingTests` (Waveform- und
  SynthParams-Mapping, alle elf Felder, Defaults-Aequivalenz),
  `LiveParameterUpdateTests` (Live-Filter wirkt sofort ohne Envelope-/
  Voice-Neustart — verifiziert ueber zwei nicht-bypassende Filtereinstellungen,
  da ein Wechsel WEG von Bypass immer stark daempft, unabhaengig von einem
  etwaigen Neustart-Bug; Live-Sustain wirkt nur in der Sustain-Stage und
  nicht rueckwirkend auf eine laufende Decay-Phase). Beide neuen
  Sustain-/Restart-Assertions wurden durch gezielte Bug-Injektion
  (Guard entfernt) gegengeprueft und schlagen dann nachweislich fehl.
- **Core-Schichtgrenzen:** per Grep bestaetigt weiterhin nur `import Darwin`
  in `Sources/HarmonyAudioCore/*.swift` — keine AVFAudio-/SwiftUI-/SceneKit-/
  AppKit-/CoreMIDI-/GameController-/App-Code-Abhaengigkeit.
- 385/385 Gesamttests gruen (380 bestehend + 5 neu). Strict-Concurrency-
  Build: identisches Warnungsprofil zu Runde 041/045/046 (480 Warnungen,
  dieselben 11 Bestandsdateien, keine `HarmonyAudioCore`-Datei betroffen).
  Clean-HEAD-Build/-Test gruen. Manueller App-Start (`swift run
  HarmonyEngine3D`) laeuft ohne Absturz.

**S-03-Ergebnis (Runde 048):** neues, versioniertes Presetmodell in
`Sources/HarmonyEngine3D/AudioPreset/` (App-Target, nicht `HarmonyAudioCore`
— File-/Application-Support-Stores und FX-/Channel-Daten gehoeren dorthin,
siehe Handoff). Reine Daten-/Persistenzinfrastruktur: **noch keine aktive
Preset-Auswahl, kein Runtime-/Default-Wechsel** — per Grep bestaetigt
referenziert kein Produktcode ausserhalb `AudioPreset/` diese neuen Typen.

- **Modell:** `AudioSynthPreset` (schemaVersion, id, name, channelRole,
  optionale author/engineVersion-Metadaten) mit zwei Sektionen:
  `AudioPresetSynthSection` (Waveform/ADSR/Filter/Unison — Feldsemantik
  identisch zu `ChannelFXConfig`, NICHT zu `AudioCoreSynthParameters`
  (Millisekunden-basiert), damit der Roundtrip zu `ChannelFXConfig`
  formelfrei/verlustfrei bleibt) und `AudioPresetFXSection` (Delay-Taps,
  Reverb, Channel-Volume, Pan). `Waveform` (`SynthParams.swift`) bekam
  dafuer eine zusaetzliche `Codable`-Konformanz (rein additiv, kein
  Verhaltensunterschied).
- **Validator:** `AudioPresetValidator`, im Stil von `HarmonyMapValidator`
  (`Issue` mit severity/code/objectPath/message). Errors: nicht unterstuetzte
  schemaVersion, leere id/name, nicht-endliche Zahlen, unisonVoices/
  maxVoices < 1. Warnings: Werte ausserhalb der heute in `AudioEngine`
  tatsaechlich geclampten Bereiche (z. B. Delay-Zeit 0.001…2.0s,
  Delay-Feedback 0…1 — direkt aus `AudioEngine.applyEffectConfigX`
  uebernommen, nicht neu erfunden) sowie ein unbekannter `reverbPreset`
  (AudioEngine faellt dort bereits sicher auf `.largeHall` zurueck).
- **Factory:** `AudioPresetFactory.legacyPresets` — vier Presets
  (`legacy.chord`/`legacy.bass`/`legacy.melody`/`legacy.chordTone`,
  stabile IDs) deterministisch aus `ChannelFXConfig.chordDefaults` etc.
  erzeugt, alle validator-akzeptabel.
- **User-Store:** `AudioPresetStore`, im Stil von `RuntimeMapImportStore`
  (V-01): Application-Support-Pfad
  `~/Library/Application Support/HarmonyEngine3D/AudioPresets`, atomisches
  Schreiben (`Data.write(options: .atomic)`), `save`/`load`/`list` mit
  `directory:`-Injection fuer Tests, keine Security-Scoped-Bookmarks, keine
  UI.
- **Legacy-Migration:** `ChannelFXConfig.audioSynthPreset(...)` und
  `AudioSynthPreset.channelFXConfig` sind zueinander inverse, 1:1-
  feldweise Funktionen (kein Formel-Rundungsrisiko). Zusaetzlich
  `AudioPresetSynthSection.audioCoreSynthParameters`: eine reine, nur
  lesende Ableitung nach `AudioCoreSynthParameters` mit EXAKT derselben
  Formel wie `AudioEngine.synthParams(from:)` (quadratische Attack-Kurve,
  lineare Decay-/Release-Umrechnung) — bewusst dupliziert statt aus
  `AudioEngine.swift` geteilt, um diesen Slice ohne jede Audio-Graph-
  Beruehrung zu halten (Nicht-Scope S-03: kein Audio-Graph-Umbau).
- 23 neue Tests (Codable-Roundtrip inkl. striktem Scheitern bei falsch
  typisierten vorhandenen Feldern, Validator-Issue-Sammlung/Error-vs-
  Warning-Blockierung, Factory-Stabilitaet, Legacy-Migration-Roundtrip
  aller vier Kanal-Defaults, `AudioCoreSynthParameters`-Formelgleichheit,
  Store-Atomaritaet/-Determinismus, sowie ein expliziter Nachweis, dass
  Factory-/Store-/Validator-Aufrufe keine `he3d.`-UserDefaults-Keys
  veraendern). 408/408 Gesamttests gruen (385 bestehend + 23 neu).
  Strict-Concurrency-Build: dieselben 11 Bestandsdateien wie in
  Runde 041/045/046/047, inhaltlich identisches Warnungsprofil pro Datei
  (Rohzaehler schwankt zwischen separaten Clean-Builds durch doppelte
  Diagnose-Emission — verifiziert per Diff der eindeutigen Warnungstexte
  je Datei, keine neue Datei/Kategorie betroffen). Clean-HEAD-Build/-Test
  gruen (Preset-Produktdateien neu). Manueller App-Start
  (`swift run HarmonyEngine3D`) laeuft ohne Absturz.

### Audio Milestone A2 - Atmospheric Voice

| Slice | Inhalt | Gate |
|---|---|---|
| **S-04a** — **erledigt (Runde 049)** | Wavetable-Bank und bandlimitierter Morph-Oszillator A | Pitch-/Alias-/Morph-Tests |
| **S-04b** — **erledigt (Runde 051)** | Source B, Texture Source C und sichere Mixmodi | feste CPU-/Voice-Grenzen |
| **S-05a** — **erledigt (Runde 052)** | Amp-/Mod-Huelle und drei LFOs | samplegenaue Zeit-/Reset-Tests |
| **S-05b** — **erledigt (Runde 053)** | feste Modulationsmatrix und vier Makros | 16-Routen-Grenze, Glattung, Determinismus |
| **S-06** — **erledigt (Runde 054)** | State-Variable-Filter, Send-Highpass und Waveshaper | Stabilitaets-/Pegeltests |
| **W-01** — **erledigt (Runde 066)** | Atmospheric Voice zusammensetzen: alle Bausteine zu einem Signalweg verbinden | sieben Modulationsziele nachweisbar, allokationsfrei per SIL, CPU gemessen |

**W-01-Ergebnis (Runde 066):** erster Slice der von Stephan am 2026-08-02
freigegebenen Verdrahtungskette (W-01 bis W-05). Zwei neue Dateien in
`Sources/HarmonyAudioCore/`, keine bestehende Core-Datei geaendert:

- `AudioCoreAtmosphericVoiceParameters.swift`: vollstaendiger Patch —
  Quellen/Mix, Filter/Shaping, Amp-/Mod-Huellenprofile, drei LFO-Profile
  samt Seeds, Modulationsmatrix, die vier Performance-Makros, Space-Send und
  die Glaettungszeit. ALLE Klemmgrenzen liegen ausschliesslich im
  Initialisierer; die verschachtelten Huellen-/LFO-Parameter werden dort
  ueber ihre eigenen Initialisierer neu gebaut, weil auch sie
  `public var`-Felder haben (S-08a-01-Lehre). Bewusste Ausnahme mit
  Begruendung: `modulationMatrix` wird nicht neu gebaut — die Matrix ist nach
  ihrer Konstruktion unveraenderlich (`public let routes`), auf 16 Routen
  gekuerzt, mit geklemmten Amounts gebaut, und `evaluate(sources:)` klemmt
  jedes Ergebnis erneut auf `[-1, 1]`. Ein Neubau waere reine Redundanz und
  wuerde eine Array-Allokation in `setParameters(_:)` erzeugen.
- `AudioCoreAtmosphericVoice.swift`: Signalweg Quelle A / Quelle B / Textur
  -> `AudioCoreMixer` -> `AudioCoreStateVariableFilter` ->
  `AudioCoreWaveshaper` -> Amp-Huelle -> Constant-Power-Pan -> additive
  L/R-Akkumulation. API sinngemaess wie die Legacy-`AudioCoreVoice`
  (`configure(note:velocity:sampleRate:parameters:activationOrder:
  detuneCents:panPosition:gainScale:)`, `triggerRelease()`, `isActive`,
  `note`, `activationOrder`, `stage`, additives
  `render(intoL:intoR:frameCount:)`), damit `VoicePool` in W-03 nicht
  umgebaut werden muss.

Modulationsrate: feste interne Kontrollrate von 32 Samples (1.500 Hz bei
48 kHz), danach Glaettung aller sieben Ziele auf Audiorate ueber
`AudioCoreParameterSmoother`. Die LFOs und die Mod-Huelle laufen selbst auf
Kontrollrate (mit `sampleRate / 32` als Sample Rate gebaut, damit Frequenzen
und Millisekunden korrekt bleiben); die Amp-Huelle bleibt auf Audiorate,
weil sie die Amplitude direkt formt. Der Filter-Cutoff wird auf Audiorate
geglaettet, aber nur auf Kontrollrate angewendet, weil
`AudioCoreStateVariableFilter.setParameters(_:)` `powf` und `tanf` rechnet.
Die Kontrollperiode haengt an einem stimmeigenen Zaehler und NICHT an
`frameCount` — derselbe Render liefert in 7er-, 256er- oder Ein-Stueck-
Bloecken bit-identische Samples.

Ersatz fuer die bewusst nicht uebernommene
`updateLowpassCoefficients(b0:b1:b2:a1:a2:)`: der Aufrufer uebergibt keine
Biquad-Koeffizienten mehr, sondern per `setParameters(_:)` einen Cutoff-/
Resonanzwert. `setParameters(_:)` setzt bewusst keine Glaetter zurueck und
startet keine Huellkurve neu — eine Live-Parameteraenderung gleitet.

Die sieben Modulationsziele und ihre Bindung in der Stimme:

| Ziel | Wirkung |
|---|---|
| `morphPosition` | Morphposition beider Morph-Oszillatoren |
| `textureLevel` | Pegel der Texturquelle, ausserhalb des Mixers addiert |
| `filterCutoff` | SVF-Cutoff, Koeffizienten pro Kontrollschritt neu |
| `mixDepth` | modusabhaengig: Pegel Quelle B (`.linear`), Ringmodulationstiefe, Phasenmodulationstiefe |
| `ampEnvelopeDepth` | Skalierung der Amp-Huelle auf die Ausgangsamplitude |
| `modEnvelopeDepth` | Skalierung der Mod-Huelle, bevor sie als Quelle in die Matrix geht |
| `spaceSend` | nur ueber `spaceSendLevel` nach aussen sichtbar, in der Stimme NICHT angewendet (W-03) |

Die Textur wird bewusst ausserhalb von `AudioCoreMixer` addiert:
`.ringModulation` und `.softPhaseModulation` ignorieren `c` per Vertrag, ein
Ziel mit Wirkung nur im Default-Mixmodus waere genau die Fehlerklasse, die
dieser Slice ausschliessen soll.

Realtime-Vertrag per SIL belegt (`swiftc -O -wmo -emit-sil`): `render`,
`configure`, `setParameters`, `reset`, `prepare` und `init` enthalten null
Allokations-Intrinsics, inklusive der strengeren Suche nach
`_ArrayBuffer._consumeAndCreateNew`. Kein LFO-Array und keine
Scratch-Puffer noetig — die drei LFO-Slots sind drei benannte Felder wie in
`AudioCoreModulationSourceValues`. Einzige Heap-Puffer sind die beiden
Wavetables; sie werden im Renderpfad nur gelesen und sind bewusst
Konstruktions- statt Note-On-Parameter.

CPU-Kosten einer Stimme (MacBookPro18,1 / Apple M1 Pro, 48 kHz, offline,
single-threaded, 512-Sample-Bloecke): Median 59,3 ns/Sample = 351x Echtzeit,
p99 66,3 ns/Sample = 314x, schlechtester Einzelblock 132,4 ns/Sample = 157x.
Hochrechnung auf 16 Stimmen: 21,9x / 19,6x / 9,8x. Bezugspunkt
`AudioCoreDeepSpaceFDNTail` bei rund 285x — der Hall bleibt gegenueber den
Stimmen praktisch kostenlos.

Default-Patch: ruhiger, nicht-harscher Startpunkt, ausdruecklich KEINE Art
Direction (moderate Morphposition 0,35, wenig Textur 0,06, offener Filter
0,85 mit Resonanz 0,05, sanfte Huelle 12/300/0,75/400 ms, zwei sehr langsame
LFO-Routen mit Amount 0,12 bzw. 0,08). Die Klanggestaltung macht Stephan
spaeter am Controller (W-05).


**S-04a-Ergebnis (Runde 049):** erste Atmospheric-Voice-DSP-Komponente
(Source A) in `Sources/HarmonyAudioCore/`, drei neue Dateien, keine
bestehende Core-Datei geaendert:

- `AudioCoreWavetable.swift`: `AudioCoreWavetableMipLevel` (`maxHarmonic`,
  `samples`) und `AudioCoreWavetable` (`id`, `tableLength`, absteigend
  sortierte `mipLevels`) als reine Value-Speicher.
  `mipLevelIndex(frequencyHz:sampleRate:)` waehlt die am wenigsten
  bandlimitierte Stufe, deren `maxHarmonic * frequencyHz` die
  Nyquist-Grenze (`sampleRate / 2`) noch einhaelt — rein technische
  Aliasing-Vermeidung. `sample(phase:mipLevelIndex:)` liest linear
  interpoliert und wrapped die Phase defensiv auf `[0, 1)`.
- `AudioCoreWavetableBank.swift`: kleine, rein prozedurale Factory-Bank —
  additive Sinus-Synthese ohne Fremdassets/-Presets/-Samples,
  deterministisch. Tabellenlaenge 2048 (power-of-two), sieben Mip-Stufen
  je Spektrum (`harmonicCaps = [64, 32, 16, 8, 4, 2, 1]`), jede Stufe nach
  Summation auf Peak 1.0 normiert:
  - `warmOdd` (`factory.warmOdd`): nur ungeradzahlige Harmonische,
    1/n^1.5-Amplitude — weich, rund.
  - `brightFull` (`factory.brightFull`): alle Harmonischen, 1/n-Amplitude
    (klassische Saegezahn-Reihe) — hell, obertonreich.
  Beide Spektren verankern alle Harmonischen bei Phase 0 auf denselben
  Tabellenindex (keine Zufallsphasen), was das Morphing zwischen ihnen
  phasenkonsistent macht.
- `AudioCoreMorphOscillator.swift`: reiner Oszillatorzustand, liest
  phasenkonsistent aus zwei `AudioCoreWavetable`-Instanzen und morpht
  linear (`output = A*(1-morph) + B*morph`). Kennt weder MIDI noch
  Harmonie — Frequenz nur in Hz. Parametergrenzen: `sampleRate` im Init
  auf `>0` erzwungen, `frequencyHz` auf `0...Nyquist` geklemmt
  (nicht-endlich/negativ → `0`), `morph` auf `0...1`. `setFrequency()`
  waehlt die Mip-Indizes beider Tabellen sofort neu. `nextSample()`/
  `render(into:frameCount:)` alloziieren nicht, sperren nicht, nutzen
  keine Dispatch-/Task-/Actor-Ausfuehrung, kein `print`.

Noch NICHT in `AudioCoreVoice`/`SynthNode` verwendet und nicht der
produktive Renderpfad (Nicht-Scope S-04a, per Grep bestaetigt: kein
Produktcode ausserhalb `Sources/HarmonyAudioCore/` bzw.
`Tests/HarmonyAudioCoreTests/` referenziert die neuen Typen).

9 neue Tests (`AudioCoreWavetableBankTests`, 4; `AudioCoreMorphOscillatorTests`,
5): stabile IDs/power-of-two Tabellenlaenge/mehrere absteigend sortierte
Mip-Stufen; Bandlimitierung per unabhaengiger diskreter Sinus-Projektion
(Harmonische oberhalb cap=8 praktisch ohne Energie, Grundton deutlich
messbar); cap=1 entspricht in beiden Spektren einer reinen, auf Peak 1.0
normierten Sinuswelle; `warmOdd` cap=8 stimmt mit einer unabhaengig
berechneten Summe der ungeraden Harmonischen 1/3/5/7 ueberein; Pitch-
Genauigkeit bei 110/440/1760 Hz per Zero-Crossing-Periodenmessung gegen
eine dedizierte reine Sinustabelle (bewusst nicht gegen die
mehrharmonischen Factory-Spektren, siehe Testfile-Kommentar); Morph
0/0.5/1 entspricht Spektrum A/Mittelwert/Spektrum B; Mip-Auswahl wechselt
bei 110→440→1760 Hz nachweislich in eine staerker bandlimitierte Stufe
innerhalb der Nyquist-Grenze; Extremparameter liefern durchgehend endliche
Samples; identische Parameter liefern bitgenau identische Samplefolge.

417/417 Gesamttests gruen (408 bestehend + 9 neu). Strict-Concurrency-
Build: dieselben 11 Bestandsdateien wie in den Vorrunden, keine der drei
neuen `HarmonyAudioCore`-Dateien in der Warnliste. Clean-HEAD-Build/-Test
gruen. `git diff --check` gruen. Manueller App-Start (`swift run
HarmonyEngine3D`) laeuft mehrere Sekunden ohne Absturz.

**S-04a-fix-Ergebnis (Runde 050):** Supervisor-Review hat einen konkreten
Randfall in `AudioCoreWavetable.sample(phase:mipLevelIndex:)` gefunden:
eine nicht-endliche `phase` (`.nan`/`.infinity`) blieb nach
`truncatingRemainder(dividingBy: 1.0)` selbst nicht-endlich (IEEE 754: Rest
mit NaN/Infinity ist NaN), wodurch die anschliessende `Double -> Int`-
Konvertierung fatal getrappt haette (isoliert verifiziert:
`Int(Double.nan)` → `Fatal error: Double value cannot be converted to Int
because it is either infinite or NaN`). Derselbe Randfall existierte in
`AudioCoreMorphOscillator.resetPhase(to:)`, dessen ungeprueft gesetzte
Phase der naechste `nextSample()`-Aufruf an `sample(phase:)`
weitergereicht haette.

Fix: beide Funktionen bilden eine nicht-endliche Eingabe VOR dem
`truncatingRemainder`-Wrapping auf `0` ab (`phase.isFinite ? phase : 0`),
statt eine gemeinsame Abstraktion einzufuehren — zwei Zeilen pro
Aufrufstelle, lokal in der jeweiligen Datei, keine neue Indirektion. 4
neue Regressionstests (`AudioCoreWavetableBankTests`: `sample(phase: .nan)`/
`sample(phase: .infinity)`; `AudioCoreMorphOscillatorTests`:
`resetPhase(to: .nan)`/`resetPhase(to: .infinity)` gefolgt von
`nextSample()`) fuehren genau diesen Pfad aus — vor dem Fix waere der
Testprozess an dieser Stelle fatal abgestuerzt statt fehlzuschlagen.

421/421 Gesamttests gruen (417 bestehend + 4 neu). Strict-Concurrency-
Build: dieselben 11 Bestandsdateien, keine neue Warnkategorie.
Clean-HEAD-Build/-Test gruen. `git diff --check` gruen. Keine Runtime-/
Default-/UI-Verdrahtung (per Grep unveraendert bestaetigt). Manueller
App-Start laeuft mehrere Sekunden ohne Absturz.

**S-04b-Ergebnis (Runde 051):** Source B, Texture Source C und sichere
Mixmodi in `Sources/HarmonyAudioCore/`, drei neue Dateien, keine
bestehende Core-Datei geaendert:

- `AudioCoreSourceB.swift`: zweite, unabhaengige Morph-Oszillator-Quelle.
  Wrappt einen eigenen `AudioCoreMorphOscillator` (Scope-Vorgabe: darf
  wiederverwendet werden), ergaenzt Transposition in Halbtoenen
  (`-24...24`), Feinstimmung in Cent (`-100...100`) als reine
  Hz-Skalierung (`effektiveFrequenz = base * 2^((semitones + cents/100) /
  12)`) und eigene, von Source A unabhaengige Phase/Reset-Logik (eigene
  gekapselte Oszillatorinstanz). Kennt weder MIDI noch Harmonie.
- `AudioCoreTextureSource.swift`: deterministische gefaerbte Rauschquelle,
  kein Sampleimport/Dateizugriff/Granular. Expliziter xorshift64-RNG-
  Zustand, Seed `0` faellt auf einen festen Ersatzwert zurueck (sonst
  degenerierter Fixpunkt). Ein One-Pole-Tiefpass mit
  `brightness`-gesteuertem Koeffizienten (`0.001 + brightness * 0.98`,
  immer in `(0, 1)`) liefert stabile, finite Farbfilterung ohne DC-/
  Feedback-Explosion; `level` (`0...1`) steuert den Ausgangspegel.
  `resetState(to:)` setzt RNG- und Filterzustand gemeinsam zurueck.
- `AudioCoreMixer.swift`: feste, typisierte Mixmodi (`AudioCoreMixMode`)
  als reine, zustandslose Funktion ueber drei bereits gerenderte Samples —
  bewusst kein Besitzer eigener Oszillatorinstanzen, dadurch bleiben
  Source A, Source B und Texture C entkoppelt und jeder Mixmodus isoliert
  testbar. `.linear` (geklemmte Gains A/B/C), `.ringModulation`
  (A x B, Tiefenregler ueberblendet mit trockenem A). Fuer die geforderte
  "sanfte Phasen- oder Frequenzmodulation" wurde bewusst eine reduzierte
  Variante gewaehlt (`.softPhaseModulation`): eine echte Audio-Rate-
  Phasenmodulation muesste in die interne Phase von Source A/B eingreifen
  und wuerde deren Kapselung aufloesen — im Kern bereits ein kleiner
  Patchgraph, den Scope D explizit ausschliesst. Stattdessen eine
  begrenzte, phasenverzerrungs-aehnliche Nachbearbeitung auf den
  Samplewerten (`a + phaseModDepth * sin(pi * b)`), mathematisch
  bandbegrenzt durch `sin()`. Jeder Mixmodus-Output wird zusaetzlich
  defensiv auf `[-1, 1]` geklemmt, nicht-endliche Eingaben werden vor der
  Berechnung als `0` behandelt.

Noch NICHT in `AudioCoreVoice`/`SynthNode` verwendet und nicht der
produktive Renderpfad (Nicht-Scope S-04b, per Grep bestaetigt: kein
Produktcode ausserhalb `Sources/HarmonyAudioCore/` bzw.
`Tests/HarmonyAudioCoreTests/` referenziert die neuen Typen).

25 neue Tests (`AudioCoreSourceBTests`, 9; `AudioCoreTextureSourceTests`,
6; `AudioCoreMixerTests`, 10): Transposition/Cent-Frequenzfaktoren inkl.
Oktav-Shift und Cent-Aequivalenz zu einem Halbton, Clamping, eigene/
unabhaengige Phase, Determinismus und Extremparameter finite fuer Source
B; identischer Seed liefert identische Samplefolge, unterschiedliche
Seeds liefern unterschiedliche Folgen, `resetState` reproduziert eine
frische Instanz, Seed `0` entartet nicht, Extremparameter finite und im
Pegelrahmen `[-1, 1]`, `level=0` erzeugt Stille fuer Texture C;
deterministischer linearer Mix mit geklemmten Gains, volle/keine
Ringmodulationstiefe, Ringmodulation und Phasenmodulation bei
Extremeingaben finite/begrenzt fuer den Mixer.

446/446 Gesamttests gruen (421 bestehend + 25 neu). Normaler Build gruen.
Strict-Concurrency-Build gruen, keine neue Warnkategorie, keine der drei
neuen `HarmonyAudioCore`-Dateien in der Warnliste. Clean-HEAD-Build/-Test
gruen (446/446). `git diff --check` gruen. Manueller App-Start (`swift run
HarmonyEngine3D`) laeuft mehrere Sekunden ohne Absturz. `bassHoldMode`,
aktiver Synth-Klang, `AudioEngine`-Graph, MIDI und `AudioOutput`-Vertrag
nicht beruehrt.

**S-05a-Ergebnis (Runde 052):** Amp-/Mod-Huelle und drei LFOs in
`Sources/HarmonyAudioCore/`, fuenf neue Dateien, keine bestehende Core-Datei
geaendert:

- `AudioCoreEnvelopeParameters.swift`/`AudioCoreEnvelope.swift`: ein
  eigenstaendiger ADSR-Huellkurven-Baustein, bewusst getrennt von den
  ADSR-Feldern in `AudioCoreSynthParameters` (dort Teil des
  Voice-Snapshots, hier ein wiederverwendbarer Baustein ohne Bindung an
  `AudioCoreVoice`). Nutzt den bestehenden `AudioCoreADSRStage`-Automaten
  (S-02a) weiter statt einen zweiten Stage-Enum einzufuehren — die
  Fallmenge passt unveraendert. Amp- und Mod-Huelle sind derselbe Typ mit
  getrennten Instanzen/Parameterprofilen (Plan erlaubt diese Verengung
  ausdruecklich). `noteOn(sampleRate:)` berechnet Attack-/Decay-/
  Release-Raten deterministisch aus Parametern + Samplerate neu
  (identisches Prinzip zu `AudioCoreVoice.configure()`), `noteOff()`
  startet aus Attack/Decay/Sustain eine kontrollierte Release-Phase vom
  aktuellen Wert aus, `reset()` setzt auf idle/0 zurueck und reproduziert
  danach denselben Verlauf wie eine frische Instanz.
- `AudioCoreLFOShape.swift`/`AudioCoreLFOParameters.swift`/
  `AudioCoreLFO.swift`: LFO-Baustein mit vier Formen (Sine, Triangle,
  Sample-and-Hold, geglaetteter Random). Frequenz ist bewusst auf
  `0...200 Hz` begrenzt (`AudioCoreLFOParameters.maxFrequencyHz`) statt
  frei bis Nyquist — haelt den LFO klar von einem Audio-Rate-Oszillator
  getrennt (Tempo-Sync/Audio-Rate-Modulation bleiben spaetere
  Ausbaustufen) und garantiert, dass die einfache
  Ein-Schritt-Phasenfortschreibung (identisches Muster zu
  `AudioCoreMorphOscillator`) bei jeder erlaubten Frequenz/Samplerate-
  Kombination korrekt bleibt. Sample-and-Hold und geglaetteter Random
  ziehen ihre Zufallswerte aus einem expliziten xorshift64-Zustand
  (identisches Muster zu `AudioCoreTextureSource`) — neuer Zufallswert
  pro abgeschlossenem LFO-Zyklus, geglaetteter Random naehert sich diesem
  Zielwert per One-Pole-Filter mit festem, immer im offenen Intervall
  `(0, 1)` liegendem Koeffizienten an (kein instabiles Feedback).
  `resetPhase(to:)` (Key-Sync) und `resetRandomState(to:)` sind getrennte
  Reset-Operationen, identisches Muster zu
  `AudioCoreMorphOscillator.resetPhase`/`AudioCoreTextureSource.resetState`.

Per-Voice vs. global (Scope C): beide Bausteine sind reine Value-Typen ohne
Singleton und ohne globalen mutable State — dieselbe Instanz kann sowohl
pro Stimme als auch als einzelner globaler Modulator gehalten werden. Noch
keine Modulationsmatrix und keine Makros (S-05b). Noch NICHT in
`AudioCoreVoice`/`SynthNode` verwendet und nicht der produktive Renderpfad
(Nicht-Scope S-05a, per Grep bestaetigt: kein Produktcode ausserhalb
`Sources/HarmonyAudioCore/` bzw. `Tests/HarmonyAudioCoreTests/` referenziert
die neuen Typen).

13 neue Tests (`AudioCoreEnvelopeTests`, 6; `AudioCoreLFOTests`, 7):
samplegenaue Attack-/Decay-Stage-Uebergaenge bei 44.1 und 48 kHz,
kontrollierte Release-Phase aus Attack/Decay/Sustain, `noteOff()` ohne
Wirkung im Idle, `reset()` reproduziert denselben Verlauf, Amp-/Mod-Profil
als unabhaengige Instanzen, Extremparameter finite fuer die Huellkurve;
Sine-/Triangle-Werte und -Periode, Sample-and-Hold konstant pro
Hold-Periode und deterministischer Wechsel danach, geglaetteter Random
endlich/begrenzt/deterministisch ohne abrupte Spruenge, Reset/Key-Sync
reproduziert Phasen- bzw. Zufallsfolge, Extremparameter finite fuer den
LFO.

459/459 Gesamttests gruen (446 bestehend + 13 neu). Normaler Build gruen.
Strict-Concurrency-Build (Clean-`.build`) gruen: 11 Bestandsdateien mit
Warnungen, keine der fuenf neuen `HarmonyAudioCore`-Dateien darunter, keine
neue Warnkategorie. Clean-HEAD-Build/-Test gruen (459/459). `git diff
--check` gruen. Manueller App-Start (`swift run HarmonyEngine3D`) laeuft
mehrere Sekunden ohne Absturz. `bassHoldMode`, aktiver Synth-Klang,
`AudioEngine`-Graph, MIDI und `AudioOutput`-Vertrag nicht beruehrt.

**S-05b-Ergebnis (Runde 053):** feste Modulationsmatrix und vier
Performance-Makros in `Sources/HarmonyAudioCore/`, elf neue Dateien, keine
bestehende Core-Datei geaendert:

- `AudioCoreMacroID.swift`/`AudioCoreMacroValues.swift`: die vier stabilen
  Makros Motion/Color/Space/Focus (Abschnitt 6.5) als `CaseIterable`-Enum
  plus Wertezustand, defensiv auf `0...1` geklemmt, nicht-endliche
  Eingaben fallen auf `0` zurueck. Reiner Value-Typ ohne Singleton.
- `AudioCoreModulationTarget.swift`: feste, interne Zielmenge (Morph-
  Position, Textur-Pegel, Filter-Cutoff, Mix-Tiefe, Amp-/Mod-Huellentiefe,
  Space-Send-Platzhalter) statt freier Strings — klein und vorausschauend
  gewaehlt, ohne die ganze Spaeter-Verdrahtung zu erraten.
- `AudioCoreLFOSlot.swift`/`AudioCoreEnvelopeRole.swift`/
  `AudioCoreModulationSource.swift`: typisierte Referenz auf einen der drei
  S-05a-LFOs bzw. die Amp-/Mod-Huellenrolle, ohne dass die Matrix selbst
  eine `AudioCoreLFO`-/`AudioCoreEnvelope`-Instanz besitzt — ein spaeterer
  Verdrahtungsslice liest die laufenden Werte und schreibt sie in
  `AudioCoreModulationSourceValues`.
- `AudioCoreModulationRoute.swift`: eine statische Route (Source, Target,
  bipolarer Amount `-1...1`, an/aus).
- `AudioCoreModulationSourceValues.swift`/`AudioCoreModulationTargetValues.swift`:
  klare Trennung zwischen laufendem Modulationszustand (Makro-/LFO-/
  Huellenwerte als reiner Snapshot) und Auswertungsergebnis. Beide nutzen
  einen `switch`-basierten Subscript statt `Dictionary` — dadurch bleibt
  derselbe Zugriffspfad sowohl fuer Tests/UI-nahe Auswertung als auch fuer
  einen spaeteren realtime-nahen Pfad geeignet (Handoff-Vorgabe).
- `AudioCoreModulationMatrix.swift`: feste Routenliste, hoechstens 16
  aktive Routen — mehr als 16 uebergebene Routen werden deterministisch auf
  die ersten 16 in Eingabereihenfolge gekuerzt. `evaluate(sources:)`
  durchlaeuft die Routen in fester Reihenfolge, ueberspringt deaktivierte
  Routen, summiert mehrere Routen auf dasselbe Ziel additiv und klemmt jedes
  Ziel abschliessend auf `[-1, 1]`; nicht-endliche Zwischenwerte werden vor
  der Akkumulation verworfen. Leere Matrix (`AudioCoreModulationMatrix.empty`)
  liefert definiert alle Ziele `0`. Keine Allocation im Auswertungspfad
  (fester `Array`-Speicher aus dem Initialisierer, feste
  `AudioCoreModulationTargetValues`-Struct statt Dictionary).
- `AudioCoreParameterSmoother.swift`: wiederverwendbarer, deterministischer
  One-Pole-Glaettungsbaustein fuer Makro- oder Zielwerte. Koeffizient aus
  expliziter Samplerate + Zeitkonstante (`1 - exp(-1/(timeMs*0.001*sr))`,
  identisches Ratenberechnungsprinzip zu `AudioCoreEnvelope`/
  `AudioCoreVoice`), kein globaler Takt/`AudioClock`/Tempo-Sync.
  `timeMs <= 0` wirkt als sofortiger Sprung (Koeffizient `1`).
  `reset(to:)`/`setTarget(_:)` sind reproduzierbar, die Annaeherung an ein
  konstantes Ziel ist bei festem Koeffizient `(0, 1)` immer monoton.

Noch NICHT in `AudioCoreVoice`/`SynthNode`/Presets/`AppSettings`/UI
verwendet (Nicht-Scope S-05b, per Grep bestaetigt: kein Produktcode
ausserhalb `Sources/HarmonyAudioCore/` bzw. `Tests/HarmonyAudioCoreTests/`
referenziert die neuen Typen).

18 neue Tests (`AudioCoreMacroValuesTests`, 5;
`AudioCoreModulationMatrixTests`, 8; `AudioCoreParameterSmootherTests`, 5):
vier Makros mit stabiler Reihenfolge/Identitaet, Clamping auf `0...1` und
Nicht-endlich-Fallback; bipolares Route-Amount-Clamping; 16-Routen-Grenze
mit deterministischer Truncation der ersten 16 Routen; gleiche Inputs
liefern gleiche Outputs; deterministische Akkumulation mehrerer Routen auf
dasselbe Ziel; deaktivierte Routen ohne Wirkung; definierter leerer
Matrix-Fall (alle Ziele `0`); finite/begrenzte Zielwerte bei
NaN/Infinity-Quellwerten; typisierte Source-Subscripts lesen die
erwarteten Felder pro Slot/Rolle; reproduzierbares Reset/monotone
Smoothing-Annaeherung an ein konstantes Ziel; Zeitkonstante `0` wirkt als
sofortiger Sprung; Extremparameter (NaN/Infinity/negative Samplerate/Zeit)
liefern durchgehend endliche Werte.

477/477 Gesamttests gruen (459 bestehend + 18 neu). Normaler Build gruen.
Strict-Concurrency-Build (Clean-`.build`) gruen: dieselben 11
Bestandsdateien wie in den Vorrunden, keine der elf neuen
`HarmonyAudioCore`-Dateien in der Warnliste, keine neue Warnkategorie.
Clean-HEAD-Build/-Test gruen (477/477). `git diff --check` gruen.
Manueller App-Start (`swift run HarmonyEngine3D`) laeuft mehrere Sekunden
ohne Absturz. `bassHoldMode`, aktiver Synth-Klang, `AudioEngine`-Graph,
MIDI und `AudioOutput`-Vertrag nicht beruehrt.

**S-06-Ergebnis (Runde 054):** Filter-/Shaping-Bausteine (Abschnitt 6.3)
in `Sources/HarmonyAudioCore/`, drei neue Dateien, keine bestehende
Core-Datei geaendert:

- `AudioCoreStateVariableFilter.swift`: `AudioCoreSVFMode`
  (`lowpass`/`bandpass`/`highpass`), `AudioCoreSVFParameters` (Cutoff/
  Resonanz `0...1`, nicht-endlich -> `0`) und
  `AudioCoreStateVariableFilter` — ein Zero-Delay-Feedback-SVF nach der
  frei dokumentierten Formel aus Andrew Simpers Cytomic-SVF-Technical-Paper
  (kein proprietaerer Code, keine Fremdbibliothek/-dependency). Cutoff-
  Kurve identisch zu `AudioCoreVoice.calcBiquadLowpassCoefficients`
  (20...20.000 Hz logarithmisch, Q 0.5...20), zusaetzlich defensiv auf
  einen sicheren Abstand zur Nyquist-Grenze begrenzt, weil `tan()` sich
  `sampleRate/2` naehert und divergiert. Lowpass/Bandpass/Highpass werden
  aus demselben Zustandspaar (`ic1eq`/`ic2eq`) abgeleitet; `reset()` setzt
  ausschliesslich den Filterzustand zurueck, Koeffizienten bleiben
  erhalten. Bewusst KEINE Ladder-Simulation und kein Oversampling
  (Scope-Vorgabe/Plan Abschnitt 6.3: "erst nach Messung").
- `AudioCoreSendHighpass.swift`: `AudioCoreSendHighpassParameters`/
  `AudioCoreSendHighpass` — bewusst KEIN zweiter SVF, sondern ein
  klassischer Ein-Pol-Highpass (RC-Differenzierer-Topologie), unbedingt
  stabil bei jedem Cutoff (kein Resonanz-/Q-Parameter, kein
  Ueberschwingen). Engerer, tieferer Cutoff-Bereich (5...2.000 Hz) als der
  Voice-SVF — Zweck ist gezieltes Abschneiden von Bassanteilen vor einem
  spaeteren Raum-Send (Plan Abschnitt 6.3), nicht ein musikalisches
  Klangfilter. Noch kein Send-Routing im Produkt (Nicht-Scope).
- `AudioCoreWaveshaper.swift`: `AudioCoreWaveshaperParameters`/
  `AudioCoreWaveshaper` — zustandsloser `tanh`-Waveshaper (allgemein
  bekannte symmetrische Sigmoidfunktion, keine Nachbildung eines
  proprietaeren Algorithmus). Drive (`0...1`) wird intern auf eine
  Drive-Verstaerkung `1...20` abgebildet; das geshapte Ergebnis wird durch
  `tanh(driveGain)` geteilt, bevor `outputGain` (`0...4`, Default `1.0`)
  angewendet wird — dadurch bleibt der Ausgangspegel bei Vollaussteuerung
  ueber den gesamten Drive-Bereich naeherungsweise konstant statt mit
  steigendem Drive nur unkontrolliert lauter zu werden (Scope-C-Vorgabe).
  Symmetrisch fuer positive/negative Eingaben (ungerade Funktion). Kein
  interner Zustand, daher kein `reset()` noetig.

Alle drei Bausteine behandeln nicht-endliche Eingaben (`.nan`/`.infinity`)
vor der Berechnung als `0`, die Ausgabe ist immer endlich (SVF/Waveshaper
zusaetzlich auf `[-1, 1]` geklemmt). Kein Heap-Zugriff, kein Lock, keine
Dispatch-/Task-/Actor-Nutzung, kein `print` im Sample-Schritt. Noch NICHT
in `AudioCoreVoice`/`SynthNode`/Presets/`AppSettings`/UI verwendet und
nicht der produktive Renderpfad (Nicht-Scope S-06, per Grep bestaetigt:
kein Produktcode ausserhalb `Sources/HarmonyAudioCore/` bzw.
`Tests/HarmonyAudioCoreTests/` referenziert die neuen Typen).

18 neue Tests (`AudioCoreStateVariableFilterTests`, 7;
`AudioCoreSendHighpassTests`, 5; `AudioCoreWaveshaperTests`, 6):
Lowpass laesst tiefe Frequenzen staerker durch als hohe, Highpass
umgekehrt, Bandpass hat um den Cutoff mehr Energie als deutlich
darunter/darueber, Cutoff-/Resonanz-/SampleRate-Extremwerte (inkl.
NaN/Infinity/negativ/0) bleiben ueber alle drei Modi endlich, Reset
reproduziert denselben Verlauf, Determinismus, Parameter-Clamping;
Send-Highpass daempft tieffrequente Energie deutlich staerker als
hochfrequente und laesst hochfrequente Anteile naeherungsweise
unveraendert durch, Extremwerte bleiben endlich, Reset, Clamping,
Determinismus; Waveshaper bleibt bei extremen Eingaben endlich und auf
`[-1, 1]` begrenzt, symmetrisches Verhalten fuer positive/negative
Eingaben, Pegel bei Vollaussteuerung bleibt ueber den gesamten
Drive-Bereich in einem engen Band (Pegelkompensation greift belegbar),
`outputGain` skaliert linear, Parameter-Clamping, Determinismus.

495/495 Gesamttests gruen (477 bestehend + 18 neu). Normaler Build gruen.
Strict-Concurrency-Build (Clean-`.build`) gruen: dieselben 11
Bestandsdateien wie in den Vorrunden, keine der drei neuen
`HarmonyAudioCore`-Dateien in der Warnliste, keine neue Warnkategorie.
Clean-HEAD-Build/-Test gruen (495/495) — ein einzelner Clean-Testlauf
zeigte einen einmaligen, nicht reproduzierbaren Fehlschlag in einer
bestehenden, unveraenderten Testdatei ausserhalb dieses Slices; drei
direkt anschliessende Wiederholungen liefen 495/495 gruen (siehe
Ruecklauf `.agent_handoff/latest_claude.md`, Runde 054, fuer Details).
`git diff --check` gruen. Manueller App-Start (`swift run
HarmonyEngine3D`) laeuft mehrere Sekunden ohne Absturz. `bassHoldMode`,
aktiver Synth-Klang, `AudioEngine`-Graph, MIDI und `AudioOutput`-Vertrag
nicht beruehrt.

### Audio Milestone A3 - Space Engine

| Slice | Inhalt | Gate |
|---|---|---|
| **S-07a** — **erledigt (Runde 055)** | Graph auf gemeinsame Echo-/Space-Sends vorbereiten, Legacy-FX weiterhin aktiv | **Deep Review (Audio-Graph).** Aendert `AudioEngine.setupGraph()`-Topologie fuer alle vier Kanaele gleichzeitig, inkl. Entscheidung zur CH1-Kompressor-Position (Abschnitt 7.1). Kein hoerbarer Default-Wechsel; kontrollierter Graph-Lifecycle; Graphwechsel nie aus dem Rendercallback und nie waehrend klingender Noten ohne kontrolliertes Crossfade/All-Off |
| **S-07b** — **erledigt (Runde 056)** | bestehende Drei-Tap-Settings in `EchoField`-Presetmodell migrieren | Legacy-Presets reproduzierbar |
| **S-08a** — **erledigt (Runde 057)** | `DeepSpace` Early Reflections + Diffusoren | offline stabil, endliche Energie |
| **S-08a-fix** — **erledigt (Runde 058)** | Parameterklemmung von `setParameters(_:)` nachziehen (Finding S-08a-01) | kein Trap/Runaway ueber Post-Init-Mutation |
| **S-08b** — **erledigt (Runde 059)** | modulationsfreier FDN-Tail, Damping, Size und lange Decays; Sample-Rate-Obergrenze (Finding S-08a-02) | Tail-/CPU-/Stabilitaetsgates |
| **S-08b-fix** — **erledigt (Runde 060)** | Allokationen aus dem FDN-Renderpfad entfernt (Finding S-08b-01) | Bit-Identitaet zu Commit `4c49ed9`, SIL-Nachweis Allokationsfreiheit |
| **S-08c** — **erledigt (Runde 061)** | langsame, dekorrelierte Delaymodulation im FDN-Feedbackpfad (lineare Interpolation) | Bit-Identitaet bei Tiefe 0 zu Commit `01085ba`, alle S-08b-Stabilitaetsgates bei maximaler Modulation, SIL-Nachweis Allokationsfreiheit |
| **Runde 064** — **erledigt** | `±1`-Ausgangsklemmung aus `AudioCoreDeepSpaceEarlyReflections.process` entfernt (Stephan-Entscheidung 1); `safeSampleRate` bekommt eine Untergrenze (`minSampleRate = 100 Hz`, S-08c-Review-Beobachtung) | Normalfall bit-identisch zu Commit `3c92919`, Ausgang nachweislich > 1,0 bei starkem Eingang, SIL-Nachweis Allokationsfreiheit |
| **W-02** — **erledigt (Runde 067)** | `DeepSpace`-Kette zusammenschalten: Pre-Delay, Early Reflections und Diffusor→FDN-Tail parallel | Topologie per Test belegt, Renderpfad zur Laufzeit allokationsfrei gemessen, CPU gemessen |
| **W-03a** — **erledigt (Runde 068)** | FDN-Tail vollstaendig renderthread-sicher: `Set<Int>` der Primzahlwahl, `reset()`-Neuallokation und zwei aufgeschobene Copy-on-Write-/Static-Init-Allokationen beseitigt | Bit-Identitaet zu Commit `b7f26d1` ueber getrennte Kompilation beider Quellstaende, dreiteiliger Allokationsnachweis (SIL-Instruktionen, demangelte SIL-Aufruflisten, Laufzeitmessung), Gegenprobe ueber alle 112 Funktionen der Kette |
| **W-03b1** — **erledigt (Runde 070)** | Umschaltmechanik zwischen Legacy- und Atmospheric-Stimme im `SynthNode`-Renderpfad; Legacy bleibt Default, Klang unveraendert | Bit-Identitaet bei Default-Einstellung zu Commit `13e5eaf` (roher `Float.bitPattern`-Vergleich gegen einen separaten Klon), zweiteiliger Allokationsnachweis plus Laufzeitmessung fuer BEIDE Stimmtypen, CPU beider Stimmtypen im echten `SynthNode`-Pfad |
| **W-03b2** — **erledigt (Runde 071)** | Produkt-Default auf die Atmospheric Voice gekippt; S-01-Baseline explizit auf Legacy festgenagelt, eigene Baseline fuer den neuen Pfad | Legacy-Baseline ohne jede Anpassung eines Erwartungswertes gruen und Pruefsumme `0x86a4b146fd9f13e9` unveraendert, neue Atmospheric-Baseline deterministisch, Allokationsfreiheit bei beiden Einstellungen erneut belegt, manueller App-Start mit Signalanalyse |
| **W-03c** — **erledigt (Runde 072)** | `AudioCoreDeepSpace` am `sharedSpaceSendBus`, Send pro Stimme mit `spaceSendLevel` gewichtet; damit ist auch der Raum hoerbar | Bit-Identitaet zu `4278cf6` bei `spaceSend = 0` fuer beide Stimmtypen (Trockenpfad-Pruefsumme `0xd6fe9a8b93774ce7` plus Bit-Vergleich des voll verdrahteten Graphen), Raum bei Produktpegel 23,7 dB unter dem Trockensignal und monoton im Sendpegel, Renderpfad allokationsfrei, beide Baselines zusaetzlich bei 96 kHz |
| **S-08d** | Freeze, Crossfade und Return-EQ fuer `DeepSpace` | kein Feedback-Runaway, Panic-Vertrag klar |
| **S-09** | `EchoField`: Cross-Feedback, Filter, Diffusion, Ducking, Freeze | Delay-Grenz-/Feedbacktests |

**S-07a-Ergebnis (Runde 055):** Stephan hat die in Abschnitt 7.1 offene
CH1-Kompressor-Frage am 2026-07-30 mit **Option A** entschieden: der
bestehende Kompressor bleibt konservativ auf den CH1-Dry-Pfad beschraenkt,
der CH1-Feed in die kuenftigen gemeinsamen Sends soll ihn nicht
durchlaufen. Umsetzung in `Sources/HarmonyEngine3D/AudioEngine.swift` und
neu `Sources/HarmonyEngine3D/AudioGraphTopology.swift`:

- **Zwei neue Busse** `sharedEchoSendBus`/`sharedSpaceSendBus`
  (`AVAudioMixerNode`) sind in `setupGraph()` attached und an
  `engine.mainMixerNode` angeschlossen — ein vorbereiteter, aber
  musikalisch inaktiver Graph-Rand fuer den spaeteren `EchoField`- (S-07b/
  S-09) und `DeepSpace`-Send (S-08). Kein Kanal verbindet sich in diesem
  Slice mit diesen Bussen; ohne Eingangssignal sind beide Busse stumm, der
  Klang aendert sich nicht.
- **Legacy-FX unveraendert:** alle vier bestehenden kanalgetrennten
  Delay-/Reverb-Ketten (inkl. `compressorBass` zwischen `gainBass` und
  `sumBass`/den Delay-Sends) sind byteidentisch erhalten geblieben — reine
  Ergaenzung, keine bestehende `engine.connect(...)`-Zeile wurde entfernt
  oder umgeschrieben.
- **CH1-Kompressor Option A als Code-Artefakt:** `AudioGraphTopology.swift`
  (reiner Swift-Typ ohne AVFAudio-Abhaengigkeit, hardwareunabhaengig
  testbar) definiert `AudioGraphSendTopology.plan` — einen deklarativen
  Plan, an welchem Punkt im jeweiligen Kanal-Signalfluss ein spaeterer
  gemeinsamer Send tatsaechlich abgreifen soll. CH1/Bass ist dort explizit
  `.preChannelDynamics` (vor `compressorBass`), alle anderen Kanaele
  `.postGain`. Der Plan verbindet in S-07a noch keine echten `AVAudioNode`s
  — das legt der jeweilige Umsetzungsslice (S-07b/S-08/S-09) fest, gebunden
  an genau diesen Abgriffspunkt. 5 neue Tests
  (`AudioGraphSendTopologyTests`) verifizieren den Plan, insbesondere den
  CH1-Option-A-Abgriffspunkt.
- **Realtime-/Lifecycle-Grenzen:** beide neuen Nodes werden ausschliesslich
  in `setupGraph()` attached/verbunden (Init-Pfad), keine Aenderung an
  `AVAudioSourceNode`-Rendercallbacks, `SynthNode`, `NoteEventQueue`,
  `AudioEngine.commandQueue` oder dem `AudioOutput`-Protokoll. Kein
  dynamischer Graphwechsel — der Graph wird einmalig beim Start aufgebaut,
  identisch zu allen vorherigen Runden.

500/500 Gesamttests gruen (495 bestehend + 5 neu). Normaler Build gruen.
Strict-Concurrency-Build (Clean-`.build`) gruen: dieselben 10 Bestands-
Dateibasenamen wie in den Vorrunden (`AppSettings`, `DesignerGamepad`,
`DesignerViewModel`, `FlightController`, `GamepadController`,
`HarmonyEngine3DApp`, `MIDIManager` [App+DesignerKit], `NetworkParser`,
`OutputCoordinator`, `SceneKitView`), weder `AudioEngine.swift` noch
`AudioGraphTopology.swift` in der Warnliste, keine neue Warnkategorie.
Clean-HEAD-Build/-Test gruen (500/500). `git diff --check` gruen.
Manueller App-Start (`.build/debug/HarmonyEngine3D`) laeuft 5s ohne
Absturz, sauberer Prozess-Kill. `bassHoldMode`, `AudioOutput`-Vertrag,
`SynthNode`, `NoteEventQueue`, MIDI und aktiver Synth-Sound nicht beruehrt.
Kein `EchoField`/`DeepSpace`-DSP, kein Default-Klangwechsel, keine
UI-Verdrahtung.

**S-07b-Ergebnis (Runde 056):** neues, eigenstaendiges `EchoFieldPreset`-
Modell in `Sources/HarmonyEngine3D/AudioPreset/` (`EchoFieldPreset.swift`,
`EchoFieldPresetValidator.swift`, `EchoFieldPresetCodec.swift`,
`EchoFieldPresetFactory.swift`, `EchoFieldLegacyMigration.swift`) —
`EchoFieldTap` (`time`/`feedback`/`mix`/`pan`) plus `EchoFieldPreset` mit
exakt vier benannten Tap-Slots `tap1`…`tap4` (kein Array, damit die
Slotzahl ein Compile-Zeit-Fakt bleibt). Zeitbereich `0.001...4.0` s folgt
bewusst dem Plan-Zielwert aus Abschnitt 7.2, nicht der heutigen
`AudioEngine`-Laufzeitgrenze `0.001...2.0` s. `ChannelFXConfig.
echoFieldPreset(...)` migriert `delay1/2/3Time/Feedback/Mix/Pan` feldgenau
in `tap1`/`tap2`/`tap3`; `AudioSynthPreset.echoFieldPreset(...)` bietet
denselben Migrationspfad ueber das bestehende S-03-Presetmodell (beide
Pfade liefern nachweislich identische Taps). Tap 4 ist ueberall
deterministisch `EchoFieldTap.neutral` (stumm, kein Feedback) — es gibt
noch kein viertes Legacy-Tap. `EchoFieldPresetFactory.legacyPresets`
stellt alle vier `ChannelFXConfig.*Defaults` als validator-akzeptables
`EchoFieldPreset` dar (stabile IDs `legacy.echo.*`). Der Validator folgt
derselben Error-/Warning-Policy wie `AudioPresetValidator`, ergaenzt aber
einen dedizierten blockierenden `tapFeedbackRunawayRisk`-Error ab
`feedback >= 1.0`, weil dieses Modell noch keinen DSP-Konsumenten hat, der
so einen Wert sicher klemmen wuerde. 525/525 Gesamttests gruen (500
bestehend + 25 neu). Normaler Build gruen. Strict-Concurrency-Build
(Clean-`.build`) gruen: dieselben 10 Bestands-Dateibasenamen wie in Runde
055, keine der fuenf neuen `EchoField*`-Dateien in der Warnliste, keine
neue Warnkategorie. Clean-HEAD-Build/-Test gruen (525/525). `git diff
--check` gruen. Manueller App-Start laeuft 5s ohne Absturz. Grep bestaetigt:
kein Produktcode ausserhalb `Sources/HarmonyEngine3D/AudioPreset/`/
`Tests/HarmonyEngine3DTests/EchoFieldPresetTests.swift` referenziert die
neuen Typen; keine `AudioEngine`-/`AudioOutput`-/`AppSettings`-/
`SynthNode`-/`NoteEventQueue`-/`HarmonyAudioCore`-Aenderung; kein
`sharedEchoSendBus`-Anschluss; `bassHoldMode` nicht beruehrt. Kein
`EchoField`-DSP, keine Delayline, kein Klang-/Default-/UI-Wechsel.

**S-08a-Ergebnis (Runde 057):** erster `DeepSpace`-Baustein
(`Sources/HarmonyAudioCore/AudioCoreDeepSpaceParameters.swift`,
`AudioCoreDeepSpaceEarlyReflections.swift`, `AudioCoreDeepSpaceDiffuser.swift`)
— reine DSP-Infrastruktur, kein Produktcode ausserhalb `HarmonyAudioCore`/
Tests referenziert die neuen Typen. `AudioCoreDeepSpaceEarlyReflections`
liest sieben feste, deterministische Taps aus einem Ringpuffer; Tap-Zeiten
skaliert mit `size` zwischen 15 ms und 150 ms plus Pre-Delay, geometrisch
fallende Gains (konservative Summe deutlich unter 1), festes Stereo-
Gewichtungsmuster ohne Zufall/Modulation. Endliche FIR-Impulsantwort (keine
Rueckkopplung), Puffer bei `init`/`prepare(sampleRate:)` fest alloziert.
`AudioCoreDeepSpaceDiffuser` verkettet vier Schroeder-Allpass-Stufen je
Kanal (links/rechts mit unterschiedlichen Verzoegerungszeiten fuer Stereo-
Dekorrelation), Koeffizient strikt unter `0.65` begrenzt. Ein echter
DSP-Fehler in der ersten Fassung (Ausgangsterm nutzte den rohen statt des
rueckgekoppelten Werts, kein Unity-Gain-Allpass mehr — Testbefund:
Impulsenergie 43 statt ~2, Spitzenpegel 13.5 statt ~1.0 bei maximaler
Diffusion) wurde vor Abschluss korrigiert; die nach der Korrektur eng
tolerierten Tests (Impulsenergie 1.9999 bei 2.0 erwartet, Spitzenpegel
1.0007 bei 1.0 erwartet ueber 50.000 Samples) bestaetigen die Allpass-
Eigenschaft. Beide Bausteine bleiben bewusst entkoppelt (nicht
zusammengeschaltet), analog zu SVF/Send-Highpass/Waveshaper aus S-06. 16
neue Tests (`AudioCoreDeepSpaceTests`) decken finite/begrenzte
Impulsantwort, Reset-/Instanz-Determinismus, nicht-endliche/extreme
Parameter und Sample-Raten, Diffusor-Stabilitaet bei maximaler Diffusion
ueber Dauersignal, deterministisches Pre-Delay und definierten Stereo-
Ausgang ab. `swift test`: 541/541 gruen (525 bestehend + 16 neu). Normaler
Build gruen. Strict-Concurrency-Build (Clean-`.build`) gruen: dieselben 10
Bestands-Dateibasenamen wie in Runde 054-056, keine der drei neuen
`AudioCoreDeepSpace*`-Dateien in der Warnliste, keine neue Warnkategorie.
Clean-HEAD-Build/-Test gruen (541/541). `git diff --check` gruen.
Manueller App-Start laeuft 5s ohne Absturz. Kein `EchoField`-DSP, kein
FDN-Tail, keine Verbindung an `sharedSpaceSendBus`/`sharedEchoSendBus`,
keine `AudioEngine`-/`AudioOutput`-/`AppSettings`-/`SynthNode`-/UI-
Aenderung, kein Klang-/Default-Wechsel. `bassHoldMode` nicht beruehrt.

**S-08a-fix-Ergebnis (Runde 058):** Supervisor-Deep-Review von S-08a fand
Finding S-08a-01: `AudioCoreDeepSpaceParameters` klemmt ausschliesslich im
`init`, ihre vier Felder sind aber `public var` — direkte Feldmutation an
einer bereits konstruierten Instanz umgeht die Klemmung vollstaendig.
Daraus folgten zwei Pfade: ein harter Trap in
`AudioCoreDeepSpaceEarlyReflections.recomputeTapDelays()` (nicht-endliches
`size`/`preDelaySeconds` nach Mutation ueber `setParameters(_:)` liess die
`Double -> Int`-Konvertierung fatal trappen — Supervisor hat das empirisch
gegen die realen Quelldateien mit `exit 133`/SIGTRAP verifiziert) und ein
Runaway ohne Crash im Diffusor (`diffusion > 1` ergibt einen
Allpass-Koeffizienten `> 1`, ausserhalb der Stabilitaetsgrenze). Dieselbe
Defektklasse wie der bereits behobene S-04a-Fund.

Fix, analog zum zweistufigen S-04a-fix-Muster: `setParameters(_:)` baut bei
beiden `DeepSpace`-Typen den uebernommenen Parametersatz jetzt ueber
`AudioCoreDeepSpaceParameters.init(...)` neu auf, statt ihn direkt zu
uebernehmen — das erzwingt den bestehenden Klemmpfad erneut, ohne eine
zweite Klemmlogik zu duplizieren (Klemmung = Semantik). Zusaetzlich, als
redundante Crash-Sicherung direkt an der trappenden Stelle: die
`Double -> Int`-Konvertierung in `recomputeTapDelays()` prueft das
gerundete Zwischenergebnis jetzt explizit auf `isFinite`, bevor sie nach
`Int` konvertiert (Guard = Crash-Sicherung, nicht Semantik). Beide
`DeepSpace`-Typen behandeln `setParameters(_:)` konsistent, auch der
Diffusor, der selbst keinen Trap-Pfad hatte.

7 neue Tests (`AudioCoreDeepSpaceTests`): Cartesian-Post-Init-
Mutationstest ueber alle vier Felder (`.nan`/`.infinity`/`-.infinity`/
negativ/deutlich ausserhalb) fuer beide Typen, expliziter
Regressionstest fuer den verifizierten Trap-Fall (`size = .nan`,
`preDelaySeconds = .infinity` ueber `setParameters(_:)`), zwei
Diffusor-Runaway-Tests ueber den Mutationspfad (`diffusion = 2.0` bzw.
`.infinity`) mit derselben engen Toleranz (`accuracy: 0.2`) wie der
bestehende S-08a-Runaway-Test ueber 50.000 Samples, sowie zwei
Bit-identisch-Nachweise, dass `setParameters(_:)` im gueltigen
Parameterbereich exakt dasselbe Ergebnis liefert wie eine reine
`init`-Konstruktion. 548/548 Gesamttests gruen (541 bestehend + 7 neu).
Normaler Build gruen. Strict-Concurrency-Build (Clean-`.build`) gruen:
dieselben 10 Bestands-Dateibasenamen wie in Runde 054-057, keine der drei
geaenderten `AudioCoreDeepSpace*`-Dateien in der Warnliste, keine neue
Warnkategorie. `git diff --check` gruen. Keine Runtime-/Default-/UI-
Aenderung, keine Tap-Zeiten-/Gains-/Stereo-Gewichte-/Allpass-Delay-/
`maxCoefficient`-Aenderung, `bassHoldMode` nicht beruehrt. Verhalten im
gueltigen Parameterbereich per Test nachweislich unveraendert.

**S-08b-Ergebnis (Runde 059):** zwei Teile.

Teil 1 schliesst Finding S-08a-02 (Supervisor-Review von S-08a-fix):
`safeSampleRate` klemmte bisher nur nach unten (`isFinite && > 0`), eine
endliche, aber absurd grosse Sample Rate liess die `Double -> Int`-
Pufferlaengen-Konvertierung in `AudioCoreDeepSpaceEarlyReflections.
capacity(forSampleRate:)` und `AudioCoreDeepSpaceAllpassStage.init(delayMs:
sampleRate:)` ueberlaufen (verifiziert: `sampleRate: 1e300` -> SIGTRAP).
`AudioCoreDeepSpaceParameters.maxSampleRate` (1.000.000 Hz, dokumentiert
weit oberhalb jeder realen Audio-Hardware) plus eine gemeinsame
`AudioCoreDeepSpaceParameters.safeSampleRate(_:)` sind jetzt die EINE
Klemmstelle fuer die gesamte `DeepSpace`-Familie (Early Reflections,
Diffusor, FDN-Tail) statt einer Kopie pro Typ. `AudioCoreDeepSpace
EarlyReflections`/`AudioCoreDeepSpaceDiffuser` rufen nur noch diese
gemeinsame Funktion auf, ihre eigenen privaten Kopien sind entfernt.

Teil 2 ist der modulationsfreie FDN-Tail (`AudioCoreDeepSpaceFDNParameters`,
`AudioCoreDeepSpaceFDNMatrix`, `AudioCoreDeepSpaceFDNTail` in
`Sources/HarmonyAudioCore/`) — reine, entkoppelte DSP-Infrastruktur, noch
nicht mit Early Reflections/Diffusor verbunden, kein Send-Bus-Anschluss.
Acht Delaylinien mit geometrisch gespreizten Ziel-Laengen (Verhaeltnis
1.0...2.6 ueber acht Stufen), auf die naechste noch nicht vergebene
Primzahl gerundet (`nearestPrime`, deterministische Trial-Division-Suche
nur bei Init/Prepare/Parameteraenderung, nicht in `process`) — zwei
verschiedene Primzahlen haben zwingend ggT 1, das macht "teilerfremd" zu
einer exakten, testbaren Eigenschaft statt einer Naeherung. Feedback-Matrix:
Ordnung-8-Walsh-Hadamard (Sylvester-Konstruktion), gewaehlt statt
Householder, weil eine Zweierpotenz-Hadamard-Matrix eine feste +-1-Struktur
ohne Reflexionsvektor-Wahl hat und per Konstruktion EXAKT orthogonal ist
(`H^T H = 8*I`) statt nur naeherungsweise. Je Linie ein Ein-Pol-Tiefpass im
Feedbackpfad (frequenzabhaengige Daempfung, DC-Gain exakt 1) und ein
Rundlauf-Gain `g_i = 10^(-3 * L_i_seconds / RT60)` (Jot-Standardformel) aus
einem gemeinsamen RT60-Sollwert (`decay`, logarithmisch 0,3...60 s) — alle
acht Linien klingen dadurch konsistent im selben RT60 ab. Stabilitaets-
argument: fuer jedes endliche RT60 ist `g_i` streng kleiner 1 (zusaetzlich
hart auf 0,999 gedeckelt), der Tiefpass hat bei jeder Frequenz Verstaerkung
<= 1, die Hadamard-Matrix ist energieerhaltend — die Gesamtschleifen-
verstaerkung bleibt damit fuer jedes endliche `decay`/`size` echt unter 1,
keine Selbstoszillation moeglich. Fester Eingangs-Injektionsvektor
(alternierende Vorzeichen, 1/sqrt(8)) und feste, asymmetrische Stereo-
Ausgangsgewichte je Linie (Gain 0,125) — kein Zufall, keine Modulation.
Delaymodulation ist bewusst als S-08c nachgeschoben (Interpolation im
Feedbackpfad ist ein eigener Risikoblock mit eigenen Artefakt-/
Determinismusgates, analog zum Vorgehen bei S-04a/S-04b und S-05a/S-05b).

Sample-Rate-Obergrenze: bei 1.000.000 Hz und `size = 1.0` betraegt die
Gesamtpuffergroesse aller acht Linien 2.437.399 Samples (~9,3 MB als
`Float`); bei jeder realen Sample Rate (<= 192 kHz) entsprechend kleiner
(~1,8 MB bei 192 kHz, `size = 1.0`). Test verifiziert < 16 MB als
konservatives Worst-Case-Budget.

22 neue Tests (18 `AudioCoreDeepSpaceFDNTests` + 4 `AudioCoreDeepSpaceTests`
fuer Teil 1): Impulsantwort finite ueber 6 s bei maximalem `decay`,
Fensterenergie faellt monoton (0,5-s-Bloecke, Toleranz 3 % gegen
Interferenz-Flutter zwischen den acht Linien), Matrix isoliert getestet
(Energieerhaltung fuer fuenf Vektoren PLUS vollstaendiger Orthonormalitaets-
nachweis ueber alle acht Spalten), Selbstoszillationsgrenze an zwei
Extremen (`size=1/decay=1`, rechnerisch strengster Fall `size=0/decay=1`
mit dem groessten `g_i`), Reset-/Instanz-Determinismus bit-exakt, nicht-
endliche/extreme Parameter inkl. Post-Init-Mutationspfad ueber
`setParameters(_:)` (S-08a-01-Lehre, jetzt Pflicht fuer jeden neuen Typ),
Sample-Rate-Grenzen inklusive `1e300`/`.greatestFiniteMagnitude`,
frequenzabhaengige Daempfung (hohe Frequenz klingt nachweislich schneller ab
als tiefe, gemessen ueber Abklingverhaeltnis nach Sinus-Burst), definierter
nicht-identischer Stereo-Ausgang, paarweise Teilerfremdheit ueber den
gesamten `size`-Bereich, Speicherbudget. `swift test`: 570/570 gruen (548
bestehend + 22 neu). Normaler Build gruen. Strict-Concurrency-Build
(Clean-`.build`) gruen: dieselben 10 Bestands-Dateibasenamen wie in Runde
054-058, keine der neuen/geaenderten `AudioCoreDeepSpace*`-Dateien in der
Warnliste, keine neue Warnkategorie. Clean-HEAD-Build/-Test gruen. `git
diff --check` gruen. Scope-Grep bestaetigt: nur die zwei unveraenderten
S-07a-Kommentare in `AudioEngine.swift` erwaehnen `DeepSpace`, keine neue
Runtime-/UI-/`AudioEngine`-Referenz. Kein `EchoField`-DSP, kein
Zusammenschalten von Early Reflections/Diffusor/Tail, keine Verbindung an
`sharedEchoSendBus`/`sharedSpaceSendBus`, kein Freeze/Return-EQ, keine
Klangabnahme, `bassHoldMode` nicht beruehrt.

**S-08b-fix-Ergebnis (Runde 060):** Finding S-08b-01 (Heap-Allokation im
FDN-Renderpfad) geschlossen. `AudioCoreDeepSpaceFDNTail.process` alloziierte
bisher pro Sample zwei Swift-Arrays (`delayed`, `damped`), zusaetzlich
alloziierte `AudioCoreDeepSpaceFDNMatrix.apply(_:)` ein drittes Array pro
Aufruf — der Dateikommentar, der das mit den bestehenden `[Float]`-
Zwischenwerten in `AudioCoreDeepSpaceEarlyReflections`/`AudioCoreDeepSpace
Diffuser` rechtfertigte, war falsch (beide Bestandstypen haben in `process`
keine einzige Array-Konstruktion) und ist jetzt korrigiert.

Realtime-Vertrag des Tails jetzt: `process(left:right:)` alloziiert keine
Arrays. Drei feste Scratch-Puffer (`delayedScratch`/`dampedScratch`/
`matrixScratch`, Groesse `lineCount` = 8) sind gespeicherte Eigenschaften,
ausschliesslich in `init`/`prepare(sampleRate:)` angelegt, in `process` nur
beschrieben. `AudioCoreDeepSpaceFDNMatrix` bekommt eine puffer-schreibende
Form `apply(_:into:)`, die in `matrixScratch` schreibt statt ein neues Array
zurueckzugeben; die allozierende `apply(_:) -> [Float]` bleibt fuer Tests/
Nicht-Renderpfad-Aufrufer bestehen, delegiert aber intern an `apply(_:into:)`
(eine Implementierung, keine Logikduplikation) und wird vom Renderpfad nicht
mehr aufgerufen. Zusaetzlich: die acht Delaylinien liegen nicht mehr als
`[[Float]]` vor (geschachtelte Array-Indirektion mit eigener Uniqueness-
Pruefung je Linie), sondern als ein einziger flacher `[Float]`-Puffer mit
festem Start-Offset je Linie (`lineOffset`, Praefixsumme ueber
`lineCapacity`) — robuster gegen CoW-Ueberraschungen und leichter beweisbar
allokationsfrei.

Nachweis per SIL (`swiftc -O -wmo -emit-sil -module-name Probe
AudioCoreDeepSpaceFDNTail.swift AudioCoreDeepSpaceFDNMatrix.swift
AudioCoreDeepSpaceFDNParameters.swift AudioCoreDeepSpaceParameters.swift`,
Probe-Kompilat aus einer Kopie der vier betroffenen Quelldateien): die
`process`-Funktion enthaelt 0x `_allocateBufferUninitialized`/
`_allocateUninitializedArray`/`alloc_ref`/`alloc_box`; die inline-
spezialisierte `apply(_:into:)` ebenfalls 0x. Verbleibend sind fuenf
bedingte `_ArrayBuffer._consumeAndCreateNew`-Slow-Path-Aufrufe (Swifts
Standard-Uniqueness-Check fuer Array-Subscript-Schreibzugriffe) — diese
Instruktionen existieren nur als vom Optimizer nicht wegbeweisbarer
Slow-Path-Zweig; da `self` waehrend `process` als eindeutiger `@inout`-
Empfaenger vorliegt, nimmt die Ausfuehrung zur Laufzeit immer den
"bereits eindeutig"-Fast-Path, ohne den Slow Path je zu betreten. Sie sind
keine Heap-Allokationen im Sinne der Finding-Definition
(`_allocateBufferUninitialized`-Zaehlung).

Bit-Identitaet zu Commit `4c49ed9`: neuer Regressionstest
`test_bitIdenticalOutput_matchesS08bBaselineChecksum` in
`AudioCoreDeepSpaceFDNTests.swift` — deterministischer FNV-1a-Bit-Checksum
(kein Swift-`Hasher`, randomisierter Prozess-Seed) ueber 4 Parameter-/
Sample-Rate-Konfigurationen x 256 Samples x Stereo. Checksum vor dem Umbau
auf dem unveraenderten Commit-`4c49ed9`-Code erzeugt
(`0xb9d103fd6854a325`), nach dem Umbau bit-identisch reproduziert.

Alle 18 bestehenden `AudioCoreDeepSpaceFDNTests` (Stabilitaets-/Energiegates)
bleiben unveraendert gruen, plus der neue Bit-Identitaets-Test: 19/19.
`swift test` gesamt: 571/571 (570 bestehend + 1 neu). Normaler Build gruen.
Strict-Concurrency-Build (Clean-`.build`) gruen: dieselben 10
Bestands-Dateibasenamen wie in Runde 054-059, keine der zwei geaenderten
`AudioCoreDeepSpaceFDN*`-Dateien in der Warnliste, keine neue Warnkategorie
(596 Gesamtwarnungen, identisch zu Runde 059). `git diff --check` gruen.
Scope-Grep bestaetigt: nur die zwei unveraenderten S-07a-Kommentare in
`AudioEngine.swift` erwaehnen `DeepSpace`, keine neue Runtime-/UI-/
`AudioEngine`-Referenz. Keine Aenderung an Linienlaengen, Primzahlwahl,
Gains, RT60-Formel, Daempfungsmodell, Matrixwerten, Injektions-/
Ausgangsgewichten — reine Ausfuehrungsform-Aenderung, Klang bit-identisch.
`bassHoldMode` nicht beruehrt.

**S-08c-Ergebnis (Runde 061):** dekorrelierte Delaymodulation im
FDN-Feedbackpfad (Abschnitt 7.3: "langsame, decorrelierte Delaymodulation"),
mit fraktionaler, linear interpolierter Leseposition je Delaylinie.
`AudioCoreDeepSpaceFDNParameters` bekommt zwei neue normalisierte
0...1-Felder, `modulationDepth` (Default `0` — kein Verhaltenswechsel fuer
bestehende Aufrufer) und `modulationRate`.

Dekorrelation: Rate- und Phasenversatz je der acht Linien kommen aus zwei
Kronecker/Weyl-Folgen ueber zwei verschiedene irrationale Konstanten
(goldener bzw. silberner Schnitt) — zwei Linien haben damit nie ein
rationales Frequenzverhaeltnis, also keine gemeinsame Periode/Schwebung,
unabhaengig von der Renderdauer. Modulationsrate ist bewusst niedrig
begrenzt (`0,02...0,35 Hz`, `AudioCoreDeepSpaceFDNTail.minModulationRateHz`/
`maxModulationRateHz`) — deutlich unterhalb der Rate, ab der Delaymodulation
als Zwitschern/Chorus wahrnehmbar wird. Modulationstiefe ist auf maximal 8
Samples begrenzt (`maxModulationDepthSamples`) und zusaetzlich je Linie
dynamisch auf `lineLengthSamples - 1` gedeckelt, damit die effektive
Delayzeit bei sehr kurzen Linien (z. B. extrem niedrige Sample Raten) nie
negativ wird.

Interpolation: linear (`AudioCoreDeepSpaceFDNTail.linearInterpolate(_:_:
fraction:)`), der im Auftrag vorgeschlagene Startpunkt. Begruendung gegen
Allpass/Lagrange: bei dieser kleinen Modulationstiefe waere der
Artefaktunterschied kaum hoerbar, waehrend Allpass-Interpolation einen
zusaetzlichen, eigenen Reset-/Determinismuspflichtigen Zustand einfuehren
wuerde. Wichtiger: lineare Interpolation ist eine Konvexkombination der
beiden Nachbar-Taps (Gewichte `1-frac`/`frac`, Summe exakt 1) — der
interpolierte Wert kann die Amplitude der beiden Quell-Samples beweisbar nie
ueberschreiten. Das bestehende S-08b-Stabilitaetsargument (Rundlauf-Gain
`g_i < 1`, Tiefpass `|H| <= 1`, orthonormale Matrix) greift damit
unveraendert auch auf den interpolierten Wert.

Bit-Identitaet bei Tiefe 0: `process(left:right:)` verzweigt VOR jeder
Modulationsrechnung auf `parameters.modulationDepth > 0`. Bei `false`
(Default) laeuft der textuell unveraenderte S-08b-fix-Lesepfad — keine
Gleitkomma-Rechenkette, die zufaellig auf denselben Wert rundet, sondern
derselbe Code. Der bestehende Checksum-Test
(`test_bitIdenticalOutput_matchesS08bBaselineChecksum`) blieb dadurch
unveraendert und bleibt gruen mit demselben Erwartungswert
(`0xb9d103fd6854a325`) wie in Runde 060; ein zweiter Test mit explizit
gesetztem `modulationDepth: 0.0` (statt implizitem Default) bestaetigt
denselben Checksum zusaetzlich.

Kapazitaetsreserve statt Laufzeitklemmung: `lineLengthSamples`/`lineGain`/
`dampingCoefficient` werden weiterhin exakt wie vor S-08c berechnet — die
Klemm-/Suchgrenze fuer die Linienlaengen-/Primzahlwahl kommt jetzt aus einem
neuen privaten `baseCapacity` (identische Formel zur alten `lineCapacity`),
nicht aus der tatsaechlich allozierten (jetzt groesseren) `lineCapacity`.
Das haelt die Linienlaengen-/Primzahlwahl byteidentisch zu `01085ba`,
unabhaengig von der zusaetzlichen Modulationsreserve. `lineCapacity` selbst
ist um `maxModulationDepthSamples` (aufgerundet) plus einen
Interpolations-Tap groesser als `baseCapacity` — rechnerisch bewiesen
ausreichend fuer jede erlaubte Kombination aus Basis-Delay, Modulationshub
und Interpolations-Tap, nie zur Laufzeit geklemmt.

Realtime-Vertrag: `process(left:right:)` bleibt allokationsfrei. Nachweis
per SIL (`swiftc -O -wmo -emit-sil`, isolierte Kopie der vier
`AudioCoreDeepSpace*`-Quelldateien wie in Runde 060): 0x
`_allocateBufferUninitialized`/`_allocateUninitializedArray`/`alloc_ref`/
`alloc_box`/`swift_allocObject` in `process` und in der spezialisierten
`apply(_:into:)`. Ein praeziser Scan aller SIL-Funktionen bestaetigt: nur
`init`, `prepare(sampleRate:)`, `reset()` (unveraendert 2 Allokationen,
identisch zum dokumentierten, bewusst nicht in diesem Slice behobenen
Vor-S-08c-Zustand) und die Kontrollrate-Hilfsfunktion `computeOffsets`
allozieren — `process`/`apply(_:into:)` nicht.

15 neue Tests decken die neun Akzeptanzgates ab: Stabilitaet bei maximaler
Modulation (3 Tests, gespiegelt an den bestehenden S-08b-Gates),
Determinismus mit aktiver Modulation (2), Bit-Identitaet bei Tiefe 0 explizit
(1) und Wirksamkeit bei Tiefe > 0 (1), Dekorrelation ueber die
Ratenmultiplikator-/Phasenversatz-Konstanten und ueber eine
Kanalkorrelationsmessung der simulierten Modulationssignale (2),
Kapazitaetssicherheit ueber extreme Parameter-/Sample-Raten-Kombinationen
inkl. `size`-Extremen (2), Artefaktarmut der Interpolationsformel plus
Kontinuitaetsnachweis am realen Renderpfad (2), Post-Init-Mutationspfad fuer
die neuen Parameter (1) sowie ein Regressionsschutz dafuer, dass
`setParameters(_:)` die Modulation nicht mehr auf die Defaults zuruecksetzt
(1). `AudioCoreDeepSpaceFDNTests`: 34/34 (19 bestehend + 15 neu).
`HarmonyAudioCoreTests` gesamt: 159/159. `swift test` gesamt: 586/586 (571
bestehend + 15 neu). Normaler Build gruen. Strict-Concurrency-Build
(Clean-`.build`) gruen: dieselben 10 Bestands-Dateibasenamen wie in Runde
054-060, keine der geaenderten `AudioCoreDeepSpaceFDN*`-Dateien in der
Warnliste, keine neue Warnkategorie (596 Gesamtwarnungen, identisch zu
Runde 060). `git diff --check` gruen. Scope-Grep bestaetigt: nur die zwei
unveraenderten S-07a-Kommentare in `AudioEngine.swift` erwaehnen
`DeepSpace`, keine neue Runtime-/UI-/`AudioEngine`-Referenz. Keine Aenderung
an Linienlaengen, Primzahlwahl, Matrixwerten, RT60-Formel,
Daempfungsmodell, Injektions-/Ausgangsgewichten oder an `reset()`s
Allokationsverhalten (Vormerkung fuer S-13, bewusst unveraendert).
`bassHoldMode` nicht beruehrt.

**Runde-064-Ergebnis:** zwei kleine, zusammengehoerige Korrekturen an den
`DeepSpace`-Core-Bausteinen, beide auf unverdrahtetem Core-Code.

Teil 1 (Stephan-Entscheidung 1, 2026-08-01): `AudioCoreDeepSpaceEarlyReflections
.process(_:)` klemmte den Ausgang bisher hart auf `±1`. Diese
Wertebereichsklemmung ist entfernt, die `isFinite`-Absicherung
(NaN/Infinity -> 0) bleibt bestehen. Begruendung: Diffusor und FDN-Tail
klemmen nicht, die drei `DeepSpace`-Bausteine waren dadurch inkonsistent;
der Baustein ist fuer einen gemeinsamen Send-Bus gebaut, auf dem das
Signal die Summe mehrerer Stimmen traegt und erst danach ueber Send-Pegel/
Fader heruntergezogen wird — ein Zwischenwert ueber 1,0 ist dort normal;
Begrenzung gehoert an das Ende einer Kette, nicht in einen
Zwischenbaustein. Der Normalfall (Eingang <= 1,0) war von der Klemmung
ohnehin praktisch nie betroffen: die Ausgangsspitze liegt bei 0 dBFS
Eingang bei ca. 0,238 (staerkster Tap-Gain `0,28 * mix<=1`, staerkstes
Links-/Rechts-Gewicht `0,85`), die Klemmung griff erst zwischen ca. +9,5
und +14 dBFS Eingang.

Verifikation: `test_earlyReflections_normalRangeInput_matches
PreRemovalChecksum` belegt per FNV-1a-Bit-Checksum ueber vier Parameter-/
Sample-Rate-Konfigurationen, dass der Output bei Eingaben in `[-1, 1]`
bit-identisch zu Commit `3c92919` bleibt (Referenz-Checksum vor der
Aenderung erzeugt). `test_earlyReflections_process_
noLongerClampsAboveUnity` belegt mit Eingangsfaktor 5 (Supervisor-Messung:
die alte Klemmung griff ab ca. Faktor 5), dass die Ausgangsspitze jetzt
> 1,0 liegt und linear dem erwarteten `Eingang * 0,238` folgt statt
geklemmt zu bleiben.

Angepasste Zusicherungen, die bisher nur durch die Klemmung galten: die
Schranke in `test_earlyReflections_stereoOutput_isDefinedAndBounded`
(`abs(value) <= 1.0`) ist von einer durch die Klemmung erzwungenen
Trivialaussage auf `abs(value) <= 0.3` VERSCHAERFT — eine echte, aus der
DSP-Struktur begruendete Aussage: ein Einheitsimpuls trifft pro
Ausgabesample hoechstens einen einzelnen Tap (die sieben Tap-Verzoegerungen
sind bei den Testparametern paarweise verschieden), das analytische
Maximum ist `0,28 * 0,85 = 0,238`, `0,3` ist die dokumentierte
Sicherheitsmarge. `test_earlyReflections_impulseEnergy_isFiniteAndBounded`
galt bereits vor der Aenderung strukturell durch die Tap-Gain-Summe (weit
unter der `< 2.0`-Schranke) und nicht durch die Klemmung — unveraendert
gueltig, Begruendung im Testkommentar ergaenzt.

Teil 2 (S-08c-Review-Beobachtung): `safeSampleRate` hatte bisher nur eine
Obergrenze (`maxSampleRate`, S-08b). Unterhalb von ca. 0,7 Hz wird in
`AudioCoreDeepSpaceFDNTail` `modIncrement > 1`, und der einfache
Phasen-Wrap `if modPhase >= 1.0 { modPhase -= 1.0 }` haelt `modPhase` dann
nicht mehr in `[0, 1)` — kein Crash (Guard-Kette haelt alle Ausgaben
endlich), aber die Modulation degeneriert. Neue Konstante
`AudioCoreDeepSpaceParameters.minSampleRate = 100.0`: eine rein technische
Sicherheitsgrenze, deutlich unterhalb jeder realen Audio-Hardware
(professionelle Interfaces starten bei ca. 8 kHz) und mit ~140-fachem
Sicherheitsabstand oberhalb des 0,7-Hz-Problembereichs, keine
Klangentscheidung. `safeSampleRate(_:)` klemmt jetzt beidseitig
(`min(max(value, minSampleRate), maxSampleRate)`). Bestehende Tests mit
`sampleRate: 1` pruefen seither die Klemmung statt eines absurden
Betriebspunkts (Handoff-Erlaubnis fuer diese eine Stelle); der
realistische Bereich (8 kHz–192 kHz) sowie die Ober-/Sonderfaelle aus
S-08b (`1e300`, `.greatestFiniteMagnitude`, `.infinity`, `.nan`, `0`,
negativ) bleiben unveraendert gueltig. Zwei neue `AudioCoreDeepSpaceFDNTests`
belegen, dass der Phasenzuwachs bei `minSampleRate` mit maximaler
Modulation analytisch unter 1 bleibt und ein 20.000-Sample-Render dort
finite bleibt.

Realtime-Vertrag: `process` bleibt allokationsfrei. SIL-Nachweis
(`swiftc -O -wmo -emit-sil`, isolierte Kopie von
`AudioCoreDeepSpaceEarlyReflections.swift`/`AudioCoreDeepSpaceParameters.swift`):
0x `alloc_ref`/`alloc_box`/`_allocateUninitializedArray`/
`_allocateBufferUninitialized`/`swift_allocObject` in `process`; die
einzigen verbleibenden Aufrufe sind zwei guarded `_consumeAndCreateNew`-
CoW-Uniqueness-Slow-Path-Aufrufe hinter `cond_br`, die zur Laufzeit nie
betreten werden, weil `self` waehrend `process` eindeutig referenziert
ist — dasselbe etablierte Muster wie in S-08b-fix/S-08c.

6 neue Tests: 4 in `AudioCoreDeepSpaceTests` (Bit-Identitaet-Regression,
Klemmung-oberhalb-Unity, `safeSampleRate`-Untergrenze, Invariante
`minSampleRate < maxSampleRate`), 2 in `AudioCoreDeepSpaceFDNTests`
(Phasenzuwachs-Analytik, Langzeit-Endlichkeit). `swift test` gesamt:
605/605 (599 bestehend + 6 neu). Normaler Build gruen. Strict-Concurrency-
Build (Clean-`.build`) gruen: dieselben 10 Bestands-Dateibasenamen wie in
Runde 054-063, keine der beiden geaenderten `AudioCoreDeepSpace*`-Dateien
in der Warnliste, keine neue Warnkategorie (596 Gesamtwarnungen,
identisch zu Runde 063). Clean-HEAD-Build/-Test gruen (605/605).
`git diff --check` gruen. Scope-Grep bestaetigt: nur die zwei
unveraenderten S-07a-Kommentare in `AudioEngine.swift` erwaehnen
`DeepSpace`, keine neue Runtime-/UI-/`AudioEngine`-Referenz. Keine
Aenderung an Tap-Zeiten, Tap-Gains, Stereo-Gewichten, Allpass-Delayzeiten,
`maxCoefficient`, Linienlaengen, Matrixwerten, RT60-Formel oder
Daempfungsmodell. `bassHoldMode` nicht beruehrt.

**W-02-Ergebnis (Runde 067):** zweiter Slice der Verdrahtungskette. Die drei
seit S-08a/S-08b/S-08c einzeln getesteten Raumbausteine laufen erstmals
zusammen. Zwei neue Dateien in `Sources/HarmonyAudioCore/`
(`AudioCoreDeepSpace.swift`, `AudioCoreDeepSpaceChainParameters.swift`),
keine bestehende Core-Datei geaendert.

Topologie exakt wie beauftragt, ohne Abweichung:

```text
Eingang → Pre-Delay → ┬→ Early Reflections ──┐
                      │                      ├→ Summe → Stereo-Ausgang
                      └→ Diffusor → FDN-Tail ┘
```

Die eine Stelle, an der die Kette von den Bausteinen abweicht: das Pre-Delay
liegt jetzt VOR der Aufteilung (Vorgabe) statt innerhalb der
Early-Reflection-Stufe. Die Kette haelt dafuer eine eigene
Verzoegerungslinie und uebergibt der Reflexionsstufe einen Parametersatz mit
`preDelaySeconds = 0`. Ohne das waere das Pre-Delay auf dem Reflexionszweig
doppelt und auf dem Tail-Zweig gar nicht wirksam — die beiden Zweige waeren
gegeneinander verschoben. `AudioCoreDeepSpaceEarlyReflections` selbst bleibt
unveraendert.

Die Kette ist mono-in/stereo-out, weil beide Zweige das sind: die
Reflexionsstufe ist per Konstruktion mono-in, und der FDN-Tail mittelt
seinen Eingang intern sofort auf mono. Folge, offen benannt: die
Links-/Rechts-Dekorrelation des Diffusors ueberlebt die Mono-Mittelung nicht
als Stereobild — sie bleibt als staerkere Diffusion wirksam, der
Stereo-Eindruck des Tails kommt aus dessen eigener Ausgangsmatrix.

**Zweigpegel vorlaeufig:** `earlyLevel`/`tailLevel` je 0,5. Gleiche
Gewichtung ist der einzige Wert, der keine Praeferenz zwischen
"nah/diskret" und "weit/verwaschen" ausdrueckt; der Faktor halbiert zugleich
den Summenpegel und ist damit headroom-freundlich fuer einen Send-Bus.
Stephan hoert die Kette ab W-03 und entscheidet dann.

Vier der 25 neuen Tests belegen die Topologie statt sie zu behaupten: die
beiden Zweige addieren sich exakt zur Summe (parallel, nicht seriell);
`diffusion` von 0 auf 1 laesst den Reflexionszweig bit-identisch und
veraendert den Tail-Zweig messbar (der Diffusor speist nur den Tail); das
Pre-Delay verschiebt beide Zweige bit-exakt um dieselbe Samplezahl; und
beide Zweige sind einzeln bit-identisch zu ihren Einzelbausteinen.

Realtime-Vertrag zur Laufzeit gemessen statt nur per SIL abgeleitet: ein
interponierter `malloc`-Zaehler zeigt 0 Allokationen fuer `process`/`render`
ueber 1.024.000 Samples und 0 fuer die eigenen Ruempfe von `reset()` und
`setParameters(_:)`. Damit ist erstmals direkt belegt, dass die
`_consumeAndCreateNew`-CoW-Slow-Paths dieser Typenfamilie zur Laufzeit
tatsaechlich nie betreten werden — bisher war das eine (richtige) Ableitung
aus der SIL-Struktur.

Dieselbe Messung deckte einen **Bestandsbefund** auf, den der SIL-Textscan
strukturell nicht sehen kann: `AudioCoreDeepSpaceFDNTail.setParameters(_:)`
alloziert 4 Mal pro Aufruf, weil `recomputeLineState()` ein `Set<Int>` fuer
die Primzahlwahl aufbaut. Die Allokation passiert innerhalb der
Standardbibliothek und steht deshalb nicht als
`alloc_ref`/`_allocateUninitializedArray` im Rumpf der Funktion. Gemeldet und
per Auftrag NICHT korrigiert (Nicht-Scope: keine Aenderung an den drei
Bausteinen); zusammen mit der seit S-08b-fix bekannten
`reset()`-Allokation (2 pro Aufruf) fuer W-03 vorgemerkt — **beide in W-03a
(Runde 068) geschlossen, siehe unten.** Gegenprobe mit
derselben Methode an `AudioCoreAtmosphericVoice`: 0 Allokationen in `render`,
`setParameters`, `reset` und `configure` — die W-01-Aussage haelt auch unter
der schaerferen Messung.

CPU (MacBookPro18,1, Apple M1 Pro, 48 kHz, 256er Bloecke, 3.000 Messbloecke
nach 500 Aufwaermbloecken, `swiftc -O -wmo`): Raumkette allein Median 248,9
ns/Sample = 83,7x Echtzeit, p99 71,8x, schlechtester Block 52,2x. 16 Stimmen
plus eine Raumkette **gemeinsam gemessen statt hochgerechnet**: Median 17,2x,
p99 15,4x, schlechtester Block 12,1x. Ziel >= 10x eingehalten, harte
Untergrenze 5x mit grossem Abstand.

25 neue Tests (`AudioCoreDeepSpaceChainTests`), `swift test` gesamt 654/654
(629 bestehend + 25 neu), `OfflineSynthBaselineTests` 8/8 unveraendert.
Normaler Build gruen, Strict-Concurrency-Build gruen mit identischem
Warnungsprofil zu Runde 054-066 (596 Warnungen, dieselben 10
Bestands-Dateibasenamen, keine der neuen Dateien in der Warnliste),
Clean-HEAD-Build/-Test gruen, `git diff --check` gruen. Scope-Grep: keine
neue Runtime-/UI-/`AudioEngine`-Referenz, nur die zwei unveraenderten
S-07a-Kommentare in `AudioEngine.swift`. Keine Aenderung an Tap-Zeiten,
Tap-Gains, Stereo-Gewichten, Allpass-Delayzeiten, `maxCoefficient`,
Linienlaengen, Primzahlwahl, Matrixwerten, RT60-Formel, Daempfungsmodell
oder an der Atmospheric Voice aus W-01 (insbesondere nicht an der
`-7`-Cent-Feinstimmung). `bassHoldMode` nicht beruehrt.

**W-03a-Ergebnis (Runde 068):** Hygiene-Slice vor der Verdrahtung. Der
Realtime-Vertrag von `AudioCoreDeepSpaceFDNTail` gilt jetzt fuer den ganzen
Typ statt nur fuer `process(left:right:)`: `setParameters(_:)` und `reset()`
allozieren nicht mehr, nur `init` und `prepare(sampleRate:)` duerfen es noch.
Damit gilt fuer die gesamte `DeepSpace`-Kette derselbe Vertrag wie fuer
`AudioCoreAtmosphericVoice`, und W-03b darf beide aus einem Command im
Rendercallback ausloesen.

Drei Stellen waren zu schliessen. Die ersten beiden waren beauftragt: das
`Set<Int>` der Primzahlwahl in `recomputeLineState()` (4 Allokationen je
`setParameters(_:)`-Aufruf, Finding W-02-01) ist durch einen festen
Acht-Element-Puffer mit linearer Suche ersetzt, und `reset()` nullt
`writeIndex`/`dampingFilterState` in place statt sie neu zu bauen (2 je
Aufruf).

Die dritte war neu und ist die eigentliche methodische Ausbeute dieser Runde:
**zwei AUFGESCHOBENE Allokationen, die nicht in der verursachenden Funktion
anfallen, sondern in der naechsten.** `modPhase = modulationPhaseOffsets` in
`init`/`prepare`/`reset` kopiert nicht, sondern teilt den Puffer der
Konstante; die Copy-on-Write-Kopie wurde erst beim naechsten Schreibzugriff
faellig — also im ersten `process`-Aufruf danach, mitten im Rendercallback
(gemessen: genau 1 je `reset()`). Dazu die faule `static let`-Initialisierung
der beiden ueber `map` gebildeten Gewichtstabellen, deren erster Zugriff in
`process` stand (2 einmalig je Prozess, faellig im allerersten
Rendercallback). Behoben durch elementweises Zuruecksetzen der Phase in den
eigenen Puffer (`resetModulationPhase()`) und durch Bindung der
Renderkonstanten an die Instanz in `init` — letzteres nimmt zusaetzlich die
`swift_once`-Pruefung aus dem Renderpfad und kostet keinen zusaetzlichen
Heap, weil eine Array-Zuweisung den Puffer teilt statt kopiert.

**Konsequenz fuer die Nachweismethode, dritte Verschaerfung in Folge.** Der
Instruktions-Textscan (seit Runde 060) findet Allokationen innerhalb der
Standardbibliothek nicht — das war Finding W-02-01. Der in Runde 067
ergaenzte Aufruflisten-Scan findet sie, aber nur DEMANGELT: in rohem SIL
heisst `Set` `Sh` und `Dictionary` `SD`, ein Textscan ueber die rohen Symbole
laeuft daran vorbei. Und beide zusammen finden Fall 3 prinzipiell nicht, weil
eine aufgeschobene Kopie in einer anderen Funktion faellig wird als der, die
sie verursacht — sie steht in keiner der beiden Aufruflisten. Nur die
Laufzeitmessung findet sie. Der Nachweis ist ab jetzt dreiteilig:
Instruktions-Scan, demangelter Aufruflisten-Scan, Laufzeitmessung mit
interponiertem `malloc`/`calloc`/`realloc`, wobei die Messung ausdruecklich
die ERSTEN Samples nach `init`/`prepare`/`reset` mitmisst statt nur den
eingeschwungenen Zustand.

Gemessen nach dem Umbau (Selbstpruefung des Zaehlers bestanden): 0
Allokationen in `process` (allererster Aufruf des Prozesses, erste Samples
nach `init`/`reset()`/`setParameters`, eingeschwungen ueber 100.000 Samples),
0 in `setParameters(_:)` und `reset()` ueber je 10.000 Aufrufe, 0 in
`AudioCoreDeepSpace.render` ueber 1.024.000 Samples. Gegenprobe ueber alle
112 SIL-Funktionen der Kette: die einzigen Funktionen mit
Allokations-Instruktion oder allozierendem Stdlib-Aufruf sind `init` und
`prepare(sampleRate:)` der vier Typen.

**Klang bit-identisch zu Commit `b7f26d1`**, belegt nicht ueber den
eingecheckten Test allein, sondern durch getrennte Kompilation beider
Quellstaende gegen denselben deterministischen Treiber: 61.022
Float-Werte ueber 10 statische Konfigurationen, vier Sample-Raten mit je zehn
`setParameters(_:)`-Wechseln mitten im Render, `reset()`/`prepare()` mitten
im Render, nicht-endliche Parameter und Sample-Raten, sowie die vollstaendige
W-02-Kette — identische SHA-1 `c1de1f911b342c2008ae8e7de0ab4e6d6ff543b1`.
Mitgeprueft werden dabei die gewaehlten Linienlaengen selbst, nicht nur ihr
Klangergebnis; die Reihenfolge der Ausschluesse bleibt dieselbe, weil die
Ausschlussliste weiterhin genau die Laengen der Linien `0..<i` enthaelt und
`contains` von Reihenfolge und Vielfachheit unabhaengig ist.

3 neue Tests (`AudioCoreDeepSpaceFDNTests` 39/39), `swift test` gesamt
657/657 (654 bestehend + 3 neu), kein bestehender Test angepasst,
`OfflineSynthBaselineTests` 8/8 unveraendert. Normaler Build gruen,
Strict-Concurrency-Build gruen mit identischem Warnungsprofil zu Runde
054-067 (596 Warnungen, dieselben 10 Bestands-Dateibasenamen, die geaenderten
Dateien nicht in der Warnliste), Clean-HEAD-Build/-Test gruen, `git diff
--check` gruen. Reine Ausfuehrungsform-Aenderung: keine Verdrahtung, keine
Send-Bus-Verbindung, keine `AudioEngine`-/`SynthNode`-/`AppSettings`-/UI-
Aenderung, keine Aenderung an Klangparametern, Zweigpegeln,
Primzahlwahl-Logik, Gains, RT60, Daempfung oder Matrixwerten, Atmospheric
Voice aus W-01 nicht beruehrt.

**W-03b2-Ergebnis (Runde 071) — der Synth ist hoerbar.** Der Slice besteht
aus zwei Dingen und sonst nichts: dem Default-Wechsel und dem Umzug der
S-01-Baseline.

**Der Default liegt an genau einer Stelle.** `AppSettings.AudioConfig
.voiceEngine` ist `.atmospheric`, ebenso der Fallback in `load()`. Von dort
laeuft der Wert ueber `HarmonyEngine3DApp.makeAudioOutput` →
`AudioEngine.applyVoiceEngine` → `synthParams(from:)` in jeden
Kanal-Snapshot — der Weg, den W-03b1 gebaut hat, unveraendert. Ein bereits
persistierter Wert gewinnt weiterhin gegen den Default.

**`SynthParams.defaults.voiceEngine` bleibt `.legacy`, und das ist
Absicht.** Der Typ ist der Kanal-Snapshot, nicht der Einstellungsspeicher;
sein Default ist der neutrale Vorkonfigurationswert, mit dem
`SynthNode.prepare()` den Pool baut, bevor der erste echte Snapshot
ankommt. Er ist ausserdem der Anker des Bit-Identitaets-Nachweises: die
Szenariofolge in `SynthVoiceEngineTests.legacyScenarioChecksum()` muss
unveraendert gegen `13e5eaf` uebersetzbar bleiben und darf
`SynthVoiceEngine` deshalb nicht erwaehnen. Waere dieser Default mitgekippt
worden, haetten ausserdem die Bestandstests fuer Live-Parameter und
`NoteEventQueue` stillschweigend einen anderen DSP-Pfad geprueft.
Die Abfolge beim Start ist im Log des manuellen App-Starts belegt: vier
`prepare()`-Zeilen mit `voiceEngine=legacy`, unmittelbar danach
`voiceEngine → atmospheric`, und erst 150 ms spaeter der erste `noteOn` —
es klingt nie eine Note auf dem abgewaehlten Pool.

**Baselines.** `OfflineSynthBaselineTests` waehlen Legacy jetzt
ausdruecklich (`legacyParams`) statt ueber einen Default und blieben ohne
jede Anpassung eines Erwartungswertes gruen; die Legacy-Pruefsumme ist
unveraendert `0x86a4b146fd9f13e9`. Neu daneben
`AtmosphericSynthBaselineTests` mit 11 Tests nach demselben Muster, plus
zwei Ergaenzungen, die der Legacy-Baseline fehlen: Determinismus auch ueber
Voice-Stealing und Unison hinweg (der Texturseed haengt an
`activationOrder`) und eine harte Pegelgrenze unterhalb Vollausschlag.
Referenzmetriken des Atmospheric-Pfads: Peak 0,10232, RMS 0,02956,
spektraler Schwerpunkt 2034 Hz — gegenueber 305 Hz beim Legacy-Referenzton
derselben Note. 680/680 Gesamttests gruen.

**Hoerprobe, rein sachlich.** Zwei Akkorde mit Produkt-Defaults: Peak
−8,5 dBFS, RMS −21,8 dBFS gegen −8,9 / −21,5 dBFS auf dem Legacy-Pfad —
kein Lautheitssprung durch den Default-Wechsel. Kein Sample >= 0,95, kein
nicht-endliches Sample, DC 1,2e−4, Peak im letzten 200-ms-Fenster exakt 0.
Knacks-Indikator (groesste Sprungstelle gegen das 99,99-Perzentil aller
Sprungstellen) 1,30 gegen 1,23 beim Legacy-Pfad, im Dichtefall (8 Noten x 2
Unison, Velocity 127) 1,23 bei Peak −3,5 dBFS. Gleiches Bild bei 44,1, 48
und 96 kHz. **Beide Baselines testen nur 44,1 und 48 kHz — die Maschine
faehrt real 96 kHz**; die Luecke ist gemeldet, nicht geschlossen.

Allokationsfreiheit bei beiden Einstellungen erneut belegt (0 ueber alle
Messabschnitte, Positivkontrolle `prepare()` 71, Zaehler-Selbstpruefung
1.000/1.000), Renderpfad-SIL unveraendert sauber. Strict-Concurrency-Build
596 Warnungen wie Runde 068/070. Nicht angefasst: Poolgroessen, Graph,
Send-Bus, Core-Bausteine, `-7`-Cent-Feinstimmung, Klangparameter.

**W-03c-Ergebnis (Runde 072) — der Raum ist hoerbar, die Verdrahtung ist
abgeschlossen.** Der seit S-07a stille `sharedSpaceSendBus` wird erstmals
gespeist.

**Die Bauform, und warum sie so ist.** Abschnitt 7.1 skizziert
`channel Space send -> DeepSpace -> master` als Graphkette. Umgesetzt ist
sie als Software-Send:

```text
vier SynthNodes ──(SpaceSendBus, je Stimme x spaceSendLevel)──┐
                                                              ↓
                  DeepSpaceReturnNode → sharedSpaceSendBus → mainMixerNode
```

Grund ist der Auftrag selbst: der Send ist PRO STIMME gewichtet.
`AudioCoreAtmosphericVoice.spaceSendLevel` ist ein eigenes Modulationsziel
und existiert nur innerhalb des `VoicePool`, VOR der Summierung der
Stimmen. Hinter `gainX` liegt nur noch die fertige Kanalsumme — ein
Knotenabgriff dort koennte den Wert prinzipiell nicht mehr anwenden. Zwei
Fragen, die dabei zu beantworten waren:

- *Bleibt der getestete Topologie-Deskriptor gueltig?* Ja. CH1
  `preChannelDynamics`: der Send greift vor `compressorBass` ab und laeuft
  nicht durch ihn — Stephans Option A, hier sogar strenger als gefordert,
  weil der Abgriff noch vor dem Kanal-Gain liegt. CH0/2/3 `postGain`: der
  Kanalfader wirkt ueber `SynthParams.spaceSendChannelGain`, denselben
  linearen Wert, der auf `gainX.outputVolume` geht. Nicht uebernommen wird
  die Pan-Position — die Kette ist mono-in, dort waere sie bedeutungslos.
- *Reihenfolge der Knoten im Renderzyklus?* AVAudioEngine sichert sie nicht
  zu, und der Bus ist so gebaut, dass sie egal ist: `accumulate` addiert,
  `drain` liest und nullt in einem Zug. Wird der Return-Knoten vor den
  Stimmen gezogen, verschiebt sich der Send um genau einen Block; danach um
  null. Jeder Block wird genau einmal verbraucht. Gemessen liegt der erste
  Raumbeitrag 198 Frames nach dem Note-On — exakt der erste
  Early-Reflection-Tap (4,1 ms), also kein Blockversatz.

**Am Graph aendert sich fast nichts.** `mainMixerNode` bekommt keinen neuen
Eingang; nur der bisher eingangslose Sammelbus bekommt einen. Das traegt
die Bit-Identitaet mit: bei stummem Send liefert die Kette exakt `0.0`, und
`0.0` in einem Float-Mixer ist bitgenau neutral.

**Gate 1, zweifach belegt.** (a) Szenario-Pruefsumme des
Atmospheric-Trockenpfads ueber 44,1/48/96 kHz mit Unison, Voice-Stealing,
Live-Parametern und All-Off: `0xd6fe9a8b93774ce7`, erzeugt VOR der ersten
geaenderten Codezeile und danach unveraendert. Sie sichert den Umbau ab,
der Atmospheric-Stimmen jetzt ueber einen Zwischenpuffer rendern laesst —
dieselben Additionen in derselben Reihenfolge, deshalb bitgenau. (b)
Vergleich des voll verdrahteten Graphen gegen den Graphen ohne Raum, Bit
fuer Bit gleich: beide Stimmtypen, alle drei Raten, zusaetzlich bei
Kanalfader 0 und fuer die Legacy-Stimme bei vollem Sendpegel.

**Gate 2.** Raumanteil bei Produkt-Sendpegel 23,7 dB unter dem
Trockensignal, gemessen als Differenzsignal `wet − dry` (moeglich, weil der
Trockenpfad bitgleich ist), monoton im Sendpegel, und nach dem Verstummen
der Stimme traegt die Fahne weiter. Nach `allNotesOff` faellt sie innerhalb
ihrer Abklingzeit unter die Stille-Schwelle (Peak im letzten
200-ms-Fenster eines 12-s-Renders: 4,4e−11). Der Raum wird bewusst nicht
hart zurueckgesetzt — das waere ein hoerbarer Schnitt. Kein Command im
Rendercallback loest `reset()` aus; die Aufrufliste der Render-Closure
enthaelt ausschliesslich `SpaceSendBus.drain` und
`AudioCoreDeepSpace.render`.

**Zweigpegel und Sendpegel bleiben vorlaeufig.** Der Sendpegel 0,5 traegt
dieselbe Begruendung wie die Zweigpegel je 0,5: er ist der einzige Wert des
Bereichs, der keine Praeferenz ausdrueckt. Einordnung fuer die
Entscheidung: die Kette ist statisch stark gedaempft (FDN-Ausgangsgain
0,125, Early-Reflection-Tapgains, Zweigpegel je 0,5) — selbst bei
Sendpegel 1,0 bleibt der Raum 17,7 dB unter dem Trockensignal. Mehr Raum
ist ueber diesen Regler allein nicht erreichbar; dafuer muesste an den
Zweigpegeln oder am Ausgangsgain gedreht werden.

**Realtime.** Zweiteiliger Nachweis plus Laufzeitmessung: 0
Allokations-Instruktionen und 0 dynamische Dispatches im SIL aller zwoelf
Renderpfad-Funktionen (beide `AVAudioSourceNode`-Closures eingeschlossen);
in den Aufruflisten nur die bekannten, hinter `cond_br` liegenden
`_ArrayBuffer._consumeAndCreateNew`-CoW-Slow-Paths. Laufzeit 0 ueber alle
Abschnitte inklusive 5.000 Bloecken reiner Hallfahne, Positivkontrolle
`prepare()` 6.383 und Zaehler-Selbstpruefung 2.000. `SpaceSendBus.drain`
hat als einzige Funktion des Pfads ueberhaupt keinen Verdachtstreffer.

**96-kHz-Luecke geschlossen, ohne Befund** — Details in `ROADMAP.md`,
W-03c-Ergebnis.

### Audio Milestone A4 - Instrument UX und Klangbank

| Slice | Inhalt | Gate |
|---|---|---|
| **S-10a** | Play View mit Preset, vier Makros, Sends und Panic | bestehende Mixer-/Settings-Funktion bleibt erreichbar |
| **S-10b** | Synth Lab fuer Sources/Shape/Modulation | kein UI-Zugriff aus dem Audio-Core |
| **S-10c** | Space-/Routing-Editor und Presetverwaltung | Save/Compare/Reset, Migration getestet |
| **S-11** | erste eigenstaendige Factory-Bank fuer vier Kanalrollen | musikalische Abnahme Stephan; keine Fremdassets |

### Audio Milestone A5 - Harmony und echte Raeumlichkeit

| Slice | Inhalt | Gate |
|---|---|---|
| **S-12** | typisierte Harmony-to-Sound-Snapshot-Grenze | Stephan entscheidet Mappings; DSP interpretiert keine Harmonik |
| **S-13a** | `SoundSourceID` und Positionssnapshot an der Output-Grenze | **Deep Review (On/Off-Vertrag).** Aendert den `AudioOutput`-Protokollvertrag selbst, von dem `OutputCoordinator`, `MIDIManager` und `AudioEngine` gemeinsam abhaengen. Note-Off-/Voice-Identitaet bleibt symmetrisch; bestehende `InteractionRuntime`-CH0-Snapshot-Garantien (Runde 038/039) duerfen nicht unterlaufen werden |
| **S-13b** | optionaler AVAudioEnvironmentNode-/Voice-Spatial-Prototyp | A/B-Spieltest; Stereo-Space bleibt Fallback |
| **S-14** | Granular-/Sample-Textur-Spike | Lizenz-, Asset-, Speicher- und Realtime-Entscheid |
| **S-15** | Shimmer-/Pitch-Feedback-Spike | Latenz-, CPU- und Stabilitaetsentscheid |

## 15. Entscheidungs-Gates

Vor produktiver Umsetzung von S-01:

1. **DSP-Weg**
   Empfehlung: eigener Swift/Accelerate-Kern, keine neue Dependency.

2. **Erste Klangquelle**
   Empfehlung: Wavetable-Morph + Noise/Textur; Granular spaeter.

3. **Default-Verhalten**
   Empfehlung: MIDI-/interner-Output-Default und bestehende Factory-Defaults
   bis S-11 nicht umstellen.

Vor S-10:

4. **UI-Richtung**
   Play View plus vertiefender Synth Lab oder nur erweiterter Mixer.
   Empfehlung: zwei Ebenen.

5. **Preset-Ort und Sharing**
   Nur Application Support oder zusaetzlich Dokumentexport.
   Empfehlung: intern zuerst, Export spaeter.

Vor S-12:

6. **Harmony-Mappings**
   Welche harmonischen Werte duerfen Motion, Color, Space und Focus bewegen?

Vor S-13:

7. **Raeumlichkeitsmodell**
   Kanalweites Stereo, per Ball oder hybride Gruppenpositionierung?

Querschnitt:

8. **Referenzhardware/CPU-Budget**
   Mac-Modell, minimale OS-Version, Zielbuffer und maximale Polyphonie.

9. **Drittanbieter**
   Jede neue DSP-/UI-Library braucht vorab Lizenz-, Wartungs- und
   Dependency-Entscheid.

10. **Offenes `bassHoldMode`-Verhalten**
    bleibt ein separater Audio-/Spielgefuehlentscheid und wird nicht
    nebenbei durch den Synth-Umbau veraendert.

## 16. Definition of Done

Der Atmospheric Synth und die Space Engine gelten erst dann als produktiv
integriert, wenn:

- vier Kanaele mit eigenen Presets und stabilen Makros spielbar sind;
- On/Off/Panic unter Last symmetrisch bleiben;
- der Audio-Thread weiterhin lock- und allokationsfrei ist;
- Presets versioniert, validiert, migrierbar und atomisch speicherbar sind;
- Legacy-Sounds erreichbar bleiben oder bewusst abgeloest wurden;
- EchoField und DeepSpace alle Stabilitaets-/Tail-/CPU-Gates bestehen;
- automatisierte Offline- und Integrationstests gruen sind;
- ein realer manueller Spieltest mit interner Audioausgabe bestanden ist;
- Stephan die Factory-Bank und die Makroreaktionen musikalisch abgenommen
  hat;
- keine fremden Markenassets, Presets, Samples oder UI-Kopien enthalten
  sind.

## 17. Nicht durch diese Planung geschlossen

- das offene V-02-DualSense-/30-Minuten-Live-Gate;
- die Releasefreigabe von V1;
- `bassHoldMode`-Toggle-Semantik;
- HarmonyWeb als App-Default;
- Art Direction des 3D-Raums;
- konkrete Harmony-to-Sound-Mappings;
- Granular-, Shimmer- oder echte per-Ball-3D-Audio-Freigabe;
- Push, Release, Tag oder Deployment.

## 18. Technische Referenzen

- Apple `AVAudioSourceNode` Render Block:
  <https://developer.apple.com/documentation/avfaudio/avaudiosourcenoderenderblock>
- Apple `AVAudioEngine` und Manual Rendering:
  <https://developer.apple.com/documentation/avfaudio/avaudioengine>
- Apple `AVAudioEnvironmentNode`:
  <https://developer.apple.com/documentation/avfaudio/avaudioenvironmentnode>
- Apple Accelerate/vDSP:
  <https://developer.apple.com/documentation/accelerate/vdsp-library>
- Apple `AVAudioUnitDelay`:
  <https://developer.apple.com/documentation/avfaudio/avaudiounitdelay>
- Apple `AVAudioUnitReverbPreset`:
  <https://developer.apple.com/documentation/avfaudio/avaudiounitreverbpreset>
- Native Instruments Absynth 5 Reference Manual, nur als historische
  Funktionsreferenz fuer Wellenform-Morphing und flexible Modulation:
  <https://www.native-instruments.com/fileadmin/drivers/absynth5/Absynth5_Reference_Manual_English.pdf>
