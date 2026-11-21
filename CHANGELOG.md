# CHANGELOG – HarmonyEngine3D

Alle nennenswerten Änderungen werden hier dokumentiert.
Format: [MAJOR.MINOR.PATCH] – Datum – Beschreibung

---

## Unreleased - Planung

### Projekt: GPLv3, öffentliches Repository, Produktrichtung Rev. 8 (21.11.2026)

- Lizenz GPLv3 wie FIRSTofFIFTH und Planarium (`LICENSE`,
  `THIRD-PARTY-NOTICES.md`, README-Abschnitt „Lizenz“).
- Besetzung wie Planarium: Claude Entwickler, Codex Zweitmeinung
  (`AGENTS.md`, `CLAUDE.md`).
- `ROADMAP.md`: neue Sektion „Produktrichtung Rev. 8“ mit den
  Owner-Entscheidungen vom 21.11.2026 und der Architekturanalyse.

### Feature: Der Klang ist am Controller formbar (W-05, Runde 074)

**Die Verdrahtungskette W-01 bis W-05 ist damit abgeschlossen.**

- `AudioCoreAtmosphericVoiceParameters.defaultModulationMatrix`: vier neue
  Makrorouten (Motion → Morphposition, Color → Filter, Space → Raumanteil,
  Focus → Quellen-Balance). Ohne sie war ein Makrowert wirkungslos — die
  Stimme reichte die Makros zwar in die Modulationsmatrix, aber es führte
  keine Route dorthin. Zuordnung, Amounts und die negative Richtung von
  `color` sind **vorläufig** und am Code begründet; sie weichen bewusst von
  `SYNTH_ARCHITECTURE_PLAN.md` 6.5 ab, weil drei der dort genannten
  Wirkungen (LFO-Tiefe, Stereo-Breite, Transienten) gar keine
  Modulationsziele sind.
- `SynthParams.macros` reist über den bestehenden Command-Pfad
  (`commandQueue` → `NoteEventQueue` `.paramUpdate` → `VoicePool.applyParams`).
  Kein neuer Ereignistyp, kein zweiter Serialisierungsweg, SPSC-Vertrag
  unberührt.
- Neu `Sources/HarmonyEngine3D/MIDIMacroMapping.swift`: Zuordnung CC-Nummer →
  Makro plus die Drossel dazwischen. Eine CC-Nummer gehört immer nur einem
  Makro; CC 120–127 sind nicht zuweisbar, weil sie im Router nie als Control
  Change ankommen. Eine unbelegte Nummer tut nichts und ist kein Fehler.
- **Gegen die CC-Flut Koaleszieren mit 20 ms Mindestpause**, nicht der
  30-ms-Debounce der Audio-Einstellungen: ein nachlaufendes Debounce gäbe
  während eines Reglerschwenks gar nichts aus. Gemessen bei 127 CC-Werten in
  einer Sekunde: ein Regler 508 → 168 `paramUpdate`-Ereignisse, vier Regler
  2.032 → 168; unter einer Flut von 2.000 CC/s hält die Rate bei 200. Im
  Leerlauf läuft kein Timer.
- `AudioEngine.applyMacroValues`: bildet die vier Kanal-Snapshots neu, wie
  `applyVoiceEngine` und aus demselben Grund (Config-Cache). Meldet genau
  einmal pro Sitzung, dass der erste CC angekommen ist.
- `AppSettings`: Zuordnung persistiert (`he3d.midiInput.macroCC.*`, −1 =
  nicht zugeordnet). Vorläufige Werksbelegung Motion CC 77, Color CC 74,
  Space CC 91, Focus CC 71.
- `ContentView.swift`: vier Zeilen „Regler → Makro" im Abschnitt
  MIDI-EINGANG (de/en).
- Nachträge aus dem Review der Vorrunde: die Lock-Haltedauer in
  `MIDIInputRouter.releaseNotes` ist als bewusste Entscheidung dokumentiert,
  und `MIDIInputManager` ist `@unchecked Sendable` mit der Liste der Felder,
  für die die Zusicherung gilt.

Ohne CC-Eingang ist der Klang bit-identisch zum Stand davor (per Test
belegt). Offen für Stephan: die vier Default-CC-Nummern, die Richtung von
`color` und die Makro-Ziel-Zuordnung insgesamt.


### Feature: MIDI-Eingang — der Synth ist spielbar (W-04, Runde 073)

- Neu `Sources/HarmonyEngine3D/MIDIInputRouting.swift`: CoreMIDI-freie
  Routing-Schicht. UMP-Dekodierung (inklusive `noteOn` mit Velocity 0 als
  `noteOff` und der Channel-Mode-Nachrichten mit Notenwirkung), Kanal-Politik,
  Quellenfilter und -aufloesung, getrennte Notenbuchfuehrung je Eingangsweg,
  Router auf das `AudioOutput`-Protokoll, CC-Register als Abholpunkt fuer W-05.
- Neu `Sources/HarmonyEngine3D/MIDIInputManager.swift`: CoreMIDI-Anbindung.
  Virtuelles Ziel „HarmonyEngine3D Input" (DAWs koennen an die App senden),
  Eingangsport mit Verbindung zu einer waehlbaren externen Quelle,
  Geraetelistung und Reaktion auf An-/Abstecken. Eigener MIDI-Client; der
  bestehende MIDI-Ausgang bleibt unveraendert.
- `AppSettings.swift`: neue `MIDIInputConfig` (Eingang aktiv, gewaehlte Quelle
  als `uniqueID` plus Anzeigename), persistiert wie die uebrigen Einstellungen.
  Ein gerade nicht vorhandenes Geraet loescht die Auswahl nicht.
- `ContentView.swift`: neuer Einstellungsabschnitt „MIDI-EINGANG" mit
  Geraeteauswahl und sichtbarem Verbindungszustand (de/en).
- `HarmonyEngine3DApp.swift`: Eingang bekommt denselben `AudioOutput` wie die
  Szene und wird ueber eine Combine-Subscription auf `AppSettings.midiInput`
  live nachgezogen.

**Der SPSC-Vertrag der `NoteEventQueue` ist unveraendert.** Der Eingang
schreibt nie selbst in die Queue, sondern ruft ausschliesslich `AudioOutput`;
bei `AudioEngine` legt das den Aufruf auf `commandQueue`, die weiterhin der
einzige Producer bleibt. An Queue und Vertrag wurde keine Zeile geaendert.

Zwei echte Fehler wurden waehrend der Runde gefunden und behoben:

1. **Ordnungsinversion im Anti-Haenger-Pfad** (vom Supervisor gemeldet):
   Buchung und Ausgabe lagen in getrennten kritischen Sektionen. CoreMIDI-
   und Main-Thread konnten sich so verschraenken, dass ein `noteOff` vor dem
   zugehoerigen `noteOn` bei `commandQueue` einreiht — die Note haette
   dauerhaft geklungen. Buchung und Ausgabe stehen jetzt unter demselben
   Lock, und das Trennen einer Quelle sperrt den Weg im selben Atemzug, in
   dem es aufraeumt.
2. **Gemeinsames Notenbuch fuer beide Eingangswege:** das Abziehen eines
   Keyboards haette die Noten beendet, die eine DAW ueber das virtuelle Ziel
   haelt. Die Buchfuehrung ist jetzt pro Weg getrennt.

Bewusst offen und dokumentiert: verschwindet ein Sender am *virtuellen Ziel*
mitten in einer Note (DAW-Absturz), gibt es dafuer kein CoreMIDI-Ereignis;
solche Noten enden erst mit Panic. Die Kanal-Politik ist vorlaeufig und
braucht eine Stephan-Entscheidung.

48 neue Tests, 740/740 gesamt gruen.

### Feature: DeepSpace am Send-Bus — auch der Raum ist hoerbar (W-03c, Runde 072)

- Neu `Sources/HarmonyEngine3D/SpaceSendBus.swift`: Software-Sammelbus
  zwischen den vier `SynthNode`-Renderpfaden und der gemeinsamen Raumkette.
  Nimmt den Ausgang jeder Atmospheric-Stimme mono-gefaltet und mit einer
  Pegelrampe auf, gibt ihn in einem Zug an den Leser weiter und nullt sich
  dabei. Keine Allokation, kein Lock.
- Neu `Sources/HarmonyEngine3D/DeepSpaceReturnNode.swift`: `AVAudioSourceNode`
  mit der W-02-Kette `AudioCoreDeepSpace`, angeschlossen an den seit S-07a
  vorbereiteten, bis jetzt stillen `sharedSpaceSendBus`.
- `AudioEngine.swift`: haengt Sammelbus und Return-Knoten in den Graph
  (nach `engine.start()`, nie aus einem Rendercallback) und setzt den
  vorlaeufigen Produkt-Sendpegel. **`mainMixerNode` bekommt keinen neuen
  Eingang** — nur der bisher eingangslose Sammelbus bekommt einen.
- `SynthNode.swift`: Atmospheric-Stimmen rendern ueber einen in `prepare()`
  angelegten Zwischenpuffer. Von dort geht ihr Signal unveraendert in die
  Kanalsumme und pro Stimme mit `spaceSendLevel` gewichtet in den Send.
  Der Legacy-Pfad ist unberuehrt und speist den Raum nicht.
- `SynthParams.swift`: zwei neue Felder, `spaceSend` (Basispegel des
  Modulationsziels) und `spaceSendChannelGain` (Kanalfader auf dem
  Sendweg). Beide Defaults sind die neutralen Werte des Werttyps
  (`0` bzw. `1`), nicht der Produktwert — dieselbe Trennung wie bei
  `voiceEngine`. Dadurch bleibt jede bestehende Baseline unveraendert
  gueltig.
- **Bei `spaceSend = 0` ist der Ausgang bit-identisch zu `4278cf6`**, fuer
  beide Stimmtypen und alle drei Sample-Raten — der Raum ist rein additiv.
  Bei Produkt-Sendpegel liegt er 23,7 dB unter dem Trockensignal und klingt
  nach `allNotesOff` von selbst aus.
- **Der Sendpegel 0,5 ist ausdruecklich vorlaeufig**, wie die Zweigpegel
  der Kette. Stephan entscheidet nach dem Hoeren.
- Tests: neu `DeepSpaceSendTests` (10 Tests), beide Baseline-Suiten um den
  real gefahrenen Betriebspunkt **96 kHz** erweitert — als eigener Test je
  Suite, **ohne einen bestehenden Erwartungswert anzufassen**. 692/692
  Gesamttests gruen.

### Feature: Atmospheric Voice ist Default — der Synth ist hoerbar (W-03b2, Runde 071)

- `Sources/HarmonyEngine3D/AppSettings.swift`: `AudioConfig.voiceEngine`
  ist `.atmospheric`, ebenso der Fallback in `load()`
  (Stephan-Entscheidung 2026-08-02). **Ab dieser Runde klingt beim Start
  die Atmospheric Voice.** Der Legacy-Pfad bleibt ueber dieselbe
  Einstellung waehlbar und klingt dann unveraendert; ein bereits
  persistierter Wert gewinnt gegen den neuen Default.
- `SynthParams.defaults.voiceEngine` bleibt bewusst `.legacy` — das ist
  kein halber Wechsel, sondern eine Trennung: `SynthParams` ist der
  Kanal-Snapshot, den die `AudioEngine` bildet, nicht der
  Einstellungsspeicher. Sein Default ist der neutrale
  Vorkonfigurationswert von `SynthNode.prepare()` und zugleich der Anker
  des Bit-Identitaets-Nachweises, dessen Szenariofolge unveraendert gegen
  `13e5eaf` uebersetzbar bleiben muss. Begruendet an der Deklaration, im
  Enum und im Test.
- `Tests/.../OfflineSynthBaselineTests.swift`: die S-01-Baseline waehlt den
  Legacy-Pfad jetzt ausdruecklich statt ueber einen Default. **Kein
  Erwartungswert angefasst**, 8/8 unveraendert gruen, Legacy-Pruefsumme
  unveraendert `0x86a4b146fd9f13e9`.
- Neu `Tests/.../AtmosphericSynthBaselineTests.swift`: eigene Baseline des
  neuen Pfads nach demselben Muster — Determinismus (auch ueber
  Voice-Stealing und Unison, weil der Texturseed an `activationOrder`
  haengt), Note-On/Off, All-Off, beide Sample-Raten, Parameterextreme ohne
  NaN/Infinity, festgehaltene Referenzmetriken (Peak 0,10232, RMS 0,02956,
  spektraler Schwerpunkt 2034 Hz gegen 305 Hz beim Legacy-Referenzton) und
  eine harte Pegelgrenze unterhalb Vollausschlag.
- Hoerprobe am Produktpfad, sachlich und ohne Klangurteil: zwei Akkorde mit
  Produkt-Defaults liefern Peak −8,5 dBFS / RMS −21,8 dBFS gegen −8,9 /
  −21,5 dBFS auf dem Legacy-Pfad — kein Lautheitssprung. Kein Sample
  >= 0,95, keine nicht-endlichen Samples, Peak im letzten 200-ms-Fenster
  exakt 0, Knacks-Indikator 1,30 gegen 1,23 (Legacy). Manueller App-Start
  ueber 55 s mit Autopilot: `voiceEngine → atmospheric` im Log, Noten auf
  CH0/CH1/CH2, kein Absturz, keine Fehlerzeile.
- Renderpfad bei beiden Einstellungen weiterhin allokationsfrei (0 ueber
  alle Messabschnitte, Positivkontrolle `prepare()` 71,
  Zaehler-Selbstpruefung 1.000/1.000). 11 neue Tests, `swift test`
  680/680 gruen.
- `ROADMAP.md` um den von Stephan freigegebenen **Audio-Track B
  (Klangvokabular)** ergaenzt — Filtermodi, Wellenformsatz/PWM,
  Ensemble/Chorus, Per-Stimme-Drift, Velocity als Modulationsquelle,
  optional Hardsync. Aktiviert wird er erst nach W-05.

### Feature: Stimmtyp umschaltbar, Legacy bleibt Default (W-03b1, Runde 070)

- Neu `Sources/HarmonyEngine3D/SynthVoiceEngine.swift`: Auswahl zwischen der
  Legacy-Stimme (`AudioCoreVoice`) und der Atmospheric Voice
  (`AudioCoreAtmosphericVoice`, W-01). **Default ist `.legacy` — diese Runde
  aendert den Klang nicht.** Das Kippen des Defaults ist W-03b2 und damit
  eine Klangentscheidung, die Stephan hoert und abnimmt.
- `Sources/HarmonyEngine3D/SynthNode.swift`: `VoicePool` haelt beide
  Stimmtypen gleichzeitig als getrennte Arrays konkreten Typs vor, beide in
  `prepare()` aufgebaut; ein Int-Tag sagt, welcher rendert. Der Renderpfad
  verzweigt einmal pro Block und laeuft danach in einer monomorphen Schleife
  — kein existentielles Boxing, kein dynamischer Dispatch, keine Allokation.
  Die Begruendung gegen Protokoll, Payload-Enum und generische
  Spezialisierung steht vollstaendig in `SynthVoiceEngine.swift`.
- Der Wechsel reist als Feld von `SynthParams` ueber den bestehenden
  Snapshot-/Command-Pfad (`AudioEngine.commandQueue` → `NoteEventQueue`
  `.paramUpdate` → `VoicePool.applyParams`). Er baut nichts auf: beide Pools
  existieren bereits. Vor dem Umlegen des Tags werden BEIDE Pools hart
  stillgelegt — ein Stimmtyp-Wechsel schneidet klingende Noten ab, statt sie
  im abgewaehlten Pool haengen zu lassen (der wuerde nicht mehr gerendert
  und käme nie aus seiner Release-Phase).
- `Sources/HarmonyEngine3D/AudioCoreMapping.swift`: schmale Abbildung
  `SynthParams` → `AudioCoreAtmosphericVoiceParameters` — die vier
  ADSR-Zeiten als Amp-Huelle sowie Filter-Cutoff und -Resonanz. Bewusst
  NICHT abgebildet: `waveform` (die Atmospheric Voice hat keine
  Wellenformauswahl; eine Zuordnung waere eine Klangentscheidung und gehoert
  zu W-05).
- `Sources/HarmonyEngine3D/AppSettings.swift`: `AudioConfig.voiceEngine`,
  persistiert unter `he3d.audio.voiceEngine`. Global fuer alle vier Kanaele.
  Neuer Umschalter im Einstellungsbereich "Audio-Ausgabe", sichtbar nur im
  Modus "Interner Sound" (de/en lokalisiert).
- **Klang bei Default-Einstellung bit-identisch zu `13e5eaf`** — belegt
  nicht per Metrik, sondern per rohem `Float.bitPattern`-Vergleich gegen
  einen separaten Klon dieses Commits: zwei Sample-Raten x fuenf Szenarien
  (Einzelnote, Unison mit Spread, Voice-Stealing ueber die Poolgroesse
  hinaus, Live-Parameter-Sweeps mitten im gehaltenen Ton, Parametergrenzen),
  Pruefsumme `0x86a4b146fd9f13e9`, als Regressionstest eingecheckt. Die
  S-01-`OfflineSynthBaselineTests` blieben unveraendert gruen; kein
  Erwartungswert wurde angefasst.
- Renderpfad bei BEIDEN Einstellungen allokationsfrei: SIL-Scan ueber alle
  201 Funktionen des Kompilats (Instruktionen UND demangelte Aufruflisten;
  kein `Set`, kein `Dictionary`, null `witness_method`/
  `open_existential_addr`/`alloc_existential_box`) plus Laufzeitmessung mit
  interponiertem `malloc` im echten `SynthNode`-Rendercallback: 0
  Allokationen ueber 2.000 Bloecke mit 16 klingenden Stimmen, ueber
  Voice-Stealing, `paramUpdate`, `noteOff`/`allNotesOff` und 50
  Stimmtyp-Wechsel mit klingenden Noten — je Stimmtyp. Positivkontrolle:
  `prepare()` zeigt 71 Allokationen, der Zaehler ist also nicht blind.
- 12 neue Tests, `swift test` 669/669 gruen.

### Fix: FDN-Tail vollstaendig renderthread-sicher (W-03a, Runde 068)

- `Sources/HarmonyAudioCore/AudioCoreDeepSpaceFDNTail.swift`: der
  Realtime-Vertrag gilt jetzt fuer den ganzen Typ, nicht nur fuer
  `process(left:right:)`. `setParameters(_:)` und `reset()` allozieren nicht
  mehr — beide werden beim Verdrahten (W-03b) voraussichtlich aus einem
  Command im Rendercallback ausgeloest und fallen damit unter denselben Hard
  Stop. Nur `init` und `prepare(sampleRate:)` allozieren noch; beide laufen
  ausschliesslich auf der Kontrollrate.
- Drei Stellen waren dafuer zu schliessen:
  1. Die Ausschlussliste der Primzahlwahl in `recomputeLineState()` war ein
     `Set<Int>` (4 Allokationen je `setParameters(_:)`-Aufruf, Finding
     W-02-01). Ersetzt durch einen festen Acht-Element-Puffer mit linearer
     Suche — bei acht Werten ohne Hashing und ohne Indirektion auch
     schneller als ein Set.
  2. `reset()` baute `writeIndex`/`dampingFilterState` mit
     `Array(repeating:count:)` neu auf (2 Allokationen je Aufruf, seit
     S-08b-fix als Vormerkung bekannt). Jetzt in place genullt.
  3. **Neu in dieser Runde gefunden:** zwei AUFGESCHOBENE Allokationen, die
     nicht in der aufrufenden Funktion anfielen, sondern erst im naechsten
     `process`-Aufruf — die Copy-on-Write-Kopie von `modPhase` nach
     `modPhase = modulationPhaseOffsets` (1 je `init`/`prepare`/`reset`,
     faellig im Rendercallback) und die faule `static let`-Initialisierung
     der beiden ueber `map` gebildeten Gewichtstabellen (2 einmalig je
     Prozess, faellig im allerersten `process`-Aufruf). Behoben durch
     elementweises Zuruecksetzen der Phase in den eigenen Puffer und durch
     Bindung der Renderkonstanten an die Instanz in `init`.
- **Klang unveraendert, bit-identisch zu `b7f26d1`** — belegt nicht nur per
  Unit-Test, sondern durch getrennte Kompilation beider Quellstaende gegen
  denselben deterministischen Treiber: 61.022 Stereo-Samples ueber 10
  statische Konfigurationen, vier Sample-Raten mit je zehn
  `setParameters(_:)`-Wechseln MITTEN im Render, `reset()`/`prepare()`
  mitten im Render, nicht-endliche Parameter und Sample-Raten sowie die
  vollstaendige W-02-Kette. Identische SHA-1
  `c1de1f911b342c2008ae8e7de0ab4e6d6ff543b1`.
- Der Allokationsnachweis ist ab dieser Runde dreiteilig: SIL-Scan auf
  Allokations-Instruktionen, SIL-Scan auf die **demangelten Aufruflisten**
  nach allozierenden Stdlib-Aufrufen, und eine Laufzeitmessung mit
  interponiertem `malloc`/`calloc`/`realloc`. Nur die Messung findet Fall 3:
  eine aufgeschobene Copy-on-Write-Kopie steht in keiner der beiden
  Aufruflisten, weil sie in einer ANDEREN Funktion faellig wird als der, die
  sie verursacht.
- Gegenprobe ueber alle 112 Funktionen der DeepSpace-Kette: die einzigen
  Funktionen mit Allokations-Instruktion oder allozierendem Stdlib-Aufruf
  sind `init` und `prepare(sampleRate:)` aller vier Typen — genau die, die
  duerfen.
- 3 neue Tests (657/657 gesamt), kein bestehender Test angepasst. Reine
  Ausfuehrungsform-Aenderung: keine Verdrahtung, keine Klangparameter,
  Zweigpegel, Primzahlwahl-Logik, Gains, RT60, Daempfung oder Matrixwerte
  beruehrt.

### Feature: DeepSpace-Kette zusammengeschaltet (W-02, Runde 067)

- `Sources/HarmonyAudioCore/AudioCoreDeepSpace.swift` und
  `AudioCoreDeepSpaceChainParameters.swift`: die drei seit S-08a/S-08b/S-08c
  einzeln getesteten Raumbausteine laufen erstmals als eine Kette. Topologie
  wie im Handoff vorgegeben: Eingang → Pre-Delay → parallel (Early
  Reflections | Diffusor → FDN-Tail) → Summe → Stereo-Ausgang. Reflexionen
  und Tail laufen parallel, der Diffusor speist ausschliesslich den Tail.
  Reine Core-Schicht — **noch nicht verdrahtet** (das ist W-03), kein
  bestehender Klang veraendert.
- Das Pre-Delay liegt jetzt in der Kette VOR der Aufteilung und verzoegert
  beide Zweige gleich. Die Early-Reflection-Stufe bekommt dafuer einen
  Parametersatz mit `preDelaySeconds = 0`; der Baustein selbst bleibt
  unveraendert. Ohne das waere das Pre-Delay auf dem Reflexionszweig doppelt
  und auf dem Tail-Zweig gar nicht wirksam.
- **Zweigpegel `earlyLevel`/`tailLevel` sind vorlaeufig auf je 0,5 gesetzt.**
  Gleiche Gewichtung ist der einzige Wert, der keine Klangaussage trifft;
  zugleich halbiert er den Summenpegel und ist damit headroom-freundlich fuer
  einen Send-Bus. Stephan hoert die Kette ab W-03 und entscheidet dann.
- Die Kette ist mono-in/stereo-out. Das ist keine Vereinfachung: die
  Early-Reflection-Stufe ist per Konstruktion mono-in und der FDN-Tail
  mittelt seinen Eingang intern sofort auf mono.
- Realtime-Vertrag zur Laufzeit gemessen (interponierter `malloc`-Zaehler,
  nicht nur SIL): `process` und `render` 0 Allokationen ueber 1.024.000
  Samples. Die eigenen Ruempfe von `reset()` und `setParameters(_:)` ebenfalls
  0.
- **Neuer Befund, gemeldet und nicht korrigiert (Nicht-Scope):**
  `AudioCoreDeepSpaceFDNTail.setParameters(_:)` alloziert 4 Mal pro Aufruf
  ueber das `Set<Int>` der Primzahlwahl in `recomputeLineState()`. Diese
  Stelle war fuer den bisherigen SIL-Textscan unsichtbar, weil die Allokation
  innerhalb der Standardbibliothek passiert. Zusammen mit der seit S-08b-fix
  bekannten `reset()`-Allokation (2 pro Aufruf) fuer W-03 vorgemerkt.
- CPU-Kosten auf der Referenzmaschine (MacBookPro18,1, Apple M1 Pro, 48 kHz,
  256er Bloecke, 3.000 Messbloecke nach 500 Aufwaermbloecken): Raumkette
  allein Median 248,9 ns/Sample = 83,7x Echtzeit, p99 71,8x, schlechtester
  Block 52,2x. 16 Stimmen plus eine Raumkette gemeinsam gemessen: Median
  17,2x, p99 15,4x, schlechtester Block 12,1x.
- 25 neue Tests (`Tests/HarmonyAudioCoreTests/AudioCoreDeepSpaceChainTests
  .swift`), davon vier reine Topologienachweise: die Zweige addieren sich
  exakt (parallel statt seriell), `diffusion` laesst den Reflexionszweig
  bit-identisch und veraendert den Tail-Zweig messbar (Diffusor sitzt richtig),
  das Pre-Delay verschiebt beide Zweige um exakt dieselbe Samplezahl, und
  beide Zweige sind einzeln bit-identisch zu ihren Einzelbausteinen.
  654/654 Gesamttests gruen.

### Feature: Atmospheric Voice zusammengesetzt (W-01, Runde 066)

- `Sources/HarmonyAudioCore/AudioCoreAtmosphericVoice.swift` und
  `AudioCoreAtmosphericVoiceParameters.swift`: erste spielbare
  Zusammenschaltung der seit S-04a einzeln getesteten DSP-Bausteine zu einer
  Stimme. Signalweg wie im Handoff vorgegeben: Quelle A / Quelle B / Textur →
  Mixer → State-Variable-Filter → Waveshaper → Amp-Huelle → Constant-Power-Pan
  → additive L/R-Akkumulation. Reine Core-Schicht — **noch nicht verdrahtet**,
  kein `SynthNode`/`AudioEngine`/`AppSettings`/UI-Bezug (das ist W-03), kein
  bestehender Klang veraendert.
- Alle sieben Ziele von `AudioCoreModulationTarget` kommen in der Stimme
  tatsaechlich an und haben je einen eigenen Wirkungsnachweis-Test.
  `spaceSend` ist der dokumentierte Sonderfall: er wird ueber
  `spaceSendLevel` nur nach aussen sichtbar gemacht und innerhalb der Stimme
  bewusst NICHT angewendet — belegt durch einen bit-exakten Vergleich.
- Modulationsrate: feste interne Kontrollrate (32 Samples, 1.500 Hz bei
  48 kHz) plus Glaettung aller sieben Ziele auf Audiorate ueber
  `AudioCoreParameterSmoother`. Die Kontrollperiode haengt an einem
  stimmeigenen Zaehler und NICHT an `frameCount` — derselbe Render liefert
  in 7er-, 256er- oder Ein-Stueck-Bloecken bit-identische Samples.
- Die aus der Legacy-Voice bewusst nicht uebernommene
  `updateLowpassCoefficients(b0:b1:b2:a1:a2:)` ist ersetzt: der Aufrufer
  uebergibt keine Biquad-Koeffizienten mehr, sondern per `setParameters(_:)`
  einen Cutoff-/Resonanzwert; die Stimme glaettet ihn und rechnet die
  SVF-Koeffizienten beim naechsten Kontrollschritt neu.
- Realtime-Vertrag per SIL belegt (`swiftc -O -wmo -emit-sil`):
  `render`, `configure`, `setParameters`, `reset`, `prepare` und `init`
  enthalten null Allokations-Intrinsics — inklusive der strengeren Suche nach
  `_ArrayBuffer._consumeAndCreateNew`, die im abgenommenen S-08b-fix-Stand
  noch als CoW-Slow-Path verbleiben durfte.
- CPU-Kosten einer Stimme auf der Referenzmaschine (MacBookPro18,1, Apple
  M1 Pro, 48 kHz, single-threaded): Median 59,3 ns/Sample = 351x Echtzeit,
  p99 66,3 ns/Sample = 314x, schlechtester Einzelblock 132,4 ns/Sample =
  157x. Hochrechnung auf 16 Stimmen: 21,9x (Median) / 19,6x (p99) / 9,8x
  (schlechtester Block).
- 23 neue Tests, 629/629 Gesamttests gruen (606 bestehend + 23 neu).
  `OfflineSynthBaselineTests` 8/8 unveraendert gruen — der bestehende Klang
  bewegt sich nicht.

### Fix: Layer-Katalog von `reference-core.json` deckt genutzte RelationTypes ab (Runde 065)

- `Sources/HarmonyShared/Resources/maps/reference-core.json`: der Layer
  `functional` deklarierte nur `["V-I", "ii-V"]`, seine Kanten nutzen aber
  zusaetzlich `commonTone` und `tritSubst` — `HarmonyMapValidator`-Warning
  `layerRelationTypeCatalogMismatch`. Katalog auf
  `["V-I", "ii-V", "commonTone", "tritSubst"]` ergaenzt (Stephan-
  Entscheidung 11, 2026-08-01). Die Kante bleibt operative Quelle: keine
  Kante, kein Node, keine Layer-Zugehoerigkeit geaendert — Diff betrifft
  ausschliesslich diese eine `relationTypes`-Zeile.
- Neuer Test `HarmonyBundleMapCatalogTests.
  test_allBundleMaps_layerCatalogCoversUsedRelationTypes`: prueft fuer alle
  vier mitgelieferten Bundle-Maps, dass der Layer-Katalog die auf ihren
  Kanten tatsaechlich genutzten RelationTypes abdeckt — kuenftige
  Abweichungen fallen jetzt im Build auf statt erst bei einem Smoke-Lauf.
- 606/606 Gesamttests gruen (605 bestehend + 1 neu). Normaler Build gruen.
  `git diff --check` gruen. Reiner Daten-/Testslice, kein Runtime-Pfad
  beruehrt (`HarmonyGraphEngine` filtert Kanten ueber `edge.layers`, nicht
  ueber `HarmonyLayer.relationTypes`).
- Offen fuer Stephan (nicht Teil dieser Runde): ob `tritSubst`/`commonTone`
  musikalisch in einen Layer namens `functional` gehoeren, ist eine
  inhaltliche Frage — dieser Slice dokumentiert nur den Ist-Zustand.

### Fix: `±1`-Ausgangsklemmung entfernt und `safeSampleRate`-Untergrenze (Runde 064)

- Zwei kleine, zusammengehoerige Korrekturen an den `DeepSpace`-Core-
  Bausteinen in `Sources/HarmonyAudioCore/`, beide auf unverdrahtetem
  Core-Code (die drei `DeepSpace`-Typen sind produktiv nirgends
  referenziert — nur zwei unveraenderte Kommentare in `AudioEngine.swift`).
- **Teil 1 (Stephan-Entscheidung 1, 2026-08-01):**
  `AudioCoreDeepSpaceEarlyReflections.process(_:)` klemmte den Ausgang
  bisher hart auf `±1`. Diese Wertebereichsklemmung ist entfernt, die
  `isFinite`-Absicherung (NaN/Infinity -> 0) bleibt bestehen. Begruendung:
  Diffusor und FDN-Tail klemmen nicht (Inkonsistenz), der Baustein ist fuer
  einen gemeinsamen Send-Bus gebaut, auf dem ein Zwischenwert ueber 1,0
  normal ist und erst nach Send-Pegel/Fader relevant wird, Begrenzung
  gehoert ans Ende einer Kette. Normalfall (Eingang <= 1,0) bit-identisch
  zu Commit `3c92919`, per FNV-1a-Checksum-Regressionstest belegt — die
  Klemmung griff dort ohnehin praktisch nie (Ausgangsspitze bei 0 dBFS
  Eingang ca. 0,238, Klemmung erst ab ca. +9,5 dBFS). Neuer Test belegt mit
  Eingangsfaktor 5, dass der Ausgang jetzt linear ueber 1,0 hinauslaeuft
  statt geklemmt zu bleiben.
- Angepasste Zusicherung: `test_earlyReflections_stereoOutput_
  isDefinedAndBounded` VERSCHAERFT die zuvor durch die Klemmung triviale
  Schranke `abs(value) <= 1.0` auf `abs(value) <= 0.3` — jetzt eine echte,
  aus der Tap-Gain-Struktur begruendete Aussage (analytisches Maximum
  `0,28 * 0,85 = 0,238`, `0,3` als dokumentierte Sicherheitsmarge).
- **Teil 2 (S-08c-Review-Beobachtung):** `safeSampleRate` hatte bisher nur
  eine Obergrenze. Unterhalb von ca. 0,7 Hz wird in
  `AudioCoreDeepSpaceFDNTail` der Modulations-Phasenzuwachs `>= 1`, der
  einfache Phasen-Wrap haelt `modPhase` dann nicht mehr in `[0, 1)` (kein
  Crash, aber degenerierende Modulation). Neue Konstante
  `AudioCoreDeepSpaceParameters.minSampleRate = 100.0` (rein technische
  Sicherheitsgrenze, ~140-facher Abstand zum 0,7-Hz-Problembereich, klar
  unterhalb jeder realen Audio-Hardware); `safeSampleRate(_:)` klemmt jetzt
  beidseitig. Bestehende Tests mit `sampleRate: 1` pruefen seither die
  Klemmung statt eines absurden Betriebspunkts (Handoff-Erlaubnis fuer
  diese eine Stelle); realistischer Bereich und S-08b-Sonderfaelle
  unveraendert gueltig.
- 6 neue Tests (4 `AudioCoreDeepSpaceTests`, 2 `AudioCoreDeepSpaceFDNTests`).
  605/605 Gesamttests gruen (599 bestehend + 6 neu). Normaler Build gruen.
  Strict-Concurrency-Build: dieselben 10 Bestandsdateibasenamen wie in
  Runde 054-063, keine neue Warnkategorie (596 Warnungen, identisch).
  Clean-HEAD-Build/-Test gruen (605/605). `git diff --check` gruen.
  SIL-Nachweis (`swiftc -O -wmo -emit-sil`): `process` bleibt
  allokationsfrei (0x `alloc_ref`/`alloc_box`/Array-Allokationsintrinsics),
  nur zwei guarded CoW-Uniqueness-Slow-Path-Aufrufe, wie in S-08b-fix/S-08c.
  Scope-Grep: keine neue Runtime-/UI-/`AudioEngine`-Referenz. Keine
  Aenderung an Tap-Zeiten, Tap-Gains, Stereo-Gewichten, Allpass-Delayzeiten,
  Linienlaengen, Matrixwerten, RT60-Formel oder Daempfungsmodell.
  `bassHoldMode` nicht beruehrt.

### Fix: haengende Bassnote beim Entladen eines nicht-aktiven Portals (Finding 062-01, Runde 063)

- Bestandsdefekt, durch Runde 062 sichtbar geworden: beim Entladen eines
  Chunks sendete `HarmonyScene.unloadChunk` das `bassNoteOff` nur, wenn das
  entladene Portal das gerade aktive war.
  `InteractionRuntime.removeBassOutputNote(forKey:)` trug den Key aber
  bedingungslos aus beiden internen Mengen aus — eine im Hold-Modus
  klingende Note eines NICHT aktiven Portals blieb beim Entladen ihres
  Chunks stumm haengen und war danach auch durch ein spaeteres Ausschalten
  von `bassHoldMode` nicht mehr erreichbar. Nur Panic konnte sie beenden.
- `removeBassOutputNote(forKey:)` liefert die Note jetzt nur noch zurueck,
  wenn sie zum Entladezeitpunkt tatsaechlich noch klang
  (`soundingBassNotesByKey`), statt des reinen `bassOutputNotesByKey`-
  Snapshots, dessen Eintraege ein `noteOff` ueberleben.
- `HarmonyScene.unloadChunk` sendet das Off jetzt fuer jede tatsaechlich
  klingende Note unabhaengig davon, ob das Portal aktiv war — der bisherige
  `portalActiveKey`-Check bleibt nur noch fuer das Zuruecksetzen des
  Triggers zustaendig, minimaler Eingriff in der SceneKit-Datei.
- 6 neue Tests in `PortalCloudInteractionRuntimeTests.swift` decken alle
  sechs Auftrags-Gates auf Runtime-Ebene ab (Kernfall, aktives Portal,
  Trigger-Modus-Gegentest, nie getriggertes Portal, Zusammenspiel mit
  Gate 10, Symmetriebilanz) — `HarmonyScene.unloadChunk` selbst bleibt
  SceneKit und wird nicht instanziiert; ein `simulateUnloadChunk`-Helper
  bildet exakt die neue, jetzt triviale `unloadChunk`-Logik nach.
- 599/599 Gesamttests gruen (593 bestehend + 6 neu). Normaler Build gruen.
  Strict-Concurrency-Build: dieselben 10 Bestandsdateibasenamen wie in
  Runde 054-062, keine neue Warnkategorie (596 Warnungen, identisch).
  `git diff --check` gruen. Kein `AppSettings`-Zugriff in
  `InteractionRuntime.swift` (Grep-Nachweis: nur Kommentare). Kein
  bestehender Portal-/Bass-Test musste angepasst werden. Gate-10-Verhalten
  aus Runde 062 unveraendert. Keine Aenderung an Chord-/Melody-Kanal-
  Unload, `OutputCoordinator`, `MIDIManager`, `AudioOutput`, `SynthNode`,
  `HarmonyAudioCore` oder UI.

### Gate 10 - Nachhol-noteOff beim Ausschalten von bassHoldMode (Runde 062)

- Stephan-Entscheidung 2026-08-01: schaltet man `bassHoldMode` waehrend
  einer gehaltenen Bassnote aus, wird jetzt ein Nachhol-`noteOff` gesendet,
  statt den Ton bis zum naechsten Portal-Trigger oder Panic haengen zu
  lassen (Fable-A12, seit V-00b offen).
- Neue explizite Menge tatsaechlich klingender Bassnoten je Portal-Key
  (`InteractionRuntime.soundingBassNotesByKey`) — bewusst NICHT ueber den
  bestehenden `bassOutputNotesByKey`-Snapshot geloest, dessen Eintraege
  beim `noteOff` nicht entfernt werden und sonst Geister-Offs fuer laengst
  verstummte Noten erzeugt haetten.
- `InteractionRuntime.updatePortal(_:)` erkennt den Uebergang
  `bassHoldMode` true -> false frame-uebergreifend (neues privates
  `previousBassHoldMode`) und sendet dann fuer jede klingende Note ein
  `bassNoteOff`, ausser fuer die Note des aktuell aktiven Portals — die
  bleibt wie im Trigger-Modus bis zum Verlassen klingen. Ist kein Portal
  aktiv, werden alle klingenden Noten freigegeben.
- `soundingBassNotesByKey` wird an allen relevanten Stellen mitgepflegt:
  Eintrag bei `bassNoteOn`, Austrag bei jedem `bassNoteOff` (Trigger-
  Verlassen, Nachhol-Off, `removeBassOutputNote` bei Chunk-Entladen,
  vollstaendig geleert bei `resetAll`).
- 7 neue Tests in `PortalCloudInteractionRuntimeTests.swift` decken alle
  neun Auftrags-Gates ab: Kernfall, Ausnahme fuer die aktive Note, mehrere
  gleichzeitig haengende Noten, keine Geister-Offs (`bassOutputNotesByKey`-
  Falle explizit reproduziert), Idempotenz bei wiederholtem Toggle,
  Symmetriebilanz explizit mit Zahlen, Determinismus ueber zwei identische
  Sequenzen.
- 593/593 Gesamttests gruen (586 bestehend + 7 neu). Normaler Build gruen.
  Strict-Concurrency-Build: dieselben 10 Bestandsdateibasenamen wie in
  Runde 054-061, keine neue Warnkategorie (596 Warnungen, identisch).
  `git diff --check` gruen. Kein `AppSettings`-Zugriff in
  `InteractionRuntime.swift` (Grep-Nachweis: nur Kommentare). Bestehendes
  Trigger-Modus-Verhalten unveraendert, kein bestehender Portal-/Bass-Test
  musste angepasst werden. Keine Aenderung an Chord-/Melody-Kanal, an
  `allNotesOff`/Panic, `OutputCoordinator`, `MIDIManager`, `AudioOutput`,
  `SynthNode`, `HarmonyAudioCore`, UI oder am Toggle-Ort selbst.

### S-08b - modulationsfreier FDN-Tail + Sample-Rate-Obergrenze (Finding S-08a-02, Runde 059)

- Teil 1 (Finding S-08a-02): `safeSampleRate` klemmte bisher nur nach
  unten. Eine endliche, aber absurd grosse Sample Rate (`1e300`) liess
  Pufferlaengen-Konvertierungen in `AudioCoreDeepSpaceEarlyReflections`/
  `AudioCoreDeepSpaceDiffuser` trappen (SIGTRAP).
  `AudioCoreDeepSpaceParameters.maxSampleRate` (1.000.000 Hz) plus eine
  gemeinsame `safeSampleRate(_:)` sind jetzt die eine Klemmstelle fuer die
  gesamte `DeepSpace`-Familie statt einer Kopie pro Typ.
- Teil 2: neuer modulationsfreier FDN-Tail in `Sources/HarmonyAudioCore/`
  (`AudioCoreDeepSpaceFDNParameters.swift`,
  `AudioCoreDeepSpaceFDNMatrix.swift`, `AudioCoreDeepSpaceFDNTail.swift`) —
  acht Delaylinien mit auf Primzahlen gerundeten, paarweise teilerfremden
  Laengen, eine energieerhaltende Ordnung-8-Hadamard-Feedback-Matrix, ein
  Ein-Pol-Tiefpass je Linie fuer frequenzabhaengige Daempfung und ein
  RT60-basierter Rundlauf-Gain je Linie — fuer jedes endliche `decay`
  streng unter 1, keine Selbstoszillation moeglich. Delaymodulation ist
  bewusst als S-08c nachgeschoben.
- Reine, entkoppelte `HarmonyAudioCore`-DSP-Infrastruktur: kein
  Zusammenschalten mit Early Reflections/Diffusor, keine Verbindung an
  `sharedEchoSendBus`/`sharedSpaceSendBus`, keine `AudioEngine`-/UI-/
  Runtime-Aenderung, kein Klang-/Default-Wechsel.
- 22 neue Tests (4 `AudioCoreDeepSpaceTests` fuer die Sample-Rate-
  Obergrenze, 18 neue `AudioCoreDeepSpaceFDNTests`): Impulsantwort finite
  bei maximalem `decay`, monotoner Fensterenergie-Abfall, isoliert
  getestete Matrix-Energieerhaltung/Orthonormalitaet, Selbstoszillations-
  grenze an zwei Extremen, bit-exakter Reset-/Instanz-Determinismus,
  Post-Init-Mutationspfad, Sample-Rate-Grenzen, frequenzabhaengige
  Daempfung, definierter Stereo-Ausgang, paarweise Teilerfremdheit,
  Speicherbudget.
- 570/570 Tests gruen (548 bestehend + 22 neu). Normaler Build gruen.
  Strict-Concurrency-Build: dieselben Bestandsdateien wie in Runde
  054-058, keine neue Warnkategorie. `git diff --check` gruen. Keine
  Runtime-/Default-/UI-Aenderung, `bassHoldMode` nicht beruehrt.

### S-08b-fix - Allokationen aus dem FDN-Renderpfad entfernt (Finding S-08b-01, Runde 060)

- Fix eines Supervisor-Deep-Review-Funds: `AudioCoreDeepSpaceFDNTail.process`
  alloziierte pro Sample auf dem Heap (zwei lokale Arrays plus ein drittes
  in `AudioCoreDeepSpaceFDNMatrix.apply`); der Dateikommentar, der das mit
  den bestehenden `[Float]`-Zwischenwerten in
  `AudioCoreDeepSpaceEarlyReflections`/`AudioCoreDeepSpaceDiffuser`
  rechtfertigte, war falsch (beide Bestandstypen haben in `process` keine
  einzige Array-Konstruktion) und ist jetzt korrigiert.
- Drei feste Scratch-Puffer (`delayedScratch`/`dampedScratch`/
  `matrixScratch`, Groesse 8), ausschliesslich in `init`/
  `prepare(sampleRate:)` angelegt, in `process` nur noch beschrieben.
- `AudioCoreDeepSpaceFDNMatrix` bekommt eine puffer-schreibende Form
  `apply(_:into:)`; die allozierende `apply(_:) -> [Float]` bleibt fuer
  Tests/Nicht-Renderpfad-Aufrufer bestehen, delegiert aber intern an
  `apply(_:into:)`.
- Die acht Delaylinien liegen nicht mehr als `[[Float]]` vor, sondern als
  ein flacher `[Float]`-Puffer mit festem Start-Offset je Linie
  (`lineOffset`) — robuster gegen CoW-Ueberraschungen, leichter beweisbar
  allokationsfrei.
- Nachweis per SIL (`swiftc -O -wmo -emit-sil`): 0x
  `_allocateBufferUninitialized`/`_allocateUninitializedArray`/`alloc_ref`/
  `alloc_box` in `process` und der inline-spezialisierten
  `apply(_:into:)`.
- Neuer Regressionstest `test_bitIdenticalOutput_matchesS08bBaselineChecksum`:
  deterministischer FNV-1a-Bit-Checksum ueber 4 Parameter-/Sample-Rate-
  Konfigurationen, vor dem Umbau auf Commit `4c49ed9` erzeugt
  (`0xb9d103fd6854a325`), nach dem Umbau bit-identisch reproduziert.
- Alle 18 bestehenden `AudioCoreDeepSpaceFDNTests` bleiben unveraendert
  gruen. 571/571 Gesamttests (570 bestehend + 1 neu). Normaler Build
  gruen. Strict-Concurrency-Build: dieselben 10 Bestandsdateibasenamen wie
  in Runde 054-059, keine neue Warnkategorie (596 Warnungen, identisch).
  `git diff --check` gruen. Reine Ausfuehrungsform-Aenderung: keine
  Aenderung an Linienlaengen, Primzahlwahl, Gains, RT60-Formel,
  Daempfungsmodell, Matrixwerten, Injektions-/Ausgangsgewichten. Keine
  Runtime-/Default-/UI-Aenderung, `bassHoldMode` nicht beruehrt.

### S-08c - dekorrelierte Delaymodulation im FDN-Feedbackpfad (Runde 061)

- `AudioCoreDeepSpaceFDNParameters` bekommt zwei neue 0...1-Felder,
  `modulationDepth` (Default `0.0` — kein Verhaltenswechsel fuer
  bestehende Aufrufer) und `modulationRate`.
- Acht per Kronecker-Folgen (goldener/silberner Schnitt) dekorrelierte
  Modulationsverlaeufe je Delaylinie (individuelle Rate UND individueller
  Phasenversatz) — kein rationales Frequenzverhaeltnis zwischen zwei
  Linien, also keine gemeinsame Periode/Schwebung.
- Rate konservativ auf `0,02...0,35 Hz` begrenzt (2,9...50 s Periode),
  Tiefe auf maximal 8 Samples, zusaetzlich je Linie dynamisch auf
  `lineLengthSamples - 1` gedeckelt (verhindert negative effektive
  Delayzeit bei sehr kurzen Linien).
- Fraktionale Leseposition mit linearer Interpolation
  (`AudioCoreDeepSpaceFDNTail.linearInterpolate(_:_:fraction:)`) —
  Konvexkombination der beiden Nachbar-Taps, kann die Amplitude der
  Quell-Samples beweisbar nie ueberschreiten; das bestehende
  S-08b-Stabilitaetsargument bleibt dadurch unveraendert gueltig.
- Kapazitaetsreserve statt Laufzeitklemmung: ein neues privates
  `baseCapacity` haelt die Linienlaengen-/Primzahlwahl byteidentisch zu
  Commit `01085ba`; `lineCapacity` ist rechnerisch bewiesen ausreichend
  fuer Basis-Delay plus maximalen Modulationshub plus Interpolations-Tap.
- Bit-Identitaet bei Modulationstiefe 0 (Kerngate): `process` verzweigt
  auf den textuell unveraenderten S-08b-fix-Lesepfad — bestehender
  Checksum-Test bleibt unveraendert gruen mit demselben Erwartungswert
  (`0xb9d103fd6854a325`).
- Kein `AudioCoreLFO`-Import (nicht Equatable, Zufallsformen unpassend) —
  eigener, kleiner Phasenakkumulator in `AudioCoreDeepSpaceFDNTail`
  selbst.
- Nachweis per SIL (`swiftc -O -wmo -emit-sil`): weiterhin 0x
  `_allocateBufferUninitialized`/`_allocateUninitializedArray`/`alloc_ref`/
  `alloc_box`/`swift_allocObject` in `process` und `apply(_:into:)`.
- 15 neue Tests (Stabilitaet bei maximaler Modulation, bit-exakter
  Determinismus mit aktiver Modulation, explizite Bit-Identitaet bei
  Tiefe 0, nachweisbare Wirksamkeit bei Tiefe > 0, Dekorrelation ueber
  Konstanten und Kanalkorrelation, Kapazitaetssicherheit ueber extreme
  Parameter-/Sample-Raten, Interpolations-Artefaktarmut, Post-Init-
  Mutationspfad, Regressionsschutz fuer `setParameters(_:)`).
- 586/586 Gesamttests (571 bestehend + 15 neu). Normaler Build gruen.
  Strict-Concurrency-Build: dieselben 10 Bestandsdateibasenamen wie in
  Runde 054-060, keine neue Warnkategorie (596 Warnungen, identisch).
  `git diff --check` gruen. Keine Aenderung an Linienlaengen, Primzahlwahl,
  Gains, RT60-Formel, Daempfungsmodell, Matrixwerten, Injektions-/
  Ausgangsgewichten oder an `reset()`s Allokationsverhalten. Keine
  Runtime-/Default-/UI-Aenderung, `bassHoldMode` nicht beruehrt.

### S-08a-fix - Parameterklemmung von setParameters(_:) bei den DeepSpace-Bausteinen nachgezogen (Finding S-08a-01, Runde 058)

- Fix eines Supervisor-Deep-Review-Funds: `AudioCoreDeepSpaceParameters`
  klemmt nur im `init`, `public var`-Felder erlaubten direkte
  Feldmutation nach Konstruktion, `setParameters(_:)` uebernahm die
  Struktur ungeklemmt. Verifizierter Trap (SIGTRAP) in
  `AudioCoreDeepSpaceEarlyReflections.recomputeTapDelays()` bei
  nicht-endlichem `size`/`preDelaySeconds`, sowie ein Diffusor-Runaway
  bei `diffusion > 1`.
- `setParameters(_:)` baut den Parametersatz bei beiden Typen jetzt ueber
  den bestehenden `init`-Klemmpfad neu auf (kein Klemm-Duplikat).
  Zusaetzlicher redundanter Endlichkeits-Guard direkt vor der trappenden
  `Double -> Int`-Konvertierung in `recomputeTapDelays()` — dasselbe
  zweistufige Muster wie S-04a-fix.
- 7 neue Tests (`AudioCoreDeepSpaceTests`): Post-Init-Mutations-Cartesian
  fuer beide Typen, expliziter Regressionstest fuer den verifizierten
  Trap-Fall, zwei Diffusor-Runaway-Tests ueber den Mutationspfad, zwei
  Bit-identisch-Nachweise fuer unveraendertes Verhalten im gueltigen
  Bereich.
- 548/548 Tests gruen (541 bestehend + 7 neu). Normaler Build gruen.
  Strict-Concurrency-Build: dieselben Bestandsdateien wie in Runde
  054-057, keine neue Warnkategorie. `git diff --check` gruen. Keine
  Runtime-/Default-/UI-Aenderung, keine Tap-Zeiten-/Gains-/Stereo-
  Gewichte-/Allpass-Delay-/`maxCoefficient`-Aenderung, `bassHoldMode`
  nicht beruehrt.

### S-08a - DeepSpace Early Reflections + Eingangs-Diffusoren als reine HarmonyAudioCore-DSP-Infrastruktur (Runde 057)

- Neu in `Sources/HarmonyAudioCore/`: `AudioCoreDeepSpaceParameters.swift`
  (gemeinsamer Parametertyp: Pre-Delay 0...0.1 s, Size, Early-Reflection-
  Mix, Diffusion, je 0...1, defensiv geklemmt),
  `AudioCoreDeepSpaceEarlyReflections.swift`,
  `AudioCoreDeepSpaceDiffuser.swift`.
- `AudioCoreDeepSpaceEarlyReflections`: sieben feste, deterministische
  Reflection-Taps ueber einen Ringpuffer, Tap-Zeiten skaliert mit `size`
  zwischen 15 ms und 150 ms plus Pre-Delay, geometrisch fallende Gains
  (konservative Summe < 1), festes Stereo-Gewichtungsmuster. Endliche
  FIR-Impulsantwort ohne Rueckkopplung. Feste Pufferallokation bei
  `init`/`prepare(sampleRate:)`.
- `AudioCoreDeepSpaceDiffuser`: vier in Serie geschaltete Schroeder-
  Allpass-Stufen je Kanal, links/rechts mit unterschiedlichen
  Verzoegerungszeiten fuer Stereo-Dekorrelation, Koeffizient strikt unter
  `0.65` begrenzt. Ein DSP-Fehler in der ersten Version (Ausgangsterm
  nutzte den rohen statt des rueckgekoppelten Werts, dadurch kein
  echtes Unity-Gain-Allpass mehr) wurde per Testbefund gefunden und
  korrigiert.
- 16 neue Tests (`AudioCoreDeepSpaceTests`): finite/endliche/begrenzte
  Impulsantwort, Reset-/Instanz-Determinismus, nicht-endliche/extreme
  Parameter und Sample-Raten, Diffusor-Stabilitaet bei maximaler
  Diffusion ueber 50.000 Samples, deterministisches Pre-Delay, definierter
  Stereo-Ausgang.
- 541/541 Tests gruen (525 bestehend + 16 neu). Normaler Build gruen.
  Strict-Concurrency-Build: dieselben Bestandsdateien wie in Runde 056,
  keine der drei neuen `AudioCoreDeepSpace*`-Dateien in der Warnliste,
  keine neue Warnkategorie. Clean-HEAD-Build/-Test gruen. Kein
  `EchoField`-/FDN-DSP, keine Verbindung an `sharedSpaceSendBus`, keine
  `AudioEngine`-/`AppSettings`-/UI-/Runtime-Aenderung, kein Klang-/
  Default-Wechsel.

### S-07b - Drei-Tap-Delay-Settings in versioniertes EchoField-Presetmodell migriert (Runde 056)

- Neu in `Sources/HarmonyEngine3D/AudioPreset/`: `EchoFieldPreset.swift`
  (`EchoFieldTap`, `EchoFieldPreset` mit exakt vier benannten, stabil
  geordneten Tap-Slots `tap1`…`tap4`), `EchoFieldPresetValidator.swift`,
  `EchoFieldPresetCodec.swift`, `EchoFieldPresetFactory.swift`,
  `EchoFieldLegacyMigration.swift` — reine `Foundation`-Abhaengigkeit,
  kein AVFAudio-/SwiftUI-/SceneKit-Import.
- `ChannelFXConfig.echoFieldPreset(...)` migriert die heutigen
  `delay1/2/3Time/Feedback/Mix/Pan`-Felder feldgenau, ohne Formel-Rundung,
  in `tap1`/`tap2`/`tap3`. `AudioSynthPreset.echoFieldPreset(...)` bietet
  denselben Migrationspfad ueber das bestehende S-03-Presetmodell — beide
  Pfade liefern nachweislich identische Taps. Tap 4 ist ueberall
  deterministisch `EchoFieldTap.neutral` (stumm, kein Feedback).
- `EchoFieldPresetFactory.legacyPresets`: alle vier heutigen
  `ChannelFXConfig.*Defaults` (Chord/Bass/Melody/ChordTone) als
  validator-akzeptables `EchoFieldPreset`, stabile IDs (`legacy.echo.*`).
- `EchoFieldPresetValidator`: Zeitbereich `0.001...4.0` s
  (Plan-Zielwert, Abschnitt 7.2), Feedback/Mix `0...1`, Pan `-1...1`,
  nicht-endliche Werte blockieren. Zusaetzlich ein dedizierter,
  blockierender `tapFeedbackRunawayRisk`-Error ab `feedback >= 1.0`.
- 25 neue Tests (`EchoFieldPresetTests`): Tap-Slots/Reihenfolge,
  feldgenaue Legacy-Migration aller vier Kanaele, Tap-4-Neutralitaet,
  Determinismus, Konsistenz beider Migrationspfade, Codable-Roundtrip
  inkl. striktem Scheitern bei Falschtypisierung, Validator-Grenzen inkl.
  Feedback-Runaway-Grenzwerttest.
- 525/525 Tests gruen (500 bestehend + 25 neu). Normaler Build gruen.
  Strict-Concurrency-Build: dieselben Bestandsdateien wie in Runde 055,
  keine der neuen `EchoField*`-Dateien in der Warnliste, keine neue
  Warnkategorie. Clean-HEAD-Build/-Test gruen. Kein `EchoField`-DSP, keine
  Verbindung an `sharedEchoSendBus`, keine `AudioEngine`-/`AppSettings`-/
  UI-/Runtime-Aenderung, kein Klang-/Default-Wechsel.

### S-07a - Audio-Graph auf gemeinsame Echo-/Space-Sends vorbereitet (Runde 055)

- `AudioEngine.setupGraph()`: zwei neue `AVAudioMixerNode`-Busse
  `sharedEchoSendBus`/`sharedSpaceSendBus`, attached und an
  `engine.mainMixerNode` angeschlossen — ein vorbereiteter, aber
  musikalisch inaktiver Graph-Rand fuer den spaeteren `EchoField`- (S-07b/
  S-09) und `DeepSpace`-Send (S-08). Kein Kanal speist diese Busse in
  diesem Slice; ohne Eingangssignal stumm, keine hoerbare Aenderung.
- Neu: `Sources/HarmonyEngine3D/AudioGraphTopology.swift` —
  `AudioGraphSendTapPoint`/`AudioGraphChannelSendPlan`/
  `AudioGraphSendTopology`, ein reiner, hardwareunabhaengiger
  Topologie-Deskriptor (kein AVFAudio-Import). Kodiert Stephans
  Option-A-Entscheidung (2026-07-30) fuer den CH1-Kompressor: der
  spaetere gemeinsame Send fuer CH1/Bass greift `.preChannelDynamics`
  (vor `compressorBass`) ab, alle anderen Kanaele `.postGain`. Verbindet
  in S-07a noch keine echten `AVAudioNode`s.
- Legacy-FX (vier kanalgetrennte Delay-/Reverb-Ketten inkl.
  `compressorBass`) unveraendert aktiv — keine bestehende
  `engine.connect(...)`-Zeile entfernt oder umgeschrieben.
- Graph-Aufbau ausschliesslich in `setupGraph()`/Init-Pfad; keine
  Aenderung an `SynthNode`, `NoteEventQueue`,
  `AudioEngine.commandQueue` oder `AudioOutput`-Protokoll.
- 5 neue Tests (`AudioGraphSendTopologyTests`): Plan deckt alle vier
  Kanaele ohne Duplikate ab, CH1-Option-A-Abgriffspunkt, Default-Abgriff
  fuer die anderen Kanaele, unbekannter Kanal liefert `nil`.
- 500/500 Tests gruen (495 bestehend + 5 neu). Normaler Build gruen.
  Strict-Concurrency-Build: dieselben Bestandsdateien wie in Runde 054,
  weder `AudioEngine.swift` noch `AudioGraphTopology.swift` in der
  Warnliste, keine neue Warnkategorie. Clean-HEAD-Build/-Test gruen.
  Kein Klang-/Default-/UI-Wechsel.

### S-06 - State-Variable-Filter, Send-Highpass und Waveshaper (Runde 054)

- Neu: `AudioCoreSVFMode`/`AudioCoreSVFParameters`/
  `AudioCoreStateVariableFilter` — stabiler State-Variable-Filter (Zero-
  Delay-Feedback-Topologie) mit Lowpass/Bandpass/Highpass aus einem
  gemeinsamen Zustandspaar (`Sources/HarmonyAudioCore/
  AudioCoreStateVariableFilter.swift`). Cutoff/Resonanz auf denselben
  Bereich wie `AudioCoreVoice.calcBiquadLowpassCoefficients` abgebildet
  (20...20.000 Hz logarithmisch, Q 0.5...20), Cutoff zusaetzlich defensiv
  auf sicheren Abstand zur Nyquist-Grenze begrenzt. `reset()` setzt nur den
  Filterzustand zurueck, Koeffizienten bleiben erhalten.
- Neu: `AudioCoreSendHighpassParameters`/`AudioCoreSendHighpass` —
  einfacher, eigenstaendiger Ein-Pol-Highpass fuer spaetere Echo-/Hall-
  Sends (`AudioCoreSendHighpass.swift`), engerer Cutoff-Bereich (5...2.000
  Hz) als der Voice-SVF, kein Resonanz-/Q-Parameter, unbedingt stabil.
- Neu: `AudioCoreWaveshaperParameters`/`AudioCoreWaveshaper` — zustandsloser
  `tanh`-Waveshaper mit Drive (0...1, intern auf Drive-Gain 1...20
  abgebildet) und Pegelkompensation (Division durch `tanh(driveGain)`
  vor `outputGain`), damit der Vollaussteuerungspegel ueber den Drive-
  Bereich stabil bleibt statt nur lauter zu werden (`AudioCoreWaveshaper.swift`).
- 18 neue Tests (`AudioCoreStateVariableFilterTests`, 7;
  `AudioCoreSendHighpassTests`, 5; `AudioCoreWaveshaperTests`, 6):
  Lowpass/Highpass-Frequenzverhalten, Bandpass-Selektivitaet um den
  Cutoff, Stabilitaet bei Cutoff-/Resonanz-/SampleRate-Extremwerten
  (inkl. NaN/Infinity/negativ/0), reproduzierbares Reset, Send-Highpass
  daempft tieffrequente Energie deutlich staerker als hochfrequente,
  Waveshaper bleibt bei extremen Eingaben endlich/begrenzt und symmetrisch,
  Pegelkompensation haelt den Vollaussteuerungspegel ueber den Drive-Bereich
  stabil, Parameter-Clamping fuer nicht-endliche/ausserhalb liegende Werte,
  Determinismus.
- Reine `HarmonyAudioCore`-DSP-Infrastruktur, noch nicht in
  `AudioCoreVoice`/`SynthNode`/Presets/UI/`AppSettings` verwendet — kein
  Klang-/Default-/UI-Wechsel.
- 495/495 Tests gruen (477 bestehend + 18 neu). Normaler Build gruen.
  Strict-Concurrency-Build: keine neue Warnkategorie, keine der drei neuen
  `HarmonyAudioCore`-Dateien in der Warnliste. Clean-HEAD-Build/-Test gruen.

### S-05b - Feste Modulationsmatrix und vier Performance-Makros (Runde 053)

- Neu: `AudioCoreMacroID`/`AudioCoreMacroValues` — die vier stabilen
  Performance-Makros Motion/Color/Space/Focus
  (`Sources/HarmonyAudioCore/AudioCoreMacroID.swift`,
  `AudioCoreMacroValues.swift`). Werte defensiv auf `0...1` geklemmt,
  nicht-endliche Eingaben fallen auf `0` zurueck.
- Neu: `AudioCoreModulationTarget` — feste, interne Zielmenge (Morph-
  Position, Textur-Pegel, Filter-Cutoff, Mix-Tiefe, Amp-/Mod-Huellentiefe,
  Space-Send-Platzhalter) statt freier Strings
  (`AudioCoreModulationTarget.swift`).
- Neu: `AudioCoreModulationSource`/`AudioCoreLFOSlot`/`AudioCoreEnvelopeRole`
  — typisierte Referenz auf Makro, einen der drei S-05a-LFOs oder die Amp-/
  Mod-Huelle, ohne dass die Matrix selbst eine `AudioCoreLFO`-/
  `AudioCoreEnvelope`-Instanz haelt.
- Neu: `AudioCoreModulationRoute` — eine statische Route (Source, Target,
  bipolarer Amount `-1...1`, an/aus). `AudioCoreModulationSourceValues`
  (laufender Wertesnapshot) und `AudioCoreModulationTargetValues`
  (Auswertungsergebnis, sieben feste `Float`-Felder statt Dictionary) sind
  bewusst getrennte Typen — statische Routenbeschreibung vs. laufender
  Modulationszustand.
- Neu: `AudioCoreModulationMatrix` — feste Routenliste, hoechstens 16
  aktive Routen (deterministisch auf die ersten 16 in Eingabereihenfolge
  gekuerzt). `evaluate(sources:)` summiert aktivierte Routen deterministisch
  auf ihr Ziel, ueberspringt deaktivierte Routen, klemmt jedes Ziel
  abschliessend auf `[-1, 1]` und bleibt garantiert endlich. Leere Matrix
  liefert definiert alle Ziele `0`.
- Neu: `AudioCoreParameterSmoother` — wiederverwendbarer, deterministischer
  One-Pole-Glaettungsbaustein fuer Makro- oder Zielwerte. Explizite
  Samplerate/Zeitkonstante statt globaler Uhr/Tempo-Sync,
  `reset(to:)`/`setTarget(_:)` reproduzierbar, monotone Annaeherung an ein
  konstantes Ziel, `timeMs <= 0` wirkt als sofortiger Sprung.
- 18 neue Tests (`AudioCoreMacroValuesTests`, 5; `AudioCoreModulationMatrixTests`,
  8; `AudioCoreParameterSmootherTests`, 5): vier Makros mit stabiler
  Reihenfolge/Identitaet, Clamping/Nicht-endlich-Fallback, bipolares
  Route-Amount-Clamping, 16-Routen-Grenze mit deterministischer Truncation,
  Determinismus, deterministische Akkumulation mehrerer Routen auf
  dasselbe Ziel, deaktivierte Routen ohne Wirkung, definierter leerer
  Matrix-Fall, finite/begrenzte Zielwerte bei Extremeingaben,
  reproduzierbares Reset und monotone Smoothing-Annaeherung.
- Reine `HarmonyAudioCore`-Daten-/DSP-Infrastruktur, noch nicht in
  `AudioCoreVoice`/`SynthNode`/Presets/UI/`AppSettings` verwendet — kein
  Klang-/Default-/UI-Wechsel.
- 477/477 Tests gruen (459 bestehend + 18 neu). Normaler Build gruen.
  Strict-Concurrency-Build: keine neue Warnkategorie, keine der elf neuen
  `HarmonyAudioCore`-Dateien in der Warnliste. Clean-HEAD-Build/-Test gruen.

### S-05a - Amp-/Mod-Huelle und drei LFOs (Runde 052)

- Neu: `AudioCoreEnvelope`/`AudioCoreEnvelopeParameters` — eigenstaendiger
  ADSR-Huellkurven-Baustein (`Sources/HarmonyAudioCore/AudioCoreEnvelope.swift`,
  `AudioCoreEnvelopeParameters.swift`), getrennt von den ADSR-Feldern in
  `AudioCoreSynthParameters`. Nutzt den bestehenden `AudioCoreADSRStage`-
  Automaten weiter. Amp- und Mod-Huelle sind derselbe Typ mit getrennten
  Instanzen/Parameterprofilen. `noteOn(sampleRate:)` berechnet Raten
  deterministisch neu, `noteOff()` startet aus jeder aktiven Stage eine
  kontrollierte Release-Phase, `reset()` reproduziert denselben Verlauf.
- Neu: `AudioCoreLFO`/`AudioCoreLFOParameters`/`AudioCoreLFOShape` —
  LFO-Baustein mit Sine, Triangle, Sample-and-Hold und geglaettetem Random
  (`Sources/HarmonyAudioCore/AudioCoreLFO.swift` u. a.). Frequenz auf
  `0...200 Hz` begrenzt (kein Audio-Rate-Oszillator). Sample-and-Hold/
  geglaetteter Random nutzen einen expliziten xorshift64-Zustand
  (identisches Muster zu `AudioCoreTextureSource`); `resetPhase(to:)`
  (Key-Sync) und `resetRandomState(to:)` sind getrennte Reset-Operationen.
- Beide Bausteine sind reine Value-Typen ohne Singleton/globalen Zustand —
  fuer per-Voice- UND globale Nutzung geeignet. Noch keine
  Modulationsmatrix/Makros (S-05b).
- 13 neue Tests (`AudioCoreEnvelopeTests`, 6; `AudioCoreLFOTests`, 7):
  samplegenaue Stage-Uebergaenge bei 44.1/48 kHz, kontrollierte Release aus
  jeder Stage, `reset()`-Reproduzierbarkeit, unabhaengige Amp-/Mod-Profile;
  Sine-/Triangle-Werte und -Periode, Sample-and-Hold-Konstanz pro
  Hold-Periode, geglaetteter Random endlich/begrenzt/deterministisch,
  Reset-/Key-Sync-Reproduzierbarkeit, Extremparameter finite.
- Reine `HarmonyAudioCore`-DSP-Infrastruktur, noch nicht in
  `AudioCoreVoice`/`SynthNode` verwendet — kein Klang-/Default-/UI-Wechsel.
- 459/459 Tests gruen (446 bestehend + 13 neu). Normaler Build gruen.
  Strict-Concurrency-Build: keine neue Warnkategorie, keine der fuenf neuen
  `HarmonyAudioCore`-Dateien in der Warnliste. Clean-HEAD-Build/-Test gruen.

### S-04b - Source B, Texture Source C und sichere Mixmodi (Runde 051)

- Neu: `AudioCoreSourceB` — zweite, unabhaengige Morph-Oszillator-Quelle
  (`Sources/HarmonyAudioCore/AudioCoreSourceB.swift`). Wrappt einen eigenen
  `AudioCoreMorphOscillator`, ergaenzt Transposition in Halbtoenen
  (`-24...24`), Feinstimmung in Cent (`-100...100`) als reine Hz-Skalierung
  und eigene Phase/Reset-Logik. Kennt weder MIDI noch Harmonie/Akkorde.
- Neu: `AudioCoreTextureSource` — deterministische, gefaerbte Rauschquelle
  (`Sources/HarmonyAudioCore/AudioCoreTextureSource.swift`). Expliziter
  xorshift64-RNG-Zustand (kein Sampleimport, kein Dateizugriff, kein
  Granular), One-Pole-Tiefpass-Farbfilterung ueber `brightness`, Koeffizient
  immer in `(0, 1)` fuer garantierte Stabilitaet, Pegel ueber `level`
  geklemmt auf `0...1`.
- Neu: `AudioCoreMixer` — feste, typisierte Mixmodi
  (`Sources/HarmonyAudioCore/AudioCoreMixer.swift`): linearer Mix A/B/C mit
  geklemmten Gains, Ringmodulation A x B mit Tiefenregler, sowie eine
  bewusst reduzierte, patchgraph-freie `.softPhaseModulation`-Variante
  (`a + depth * sin(pi * b)`) statt echter Audio-Rate-Oszillatorkopplung.
  Output immer endlich und auf `[-1, 1]` geklemmt.
- 25 neue Tests (`AudioCoreSourceBTests`, `AudioCoreTextureSourceTests`,
  `AudioCoreMixerTests`): Transposition/Cent-Frequenzfaktoren, eigene
  Phase/Determinismus fuer Source B; Determinismus bei gleichem Seed,
  unterschiedliche Seeds, Extremparameter finite/pegelkontrolliert fuer
  Texture C; deterministischer linearer Mix, geklemmte Gains, Ringmodulation
  und reduzierte Phasenmodulation endlich/begrenzt fuer den Mixer.
- Reine `HarmonyAudioCore`-DSP-Infrastruktur, noch nicht in `AudioCoreVoice`/
  `SynthNode` verwendet — kein Klang-/Default-/UI-Wechsel.
- 446/446 Tests gruen (421 bestehend + 25 neu). Normaler Build gruen.
  Strict-Concurrency-Build: keine neue Warnkategorie, keine der drei neuen
  `HarmonyAudioCore`-Dateien in der Warnliste. Clean-HEAD-Build/-Test gruen.

### S-04a-fix - Nicht-endliche Phase im Wavetable-/Morph-Oszillator-Pfad (Runde 050)

- Fix: `AudioCoreWavetable.sample(phase:mipLevelIndex:)` und
  `AudioCoreMorphOscillator.resetPhase(to:)` bilden eine nicht-endliche
  Phase (`.nan`/`.infinity`) jetzt VOR dem `truncatingRemainder`-Wrapping
  auf `0` ab, statt eine trappende `Double -> Int`-Konvertierung zu
  riskieren (Supervisor-Review von S-04a fand den Randfall; `Int(Double.nan)`
  ist in Swift ein Fatal Error).
- Neu: 4 Regressionstests (`AudioCoreWavetableBankTests`:
  `sample(phase: .nan)`/`sample(phase: .infinity)`;
  `AudioCoreMorphOscillatorTests`: `resetPhase(to: .nan)`/
  `resetPhase(to: .infinity)` gefolgt von `nextSample()`) — fuehren den
  Pfad aus, an dem der Testprozess vor dem Fix fatal abgestuerzt waere.
- Keine Verhaltensaenderung fuer endliche Phasenwerte; bestehende S-04a-
  Funktionalitaet (Bandlimitierung, Pitch, Morph, Determinismus)
  unveraendert.
- 421/421 Tests gruen (417 bestehend + 4 neu). Normaler Build gruen.
  Strict-Concurrency-Build: dieselben 11 Bestandsdateien, keine neue
  Warnkategorie. Clean-HEAD-Build/-Test gruen. Keine Runtime-/Default-/
  UI-Verdrahtung (per Grep unveraendert bestaetigt).

### S-04a - Wavetable-Bank und bandlimitierter Morph-Oszillator A (Runde 049)

- Neu: `Sources/HarmonyAudioCore/AudioCoreWavetable.swift`
  (`AudioCoreWavetable`/`AudioCoreWavetableMipLevel`-Value-Speicher +
  Mip-Auswahl/Sample-Lesevorgang), `AudioCoreWavetableBank.swift` (kleine
  prozedurale Factory-Bank: `warmOdd`/`brightFull`, je 2048 Samples,
  7 bandlimitierte Mip-Stufen `[64,32,16,8,4,2,1]` Harmonische, additive
  Sinus-Synthese ohne Fremdassets/-Presets), `AudioCoreMorphOscillator.swift`
  (phasenkonsistenter Morph-Oszillator zwischen zwei Wavetables, Frequenz
  in Hz, `morph` 0…1).
- Reine `HarmonyAudioCore`-DSP-Infrastruktur: keine AVFAudio-/SwiftUI-/
  SceneKit-/AppKit-/CoreMIDI-/GameController-Abhaengigkeit, keine neue
  Fremddependency, keine Verwendung durch `AudioCoreVoice`/`SynthNode`,
  kein Runtime-/Default-/UI-Wechsel (per Grep verifiziert).
- Neu: 9 Tests (`AudioCoreWavetableBankTests`, 4; `AudioCoreMorphOscillatorTests`,
  5) — stabile IDs/power-of-two Tabellenlaenge/mehrere Mip-Stufen,
  Bandlimitierung per unabhaengiger Sinus-Projektion, Pitch-Genauigkeit
  bei 110/440/1760 Hz, Morph-Verhalten 0/0.5/1, Mip-Auswahl bei steigender
  Frequenz, finite Samples bei Extremparametern, Determinismus.
- 417/417 Tests gruen (408 bestehend + 9 neu). Normaler Build gruen.
  Strict-Concurrency-Build: dieselben 11 Bestandsdateien, keine neue
  `HarmonyAudioCore`-Datei betroffen. Clean-HEAD-Build/-Test gruen.
  Manueller App-Start (`swift run HarmonyEngine3D`) laeuft ohne Absturz.

### S-03 - Versioniertes Audio-Presetmodell (Runde 048)

- Neu: `Sources/HarmonyEngine3D/AudioPreset/` — `AudioSynthPreset`
  (schemaVersion/id/name/channelRole/optionale Metadaten + `synth`-/`fx`-
  Sektionen), `AudioSynthPresetCodec` (striktes Decoding, kanonisches
  JSON), `AudioPresetValidator` (strukturierte Issues im Stil von
  `HarmonyMapValidator`), `AudioPresetFactory` (vier Legacy-Presets aus
  `ChannelFXConfig.*Defaults`), `AudioPresetStore` (atomischer User-Store
  in Application Support, `directory:`-Injection), `AudioPresetLegacyMigration`
  (verlustfreie `ChannelFXConfig`-Konvertierung + reine
  `AudioCoreSynthParameters`-Ableitung).
- `Waveform` (`SynthParams.swift`) zusaetzlich `Codable` — rein additiv,
  keine Verhaltensaenderung.
- Reine Daten-/Persistenzinfrastruktur: kein Produktcode ausserhalb
  `AudioPreset/` referenziert die neuen Typen (per Grep verifiziert) —
  keine aktive Preset-Auswahl, kein Runtime-/Default-Wechsel,
  `AppSettings`/UserDefaults unveraendert.
- Neu: 23 Tests (`AudioSynthPresetTests`, `AudioPresetValidatorTests`,
  `AudioPresetFactoryAndMigrationTests`, `AudioPresetStoreTests`) — Codable-
  Roundtrip inkl. striktem Scheitern bei falsch typisierten Feldern,
  Validator-Issue-Sammlung/Error-vs-Warning-Blockierung, Factory-
  Stabilitaet, verlustfreie Legacy-Migration aller vier Kanal-Defaults,
  `AudioCoreSynthParameters`-Formelgleichheit, atomisches/deterministisches
  Store-Verhalten, Nachweis dass `he3d.`-UserDefaults-Keys unveraendert
  bleiben.
- 408/408 Tests gruen (385 bestehend + 23 neu). Normaler Build gruen.
  Strict-Concurrency-Build: dieselben 11 Bestandsdateien, inhaltlich
  identisches Warnungsprofil je Datei. Clean-HEAD-Build/-Test gruen.
  Manueller App-Start (`swift run HarmonyEngine3D`) laeuft ohne Absturz.

### S-02b - SynthNode auf HarmonyAudioCore umgeschaltet (Runde 047)

- `HarmonyEngine3D` haengt jetzt von `HarmonyAudioCore` ab (`Package.swift`).
  `SynthNode.VoicePool` rendert Stimmen ueber `[AudioCoreVoice]` statt
  `[SynthVoice]` — die alte, dupliziert DSP-Datei `SynthVoice.swift`
  (inkl. `ADSRStage`-Enum) wurde vollstaendig entfernt.
- Neu: `Sources/HarmonyEngine3D/AudioCoreMapping.swift` — schmales App-
  seitiges Mapping `Waveform -> AudioCoreWaveform` und
  `SynthParams -> AudioCoreSynthParameters` (alle elf Felder). Lebt im
  App-Target, weil der Core `HarmonyEngine3D` nicht importieren darf.
- `AudioCoreVoice` (`HarmonyAudioCore`) um drei kleine, fachlich benannte
  Methoden fuer die Pool-Integration ergaenzt: `note` read-only public,
  `updateLowpassCoefficients(...)` (Filter-Live-Update ohne State-Reset),
  `applySustainIfInSustain(...)` (Sustain-Live-Update nur in Sustain-Stage).
- Voice-Stealing, Unison-Verteilung (Detune-/Pan-Spread, `gainScale =
  1/√n`), Live-Filter/-Sustain-Semantik, `maxVoices`-Fixierung,
  `AVAudioSourceNode`-Erzeugung, Buffer-Nulling, Event-FIFO-Verarbeitung,
  `NoteEventQueue`, `AudioEngine.commandQueue`, `AudioOutput`,
  `OutputCoordinator` und MIDI-Kanalvertraege bleiben unveraendert.
- Neu: `Tests/HarmonyEngine3DTests/AudioCoreMappingTests.swift` (3 Tests —
  Waveform-/SynthParams-Mapping, alle elf Felder, Defaults-Aequivalenz) und
  `Tests/HarmonyEngine3DTests/LiveParameterUpdateTests.swift` (2 Tests —
  Live-Filter wirkt sofort ohne Voice-Neustart, Live-Sustain wirkt nur in
  der Sustain-Stage und nicht rueckwirkend auf eine laufende Decay-Phase).
- A/B-Nachweis: alle acht bestehenden `OfflineSynthBaselineTests` (S-01)
  bleiben unveraendert gruen, keine Toleranzanpassung noetig.
- 385/385 Tests gruen (380 bestehend + 5 neu). Strict-Concurrency-Build:
  identisches Warnungsprofil zu Runde 041/045/046 (480 Warnungen, dieselben
  11 Bestandsdateien, keine `HarmonyAudioCore`-Datei betroffen).
  Clean-HEAD-Build/-Test gruen. Manueller App-Start (`swift run
  HarmonyEngine3D`) laeuft ohne Absturz.

### S-02a - HarmonyAudioCore-Fundament (Runde 046)

- Neu: SwiftPM-Target `HarmonyAudioCore` (`Sources/HarmonyAudioCore/`) —
  reine DSP-Schicht ohne AVFAudio/SwiftUI/SceneKit/AppKit/CoreMIDI/
  GameController/App-Code-Abhaengigkeit, keine neue Fremddependency.
  `AudioCoreWaveform`, `AudioCoreADSRStage`, `AudioCoreSynthParameters`
  (Value-Modell, Defaults identisch zu `SynthParams`) und `AudioCoreVoice`
  (einzelne Stimme: Frequenzformel, alle vier Wellenformen inkl. PolyBLEP,
  ADSR-State-Machine, Biquad-Tiefpass, Constant-Power-Pan — behavior-nahe
  Portierung von `SynthVoice`, kein Voice-Pool/Voice-Stealing/Unison-
  Verteilung, das bleibt S-02b).
- Neu: `HarmonyAudioCoreTests`, 11 Tests — Defaults, Frequenzformel, ADSR-
  Timing bei 44.1/48 kHz, NoteOff/Release/Idle, alle Wellenformen finite,
  Filter-Bypass/-Extremwerte, Stereo-Pan-Gainverhaeltnisse, Determinismus,
  Baseline-Vergleich des Default-C4-Renders gegen die S-01-Legacy-Referenz.
- `HarmonyEngine3D` importiert `HarmonyAudioCore` noch nicht (per Grep
  verifiziert) — keine Runtime-/Klangaenderung, reines Parallel-Fundament.
- 380/380 Tests gruen (369 bestehend + 11 neu). Strict-Concurrency-Build:
  identisches Warnungsprofil zu Runde 041/045 (480 Warnungen, dieselben 11
  Bestandsdateien). Clean-HEAD-Build/-Test gruen (`Package.swift` und
  neues Target geaendert).

### S-01 - Offline-Render-Harness und Baseline-Metriken (Runde 045)

- Neu: `Tests/HarmonyEngine3DTests/Support/OfflineSynthHarness.swift` treibt
  den echten `SynthNode`-`AVAudioSourceNode`-Rendercallback ueber
  `AVAudioEngine.enableManualRenderingMode(.offline, …)` — keine
  Audio-Hardware, keine DSP-Duplikation, keine Klangaenderung. Events
  (`noteOn`/`noteOff`/`allNotesOff`/`paramUpdate`) werden frame-genau an
  `renderOffline`-Chunkgrenzen eingespeist.
- Neu: `Tests/HarmonyEngine3DTests/Support/OfflineSynthMetrics.swift`
  berechnet Peak/RMS/DC-Offset/nicht-endliche Samples/Gesamt-/Tail-Energie/
  Stille-Grenzen/Stereo-Korrelation/spektralen Schwerpunkt (erste
  Accelerate/vDSP-Nutzung in dieser Codebasis, ausschliesslich im
  Testtarget).
- Neu: `Tests/HarmonyEngine3DTests/OfflineSynthBaselineTests.swift`, 8
  Tests: Determinismus (bitgenau), Note-On/Off/All-Off-Symmetrie, 44,1 und
  48 kHz, Unison-/Stereo-Spread, Legacy-Referenzrender-Baseline mit
  begruendeten Toleranzen, vier Wellenformen an ADSR-/Filter-/Unison-
  Extremwerten ohne NaN/Infinity.
- 369/369 Tests gruen (361 bestehend + 8 neu). Strict-Concurrency-Build:
  identisches Warnungsprofil zu Runde 041 (480 Warnungen, dieselben 11
  Bestandsdateien, keine der neuen Dateien betroffen).
- Keine Aenderung unter `Sources/` oder `Package.swift` — reiner
  Testtarget-Zuwachs. Kein Fremd-Dependency (Accelerate ist ein
  System-Framework).

### SYNTH-00 - Atmospheric Synth und Space Engine

- `SYNTH_ARCHITECTURE_PLAN.md` als umfassenden Planungsentwurf ergaenzt:
  Klangziel, aktuelle Audio-Baseline, Zielarchitektur, Realtime-Vertrag,
  Morph-/Texture-Synthese, Modulationsmatrix, gemeinsame
  `EchoField`-/`DeepSpace`-Busse, Presetmodell, UI-Konzept, Teststrategie,
  Performance-Gates und Slices S-01 bis S-15.
- Eigenstaendige Absynth-inspirierte Richtung dokumentiert; kein 1:1-Klon
  und keine Uebernahme proprietaerer Presets, Assets, UI oder Algorithmen.
- Keine Produktcode- oder Klangverhaltensaenderung. Das offene
  V-02-Live-/DualSense-/30-Minuten-Gate bleibt bestehen.

## [3.9.9] – 2026-07-14

### Fix: Erste Reparaturrunde aus Stufe 3.9 (ROADMAP.md Rev. 6)

Phasen 3.9.1a–c umgesetzt — die drei hörbaren/deterministischen Fehler aus
`REVIEW_3.9.8.md`/`CODEX_REVIEW_3.9.8.md`, die in Rev. 5 fälschlich als
erledigt geführt wurden (`SYNTHESE_3.9.8.md`).

**3.9.1a — MIDI On/Off-Symmetrie (Chord + Bass):**
- `HarmonyScene.swift`: neue Snapshot-Dictionaries `chordOutputNotes`/`bassOutputNotes`.
  Die tatsächlich oktavverschobenen MIDI-Noten werden **einmal** bei Aktivierung
  berechnet und für das zugehörige Deaktivierungs-Event unverändert wiederverwendet —
  unabhängig davon, ob sich `chordOctaveShift`/`bassOctaveShift` (AppSettings) zwischen
  On und Off geändert hat. Vorher wurde der Shift bei On und Off unabhängig live
  gelesen → bei Änderung während eine Note klang, hängende Noten.
- `OutputCoordinator.swift`: CH0/CH1 wenden den Oktav-Shift nicht mehr selbst an —
  reiner Durchreicher, wie bereits bei CH2/CH3. `bassOctaveShift` aus `OutputConfig`
  entfernt (nicht mehr gelesen); `HarmonyEngine3DApp.swift` entsprechend angepasst.
- Fix sitzt bewusst in der Eventquelle (`HarmonyScene.swift`), nicht im
  `OutputCoordinator` — siehe Schichtenkorrektur in `ROADMAP.md` Phase 3.9.1a.

**3.9.1b — Deterministische Kandidatenauswahl:**
- `RuntimeHarmonik.swift`: Kandidaten vor der Auswahl stabil nach `(distance, id)`
  sortiert statt `min(by:)` auf einer Liste mit undefinierter Dictionary-Reihenfolge.
  Falscher Kommentar zu „stabiler Dictionary-Reihenfolge" entfernt.

**3.9.1c — Harmonischer Magnet zeitbasiert:**
- `FlightController.swift`: feste 85/15-Frame-Mischung durch
  `alpha = 1 - exp(-rate * dt)` ersetzt (vorher bei 120 Hz doppelt so stark wie bei
  60 Hz). Winkelgeschwindigkeit begrenzt (`harmonicMagnetMaxAngularSpeed`),
  NaN-/Zero-Length-Guards für Zielrichtung und Blend-Ergebnis ergänzt.

**Nicht Teil dieser Runde:** 3.9.1d (Trigger-Hysterese) — der Start-Trigger-Verdacht
ist laut `SYNTHESE_3.9.8.md` §7.2 noch nicht empirisch bestätigt.

Build erfolgreich (`swift build`), keine Warnungen. Kein manueller Spieltest in
dieser Session (Doku-Update folgt direkt aus Code-Review, kein UI-Zugriff).

**Nachtrag — Build-Selbstständigkeit (Codex-Handoff HE3D-CX-2026-07-14-006):**
Commit `1e574a5` (Phase 3.9.2) baute inhaltlich korrekt, aber nicht aus einem
sauberen `git archive HEAD` heraus — `ContentView.swift`/`HarmonyEngine3DApp.swift`
enthielten Referenzen auf `HarmonicDebugModel`/`HarmonicRadarView` (Debug-Radar,
R-Taste) und einen Easter-Theme-Toggle, die als lokale, nie gestagete
Nebenarbeit im Arbeitsbaum standen, aber beim `git add` der 3.9.2-Dateien
versehentlich mitgestaged wurden. Zusätzlich hing bereits `HarmonyScene.swift`
(unverändert seit Commit `a5e77c5`, 3.9.1d) von `AppSettings.render.easterTheme`
ab, das ebenfalls nie committed war — ein tieferliegender, älterer Riss als von
Codex ursprünglich vermutet. Reparatur: Radar-/Debug-Verdrahtung vollständig aus
`ContentView.swift` und `HarmonyEngine3DApp.swift` entfernt (Feature bleibt
funktional unberührt, da nie im Bundle committed); die fehlende
`easterTheme`-Property in `AppSettings.swift` nachgetragen (reine Datenhaltung,
Default `false`, keine UI-Anbindung — die Easter-Theme-Funktion selbst bleibt
außerhalb des Scopes). `git archive HEAD` + strict build laufen jetzt beide
erfolgreich.

**Nachtrag — Passiver Magnet löst keinen Start-Trigger mehr (Codex-Handoff
HE3D-CX-2026-07-14-007):** Der proximity-basierte Magnet in
`FlightController.applyMagneticForce` zog die Kamera bislang auch im
Stillstand (ohne jeden Spielerinput) aktiv zum nächsten Akkordknoten und
überschritt dabei nach ca. 1s `triggerArmDistance` — Folge: verzögerter,
ungewollter Auto-Trigger beim Start (offener Punkt aus 3.9.1d/Runde 005).
Fix: `update(deltaTime:)` ermittelt jetzt `hasPilotTranslationInput` aus dem
gebauten `InputState` (`forward`/`strafe`/`vertical` — reine Blick-/Stick-
Rotation und Bremsen zählen bewusst nicht) und reicht das an
`applyMagneticForce(dt:hasPilotTranslationInput:)` durch; der
proximity-basierte Abschnitt greift nur noch, wenn das Flag gesetzt ist. Der
separate harmonische Richtungskorrektur-Mechanismus (`harmonicMagnetTarget`)
sowie der komplette Autopilot-Pfad bleiben unverändert.

**Nachtrag — Anker/Render-Trennung, Fundament (Codex-Handoff
HE3D-CX-2026-07-14-008, Phase 3.9.3a):** `HarmonyScene.swift` führt
`chordAnchorPositions: [String: simd_float3]` als SceneKit-freie Anker-Registry
ein — einzige Quelle für musikalische Akkordpositionen (Trigger, Kandidatenwahl,
Magnetziel, Autopilot). Gesetzt an allen vier Erzeugungspfaden (Chunk-Betrieb,
JSON-Web-Preview, kuratiertes Layout, Harmony-Codex-Layout), gelöscht in
`unloadChunk(_:)`. Umgestellte Leser: `magnetTargetPosition`, `localChordNodes`,
`applyHarmonicDecision`, `updateChordProximity`, `updateChordVisibility`,
`buildChordPositionMap`. `SCNNode.position`/`simdWorldPosition` bleibt für
Rendering und Sichtbarkeit (`opacity`) bestehen, ist aber keine Datenquelle
mehr für harmonische Logik — künftige Render-Bewegung/Morphing kann Trigger
und Kandidatenwahl damit nicht mehr versehentlich beeinflussen. `renderPosition
== anchorPosition` für diese Runde; animierter Offset ist nicht Teil des
Scopes. Kleine Hilfsfunktion `simd3(_ v: SCNVector3)` in `SCNVector3+Math.swift`
ergänzt (Konvertierung, an mehreren Stellen wiederverwendet). Bass-Portale,
Edge-Line-Rendering, `RuntimeHarmonik` (weiterhin SceneKit-frei) unverändert.

**Nachtrag — Anker/Render-Trennung abgeschlossen (Codex-Handoff
HE3D-CX-2026-07-14-009, Phase 3.9.3a):** `HarmonyScene.swift` leitet
`SCNNode.position` für Akkordknoten jetzt explizit aus `chordAnchorPositions +
chordRenderOffsets` ab, statt es beim Erzeugen direkt auf die Ankerposition zu
setzen. Neue Registry `chordRenderOffsets: [String: simd_float3]` (Default
`.zero`) plus drei kleine Helfer: `chordRenderPosition(for:)` (liest Anchor +
Offset), `applyChordRenderPosition(key:)` (schreibt `SCNNode.position`),
`setChordRenderOffset(_:for:)` (aktuell ungenutzt — Infrastruktur für
künftiges Morphing ab Phase 3.9.4). Alle vier Erzeugungspfade registrieren
Anchor + Offset und rufen `applyChordRenderPosition(key:)` auf; `unloadChunk(_:)`
räumt `chordRenderOffsets` zusammen mit `chordAnchorPositions` auf. Zusätzliche
Härtung: `applyHarmonicDecision` verwendet keinen Fallback auf
`node.simdWorldPosition` mehr — fehlt der Anker für einen Kandidaten, wird
Magnetismus sauber gecleart statt auf Render-Position auszuweichen. Sichtbares
Verhalten bleibt unverändert (`offset` überall `.zero`), manuell verifiziert:
identische Trigger-Sequenz und -Distanzen in der JSON-Web-Preview wie vor 009.
Kein Morphing, kein Radar, keine 3.9.3b/3.9.3c-Arbeit. **Phase 3.9.3a ist
damit vollständig abgeschlossen.**

**Nachtrag — Semantisches Fundament + erster spielbarer Impuls (Codex-Handoff
HE3D-CX-2026-07-14-010, Phasen 3.9.3b/3.9.3c/3.9.3d/3.9.4a):**

- **3.9.3b — Layer-Mitgliedschaft:** `HarmonyNode` bekommt ein optionales
  `layers: [String]?` (fehlt in bestehenden Maps → weiterhin dekodierbar). Neue
  `HarmonyMap`-Extension `activeNodeIDs(in:)`/`isNode(_:activeIn:)` in
  `HarmonyModel.swift`: explizite Mitgliedschaft über `node.layers`, sonst aus
  `HarmonyEdge.layers` abgeleitet (source **oder** target, unabhängig von
  `directed`). `HarmonyScene.buildJsonWebLayout` baut nur noch die im aktiven
  Layer aktiven Nodes (`jsonWebLayer`, aus `HarmonyEngine3DApp` durchgereicht,
  default `"functional"`) — `Bbmaj7`/`Ebmaj7` (nur modal angebunden) erscheinen
  im functional Preview nicht mehr (12 von 14 Nodes, geloggt).
- **3.9.3c — Map-Pfad:** `HarmonyMapLoader.toChordNetwork(_:layer:)` filtert bei
  gesetztem Layer jetzt auch die Nodes (`activeNodeIDs(in:)`), nicht mehr nur
  die Kanten — GraphEngine und Legacy-Export sehen dieselbe Welt. Ungerichtete
  Kanten werden symmetrisch als zwei `EdgeData`-Einträge exportiert (Legacy-
  Format kennt kein `directed`; Autopilot traversiert sonst nur source→target).
  Neue private `warnAboutSemanticLoss(...)`: warnt einmalig/aggregiert, wenn
  `relationTypes`, Mehrfach-Layer-Zugehörigkeit oder `magnetProfile` beim
  Export verloren gehen.
- **3.9.3d — Validator:** `HarmonyMapLoader.validate` deutlich gehärtet — neue
  harte Prüfungen (doppelte Layer-IDs, `midiNotes` nicht leer, MIDI `0...127`,
  explizite Layer-Referenzen existieren, `layout3D` finite, Edge-`relationTypes`
  nicht leer, `weight.isFinite && weight > 0`, Layer-`relationTypes` nicht leer,
  global isolierte Nodes) plus zwei neue ℹ️-Warnings ohne Ladeabbruch (leerer
  Layer; explizit aktiver, aber im Layer kantenloser Node). Alle drei
  ausgelieferten Maps laden weiterhin unverändert.
- **3.9.4a — Impuls + Nachbarschafts-Antwort (erste Fassung):** Bei jeder
  Akkord-Aktivierung ruft `updateChordProximity` neu `triggerHarmonicImpulse(from:)`
  auf — nur im JSON-Web-Modus aktiv, sonst stabiler No-op. Gewichtung der
  Nachbarn aus Graph × Layer × `edge.weight` × Distanzdämpfung, deterministisch
  bei Gleichstand, harte Obergrenze `impulseMaxNeighbors = 4`. Reaktion ist
  ausschließlich `chordRenderOffsets` (linear zerfallende Amplitude über
  `impulseDecayDuration = 0.9s`, `impulseMaxOffset = 6` Einheiten) — Trigger,
  Distanzen, Kandidatenwahl und Notes bleiben ausschließlich an
  `chordAnchorPositions` gekoppelt. `updateProximity` bekommt dafür ein
  `deltaTime`-Argument (aus dem in `SceneKitView.Coordinator` bereits
  vorhandenen `dt`), rein für den Zerfall.

Kein Morphing-Regler, kein Radar, kein großer Layer-UI-Scope, kein
Autopilot-Rewrite. Build (normal + strict-concurrency + Clean-HEAD) erfolgreich;
manuell verifiziert per JSON-Web-Preview (Layer-Filterung, Semantikverlust-
Warnung, Impuls-Zielauswahl) und Explore-Default-Idle (keine Regression).

**Nachtrag — Gewichtete Kandidatenliste + Morphing-Regler + Kandidatenbetonung
(Codex-Handoff HE3D-CX-2026-07-15-011, Phasen 3.9.4b/3.9.4c, 3.9.4a abgerundet):**

- **3.9.4b — Gewichtete Kandidatenliste:** `HarmonyGraphEngine` bekommt
  `weightedTransitions(from:)` — dieselbe Kontext-Modulation wie
  `weightedChoice(from:)` (ii-V-Boost, Rückkehr-Dämpfung, Spannungserhalt),
  aber deterministisch ohne RNG (`[WeightedTransition]`: Kante + Zielknoten +
  `effectiveWeight`). `weightedChoice(from:)` selbst nutzt diese API jetzt
  intern (Verhalten unverändert, keine doppelte Gewichtslogik mehr). Neuer
  Wertyp `HarmonicCandidate` (`RuntimeHarmonik.swift`): `nodeID`, `chordName`,
  `distance`, `harmonicWeight` (Anteil am Graph-Gesamtgewicht, 0…1),
  `distanceWeight` (`1 / (1 + distance)`), `score` (Produkt beider). Pro
  Graph-Übergang wird der nächstgelegene lokale Node mit passendem
  Akkordnamen gesucht; `HarmonicDecision` bekommt ein neues Feld
  `candidates: [HarmonicCandidate]`, deterministisch sortiert (score
  absteigend, dann distance aufsteigend, dann nodeID aufsteigend), hart
  begrenzt auf `maxCandidates = 4` (konsistent mit `impulseMaxNeighbors`).
  `selectedNodeID`/`suggestedChord` sind jetzt der beste Kandidat statt eines
  separaten RNG-Vorschlags — vollständig deterministisch, konsistent mit der
  sichtbaren Liste. `weightedChoice(from:)` bleibt als API unverändert
  nutzbar, wird im RuntimeHarmonik-Entscheidungspfad aber nicht mehr
  aufgerufen.
- **3.9.4c — Morphing-Regler:** `RenderConfig.morphingIntensity: Double`
  (0.0…1.0, Default 0.0), persistiert unter `he3d.morphIntensity`, geklammert
  beim Laden. Schlanker Slider im bestehenden Abschnitt „RENDERING"
  (`ContentView.swift`, DE/EN-Lokalisierung ergänzt) — keine neue
  Panel-Architektur. `updateHarmonicImpulses` multipliziert den
  Render-Offset jedes Nachbarschafts-Impulses mit `morphingIntensity`; der
  Amplituden-Zerfall selbst läuft unabhängig weiter, ein späteres Hochregeln
  wirkt ohne Neuauslösung sofort. Kein `morphingSpeed`/`morphingDamping`.
- **3.9.4a abgerundet — Kandidatenbetonung:** Neuer render-only Zustand
  `chordCandidateGlow` in `HarmonyScene.swift`, gefüllt in
  `applyHarmonicDecision` aus `decision.candidates` (bester Kandidat volle
  Amplitude 1.0, weitere anteilig aus ihrem relativen Score), zerfallend über
  denselben Zeitpfad wie die Impulse (`impulseDecayDuration`). Nutzt
  `mat.emission.contents` auf der Akkordkugel — denselben Pfad wie
  `setChordHighlighted`/`setChordApproachGlow`, zeitlich nach der
  Annäherungs-Aktualisierung im selben Frame aufgerufen, sodass der Glow
  sichtbar Vorrang hat, ohne den Approach-Glow-Zustand dauerhaft zu
  überschreiben (`resetChordApproachGlow` bei Ablauf/neuer Entscheidung
  stellt den Basiswert wieder her). Bewusst **nicht** an `morphingIntensity`
  gekoppelt, da kein Positionsversatz. Kanten-Intensität bei
  `showNetworkEdges` bewusst nicht umgesetzt — `rebuildEdgeLines()` baut nur
  bei strukturellen Änderungen neu, ein flüssiges Pro-Frame-Update hätte eine
  zusätzliche Kanten-Referenzhaltung erfordert (siehe `ROADMAP.md`).
- **Code-Hygiene:** Kommentar in `HarmonyMapLoader.toChordNetwork(_:layer:)`
  korrigiert (symmetrische Legacy-Duplizierung ungerichteter Kanten gilt
  unabhängig von `layer`). `updateHarmonicImpulses` auf Collect-then-Mutate
  umgestellt (erst Updates/Removals sammeln, dann `chordImpulses` mutieren).

Kein Radar, keine Layer-Umschaltung, kein Identitätswechsel, kein
Autopilot-Rewrite, keine neue Map. Build (normal + strict-concurrency +
Clean-HEAD) erfolgreich; manuell verifiziert per JSON-Web-Preview
(Kandidatenliste im Log, plausibel und deterministisch), `morphingIntensity`
0.0 (kein Offset) und 0.6 (sichtbarer, korrekt zerfallender Offset, temporärer
Debug-Log vor Commit entfernt) sowie Explore-Default-Idle (keine Regression).

**Nachtrag — Semantische 3D-Anker für den JSON-Web-Modus, Phase 4.1a
(Codex-Handoff HE3D-CX-2026-07-15-012):**

- **Neue `SemanticHarmonyLayout` (HarmonyShared, SceneKit-frei):**
  `position(for: HarmonyNode) -> simd_float3`. `node.layout3D` gewinnt immer;
  ohne `layout3D` ein deterministischer Fallback ohne externen Zustand/RNG:
  XZ-Winkel aus `(root * 7) % 12` (Quintenzirkel-Reihenfolge — `root` ist in
  den vorhandenen Maps ein MIDI-Notennummer, die Formel arbeitet mod 12, die
  Oktave spielt also keine Rolle), Radius aus `function` (`tonic 0.55× …
  dominant 1.15×` von `baseRadius = 150`), Y aus `type` (`maj7 +18 … dim7 −30`,
  rein visuelle Staffelung).
- **`HarmonyScene.buildJsonWebLayout`** nutzt diese Funktion jetzt statt des
  bisherigen Index-Rings. Active-Layer-Filterung (3.9.3b) unverändert.
  Anker/Render-Invariante bleibt erhalten: `chordAnchorPositions` kommt aus
  der Layout-Funktion, `chordRenderOffsets` startet bei `.zero`,
  `applyChordRenderPosition` bleibt der einzige Render-Schreibpfad. Log zeigt
  jetzt die Layout-Quelle (`N mit layout3D`, `N semantischer Fallback`) statt
  eines festen Radius-Werts.
- **Kamera-Reset:** neue `cameraPosition(forAnchors:)` — einfache
  Bounding-Box über die Anker statt einer festen Position; bewusst keine
  echte Look-at-Berechnung (die Kamera behält nach dem Reset weiterhin
  Identitäts-Orientierung, Blick entlang -Z).
- **Maps unverändert:** `reference-core.json` war bereits dirty im
  Arbeitsbaum, `harmony-web-c-center.json`/`harmony-web-c-diatonic.json`
  sind untracked — alle drei bewusst nicht angefasst (keine ungefragten
  Änderungen an User-/Fremd-Dateien). Der semantische Fallback trägt die
  functional Preview vollständig ohne manuelle `layout3D`-Werte.
- **Kleine Review-Korrektur (aus Runde 011):** Kommentar zu
  `RenderConfig.morphingIntensity` präzisiert — der Wert wirkt aktuell
  ausschließlich auf die Nachbarschafts-Impulse, nicht auf die
  Kandidaten-Glow-Betonung (die ist bewusst nicht gekoppelt).

Keine Force-Directed-Relaxierung, keine Layer-UI, keine Art-Direction-
Entscheidung, keine Edge-Intensity-Nacharbeit, kein Identitätswechsel, kein
Autopilot-Rewrite, kein Umbau der klassischen Chunk-Generierung. Build (normal
+ strict-concurrency + Clean-HEAD) erfolgreich; manuell verifiziert per
JSON-Web-Preview (Layout-Quellen-Log, 12/14-Layer-Filter unverändert,
`Bbmaj7`/`Ebmaj7` weiterhin draußen, Positionen sichtbar semantisch statt
gleichmäßiger Ring, kein Kollisionsfall in der aktuellen Map, temporärer
Debug-Log vor Commit entfernt) sowie Explore-Default (unverändert, da
klassischer Chunk-Betrieb nicht Teil dieses Slices ist).

**Nachtrag — Harmonischer Magnet mit Profil/Score, Phase 4.2a
(Codex-Handoff HE3D-CX-2026-07-15-013):**

- **Neuer Werttyp `HarmonicMagnetInfluence`** (RuntimeHarmonik.swift,
  SceneKit-frei): `target: simd_float3`, `rateMultiplier`/
  `maxAngularSpeedMultiplier: Float`, `score: Float`, `preset:
  MagnetProfile.Preset?`. Bündelt Position + Magnet-Stärke in einem Wert,
  damit beide nie auseinanderlaufen können.
- **`HarmonicCandidate`** trägt zusätzlich `magnetPreset`/
  `magnetRateMultiplier`/`magnetAngularSpeedMultiplier`, abgeleitet aus
  `WeightedTransition.edge.magnetProfile?.preset`. Mapping: `weak` → rate
  0.70 / angular 0.75, `medium`/nil → 1.00 / 1.00, `strong` → 1.30 / 1.20 —
  zusätzlich moderat moduliert durch `scoreBoost` (0.85...1.15) aus
  `harmonicWeight` (nicht dem rohen `score`, dessen `distanceWeight`-Anteil
  bei realistischen Distanzen zu klein für einen Multiplikator wäre).
- **`HarmonyScene.magnetInfluence`** (computed, wie `magnetTargetPosition`):
  kombiniert live `chordAnchorPositions[id]` mit dem in
  `applyHarmonicDecision()` gesetzten `currentMagnetProfile`. Beide werden
  gemeinsam gesetzt/gelöscht (inkl. `reloadAllChunks()`).
- **`FlightController`** ersetzt `harmonicMagnetTarget: simd_float3?` durch
  `harmonicMagnetInfluence: HarmonicMagnetInfluence?`. Effektive Rate/
  Winkelgeschwindigkeit = Basis (`harmonicMagnetRateBase` 9.75 /
  `harmonicMagnetMaxAngularSpeedBase` 3.0 rad/s, unverändert aus 3.9.1c) ×
  Multiplikatoren, geklammert auf Rate 3...16 und Winkelgeschwindigkeit
  1...5 rad/s. Keine zusätzliche Kraft, kein Speed-Push — weiterhin reiner
  Richtungsblend, Proximity-Magnet (`magnetTarget`) und Autopilot
  unverändert.
- **`SceneKitView`**: `flightController.harmonicMagnetInfluence =
  scene.magnetInfluence` ersetzt die frühere Positions-Zuweisung.
- **Kleiner Kommentar-Fix (aus Runde 012):** veralteter Ringlayout-Doc-Block
  über `buildJsonWebLayout` (Radius 180, Kamera (0, 30, 240)) auf die
  semantischen Anker aus Phase 4.1a aktualisiert.

Keine übrigen K3-Krafttypen (`relMajMin`/`commonTone3` als eigene
Feldtypen), keine UI/Settings-Anbindung der Magnet-Parameter, kein
Identitätswechsel, kein Force-Directed Layout, kein Chunk-Integration-Umbau,
keine Layer-UI, keine Art Direction, keine Edge-Intensity-Visualisierung,
keine große Strict-Concurrency-Bereinigung. Build (normal + strict-
concurrency + Clean-HEAD) erfolgreich; manuell verifiziert per
JSON-Web-Preview (temporärer Aufruf von `RuntimeHarmonik.process()` +
`applyHarmonicDecision()` für mehrere Testakkorde, vor Commit entfernt):
`medium` (rate×0.95…0.97, angular×0.95…0.97) und `strong`
(rate×1.39…1.50, angular×1.28…1.38) klar unterscheidbar, `weak`
(Preset-Basis 0.70/0.75) über Kandidatenliste bestätigt, `.noSuggestion`
löscht `magnetInfluence` korrekt (`nil`) sowie Explore-Default unverändert
lauffähig.

**Nachtrag — Relationstyp-spezifische Magnetfelder, Phase 4.2b
(Codex-Handoff HE3D-CX-2026-07-15-014):**

- **Neuer Enum `HarmonicMagnetFieldKind`** (RuntimeHarmonik.swift,
  SceneKit-frei): `dominantResolution` (`.vToI`), `preDominantMotion`
  (`.iiToV`), `substitution` (`.tritSubst`), `relative` (`.relMajMin`),
  `commonTone` (`.commonTone`), `generic` (Fallback, praktisch nur
  `.parallelMajMin`-only-Kanten). Klassifiziert den musikalischen
  *Charakter* einer Kante, getrennt von `MagnetProfile.Preset` (bleibt
  primäre *Stärke* der Kante).
- **Deterministische Priorisierung** bei mehreren `relationTypes` auf
  einer Kante (`magnetFieldKind(for:)`): V-I → ii-V → tritSubst → relMajMin
  → commonTone → Fallback generic — exakt wie beauftragt.
- **`HarmonicCandidate`** trägt zusätzlich `relationTypes: [RelationType]`
  und `magnetFieldKind: HarmonicMagnetFieldKind`. Feld-Basismultiplikatoren
  (`fieldMultipliers(for:)`): dominantResolution 1.15/1.10,
  preDominantMotion 1.08/1.05, substitution 1.00/1.15, relative 0.90/0.85,
  commonTone 0.78/0.75, generic 0.85/0.80. Effektiv:
  `magnetRateMultiplier = presetBase.rate × fieldBase.rate × scoreBoost`
  (analog für angular) — Preset- und Feld-Effekt werden multipliziert,
  bleiben aber durch die bestehenden `FlightController`-Clamps (Rate 3...16,
  Winkelgeschwindigkeit 1...5 rad/s) begrenzt. Keine neue Kraftphysik, keine
  zusätzliche Beschleunigung — der bestehende Richtungsblend bleibt das
  einzige Verhalten.
- **`HarmonicMagnetInfluence`/`HarmonyScene.currentMagnetProfile`/
  `magnetInfluence`** erweitert um `fieldKind`/`relationTypes` (Debug/HUD-
  Weitergabe). `FlightController` bleibt unverändert — kennt weiterhin
  keine `HarmonyMap`, `HarmonyGraphEngine` oder `RelationType`, konsumiert
  ausschließlich die bereits kombinierten Multiplikatoren aus
  `HarmonicMagnetInfluence`.
- **Logs erweitert** (`[RuntimeHarmonik]`/`[Magnetism]`, weiterhin nur bei
  Akkordwechsel, nicht pro Frame): zeigen jetzt zusätzlich `field:
  <fieldKind> [<relationTypes>]` neben Preset und effektiven
  Multiplikatoren.
- **Kleiner Kommentar-Fix:** veralteter RuntimeHarmonik-Hook-Kommentar in
  `HarmonyEngine3DApp.swift` (`magnetTargetPosition`/„Magnetism strength
  intentionally constant in v1") auf `magnetInfluence` und die
  Preset-/Feld-/Score-Modulation aktualisiert.

Kein Identitätswechsel, keine Force-Directed-Relaxierung, keine
Chunk-Integration, keine Layer-UI, keine Settings-/Regler-UI für
Magnetparameter, keine Art Direction, keine Edge-Intensity-Visualisierung,
keine große Strict-Concurrency-Bereinigung, kein `HarmonyScene`-Split,
keine Änderung an dirty/untracked Map-Dateien. Build (normal + strict-
concurrency + Clean-HEAD) erfolgreich; manuell verifiziert per
JSON-Web-Preview (`harmony-web-c-diatonic`, temporärer Testaufruf, vor
Commit entfernt): `G7 → Cmaj7` (dominantResolution/V-I, rate×1.72
angular×1.52) klar stärker als `Fmaj7 → Cmaj7` (commonTone, rate×0.74
angular×0.71) und `Cmaj7 → Am7` (relative/relMajMin, rate×0.85
angular×0.80) — Feldwirkung sichtbar unterscheidbar und in der erwarteten
Reihenfolge. `.noSuggestion` löscht `magnetInfluence` weiterhin korrekt
(`nil`); Explore-Default unverändert lauffähig. `preDominantMotion`
(ii-V) und `substitution` (tritSubst) nicht als Top-Kandidat in den
verfügbaren Testakkorden beobachtet (siehe Offene Punkte/Rücklauf) —
über Code-Pfad-Identität mit den anderen Fällen sowie Kandidatenlisten-
Mitgliedschaft bestätigt.

**Nachtrag — F-01: Testfundament + Graph-Kontext repariert (Codex-Handoff
HE3D-CX-2026-07-26-015, Runde 015):** Erster Slice der operativen Rev.-7-
Roadmap (`ARCHITECTURE_REVIEW_2026-07-26.md`). Kein Feature-Ausbau — Test-
Target plus eine gezielte Bugfix in `HarmonyGraphEngine`.

- **Neues Target `HarmonySharedTests`** (`Package.swift`, `.testTarget`,
  hängt nur von `HarmonyShared` ab). 11 Tests in
  `Tests/HarmonySharedTests/` mit Inline-JSON-Fixtures (kein Bezug auf
  Bundle-/App-Maps): Decode einer gültigen `HarmonyMap`, gerichtete Kante
  nur source→target, ungerichtete Kante beidseitig, Layerfilterung,
  deterministische `weightedChoice`-Sequenz bei festem Seed,
  Rückkehr-Dämpfung, ii-V→V-I-Boost, Regel „zwei starke Transitionen"
  (Regressionsfall + Positivfall), parallele Kanten/mehrere Layer
  zwischen demselben Node-Paar deterministisch (order-independent,
  layer-aware).
- **Graph-Kontext repariert (`HarmonyGraphEngine.swift`):** `history`
  hielt bisher max. 2 Einträge — `lastEdge()`/`prevEdge()` fielen dadurch
  auf denselben Übergang zurück, und Regel 3 („2 aufeinanderfolgende
  starke Kanten → schwache Kante × 1.3") griff bereits nach einer
  einzigen starken Kante (Doppelzählung). `history` hält jetzt bis zu 3
  Einträge, sodass zwei aufeinanderfolgende Übergänge als zwei getrennte
  Kontexte (`lastTransition()`/`prevTransition()`) auflösbar sind. Regel 2
  (Rückkehr-Dämpfung) bleibt bewusst exakt auf die letzten 2 Schritte
  begrenzt (`history.suffix(2)`) — unverändertes Verhalten trotz größerem
  Puffer. Neue private `transitionContext(from:to:)` löst die Kante(n)
  eines historischen Übergangs layer-bewusst auf und aggregiert bei
  mehreren passenden Kanten (parallele Kanten oder mehrere Layer
  zwischen demselben Node-Paar) deren `relationTypes` als Vereinigung —
  ersetzt eine ordnungsabhängige `map.edges.first`-Auswahl. Öffentliche
  Signaturen (`weightedTransitions(from:)`, `weightedChoice(from:)`,
  `recordVisit(_:)`) unverändert.
- **`RelationType`** um `Hashable` ergänzt (Scope C, für `Set<RelationType>`
  in der Übergangs-Aggregation; Codable-Semantik unverändert).
- Regressionstest bestätigt manuell gegen den alten Code (`git stash` auf
  `HarmonyGraphEngine.swift`): schlägt dort fehl (1.3 statt 1.0), da ein
  einzelner Übergang fälschlich doppelt gezählt wird; mit dem Fix grün.
- Keine Änderung an dirty/untracked DesignerKit-, Map-, Radar-,
  AudioMixer-, Doku- oder Bilddateien. Kein Audio-/MIDI-/UI-/SceneKit-
  Bezug. Keine neue musikalische Gewichtungsregel.
- Checks: `swift test` grün (11/11), normaler `swift build` grün, Strict-
  Concurrency-Build (`-strict-concurrency=complete`) grün — keine neuen
  Warnungen in den geänderten/neuen Dateien (nur vorbestehende Warnungen
  in unveränderten Dateien wie `NetworkParser.swift`/`AppSettings.swift`).

**Nachtrag — F-02: Echter Audio-Producer-Datenrace behoben (Codex-Handoff
HE3D-CX-2026-07-27-016, Runde 016):** `NoteEventQueue` war als SPSC-Ringpuffer
dokumentiert ("Main Thread" als alleiniger Producer), real schrieben aber
mehrere Threads gleichzeitig hinein: der SceneKit-Render-Thread (Akkord-/
Bass-/Melodie-Events aus `HarmonyScene` → `OutputCoordinator` →
`noteOn`/`noteOff`), der GameController-Handler-Thread (CH3 Chord-Tones,
△-All-Notes-Off) und der Main Thread (Combine-Subscription
`AppSettings.$audio` → `applyEffectConfig*` → `SynthNode.updateParams`, sowie
`stopAll()`). Das war ein echter Datenrace auf `NoteEventQueue.writeIndex`,
kein reines Dokumentationsproblem.

- **`AudioEngine`** bekommt eine private serielle `commandQueue`
  (`DispatchQueue`) als alleinige Serialisierungsgrenze. Alle vier
  `AudioOutput`-Methoden (`noteOn`, `noteOff`, `allNotesOff(channel:)`,
  `allNotesOff()`) sowie der `SynthNode.updateParams()`-Aufruf in den vier
  `applyEffectConfig*`-Methoden laufen jetzt ausschließlich auf dieser einen
  Queue — unabhängig vom Aufrufer-Thread gibt es pro `NoteEventQueue` wieder
  genau einen Producer-Thread. Der Audio-Render-Thread (Consumer) bleibt
  unverändert lock-/allokations-/Concurrency-frei; die Closures fangen bewusst
  nur die konkrete `SynthNode`-Referenz ein, nicht `self`/`AudioEngine`, damit
  keine neuen Sendable-Warnungen entstehen (kleiner, gezielter Refactor,
  `synthNode(forChannel:)`-Helper extrahiert).
- **Reihenfolgegarantie (dokumentiert):** Aufrufe vom selben Thread behalten
  ihre Reihenfolge (GCD serialisiert `.async`-Submits pro Thread in
  Submit-Reihenfolge). Über verschiedene Aufrufer-Threads hinweg gilt
  Submit-Reihenfolge auf `commandQueue` — dieselbe (fehlende) Garantie wie
  vorher, jetzt aber racefrei statt Undefined Behavior.
- **`SynthNode`** um `@unchecked Sendable` ergänzt — begründet durch den bereits
  bestehenden, jetzt in der Kopfdokumentation präzisierten Aufrufer-Vertrag
  ("nur von `AudioEngine.commandQueue` aufzurufen"); keine interne
  Synchronisation nötig, der Compiler kann den Vertrag nur nicht selbst prüfen.
- **`NoteEventQueue`**: Kopfdokumentation korrigiert (Producer ist kein
  bestimmter benannter Thread, sondern "genau ein Thread — durchgesetzt von
  `AudioEngine.commandQueue`"). Overflow ist nicht mehr kommentarlos: neuer
  `droppedEventCount`-Zähler (nur vom Producer geschrieben, keine neue
  Synchronisation nötig) plus sofortiges, sichtbares Log speziell für
  verworfene `.noteOff`/`.allOff`-Events. Bewusst kein Lossless-Hard-
  Guarantee — das hätte eine Producer-seitige Verschiebung von `readIndex`
  erfordert und die Consumer-Alleinschreiberschaft auf diesen Index verletzt.
  Ring-Puffer-Logik (`writeIndex`/`readIndex`-Ownership) unverändert.
- **Keine hörbaren Änderungen:** kein Synth-Feature, kein neuer Klangparameter,
  keine geänderten Defaults, keine `AVAudioEngine`-Graph-Umbauten.
- **Neues Test-Target `HarmonyEngine3DTests`** (`Package.swift`,
  `@testable import HarmonyEngine3D`), 5 Tests für `NoteEventQueue` (reines
  Foundation, keine `AVFoundation`-Abhängigkeit): FIFO-Reihenfolge, leerer
  Puffer, Overflow verwirft + zählt, Wrap-Around über die Ringgrenze,
  `paramUpdate` trägt `SynthParams` korrekt. `SynthNode`/`AudioEngine` selbst
  bewusst nicht automatisiert getestet (echte `AVAudioEngine`-Graph-
  Konstruktion/Audio-Hardware-Abhängigkeit) — stattdessen Codepfad-Analyse
  (Scope A) plus Build-/Strict-Build-Nachweise.
- Checks: `swift test` grün (16/16), normaler `swift build` grün,
  Strict-Concurrency-Build grün — keine neuen Warnungen in den
  geänderten/neuen Dateien.

**Nachtrag — F-03: HarmonyMapCodec + strukturierter Validator (Codex-Handoff
HE3D-CX-2026-07-27-017, Runde 017):** `HarmonyShared` bekommt einen
öffentlichen, strukturierten Map-Codec und Validator; defekte optionale
Felder werden nicht mehr still verschluckt. Engine und (später) DesignerKit
können denselben Diagnose-/Validierungsvertrag nutzen.

- **Neuer `HarmonyMapCodec`** (`HarmonyMapCodec.swift`): Decode aus `Data`,
  `URL` und Bundle-Resource (`Bundle.module`-Default über `Bundle?`-Umweg, da
  SPM-generiertes `Bundle.module` `internal` ist und nicht direkt als
  Default-Parameterwert einer `public` Funktion stehen darf). Encode zu
  kanonischem JSON (`.sortedKeys` für deterministische Object-Key-Reihenfolge,
  `.prettyPrinted` für Lesbarkeit; Array-Reihenfolge bleibt exakt die
  Modell-Reihenfolge — `JSONEncoder` sortiert nur Objekt-Keys).
- **Striktes Decoding** (`HarmonyModel.swift`): `HarmonyNode.tags/layout3D/
  layers` und `HarmonyEdge.weight/magnetProfile/bridgesTo` nutzen jetzt
  `decodeIfPresent` statt `try?` — fehlende optionale Felder bleiben erlaubt
  (Default/`nil`), ein vorhandenes, falsch typisiertes optionales Feld wird
  jetzt ein Decode-Fehler statt still zu Default/`nil` zu werden. Minimale,
  präzise Änderung: `decodeIfPresent` leistet exakt die geforderte Semantik
  bereits eingebaut (Key fehlt → nil ohne Throw; Key vorhanden mit falschem
  Typ → Throw), keine eigene Fallback-Logik nötig.
- **Neuer `HarmonyMapValidator`** (`HarmonyMapValidator.swift`): portiert die
  bisher private, print-basierte Validierung aus `HarmonyMapLoader` in
  strukturierte `Issue`-Werte (`severity`, `code`, `objectPath`, `message`).
  Alle bisherigen Regeln unverändert (schemaVersion, doppelte IDs,
  Edge-Referenzen, midiNotes-Bereich, layout3D finite, relationTypes/weight
  gültig, Isolation), plus eine neue Regel (Scope C): Layer-Katalog
  (`HarmonyLayer.relationTypes`) gegen tatsächlich über `HarmonyEdge.layers`
  zugeordnete `relationTypes` — Kante bleibt operative Quelle, Abweichung ist
  `layerRelationTypeCatalogMismatch`-Warning, kein Error. `Result.isAcceptable`
  ist `true` bei ausschließlich Warnings (keine Blockade gültiger Runtime-Maps).
- **`HarmonyMapLoader.load(named:)`** ist jetzt dünner Adapter über Codec +
  Validator (alte private `validate(_:filename:)`-Funktion entfernt);
  Runtime-Verhalten unverändert (Errors → `nil` + sichtbare Diagnose, Warnings
  ohne Errors → Map zurückgegeben + sichtbare Diagnose). `toChordNetwork`
  unverändert.
- **Manuell verifiziert (temporärer Testaufruf, vor Commit entfernt):** alle
  drei bestehenden Bundle-Maps (`reference-core`, `harmony-web-c-center`,
  `harmony-web-c-diatonic`) laden weiterhin erfolgreich unter dem strikteren
  Decoding — keine Regression. Die neue Layer-Katalog-Warnung feuert dabei
  sinnvoll auf `reference-core.json` (Layer `functional` deklariert nur
  V-I/ii-V, nutzt aber auch commonTone/tritSubst) — rein informativ, blockiert
  das Laden nicht.
- **Neue Bundle-Fixture** `Resources/maps/harmony-map-loader-test-fixture.json`
  (klein, 2 Nodes/1 Edge, committet) ausschließlich für
  `HarmonyMapLoaderTests` — bewusst nicht die bestehenden untracked
  Bundle-Maps verwendet.
- **Neue Tests** (`Tests/HarmonySharedTests/`): `HarmonyMapCodecStrictDecodingTests`
  (7: Decode, kanonischer Roundtrip, Encode-Determinismus, fehlende optionale
  Felder erlaubt, falsch typisierte tags/weight/layout3D scheitern),
  `HarmonyMapValidatorTests` (5: gültige Map ohne Errors, mehrere Errors in
  einem Lauf gesammelt, Warnings blockieren Akzeptanz nicht, Layer-Katalog-
  Mismatch als Warning, kein Mismatch bei passendem Katalog),
  `HarmonyMapLoaderTests` (2: gültige Fixture lädt, unbekannter Dateiname
  liefert `nil`).
- Kein DesignerKit-Umbau, keine Migration alter `.txt`-Netze, keine neuen
  RelationTypes/MagnetProfile-Felder.
- Checks: `swift test` grün (30/30 — 16 bestehend + 14 neu), normaler
  `swift build` grün, Strict-Concurrency-Build grün — keine neuen Warnungen in
  den geänderten/neuen Dateien.

**Nachtrag — F-04: Baseline-Übernahme (Codex-Handoff HE3D-CX-2026-07-27-019,
Runde 019):** Reiner Baseline-/Reproduzierbarkeits-Slice, kein Feature-Slice.
Stephan hat entschieden (2026-07-27): der komplette damalige dirty/untracked-
Bestand gehört in die Baseline — nichts bewusst ausgeschlossen. Drei getrennte
Commits statt einem Sammelcommit:

- **Produktcode** (`91065df`): `DesignerCanvasView.swift`/`DesignerViewModel.swift`
  (HarmonyWeb-Anzeigemodus im Designer, read-only), `AudioMixerPanel.swift`
  (rein optisches Redesign, keine Logikänderung), neu `HarmonicDebugModel.swift`/
  `HarmonicRadarView.swift` (fertig gebautes Debug-Radar-Overlay, **noch nicht
  verdrahtet** — `FlightController.showHarmonicRadar`/Taste R existiert bereits,
  hat aber keinen Consumer; bewusst nicht verdrahtet, das wäre eine neue
  Runtime-Verknüpfung außerhalb des Baseline-Scopes). Kein Compile-Fix nötig,
  Build war bereits vorher grün. Kein Secrets-/Sicherheitsbefund (Review vor
  Commit).
- **Maps** (`6f0d85e`): alle drei bestätigten Bundle-Maps mit dem F-03-Codec/
  Validator geprüft (temporärer Testaufruf, vor Commit entfernt) —
  `reference-core.json` (7/11/2, eine `layerRelationTypeCatalogMismatch`-
  Warning, bewusst nicht repariert: fachliche Entscheidung, außerhalb des
  Scopes), `harmony-web-c-center.json` (8/22/2, keine Issues),
  `harmony-web-c-diatonic.json` (14/29/2, keine Issues). Keine Errors, keine
  Map-Reparatur nötig.
- **Projekt-/Planungs-/Guide-/Asset-Baseline**: `AGENTS.md`, `TEAM_RULES.md`,
  `CLAUDE.md`, `ARCHITECTURE_REVIEW_2026-07-26.md`, `ROADMAP.md` (F-01–F-04
  jetzt als erledigt markiert), `HarmonyNetwork_Spec_v1.md` (nicht einzeln in
  Stephans Aufzählung genannt, aber vom „kompletter aktueller Bestand"-Beschluss
  erfasst — reine Status-/Kommentar-Aktualisierung, keine Schemaänderung),
  Review-/Synthese-/Guide-Dateien, drei Bilder, sowie
  `.agent_handoff/checkpoint.md`/`latest_reviewer.md`/`latest_codex.md` (per
  `git add -f`, da `.agent_handoff/` regulär in `.gitignore` steht — Stephan hat
  genau diese drei Dateien explizit für die Baseline freigegeben; der Rest des
  Ordners bleibt lokal/ignoriert, `latest_claude.md` insbesondere). `ARCHITECTURE.md`
  bewusst nicht über den bereits vorhandenen Reviewer-Hinweis hinaus verändert
  (keine falschen Aussagen zu Test-Targets gefunden; volle Synchronisierung ist
  V-03).
- Checks: `swift test` grün, normaler Build grün, Strict-Concurrency-Build
  grün, Clean-HEAD strict build + Clean-HEAD `swift test` grün.
- Kein Push/Release/Deployment, kein Löschen/Umbenennen, keine neue Produkt-
  entscheidung.

**Nachtrag — E-01: WorldSession + direkter Map-Pfad (Codex-Handoff
HE3D-CX-2026-07-27-020, Runde 020):** Erster Slice von Milestone M1 (Rev. 7).
Validierte Map, aktiver Layer, `HarmonyGraphEngine` und `RuntimeHarmonik`
kommen jetzt aus einer Hand statt separat konstruierter Kopien; der
Map-Preview-Produktpfad exportiert nicht mehr über
`HarmonyMapLoader.toChordNetwork`.

- **Neuer `WorldSession`-Typ** (`Sources/HarmonyEngine3D/WorldSession.swift`,
  App-Target, nicht `HarmonyShared` — besitzt `RuntimeHarmonik`). Bündelt
  validierte `HarmonyMap`, `activeLayer`, `HarmonyGraphEngine`,
  `RuntimeHarmonik` und einen deterministischen `Snapshot` (layer-gefilterte
  `nodeIDs`/`nodes`/`edges`, Reihenfolge = Map-Deklarationsreihenfolge).
  `WorldSession(map:activeLayer:seed:)` validiert intern erneut über
  `HarmonyMapValidator` (günstig, kein I/O — eigene Invariante unabhängig vom
  Aufrufer) und scheitert sauber (`WorldSessionError`) bei Validator-Errors,
  unbekanntem Layer oder leerer Layer-Sicht (Layer existiert, aber kein
  aktiver Node). Warnings werden weitergereicht, blockieren nicht. Bundle-
  Factory `WorldSession.load(named:activeLayer:bundle:seed:)` nutzt
  `HarmonyMapCodec`/`HarmonyMapValidator` direkt statt `HarmonyMapLoader.load`
  (vermeidet doppelte Validierung).
- **`HarmonyScene`** bekommt einen neuen `convenience init(worldSession:)`.
  `allChords`/`allEdges` (Autopilot, Verbindungslinien) werden lokal aus
  `worldSession.snapshot` abgeleitet (dieselbe Kanten-Transformation wie
  `toChordNetwork` — symmetrische Duplikation ungerichteter Kanten, da
  `EdgeData` kein `directed` kennt — aber ohne den Legacy-Adapter
  aufzurufen). `buildJsonWebLayout` (Anker/Render) unverändert, liest schon
  seit Phase 3.9.3a direkt aus `harmonyMap`. Bestehender
  `init(network:harmonyMap:layer:)` unverändert, bleibt für Explore aktiv.
- **`AppModel.init()`** (`HarmonyEngine3DApp.swift`) baut im Map-Preview-Pfad
  eine `WorldSession`; `graphEngine`/`runtimeHarmonik` kommen aus der Session
  statt separat konstruiert zu werden. Bei Konstruktionsfehler (z. B. defekte
  Map) sauberer Fallback auf Explore, wie zuvor bei fehlgeschlagenem Laden.
  Explore-/Legacy-Pfad unverändert, nutzt weiterhin `ChordNetwork` direkt.
  Rein beobachtendes `[HarmonyTest]`-Logging (eigene `testEngine`, Seed
  12345) unverändert erhalten.
- **Sendable-Detail:** `WorldSessionError` trägt bei `.invalidMap` bereits
  gerenderte `[String]`-Beschreibungen statt `[HarmonyMapValidator.Issue]`
  direkt — `Issue` ist nicht `Sendable`, `Error`-Typen werden unter Strict
  Concurrency implizit als `Sendable` erwartet. Lokal in `WorldSession.swift`
  gelöst, keine Änderung an `HarmonyShared` nötig.
- **Manuell live verifiziert** (Runde-020-spezifisch, über den in F-01/013
  etablierten `HE3D_MAP_PREVIEW=1`-Pfad, direkter Prozessstart statt
  `swift run`-Wrapper wegen Output-Buffering): Map-Preview
  (`reference-core`) lädt über WorldSession, JSON-Web-Layout baut 6 Nodes,
  Autopilot triggert Akkordwechsel (`Db7→Cmaj7`, `Am7→Dm7`, `Fmaj7→G7`)
  korrekt aus dem Snapshot, `RuntimeHarmonik`/Magnetismus-Log zeigt
  konsistente Kandidaten (`field: substitution [tritSubst]` für `Db7→Cmaj7`
  passt zur Map), Audio spielt symmetrisch (noteOn/noteOff CH0). Explore-
  Default (`network_wholetone.txt`) unverändert lauffähig, Autopilot/Audio
  normal.
- Keine Radar-/Debug-UI-Verdrahtung, keine Magnet-4.2c-Arbeit, keine Datei-/
  Bundle-Auswahl-UI, kein HarmonyWeb-Default-Wechsel, keine musikalischen
  Map-Reparaturen, keine neuen RelationTypes.
- Neue Tests (`Tests/HarmonyEngine3DTests/WorldSessionTests.swift`, 8):
  valide Map + existierender Layer gelingt, unbekannter Layer/Validator-
  Errors/leere Layer-Sicht scheitern sauber und typisiert, Snapshot
  deterministisch über zwei Instanzen, Snapshot entspricht
  `HarmonyMap.activeNodeIDs(in:)`, `GraphEngine`/`RuntimeHarmonik` liefern
  konsistente Vorschläge für denselben Ausgangsakkord, Bundle-Factory lädt
  die F-03-Testfixture. Keine SceneKit-/Rendering-Abhängigkeit.
- Checks: `swift test` grün (38/38 — 30 bestehend + 8 neu), normaler Build
  grün, Strict-Concurrency-Build grün (keine neuen Warnungen in
  `WorldSession.swift`/`HarmonyScene.swift`/`HarmonyEngine3DApp.swift`),
  Clean-HEAD strict build + Clean-HEAD `swift test` grün.

**Nachtrag — E-02: Harmonic Magnet 4.2c korrigiert (Codex-Handoff
HE3D-CX-2026-07-27-021, Runde 021):** Der harmonische Magnet bekommt einen
klaren, testbaren, konfigurierbaren Vertrag. Kein neues JSON-Feld, kein
`MagnetProfile.range` — Range wird ausschließlich aus dem bestehenden
`MagnetProfile.Preset` abgeleitet.

- **Neuer `HarmonicMagnetConfig`** (`RuntimeHarmonik.swift`, reiner Value-Typ):
  `isEnabled`, `intensity` (0…1, geklammert), `rangeScale` (0.25…4.0,
  geklammert). `effectiveRange(preset:config:)`: Preset-Basis (`strong=25`,
  `medium=15`, `weak=8`, kein `magnetProfile` → wie `medium`) × `rangeScale` —
  dieselben Zahlen, die schon in `MagnetProfile`s ursprünglicher Doku-Notiz
  standen, aber nie ausgewertet wurden. `falloff(distance:range:)`: quadratisch
  weich, `1.0` bei Distanz 0, `0.0` an/außerhalb der Reichweite, kein harter
  Kraftrand — konsistent mit dem bestehenden proximity-Magnet-Falloff-Stil.
- **`HarmonicCandidate`** um `effectiveRange: Float` erweitert;
  **`HarmonicDecision`** um `magnetConfig: HarmonicMagnetConfig` (die für
  diese Entscheidung verwendete Konfiguration — einzige Quelle für
  `isEnabled`/`intensity` in `HarmonyScene`, kein separater AppSettings-
  Zugriff dort nötig). **`HarmonicMagnetInfluence`** um `effectiveRange`,
  `intensity`, `isEnabled` erweitert.
  `RuntimeHarmonik.process(currentChord:localNodes:magnetConfig:)` — neuer
  Parameter mit Default `.defaults`, bestehende Aufrufer/Tests bleiben ohne
  Änderung lauffähig. `RuntimeHarmonik` bleibt vollständig AppSettings-/
  SceneKit-/SwiftUI-/Audio-frei — bekommt nur den Value-Snapshot.
- **`AppSettings`**: neuer `HarmonicMagnetSettings`-Block
  (`@Published var harmonicMagnet`, eigene UserDefaults-Keys
  `he3d.harmonicMagnet.*`), vollständig getrennt von
  `FlightConfig.magnetStrength`/`magnetRadius` (proximity-Magnet, unverändert).
- **`HarmonyEngine3DApp.onGraphHook`** baut pro Aufruf einen
  `HarmonicMagnetConfig`-Snapshot aus `AppSettings.shared.harmonicMagnet` und
  übergibt ihn an `RuntimeHarmonik.process(...)`.
- **`FlightController.applyMagneticForce`**: `isEnabled == false` überspringt
  die harmonische Richtungskorrektur vollständig (kein Floor-Clamp-Risiko wie
  bei einer reinen Rate-Multiplikator-Nullung — `harmonicMagnetRateMin` ist
  ein Floor auf die Rate-*Konstante*, ein auf 0 gehender `rateMultiplier`
  würde trotzdem eine spürbare Restrate ergeben; der frühe `isEnabled`-Ausstieg
  umgeht das korrekt). `falloff`/`intensity` wirken als zusätzliche,
  multiplikative Alpha-Faktoren NACH der bestehenden Winkelgeschwindigkeits-
  Klammer — weich, kein harter Kraftrand. Proximity-Magnet
  (`magnetTarget`/`FlightConfig.magnetStrength`/`magnetRadius`) unverändert,
  komplett separater Codepfad.
- **Beobachtung (kein Bugfix-Scope, zur Kenntnis für Stephan/Codex):** live im
  Map-Preview verifiziert (`reference-core`) — bei den dortigen Node-Abständen
  (~110–250 m) liegt der harmonische Magnet mit den vorgegebenen
  Preset-Ranges (8–25 m) faktisch permanent außerhalb der Reichweite und wirkt
  praktisch nie. Das ist eine direkte, korrekte Konsequenz der im Handoff
  vorgegebenen Preset-Range-Werte, keine eigene Interpretation — ob
  `rangeScale`-Defaults oder die Preset-Basiswerte für die tatsächlichen
  Weltgrößen angepasst werden sollen, ist eine Spielgefühl-Entscheidung
  außerhalb des E-02-Scopes.
- Kein UI-Control im Settings-Panel ergänzt (Handoff erlaubt das nur „wenn
  sehr klein"; Persistenz + Tests + Doku ist als für E-02 ausreichend markiert
  — UI-Anbindung bleibt offen für eine spätere Runde).
- Neue Tests (`Tests/HarmonyEngine3DTests/HarmonicMagnetConfigTests.swift`,
  12): Preset-Range-Mapping (inkl. `nil`→`medium`), `rangeScale`/`intensity`
  wirken und werden geklammert, Falloff (max bei 0, null an/außerhalb Range,
  nie <0/>1, `range=0`→0), `isEnabled=false` deaktiviert den Einfluss ohne die
  Kandidaten-/Entscheidungsermittlung zu brechen, Default-`magnetConfig`
  entspricht `.defaults` (Rückwärtskompatibilität), `process(...)` bleibt
  deterministisch über zwei identisch konstruierte Sessions. Keine SceneKit-/
  FlightController-Zustandsabhängigkeit — reine Value-Typ-/RuntimeHarmonik-
  Tests.
- Checks: `swift test` grün (50/50 — 38 bestehend + 12 neu), normaler Build
  grün, Strict-Concurrency-Build grün (keine neuen Warnungen — verifiziert
  per Vorher/Nachher-Diff der Warnungsmenge in den geänderten Dateien, nicht
  nur Zeilennummern-Grep), Clean-HEAD strict build + Clean-HEAD `swift test`
  grün.

**Nachtrag — E-03: HarmonyWeb als normal wählbarer Modus (Codex-Handoff
HE3D-CX-2026-07-27-023, Runde 023):** Stephan-Entscheidung (2026-07-27,
Option A): HarmonyWeb ist jetzt über normale App-Settings wählbar, ohne
`--map-preview`/`HE3D_MAP_PREVIEW` setzen zu müssen. **Explore bleibt
App-Default.** Initiale HarmonyWeb-Map: `reference-core`. Der bestehende
Environment-/CLI-Flag bleibt als vorrangiger Developer-/Kompatibilitäts-
Override erhalten.

- **Neuer `RuntimeWorldSelection.swift`**: `RuntimeWorldMode` (`.explore`/
  `.harmonyWeb`), `HarmonyWebMapCatalog` (`.referenceCore`/`.webCenter`/
  `.webDiatonic` — `rawValue` == Bundle-Resource-Name, keine externe
  Datei-Auswahl in diesem Slice, bewusst als Stop-Kriterium-Vermeidung: das
  wäre eine Sicherheits-/Bookmark-/Sandbox-Entscheidung), `RuntimeWorldSelection`
  (Default `.explore`, `harmonyWebLayer` startet `"functional"`).
- **`AppSettings`**: neuer, eigener `worldSelection`-Block, getrennt von
  `HarmonyConfig.networkIndex` (bleibt reine Explore-Netzwerkauswahl).
- **`AppModel.effectiveHarmonyWebRequest(envOverride:selection:)`**
  (`HarmonyEngine3DApp.swift`, `internal` statt `private` für Testbarkeit):
  Vorrang Developer-Override (Layer bleibt dabei hart `"functional"` wie
  bisher), sonst persistierte `AppSettings.worldSelection` nur bei
  `mode == .harmonyWeb`. `envOverride`/`selection` sind injizierbare
  Parameter mit Default aus den echten globalen Quellen — reine, testbare
  Entscheidungslogik ohne `AppSettings.shared` in Tests mutieren zu müssen
  (der bestehende 500-ms-Debounce-Save hätte sonst reale UserDefaults
  verändert).
- **`RuntimeWorldInfo`** um `layer: String?` erweitert (Default `nil`);
  bekam einen expliziten Initializer, weil der synthetisierte Memberwise-
  Init den Default-Parameter für `layer` nicht wie erwartet übernahm
  (während der Entwicklung als Compile-Fehler aufgetreten, so gelöst).
  Enum-Fallname `RuntimeWorldInfo.Kind.mapPreview` bewusst NICHT umbenannt
  (z. B. zu `.harmonyWeb`) — hätte `OutputCoordinator.swift` erzwungen
  anzufassen, außerhalb der erlaubten Dateiliste dieses Slices; nur Bedeutung
  und sichtbare UI-Beschriftung ändern sich.
- **`ContentView.swift`**: neuer, kompakter Settings-Abschnitt „WELT" (zwei
  Modus-Buttons Explore/HarmonyWeb, bei HarmonyWeb zusätzlich Map-Auswahl aus
  dem Katalog, Hinweistext „wirkt nach dem nächsten Neustart"). Welt-
  Statuszeile zeigt jetzt „HarmonyWeb (Layer)" statt „Map Preview". Kein
  ContentView-Redesign — kleine, in den bestehenden Panel-Stil eingepasste
  Ergänzung.
- Neue Lokalisierungs-Keys (DE + EN): `settings.section.world`,
  `settings.world.mode.explore`, `settings.world.mode.harmonyweb`,
  `settings.world.restart.desc`.
- **Live verifiziert** (direkter Prozessstart, `stdbuf -oL`): frischer Start
  ohne jeden Override → Explore (`Ganzton-Netzwerk geladen`). Start mit
  NSUserDefaults-Argument-Overrides `-he3d.world.mode harmonyWeb
  -he3d.world.harmonyWebMap reference-core -he3d.world.harmonyWebLayer
  functional` (simuliert eine persistierte Auswahl, ohne echte UserDefaults
  zu verändern — Argument-Domain-Override ist flüchtig) → HarmonyWeb startet
  korrekt **ohne jeden Env-/CLI-Flag**, Log zeigt `[HarmonyTest] ✅
  HarmonyWeb aktiv: reference-core ... Layer 'functional'`.
- Kein Live-Wechsel der laufenden Scene (Auswahl wirkt erst beim nächsten
  App-Start, wie im Handoff als Standardannahme vorgegeben — Live-Rebuild
  gehört zu E-04/E-05). Keine externe Datei-Auswahl-UI. Kein HarmonyWeb-
  Default-Wechsel. Keine ContentView-Neugestaltung.
- Neue Tests (`Tests/HarmonyEngine3DTests/RuntimeWorldSelectionTests.swift`,
  8): Default-Selection ist Explore, `HarmonyWebMapCatalog`-rawValues
  passen zu den Bundle-Resource-Namen, `effectiveHarmonyWebRequest(...)`
  liefert korrekt für Explore-Default/HarmonyWeb-Auswahl/verschiedene
  Map+Layer-Kombinationen, Env-Override hat Vorrang und erzwingt weiterhin
  `"functional"` unabhängig von einer abweichenden persistierten Layer-Wahl,
  `WorldSession.load(named: "reference-core", activeLayer: "functional")`
  ist valide. `toChordNetwork` bleibt im HarmonyWeb-Startpfad ungenutzt
  (Codeinspektion: `grep -n toChordNetwork HarmonyEngine3DApp.swift` liefert
  keinen Treffer, wie bereits seit E-01).
- Checks: `swift test` grün (58/58 — 50 bestehend + 8 neu), normaler Build
  grün, Strict-Concurrency-Build grün (Vorher/Nachher-Warnungsdiff bestätigt
  keine neuen Warnungen in `ContentView.swift`/`HarmonyEngine3DApp.swift`/
  `AppSettings.swift`, keine Warnungen in `RuntimeWorldSelection.swift`),
  Clean-HEAD strict build + Clean-HEAD `swift test` grün.

**Nachtrag — E-04: InputSnapshot + FlightState-Ownership (Codex-Handoff
HE3D-CX-2026-07-27-024, Runde 024):** Technischer Stabilisierungsslice.
`FlightState` wird jetzt ausschließlich im Renderloop (`SceneKitView.
Coordinator.renderer(_:updateAtTime:)` → `FlightController.update(...)`)
mutiert; `FlightController.state` ist `private(set)`. Maus/Tastatur liefern
nur noch Inputzustand.

- **Neue Datei `FlightInputSnapshot.swift`**: `FlightConfigSnapshot`
  (Value-Snapshot der relevanten `AppSettings.shared.flight`-Werte, einmal
  pro Frame via `.current()` statt mehrfacher Live-Reads in
  `buildInputState`/`applyMagneticForce`), `FlightInputSnapshot` (bündelt
  Tastatur-Achsen, konsumierte Maus-Deltas, Gamepad-Schub/Blick/Brake,
  Autopilot-Ziel, harmonischen Magnet-Einfluss, Proximity-Magnet-Ziel,
  Config — siehe Doku-Kommentar zur bewusst getrennten Behandlung von
  `harmonicMagnetInfluence`/`magnetTarget`), `FlightHUDSnapshot`
  (`currentSpeed`/`autopilotNextChord`/Gyro/Motion; `gyroRoll`/`gyroPitch`
  optional = „diesen Frame keine neuen Sensordaten", identisch zum
  bisherigen Verhalten ohne Dispatch in diesem Fall).
- **`FlightController.mouseDragged(_:)`** (Main-Thread-Callback aus
  `FlightSCNView`) mutiert nicht mehr `state.orientation` direkt, sondern
  akkumuliert nur noch über den neuen, gelockten, AppKit-freien Testseam
  `recordMouseDelta(dx:dy:)`. Der Renderloop konsumiert (liest + nullt) die
  Deltas einmal pro Frame in `buildInputState(...)` und wendet sie additiv
  auf `yawDelta`/`pitchDelta` an — identische Rotationsformel wie zuvor
  (`orientation = normalize(orientation * yawQ * pitchQ)`), nur der
  Mutationszeitpunkt wandert vom Main-Thread-Callback in den Renderloop.
- **Tastatur-Monitor** schreibt `keysDown` jetzt hinter einem `NSLock`
  (`keysLock`) statt ungeschützt vom Renderloop gelesen zu werden; neuer
  AppKit-freier Testseam `setKeyDown(_:isDown:)`.
- **`autopilotTarget`/`harmonicMagnetInfluence`/`magnetTarget`** sind keine
  von außen beschreibbaren Properties mehr, sondern Parameter von
  `update(deltaTime:autopilotTarget:harmonicMagnetInfluence:magnetTarget:
  autopilotNextChordName:)` — `SceneKitView` übergibt sie direkt statt sie
  vorher separat zu setzen.
- **Camera-Reset** läuft über neue Methode `resetForRender(position:)` statt
  offenem `flightController.state.xxx = ...`-Zugriff aus `SceneKitView`.
- **Proximity-Magnet-Ziel** (`updateTargets`, alle 3 Frames) wird jetzt
  Render-Thread-lokal in `Coordinator.latestMagnetTarget` gehalten statt
  asynchron auf den Main Thread dispatcht — behob einen echten Cross-
  Thread-Race: die alte `DispatchQueue.main.async { flightController.
  magnetTarget = ... }`-Zuweisung lief auf einem anderen Thread als
  `applyMagneticForce`, das denselben Wert im selben Frame auf dem
  Render-Thread las.
- **HUD-Werte** (`currentSpeed`, `autopilotNextChord`, Gyro, Motion) werden
  jetzt in einem einzigen `FlightHUDSnapshot` gebündelt und über einen
  einzigen `DispatchQueue.main.async`-Aufruf (`applyHUDSnapshot`)
  angewendet statt über vormals fünf einzelne Dispatches aus `update()`/
  `processSensors()`/`SceneKitView`. `debugInput` bewusst nicht im
  Snapshot (kein Bezug zum Renderloop-Takt, bleibt eigener Main-Thread-
  Callback-Write aus dem Tastatur-Monitor).
- Neue Tests (18): `Tests/HarmonyEngine3DTests/FlightPhysicsTests.swift`
  (8, reine Value-Typ-Regressionstests: Vorwärtsschub, Bremsen ignoriert
  Schub, MaxSpeed-Klammerung bei Geschwindigkeit über dem Limit, Yaw-/
  Pitch-Determinismus, Null-Input → keine Rotation) und
  `FlightControllerInputSnapshotTests.swift` (10, über die AppKit-freien
  Testseams `recordMouseDelta`/`setKeyDown` statt echter `NSEvent`-
  Konstruktion, wie im Handoff empfohlen: Maus-Delta mutiert `state` nicht
  sofort, wird erst im nächsten `update()` angewendet und danach genullt,
  mehrere kleine Deltas akkumulieren wie ein großes, Tastatur beeinflusst
  `state` nicht sofort, W+S heben sich auf, `resetForRender` setzt
  Position/Velocity/Orientation deterministisch).
- **Live verifiziert** (direkter Prozessstart, `stdbuf -oL`, ~15 s
  Laufzeit): Explore-Start, Autopilot bewegt die Kamera kontinuierlich,
  durchgehende Proximity-Chord-Trigger-Sequenzen (CH0 `noteOn`/`noteOff`)
  ohne Crash/Hang — bestätigt den vollständigen Renderloop → `update()` →
  Physik → Proximity → Audio-Pfad inklusive der neuen Locks. Mausblick/
  WASD/QE deterministisch über die neuen Unit-Tests verifiziert (reale
  `NSEvent`-Simulation in dieser Umgebung nicht möglich, wie vom Handoff
  antizipiert).
- Checks: `swift test` grün (76/76 — 58 bestehend + 18 neu), normaler Build
  grün, Strict-Concurrency-Build grün (Vorher/Nachher-Diff bestätigt keine
  neuen Warnungen — eine anfängliche `[weak self]`-Variante der HUD-
  Dispatch-Closure hätte eine neue Warnkategorie erzeugt, korrigiert auf
  denselben Strong-Self-Stil wie die bestehenden Dispatches in dieser
  Datei), Clean-HEAD strict build + Clean-HEAD `swift test` grün.
- Kein E-05-Vorgriff (keine Render-Command-Queue), kein Live-Scene-Rebuild,
  keine neue Gamepad-/Keyboard-Belegung, kein Audio-/MIDI-Refactor, keine
  HarmonyWeb-/Map-/Layer-Semantik.

**Nachtrag — E-05: Render-Commands + Config-Snapshots (Codex-Handoff
HE3D-CX-2026-07-27-025, Runde 025):** Ersetzt lose Pending-Bool-/Tuple-
Gruppen in `HarmonyScene.swift` durch einen atomaren Command-Typ plus
lockgeschützte Queue; zieht den letzten verbliebenen Live-`AppSettings.shared`-
Read aus dem `FlightController`-Renderpfad heraus.

- **Neue Datei `RenderCommand.swift`**: `RenderCommand`-Enum
  (`.switchNetwork(ChordNetwork, isCurated:filename:)`, `.reload`,
  `.lightingUpdate`, `.edgeRebuild`, `.visibilityRebuild`,
  `.cameraReset(simd_float3)`) plus `RenderCommandQueue`
  (`NSLock`-geschützt, `enqueue(_:)` von jedem Thread sicher aufrufbar,
  `drain()` liefert FIFO-geordnet und leert die Queue atomar).
  Netzwerkwechsel trägt jetzt `ChordNetwork`+`isCurated`+`filename` als
  **ein** Command statt drei unabhängig auf dem Main Thread gesetzter
  Felder (`pendingNetwork`/`pendingNetworkIsCurated`/
  `pendingNetworkFilename`) — schließt eine echte, wenn auch seltene
  Torn-Read-Möglichkeit, bei der der Render-Thread ein neues Netzwerk mit
  einem noch alten `isCurated`/`filename`-Wert hätte lesen können.
  `loadNetwork(_:isCurated:filename:)` (`HarmonyScene.swift`) nimmt beide
  Werte jetzt als Parameter statt aus Instanzfeldern zu lesen.
- **`HarmonyScene.updateProximity(...)`** konsumiert Commands über eine neue
  `drainRenderCommands(phase:cameraPosition:)`-Hilfsmethode mit drei Phasen
  (`.top`/`.postChunks`/`.end`), die exakt die bisherige Pending-Flag-
  Konsumreihenfolge nachbildet: Netzwerk/Reload/Lighting/CameraReset vor
  jeder Chunk-Logik, Edge-Rebuild erst **nach** `updateChunks(...)` (braucht
  dessen ggf. neu geladene Chord-Nodes als Kantenendpunkte — vorher hätte
  `rebuildEdgeLines()` auf noch nicht existierende Nodes zeigen können),
  Visibility erst nach den übrigen Proximity-Passes (Chord/Portal/Cloud/
  Autopilot), wie zuvor bewusst zuletzt. Commands, die in einer noch nicht
  zuständigen Phase drainen (in der Praxis nur bei race-artigem Timing
  zwischen Main-Thread-Enqueue und Render-Thread-Drain möglich), werden
  zurück in die Queue gestellt statt verworfen oder verfrüht angewendet.
- **`requestCameraReset(_:)`** enqueued jetzt `.cameraReset(pos)` statt
  `pendingCameraReset` direkt zu setzen; `triggersArmed`/`armReferencePos`
  bleiben bewusst synchron mit dem Aufruf (nicht mit dem späteren Drain) —
  identisches Verhalten zu vorher. `consumePendingCameraReset()` (externe
  API, von `SceneKitView` konsumiert) bleibt unverändert.
- **`FlightController`**: neuer `MidiRuntimeConfigSnapshot`
  (`FlightInputSnapshot.swift`) für die von `processSensors()` genutzten
  `AppSettings.shared.midi`-Werte. `FlightController` abonniert jetzt
  `AppSettings.shared.$flight`/`.$midi` per Combine-Sink
  (`subscribeToConfigChanges()`, läuft auf dem Main Thread — wie die
  bestehenden `HarmonyScene`-Sinks) und hält die zuletzt gebauten Snapshots
  gelockt vor (`configLock`/`snapshotConfig()`). `buildInputSnapshot()`/
  `processSensors()` lesen nur noch den gecachten Snapshot statt
  `FlightConfigSnapshot.current()`/`AppSettings.shared` live vom
  Render-Thread — der letzte verbliebene Render-Thread-Live-Read aus E-04
  ist damit geschlossen. Neuer Testseam `setConfigForTesting(flight:midi:)`
  injiziert deterministische Snapshots, ohne `AppSettings.shared` zu
  mutieren.
- Stale gewordener E-04-Kommentar in `HarmonyScene.swift` zum alten
  `flightController.harmonicMagnetInfluence`-Property-Flow korrigiert (von
  Codex im E-04-Review explizit freigegeben, da `HarmonyScene.swift` in
  E-05 ohnehin gezielt angefasst wird).
- **Bewusst nicht konvertierte Live-Reads** (Pragmatische Grenze laut
  Handoff — kein Big-Bang über die ganze Datei): `applyLightingQuality()`
  liest `AppSettings.shared.render.highQualityRendering` weiterhin live
  (reiner Bool-Trigger ohne Mehrfeld-Tearing-Risiko, kein „atomarer
  Payload"-Bedarf); `rebuildEdgeLines()` prüft
  `AppSettings.shared.render.showNetworkEdges` weiterhin als
  Sicherheits-Guard beim Anwenden (idempotente Re-Prüfung, kein
  treibender Konfigurationswert, der command-artig transportiert werden
  müsste). Die Thread-Safety-Lücke, die E-05 schließt, betraf das Fehlen
  jeglicher Synchronisierung beim Main→Render-Übergang — nicht diese
  spezifischen, bereits idempotenten Re-Checks.
- Neue Tests (10): `Tests/HarmonyEngine3DTests/RenderCommandQueueTests.swift`
  (6 — FIFO-Reihenfolge, atomarer Drain, leere Queue, Netzwerk-Command trägt
  Network+Curated-Flag+Filename zusammen, CameraReset-Command trägt Position
  als Value, Thread-Sicherheit unter `DispatchQueue.concurrentPerform` mit
  500 gleichzeitigen `enqueue`-Aufrufen) und `ConfigSnapshotTests.swift`
  (4 — `MidiRuntimeConfigSnapshot.current()` spiegelt
  `AppSettings.shared.midi`, Equatable-Value, Nachweis dass `update(...)`
  einen injizierten Snapshot verwendet statt live AppSettings zu lesen via
  `setConfigForTesting` mit `maxSpeed: 5` weit unter jedem realistischen
  Default, Regression-Test ohne Injection gegen die echten Defaults).
- **Live verifiziert** (direkter Prozessstart, `stdbuf -oL`, je ~10 s
  Laufzeit): Explore-Start (Autopilot bewegt die Kamera kontinuierlich,
  durchgehende CH0-Chord-Trigger-Sequenzen ohne Crash/Hang) und
  HarmonyWeb-Start via NSUserDefaults-Argument-Override (JSON-Web-Layout
  baut korrekt, harmonischer Magnet aktiv, Audio läuft) — beide bestätigen
  den kompletten Command-Queue-/Config-Snapshot-Pfad inklusive
  `buildJsonWebLayout`s Main-Thread-Enqueue beim Konstruktions-Init.
- Checks: `swift test` grün (86/86 — 76 bestehend + 10 neu), normaler Build
  grün, Strict-Concurrency-Build grün — vollständiger Clean-Rebuild vorher/
  nachher verglichen (ein erster inkrementeller Vergleich zeigte zunächst
  scheinbar „entfernte" Warnungen aus nicht neu kompilierten `DesignerKit`-/
  `HarmonyShared`-Modulen, ein reiner Build-Cache-Artefakt; beim
  vollständigen Rebuild beider Zustände: exakt identische Warnmenge, keine
  neuen, keine entfernten), Clean-HEAD strict build + Clean-HEAD
  `swift test` grün.
- Kein `InteractionRuntime`-Vorgriff (E-06), keine Chord-/Bass-/Cloud-
  Trigger-Semantik geändert, kein Settings-UI-Umbau, kein Audio-/MIDI-
  Refactor, kein HarmonyWeb-/Map-/Layer-Default-Wechsel.

**Nachtrag — E-06a: InteractionRuntime Chord-Proximity + Trigger
(Codex-Handoff HE3D-CX-2026-07-27-026, Runde 026):** Erster Teilschritt der
`InteractionRuntime`-Extraktion aus `HarmonyScene` (nur Chord-Kanal — Bass/
Cloud bleiben E-06b, weiterhin offen).

- **Neue Datei `InteractionRuntime.swift`** — SceneKit-frei, kein
  `AppSettings.shared`, kein `SCNNode`, kein `MIDIManager`/`AudioOutput`/
  `OutputCoordinator`:
  - `ChordInteractionCandidate` (Key/Position/`ChordData`/`visible`-Flag —
    bewusst ALLE geladenen Chord-Knoten, nicht nur sichtbare, damit ein
    Knoten, der im selben Frame unsichtbar wird UND den Trigger-Radius
    verlässt, trotzdem korrekt deaktiviert wird).
  - `ChordInteractionConfig` (fertig berechnete Entry-/Exit-/
    Approach-Radien + `triggersArmed`/`voiceLeadingEnabled`/
    `chordOctaveShift` — die Runtime multipliziert nichts selbst).
  - `InteractionRenderEffect` (`resetApproachGlow`/`setApproachGlow`/
    `setHighlighted`/`triggerHarmonicImpulse`/`updateChordData`) und
    `InteractionOutputEvent` (`nearestChord`/`chordActivated`/
    `chordDeactivated`, bereits vollständig aufgelöste Note-On/Note-Off-
    Daten), zusammengeführt in `InteractionAction` (Sum-Typ) — `HarmonyScene`
    wendet das zurückgegebene Array in exakt der gelieferten Reihenfolge an,
    damit die kritische relative Reihenfolge erhalten bleibt (`updateChordData`
    vor `chordActivated`, `triggerHarmonicImpulse` NACH `chordActivated`,
    identisch zum bisherigen `updateChordProximity`).
  - `struct InteractionRuntime` besitzt `TriggerEngine` (Chord-Kanal) +
    `VoiceLeadingEngine` als eigenen, framestabilen Zustand — beide waren
    zuvor `HarmonyScene`-Felder. API: `updateChord(_:) -> [InteractionAction]`
    (reproduziert `ProximityTracker.evaluate` + Trigger-Übergang +
    VoiceLeading + Octave-Shift-Snapshot 1:1), plus granulare Reset-Methoden:
    `clearActiveTrigger()` (nur Trigger, für `unloadChunk`), `clearApproach(
    ifEquals:)` (bedingt), `resetAll()` (vollständig, für `reloadAllChunks()`),
    `outputNotes(forKey:)`/`removeOutputNotes(forKey:)` (symmetrisches
    NoteOff aus den Reset-Pfaden).
- **`HarmonyScene`**: `chordTriggerEngine`/`voiceLeadingEngine`/
  `lastApproachChordName`/`chordOutputNotes` entfernt, ersetzt durch ein
  einzelnes `interactionRuntime`-Feld. `updateChordProximity(_:)` baut nur
  noch Value-Kandidaten aus `chordNodes`/`chordAnchorPositions`/
  `chordDataMap`, ruft `interactionRuntime.updateChord(...)` auf und wendet
  das Ergebnis über eine neue `applyInteractionActions(_:)`-Methode an
  (SceneKit-Calls + Callbacks) — trifft selbst keine musikalische
  Entscheidung mehr. `reloadAllChunks()`/`unloadChunk(_:)` nutzen die
  granularen Reset-Methoden statt direkter Feldzugriffe. `activeChordNotes`/
  `nearestChordNotes` und die Candidate-Glow-Guards lesen
  `interactionRuntime.activeKey`/`.lastApproachKey`.
  `currentMagnetNodeID`/`currentMagnetProfile`/`applyHarmonicDecision`
  unverändert in `HarmonyScene` (werden extern über die
  `onChordActivated`-Callback-Kette gesetzt, nicht innerhalb der
  Proximity-Entscheidung — keine Verschiebung nötig).
- 18 neue Tests (`InteractionRuntimeTests.swift`): Approach (nächster
  sichtbarer Kandidat erzeugt Glow+Event, Approach-Wechsel resettet den
  alten Glow zuerst, keine Kandidaten → leeres `nearestChord`-Event),
  Trigger Entry/Exit/Hysterese, `triggersArmed`-Gate (verhindert
  Aktivierung, deaktiviert sauber bei Entzug), On/Off-Symmetrie über einen
  zwischenzeitlichen Config-Wechsel (Octave-Shift + VoiceLeading ändern
  sich zwischen Aktivierung und Deaktivierung, Noten bleiben exakt gleich),
  Octave-Shift-Clamp auf 127, VoiceLeading enabled/disabled, granulare
  Reset-API (inkl. Nachweis dass `resetAll()` bewusst NICHT die
  Output-Notes-Snapshots löscht — identisch zum bisherigen Verhalten),
  Reihenfolge-Nachweis `triggerHarmonicImpulse` nach `chordActivated`.
  Kein separater HarmonyScene-Adapter-Test: `HarmonyScene` baut echte
  SCNNode-Geometrie im Konstruktor, es gibt im gesamten Testbestand keinen
  leichten Weg eine Instanz ohne diese Kosten zu erzeugen — stattdessen
  sind die Runtime-Tests entsprechend umfassender (wie im Handoff als
  Ausweg vorgesehen).
- **Live verifiziert** (direkter Prozessstart, `stdbuf -oL`, je ~15 s
  Laufzeit): Explore-Start — durchgehende CH0-Chord-Sequenzen mit exakt
  symmetrischen NoteOn-/NoteOff-Notenmengen über die gesamte Laufzeit, kein
  Crash/Hang; HarmonyWeb-Start via NSUserDefaults-Argument-Override —
  JSON-Web-Layout baut korrekt, symmetrische CH0-Sequenzen, UND der
  komplette `onChordActivated`→`onGraphHook`→`RuntimeHarmonik.process`→
  `applyHarmonicDecision`-Kettenaufruf (harmonischer Magnet) feuert
  weiterhin korrekt — bestätigt, dass die Extraktion die synchrone
  Callback-Reihenfolge nicht gebrochen hat.
- Checks: `swift test` grün (104/104 — 86 bestehend + 18 neu), normaler
  Build grün, Strict-Concurrency-Build grün (vollständiger Clean-Rebuild
  vorher/nachher, identische Warnmenge, keine neuen, keine entfernten),
  Clean-HEAD strict build + Clean-HEAD `swift test` grün.
- Kein Bass-/Portal-/Cloud-/Melody-Kanal angefasst, keine musikalische
  Regel/RelationType/Magnet-Arbitration geändert, kein
  `OutputCoordinator`-Umbau, kein Render-Animation-Redesign — E-06b
  (Bass+Cloud) bleibt offen.

**Nachtrag — E-06b: InteractionRuntime Portal/Bass + Cloud/Melody
(Codex-Handoff HE3D-CX-2026-07-27-027, Runde 027):** Zweiter und letzter
Teilschritt der `InteractionRuntime`-Extraktion. Chord+Bass+Cloud laufen
jetzt vollständig über die Runtime — **E-06 damit insgesamt abgeschlossen,
Milestone M1 vollständig.**

- **`InteractionRuntime.swift` erweitert** um `PortalInteractionCandidate`
  (Key/Position/`bassNote: Int?` — optional, weil die Original-Semantik
  einen Trigger-Übergang auch ohne bekannte Bass-Note erlaubt),
  `PortalInteractionConfig` (Radien + `triggersArmed`/`bassHoldMode`/
  `bassOctaveShift`), `CloudInteractionCandidate` (Key/Position, jeden
  Frame frisch aus `cloudNodes` gebaut — kein Positions-Cache wie bei
  Chord/Portal, identisch zum bisherigen Verhalten), `CloudInteractionConfig`
  (Radien + `triggersArmed`/`melodyTempo`/`melodyVelMax`/`energyLevel`/
  `now` — `now` wird von `HarmonyScene` übergeben statt von der Runtime
  selbst gelesen, hält sie deterministisch/testbar).
- **Kanalspezifische RenderEffect-/OutputEvent-Fälle** statt Wiederverwendung
  der generisch benannten Chord-Fälle: `setPortalApproachGlow`/
  `setPortalHighlighted`/`resetPortalApproachGlow`, `setCloudApproachGlow`/
  `setCloudHighlighted`/`resetCloudApproachGlow`,
  `nearestPortal(bassNote:proximity:)`, `bassNoteOn`/`bassNoteOff`,
  `nearestCloud`, `melodyNoteWithVelocity`, `melodyNoteOff` — unterschiedliche
  Node-Pools (`bassPortalNodes`/`cloudNodes` vs. `chordNodes`) und Helfer in
  `HarmonyScene`.
- **`InteractionRuntime`** besitzt jetzt zusätzlich zwei `TriggerEngine`-
  Instanzen (Portal/Cloud) und eine `MelodyEngine`-Instanz (bereits vorher
  vollständig SceneKit-/AppSettings-frei, drop-in wie `VoiceLeadingEngine`).
  Alle `melodyEngine`-Mutationen (`resetCloudIndex`/`stop`/`reset`/`tick`)
  laufen intern in `updateCloud(_:)`, ohne RenderEffect-Umweg — anders als
  `chordDataMap` beim Chord-Kanal lebt kein Teil des Melody-Zustands
  außerhalb der Runtime.
- **Neue API**: `updatePortal(_:)`/`updateCloud(_:)` (1:1-Reproduktion von
  `updatePortalProximity`/`updateCloudProximity`, inkl. der
  `bassHoldMode`-Gate beim Verlassen und der „Off für Vorgängerton vor On
  für neuen Ton"-Sequenzierung im Melody-Tick), `portalActiveKey`/
  `cloudActiveKey`/`currentMelodyPresetName`, `bassOutputNote(forKey:)`/
  `removeBassOutputNote(forKey:)`, `clearActivePortalTrigger()`/
  `clearPortalApproach(ifEquals:)`, `clearActiveCloudTrigger()`/
  `clearCloudApproach(ifEquals:)`, `stopMelody()`, `addCloud(key:root:)`/
  `removeCloud(_:)`, `nextMelodyPreset()`/`prevMelodyPreset()`. `resetAll()`
  erweitert, um alle drei Kanäle zurückzusetzen (Output-Note-Snapshots und
  Cloud-Registrierungen bleiben bewusst erhalten — identisch zum bisherigen
  Verhalten).
- **`HarmonyScene.updatePortalProximity(_:)`/`updateCloudProximity(_:)`**
  sind jetzt reine Adapter (Kandidaten bauen, Runtime aufrufen,
  `applyInteractionActions(_:)` anwenden — dieselbe Methode wie für Chord,
  jetzt mit erweitertem Switch). `reloadAllChunks()`/`unloadChunk(_:)` nutzen
  die neuen granularen Runtime-Methoden statt direkter Feldzugriffe, mit
  exakt denselben (leicht asymmetrischen, aber folgenlosen)
  Aufrufreihenfolgen wie zuvor — z. B. resettet der Portal-Block in
  `unloadChunk` den Trigger VOR dem Off-Event, der Cloud-Block DANACH,
  bewusst unverändert übernommen statt „korrigiert".
- `portalTriggerEngine`/`cloudTriggerEngine`/`lastApproachPortalName`/
  `lastApproachCloudName`/`bassOutputNotes`/`melodyEngine` sind aus
  `HarmonyScene` entfernt; `bassPortalPositions`/`portalBassNote`/
  `cloudNodes`/`bassPortalNodes` (Render-/Positionsdatenschicht) bleiben
  dort, ebenso die sechs SceneKit-Glow-/Highlight-Helfer (nur ihre
  `activeKey`-Guards zeigen jetzt auf `interactionRuntime.portalActiveKey`/
  `.cloudActiveKey`). `snapshotBassOutputNote(key:rawNote:)` entfernt (Logik
  jetzt Teil von `updatePortal(_:)`).
- Neue Tests (18): `Tests/HarmonyEngine3DTests/
  PortalCloudInteractionRuntimeTests.swift` — Portal-Approach/Glow-Reset,
  Entry→Highlight+BassNoteOn+Octave-Clamp, Exit→Highlight+BassNoteOff-aus-
  Snapshot, `bassHoldMode`-Gate, On/Off-Symmetrie über Octave-Shift-Wechsel,
  Kandidat-ohne-Bass-Note-Edge-Case; Cloud-Approach/Glow-Reset,
  Trigger-Entry→Highlight, erste Tick-Note nach Aktivierung deterministisch
  (Round-Robin via `resetCloudIndex`), Off-vor-On-Reihenfolge im Tick,
  Trigger-Exit→Highlight+MelodyNoteOff, Proximity≤0,08 stoppt genau einmal
  (idempotent), Preset-API-Zyklus; granulare Reset-API. Melody-Tick-Tests
  nutzen ausschließlich die deterministischen Zweige von `MelodyEngine.
  tick(...)` (Round-Robin bei `lastNote < 0` oder `energyLevel ≥ 0,95`) —
  der `.randomElement()`-Zweig ist bewusst nicht getestet (nicht
  deterministisch reproduzierbar).
- **Live verifiziert** (direkter Prozessstart, `stdbuf -oL`, je ~20–35 s
  Laufzeit): Explore-Start — CH0/CH1/CH2 feuern über die gesamte Laufzeit
  durchgehend exakt symmetrisch (u. a. beobachtet: CH1 `noteOn 47`→
  `noteOff 47`, CH2 `noteOn 71 vel=29`→`noteOff 71`), kein Crash/Hang;
  HarmonyWeb-Start via NSUserDefaults-Argument-Override — CH0 weiterhin
  symmetrisch, harmonischer Magnet/`RuntimeHarmonik`-Kette intakt (CH1/CH2
  feuern dort erwartungsgemäß nicht, da JSON-Web-Maps keine Bass-/
  Cloud-Entitäten definieren — unverändertes, bereits in E-05/E-06a
  bestätigtes Verhalten).
- Checks: `swift test` grün (122/122 — 104 bestehend + 18 neu), normaler
  Build grün, Strict-Concurrency-Build grün (vollständiger Clean-Rebuild
  vorher/nachher, identische Warnmenge, keine neuen, keine entfernten),
  Clean-HEAD strict build + Clean-HEAD `swift test` grün.
- Kein `OutputCoordinator`-Umbau, keine neue musikalische Regel/
  Melody-Strategie/RelationType/Magnet-Arbitration/Voice-Leading-Semantik,
  kein Render-Animation-Redesign, kein Settings-UI-Umbau, kein
  Audio-/MIDI-Refactor.

**Nachtrag — K-01: HarmonyAuthoring-Fundament (Codex-Handoff
HE3D-CX-2026-07-27-028, Runde 028):** Erster Slice von Milestone M2
(HarmonyWeb Construction Kit V1). Legt die editierbare Dokumentbasis für das
künftige Construction Kit an, ohne UI- oder Dateisystem-Workflow
vorwegzunehmen. `HarmonyMap` bleibt die einzige musikalische Datenwahrheit —
es entsteht kein zweites Node-/Edge-/Layer-Semantikmodell.

- **Neues Target `HarmonyAuthoring`** (`Package.swift`): Library-Target,
  hängt nur von `HarmonyShared` ab; `HarmonyShared` hängt nicht von
  `HarmonyAuthoring` ab. `HarmonyEngine3D`/`DesignerKit` sind in K-01
  bewusst nicht auf das neue Target umgestellt. Neues Test-Target
  `HarmonyAuthoringTests`.
- **`HarmonyMapDocument`** (`Sources/HarmonyAuthoring/HarmonyMapDocument.swift`):
  hält einen `HarmonyMap`-Draft als kanonischen Wert (kein paralleler
  Node-/Edge-Zustand), dazu `documentURL: URL?` (reines Metadatum, kein
  Open/Save), `isDirty`, einen monoton steigenden `revision`-Zähler (erhöht
  sich bei jeder erfolgreichen Draft-Änderung — Command, Undo, Redo — und
  fällt bei Undo bewusst nicht zurück, da er die Gesamtzahl erfolgreicher
  Zustandsübergänge zählt, nicht die Position in der Historie), `diagnostics:
  HarmonyMapValidator.Result` sowie `canUndo`/`canRedo`. Initialisierung aus
  einer bestehenden `HarmonyMap` ergibt `isDirty == false`, `revision == 0`.
  Der Draft darf vorübergehend Validator-Errors enthalten — das Dokument hält
  und diagnostiziert diesen Zustand, statt ihn zu verhindern.
- **Commands (`HarmonyMapCommand.swift`)**: minimaler Protokoll-Vertrag
  `func apply(to:) throws -> HarmonyMap`. Zwei bewusst risikoarme
  Minimal-Commands statt einer vollständigen Node-/Edge-/Layer-CRUD-Suite:
  `SetMapNameCommand` (setzt den Kartennamen, wirft bei leerem/nur-Whitespace-
  Namen) und `DraftTransformCommand` (generischer, closure-basierter
  Draft-Transform — reine Plumbing ohne eigene Authoring-Domänenlogik, dient
  nur dazu, den Command-/Undo-Redo-Vertrag zu beweisen). Beide nehmen K-04/
  K-05 nicht vorweg: es entsteht keine ID-Vergabe-, Referenz-Update- oder
  Layer-Verdrahtungslogik — die eigentliche Node-/Edge-/Layer-Authoring-API
  bleibt vollständig offen für K-04/K-05.
- **`HarmonyMapDocument.perform(_:)`**: übernimmt den neuen Draft nur bei
  Erfolg (Redo-Stack wird geleert, `isDirty`/`revision`/`diagnostics`
  aktualisiert). Ein fehlschlagender Command lässt Draft, Dirty-State,
  Revision und beide Stacks unverändert und reicht den Fehler weiter.
- **Undo/Redo**: Snapshot-basiert (voller `HarmonyMap`-Draft pro
  Stack-Eintrag, kein inverser Command nötig). `undo()`/`redo()` werfen bei
  leerem Stack `HarmonyMapDocument.UndoRedoError.nothingToUndo`/
  `.nothingToRedo` — bewusst kein stilles No-op, um Aufrufer nicht über den
  tatsächlichen Zustand im Unklaren zu lassen.
- **Validierter Snapshot**: `validatedSnapshot() -> ValidatedHarmonyMap?`
  ruft `HarmonyMapValidator.validate(_:)` und liefert `nil`, sobald Errors
  vorliegen; Warnings blockieren den Export nicht. `ValidatedHarmonyMap`
  (`ValidatedHarmonyMap.swift`) ist ein schlanker Wrapper mit modul-internem
  Initializer — nur `HarmonyMapDocument` innerhalb von `HarmonyAuthoring`
  kann Instanzen erzeugen, ein "validierter Snapshot" kann also nicht ohne
  echte Validation vorgetäuscht werden.
- **Kleine öffentliche Shared-Factories** (`Sources/HarmonyShared/
  HarmonyModel.swift`): public `init` für `HarmonyMap`, `HarmonyNode`,
  `HarmonyEdge`, `HarmonyLayer`, `MapLayout`, `Layout3D`, `MagnetProfile` —
  reine Memberwise-Initializer für bestehende Felder, keine neuen Felder,
  keine Codable-Semantik-Änderung, keine Validator- oder RelationType-/
  MagnetProfile-Erweiterung. Vorher hatten diese `public struct`s nur einen
  implizit `internal` synthetisierten Memberwise-Init — `HarmonyAuthoring`
  (und künftig `DesignerKit`) können Snapshots damit erstmals außerhalb von
  `HarmonyShared` konstruieren.
- Neue Tests (13): `Tests/HarmonyAuthoringTests/HarmonyMapDocumentTests.swift`
  — Target baut gegen `HarmonyShared` (Shared-Factories aus Tests nutzbar),
  Dokument-Init aus valider Map (sauber/Revision 0/kein Undo-Redo),
  erfolgreicher Command (Draft/Dirty/Revision/Diagnosen), generischer
  `DraftTransformCommand`-Erfolgspfad, fehlgeschlagener Command (Draft/Dirty/
  Revision/Stacks unverändert), Undo (vorheriger Draft, Redo verfügbar),
  Redo (Command-Änderung wiederhergestellt), neuer Command nach Undo leert
  Redo-Stack, Undo/Redo bei leerem Stack werfen die jeweilige
  `UndoRedoError`, invalider Draft wird gehalten aber `validatedSnapshot()`
  liefert `nil`, Warnings blockieren `validatedSnapshot()` nicht,
  `validatedSnapshot()`-Roundtrip über `HarmonyMapCodec` bleibt stabil.
- Checks: `swift test` grün (135/135 — 122 bestehend + 13 neu), normaler
  Build grün, Strict-Concurrency-Build grün (vollständiger Clean-Rebuild
  vorher/nachher, identische Warnmenge — 482/482, keine neuen, keine
  entfernten Warnungen), `git diff --check HEAD~1 HEAD` grün.
- Kein DesignerKit-UI-Umbau, kein Canvas-Refactor, keine `EdgeData`-
  Entfernung, kein New/Open/Save/Save-As, kein atomisches Schreiben, kein
  Workspace-Sidecar, keine Node-/Edge-/Layer-CRUD-Feature-Suite, keine
  Runtime-/`HarmonyEngine3D`-Composition-Root-Änderung, keine Map-JSON-
  Änderung, keine musikalische Semantik-Änderung.

**Nachtrag — K-02: Dokument-App (Codex-Handoff HE3D-CX-2026-07-27-029, Runde
029):** Zweiter Slice von Milestone M2. Macht aus `HarmonyMapDocument` eine
echte Dokumentbasis — Dateien lassen sich neu anlegen, aus beliebigen
JSON-URLs öffnen, speichern und per Save As an eine andere URL schreiben;
Bundle-Maps werden als read-only Templates behandelt. `DesignerKit` bindet
das schmal an, ohne die Canvas-/Workspace-Migration aus K-03 vorzuziehen.

- **`DocumentOrigin`** (neuer Enum-Fall in `HarmonyMapDocument.swift`):
  `.unsaved` (neu, ungespeichert) / `.file(URL)` (normale Datei) /
  `.readOnlyTemplate(name:)` (Bundle-Template) — ersetzt das bisherige
  `documentURL: URL?` aus K-01 als eindeutigen Dokumentursprung/-status.
  `HarmonyMapDocument.documentURL`/`.isReadOnly` sind jetzt read-only
  computed Properties auf `origin`. Neue modul-interne `mutating func
  markSaved(at:)` (nur von `HarmonyMapDocumentStore` aufrufbar, da
  `private(set)`-Felder nur innerhalb derselben Datei setzbar sind) setzt
  `origin = .file(url)` und `isDirty = false` — `revision` bleibt
  unverändert, Speichern ist keine Draft-Mutation.
- **`HarmonyMapDocumentStore`** (neu, `Sources/HarmonyAuthoring/
  HarmonyMapDocumentStore.swift`): `newDocument(name:)` (minimal neutrale
  Draft-Map — `schemaVersion "1.0"`, UUID-basierte, pro Aufruf eindeutige ID,
  Name „Untitled HarmonyWeb" per Default, leere Layers/Nodes/Edges; keine
  musikalische Starter-Map-Entscheidung, keine Builder-Regel),
  `openDocument(at:)` (beliebige JSON-URL über `HarmonyMapCodec`, kein
  Validator-Gate — ein invalider Draft darf geöffnet werden),
  `openBundledTemplate(named:bundle:)` (Bundle-Resource, Ergebnis-Origin
  `.readOnlyTemplate`), `save(_:)` (schreibt nur bei `origin == .file`, wirft
  `StoreError.noSaveTarget`/`.readOnlyTemplate` sonst — kein stilles
  Schreiben ins Bundle oder auf eine nicht vorhandene URL),
  `saveAs(_:to:)` (schreibt unabhängig vom bisherigen Origin, macht aus
  einem Template oder neuen Dokument eine normale Datei). Schreiben läuft
  über `Data.write(..., options: .atomic)`; Encode-Fehler propagieren
  unverändert als `HarmonyMapCodec.CodecError` (bereits strukturiert), nur
  echte Dateisystemfehler werden als `StoreError.write` typisiert.
- **`RecentDocumentsStore`** (neu, `Sources/HarmonyAuthoring/
  RecentDocumentsStore.swift`): URL-Liste in `UserDefaults` (neueste zuerst,
  dedupliziert, auf `limit` begrenzt, Default 10), testbare Injection über
  `defaults`/`key`/`limit`. Nur normale Datei-Open/Save-As-Erfolge werden
  erfasst — bewusst **kein** separates Template-Recent (Ruecklauf-
  Begründung: eine zweite parallele Liste/UI-Fläche wäre vor einer echten
  Recent-Documents-UI verfrüht gewesen, bleibt offen für K-03/K-06).
- **`DesignerViewModel`** (`import HarmonyAuthoring` ergänzt): `harmonyMap:
  HarmonyMap?` ist jetzt eine computed Property auf `document?.draft` statt
  einer eigenständig zugewiesenen `@Published`-Property — ein einziger
  Quellzustand statt zweier synchron zu haltender Felder (SwiftUI-Views
  aktualisieren sich weiterhin korrekt, da `objectWillChange` bei jeder
  `@Published`-Änderung inklusive `document` feuert). Neues `document:
  HarmonyMapDocument?` (`private(set)`), `documentErrorMessage: String?`
  (Fehler aus Open/Save/Save As landen hier statt stumm verworfen zu
  werden), `documentStatusText`/`documentIsReadOnly`/`canSaveDocument`/
  `documentDiagnosticsSummary` (computed, „N Fehler · M Warnungen" aus dem
  echten `HarmonyMapValidator`-Ergebnis — zusätzlich zu den bestehenden
  Ad-hoc-Prüfungen in `webValidationWarnings`, die unverändert bleiben).
  `loadHarmonyWeb(named:in:)` lädt jetzt über
  `HarmonyMapDocumentStore.openBundledTemplate(named:)` statt
  `HarmonyMapLoader.load(named:)` — bestehende Bundle-Web-Auswahl läuft
  damit über den neuen read-only-Template-Pfad; einziger Verhaltens-
  unterschied: ein Bundle-Template mit Validator-*Errors* (nicht nur
  Warnings) würde jetzt geladen statt wie zuvor mit `nil` abgelehnt — bei
  den drei aktuell gelisteten Bundle-Maps praktisch folgenlos, da sie schon
  heute nur Warnings haben (sonst wären sie im bisherigen Pfad gar nicht
  ladbar gewesen). Neue Methoden `newHarmonyWebDocument(in:)`,
  `openHarmonyWebDocument(at:in:)`, `saveDocument()`, `saveDocumentAs(to:)`,
  private `applyDocument(_:in:)` (gemeinsamer Aufbau der Canvas-Darstellung
  aus einem geladenen/neuen Dokument, gleiche Force-Layout-Strategie wie
  zuvor). `exitHarmonyWebMode(in:)` setzt jetzt `document = nil` statt
  `harmonyMap = nil`.
- **`DesignerCanvasView`** (`import UniformTypeIdentifiers` ergänzt):
  Toolbar im normalen Netzwerk-Modus um zwei kleine Buttons „Neu"
  (`doc.badge.plus`) und „Öffnen…" (`folder`, öffnet `NSOpenPanel` gefiltert
  auf `.json`) erweitert. Toolbar im HarmonyWeb-/Dokumentmodus um einen
  Status-Chip (Dateiname/„Neu"/Template-Name + Dirty-Sternchen, Schloss-Icon
  bei read-only, „N Fehler · M Warnungen") sowie „Speichern"
  (`square.and.arrow.down`, deaktiviert außer bei `origin == .file`) und
  „Speichern unter…" (`square.and.arrow.down.on.square`, öffnet
  `NSSavePanel`) erweitert. `.alert(...)` am View-Body zeigt
  `documentErrorMessage`. Bestehender lokaler `NSEvent`-Tastatur-Monitor
  (bisher nur ⌘E/Tab) um ⌘N/⌘O/⌘S/⇧⌘S ergänzt (⌘S/⇧⌘S nur aktiv im
  Dokumentmodus) — keine `DesignerApp.swift`-Menü-Commands nötig, da der
  bestehende Monitor-/Toolbar-Ansatz für diesen schmalen Scope ausreicht
  (`DesignerApp.swift` unverändert).
- **Keine Security-Scoped Bookmarks/Sandbox-Entitlements** ergänzt (K-02
  läuft ohne Sandbox-Entitlement, wie vom Handoff vorgegeben).
- Neue Tests (15): `Tests/HarmonyAuthoringTests/HarmonyMapDocumentStoreTests.swift`
  (9 — `newDocument` unsaved/nicht dirty/encodierbar, pro Aufruf eindeutige
  ID, `openDocument` setzt File-Origin + sauberen Dirty-State, `saveAs`
  schreibt atomisch + setzt URL/Dirty, `save` auf normalem Datei-Dokument
  schreibt Änderungen, `save` auf ungespeichertem Dokument wirft
  `.noSaveTarget`, Save-Reopen-Roundtrip über `HarmonyMapCodec` erhält
  ID/Name/Nodes/Edges/Layers/Layout, invalider Draft bleibt nach Save-
  Reopen diagnostizierbar, Bundle-Template read-only — `save()` wirft
  `.readOnlyTemplate`, `saveAs()` erzeugt normale Datei) und
  `Tests/HarmonyAuthoringTests/RecentDocumentsStoreTests.swift` (6 —
  Prepend auf leere Liste, Reihenfolge neueste-zuerst, Dedupe bei erneutem
  Record, Limit-Kappung, Persistenz über zwei Store-Instanzen mit gleichen
  `defaults`/`key`, `clear()`). Neue Test-Fixture
  `Tests/HarmonyAuthoringTests/Resources/authoring-template-fixture.json`
  (eigenes `Bundle.module` des Test-Targets, `Package.swift` um
  `resources: [.process("Resources")]` für `HarmonyAuthoringTests`
  ergänzt).
- `Package.swift`: `DesignerKit` hängt jetzt zusätzlich von
  `HarmonyAuthoring` ab.
- Checks: `swift test` grün (150/150 — 135 bestehend + 15 neu), normaler
  Build grün, Strict-Concurrency-Build grün (vollständiger Clean-Rebuild
  vorher/nachher, identische Warnmenge — 482/482, keine neuen, keine
  entfernten), Clean-HEAD strict build + Clean-HEAD `swift test` grün,
  `git diff --check HEAD~1 HEAD` grün. `DesignerKit` und `HarmonyEngine3D`
  manuell direkt gestartet (kein interaktiver GUI-Klick-Test möglich in
  dieser Umgebung — kein Fenstersystem-Zugriff für `NSOpenPanel`/
  `NSSavePanel`-Interaktion): beide starten fehlerfrei, `DesignerKit` lädt
  sein Default-Netzwerk normal, `HarmonyEngine3D` (Explore) feuert weiterhin
  symmetrische CH0/CH1-Sequenzen — bestätigt, dass die Integration keine
  Startup-Regression verursacht; die eigentlichen Dokument-I/O-Pfade sind
  stattdessen vollständig über `HarmonyAuthoringTests` abgesichert (wie vom
  Handoff als Ausweg vorgesehen).
- Kein Canvas-Refactor auf `HarmonyMapDocument` als alleinige Quelle, keine
  `EdgeData`-Entfernung, kein Workspace-Sidecar, keine Drag-/Pin-/Zoom-
  Migration, keine Node-/Edge-/Layer-CRUD-Feature-Suite, kein Issue-
  Navigator/Export-Gate, kein Builder, keine Runtime-/`HarmonyEngine3D`-
  Integration, keine Map-JSON-Schema-Änderung, keine Security-Scoped
  Bookmarks/Sandbox-Entitlements, keine Recent-Documents-UI (nur die
  testbare Datenkomponente — UI-Surfacing bleibt offen, s. o.).

**Nachtrag — K-03: Canvas auf kanonisches Dokument + Workspace-Sidecar
(Codex-Handoff HE3D-CX-2026-07-27-030, Runde 030):** Dritter Slice von
Milestone M2. Beseitigt die letzte musikalische Schattenkopie im
DesignerKit-Dokumentmodus: `HarmonyMapDocument.draft` ist dort jetzt die
einzige Nodes-/Edges-/Layers-Quelle, 2D-Editorzustand (Positionen, Pins,
Zoom, aktiver Layer) lebt getrennt als Workspace-Sidecar.

- **`HarmonyMapWorkspaceState`** (neu, `Sources/HarmonyAuthoring/
  HarmonyMapWorkspaceState.swift`): `positions: [String: WorkspacePoint]`
  (UI-Framework-freier 2D-Punkt, kein `CGPoint` — `HarmonyAuthoring` bleibt
  plattformfrei), `pinnedNodeIDs: Set<String>`, `zoom: Double`,
  `activeLayer: String?`, `version` (Sidecar-Format). Lebt vollständig
  getrennt von `HarmonyMap`/`HarmonyMapDocument` — nie in der Map-JSON,
  keine Codable-Vermischung mit den Shared-Modellen. `HarmonyMapDocument.
  isDirty` beschreibt weiterhin ausschließlich Map-Draft-Mutationen;
  Workspace-Änderungen wirken sich darauf nicht aus.
- **`WorkspaceKey`/`HarmonyMapWorkspaceStore`** (neu, `Sources/
  HarmonyAuthoring/HarmonyMapWorkspaceStore.swift`): Sidecar-Schlüssel pro
  Dokumentursprung — `.file(URL)` (deterministischer FNV-1a-Hash der
  normalisierten Datei-URL; bewusst **kein** `String.hashValue`/`Hasher`,
  die Swift pro Prozessstart zufällig salzen und damit bei jedem Neustart
  einen anderen Sidecar-Dateinamen ergeben würden), `.template(name:)`
  (Bundle-Template-Name), `.unsaved(mapID:)` (Map-ID, gilt nur für die
  laufende Session). Persistenz unter `Application Support/HarmonyAuthoring/
  Workspaces/<slug>.json`, injizierbares `directory`-Argument für Tests.
  `load(for:)` liefert bei fehlendem/nicht dekodierbarem Sidecar einen
  sauberen Default-State statt zu werfen (reines Komfort-Feature, kein
  Error-Pfad nötig); `save(_:for:)` schreibt atomisch, wirft
  `StoreError.write` bei echten Encode-/Dateisystemfehlern. Kein
  Security-Scoped Bookmark, kein neues Entitlement.
- **`LayoutNode.pinned: Bool`** (neu, Default `false` — im Legacy-`.txt`-
  Netzwerkmodus immer `false`, keine Verhaltensänderung dort) und neuer
  privater `LayoutEdge`-Typ (Source/Target/Weight) ersetzen `[EdgeData]` als
  Eingabe für `forceLayout(nodes:edges:size:)` — bewusst nicht `EdgeData`,
  damit die reine Layout-Geometrie nicht mit der Frage verwechselt wird, ob
  `EdgeData` gerade die musikalische Datenquelle ist (im Dokumentmodus ist
  sie das seit K-03 nicht mehr). `forceLayout` überspringt jetzt gepinnte
  Nodes in der Positions-/Velocity-Aktualisierung (nimmt an Abstoßungs-/
  Federkräften weiterhin teil — andere Nodes weichen ihnen aus — wird aber
  selbst nicht bewegt).
- **`DesignerViewModel.applyDocument(_:in:)`** (K-02, jetzt erweitert): baut
  Nodes aus `document.draft.nodes` + geladenem Workspace — existiert für
  einen Node bereits eine gespeicherte Position, wird die vorhandene
  Anordnung respektiert (**kein** automatisches Re-Layout beim Laden). Nur
  für ein wirklich frisches Dokument ohne Sidecar läuft einmalig die
  bisherige Force-Layout-Strategie asynchron, das Ergebnis wird direkt als
  Startzustand persistiert. `edges: [EdgeData]` wird im Dokumentmodus nicht
  mehr aus `map.edges` befüllt (bleibt leer) — Kanten kommen für die Canvas
  ausschließlich aus `webEdgesForDisplay` (bestand bereits seit K-01/vorher,
  war nie eine `EdgeData`-Kopie). `activeLayer`/`zoomScale` werden aus dem
  Workspace übernommen (Fallback: erster Map-Layer / 1.0).
- **Neue Workspace-Methoden**: `saveWorkspace()`, `isPinned(_:)`,
  `togglePin(_:)` (reine Workspace-Mutation, keine Draft-Änderung, sofort
  persistiert), `persistZoomIfDocumentMode()` (Aufrufer entscheiden den
  Zeitpunkt — Zoom-Buttons sofort, Pinch-Geste erst bei `onEnded`, um nicht
  jeden Frame zu schreiben), `persistActiveLayerIfDocumentMode()`,
  `autoLayoutDocument()` (re-simuliert die Anordnung, gepinnte Nodes bleiben
  unverändert, Ergebnis wird vollständig persistiert), `relayoutDocumentCanvas(in:)`
  (Resize-Reaktion für den Dokumentmodus — klammert Positionen auf die neuen
  Canvas-Grenzen statt automatisch neu zu simulieren; kein Re-Layout bei
  jedem Fenster-Resize, das bleibt der expliziten Auto-Layout-Aktion
  vorbehalten). `moveNode(id:by:)` pinnt einen gedragten Node im
  Dokumentmodus implizit und aktualisiert die Workspace-Position (nicht
  `document.draft`); Persistenz erfolgt am Drag-Ende
  (`DesignerCanvasView.dragGesture.onEnded`), nicht bei jedem Delta.
- **K-02-Rest behoben** (Codex-Ruecklaufnotizen Runde 029→030): Der
  Resize-Pfad ruft nicht mehr `loadHarmonyWeb(named:)` auf (war für
  externe/neue Dokumente mit leerem `selectedWebName` ein No-op und hätte
  sie beim Resize durch ein Bundle-Template ersetzen können) — jetzt
  `relayoutDocumentCanvas(in:)`. Der `Package.swift`-Kommentar zur
  `HarmonyAuthoring`-Abhängigkeit ist synchronisiert (DesignerKit hängt seit
  K-02 davon ab). Der Legacy-Edit-Button erzeugt im Dokumentmodus keine
  `EdgeData`-Musikdaten mehr — Tap-zu-Verbinden (`toggleEdge`) ist dort
  deaktiviert, ein Tap bleibt reine Auswahl; derselbe Button schaltet im
  Dokumentmodus stattdessen nur Node-Dragging um (Label „Drag"/„Ansicht"
  statt „Edit"/„Play", `toggleEditMode()` ruft dort `saveWorkspace()` statt
  des `.txt`-Sidecar-`saveLayout()`).
- **`DesignerCanvasView`**: `isHighlighted(_:)` ist jetzt modusabhängig
  (Dokumentmodus liest Adjazenz aus `webEdgesForDisplay`, Legacy-Modus
  weiterhin aus `vm.edges` — vorher fest auf `vm.edges` verdrahtet, wäre mit
  der jetzt leeren `edges`-Liste im Dokumentmodus stumm kaputt gegangen).
  Neue kleine Toolbar-Buttons im Dokumentmodus: Pin/Unpin für den
  selektierten Node (nur sichtbar bei aktivem Drag-Modus + Auswahl),
  Auto-Layout (`arrow.triangle.2.circlepath`). Layer-Picker persistiert den
  aktiven Layer bei Änderung. Bestehende K-02-Buttons (Neu/Öffnen/Speichern/
  Speichern-unter) bleiben unverändert funktionsfähig.
- Neue Tests (10): `Tests/HarmonyAuthoringTests/
  HarmonyMapWorkspaceStoreTests.swift` (6 — Default-State ohne Sidecar/ohne
  Crash, Save-Load-Roundtrip erhält Positionen/Pins/Zoom, vier
  Origin-Varianten erzeugen unterschiedliche stabile Slugs, derselbe
  File-Origin liefert über mehrere Aufrufe denselben Slug, unterschiedliche
  File-Origins sind nicht gegenseitig ladbar, Map-JSON-Encoding enthält
  keine Workspace-Feldnamen) und neues, erstmals praktikables Test-Target
  `Tests/DesignerKitTests/DesignerViewModelWorkspaceTests.swift` (4 —
  `newHarmonyWebDocument` betritt den Dokumentmodus nicht-read-only,
  `moveNode` im Dokumentmodus pinnt und aktualisiert nur den Workspace
  — nicht `document.draft`/`isDirty` —, Dokumentmodus führt keine
  `EdgeData`-Schattenkopie, `relayoutDocumentCanvas` ersetzt ein externes
  Dokument nicht durch ein Bundle-Template). `Package.swift`: neues
  `.testTarget("DesignerKitTests", dependencies: ["DesignerKit"])` — SPMs
  Executable-Testing funktioniert hier, weil `DesignerApp.swift` die
  moderne `@main`-Konvention nutzt. Bekannter, bewusst in Kauf genommener
  Nebeneffekt: `DesignerViewModel`s Workspace-/Dokument-Store-Aufrufe nutzen
  den Default-Pfad (Application Support) ohne Dependency Injection (anders
  als `RecentDocumentsStore`s injizierbare `UserDefaults` aus K-02) — Tests,
  die `applyDocument(_:in:)` durchlaufen, könnten kleine, harmlose
  Sidecar-Dateien unter Tempfile-Pfad-Hashes im echten
  Application-Support-Verzeichnis hinterlassen; eine Directory-Injection-
  Kette durch die ViewModel-API bleibt als Verbesserung für eine spätere
  Runde offen.
- Checks: `swift test` grün (160/160 — 150 bestehend + 10 neu), normaler
  Build grün (inkl. `DesignerKit`), Strict-Concurrency-Build grün
  (vollständiger Clean-Rebuild vorher/nachher — 241/240 Diagnosezeilen,
  identische 22 Warnkategorien, keine neuen; die eine verschobene Zahl ist
  eine erwartete Verbesserung: die Warnung „non-Sendable type '[EdgeData]'
  of property 'edges' cannot exit main actor-isolated context" sinkt von 4
  auf 2 Vorkommen, weil zwei `forceLayout`-Aufrufstellen `self.edges` nicht
  mehr über die Actor-Grenze lesen), Clean-HEAD strict build + Clean-HEAD
  `swift test` grün, `git diff --check HEAD~1 HEAD` grün. `DesignerKit` und
  `HarmonyEngine3D` manuell direkt gestartet (kein interaktiver GUI-
  Klicktest möglich in dieser Umgebung): beide starten fehlerfrei, keine
  Startup-Regression.
- Kein Node Add/Duplicate/Rename/Delete, keine Edge-/Layer-Authoring-
  Feature-Suite, keine RelationType-/MagnetPreset-UI, kein Issue-Navigator/
  Export-Gate, kein Builder, keine Runtime-/`HarmonyEngine3D`-Integration,
  keine Map-JSON-Schema-Änderung, keine Workspace-Daten im Map-JSON, keine
  Security-Scoped Bookmarks/Sandbox-Entitlements.

**Nachtrag — K-04: Node-Authoring — Add/Duplicate/Rename/Delete + Inspector
(Codex-Handoff HE3D-CX-2026-07-27-031, Runde 031):** Vierter Slice von
Milestone M2. Erstes echtes Authoring-Werkzeug: Nodes lassen sich im
HarmonyWeb-/Dokumentmodus erstellen, duplizieren, umbenennen, löschen und
über einen vollständigen Inspector bearbeiten. Jede fachliche Mutation
läuft ausschließlich über `HarmonyMapCommand`/`HarmonyMapDocument.perform(_:)`
— `document.draft` bleibt die einzige musikalische Datenquelle, Workspace
bleibt Sidecar.

- **Fünf neue Commands** (`Sources/HarmonyAuthoring/
  NodeAuthoringCommands.swift`): `AddNodeCommand` (fügt genau eine Node an,
  rejectet leere/doppelte ID, ändert nur die Node-Liste), `DuplicateNodeCommand`
  (kopiert Root/Type/Function/MIDI/Tags/Layers/layout3D, generiert eine
  deterministisch freie ID über `NodeIDGenerator` — `<id>-copy`,
  `<id>-copy-2`, ...; keine Edges), `RenameNodeCommand` (benennt eine Node
  atomar um UND aktualisiert im selben Apply alle `HarmonyEdge.source`/
  `target`-Referenzen — da `HarmonyMapDocument.perform(_:)` den neuen Draft
  ohnehin nur bei vollständigem Erfolg übernimmt, kann zu keinem
  Zwischenzeitpunkt eine dangling Referenz entstehen; No-op-Rename
  `newID == nodeID` ist bewusst deterministisch ein Erfolg mit
  unverändertem Draft, kein Fehler), `DeleteNodeCommand` (entfernt die Node
  UND alle inzidenten Kanten im selben Apply — referenzielle
  Cleanup-Semantik, kein K-05-Edge-Authoring), `UpdateNodeCommand` (Root/
  Type/Function/MIDI/Tags/Layers/layout3D; MIDI muss nicht-leer und
  0...127 bleiben, Layers dürfen nur bestehende Layer-IDs referenzieren
  oder `nil`/leer sein). `NodeIDGenerator.freeID(base:existingIDs:)` ist
  eine gemeinsame, deterministische Utility (kein Zufall) — `Duplicate`
  nutzt sie intern, `DesignerViewModel` spiegelt sie vorab mit identischer
  Basis, um die vom Command intern erzeugte ID zu kennen, ohne den Draft
  nach der Antwort diffen zu müssen.
- **`DesignerViewModel`**: `performNodeCommand(_:onSuccess:)` ist der
  gemeinsame Erfolgs-/Fehlerpfad aller Node-Mutationen — übernimmt den
  Draft nur bei Erfolg, ruft danach `onSuccess` (z. B. Rename-Workspace-
  Migration, die noch die alte/neue ID braucht) und erst danach
  `syncNodesFromDraft()`. `syncNodesFromDraft()` baut `nodes: [LayoutNode]`
  komplett aus `document.draft.nodes` neu auf — bestehende Canvas-Position/
  Pin bleiben für weiterhin existierende Nodes erhalten, neue Nodes (Add/
  Duplicate) ohne bekannte Position bekommen eine deterministische
  Fallback-Position nahe dem Canvas-Mittelpunkt (Offset nach Node-Index),
  und räumt abschließend verwaiste Workspace-Positionen/-Pins sowie eine
  Selection auf eine nicht mehr existierende ID auf. `migrateWorkspace(from:to:)`
  wandert Workspace-Position/Pin/Selection von der alten auf die neue ID —
  läuft als `onSuccess`-Closure einer erfolgreichen `RenameNodeCommand` VOR
  `syncNodesFromDraft()`, damit der generische Resync die migrierte
  Position unter der neuen ID vorfindet statt eine Fallback-Position zu
  vergeben. Neue Methoden `addNode()` (rein technischer Platzhalter-
  Default: Root C, Dur-Dreiklang, eine einzelne MIDI-Note 60 — bewusst
  keine musikalische Builder-Entscheidung, nur ein sofort editierbares,
  valides Objekt; selektiert den neuen Node sofort), `duplicateSelectedNode()`
  (platziert die Kopie leicht versetzt neben dem Original statt am
  Canvas-Mittelpunkt), `renameSelectedNode(to:)`, `deleteSelectedNode()`,
  `updateSelectedNode(root:type:function:midiNotes:tags:layers:layout3D:)`.
  Neues Dokument-Undo/Redo: `undoDocument()`/`redoDocument()`/
  `canUndoDocument`/`canRedoDocument` (ruft `document.undo()`/`.redo()`,
  synct Canvas/Workspace identisch zum Command-Pfad).
- **`DesignerCanvasView`**: neue Toolbar-Buttons Add (`plus.circle`),
  Duplicate (`doc.on.doc`), Rename (Inline-`TextField` + Bestätigen/
  Abbrechen statt Dialog), Delete (`trash`, rückgängig via Undo — bewusst
  keine zusätzliche Bestätigungs-Dialog, da Undo direkt verfügbar ist),
  Undo/Redo (`arrow.uturn.backward/forward.circle`, deaktiviert wenn nicht
  verfügbar) — alle nur sichtbar/aktiv im Dokumentmodus. Tastaturkürzel
  ⌘Z/⇧⌘Z im bestehenden `NSEvent`-Monitor ergänzt (nur im Dokumentmodus
  aktiv). Neuer **Node-Inspector** (`nodeInspector(for:)`, Trailing-Overlay
  im selben Stil wie `settingsPanel`, weicht bei geöffneten Settings
  zurück statt zu überlappen): Root-Stepper, Type-/Function-Picker
  (`ChordType`/`HarmonicFunction`, jetzt `CaseIterable` — siehe unten),
  MIDI-Notes/Tags als kommagetrennte Textfelder, Layer-Zugehörigkeit als
  Checkbox-Liste über `vm.availableLayers`, optionales `layout3D` (x/y/z-
  Textfelder), Diagnose-Zusammenfassung. Alle Felder sind lokaler `@State`,
  der bei Auswahlwechsel neu synchronisiert wird (`syncInspectorFields`) —
  ein einzelner „Anwenden"-Command pro Bearbeitungssession statt eines
  Commands pro Tastenanschlag (hätte sonst den Undo-Stack geflutet).
- **`Sources/HarmonyShared/HarmonyModel.swift`**: `ChordType`/
  `HarmonicFunction` bekommen zusätzlich `CaseIterable` (rein additive
  Protokoll-Konformität, keine Codable-/Schema-/Validator-Semantik-
  Änderung) — für die Inspector-Picker benötigt.
- Neue Tests (32): `Tests/HarmonyAuthoringTests/
  NodeAuthoringCommandsTests.swift` (26 — `NodeIDGenerator` Basis-frei/
  Suffix-Inkrement, Add Erfolg/doppelte-ID/leere-ID, Duplicate generiert
  freie ID + kopiert Felder + zweite Duplikation bekommt `-copy-2` +
  unbekannte Quelle wirft, Rename aktualisiert Edge-source-UND-target-
  Referenzen atomar + No-op-Erfolg + unbekannte-alte-ID/leere-neue-ID/
  doppelte-neue-ID werfen und lassen Draft/Dirty/Revision unverändert,
  Delete entfernt Node + inzidente Edges + lässt unbeteiligte Edges
  unangetastet + unbekannte ID wirft, Update setzt alle Felder + leere/
  außerhalb-0...127-MIDI-Notes/unbekannter-Layer werfen, Undo/Redo über
  Rename und Delete stellen Draft/Edges korrekt wieder her, Diagnostics
  bleiben nach Delete/Update aktuell) und `Tests/DesignerKitTests/
  DesignerViewModelNodeAuthoringTests.swift` (6 — Add/Duplicate/Rename/
  Delete aktualisieren `document.draft`, `nodes` und Workspace konsistent,
  Rename migriert Workspace-Position/Pin/Selection, Delete entfernt
  Workspace-Position/Pin/Selection + inzidente Edges, Update mutiert Draft
  via Command und setzt dirty, Undo/Redo über Delete aktualisieren Canvas
  und Diagnostics).
- Checks: `swift test` grün (192/192 — 160 bestehend + 32 neu), normaler
  Build grün (inkl. `DesignerKit`), Strict-Concurrency-Build grün
  (vollständiger Clean-Rebuild vorher/nachher: 240/240 identische
  Diagnosezeilen, exakt gleiche Warnkategorien, keine neuen), Clean-HEAD
  strict build + Clean-HEAD `swift test` grün, `git diff --check HEAD~1
  HEAD` grün. `DesignerKit` und `HarmonyEngine3D` manuell direkt gestartet
  (kein interaktiver GUI-Klicktest möglich in dieser Umgebung — kein
  Fenstersystem-Zugriff für Inspector-/Button-Interaktion): beide starten
  fehlerfrei, keine Startup-Regression; Node-Authoring-Pfade vollständig
  über `HarmonyAuthoringTests`/`DesignerKitTests` abgesichert.
- Kein Edge-Authoring aus K-05 (außer dem vorgegebenen Rename-
  Referenzupdate und Delete-Cleanup inzidenter Edges), kein Layer Add/
  Rename/Delete, keine RelationType-/MagnetPreset-UI, kein Issue-Navigator/
  Export-Gate, kein Builder, keine `HarmonyEngine3D`-Runtime-Integration,
  keine Map-JSON-Schema-Änderung, keine Security-Scoped Bookmarks/
  Sandbox-Entitlements.

**Nachtrag — K-05: Edge-/Layer-Authoring (Codex-Handoff
HE3D-CX-2026-07-27-032, Runde 032):** Fünfter Slice von Milestone M2.
Erweitert das Construction Kit auf Kanten und Layer — referenzsicheres
Edge-/Layer-Authoring mit Live-Validation, ohne neue musikalische Semantik,
Runtime-Integration oder Map-Schema-Änderung.

- **Drei neue Edge-Commands** (`Sources/HarmonyAuthoring/
  EdgeAuthoringCommands.swift`): `AddEdgeCommand` (rejectet leere/doppelte
  Edge-ID, unbekannte source/target, leere relationTypes, nicht-endliches/
  ≤0-weight, unbekannte Layer-IDs), `DeleteEdgeCommand` (entfernt genau
  eine Edge, ändert keine Nodes/Layers), `UpdateEdgeCommand` (source/
  target/directed/relationTypes/layers/weight/magnetProfile/bridgesTo,
  Edge-ID bleibt erhalten — kein Edge-Rename-Konzept, anders als bei Nodes/
  Layern —, dieselben Referenz-/Gewichts-/RelationType-/Layer-Checks wie
  `AddEdgeCommand`).
- **Drei neue Layer-Commands** (`Sources/HarmonyAuthoring/
  LayerAuthoringCommands.swift`): `AddLayerCommand` (rejectet leere/
  doppelte ID, leeren RelationType-Katalog, keine automatische Edge-/Node-
  Erzeugung), `UpdateLayerCommand` (ID-Rename + Name/RelationTypes-Update
  in einem Apply — bei ID-Änderung werden im selben Apply alle
  `HarmonyEdge.layers`- und alle expliziten `HarmonyNode.layers`-Einträge
  atomar mitmigriert; No-op-Rename ist wie bei `RenameNodeCommand`
  deterministisch ein Erfolg), `DeleteLayerCommand` (entfernt den Layer UND
  die Layer-ID aus allen Edge-/Node-Layerlisten im selben Apply —
  referenzielle Cleanup-Semantik analog `DeleteNodeCommand`s Edge-Cleanup;
  entfernt keine Nodes/Edges selbst, kann dadurch andernorts Validator-
  Warnings/-Errors erzeugen, aber nie eine dangling Layer-ID-Referenz).
  `AuthoringIDGenerator` (K-04s `NodeIDGenerator` umbenannt — reine
  Umbenennung, gleicher Algorithmus, jetzt über Node-/Edge-/Layer-Commands
  hinweg geteilt).
- **`DesignerViewModel`**: `performNodeCommand` in `performDocumentCommand`
  umbenannt (war bereits generisch über jeden `HarmonyMapCommand`, jetzt
  auch für Edge-/Layer-Mutationen genutzt — keine funktionale Änderung).
  `syncNodesFromDraft()` bereinigt zusätzlich `selectedDocumentEdgeID`/
  `selectedLayerID` bei nicht mehr existierenden IDs (z. B. wenn ein
  Delete-Node eine inzidente Edge mitentfernt hat) und fällt `activeLayer`
  auf den ersten verbleibenden Layer zurück, falls der bisherige entfernt
  wurde — inklusive `workspace.activeLayer`, damit der persistierte
  Sidecar-Zustand nicht hinter dem sichtbaren UI-Zustand zurückbleibt.
  Neue Methoden `addEdge(from:to:)` (Platzhalter-Default `relationTypes:
  [.commonTone]`, `directed: true`, keine Layer — wie `addNode()`s
  Default in K-04 bewusst nur ein sofort editierbares, valides Objekt,
  keine musikalische Entscheidung; ID deterministisch aus `source-target`
  via `AuthoringIDGenerator`), `deleteSelectedEdge()`,
  `updateSelectedEdge(...)`, `addLayer()`/`addLayer(id:name:relationTypes:)`,
  `updateLayer(...)`, `deleteLayer(...)`. Neue `@Published`-Properties
  `selectedDocumentEdgeID` (getrennt von `selectedEdge`, dem Legacy-`.txt`-
  Tupel ohne stabile ID), `selectedLayerID`, `showLayerManager`.
- **`DesignerCanvasView`** (`import HarmonyAuthoring` ergänzt): Tap-zu-
  Verbinden-Gesture (bisher nur Legacy-`.txt`-Modus) läuft im Dokumentmodus
  jetzt wieder — über `AddEdgeCommand` statt direkter `EdgeData`-Mutation,
  Auswahl bleibt reine Auswahl. Neue Toolbar-Controls: kompakter Edge-
  Picker (Auswahl per ID-Liste statt Canvas-Hit-Testing auf Kantenlinien —
  bewusste UI-Vereinfachung, s. u.) + Delete-Button, Layer-Manager-Toggle.
  Neuer **Edge-Inspector** (Trailing-Overlay, gleiche Priorität-vor-Node-
  Inspector-Logik wie Settings vor allen anderen Panels): source-/target-
  Picker, directed-Toggle, RelationType-Checkboxen, Gewicht-Textfeld,
  MagnetPreset-Picker, Layer-Checkboxen, optionales bridgesTo — ein
  „Anwenden"-Command pro Bearbeitungssession. Neuer **Layer-Manager**
  (eigenes Trailing-Overlay): Liste bestehender Layer mit Rename-/Delete-
  Icon-Buttons, Formular für Add/Update (ID/Name/RelationType-Checkboxen)
  vorbefüllt mit einer sofort editierbaren Platzhalter-ID (analog zum Node-/
  Edge-Add-Default) statt leerer Felder. Layer-Solo/Overlay bleibt der
  bereits seit vor K-03 bestehende `activeLayer`/Layer-Picker in der
  Toolbar (Workspace-Zustand, `HarmonyMapWorkspaceState.activeLayer`) — der
  Layer-Manager verwaltet nur den Layer-Katalog selbst, keine neue
  Sichtbarkeits-Mechanik.
- **`Sources/HarmonyShared/HarmonyModel.swift`**: `RelationType` und
  `MagnetProfile.Preset` bekommen zusätzlich `CaseIterable` (rein additive
  Protokoll-Konformität, keine Codable-/Schema-/Validator-Semantik-
  Änderung, keine neuen Cases) — für die Edge-/Layer-Inspector-Picker
  benötigt.
- **Bewusste UI-Vereinfachung**: keine präzise Canvas-Hit-Testing-Logik für
  Kantenlinien (dünne Linien exakt anzuklicken wäre deutlich mehr
  Geometrie-Code für wenig Zusatznutzen) — Edge-Auswahl läuft stattdessen
  über eine kompakte Picker-Liste nach `source→target`-Label, konsistent
  mit „UI klein halten".
- Neue Tests (46): `Tests/HarmonyAuthoringTests/
  EdgeAuthoringCommandsTests.swift` (21 — Add Erfolg/leere-doppelte-ID/
  unbekannte-source-target/leere-relationTypes/nicht-endliches-null-
  negatives-weight/unbekannter-Layer, Delete Erfolg/unbekannte-ID, Update
  Erfolg + dieselben Fehlerpfade, Undo/Redo über Add/Delete/Update) und
  `LayerAuthoringCommandsTests.swift` (16 — Add Erfolg/doppelte-leere-ID/
  leere-relationTypes, Rename migriert Edge- und Node-Layerlisten atomar,
  Content-only-Update lässt Layerlisten unangetastet, Delete entfernt Layer-
  Referenzen aus Edges/Nodes ohne Nodes/Edges selbst zu löschen, Undo/Redo
  über Rename/Delete, Diagnostics bleiben nach Mutation aktuell) sowie
  `Tests/DesignerKitTests/DesignerViewModelEdgeLayerAuthoringTests.swift`
  (9 — Edge Add/Delete/Update aktualisieren Draft und
  `webEdgesForDisplay`, Layer Add/Rename/Delete aktualisieren Draft und
  Workspace/Selection inkl. `activeLayer`-Migration/-Fallback,
  `activeLayer` landet nachweislich nicht in der Map-JSON-Kodierung, Undo/
  Redo über Add-Edge und Delete-Layer aktualisieren Canvas/Status).
- Checks: `swift test` grün (238/238 — 192 bestehend + 46 neu), normaler
  Build grün (inkl. `DesignerKit`), Strict-Concurrency-Build grün
  (vollständiger Clean-Rebuild vorher/nachher: 240/240 identische
  Diagnosezeilen, exakt gleiche Warnkategorien, keine neuen), Clean-HEAD
  strict build + Clean-HEAD `swift test` grün, `git diff --check HEAD~1
  HEAD` grün. `DesignerKit` und `HarmonyEngine3D` manuell direkt gestartet
  (kein interaktiver GUI-Klicktest möglich in dieser Umgebung): beide
  starten fehlerfrei, keine Startup-Regression; Edge-/Layer-Authoring-Pfade
  vollständig über Tests abgesichert.
- Kein Issue-Navigator/Export-Gate aus K-06, keine runtime-nahe Simulation
  aus K-07, kein Builder aus K-08, keine `HarmonyEngine3D`-Runtime-
  Integration, keine neuen RelationType-/ChordType-/HarmonicFunction-/
  MagnetProfile-Cases, keine automatische musikalische Edge-/Layer-
  Generierung, keine Map-JSON-Schema-Änderung, keine Workspace-Daten in der
  Map-JSON, keine Security-Scoped Bookmarks/Sandbox-Entitlements.

**Nachtrag — K-06: Issue-Navigator + Export-Gate (Codex-Handoff
HE3D-CX-2026-07-27-033, Runde 033):** Sechster Slice von Milestone M2 —
macht den Editor belastbar für echte Nutzung. Validator-Issues sind sicht-
und klickbar, Draft-Save bleibt bei Errors erlaubt, Runtime-Export wird bei
Errors blockiert und erlaubt Warnings. Keine Runtime-Integration, kein
neues Schema.

- **`IssueFocusTarget`** (neu, `Sources/HarmonyAuthoring/
  IssueFocusTarget.swift`, UI-frei): `.node(id:)`/`.edge(id:)`/`.layer(id:)`/
  `.global` — `parse(objectPath:)` erkennt die heutigen Validator-Pfadformen
  `$.nodes[id]`/`$.edges[id]`/`$.layers[id]`, alles andere (inkl.
  `$.schemaVersion`, `$.nodes`/`$.edges`/`$.layers` ohne Klammer-Suffix,
  jeder unbekannte/malformte Pfad) fällt robust auf `.global` zurück statt
  zu crashen. Keine Änderung an `HarmonyMapValidator`-Regeln/-Codes.
- **`HarmonyMapValidator.Issue` bekommt einen public Initializer** (additiv,
  reine Value-Konstruktion, keine Regel-/Code-/Severity-Änderung) — erlaubt
  `DesignerKitTests`, Test-Issues ohne echten Validator-Lauf zu
  konstruieren.
- **`DesignerViewModel.focusIssue(_:)`** (neu): parst das Issue-`objectPath`
  über `IssueFocusTarget`, prüft, ob das Zielobjekt im aktuellen Draft noch
  existiert (sonst No-op, kein Crash), und setzt exklusiv genau eine
  Node-/Edge-/Layer-Selektion (löscht die jeweils anderen zwei) — Node
  öffnet den Node-Inspector, Edge den Edge-Inspector, Layer öffnet den
  Layer-Manager und synct dessen Bearbeitungsformular (`.onChange(of:
  vm.selectedLayerID)` in `DesignerCanvasView`, nicht nur der bisherige
  Pencil-Button-Pfad). `.global`-Issues ändern die Selektion bewusst nicht.
  Da `document.diagnostics` bei jeder Command-Mutation/jedem Undo/Redo
  bereits automatisch aktualisiert wird (seit K-01) und `document` ein
  `@Published`-Wert ist, zeigt der Navigator immer den aktuellen Stand ohne
  eigene Nachführlogik.
- **Export-Gate** (`DesignerViewModel`): `canExportToRuntime`
  (`document.validatedSnapshot() != nil`), `exportGateStatusText`
  ("Export bereit"/"Export bereit (N Warnungen)"/"Export blockiert (N
  Fehler)"), `exportValidatedMap() -> HarmonyMap?` (reiner Daten-Pfad, kein
  Dateischreiben), `exportDocumentAs(to:)` (schreibt — s. u.). Draft-Save
  (`saveDocument()`/`saveDocumentAs(to:)`, unverändert seit K-02) bleibt
  bewusst vollständig vom Export-Gate getrennt und ungegatet.
- **`exportDocumentAs(to:)` schreibt eine Datei**, aber nur wenn
  `validatedSnapshot()` erfolgreich ist (sonst strukturierter
  `documentErrorMessage` statt stillem No-op) — exakt dieselbe kanonische
  `HarmonyMapCodec.encode`-Repräsentation wie jeder andere Save-Pfad, kein
  eigenes Exportformat. Schreibt bewusst NICHT über
  `HarmonyMapDocumentStore.saveAs` und ändert daher `document.origin`/
  `.isDirty` nicht — Export ist kein „Speichern unter" für das Dokument
  selbst (das würde fälschlich die Dokumentidentität auf die Export-Datei
  umbiegen), sondern eine separate validierte Kopie.
- **`DesignerCanvasView`**: neuer Issue-Navigator-Toolbar-Button
  (Fehleranzahl-Badge, nur sichtbar wenn Issues vorhanden) mit Trailing-
  Overlay-Panel (Severity-Icon, Code, objectPath, Message pro Issue, Klick
  ruft `vm.focusIssue(_:)`); neuer Export-Toolbar-Button (`shippingbox`,
  Farbe zeigt `canExportToRuntime`) öffnet `NSSavePanel` mit eigenem Titel
  „Validierten HarmonyWeb-Export speichern" (bewusst kein Save-As-Alias).
  Overlay-Priorität erweitert: Settings > Issue-Navigator > Layer-Manager >
  Edge-Inspector > Node-Inspector — `focusIssue(_:)` schließt den Navigator
  bei erfolgreichem Fokus selbst, damit das Zielpanel im nächsten Render
  sichtbar wird.
- Neue Tests (21): `Tests/HarmonyAuthoringTests/IssueFocusTargetTests.swift`
  (7 — Node-/Edge-/Layer-Pfad, `$.schemaVersion`, Klammer-lose
  Sammlungspfade, leere/malformte/unbekannte Pfade fallen auf `.global`
  zurück, Sonderzeichen in IDs werden verbatim extrahiert) und
  `ExportGateTests.swift` (4 — invalider Draft bleibt speicher-/wieder-
  öffenbar mit sichtbaren Diagnostics und weiterhin blockiertem Export,
  valider Draft exportiert denselben semantischen Inhalt nach Reopen,
  Warnings blockieren Export nicht, Draft-Save ist nachweislich nicht vom
  Validator gegatet) sowie `Tests/DesignerKitTests/
  DesignerViewModelIssueExportTests.swift` (10 — Issue-Klick selektiert
  Node/Edge/Layer exklusiv und schließt andere Panels, globale Issues
  lassen die Selektion unverändert, Fokus auf ein gelöschtes Objekt ist
  No-op ohne Crash, Export-Gate blockiert Errors/erlaubt Warnings,
  Export-Gate-Status ändert sich korrekt nach Undo/Redo, Export schreibt
  den kanonischen `HarmonyMapCodec`-Inhalt bei validem Draft, Export
  blockiert mit Fehlertext und schreibt keine Datei bei invalidem Draft,
  Draft-Save bleibt trotz Validator-Errors unblockiert).
- Checks: `swift test` grün (259/259 — 238 bestehend + 21 neu), normaler
  Build grün (inkl. `DesignerKit`), Strict-Concurrency-Build grün
  (vollständiger Clean-Rebuild vorher/nachher: 240/240 identische
  Diagnosezeilen, exakt gleiche Warnkategorien, keine neuen), Clean-HEAD
  strict build + Clean-HEAD `swift test` grün, `git diff --check HEAD~1
  HEAD` grün. `DesignerKit` und `HarmonyEngine3D` manuell direkt gestartet
  (kein interaktiver GUI-Klicktest möglich in dieser Umgebung): beide
  starten fehlerfrei, keine Startup-Regression; Issue-/Export-Pfade
  vollständig über Tests abgesichert.
- Keine runtime-nahe Simulation aus K-07, kein Builder aus K-08, keine
  `HarmonyEngine3D`-Runtime-Integration oder „In 3D prüfen", kein
  automatischer App-Start/URL-Scheme/Import-Bridge/Deployment, keine
  Map-JSON-Schema-Änderung, keine Workspace-Daten in der Map-JSON, keine
  neuen Validator-Regeln, keine Edge-/Layer-/Node-Authoring-Semantik über
  die Fokus-/UI-Fixes hinaus.

**Nachtrag — K-07: Runtime-nahe 2D-Simulation (Codex-Handoff
HE3D-CX-2026-07-27-034, Runde 034):** Siebter Slice von Milestone M2. Das
Construction Kit bekommt eine 2D-Simulation, die exakt dieselbe
`HarmonyGraphEngine` nutzt wie die 3D-Runtime — keine nachgebaute
Parallel-HarmonyLogic.

- **`HarmonicMagnetFieldKind` + `HarmonicMagnetPreview`** (neu, `Sources/
  HarmonyShared/HarmonicMagnetPreview.swift`): `HarmonicMagnetFieldKind` war
  bisher privat in `HarmonyEngine3D/RuntimeHarmonik.swift` deklariert — nach
  `HarmonyShared` verschoben, weil `DesignerKit` `RuntimeHarmonik` nicht
  importieren kann (liegt im `HarmonyEngine3D`-Executable-Target), aber
  dieselbe Feldklassifikation für die Simulation-Preview braucht.
  `HarmonicMagnetPreview.fieldKind(for:)` (relationTypes → Feldkategorie,
  identische Prioritätsreihenfolge wie zuvor), `.baseRange(for:)`/
  `.effectiveRange(preset:rangeScale:)` (Preset → Basis-/effektive
  Reichweite, identische Preset→Meter-Zuordnung: strong 25, medium 15,
  weak 8) — reine, deterministische Werte-Funktionen, kein SceneKit, kein
  AppSettings.
- **`RuntimeHarmonik.swift` delegiert** auf `HarmonicMagnetPreview` statt
  eigener Kopien: die private `magnetFieldKind(for:)`-Methode und
  `HarmonicMagnetConfig.baseRange(for:)` sind entfernt,
  `HarmonicMagnetConfig.effectiveRange(preset:config:)` ruft jetzt
  `HarmonicMagnetPreview.effectiveRange(preset:rangeScale:)` auf. Behavior-
  identisch — bestätigt durch die unveränderten `HarmonicMagnetConfigTests`
  (12/12 grün ohne jede Anpassung) und einen manuellen HarmonyWeb-Live-Start
  mit identischer `[RuntimeHarmonik]`-Log-Ausgabe (Feld/Range-Werte
  unverändert). Einzige berührte Datei in `Sources/HarmonyEngine3D/*` — wie
  vom Handoff vorgegeben (`HarmonyScene.swift`/`FlightController.swift`/
  `AppSettings.swift`/`HarmonyEngine3DApp.swift` referenzieren
  `HarmonicMagnetFieldKind`/`HarmonicMagnetConfig` weiterhin unqualifiziert
  über das bereits bestehende `import HarmonyShared` — keine Änderung an
  diesen Dateien nötig, reine transparente Typ-Umsiedlung).
- **`HarmonyGraphSimulation`** (neu, `Sources/HarmonyAuthoring/
  HarmonyGraphSimulation.swift`, UI-frei): hält intern eine
  `HarmonyGraphEngine`-Instanz (dieselbe Klasse, die `RuntimeHarmonik`
  nutzt) und exponiert `currentNodeID`/`activeLayer`/`seed`/`history`/
  `candidates` (aus `HarmonyGraphEngine.weightedTransitions(from:)`,
  angereichert um `fieldKind`/`magnetPreset`/`effectiveRange` aus
  `HarmonicMagnetPreview`). `step()` nutzt `HarmonyGraphEngine.
  weightedChoice(from:)`, `setLayer(_:)` delegiert auf `HarmonyGraphEngine.
  setLayer(_:)`. `reset()` baut eine frische `HarmonyGraphEngine` mit
  identischem Seed/Start-Node/Layer auf — reproduziert exakt dieselbe
  deterministische Step-Sequenz. History-Vertrag identisch zu
  `RuntimeHarmonik.process()`: der aktuelle Node gilt als besucht
  (`recordVisit`), bevor die nächsten Kandidaten ausgewertet werden.
- **`DesignerViewModel`**: `canRunSimulation` (`document.
  validatedSnapshot() != nil` — derselbe Gate-Vertrag wie K-06s Export-
  Gate), `simulationStatusText` (teilt sich den Text mit
  `exportGateStatusText` bei erlaubtem Zustand, verweist bei Errors explizit
  auf Issues). `startSimulation(from:)`/`stepSimulation()`/
  `resetSimulation()`/`setSimulationLayer(_:)` prüfen alle `canRunSimulation`
  vor jeder Aktion — Draft-Errors blockieren, Warnings erlauben.
  `stopSimulation()` beendet die laufende Simulation.
- **`DesignerCanvasView`**: neuer Simulation-Toolbar-Button (Play-Icon,
  Farbe zeigt `canRunSimulation`) mit Trailing-Overlay-Panel — Start-Node-/
  Seed-Eingabe vor dem Start, danach aktueller Node/Layer/Seed/History/
  Kandidatenliste (RelationTypes, Feldkategorie, MagnetPreset, effektive
  Range, effektives Gewicht — alle aus `HarmonyGraphSimulation`, keine
  eigene Berechnung) plus Step-/Reset-/Stop-Buttons. Layerwechsel im Panel
  läuft über `HarmonyGraphSimulation.setLayer(_:)`. Overlay-Priorität
  erweitert: Settings > Issue-Navigator > Simulation > Layer-Manager >
  Edge-Inspector > Node-Inspector.
- Neue Tests (24): `Tests/HarmonySharedTests/
  HarmonicMagnetPreviewTests.swift` (9 — Feldkategorie-Prioritätsreihenfolge
  für alle sechs Ausgänge, Preset→Range-Zuordnung inkl. `nil`-Fallback,
  `rangeScale`-Multiplikation) und `Tests/HarmonyAuthoringTests/
  HarmonyGraphSimulationTests.swift` (8 — deterministische Step-Sequenz bei
  festem Seed über zwei unabhängige Instanzen, Reset reproduziert dieselbe
  Sequenz, Reset stellt Node/Layer/History wieder her, aktiver Layer
  filtert Kandidaten wie `HarmonyGraphEngine`, unbekannte Layer-ID ist
  No-op, effektive Gewichte stimmen exakt mit einer parallel aufgebauten
  `HarmonyGraphEngine`-Referenz überein, ii-V-Boost wirkt nach einem Schritt
  durch eine ii-V-Kante, Preview-Felder eines Kandidaten stimmen mit direkt
  aufgerufenem `HarmonicMagnetPreview` überein) sowie `Tests/
  DesignerKitTests/DesignerViewModelSimulationTests.swift` (7 — Start
  blockiert bei Errors/nicht bei reinen Warnings, Step aktualisiert
  Current/History, Step blockiert bei Errors, Layerwechsel aktualisiert
  Kandidaten und `activeLayer`, Reset mit gleichem Seed reproduziert die
  Sequenz, Kandidaten zeigen effektive Gewichte + Preview-Felder aus der
  Simulation).
- Checks: `swift test` grün (283/283 — 259 bestehend + 24 neu), normaler
  Build grün (inkl. `DesignerKit`), Strict-Concurrency-Build grün
  (vollständiger Clean-Rebuild vorher/nachher: 240/240 identische
  Diagnosezeilen, exakt gleiche Warnkategorien, keine neuen), Clean-HEAD
  strict build + Clean-HEAD `swift test` grün, `git diff --check HEAD~1
  HEAD` grün. `DesignerKit` und `HarmonyEngine3D` manuell direkt gestartet
  (kein interaktiver GUI-Klicktest möglich in dieser Umgebung): beide
  starten fehlerfrei, keine Startup-Regression. Zusätzlich `HarmonyEngine3D`
  im HarmonyWeb-Modus gestartet, um die `RuntimeHarmonik`-Delegation direkt
  zu verifizieren — `[RuntimeHarmonik]`-Log zeigt weiterhin korrekte Feld-/
  Range-Werte (`field: substitution [tritSubst] ... range=15.0`).
- Kein Builder aus K-08, keine `HarmonyEngine3D`-Runtime-Integration oder
  „In 3D prüfen", kein automatischer App-Start/URL-Scheme/Import-Bridge/
  Deployment, keine Map-JSON-Schema-Änderung, keine Workspace-Daten in der
  Map-JSON, keine neuen RelationTypes/MagnetProfile/ChordTypes/
  musikalischen Regeln, keine alternative Graph-/Weight-/Layer-Logik im
  DesignerKit.

**Nachtrag — K-08: Erster regelbasierter diatonischer Builder (Codex-Handoff
HE3D-CX-2026-07-27-035, Runde 035) — Milestone M2 vollständig
abgeschlossen:** Achter und letzter Slice von Milestone M2 (HarmonyWeb
Construction Kit V1). Der Builder erzeugt einen transparenten Vorschlags-
Diff, den der Nutzer per Apply in einem einzigen Schritt übernimmt oder per
Cancel folgenlos verwirft.

- **`DiatonicHarmonyBuilder` + `HarmonyBuilderDiff` + `HarmonyBuilderConfig`**
  (neu, `Sources/HarmonyAuthoring/DiatonicHarmonyBuilder.swift`, UI-frei):
  reine, seiteneffektfreie Funktion `proposeDiff(for:config:)` — gleicher
  Input liefert immer denselben Diff, keine Zufallswerte. V1 bewusst schmal:
  feste Tonart als Pitch-Class-Parameter (Default C), fest Dur/Ionian, sieben
  diatonische Stufenakkorde (I–vii°) nach Standard-Funktionsharmonik (Piston:
  Tonic I/iii/vi, Subdominant ii/IV, Dominant V/vii°) plus sieben stufenweise
  Nachbarschafts-Kanten im geschlossenen Ring (I-ii-iii-IV-V-vi-vii-I),
  durchgehend `commonTone` statt `.vToI`/`.iiToV` — eine funktionale
  Progressions-Aussage wäre „ii-V-I-Automatik" und ist expliziter
  Nicht-Scope, eine strukturelle Stufennachbarschaft ist es nicht. Stabile
  IDs (`<Tonart>-<Stufe>`, z. B. `C-I`, `C-ii`) und stabile Reihenfolge.
  Existiert eine Node-/Edge-ID bereits, wird sie übersprungen und als
  `HarmonyBuilderDiff.Warning` gemeldet statt still überschrieben; ein
  optionaler Ziel-Layer, der im Dokument nicht existiert, erzeugt ebenfalls
  eine Warnung und wird bei der Zuordnung ausgelassen statt einen
  unbekannten Layer zu referenzieren.
- **`ApplyHarmonyBuilderDiffCommand`** (neu, selbe Datei): wendet den
  gesamten Diff als EIN `HarmonyMapCommand` an — `HarmonyMapDocument.
  perform(_:)` macht daraus automatisch genau einen Undo-Schritt für den
  kompletten Apply, keine Node-für-Node-Historie. Referenzsicher wie
  `AddNodeCommand`/`AddEdgeCommand`: prüft erneut auf doppelte IDs/
  unbekannte source-target-/Layer-Referenzen, unabhängig davon, dass
  `proposeDiff` bereits konfliktfrei filtert (Verteidigung gegen einen
  zwischen Preview und Apply veränderten Draft). Ein leerer Diff wird
  abgelehnt (`CommandError.emptyDiff`).
- **`DesignerViewModel`**: `showBuilderPanel`/`builderKeyRoot`/
  `builderDiff` (`private(set)`). `previewBuilderDiff()` ruft ausschließlich
  die reine `proposeDiff`-Funktion auf — keine Draft-Mutation, daher hat
  `cancelBuilderDiff()` (verwirft nur `builderDiff`) garantiert keine Draft-/
  Dirty-State-Nebenwirkung. Nutzt `activeLayer` als Ziel-Layer, aber nur,
  wenn er im aktuellen Dokument tatsächlich existiert. `applyBuilderDiff()`
  läuft über `performDocumentCommand(ApplyHarmonyBuilderDiffCommand(...))` —
  derselbe Erfolgs-/Fehlerpfad wie Node-/Edge-/Layer-Authoring, synchronisiert
  Canvas/Workspace automatisch mit (`syncNodesFromDraft()`), schließt Diff
  und Panel bei Erfolg.
- **`DesignerCanvasView`**: neuer Builder-Toolbar-Button (Zauberstab-Icon)
  mit Trailing-Overlay-Panel — Tonart-Picker, „Vorschlag erzeugen", danach
  Diff-Zusammenfassung (Node-/Edge-Anzahl), Warnungen, Begründung je
  vorgeschlagenem Node/Edge, Apply-/Cancel-Buttons. Overlay-Priorität
  erweitert: Settings > Issue-Navigator > Simulation > Builder >
  Layer-Manager > Edge-Inspector > Node-Inspector.
- Strict-Concurrency-Fund während der Umsetzung behoben: die ursprünglich
  gespeicherte `static let degrees: [Degree]` wurde von Swift 6 als
  `#MutableGlobalVariable` markiert, weil `ChordType`/`HarmonicFunction`
  (`HarmonyShared`) nicht `Sendable`-annotiert sind. Gelöst durch eine
  berechnete statt gespeicherte statische Property (frisches lokales Array
  pro Zugriff, kein geteilter globaler Zustand) — keine Änderung an
  `HarmonyShared` nötig, Clean-Rebuild-Diff danach wieder 0.
- Neue Tests (19): `Tests/HarmonyAuthoringTests/
  DiatonicHarmonyBuilderTests.swift` (13 — deterministischer Diff für
  C-Dur/Ionian mit stabilen IDs, Wiederholbarkeit über zwei Aufrufe,
  Funktionsharmonik-Zuordnung, Transposition über `keyRoot`, existierende
  Node-ID wird übersprungen und gewarnt statt überschrieben, fehlender
  Ziel-Layer wird gewarnt und weggelassen, existierender Ziel-Layer wird den
  Edges zugeordnet, Apply erzeugt eine referenzsichere Map, leerer Diff wird
  abgelehnt, Apply ist genau ein Undo-Schritt, Redo stellt denselben Diff
  wieder her, ein zwischenzeitlich in Konflikt geratener Draft wird beim
  Apply abgelehnt statt überschrieben, Validator akzeptiert das Apply-
  Ergebnis fehlerfrei) sowie `Tests/DesignerKitTests/
  DesignerViewModelBuilderTests.swift` (6 — Diff-Erzeugung, aktiver Layer
  wird bei Existenz zugeordnet, Apply mutiert Draft und Canvas konsistent
  und schließt Diff/Panel, Cancel lässt Draft/Dirty-State/Revision
  unverändert, Undo/Redo über das ViewModel entfernt/stellt den gesamten
  Apply wieder her, Export-/Simulation-Gates bleiben nach einem sauberen
  Apply offen).
- Checks: `swift test` grün (302/302 — 283 bestehend + 19 neu), normaler
  Build grün (inkl. `DesignerKit`), Strict-Concurrency-Build grün
  (vollständiger Clean-Rebuild vorher/nachher: 0 Diff in Diagnosezeilen-
  Kategorien+Zählungen, keine neuen Warnkategorien — nach der oben
  beschriebenen `degrees`-Korrektur), Clean-HEAD strict build + Clean-HEAD
  `swift test` grün, `git diff --check` grün. `DesignerKit` manuell direkt
  gestartet (kein interaktiver GUI-Klicktest in dieser Umgebung möglich):
  startet fehlerfrei, keine Startup-Regression — Builder-/Apply-/Cancel-/
  Undo-Pfade vollständig über die 19 neuen Tests abgesichert.
- Keine ii-V-I-/Modal-Interchange-Automatik, keine Sekundärdominanten/
  Borrowed Chords/Pivot-Chords/Style-Builder, keine `HarmonyEngine3D`-
  Runtime-Integration oder „In 3D prüfen", keine Map-JSON-Schema-Änderung,
  keine Workspace-Daten in der Map-JSON, keine neue musikalische
  Runtime-Regel, keine Audio-/Synth-/MIDI-Änderung, kein Default-Wechsel
  HarmonyWeb vs. Explore.

**Milestone M2 (HarmonyWeb Construction Kit V1) ist mit K-08 vollständig
abgeschlossen** (K-01 bis K-08, Runden 028–035). Nächster Schritt laut
Supervisor-Handoff: ein Code-/Produktreview mit Claude Fable 5 vor dem
produktiven Start von Milestone M3.

**Nachtrag — Fable-5-Code-/Produktreview vor M3 (Runde 036):** Reine
Review-Runde, keine Codeänderung, kein Commit außer dem lokalen Rücklauf.
Claude Fable 5 hat Architektur, Produkt-/UX-Fluss und M3-Risiken von M1+M2
geprüft. Urteil: **M3-Go mit Auflagen**. Kritischster Befund: Der K-08-Builder
erzeugt für ein Dokument ohne Layer (der Standardfall bei „Neu") Kanten ohne
Layer-Zuordnung — für `HarmonyGraphEngine` untraversierbar, vom Validator und
Export-Gate nicht erkannt (Builder-A1). Weitere Befunde: stale Builder-/
Simulation-State nach Dokumentwechsel oder Draft-Mutation; Legacy-`.txt`-
Aktionen (Netzwerkladen, Layout speichern/zurücksetzen, Autopilot) im
Dokumentmodus weiterhin erreichbar; `DeleteLayerCommand` setzt
`HarmonyNode.layers` auf `[]` statt `nil` und macht Nodes damit fälschlich in
allen Layern unsichtbar. Vollständiger Befund inkl. Risiko-Review und
empfohlenem M3-Slice-Schnitt: `.agent_handoff/latest_claude.md` (Runde 036,
lokal, nicht versioniert).

**Nachtrag — V-00a: Kit-Konsistenz-Fixes vor V-01 (Codex-Handoff
HE3D-CX-2026-07-27-037, Runde 037):** Behebt die vier von Runde 036 als
Blocker benannten Kit-Konsistenzprobleme. Keine Runtime-Integration
(das ist V-01), keine Audio-/Synth-/MIDI-Änderung, keine Map-JSON-Schema-
Änderung, keine neue musikalische Runtime-Regel.

- **Default-Layer für neue Dokumente** (Stephan-Entscheidung):
  `HarmonyMapDocumentStore.newDocument()` erzeugt jetzt einen Layer
  `functional` mit `relationTypes: [.commonTone]` statt einer leeren
  Layer-Liste — `.commonTone` deckt genau die RelationType ab, die der
  K-08-Builder für seine Ring-Kanten verwendet. Reine Dokument-/UX-Basis,
  keine neue musikalische Runtime-Regel.
- **Builder-A1 behoben:** `DesignerViewModel.previewBuilderDiff()` nutzt
  `activeLayer`, wenn er im Dokument existiert, sonst den ersten
  vorhandenen Layer — nie mehr `nil`, solange das Dokument einen Layer hat.
  Hat ein Dokument (z. B. nach Löschen des letzten Layers) trotzdem keinen
  Layer, blockiert `canRunBuilder`/`builderBlockedReason` sichtbar statt
  einen toten Diff zu erzeugen; UI (Toolbar-Icon, „Vorschlag erzeugen"-
  Button) spiegelt den Blockadezustand.
- **Stale Builder-/Simulation-State invalidiert** (Finding A4/A7/A9):
  `applyDocument(_:in:)` setzt `builderDiff`, `simulation`, beide Panels,
  Node-/Edge-/Layer-Selektionen und `documentErrorMessage` beim
  Dokumentwechsel zurück — ein Diff oder eine Simulation aus dem alten
  Dokument kann sich nicht mehr auf das neue beziehen. Zusätzlich
  invalidiert `performDocumentCommand(_:)` (zentral für alle Node-/Edge-/
  Layer-/Builder-Commands) sowie `undoDocument()`/`redoDocument()` jetzt
  konservativ eine laufende Simulation und einen offenen Builder-Vorschlag
  bei JEDER Draft-Mutation — unabhängig davon, ob der Draft danach noch
  valide ist (`HarmonyGraphSimulation` hält eine eigene Map-Kopie, die
  sonst unbemerkt veraltet).
- **Legacy-/Dokumentmodus-Guards** (Finding A9): `load(networkIndex:in:)`,
  `saveLayout()`, `resetLayout()` und `toggleAutopilot()` sind im
  HarmonyWeb-/Dokumentmodus jetzt No-ops (`guard !harmonyWebMode else {
  return }`) — vorher konnten sie ein offenes Dokument in einen
  Legacy-Canvas-Mischzustand bringen (Architekturreview 2026-07-26, P1).
  `applyDocument(_:in:)` setzt zusätzlich ein stale `autopilotActive`-Flag
  aus dem Legacy-Modus zurück. UI: Play/Stop- und Layout-Speichern/
  Zurücksetzen-Buttons im Settings-Panel sind im Dokumentmodus sichtbar
  deaktiviert (`.disabled(vm.harmonyWebMode)` + erklärender Help-Text)
  statt nur still No-op zu sein.
- **`DeleteLayerCommand`-Node-Layer-Semantik korrigiert** (Finding A10):
  `HarmonyNode.layers` (optional) wird nach dem Entfernen der gelöschten
  Layer-ID auf `nil` statt `[]` gesetzt, wenn keine explizite Layerbindung
  mehr übrig bleibt — `nil` bedeutet „Mitgliedschaft aus `HarmonyEdge.layers`
  ableiten" (siehe `HarmonyMap.activeNodeIDs(in:)`), `[]` hätte den Node
  fälschlich aus JEDEM Layer verschwinden lassen, auch dort, wo er über
  seine Kanten weiterhin aktiv wäre. `HarmonyEdge.layers` ist nicht optional
  und bleibt unverändert bei `[]`.
- Neue/angepasste Tests (19 neu, 2 angepasst): `Tests/HarmonyAuthoringTests/
  DiatonicHarmonyBuilderTests.swift` (+4 — Default-Layer vorhanden, Builder-
  Diff nutzt ihn ohne Warnungen, Apply-Ergebnis ist per `HarmonyGraphEngine`
  traversierbar, dokumentiertes Rest-Verhalten ohne explizite `layerID`),
  `Tests/HarmonyAuthoringTests/LayerAuthoringCommandsTests.swift` (+2 neu,
  1 angepasst — `DeleteLayerCommand` setzt Node-Layer auf `nil`, Node mit
  mehreren Layern behält die verbleibende Bindung explizit, ein `nil`-
  Node wird über seine Kanten wieder aktiv), `Tests/DesignerKitTests/
  DesignerViewModelBuilderTests.swift` (+4 — Builder blockiert ohne Layer,
  Fallback auf ersten Layer bei stale `activeLayer`, Dokumentwechsel
  invalidiert Diff/Panel, jede Draft-Mutation invalidiert einen offenen
  Diff), `Tests/DesignerKitTests/DesignerViewModelSimulationTests.swift`
  (+4 neu, 1 angepasst — valide UND invalide Draft-Mutation invalidiert die
  Simulation, Undo/Redo invalidieren sie ebenso, Dokumentwechsel invalidiert
  Simulation/schließt Panel), neue Datei `Tests/DesignerKitTests/
  DesignerViewModelLegacyGuardTests.swift` (+5 — `load`/`resetLayout`/
  `saveLayout`/`toggleAutopilot` sind im Dokumentmodus No-ops, `applyDocument`
  setzt ein stale `autopilotActive`-Flag zurück).
- Checks: `swift test`, normaler Build (inkl. `DesignerKit`), Strict-
  Concurrency-Build, Clean-HEAD strict build + Clean-HEAD `swift test`,
  `git diff --check` — Ergebnisse siehe `.agent_handoff/latest_claude.md`
  (Runde 037).
- Keine Engine-Import-Implementierung (V-01), keine 3D-Runtime-Integration,
  keine Audio-/Synth-/MIDI-Änderungen, keine ii-V-I-/Modal-Interchange-
  Builder, keine Map-JSON-Schema-Änderung, keine neue musikalische
  Runtime-Regel, kein HarmonyWeb-Default-Wechsel.

**Nachtrag — V-00b: Engine-Symmetrie-/Determinismus-Fixes vor V-02
(Codex-Handoff HE3D-CX-2026-07-27-038, Runde 038):** Behebt drei der
verbleibenden, rein technischen Symmetrie-/Determinismus-Befunde aus dem
Fable-5-Review (Runde 036). `bassHoldMode`-Toggle-Semantik (Finding A12)
bleibt bewusst unverändert — Audio-/Spielgefühlverhalten, nicht ohne
Stephan-Entscheidung änderbar.

- **CH0-NoteOff-Symmetrie aus Snapshot (Finding A2):**
  `InteractionRuntime.updateChord(_:)` koppelt das Deaktivierungs-NoteOff
  jetzt ausschließlich an `outputNotesByKey[old]` (den Snapshot der
  tatsächlich gesendeten, oktavverschobenen Noten) statt an
  `byKey[old]?.chord.midiNotes`. Vorher fiel das gesamte NoteOff aus, wenn
  der Knoten im selben Frame nicht mehr Teil der aktuellen Kandidatenliste
  war — der Snapshot lag trotzdem vor. Der frühere Fallback auf
  unverschobene `chord.midiNotes` ist entfernt: er hätte theoretisch ein
  Off auf nie gesendete Noten erzeugen können. Dieselbe Härtung in
  `HarmonyScene.reloadAllChunks()` und `unloadChunk(_:)` — beide nutzen
  jetzt ausschließlich den Snapshot, kein `?? data.midiNotes`-Fallback mehr.
- **Seeded Determinismus statt unseeded Zufall (Finding A3):**
  `MelodyEngine` hält jetzt eine eigene `SeededRNG`-Instanz
  (`init(seed:)`, Default-Seed fix) und ersetzt `close.randomElement()` in
  `tick()` durch `close[rng.i(close.count)]` — dieselbe musikalische Regel
  (Kandidaten innerhalb der erlaubten Schrittweite), nur deterministisch
  ausgewählt. `AutopilotEngine` ersetzt `Float.random(in: 0..<total)` in
  der gewichteten Kantenauswahl durch `rng.f() * total` (`SeededRNG`,
  ebenfalls mit `init(seed:)`). Beide Default-Initialisierer
  (`MelodyEngine()`/`AutopilotEngine()`, unverändert von allen
  Bestandsaufrufern genutzt) bleiben parameterlos aufrufbar, sind aber
  jetzt deterministisch statt System-RNG-gestützt.
- **Stabile Candidate-/Tie-Break-Ordnung (Finding A8):** Die drei
  Kandidatenlisten in `HarmonyScene` (`updateChordProximity`,
  `updatePortalProximity`, `updateCloudProximity`) werden nach dem Bau aus
  den jeweiligen Dictionaries (`chordNodes`/`bassPortalPositions`/
  `cloudNodes`) zusätzlich nach `key` sortiert — `ProximityTracker.evaluate`
  löst Distanzgleichstände über den ersten Treffer in Array-Reihenfolge
  auf; ohne Vorsortierung war das Ergebnis bei exaktem Gleichstand
  prozesszufällig statt reproduzierbar. `buildChordPositionMap()` (Basis
  für `AutopilotEngine`) delegiert an eine neu extrahierte, SceneKit-freie
  reine Funktion `resolveChordPositionMap(entries:)` (neuer Typ
  `ChordPositionEntry`, beide file-scope in `HarmonyScene.swift`): sortiert
  zuerst nach `key`, dann Last-Writer-Wins — deterministisch, direkt ohne
  `HarmonyScene`-Instanz testbar.
- Neue Tests (16): `Tests/HarmonyEngine3DTests/InteractionRuntimeTests.swift`
  (+3 — Kandidat verschwindet aus der Liste, Snapshot feuert trotzdem genau
  ein NoteOff mit den ursprünglichen Noten; kein Doppel-Off bei
  wiederholtem leerem Frame; Octave-Shift-Wechsel kombiniert mit
  Kandidatenverlust bleibt symmetrisch), neue Datei `Tests/
  HarmonyEngine3DTests/MelodyEngineTests.swift` (4 — gleicher Seed liefert
  identische Notensequenz, unterschiedlicher Seed liefert über genug Ticks
  eine andere, Default-Init bleibt zwischen Instanzen deterministisch,
  gewählte Note verletzt nie die bestehende Schrittweiten-Regel), neue
  Datei `Tests/HarmonySharedTests/AutopilotEngineTests.swift` (5 — gleicher
  Seed liefert identische Zielsequenz, unterschiedlicher Seed liefert eine
  andere, Default-Init bleibt deterministisch, leere Positionen liefern
  `false`, jedes Ziel bleibt ein gültiger Kandidatenname), neue Datei
  `Tests/HarmonyEngine3DTests/ChordPositionResolutionTests.swift` (4 —
  mehrere gleichnamige Instanzen lösen deterministisch nach höchstem `key`
  auf, Ergebnis ist unabhängig von der Eingabe-Array-Reihenfolge,
  unsichtbare Einträge werden ausgeschlossen, unterschiedliche Namen
  bleiben beide erhalten).
- Checks: `swift test` 337/337 grün (321 bestehend + 16 neu), normaler
  Build grün, Strict-Concurrency-Build grün (identisches Warnungsprofil zu
  Runde 037 — 480 Warnungen, dieselben 11 Bestandsdateien, keine neuen
  Kategorien/Dateien), Clean-HEAD strict build + Clean-HEAD `swift test`
  grün, `git diff --check` grün. Details:
  `.agent_handoff/latest_claude.md` (Runde 038).
- Keine `bassHoldMode`-Semantik-Änderung, keine HarmonyWeb-/Explore-
  Default-Änderung, keine Engine-Import-/V-01-Implementierung, keine
  3D-Art-Direction-/Layout-Entscheidung, keine Audio-Synth-/Reverb-/MIDI-
  Feature-Änderung, keine Map-JSON-Schema-Änderung.

**Nachtrag — V-00b.1: CH0-Output-Snapshot vollständig gemacht
(Codex-Handoff HE3D-CX-2026-07-27-039, Runde 039):** Kleiner
Supervisor-Nachlauf zu V-00b. Restbefund aus der Runde-038-Abnahme: das
Deactivation-Event nach Kandidatenverlust trug die richtigen Noten, aber
`name: ""` statt des ursprünglich aktivierten Chord-Namens —
`OutputCoordinator` leert `flightController.soundingChordName` nur bei
`soundingChordName == chord.name`, ein leerer Name ließ den HUD-Namen also
stehen, obwohl `ch0Active = false` und MIDI bereits korrekt beendet war.

- **`InteractionRuntime.swift`:** neue private `ChordOutputSnapshot`-Struct
  (`name` + `midiNotes`, file-scope). Das bisherige
  `outputNotesByKey: [String: [Int]]` ist zu
  `outputSnapshotByKey: [String: ChordOutputSnapshot]` geworden — Name und
  Noten stammen dadurch strukturell aus demselben Aktivierungszeitpunkt,
  keine zwei getrennten Dictionaries, die auseinanderlaufen könnten. Die
  öffentliche API (`outputNotes(forKey:)`, `removeOutputNotes(forKey:)`)
  ist nach außen unverändert (weiterhin `[Int]?`) — beide lesen jetzt
  `.midiNotes` aus dem gebündelten Snapshot. `updateChord(_:)`s
  Deactivation-Zweig baut `ChordData` jetzt aus `snapshot.name` +
  `snapshot.midiNotes` statt aus `byKey[old]?.chord.name ?? ""` +
  `outputNotesByKey[old]`.
- `HarmonyScene.reloadAllChunks()`/`unloadChunk(_:)` bleiben unverändert —
  beide beziehen den Namen bereits aus `chordDataMap`/`unloadedChordData`,
  das zum Aufrufzeitpunkt noch denselben Knoten kennt (kein
  Kandidatenverlust-Szenario wie in `updateChord(_:)`), daher kein
  Anpassungsbedarf laut Handoff-Scope.
- Neue/angepasste Tests (3 neu, 2 angepasst) in
  `Tests/HarmonyEngine3DTests/InteractionRuntimeTests.swift`:
  `test_candidateVanishesFromList_stillFiresNoteOffFromSnapshot` und
  `test_configChangeAndCandidateVanish_combined_stillUsesOriginalSnapshot`
  (aus Runde 038) prüfen jetzt zusätzlich `deactivated.name`; neu:
  `test_candidateVanishesFromList_deactivatedChordNameMatchesOriginalActivation`,
  `test_configChangeAndCandidateVanish_nameSurvivesToo`,
  `test_outputSnapshot_isCorrectlyCleanedUp_afterDeactivationAndAfterRemoval`.
- Checks: `swift test` 340/340 grün (337 bestehend + 3 neu), normaler Build
  grün, Strict-Concurrency-Build grün (identisches Warnungsprofil zu Runde
  038 — 480 Warnungen, dieselben 11 Bestandsdateien, `InteractionRuntime.swift`
  weiterhin ohne Warnung), Clean-HEAD strict build + Clean-HEAD `swift test`
  grün, `git diff --check` grün. Details:
  `.agent_handoff/latest_claude.md` (Runde 039).
- `bassHoldMode`-Toggle-Semantik (Finding A12) weiterhin unverändert — per
  Diff verifiziert, keine Zeile in `updatePortal(_:)` berührt. Kein
  Engine-Import/V-01, keine Audio-Synth-/Reverb-/MIDI-Feature-Änderung,
  keine neuen seeded/random/Tie-Break-Umbauten, keine UI-Neugestaltung.

**Nachtrag — V-01: erster Kit-zu-Engine-Vertikalslice (Codex-Handoff
HE3D-CX-2026-07-27-040, Runde 040):** Eine vom Construction Kit erzeugte/
kanonisch exportierte HarmonyMap-Datei ist jetzt über einen einfachen
Application-Support-Importordner in der 3D-App als HarmonyWeb ladbar.
Stephan-Entscheidung für diesen Slice: kein NSOpenPanel, keine
Security-Scoped Bookmarks, kein URL-Scheme — ein Importordner reicht für
V1. Explore bleibt App-Default, Bundle-Maps bleiben unverändert wählbar,
`--map-preview`/`HE3D_MAP_PREVIEW` bleibt vorrangig und lädt weiterhin nur
aus dem Bundle.

- **`RuntimeMapImportStore`** (neu, `Sources/HarmonyEngine3D/
  RuntimeMapImportStore.swift`, nur `Foundation`+`HarmonyShared`): reine
  Datei-/Codec-Schicht ohne SceneKit/AppSettings/UI.
  `importDirectory()` liefert `~/Library/Application Support/
  HarmonyEngine3D/HarmonyWeb/Maps`; `ensureImportDirectoryExists()` legt
  ihn bei Bedarf an, ohne vorhandene Dateien zu löschen;
  `listImportedMaps()` listet `.json`-Dateien stabil nach Dateiname
  sortiert und deckt jede Datei mit `ImportedHarmonyMapEntry` (Dateiname,
  Anzeigename, optionale `loadError`-Diagnose) ab — ungültige/nicht
  dekodierbare Dateien bleiben sichtbar gelistet, aber nicht wählbar,
  statt die App-Auswahl crashen zu lassen; `load(fileName:)` dekodiert +
  validiert über `HarmonyMapCodec`/`HarmonyMapValidator` (derselbe Vertrag
  wie `HarmonyMapLoader.load(named:)` für Bundle-Maps: Errors → `nil` +
  Diagnose, Warnings blockieren nicht). Alle Funktionen akzeptieren ein
  optionales `directory:` zum Überschreiben des Application-Support-Pfads
  — ausschließlich für Tests.
- **`RuntimeWorldSelection`**: neues Feld `externalMapFileName: String?`
  (stabiler Dateiname, kein absoluter Pfad — Persistenz bleibt stabil,
  auch wenn sich Application-Support-Wurzel/Homeverzeichnis ändern).
  Gesetzt hat Vorrang vor `harmonyWebMap` (Bundle-Katalog).
- **`AppModel.effectiveHarmonyWebRequest(envOverride:selection:)`**:
  Rückgabetupel um `isExternal: Bool` erweitert (rein additiv — bestehende
  Feldnamen/-semantik unverändert, alle bisherigen Tests blieben ohne
  Anpassung grün). `--map-preview`/`HE3D_MAP_PREVIEW` liefert immer
  `isExternal: false` (lädt weiterhin nur aus dem Bundle); innerhalb von
  `.harmonyWeb` hat `externalMapFileName` (falls gesetzt) Vorrang vor
  `harmonyWebMap`. `AppModel.init()` wählt darüber die Ladequelle
  (`RuntimeMapImportStore.load(fileName:)` statt
  `HarmonyMapLoader.load(named:)`) — der restliche Pfad (`WorldSession`,
  `HarmonyScene`, Observational-Logging) ist identisch und bleibt
  `toChordNetwork`-frei.
- **`ContentView`/`AppSettings`**: WELT-Abschnitt zeigt bei `.harmonyWeb`
  zusätzlich eine „Importierte Maps"-Liste (Bundle- und externe Auswahl
  sind gegenseitig exklusiv markiert; nicht ladbare externe Dateien sind
  sichtbar, aber deaktiviert, mit kurzer Fehlerzeile) sowie den
  Importordner-Pfad als knappe Statusinfo. `AppSettings` persistiert
  `externalMapFileName` über einen neuen UserDefaults-Key (leerer String
  == kein Override, da `Optional<String>` kein natives UserDefaults-
  Pendant hat). Neue Lokalisierungs-Keys (`settings.world.imported.header`,
  `settings.world.import.folder.label`) in `de.lproj`/`en.lproj`.
- **`Package.swift`**: `HarmonyEngine3DTests` hängt jetzt zusätzlich von
  `HarmonyAuthoring` ab (nur der Test-Target) — ausschließlich, um eine
  Kit-nahe Testkarte über `HarmonyMapDocumentStore`/`DiatonicHarmonyBuilder`
  zu erzeugen. Der Runtime-Produktcode (`HarmonyEngine3D`-Target) bleibt
  Authoring-/DesignerKit-frei (per Grep verifiziert: kein
  `import DesignerKit`/`import HarmonyAuthoring` in `Sources/
  HarmonyEngine3D`).
- Vertikaler Nachweis (neue Datei `Tests/HarmonyEngine3DTests/
  KitToRuntimeImportTests.swift`, 3 Tests): eine über
  `HarmonyMapDocumentStore.newDocument()` + `DiatonicHarmonyBuilder` erzeugte
  Kit-Map wird per `HarmonyMapCodec.encode` in einen temporären
  Importordner geschrieben, von `RuntimeMapImportStore` gelistet/geladen
  und über `WorldSession` konstruiert — Nodes/Edges bleiben vollständig
  erhalten; ein zweiter Test mit einem handgebauten kanonischen Fixture
  beweist zusätzlich Feldtreue für `layout3D`, `tags`, mehrere
  `relationTypes`, `weight` und `magnetProfile`; ein dritter Test belegt
  positiv (nicht nur per Grep), dass eine Map mit mehreren RelationTypes,
  ungerichteter Kante und MagnetProfile — Felder, die `toChordNetwork`
  laut eigener Doku verlustbehaftet exportieren würde — unverändert durch
  `RuntimeMapImportStore`/`WorldSession` läuft.
- Neue Datei `Tests/HarmonyEngine3DTests/RuntimeMapImportStoreTests.swift`
  (13 Tests): Importordner-Ableitung, Anlegen ohne Löschen bestehender
  Dateien, Listing (leer/fehlender Ordner/Nicht-JSON ignoriert/stabile
  Sortierung/valide Datei), kein Crash bei nicht dekodierbaren Dateien
  oder Validator-Errors (sowohl beim Listing als auch beim Laden), `load`
  bei fehlender Datei liefert `nil` ohne Crash.
- `Tests/HarmonyEngine3DTests/RuntimeWorldSelectionTests.swift` (+2 neu,
  3 angepasst): externe Map hat Vorrang vor `harmonyWebMap`; Developer-
  Override hat weiterhin Vorrang auch gegenüber einer persistierten
  externen Auswahl; bestehende Tests prüfen zusätzlich `isExternal`/
  `externalMapFileName`, unverändert grün.
- Checks: `swift test` 358/358 grün (340 bestehend + 18 neu), normaler
  Build grün, Strict-Concurrency-Build grün (identisches Warnungsprofil zu
  Runde 039 — 480 Warnungen, dieselben 11 Bestandsdateien; keine der
  neuen/geänderten Dateien in der Warnungsliste), Clean-HEAD strict build +
  Clean-HEAD `swift test` grün, `git diff --check` grün. `HarmonyEngine3D`
  manuell direkt gestartet (Explore-Default und `--map-preview`-Override):
  beide starten fehlerfrei, keine Startup-Regression — stdout-Diagnose war
  über den gewählten Hintergrund-Start-/Kill-Mechanismus in dieser
  Umgebung nicht einsehbar (bekannte Einschränkung, kein GUI-Klicktest
  möglich), die eigentliche Auswahl-/Ladelogik ist stattdessen über die
  deterministischen Unit-/Integrationstests oben vollständig abgesichert.
  Details: `.agent_handoff/latest_claude.md` (Runde 040).
- Kein `bassHoldMode`-Toggle-Fix, kein HarmonyWeb-Default-Wechsel, kein
  Synth-/Reverb-/Delay-/MIDI-Feature, keine Map-JSON-Schema-Änderung, kein
  portables Workspace-Metadatum im Map-JSON, kein URL-Scheme, keine
  Security-Scoped Bookmarks, kein NSOpenPanel als Runtime-Ladeweg.

**Nachtrag — V-01.1: Runtime-Importordner im Produktpfad wirklich anlegen
(Codex-Handoff HE3D-CX-2026-07-28-041, Runde 041):** Supervisor-Review von
V-01 stellte fest, dass `RuntimeMapImportStore.ensureImportDirectoryExists()`
zwar existierte und getestet war, im produktiven App-/UI-Pfad
(`ContentView`s WELT-Abschnitt ruft `listImportedMaps()` ohne `directory:`-
Argument auf) aber nie aufgerufen wurde — ein fehlender Importordner blieb
dadurch unsichtbar fehlend, statt automatisch angelegt zu werden, wie der
V-01-Handoff es vorsah.

- **`RuntimeMapImportStore.listImportedMaps(in:fileManager:)`**: der
  Default-Produktpfad (`directory` nicht übergeben, also `nil`) ruft jetzt
  selbst `ensureImportDirectoryExists(fileManager:)` auf, bevor er den
  Ordnerinhalt liest — der reale Application-Support-Importordner wird beim
  nächsten Aufruf des WELT-Abschnitts (oder jedem anderen Produktionsaufruf)
  automatisch angelegt, falls er fehlt. Ein von Tests explizit injiziertes
  `directory:` (auch wenn es auf einen fehlenden Pfad zeigt) wird dagegen
  NIE automatisch angelegt — nur so bleibt der bestehende No-Crash-Test für
  ein fehlendes, explizit übergebenes Testverzeichnis
  (`test_listImportedMaps_missingDirectory_returnsEmptyArray_noCrash`)
  weiterhin isoliert und aussagekräftig. `ContentView.swift` musste dafür
  nicht geändert werden, da der einzige Produktionsaufruf bereits ohne
  `directory:`-Argument erfolgt.
- Bestehende Dateien im Importordner werden dabei nie verändert oder
  gelöscht — `ensureImportDirectoryExists` legt ausschließlich fehlende
  Verzeichniskomponenten an (`createDirectory(withIntermediateDirectories:
  true)`), rührt existierende Inhalte nicht an.
- Neue Datei-Test-Helferklasse `RedirectingFileManager` (nur in
  `RuntimeMapImportStoreTests.swift`, `private final class`, überschreibt
  `urls(for:in:)` für `.applicationSupportDirectory`) erlaubt es, den
  Default-Produktpfad (`directory: nil`) gegen ein temporäres statt das
  echte Application-Support-Verzeichnis zu testen, ohne den Testrechner zu
  berühren.
- Drei neue Tests in `RuntimeMapImportStoreTests.swift`: (1)
  `test_listImportedMaps_defaultProductPath_autoCreatesMissingImportDirectory`
  beweist, dass der Default-Produktpfad einen fehlenden Ordner anlegt; (2)
  `test_listImportedMaps_explicitMissingDirectory_isNotAutoCreated` beweist
  begleitend, dass ein explizit injiziertes fehlendes Testverzeichnis NICHT
  automatisch angelegt wird (Regressionsschutz für die bestehende
  No-Crash-Testsemantik); (3)
  `test_listImportedMaps_defaultProductPath_doesNotDeleteExistingFiles`
  beweist, dass eine bereits vorhandene Datei im automatisch angelegten
  Ordner beim Listing erhalten bleibt.
- V-01-Funktionalität bleibt vollständig unverändert: externe Maps über
  `RuntimeMapImportStore`, Bundle-Maps, Explore-Default,
  `--map-preview`/`HE3D_MAP_PREVIEW`-Vorrang, `WorldSession`-Integration —
  alles unangetastet, nur das Anlegen des Ordners im Default-Produktpfad
  wurde nachgezogen.
- Checks: `swift test` 361/361 grün (358 bestehend + 3 neu), normaler Build
  grün, Strict-Concurrency-Build grün (Warnungsprofil identisch zu Runde
  040 — 480 Warnungen, dieselben 11 Bestandsdateien; keine der
  geänderten/neuen Dateien in der Warnungsliste), Clean-HEAD strict build +
  Clean-HEAD `swift test` grün, `git diff --check` grün. Details:
  `.agent_handoff/latest_claude.md` (Runde 041).
- Kein neuer Runtime-Ladeweg, kein NSOpenPanel, kein URL-Scheme, keine
  Security-Scoped Bookmarks, kein HarmonyWeb-Default-Wechsel, keine
  Audio-/Synth-/MIDI-/Spielgefühl-/`bassHoldMode`-Änderung, keine
  Map-JSON-Schema-Änderung, keine V-02-Smoke-Matrix vorgezogen.

**Nachtrag — V-02: Live-Instrument-Smoke-Matrix (Codex-Handoff
HE3D-CX-2026-07-28-042, Runde 042):** Reiner Verifikationsslice, keine
Produktcode-Änderung. Neues, versioniertes `SMOKE_TEST_V1.md` protokolliert
Umgebung, Kommandos, Testmatrix und Findings.

- **Boot-Matrix bestanden:** Explore-Default, HarmonyWeb Bundle-Map
  (`HE3D_MAP_PREVIEW`/`HE3D_MAP_NAME`) und HarmonyWeb externe importierte
  Map (`RuntimeMapImportStore`, Runde 040/041-Importordner) starten
  reproduzierbar sowohl über internen Synth (`AudioEngine`) als auch über
  MIDI (`CoreMIDI` Virtual Source), jeweils ohne Crash, mit korrekten
  `[HarmonyTest]`/`WorldSession`-Diagnosen. Externer Map-Test nutzte eine
  temporäre, hinterher wieder entfernte Kopie von `reference-core.json` im
  echten Application-Support-Importordner sowie die Cocoa-„Argument-
  Domain" (`-he3d.world.mode`/`-he3d.world.externalMapFileName` als
  Prozessargumente) — kein neuer Produktpfad, nur Standard-`NSUserDefaults`-
  Verhalten zur Testvorbereitung. Alle dadurch berührten realen
  `UserDefaults`/Application-Support-Zustände wurden nach dem Test wieder
  auf den Ausgangszustand zurückgesetzt.
- **Wichtiger Befund:** In der nicht-interaktiven CLI-Agent-Umgebung dieser
  Runde läuft SceneKits Renderer-Update-Callback nach der Erstinitialisierung
  nicht weiter (kein kompositiertes Fenster, `launchctl` klassifiziert die
  Session als `Background`) — dadurch endet jede beobachtete Log-Aktivität
  nach einer kurzen, deterministischen Bootstrap-Sequenz (1–2s), unabhängig
  von der gewählten Wartezeit (empirisch mit einem ~65s-Lauf belegt). Das ist
  eine präzisere Fassung der bereits seit Runde 040 dokumentierten
  Einschränkung „kein interaktiver GUI-Klicktest möglich", keine neue
  Regression. Eine echte, durchgehend aktive 30-Minuten-Session ist in
  dieser Umgebung deshalb nicht sinnvoll ausführbar.
- **DualSense/Gamepad:** auf diesem Rechner per Bluetooth gepaart, aber zum
  Testzeitpunkt nicht verbunden — als `skipped: hardware unavailable`
  dokumentiert, nicht simuliert. Panic/All-Notes-Off (Gamepad-Dreieck)
  ebenso `skipped` (nur über Gamepad/UI erreichbar). Die App behandelt die
  Gamepad-Abwesenheit selbst bereits sauber (`🎮 Kein Gamepad gefunden`),
  kein Crash.
- **Keine Code-Änderung nötig:** kein reproduzierbarer Startcrash, keine
  hängende Note im Sinne eines Produktdefekts, keine State-Divergenz
  gefunden — der letzte beobachtete `noteOn` ohne Folge-`noteOff` in der
  ~65s-Session erklärt sich durch den stillstehenden Renderloop, nicht durch
  fehlerhaftes On/Off-Tracking (`he3d.bassHold` war korrekt `false`).
- **Ergebnis:** V-02 wird als **teilweise erledigt** markiert (siehe
  `ROADMAP.md`) — die Boot-/Start-Matrix ist reproduzierbar grün, die
  Sustained-/Live-Interaktions-Achse (Tastatur-/Maus-Trigger über die Zeit,
  DualSense, durchgehende 30-Minuten-Session) ist in dieser Headless-Umgebung
  nicht abschließend prüfbar. `SMOKE_TEST_V1.md` empfiehlt, diese Achse
  entweder durch eine echte manuelle Session von Stephan oder durch eine
  explizite Supervisor-Entscheidung (Boot-Smoke + bestehende deterministische
  Testsuite als Ersatzverifikation) zu schließen.
- Checks: `swift test` 361/361 grün (unverändert gegenüber Runde 041, keine
  neuen Tests in diesem Verifikationsslice), normaler Build grün,
  Strict-Concurrency-Build grün (Warnungsprofil identisch zu Runde 041 —
  480 Warnungen, dieselben 11 Bestandsdateien), Clean-HEAD-Build +
  Clean-HEAD `swift test` grün (361/361), `git diff --check` grün. Details:
  `.agent_handoff/latest_claude.md` (Runde 042).
- Kein Synth-/Reverb-/Delay-Sounddesign, kein `bassHoldMode`-Eingriff, kein
  HarmonyWeb-Default-Wechsel, keine Magnet-Arbitration/Spielgefühl-Änderung,
  keine Map-JSON-Schema-Änderung, kein NSOpenPanel/URL-Scheme/Security-Scoped
  Bookmarks, kein Push/Release/Tag/Deployment, kein V-03-Dokumentations-
  vollausbau.

**Nachtrag — V-03: Dokumentation und Release-/Smoke-Checkliste (Codex-Handoff
HE3D-CX-2026-07-29-043, Runde 043):** Reiner Dokumentationsslice, **keine
Produktcode-Änderung**.

- **Neues `README.md`:** aktueller Einstiegspunkt — Voraussetzungen,
  SPM-Targets-Tabelle, `swift build`/`swift test`/Strict-Concurrency-
  Kommandos, `swift run HarmonyEngine3D`/`swift run DesignerKit`,
  Explore-Start (Default), HarmonyWeb-Bundle-Start (Settings-UI +
  `--map-preview`/`HE3D_MAP_PREVIEW`/`HE3D_MAP_NAME`-Override), externer
  HarmonyWeb-Importordner
  (`~/Library/Application Support/HarmonyEngine3D/HarmonyWeb/Maps`).
- **`ARCHITECTURE.md`** gezielt synchronisiert (nicht neu geschrieben):
  neuer Abschnitt „V1-Integrationsstand" direkt nach „Projektziel" deckt
  die aktuellen SPM-Targets (inkl. `HarmonyAuthoring` + alle vier
  Test-Targets), `WorldSession` als kanonischen HarmonyWeb-Produktpfad für
  Bundle- und externe Maps, `RuntimeMapImportStore`, `InteractionRuntime`
  (CH0-Snapshot-Symmetrie, `SeededRNG`-Determinismus), die Audio-/MIDI-
  Grenze (`AudioOutput`-Protokoll, `MIDIManager`/`AudioEngine`,
  `MIDIManager.shared`-Zugriffsregel, bekanntes 480-Warnungen-Strict-
  Concurrency-Profil über dieselben 11 Bestandsdateien) und den
  V-02-Status ab. Der Review-Hinweis am Dokumentenkopf markiert ältere,
  widersprechende Abschnitte weiter unten (vor `WorldSession`/
  `InteractionRuntime`/Construction Kit) explizit als historisch, statt sie
  vollständig neu zu schreiben.
- **Neue `RELEASE_CHECKLIST_V1.md`:** feste Checkliste mit sieben
  automatischen Checks (Tests, Build, Strict-Build, Clean-Checkout-Build/
  -Tests, `git diff --check`, sauberer Worktree) und zehn manuellen Checks
  M1–M10 (App-Start je Weltquelle, Tastatur/Maus, DualSense, Panic/All-
  Notes-Off, interner Synth, MIDI, kurze reale Session, **M10 = die volle
  30-Minuten-Session als explizites Release-Gate**), einer Blocker-
  Definition (Crash, hängende Note, State-Divergenz, falsche Map/Layer,
  ungefragter Systemzugriff) und einer `skipped`-Dokumentationskonvention.
  Ergänzt (nicht ersetzt) `SMOKE_TEST_V1.md`, das als Durchlauf-Log
  bestehen bleibt und nun auf die Checkliste verweist.
- **`SETUP.md`** erhielt einen „historisch/veraltet"-Hinweis auf
  `README.md` (beschreibt einen frühen `network.txt`-only-Xcode-Workflow
  ohne HarmonyWeb/DesignerKit/SwiftPM-CLI).
- **Wichtig — keine Übertreibung:** An keiner Stelle behauptet die
  aktualisierte Dokumentation, die 30-Minuten-Live-Interaktionssession aus
  V-02 sei bestanden. `README.md`, `ARCHITECTURE.md` und
  `RELEASE_CHECKLIST_V1.md` markieren dieses Gate übereinstimmend als
  offen und benennen den Weg zur Schließung (echte Session oder explizite
  Stephan-/Supervisor-Akzeptanzentscheidung).
- V-03 wird als **Doku-Slice erledigt** markiert (`ROADMAP.md`) — nicht als
  „V1 releasefähig", da das V-02-Live-Gate weiterhin offensteht.
- Checks: nur Markdown-Dateien geändert, kein Package-/Quellcode betroffen
  — daher wie im Handoff vorgesehen `git diff --check HEAD~1 HEAD` grün
  plus gezielte Konsistenz-Greps (SPM-Targetnamen gegen `Package.swift`,
  keine `import DesignerKit`/`import HarmonyAuthoring` in
  `Sources/HarmonyEngine3D/`, kein `bassHoldMode`-Eingriff), `swift test`
  zusätzlich zur Sicherheit erneut ausgeführt (361/361 grün, unverändert).
- Kein Produktcode, kein Synth-/Reverb-/Delay-Sounddesign, kein
  `bassHoldMode`-Fix, kein HarmonyWeb-Default-Wechsel, kein Art-Direction-/
  UX-Redesign, kein Push/Release/Tag/Deployment, keine Aussage, V-02 sei
  vollständig bestanden.

---

## [3.9.8] – 2026-04-11

### Dokumentation: ROADMAP.md Rev. 5 — Review-basierte Überarbeitung

Vollständige Überarbeitung der Roadmap auf Basis des Code-Reviews (REVIEW.md v3.9.7).

**Neu hinzugefügt:**
- Phase 0.9: K3-Fix (Opacity-Check ProximityTracker) — Korrektheitsfehler, fehlte bislang
- Phase 0.10: minimal.sf2 entfernen (trivial, ungenutzt seit Phase 3E)
- Phase 0.11: SETUP.md aktualisieren (trivial, Dokumentationspflege)
- Phase 1d: HarmonyScene intern aufteilen → ChunkManager + TriggerCoordinator + HarmonyScene (Renderer)
- Phase 1e: ContentView aufteilen → SettingsPanel + CockpitHUD + OverlayController + ContentView (Root)
- Phase 1.5: Stabilisierung nach HarmonyCore-Extraktion
  - 1.5a: Unit Tests für HarmonyCore (erstmals in Roadmap)
  - 1.5b: FlightController von SCNNode entkoppeln (aus Phase 5.4 vorgezogen)

**Verschoben:**
- FlightController SCNNode-Entkopplung: Phase 5.4 → Phase 1.5b

**Geschärft:**
- Phase 4.4: Struktureller Split von ContentView herausgelöst (→ 1e); 4.4 = Funktions-Audit
- Phase 5.3: Scope reduziert; Kernarbeit in Phase 1/1d erledigt
- Phase 5.4: SCNNode-Arbeit in 1.5b; verbleibend: GamepadController-Init + TouchInputProvider

---

## [3.9.7] – 2026-04-06

### Feature: DesignerKit — HarmonyWeb-Viewer

DesignerKit kann jetzt HarmonyMap-JSONs laden und visualisieren.
Kein Edit-Zugriff auf das Web — reiner Betrachtungsmodus.

**DesignerViewModel.swift**
- `harmonyMap: HarmonyMap?` — geladene HarmonyMap; `nil` im normalen Netzwerk-Modus.
- `activeLayer: String` — steuert Layer-Opacity in der Kantenzeichnung.
- `selectedWebName: String` — aktuell gewählter HarmonyWeb-Name (Picker-Binding).
- `harmonyWebMode: Bool` — computed, true wenn harmonyMap != nil.
- `webEdgesForDisplay: [HarmonyEdge]` — sichtbarkeitsgefilterte Kanten für drawWebEdges().
- `availableLayers: [String]` — Layer-IDs der geladenen HarmonyMap für den Layer-Picker.
- `webValidationWarnings: [String]` — computed: prüft Namenskonvention, doppelte IDs, kaputte Referenzen.
- `loadHarmonyWeb(named:in:)` — lädt HarmonyMap via HarmonyMapLoader, baut LayoutNodes,
  startet Force-Layout async; editMode = false erzwungen.
- `exitHarmonyWebMode(in:)` — wechselt zurück in den normalen .txt-Netzwerk-Modus.
- `availableWebNames: [String]` (static) — bekannte HarmonyWebs im Bundle.

**DesignerCanvasView.swift**
- `drawWebEdges(ctx:)` — neue Zeichenroutine für HarmonyWeb-Modus:
  - RelationType → Farbe (vToI=Gold, iiToV=Orange, relMajMin=Teal, parallelMajMin=Grünblau,
    commonTone=Blaugrau, tritSubst=Violett)
  - `directed=true` → Pfeilspitze an Knotenkontur (`drawArrowhead`)
  - `directed=false` → einfache Linie
  - Layer-Zugehörigkeit → volle Opacity (aktiver Layer) vs. 0.18 (anderer Layer)
  - Gewichts-Label an Kantenmitte für Kanten des ausgewählten Knotens
- `drawArrowhead(ctx:from:to:nodeRadius:color:)` — gefüllte Dreieck-Pfeilspitze
- `webEdgeColor(_ types:)` — RelationType-zu-Farbe Mapping
- Toolbar: "🌐 Web"-Button aktiviert HarmonyWeb-Modus; Web-Modus zeigt Web-Picker,
  Layer-Segmented-Control und Exit-Button
- `webValidationBar` — gelbe Warnleiste unterhalb der Toolbar (nur wenn Warnungen vorhanden)
- Canvas-Branch: `harmonyWebMode` → `drawWebEdges`, sonst bestehende `drawEdges` + Ringe

Bestehendes .txt-Netzwerk-System vollständig unberührt.

---

## [3.9.6] – 2026-04-05

### Feature: Erstes vollständiges HarmonyWeb + Akkord-Namenskonvention

**Akkord-Namenskonvention (ARCHITECTURE.md)**
Neue Sektion „Akkord-Namenskonvention" — verbindliche Schreibregeln für `HarmonyNode.id`,
`LocalNode.chordName`, RuntimeHarmonik-Vergleiche und Debug-Anzeige. Klärt: Grundton-
Großschreibung, Vorzeichen (`b`/`#`), Akkordtyp-Suffixe (`maj7`, `7`, `m7`, `m7b5`,
`dim7`, `dim`, `m`), keine Leerzeichen, keine alternativen Symbole.

**harmony-web-c-diatonic.json (neu, HarmonyShared/Resources/maps/)**
Erstes vollständig überführtes HarmonyWeb. Basis: `network_diatonisch.txt`.

- 14 Nodes: 7 diatonische Stufenakkorde (Cmaj7 … Bm7b5) + 4 Sekundärdominanten
  (D7, A7, E7, C7) + Sekundärtonika (Gmaj7) + 2 Modal-Interchange-Akkorde (Bbmaj7, Ebmaj7)
- 29 Edges in 2 Layern:
  - `functional`: V-I (5), ii-V (2), commonTone-Funktionsbewegungen (14), relMajMin (3)
  - `modal`: relMajMin (3, geteilt mit functional), parallelMajMin/Modal Interchange (5)
- Gegenüber dem .txt-Netzwerk neu ergänzt (HarmonyLogic):
  - RelationType-Klassifikation pro Kante (V-I, ii-V, relMajMin, parallelMajMin, commonTone)
  - Layer-Zuordnung (functional vs. modal)
  - Directed/undirected-Unterscheidung (relMajMin = undirected, V-I/ii-V = directed)
  - MagnetProfile pro Kante (strong/medium/weak)

**HarmonyEngine3DApp.swift**
- `mapName` von `"harmony-web-c-center"` auf `"harmony-web-c-diatonic"` umgestellt.
- Ältere Testwelten (harmony-web-c-center, reference-core) bleiben unberührt im Bundle.
- Fallback (ChordGenerator) bleibt intakt.

---

## [3.9.5] – 2026-04-05

### Refactor: Magnetismus-Datenfluss — Single Source of Truth

**Problemstellung:** `magnetTargetPosition` war eine eigenständig gespeicherte Property
(`simd_float3?`), die in `applyHarmonicDecision()` beschrieben wurde. Damit gab es zwei
unabhängige Zustände für denselben Sachverhalt: `selectedNodeID` im `HarmonicDecision`-Objekt
und `magnetTargetPosition` in `HarmonyScene`. Bei Chunk-Unload oder Node-Verschiebung konnte
die gespeicherte Position veralten.

**Lösung: Computed Property statt gespeicherter Wert**

`HarmonyScene.swift`
- `private(set) var magnetTargetPosition: simd_float3? = nil` entfernt.
- `private var currentMagnetNodeID: String? = nil` hinzugefügt (einzige gespeicherte Größe).
- `var magnetTargetPosition: simd_float3?` als computed property:
  `chordNodes[currentMagnetNodeID]?.simdWorldPosition` — automatisch `nil` wenn Node nicht geladen.
- `applyHarmonicDecision()`: schreibt nur noch `currentMagnetNodeID`, liest keine Position mehr.
- `reloadAllChunks()`: `currentMagnetNodeID = nil` explizit hinzugefügt (neben `lastApproachChordName = nil`).
- Kommentar `onRadarSnapshot` aktualisiert (Parameter-Bezeichnung, Computed-Property-Erklärung).

`FlightController.swift`
- Kommentar für `harmonicMagnetTarget` aktualisiert: Quelle ist jetzt computed property.

`HarmonyEngine3DApp.swift`
- Kommentar `onGraphHook`-Block aktualisiert: `currentMagnetNodeID` statt `magnetTargetPosition`.

`ARCHITECTURE.md`
- Glossar-Eintrag „Magnet Target" aktualisiert: beschreibt computed-property-Ansatz und
  `currentMagnetNodeID` als einzige gespeicherte Größe.

**Ergebnis:**
- Keine zwei synchron zu haltenden Zustände mehr für dieselbe Information
- Veraltete Magnet-Positionen nach Chunk-Unload strukturell ausgeschlossen
- Kein Verhalten geändert — `SceneKitView.swift` liest weiterhin `scene.magnetTargetPosition`

---

## [3.9.4] – 2026-04-05

### Refactor: Harmonic Radar — push → pull (kontinuierliche Aktualisierung)

**Problemstellung:** Der Radar zeigte bisher nur den Zustand zum Zeitpunkt des letzten
`onChordActivated`-Events. Zwischen Akkord-Aktivierungen blieb die Anzeige eingefroren.

**Lösung: zwei getrennte Aktualisierungspfade**

`HarmonyScene.swift`
- `var onRadarSnapshot: (([LocalNode], simd_float3, simd_float3?) -> Void)?` — neuer Callback.
- `private var radarFrameCounter = 0` — Throttle-Zähler.
- Am Ende von `updateProximity()`: alle 6 Frames (`radarFrameCounter % 6 == 0`, ≈10 Hz)
  wird `onRadarSnapshot` mit `localChordNodes`, `cameraNode.simdWorldPosition` und
  `magnetTargetPosition` aufgerufen. Aufruf auf dem Render-Thread.

`HarmonicDebugModel.swift`
- `@Published var magnetTarget: simd_float3? = nil` hinzugefügt.
- Kommentar dokumentiert beide Aktualisierungspfade (kontinuierlich vs. ereignisbasiert).

`HarmonyEngine3DApp.swift`
- `scene.onRadarSnapshot` verdrahtet: dispatcht auf Main Thread, schreibt
  `dbm.localNodes`, `dbm.playerPosition`, `dbm.magnetTarget`.
- `coordinator.onGraphHook` vereinfacht: schreibt nur noch `lastDecision` + `activeChord`
  (kein `localNodes`/`playerPosition` mehr — die kommen jetzt live via onRadarSnapshot).

`HarmonicRadarView.swift`
- Neuer `magnetMarker`: offener Magenta-Ring an der Weltposition von `magnetTarget`.
  Überlagert ggf. den Node-Punkt (gewollt — Zielposition und Node fallen normalerweise zusammen).
- Neue `magnetRow` in der Statusleiste: zeigt Echtzeit-Distanz Spieler → Magnet-Ziel.
- Kommentar aktualisiert.

**Ergebnis:**
- `localNodes` / `playerPosition` / `magnetTarget`: live, alle ~100 ms, unabhängig von Akkord-Events
- `lastDecision` / `activeChord`: weiterhin ereignisbasiert (letzter bekannter RuntimeHarmonik-Output)
- Keine Änderung an Harmonielogik, RuntimeHarmonik, Magnetismus, Chunk-/JSON-Web-Logik

---

## [3.9.3] – 2026-04-05

### Feature: JSON-Web-Modus — 3D-Welt direkt aus HarmonyMap

**Kernidee:** Die 3D-Welt wird nicht mehr aus dem Chunk-System + `.txt`-Netzwerkdaten gebaut,
sondern direkt aus der geladenen `HarmonyMap` (`harmony-web-c-center.json`).
Das Chunk-System bleibt als Fallback vollständig erhalten, wird bei aktivem JSON-Web-Modus
aber vollständig überbrückt.

**`HarmonyScene.swift`**

- `init(network:harmonyMap:)` — neuer optionaler Parameter `harmonyMap: HarmonyMap? = nil`.
  Wenn nicht nil: `buildJsonWebLayout(map:)` statt `updateChunks`.
  `jsonWebMap` wird im init gesetzt; `jsonWebMode` leitet daraus ab (`jsonWebMap != nil`).

- `buildJsonWebLayout(map:resetCamera:)` (neu): Platziert alle `map.nodes` gleichmäßig auf
  einem XZ-Kreis (Radius 180 Einheiten). Jeder Node bekommt Schlüssel `"chord_json_<id>"`.
  `ChordData` wird direkt aus `HarmonyNode.midiNotes` + `id` gebaut.
  Nodes als Pseudo-Chunk unter `jsonWebCoord (888888, 888888, 888888)` registriert →
  `reloadAllChunks()` räumt automatisch auf.
  Kamera-Reset auf `(0, 30, 240)` → Blick von außen auf den Ring.

- `reloadJsonWebLayout()` (neu): `reloadAllChunks()` + `buildJsonWebLayout(map:, resetCamera: false)`.
  Spielerposition bleibt beim Reload erhalten.

- `loadNetwork(_:)`: Guard `!jsonWebMode` → Netzwerkwechsel aus Settings wird im JSON-Web-Modus lautlos ignoriert.

- `updateProximity()`: Wenn `jsonWebMode`:
  - `pendingNetwork` wird verworfen (statt `loadNetwork` aufzurufen)
  - `pendingReload` ruft `reloadJsonWebLayout()` statt `reloadAllChunks()`
  - `updateChunks` wird nicht aufgerufen

**`HarmonyEngine3DApp.swift`**

- `_harmonyMap: HarmonyMap?` im init gesetzt, wenn JSON erfolgreich geladen.
- `HarmonyScene(network: network, harmonyMap: _harmonyMap)` — Map wird durchgereicht.

---

## [3.9.2] – 2026-04-05

### Feature: Harmonic Radar (Debug) + Harmony Web C-Zentrum (Testwelt)

**TEIL A — HarmonicRadarView (neues Debug-Overlay, Hotkey R)**

`HarmonicDebugModel.swift` (neu): Observable-Datenbehälter mit `lastDecision`, `localNodes`,
`activeChord`, `playerPosition`. Ausschließlich vom AppModel (App Layer) beschrieben.
UI-Komponenten lesen nur.

`HarmonicRadarView.swift` (neu): Radar-Draufsicht (XZ-Ebene). Spieler als Fadenkreuz in der Mitte.
Lokale Akkord-Nodes als farbige Punkte mit Chord-Name-Labels.
Farbkodierung: Grün = selectedNodeID (Magnet-Ziel), Gelb = suggestedChord (HarmonyLogic-Empfehlung),
Weiß = activeChord (zuletzt aktiviert), Grau = übrige Nodes.
Statuszeilen: suggested / target (ID + Distanz) / active / strategy.
Kein SceneKit, keine Harmonielogik im Panel.

`FlightController`: `@Published var showHarmonicRadar: Bool = false` + keyCode 15 (R-Taste) zum Togglen.

`ContentView`: neuer Parameter `harmonicDebugModel: HarmonicDebugModel`. Radar-Overlay top-right,
zIndex 30, Transition `.opacity + .move(.trailing)`.

`HarmonyEngine3DApp`: `harmonicDebugModel` in AppModel, non-private.
`coordinator.onGraphHook` erweitert: schreibt `HarmonicDecision`, `localNodes`, `activeChord`
und `playerPosition` auf Main Thread in `HarmonicDebugModel`.

**TEIL B — harmony-web-c-center.json (neue Testwelt)**

`Sources/HarmonyShared/Resources/maps/harmony-web-c-center.json` (neu):
8 Nodes: Cmaj7, Dm7, Em7, Fmaj7, G7, Am7, Bm7b5, Db7.
22 Kanten: 17 gerichtet (functional), 5 ungerichtet (modal).
Abgedeckte Funktionsbereiche: Tonika (Cmaj7, Em7, Am7), Subdominante (Fmaj7, Dm7),
Dominante (G7, Bm7b5), Tritonussubstitution (Db7→Cmaj7), Trugschluss (G7→Am7),
iii-vi-ii-V-I-Kette, relMajMin-Bezüge.
HarmonyNetwork + HarmonyLogic konsistent im selben File → kein Mismatch mehr.

**TEIL C — Neue Testwelt als aktive Basis**

`HarmonyEngine3DApp.init()`: lädt `harmony-web-c-center` statt `reference-core` als primäre Map.
ChordGenerator-Fallback bleibt erhalten. `reference-core.json` bleibt unberührt im Bundle.

---

## [3.9.1] – 2026-04-05

### UI: AudioMixerPanel – Hardware-Mischpult-Optik

**Rein visuelles Restyling** — alle Bindings, Logik, Konfigurationsfelder unverändert.

**Globale Farbtoken (`MixerColor`)**
Neue `enum MixerColor` mit benannten Konstanten für Gehäuse (bodyTop/Mid/Bot), Rahmen (rimTop/Bot),
Knob-Kappe (knobCapHi/Lo/rim) und Text (labelFg, dimFg, sectionFg). Verhindert Magic-Color-Streuung.

**Panel-Gehäuse**
Dreistufiger `LinearGradient` (dunkel-charcoal, top → bottom). Gestufter Doppelrahmen:
äußere helle Linie + innere dunkle Linie → Tiefenwirkung wie ein Hardware-Chassis.

**Header**
Gradient-Hintergrund (leicht heller als Body), amber-farbiger Titeltext (`rgb 0.90/0.75/0.45`),
oranges Akzentstreifen-Detail links (3 × 18 px, LinearGradient), physischer Close-Knopf (RadialGradient-Kappe).

**Kanal-Trennlinie**
Zwei-Linien-Rille (dunkle Linie + helle Gegenlinie, 2 px) statt einfacher Divider → eingravierter Effekt.

**ChannelStrip**
3 px farbiger Akzentbalken oben pro Strip (LinearGradient links → rechts).
Header-Bereich mit eigenem dunkleren Inset-Hintergrund + feiner Trennlinie unten.
Kanal-Titel als `weight: .heavy`.

**KnobView**
RadialGradient-Kappe (Lichteinfall von oben-links) + Gradient-Rand (TopLeading hell → BottomTrailing dunkel).
Vollständiger Track-Ring (gesamter Drehweg sichtbar, `color.opacity(0.18)`).
Indikator-Punkt mit `.shadow` (farbiger Glow).

**VFaderView**
Track: dunkle Nut (rgb 0.06) mit Rand. Thumb: breiter (24 × 14 px), Gradient-Körper (grau),
horizontaler Griffstreifen (farbiger LinearGradient), Gradient-Rand, Schatten.

**SectionLabel**
Kleiner farbiger Akzentbalken (2 × 9 px) links + off-white Text (sectionFg). Font: size 9 statt 10.

**DelayTapRow**
Kleine LED-artige Rechteckmarkierung (3 × 10 px) am Tap-Button. Track: dunkleres Fill.

**sectionDivider**
Zwei-Linien-Rille (Grobe-Linie + Gegenlinie offset +1) statt weißer Opacity-Linie.

---

## [3.9.0] – 2026-04-05

### Feature: v1-Netzwerkmodell in HarmonyShared (HarmonyNetwork_Spec_v1.md)

**SeededRNG nach HarmonyShared verschoben**
`SeededRNG` war in `HarmonyEngine3D/WorldGeneration.swift` — für `HarmonyGraphEngine` in
`HarmonyShared` nötig. Verschoben nach `Sources/HarmonyShared/SeededRNG.swift`, `public` gemacht.
Algorithmus identisch. `HarmonyEngine3D` importiert `HarmonyShared` → keine Verwendungsstelle betroffen.

**HarmonyModel.swift (neu)**
`RelationType` (6 Typen: V-I, ii-V, relMajMin, parallelMajMin, commonTone, tritSubst),
`ChordType`, `HarmonicFunction`, `Layout3D`, `MagnetProfile` (3 Presets),
`HarmonyNode`, `HarmonyEdge`, `HarmonyLayer`, `MapLayout`, `HarmonyMap` — alle `Codable`
(custom `init(from:)` für `tags` und `weight` mit Defaultwerten), `Identifiable` wo vorgesehen.

**HarmonyMapLoader.swift (neu)**
`load(named:)` — lädt JSON aus `Bundle.module/maps/`, validiert und gibt `HarmonyMap?` zurück.
`toChordNetwork(_:layer:)` — konvertiert zu `ChordNetwork` (Kompatibilität mit bestehendem System).
Validierung: schemaVersion-Check (hard), doppelte Node/Edge-IDs, Edge-Referenzen auf Nodes und Layer.
Bei Fehler: nil + Log — kein Crash, Fallback auf `ChordGenerator`.

**reference-core.json (neu)**
`Sources/HarmonyShared/Resources/maps/reference-core.json` — 7 Nodes (C-Dur-Diatonik + Db7),
7 Edges, 2 Layer (functional, modal). Exakt nach Spec, keine Änderungen.

**HarmonyGraphEngine.swift (neu)**
`neighbors(of:)`, `transitions(from:)`, `weightedChoice(from:)` (SeededRNG, deterministisch),
`setLayer(_:)`, `recordVisit(_:)`.
Kontext-Modulation: ii-V-Boost (×1.5), Rückkehr-Dämpfung (×0.4), Spannungserhalt (×1.3).

**AppModel-Integration (minimal)**
GraphEngine instanziiert und gehalten — noch nicht mit Proximity/Trigger/Audio verdrahtet.
`reference-core.json` als initiales Netzwerk für `HarmonyScene`. Fallback auf `ChordGenerator`
wenn JSON nicht geladen werden kann. `.txt`-Netzwerke vollständig unverändert.

---

## [3.8.7] – 2026-04-04

### Performance: Node-Budgeting + Bass-Portal als Diamant

**BLOCK A — Node-Budgeting (`updateChunks`)**
Ersetzt das frühere `while drained < 2`-Chunk-Limit durch ein Node-basiertes Budget.
`maxNodesPerFrame = 3`: Chunks mit vielen Nodes (z.B. Clouds) verbrauchen mehr Budget
als leere Chunks — ehrlichere Lastverteilung pro Frame.
Leere Chunks (0 Top-Level-Nodes) zählen als 1, verhindert Endlos-Loop.
Chunk-Reihenfolge, Triggerlogik, musikalische Inhalte: unverändert.

**BLOCK B — Bass-Portal Diamant (`makeBassPortalNode`)**
Ersetzt `SCNTorus` (Mode 0/1/2, ~1152 Dreiecke) und Kugelkranz (Mode 4, ~3200 Dreiecke)
durch zwei `SCNPyramid` Rücken an Rücken (~12 Dreiecke gesamt).
Form: Oktaeder-/Diamantform, symmetrisch um y=0.
Die semitransparente Füll-Kugel (früher innerhalb des Torus) entfällt — war für
den Diamanten nicht sinnvoll und erzeugte ein zusätzliches SCNSphere-Objekt.
Pulse-Animation (Opacity-Sweep) beibehalten — passt zum neuen Objekt, ist günstig.
Triggerlogik, Proximity-Hitbox, Node-Positionen, Node-Namen: unverändert.

---

## [3.8.6] – 2026-04-04

### Bugfix: Regression — Akkord-Gewichtungsberechnung jetzt wieder bedingt

**Problem (eingeführt in 3.8.5):** `loadChunk` berechnete Filter + `allEdges`-Iteration
immer für jeden Chunk, auch wenn der Dichte-Check später keinen Akkord erzeugte.
Vor Sub-Step B war diese Berechnung innerhalb des Dichte-Conditionals — korrekt.

**Fix:** Peek-RNG mit gleichem Seed wie `computeChunkData` (`chunkLogic.chunkSeed(for: coord)`).
`peek.i(100) < chordDensity` liefert dieselbe Entscheidung wie der erste RNG-Call in
`computeChunkData`. Filter + Gewichtungsberechnung laufen nur wenn `willHaveChord == true`.
Leere `weightedChords`-Liste bei `willHaveChord == false` → `computeChunkData` überspringt
Akkord-Auswahl via `!weightedChords.isEmpty`-Guard — Verhalten identisch.

**RNG-Korrektheit:** `computeChunkData` startet seinen eigenen RNG neu (gleicher Seed,
erste Operation `rng.i(100)`) — Peek hat keinen Einfluss auf den echten Daten-RNG.
Musikalische Inhalte (Positionen, Akkorde, Bass-Noten, Roots) sind bit-for-bit identisch.

**Betroffene Datei:** `HarmonyScene.swift` (nur `loadChunk`)

---

## [3.8.5] – 2026-04-04

### Refactoring: ChunkLogic Sub-Step B — ChunkData + computeChunkData + buildNodes

**Ziel:** Daten-Entscheidungen (ChunkLogic) von Rendering (HarmonyScene) trennen. Zweite Stufe der ChunkMap-Extraktion.

**`ChunkLogic.swift` — Ergänzungen:**
- `struct ChunkData` (neu): SceneKit-freie Chunk-Inhaltsbeschreibung (`coord`, `chord?`, `bass?`, `cloud?`, `visualSeed`)
- `computeChunkData(coord:chordDensity:portalDensity:cloudDensity:weightedChords:) -> ChunkData`: deterministisch, kein SceneKit, kein AppSettings
  - Übernimmt alle 3 Daten-Entscheidungen aus dem früheren `loadChunk` mit identischer RNG-Sequenz
  - Erfasst `rng.state` nach allen Daten-Entscheidungen als `visualSeed`

**`HarmonyScene.swift` — Umbau `loadChunk`:**
- Akkord-Typ-Filter + Key-Center-Filter bleiben in `loadChunk` (AppSettings-Zugriff erlaubt)
- Energie-Gewichtung wird als `[(name: String, weight: Float)]` pre-computiert
- Delegiert an `chunkLogic.computeChunkData(...)` für alle Daten-Entscheidungen
- Delegiert an `buildNodes(from:)` für Node-Erstellung

**`HarmonyScene.swift` — neue Funktion `buildNodes(from: ChunkData)`:**
- Baut SCNNodes aus `ChunkData`: `makeChordNode`, `makeBassPortalNode`, `makeMelodyCloudNode`
- Visueller RNG: `SeededRNG(seed: data.visualSeed)` — separater Strom
- Registriert Nodes in `chordDataMap`, `bassPortalPositions`, `cloudNodes` etc.
- Keine Entscheidungslogik, kein AppSettings-Zugriff

**Invarianten:**
- `unloadChunk`: unverändert
- Trigger-Events, MIDI, Audio: unverändert
- Chord-/Bass-/Cloud-Existenz, Positionen, Akkordauswahl, Bass-Noten, Cloud-Roots: identisch
- Akzeptierter Nebeneffekt: visuelle Variation (Knoten-Erscheinung) ändert sich einmalig

---

## [3.8.4] – 2026-04-04

### Bugfix: Lokalisierung — bundle: .module in allen Text()-Aufrufen

**Problem:** Bei SPM-`.executableTarget` mit `.process("Resources")` landen `.lproj`-Dateien in `Bundle.module`, nicht in `Bundle.main`. `Text("key")` sucht standardmäßig in `Bundle.main` → findet nichts → zeigt Raw-Key.

**Betroffene Dateien:** `ContentView.swift`, `AudioMixerPanel.swift`, `ControlsOverlay.swift`

**Fix:** `bundle: .module` in allen `Text()`-Aufrufen mit `LocalizedStringKey`-Inhalt:
- 44 direkte `Text("key")` in ContentView (sed)
- 19 direkte `Text("key")` in AudioMixerPanel (sed)
- 18 direkte `Text("key")` in ControlsOverlay (sed)
- 7 Helper-Function-Bodies in ContentView (`Text(label/title)` mit `LocalizedStringKey`-Parameter)
- 2 ternäre Expressions in ContentView (`Text(cond ? "key1" : "key2", bundle: .module)`)
- `SectionLabel` in AudioMixerPanel (`text: LocalizedStringKey`)
- `labelBlock` in ControlsOverlay (`desc: LocalizedStringKey`)
- 2× `Text(LocalizedStringKey(btn))` in ControlsOverlay

**Korrekt unverändert:** `Text(label)` wo `label: String` (verbatim Strings: Akkordnamen, Emoji, Button-Labels, Format-Strings).

---

## [3.8.3] – 2026-04-04

### Refactoring: ChunkLogic extrahiert (Sub-Step A)

**Ziel:** Reine Chunk-Berechnungslogik aus HarmonyScene herauslösen. Kein funktionaler Umbau, kein RNG-Einfluss.

**Neue Datei `ChunkLogic.swift`:**
- `struct ChunkLogic { chunkSize: Float, loadRadius: Int }`
- `currentChunk(for: simd_float3) -> ChunkCoord` — ersetzt cx/cy/cz-Block in updateChunks
- `neededChunkCoords(around: ChunkCoord) -> Set<ChunkCoord>` — ersetzt Triple-Loop
- `sortedByDistance(from:coords:) -> [ChunkCoord]` — ersetzt newCoords.sorted-Block
- `chunkSeed(for: ChunkCoord) -> UInt64` — identische Implementierung wie bisher
- `randomPosition(in:rng:) -> simd_float3` — wie bisher, Rückgabe auf simd_float3 geändert

**HarmonyScene.swift:**
- `chunkSize: Float` und `loadRadius: Int` entfernt → `private let chunkLogic = ChunkLogic(chunkSize: 160.0, loadRadius: 3)`
- `chunkSeed(_:)` entfernt (jetzt in ChunkLogic)
- `randomPosInChunk(_:rng:)` entfernt (jetzt in ChunkLogic als `randomPosition(in:rng:)`)
- `updateChunks` verwendet jetzt `chunkLogic.*`
- `loadChunk` verwendet `chunkLogic.chunkSeed(for:)` und `SCNVector3(chunkLogic.randomPosition(in:rng:))` an den 3 Callsites
- `loadChunk`/`unloadChunk` inhaltlich unverändert

**Invarianten:**
- RNG-Sequenz identisch → Welt deterministisch unverändert
- Verhalten identisch (gleiche Load/Unload-Mengen, gleiche Sortierung)
- Kein SceneKit in ChunkLogic

**Geänderte Dateien:** `ChunkLogic.swift` (neu), `HarmonyScene.swift`, `VERSION`, `CHANGELOG.md`, `PROJECT_LOG.md`

---

## [3.8.2] – 2026-04-04

### Fix: Inkonsistentes CH3-Mapping (Name ohne Töne) — ChordMapping-Struct

**Ursache:** `mappingChordName` und `mappingChordTones` waren zwei unabhängige `@Published`-Properties. Zwischen ihren Writes konnten SwiftUI-Renders stattfinden, was kurzzeitig zu Name-ohne-Töne führte. Zusätzlich: bei `chord.midiNotes.isEmpty` (defekte ChordData) wurde `mappingChordTones = ""` geschrieben während `mappingChordName` gesetzt blieb.

**Fix:**
- `struct ChordMapping: Equatable` in `FlightController.swift` eingeführt: `name: String` + `tones: [String]`. Atomar, kein inkonsistenter Zwischenzustand möglich.
- `mappingChordName: String` + `mappingChordTones: String` durch `@Published var mappingChord: ChordMapping? = nil` ersetzt.
- `OutputCoordinator.onChordActivated`: Guard `!tonesArray.isEmpty` — kein Update bei leeren midiNotes; ansonsten atomares `ChordMapping` in einem Assign.
- `ContentView.topDisplay`: `if let mapping = flightController.mappingChord { ... mapping.name ... }`
- `ContentView.leftStickMap`: `mapping?.tones ?? []` — kein String-Split mehr.
- `ContentView.midiRow`: `.map { LocalizedStringKey($0.name) } ?? "hud.chords"` — Optional-Chain statt leerer String-Prüfung.

**Geänderte Dateien:** `FlightController.swift`, `OutputCoordinator.swift`, `ContentView.swift`, `VERSION`, `CHANGELOG.md`, `PROJECT_LOG.md`

---

## [3.8.1] – 2026-04-04

### Fix/Feature: Cockpit-Zustand – sounding vs. CH3-Mapping-Quelle getrennt

**Problem:** `onChordDeactivated` löschte `activeChord` und `activeChordTones` gemeinsam. Dadurch verschwanden sowohl Akkordname als auch Stick-Karte (Chord-Tones) aus dem Cockpit, sobald ein Akkord nicht mehr klang — obwohl `chordToneProvider` weiterhin Noten lieferte und der CH3-Gamepad-Input weiterhin funktionierte.

**Lösung – `FlightController.swift`:**
Zwei alte Properties (`activeChord`, `activeChordTones`) durch drei klar getrennte Properties ersetzt:
- `soundingChordName: String` — gesetzt solange CH0 MIDI-Noten ausgibt; leer bei noteOff.
- `mappingChordName: String` — letzter aktivierter Akkord; bleibt bis ein neuer Akkord übernimmt.
- `mappingChordTones: String` — Töne der CH3-Mapping-Quelle; gleicher Lifecycle wie `mappingChordName`.

**Lifecycle – `OutputCoordinator.swift`:**
- `onChordActivated`: setzt alle drei Properties.
- `onChordDeactivated`: leert nur `soundingChordName`. `mappingChord*` bleiben erhalten.

**Cockpit-Darstellung – `ContentView.swift`:**
- Akkordname sichtbar solange `mappingChordName != ""` (= CH3-Quelle existiert).
- Volle Helligkeit (`opacity 1.0`) wenn `soundingChordName != ""` (klingt aktiv).
- Gedimmt (`opacity 0.35`) wenn nur noch Mapping-Quelle (klingt nicht mehr).
- Übergang animiert (0.20 s).
- Stick-Karte (Chord-Tones) sichtbar solange `mappingChordName != ""` — unabhängig vom Klangzustand.

**Geänderte Dateien:** `FlightController.swift`, `OutputCoordinator.swift`, `ContentView.swift`, `VERSION`, `CHANGELOG.md`, `PROJECT_LOG.md`

---

## [3.8.0] – 2026-04-04

### Feature: Zweisprachige UI (Deutsch / Englisch)

**Infrastruktur:**
- `AppLanguage.swift`: Neues Enum `AppLanguage` (`.german` / `.english`) mit `CaseIterable`, `Hashable`, `rawValue` = Locale-Identifier.
- `AppSettings.swift`: Neues `@Published var language: AppLanguage` mit sofortigem `didSet`-Schreiben in UserDefaults (Key `he3d.ui.language`).
- `HarmonyEngine3DApp.swift`: `@AppStorage("he3d.ui.language")` + `.environment(\.locale, Locale(identifier: languageRaw))` am Root-WindowGroup. SwiftUI propagiert die Locale in den gesamten View-Baum; `Text(LocalizedStringKey(...))` löst automatisch in der richtigen Sprache auf (macOS 13+, sofortige Wirkung ohne Neustart).

**Sprachdateien:**
- `Resources/de.lproj/Localizable.strings` — 100 Keys, vollständige deutsche Übersetzung.
- `Resources/en.lproj/Localizable.strings` — 100 Keys, englische Entsprechungen.
- DSP-Fachbegriffe (Attack, Reverb, ADSR, Pan, etc.) bewusst in beiden Dateien identisch — international einheitlich im professionellen Audiobereich.

**UI-Änderungen:**
- `SettingsPanel` (ContentView): Alle `settingsSection` / `settingsToggle` / `settingsSlider` / `settingsSliderF` / `settingsStepper` / `settingsChannelRow` Hilfsfunktionen nehmen jetzt `LocalizedStringKey` statt `String`. Alle ~40 Call-Sites auf Lokalisierungs-Keys umgestellt.
- Sprach-Picker in SettingsPanel unter eigenem Abschnitt „SPRACHE / LANGUAGE" ergänzt.
- `ControlsOverlay`: `labelBlock(desc: LocalizedStringKey)` + `midiLegend(LocalizedStringKey)`. Alle deutschen Beschreibungstexte durch Keys ersetzt.
- `AudioMixerPanel`: `SectionLabel(text: LocalizedStringKey)` + `PanelSlider(label: LocalizedStringKey)`. Alle Sektion- und Parameter-Labels durch Keys ersetzt.
- `midiRow(label: LocalizedStringKey)` in ContentView — Akkordnamen (dynamisch, nicht in .strings) fallen auf Literal zurück.

**Geänderte Dateien:** `AppLanguage.swift` (neu), `de.lproj/Localizable.strings` (neu), `en.lproj/Localizable.strings` (neu), `AppSettings.swift`, `HarmonyEngine3DApp.swift`, `ContentView.swift`, `AudioMixerPanel.swift`, `ControlsOverlay.swift`, `VERSION`, `CHANGELOG.md`, `PROJECT_LOG.md`

---

## [3.7.2] – 2026-04-04

### Fix: Bass-Velocity erhöht (80 → 110)

**Ursache:** Mit `bassVelocity = 80` und Unison-`gainScale = 1/sqrt(2) ≈ 0.707` landete die effektive Stimm-Amplitude bei `(80/127) × 0.707 ≈ 0.446` — also weniger als die Hälfte des möglichen Pegels. Der Bass klang im Mix deutlich zu leise.

**Fix (`AppSettings.swift`):** Default `MIDIConfig.bassVelocity: Double = 110` (war 80). Gleiches gilt für den `load()`-Fallback-Wert. Effektive Amplitude steigt auf `(110/127) × 0.707 ≈ 0.613` (+2.8 dB gegenüber vorher).

### Feature: Dynamik-Kompressor auf CH1 (Bass)

**Motivation:** Unison-Stimmen mit Detune erzeugen eine langsame Amplitudenmodulation (Schwebung). Ohne Kompressor schlägt der Bass in Peaks kurz durch und wirkt dann wieder zu leise. Zusätzlich soll der Kompressor den Sustained-Pegel anheben.

**Implementierung (`AudioEngine.swift`):**
- Neues Objekt `private let compressorBass = AVAudioUnitDynamicsProcessor()`
- Signalpfad CH1: `gainBass → compressorBass → [sumBass (Dry) + delay1/2/3SendBass]` — ersetzt vorherigen Direktpfad `gainBass → [sumBass + Sends]`
- Parameter: threshold −20 dB, headRoom 5 dB, compressionRatio 3:1, expansionRatio 1:1, attack 20 ms, release 150 ms, masterGain +6 dB

**Wirkung:** Peaks werden um max. −9 dB (3:1 bei −50 dB Excess) komprimiert; +6 dB Make-up Gain hebt den Sustained-Pegel an; die Schwebungsmodulation der Unison-Stimmen wird gleichmäßiger.

**Geänderte Dateien:** `AppSettings.swift`, `AudioEngine.swift`, `VERSION`, `CHANGELOG.md`, `PROJECT_LOG.md`

---

## [3.7.1] – 2026-04-04

### Bugfix: Unison-Gain-Scaling (Bass zu leise)

**Ursache:** `gainScale = 1/n` ist eine Amplituden-Normierung, die für korrelierte (phasengleiche) Signale gilt. Unison-Stimmen sind durch Detune unkorreliert — für unkorrellierte Signale ist die energie-erhaltende Formel `1/sqrt(n)`. Mit `n=2` und `gainScale=0.5` war der Bass um ~3 dB zu leise gegenüber einem Kanal ohne Unison.

**Fix (`SynthNode.swift`):** `gainScale = 1/sqrt(n)` statt `1/n`. Bei `n=2`: 0.707 statt 0.500 → +3 dB zurückgewonnen.

### Fix: Volume-Mapping logarithmisch (alle Kanäle)

**Ursache:** `gainX.outputVolume = cfg.channelVolume` war lineares Amplitude-Mapping. `AVAudioMixerNode.outputVolume` ist eine lineare Skala — lineares UI-Mapping ist psychoakustisch falsch, da das Gehör logarithmisch arbeitet. 50 % UI-Wert klingt bei linearem Mapping nicht wie −6 dB, sondern wie −20 dB.

**Fix (`AudioEngine.swift`):** Neue private Funktion `linearVolume(_ v: Float) -> Float` — dB-basiertes Mapping:
- UI-Wert 0…1 → −60 dB … 0 dB → lineare Amplitude via `pow(10, db/20)`
- `volume = 0` → exakt 0 (stumm)
- `volume = 1` → Amplitude 1.0 (0 dB, unverändert)
- Default-Werte (0.80/0.85/0.90) → ca. −12 dB … −6 dB (praxisgerechte Arbeitspegel)

Gilt für alle vier Kanäle symmetrisch. UI zeigt weiterhin 0…100 % — keine Änderung an AppSettings oder PanelSlider.

**Geänderte Dateien:** `SynthNode.swift`, `AudioEngine.swift`, `VERSION`, `CHANGELOG.md`, `PROJECT_LOG.md`

---

## [3.7.0] – 2026-04-04

### Block A — Dry-Panning pro Kanal (Mixer-Layer)

**Neuer Parameter `ChannelFXConfig.pan: Float` (−1.0…+1.0):**
- Wirkt auf `gainX.pan` (AVAudioMixerNode) — positioniert den gesamten Kanal im Stereofeld.
- Alle vier Kanäle (CH0/1/2/3) haben eigene Pan-Einstellung.
- Default: `0.0` (Mitte) für alle Kanäle. CH1 (Bass) sollte typischerweise zentriert bleiben — dokumentiert im Code und im Default.
- Persistenz via UserDefaults: Key `he3d.audio.[kanal].pan`.
- `AudioEngine.applyEffectConfigX()`: setzt `gainX.pan = cfg.pan` (nach Volume, vor applyFX).
- `AudioMixerPanel`: neue **PAN-Sektion** oben in jedem Strip — KnobView zwischen "L"/"R"-Labels, Anzeige "L50" / "C" / "R50".

**Layer-Trennung eingehalten:**
- Pan ist Mixer-Layer (AVAudioMixerNode) — kein Pan in SynthVoice/SynthNode.
- `SynthVoice.panGainL/R` (Block B, Unison-Spread) ist Synth-Layer — keine Vermischung.

### Block B — Unison für Bass (Synth-Layer)

**Neue `SynthParams`-Felder:**
- `unisonVoices: Int` — Anzahl der Stimmen pro NoteOn (1 = kein Unison, 2–3 = Unison).
- `unisonDetune: Float` — Maximale Verstimmung der äußersten Stimmen in Cent (0…20).
- `unisonSpread: Float` — Stereo-Verteilung der Stimmen (0 = Mono, 1 = volle Breite).

**`VoicePool.noteOn()` — Unison-Voice-Erzeugung:**
- Spawnt `unisonVoices` Voices statt einer.
- `gainScale = 1/n` → konstante Gesamtlautstärke bei beliebiger Voice-Anzahl.
- Detune-Verteilung: symmetrisch um 0, t∈[0,1] normiert → `detuneOffset = (t−0.5)·2·unisonDetune`.
- Pan-Verteilung: analog → `voicePan = (t−0.5)·2·unisonSpread`.
- Voice-Stealing: korrekt für alle Unison-Voices (gestohlene Voice bekommt voiceTimestamp, nächste Iteration findet andere).

**`SynthVoice.configure()` — erweiterte Signatur:**
- Neue Parameter: `detuneOffset: Float = 0.0`, `voicePan: Float = 0.0`, `gainScale: Float = 1.0`.
- Detune: `freq = baseFreq * pow(2, detuneOffset/1200)`.
- Constant-Power-Panning: `L = √2·cos(angle), R = √2·sin(angle), angle = (voicePan+1)·π/4`.
  - Pan=0: L=R=1.0 (kein Pegelabfall gegenüber Vorgänger).
  - Pan=±1: dominanter Kanal = √2 ≈ +3 dB (Standard-DAW-Panning).

**`SynthVoice.render()` — Stereo-Output:**
- Neue Signatur: `render(intoL:intoR:frameCount:)`.
- Beide Kanäle separat akkumuliert: `L += sample * panGainL`, `R += sample * panGainR`.
- Kein Heap, kein Alloc.

**`VoicePool.render()` und Render-Closure:**
- Render-Closure übergibt L- und R-Buffer separat an `VoicePool.render(intoL:intoR:)`.

**Bass-Defaults (aktiviert):**
- `unisonVoices: 2`, `unisonDetune: 8.0` Cent, `unisonSpread: 0.25`.
- Spread bewusst moderat: zu breiter Bass destabilisiert den Mix.
- Alle anderen Kanäle: `unisonVoices: 1` (kein Unison, kein Pegelunterschied).

**Neue ChannelFXConfig-Felder:** `pan`, `unisonVoices`, `unisonDetune`, `unisonSpread`.
Persistenz und UI vollständig integriert.

**`AudioMixerPanel`: neue UNISON-Sektion** — Voices-Picker (segmented 1/2/3), Detune-Slider (Cent), Spread-Slider (%). Alle Kanäle gleichartig — Bass hat durch Defaults ab Start aktives Unison.

**Geänderte Dateien:**
`SynthParams.swift`, `SynthVoice.swift`, `SynthNode.swift`,
`AppSettings.swift`, `AudioEngine.swift`, `AudioMixerPanel.swift`,
`VERSION`, `CHANGELOG.md`, `PROJECT_LOG.md`

---

## [3.6.2] – 2026-04-04

### Live-Parameter: Filter Cutoff/Resonance + Sustain auf laufende Voices

**Problem:** Filter und Sustain wirkten bisher nur ab der nächsten NoteOn (Snapshot-Semantik).
Beim Slider-Ziehen hörte man keine Reaktion auf laufende Noten.

**Fix in `SynthNode.VoicePool.applyParams()`:**
- **Filter (Cutoff + Resonance):** Wenn sich einer der Werte ändert, werden die neuen
  Biquad-Koeffizienten (b0/b1/b2/a1/a2) sofort auf alle aktiven Voices übertragen.
  Filter-State (S1/S2) wird NICHT zurückgesetzt → kein Knacken bei glattem Sweep.
  Analog-Verhalten: Filter-Sweep wirkt in Echtzeit auf alle klingenden Noten.
- **Sustain-Level:** Wenn sich der Wert ändert, wird `sustainLevel` und `envelopeValue`
  aller Voices im Sustain-Stage sofort aktualisiert.
  → Lautstärke gehaltener Noten reagiert live auf Slider-Bewegung.

**Snapshot-Semantik erhalten (by design):**
- Attack/Decay/Release: Rate bereits bei configure() berechnet, mid-note-Änderung sinnlos
- Waveform: Wechsel mid-note klingt mechanisch — Snapshot ist musikalisch korrekt

**Verarbeitung:** Alle Änderungen laufen über die SPSC-Queue (Main → Audio-Thread), kein Lock.
`calcBiquadLP()` wird nur aufgerufen wenn sich Cutoff oder Resonance tatsächlich geändert haben.

### Stereo-Format: expliziter stereoFormat für AVAudioSourceNode

**Problem:** `AVAudioSourceNode(renderBlock:)` (ohne Format-Angabe) verhandelt das Format
mit AVAudioEngine. Format-Negotiation konnte theoretisch mono ergeben, wodurch Delay-Panning
(`delay1SendX.pan`, etc.) keine stereo-Breite erzeugt hätte.

**Fix in `SynthNode.prepare()`:**
- `AVAudioSourceNode(format: stereoFormat, renderBlock:)` mit explizitem 32-Bit-Float-Stereo-Format.
- `abl.count` in der Render-Closure ist garantiert 2 — Panning und Stereo-Verarbeitung
  in AVAudioUnitDelay/AVAudioUnitReverb sind sichergestellt.
- Signal-Charakter bleibt L=R (dual-mono am Source); Stereo entsteht durch Delay-Panning downstream.

**Geänderte Dateien:** `SynthNode.swift`, `VERSION`, `CHANGELOG.md`, `PROJECT_LOG.md`

---

## [3.6.1] – 2026-04-04

### PolyBLEP-Bandlimitierung für Saw und Square

**Problem:** Naive Sägezahn- und Rechteckwellen erzeugen beim Phase-Wrap hörbare Aliasing-Artefakte (Clicking, Zipper-Noise), besonders bei hohen Noten.

**Lösung:** PolyBLEP (Polynomial Band-Limited Step)-Korrekturfunktion in `SynthVoice`.
- `SynthVoice.polyBLEP(phase:phaseIncrement:)` — private static, kein Heap, kein Alloc
- `.saw`: ein polyBLEP-Aufruf am Phase-Wrap (Diskontinuität Phase ≈ 0/1)
- `.square`: zwei polyBLEP-Aufrufe (steigende Flanke Phase=0, fallende Flanke Phase=0.5, um 0.5 verschoben)
- `.sine` und `.triangle` unverändert (Sinus inherent bandlimitiert; Dreieck harmonics ∝ 1/n²)

### Musikalisches Attack-Mapping (quadratisch)

**Problem:** Lineares `attack × 2000 ms` gibt kurzen Attacks (1–50 ms) zu wenig Slider-Auflösung.

**Lösung:** Quadratische Kurve in `AudioEngine.synthParams(from:)`:
- `attackMs = attack² × 2000 + 1`  (statt `attack × 2000`)
- Erste 22 % des Attack-Sliders decken 0–100 ms ab (statt 0–440 ms)
- Decay/Release: linear (Slider in physikalischen Sekunden — kein Display-Mismatch)
- `PanelSlider.Format.adsrQuadratic(maxMs:)` — neue Format-Variante; spiegelt exakt die DSP-Kurve im Display

### Filter-Resonanz-Range erweitert

- `SynthVoice.calcBiquadLP()`: Q-Range von 0.5…10 auf 0.5…20 erweitert
- Q=20: +26 dB Resonanzspitze — deutlich hörbarer Wah-Sweep-Effekt
- Filter klanglich am besten mit Saw/Square Waveforms wahrnehmbar (Obertöne vorhanden)

### UI — Picker-Farben

**Problem:** Waveform- und Reverb-Preset-Picker zeigten schwarzen Text auf dunklem Hintergrund (system-native NSPopUpButton im hellen Erscheinungsbild).

**Fix:** `.colorScheme(.dark)` + `.foregroundStyle(color)` auf beide Pickers.
- Erzwingt dunkles Erscheinungsbild (helle Schrift) unabhängig von System-Einstellung.

**Geänderte Dateien:**
`SynthVoice.swift`, `AudioEngine.swift`, `AudioMixerPanel.swift`, `VERSION`, `CHANGELOG.md`, `PROJECT_LOG.md`

---

## [3.6.0] – 2026-04-04

### Block A — CH3 vollständiger unabhängiger Kanalzug

**Ist-Zustand (vorher):** `synthChordTone.sourceNode` war direkt an `gainChord` angehängt.
CH3 teilte Gain, alle drei Delay-Ketten, Summierer und Reverb mit CH0.
`applyFXConfig(_, channel: 3)` war ein No-Op.

**Fix:** CH3 hat jetzt einen vollständig eigenen Kanalzug:
- `gainChordTone` — eigener Gain/Level-Fader
- `delay1/2/3SendChordTone` + `delay1/2/3ChordTone` — eigene Delay-Kette
- `sumChordTone` — eigener Summierer (Dry + Taps)
- `reverbChordTone` — eigenes Reverb

`synthChordTone.sourceNode` → `gainChordTone` (kein geteilter Node mit CH0).
`applyEffectConfigChordTone()` vollständig implementiert.
`applyFXConfig(_, channel: 3)` ruft `applyEffectConfigChordTone()` auf.
`AudioConfig.chordTone: ChannelFXConfig` — eigene persistierte Konfiguration.
`AudioMixerPanel` hat jetzt 4 Strips (Chord / Bass / Melody / Chord Tone).

### Block B — Synth-Ausbau: Wellenform, Filter, ADSR

**Wellenformwahl (`SynthParams.waveform: Waveform`):**
- Enum `Waveform: UInt8` mit `.sine` / `.saw` / `.square` / `.triangle`
- Pro-Kanal konfigurierbar via `ChannelFXConfig.waveform`
- Snapshot-Semantik: Wellenform in `SynthVoice.configure()` eingefroren
- Implementierung in `SynthVoice.render()`: phasenbasierte Wellenformgeneratoren

**Biquad-Tiefpassfilter (`SynthParams.filterCutoff/filterResonance`):**
- DF-II Transposed Biquad nach Audio EQ Cookbook
- Cutoff: 0…1 normiert → logarithmisch 20…20.000 Hz
- Resonanz: 0…1 → Q 0.5…10
- Cutoff=1.0 + Resonanz=0.0: Identity-Koeffizienten (vollständiger Bypass, kein Einfluss)
- Koeffizienten bei `configure()` berechnet, State-Reset bei neuer Note
- `SynthVoice.calcBiquadLP()` als private static Funktion (kein Heap, kein Alloc)

**ADSR vollständig steuerbar:**
- `ChannelFXConfig` um `decay: Float` (0.001…2.0 s) und `sustain: Float` (0…1) erweitert
- `attack` und `release` waren gespeichert aber nie auf SynthParams gemappt — jetzt aktiv
- Mapping in `AudioEngine.synthParams(from:)`: attack×2000→attackMs, decay×1000→decayMs,
  sustain direkt, release×1000→releaseMs
- `applyEffectConfigX()` ruft `synthX.updateParams()` — ADSR-Änderungen wirken ab nächster NoteOn
- `VoicePool.noteOn()` übergibt `params: SynthParams` kompakt statt einzelner Felder

**AudioMixerPanel — neue Sektionen:**
- ADSR: alle vier Parameter (A/D/S/R) mit musikalisch beschrifteten Displaywerten
- FILTER: Cutoff-Slider (Hz-Anzeige logarithmisch) + Resonanz-Knob
- OSCILLATOR: Waveform-Picker (Sine / Saw / Square / Triangle)
- Breite: 1040px für 4 Strips (vorher 750px für 3)

**Geänderte Dateien:**
SynthParams.swift, SynthVoice.swift, SynthNode.swift, AppSettings.swift,
AudioEngine.swift, HarmonyEngine3DApp.swift, AudioMixerPanel.swift,
VERSION, CHANGELOG.md, PROJECT_LOG.md

---

## [3.5.9] – 2026-04-04

### Bereinigung – MIDIManager: Dead Code entfernt, allNotesOff() vereinfacht

**Analyse:** MIDIManager enthielt sechs Legacy-Methoden (`playChord`, `stopCurrentChord`,
`playBassNote`, `stopBassNote`, `playMelodyNote`, `playChordTone`) sowie eine separate
`stopAll()`-Methode und zwei Noten-Tracking-Felder (`activeChordNotes`, `activeBassNote`),
die im `AudioOutput`-Protokoll-Flow nie befüllt wurden. Kein Aufrufer dieser Methoden
existierte im `Sources/HarmonyEngine3D/`-Verzeichnis (Grep bestätigt).

Das `allNotesOff()`-Protokoll-Impl. bereinigten diese nie befüllten Felder explizit
(always-no-op) vor dem CC-123-Loop — strukturell irreführend.

**Fix:**
- Alle sechs Legacy-Methoden entfernt.
- `stopAll()` (standalone, nicht Protokoll) entfernt.
- `activeChordNotes: [UInt8]` und `activeBassNote: UInt8?` entfernt.
- `allNotesOff()` auf den CC-123-Loop über CH 0–3 reduziert.
- Kopfkommentar aktualisiert: Kanalnummern jetzt 0-indexed (CH 0–3), passend zum Protokoll.
- Klassen-Doku ergänzt: MIDIManager verwaltet keinen eigenen Noten-State.

MIDIManager ist jetzt ein reiner, zustandsloser MIDI-Byte-Sender. Alle Zustandsentscheidungen
(welche Note ist aktiv, wann off) liegen ausschließlich in den Aufrufschichten.

Geänderte Dateien: MIDIManager.swift, VERSION, CHANGELOG.md, PROJECT_LOG.md

---

## [3.5.8] – 2026-04-04

### Architektur – Bass-Portal-Triggergeometrie explizit entkoppelt

**Analyse:** Die Triggerprüfung (`simd_distance` in `ProximityTracker`) war bereits
mathematisch korrekt kugelförmig. Jedoch wurde die Kandidaten-Position zur Laufzeit
via `node.simdWorldPosition` aus dem SceneKit-Szenegraph gelesen. Die Entkopplung
von visueller Ringform und Triggerzone war damit implizit, nicht dokumentiert und
strukturell nicht gesichert.

**Fix:** Neues `private var bassPortalPositions: [String: simd_float3]` in HarmonyScene.
- Wird beim Platzieren jedes Portals (Status Quo, Harmony Codex, Chunk-Load) mit dem
  gecachten Weltpositions-Vektor befüllt.
- Wird beim Unload synchron entfernt (zusammen mit `bassPortalNodes`).
- `updatePortalProximity` liest ausschließlich aus `bassPortalPositions` — kein
  `simdWorldPosition`-Zugriff mehr in der Triggerlogik.

Ergebnis: Trigger-Hitbox ist jetzt eine explizit gecachte Kugel um den Ringmittelpunkt.
Visuelle Form (SCNTorus) und Triggerzone sind strukturell getrennt und dokumentiert.
ProximityTracker und TriggerEngine sind unverändert.

Geänderte Dateien: HarmonyScene.swift

---

## [3.5.7] – 2026-04-04

### Architektur-Fix – CH3: Note wird in der Eingabeschicht (GamepadController) fixiert

**Problem:** `onChordToneOff` berechnete die MIDI-Note aus `nearestChordNotes` zum
Off-Zeitpunkt neu. Wenn sich der aktive Akkord zwischen NoteOn und NoteOff geändert hatte
(z. B. durch Weiterflug), wurde eine andere Note gestoppt als die, die gestartet worden war.
Die ursprüngliche Note blieb dauerhaft hängend — im SynthNode im Sustain-Zustand, im
MIDI-Ausgang offen.

**Ursache:** Die Note lebte im OutputCoordinator (Berechnung im Off-Closure), nicht in der
Eventquelle (GamepadController). Das widerspricht dem Architekturprinzip: State gehört
in die Schicht, die das Ereignis auslöst.

**Fix:**
- `GamepadController` bekommt `var chordToneProvider: (() -> [UInt8])?` — eine Closure,
  die beim NoteOn von OutputCoordinator gesetzt wird und das aktuelle Noten-Array liefert.
- `private var activeChordToneNote: UInt8? = nil` in GamepadController speichert die
  Note zum NoteOn-Zeitpunkt (Sektor-Eintritt des linken Sticks).
- Callback-Signaturen erweitert:
  - `onChordTone: ((Int, UInt8, UInt8) -> Void)?`  → (sector, **note**, velocity)
  - `onChordToneOff: ((Int, UInt8) -> Void)?`      → (sector, **note**)
- Alle drei Off-Callsites in GamepadController (Mitte-Return, Sektorwechsel, resetAll)
  übergeben die gespeicherte Note.
- OutputCoordinator wird reiner Durchreicher für CH3: setzt Provider einmalig,
  leitet Note aus den Events direkt weiter — keine Berechnung, kein Tracking.

**Invariante:** CH3-Note wird genau einmal festgelegt (beim Sektor-Eintritt) und genau
einmal freigegeben (bei aktiver Note + Off-Event). Kein Akkordwechsel kann die laufende
Note korrumpieren.

Geänderte Dateien: GamepadController.swift, OutputCoordinator.swift

---

## [3.5.6] – 2026-04-04

### Fix – CH2 Melodie: fehlende noteOff zwischen aufeinanderfolgenden Ticks

**Problem:** `MelodyEngine.tick()` setzt `lastNote = nextNote` bevor es die Note zurückgibt.
Beim nächsten Tick-Aufruf war die Vorgängernote damit überschrieben — kein noteOff wurde
zwischen zwei aufeinanderfolgenden Melody-Noten gesendet. Nur der letzte Ton vor dem
Cloud-Verlassen bekam sein Off (via `stop()`). Alle vorherigen Noten hingen:
- SynthNode: durch Voice-Stealing irgendwann überschrieben
- MIDI-Ausgang: dauerhaft hängend

**Fix:** In `updateCloudProximity` (HarmonyScene) wird `melodyEngine.lastNote` BEFORE
dem `tick()`-Aufruf in `prevNote` gesichert. Wenn `tick()` eine neue Note liefert und
`prevNote >= 0`, wird zuerst `onMelodyNoteOff?(prevNote)` gesendet, dann `onMelodyNoteWithVelocity?`.

Vollständige CH2-Sequenz nach Fix:
  tick → noteOff(prev) + noteOn(A)
  tick → noteOff(A) + noteOn(B)
  tick → noteOff(B) + noteOn(C)
  [verlassen] → noteOff(C)  via stop()

**CH3 Kommentar:** Veralteter Kommentar aus 3.5.4 ("Note wird lokal im Binding-Scope
gehalten") korrigiert — trifft seit 3.5.5 nicht mehr zu.

Geänderte Dateien: HarmonyScene.swift, OutputCoordinator.swift

---

## [3.5.5] – 2026-04-04

### Architektur-Korrektur – CH3: `lastCH3Note`-Tracking entfernt

**Problem:** Der vorherige CH3-Fix (3.5.4) führte `var lastCH3Note: UInt8? = nil` als
closure-lokale Variable im OutputCoordinator ein. Closure-lokal ist kein class-level Property,
aber es bleibt Tracking im Coordinator — gegen das Grundprinzip des Systems.

**Ursache des Trackings:** `onChordToneOff: (() -> Void)?` war parameterlos. Der Empfänger
hatte keine Information darüber, welcher Sektor verlassen wurde, und konnte die Note nicht
ohne vorherigen Speicher berechnen.

**Fix:** `onChordToneOff: ((Int) -> Void)?` — trägt jetzt den Sektor-Index des verlassenen
Sektors. Der Sektor ist der vollständige Identifier für CH3, analog zum Portal-Key (CH1) oder
dem Cloud-Key (CH2). OutputCoordinator berechnet die Note aus dem Sektor mit identischer
Logik wie beim NoteOn — kein Zustand, kein Tracking.

Drei Callsites in GamepadController angepasst (Mitte, Sektorwechsel, resetAll).
`lastCH3Note` vollständig aus OutputCoordinator entfernt.

Geänderte Dateien: GamepadController.swift, OutputCoordinator.swift

---

## [3.5.4] – 2026-04-04

### Fix – CH3 Chord-Tones: symmetrisches noteOn / noteOff

**Problem:** CH3 sendete `noteOn` beim Stick-Eingang, aber kein `noteOff` beim Loslassen.
`SynthVoice` verbleibt ohne `triggerRelease()` dauerhaft in der Sustain-Phase und terminiert
nicht. Voice-Stealing verhinderte unbegrenzte Akkumulation (16 Voices max), aber das ADSR-
Release wurde nie getriggert. CH3 verhielt sich nicht wie ein reguläres Spielinstrument.

**Fix — GamepadController:**
- Neuer Callback `onChordToneOff: (() -> Void)?`
- In `leftThumbstick.valueChangedHandler`:
  - Stick → Mitte (mag < 0.40): `onChordToneOff?()` wird gefeuert, wenn ein Sektor aktiv war.
  - Sektorwechsel: `onChordToneOff?()` vor `onChordTone?()` — Off für alten, On für neuen Ton.
- In `resetAll()` (Controller-Disconnect): Off wenn Sektor aktiv.

**Fix — OutputCoordinator:**
- Lokale `var lastCH3Note: UInt8? = nil` im Binding-Scope von `bindGamepadEvents()`.
  Geteilt zwischen `onChordTone`- und `onChordToneOff`-Closures. Kein class-level Property.
- `onChordTone`: setzt `lastCH3Note = n` nach dem noteOn.
- `onChordToneOff`: sendet `noteOff(channel: 3, note: note)`, löscht `lastCH3Note`.

**Ergebnis:** CH0–CH3 alle symmetrisch (noteOn / noteOff). ADSR ist nur noch Hüllkurve nach
dem Off, kein Ersatz für das Loslassen. `allNotesOff` bleibt ausschließlich für den Panic-Button.

Geänderte Dateien: GamepadController.swift, OutputCoordinator.swift

---

## [3.5.3] – 2026-04-04

### Bugfix – CH0 Akkorde: drei Note-Off-Defekte behoben

**Bug 1 — Voice-Leading-Asymmetrie:**
`onChordActivated` sendete `voiced`-Noten (Ergebnis von `VoiceLeadingEngine.apply()`),
`onChordDeactivated` las aber das originale, unbearbeitete `ChordData` aus `chordDataMap`.
Da `voiceLead()` jeden Ton unabhängig in die optimal nächste Oktavlage verschiebt,
wichen die gesendeten und gestoppten MIDI-Noten systematisch voneinander ab → Voices hingen.
Fix: `chordDataMap[new] = voicedData` nach dem Voice-Leading-Schritt — der Deaktivierungspfad
liest jetzt exakt dieselben Noten, die beim NoteOn verwendet wurden.

**Bug 2 — Kein NoteOff bei `unloadChunk`:**
`chordDataMap.removeValue(forKey: n)` erfolgte vor dem Trigger-Check. Wenn der aktive Akkord
entladen wurde, war `chordDataMap[n]` bereits nil → kein `onChordDeactivated`, keine NoteOffs.
Fix: `chordDataMap.removeValue(forKey: n)` gibt das Optional zurück (wie bereits bei Bass);
das Ergebnis (`unloadedChordData`) wird gesichert und für `onChordDeactivated` vor dem
`chordTriggerEngine.reset()` verwendet.

**Bug 3 — Kein NoteOff bei `reloadAllChunks`:**
`chordTriggerEngine.reset()` wurde aufgerufen ohne vorheriges `onChordDeactivated`,
während CH1 und CH2 ihre Off-Events korrekt sendeten.
Fix: `if let key = chordTriggerEngine.activeKey, let data = chordDataMap[key]` vor dem Reset.

Geänderte Datei: HarmonyScene.swift

---

## [3.5.2] – 2026-04-04

### Bugfix – CH2 Melodie: symmetrisches noteOff

**Problem:** CH2 hatte kein Off-Konzept im Eventmodell. Das Off wurde im OutputCoordinator
über einen Proximity-Float-Schwellwert (`onNearestCloud prox < 0.08`) detektiert und als
`allNotesOff(channel: 2)` (Hard-Kill) gesendet. Die laufende Notennummer war dem Coordinator
unbekannt. MelodyEngine hielt `lastNote: Int` intern, surfacte es aber nicht als Off-Event.

**Fix:**
- `MelodyEngine.stop() -> Int?`: neue Methode — gibt lastNote zurück (wenn >= 0) und setzt
  es auf -1. Idempotent: zweiter Aufruf gibt nil. Kein Tracking außerhalb der Eventquelle.
- `HarmonyScene.onMelodyNoteOff: ((Int) -> Void)?`: neuer Callback, analog zu onBassNoteOff.
- `updateCloudProximity` — zwei Auslöser:
  1. Cloud-Trigger-Wechsel: `stop()` vor `melodyEngine.reset()` → Off vor dem Zustandslöschen.
  2. Proximity-Abfall ≤ 0.08: `else if proximity <= 0.08, let offNote = melodyEngine.stop()`
     in tick()-Zweig → Off einmalig beim ersten Unterschreiten der Schwelle.
- `reloadAllChunks`: `stop()` vor `melodyEngine.reset()`.
- `unloadChunk`: `stop()` vor `cloudTriggerEngine.reset()` wenn aktive Cloud entladen.
- `OutputCoordinator`: `scene.onMelodyNoteOff` neu gebunden → `noteOff(channel: 2, note: n)`.
  `allNotesOff(channel: 2)` vollständig entfernt. `melodyWasActive`-Flag entfernt.
  `onNearestCloud` jetzt reine HUD-Weiterleitung (kein Proximity-Trigger mehr).

**Ergebnis:** CH0–CH2 vollständig symmetrisch (noteOn/noteOff). Kein Coordinator-Tracking.
`allNotesOff(channel:)` bleibt nur für den Gamepad-Panic-Button (onAllNotesOff).

Geänderte Dateien: MelodyEngine.swift, HarmonyScene.swift, OutputCoordinator.swift

---

## [3.5.1] – 2026-04-04

### Bugfix – CH1 Bass: symmetrisches noteOff

**Problem:** `onBassNoteOff` war als parameterloses `(() -> Void)?`-Closure deklariert.
Die Notennummer war in `HarmonyScene` an allen drei Callsites aus `portalBassNote` lesbar,
wurde aber nicht transportiert. Folge: `OutputCoordinator` musste `allNotesOff(channel: 1)`
senden — ein Hard-Kill aller CH1-Stimmen statt eines gezielten noteOff.

**Fix:**
- `onBassNoteOff`: Signatur `(() -> Void)?` → `((Int) -> Void)?` (HarmonyScene)
- Normaler Deaktivierungs-Pfad (updatePortalProximity): `portalBassNote[old]` wird
  per `if let` gesichert und an den Callback übergeben. Kein Event wenn Note fehlt.
- `reloadAllChunks()`: `portalTriggerEngine.activeKey` + `portalBassNote[key]` gelesen,
  bevor Engines zurückgesetzt werden.
- `unloadChunk()`: Note via `portalBassNote.removeValue(forKey: n)` gesichert (gibt
  Optional zurück), dann nach dem Trigger-Check verwendet — korrekte Reihenfolge,
  da `portalBassNote` vor der Trigger-Prüfung entfernt wurde.
- `OutputCoordinator.onBassNoteOff`: Closure erhält `note: Int`, wandelt analog zum
  NoteOn mit `bassOctaveShift` um, sendet `noteOff(channel: 1, note: n)`.
  `allNotesOff(channel: 1)` vollständig entfernt.

**Ergebnis:** CH1 ist jetzt symmetrisch (noteOn / noteOff). Kein Tracking im Coordinator.
CH2 (Melody) bleibt unverändert — strukturelles Problem im Eventmodell, separater Schritt.

Geänderte Dateien: HarmonyScene.swift, OutputCoordinator.swift

---

## [3.5.0] – 2026-04-04

### Reines Synth-System (Rev. 5) – vollständige Umsetzung

**Architekturprinzip:**
Die Engine ist ausschließlich ein Note-Event-Generator (wie eine Klaviatur).
Polyphonie, Voice-Stealing und ADSR sind Eigenschaften des SynthNode, nicht der Engine.
Musikalische Logik liegt ausschließlich in HarmonyCore.

**Step 2 – SynthParams + erweitertes NoteEventQueue-Protokoll:**
- `SynthParams.swift` neu: ADSR (attackMs, decayMs, sustain, releaseMs) + maxVoices.
  Eigenschaft des SynthNode, nicht der AudioEngine.
- `NoteEventQueue.swift`: neues `Kind.paramUpdate` + `params: SynthParams`-Feld in NoteEvent.
- `SynthNode.swift`: VoicePool mit SynthParams-Übergabe; `updateParams(_ params:)` für Live-ADSR-Updates via Queue.

**Step 3 – Neues AudioOutput-Protokoll (Rev. 5):**
- `AudioOutput.swift` ersetzt: `noteOn(channel:note:velocity:)`, `noteOff(channel:note:)`,
  `allNotesOff(channel:)`, `allNotesOff()`, `applyFXConfig(_:channel:)`.
- `MIDIManager.swift`: neue Konformanz (MIDI-Byte-Ebene, kein Auto-Off mehr in noteOn).
- `OutputCoordinator.swift`: alle Bindings auf neues Protokoll umgestellt.
  CH0: noteOff pro Note (chord.midiNotes trägt Notennummer).
  CH1/CH2: allNotesOff(channel:) – struktureller Mangel dokumentiert (Off-Events tragen keine Notennummer).
  Ziel: nach HarmonyCore-Extraktion (Phase 1) durch noteOff ersetzt.

**Step 4 – Alle vier Kanäle auf SynthNodes:**
- `synthBass` ersetzt samplerBass (CH1), `synthMelody` ersetzt samplerMelody (CH2).
- `synthChordTone` neu für CH3 (Chord-Tones via Gamepad).
- samplerBass/samplerMelody nicht mehr im Audio-Graph.

**Step 5 – Vollständiges Aufräumen:**
- `AudioEngine.swift` final: alle Sampler-Reste entfernt, SF2-Lade-Logik entfernt,
  alte play*/stop*-Methoden entfernt, Note-Tracking entfernt.
  Node-Umbenennung: panMixerX → delay1/2/3SendX, preReverbX → sumX, dryMixerX entfällt.
  Send-Modell: delay1/2/3SendX liegt VOR dem Delay-Unit (Send-Pegel = Feed in Delay).
- `AppSettings.swift`: instrumentProgram, instrumentBankMSB, instrumentBankLSB aus
  ChannelFXConfig, loadFX() und saveFX() entfernt.
- `AudioMixerPanel.swift`: instrumentSection entfernt.

Geänderte Dateien: SynthParams.swift (neu), NoteEventQueue.swift, SynthNode.swift,
AudioOutput.swift, MIDIManager.swift, OutputCoordinator.swift, AudioEngine.swift,
AppSettings.swift, AudioMixerPanel.swift

---

## [3.4.2] – 2026-04-04

### Bugfix – Pitch und Klick bei Bass und Melody (AudioEngine)

**Pitch-Fehler (Bass und Melody 2 Oktaven zu hoch):**

SF2-Analyse ergab: testpad.sf2 und minimal.sf2 haben beide bank=0, program=0.
Der Code lud mit `bankMSB: 0x79` (= bank 121) — diese Bank existiert nicht in den bundle-eigenen SF2-Dateien.
`AVAudioUnitSampler` fiel auf einen internen Apple-DLS-Sound zurück, dessen Pitch-Mapping
von den bundle-eigenen Samples abweicht → Pitch ~2 Oktaven zu hoch für Bass und Melody.

Fix: `bankMSB: 0x79` → `bankMSB: 0` in `loadAllSoundBanks_sf2()` und `applyInstrument()`.
`applyInstrument` nutzt nun `effectiveBankMSB`: 0 für bundle-SF2, `cfg.instrumentBankMSB` nur für System-DLS.
ChannelFXConfig-Defaults (chordDefaults, bassDefaults, melodyDefaults): `instrumentBankMSB: 0x79` → `0`.

**Klacken/Klicken bei monophonem Note-Wechsel (Bass und Melody):**

SF2-Analyse ergab: testpad.sf2 hat `exclusiveClass=69` in IGEN → neues Note On schneidet
laufende Voice sofort hart ab (kein Release) → hörbare Wellenform-Diskontinuität = Klack.

Fix 1: Wechsel von testpad.sf2 auf minimal.sf2 für alle Sampler-Pfade.
minimal.sf2 hat kein `exclusiveClass` → Note-Wechsel läuft sauber mit Release durch.

Fix 2: Legato-Note-Reihenfolge in `playBassNote()` und `playMelodyNote()`:
Bisher: stopNote(alt) → startNote(neu) → kurze Stille zwischen Release und neuem Attack.
Neu:    startNote(neu) → stopNote(alt) → neuer Ton beginnt sofort, alter Ton klingt natürlich aus.

**SynthVoice-Formel verifiziert:**
`440.0 * pow(2.0, (note - 69.0) / 12.0)` ist korrekt (gleichstufig, A4 = 440 Hz).
MIDI 60 → 261.63 Hz ✓, MIDI 69 → 440.00 Hz ✓, MIDI 72 → 523.25 Hz ✓.
Einmalige Verifikations-Log in `SynthNode.prepare()` hinzugefügt.

Geänderte Dateien: AudioEngine.swift, AppSettings.swift, SynthNode.swift

---

## [3.4.1] – 2026-04-04

### Stabilisierung – SynthNode (Phase 3D)

**NoteEventQueue.swift**
- Dokumentation der SPSC-Korrektheit vollständig ausgebaut (ARM64 / x86_64 Barrier-Semantik explizit erklärt)
- `if next == readIndex` → `guard next != readIndex` / `guard readIndex != writeIndex` (konsistenter Swift-Stil)
- Upgrade-Pfad auf `swift-atomics` / `Swift 6 Synchronization.Atomic` dokumentiert

**SynthVoice.swift**
- Neues Feld `activationOrder: UInt64` — monotoner Zähler für Voice-Stealing
- `configure()` erhält zusätzlichen Parameter `order: UInt64`
- Oszillator erweitert: Fundamental (85 %) + 2. Harmonische sin(4π·phase) (15 %)
  → Einzelstimmen im Akkord-Cluster sind musikalisch besser erkennbar; Amplitudenfaktor 0.15 unverändert

**SynthNode.swift (VoicePool)**
- Neues Feld `private var voiceTimestamp: UInt64 = 0` (Audio-Thread-exklusiv)
- `noteOn`: inkrementiert `voiceTimestamp` (wrapping add) bei jeder Aktivierung
- Voice-Stealing ersetzt „immer Index 0" durch linearen Scan nach minimalem `activationOrder`
  → älteste aktive Stimme wird gestohlen (musikalisch sinnvollste Strategie)

---

## [3.5.0] – 2026-04-03

### Architektur – AppSettings aufgesplittet (Phase 4)
- `AppSettings` in vier typisierte Sub-Configs aufgeteilt: `FlightConfig`, `MIDIConfig`, `RenderConfig`, `HarmonyConfig`
- Alle Zugriffe im gesamten Codebase auf Sub-Config-Pfade migriert (`s.flight.*`, `s.midi.*`, `s.render.*`, `s.harmony.*`)
- UI-State (`showSettingsPanel`, `showCockpitPanel`, `showControlsOverlay`) aus `AppSettings` in `FlightController` verlagert (@Published)
- `ControlsOverlay`: `onDismiss`-Closure statt direktem `AppSettings`-Zugriff
- `CockpitControlPanel`, `SettingsPanel`: `onClose`-Closure statt direktem `AppSettings`-Zugriff
- Combine-Subscriptions in `HarmonyScene` auf Sub-Config-Pfade migriert (`$harmony.map { $0.networkIndex }`, `$render.map { $0.showNetworkEdges }`)

### Architektur – Input Layer formalisiert (Phase 5)
- `InputProvider.swift` neu: Protokoll mit fünf Flug-Eingabe-Properties (thrustFwd/Bwd, lookX/Y, braking)
- `GamepadController` konformiert via leerer Extension (alle Properties bereits vorhanden)
- `FlightController`: `inputProvider: (any InputProvider)?` statt direktem `GamepadController`-Zugriff in `buildInputState()`
- Dependency Injection im App Layer: `AppModel.init()` setzt `fc.inputProvider = GamepadController.shared`
- Sensor-Telemetrie (Gyro, Touchpad → MIDI CC) bewusst außerhalb des Protokolls belassen
- `InputProvider.swift` dokumentiert Ausschlussgründe (Sensor-CC, Audio-Callbacks, Tastatur, Maus)

### Dokumentation
- `ARCHITECTURE.md` erstellt: Schichtenmodell, Datenfluss, Thread-Modell, Modul-Grenzen, Key Types, MIDI-Mapping, Restkopplungen

---

## [3.3.0] – 2026-03-26

### Feature – Quaternion-Orientierung + Loopings
- `FlightState`: `yaw`/`pitch` (Float) → `orientation: simd_quatf`; kein Gimbal-Lock, Loopings möglich
- `FlightPhysics.update()`: Rotation als body-space Quaternion-Komposition (yaw → Y, pitch → X)
- `FlightController.mouseDragged()`: Quaternion-Rotationen statt Winkel-Arithmetik; kein Pitch-Limit mehr
- Autopilot: navigiert jetzt über body-space Winkelberechnung (`atan2` auf transformierten Zielvektor)
- `SceneKitView`: `pendingCameraReset` setzt `orientation` auf Identitäts-Quaternion zurück

### Feature – Magnetische Akkord-Anziehung
- `FlightController.applyMagneticForce()`: weiche Velocity-Nudge Richtung nächsten Akkord
- Kraft ∝ (1 − dist/radius)² → kein Snap, keine abrupten Richtungswechsel
- `AppSettings.magnetStrength` (0…3, Standard 0.5) + `AppSettings.magnetRadius` (Standard 120 m)
- Nur im manuellen Modus aktiv; Autopilot deaktiviert Magnetik

### Fix – Akkordnamen im Lock-On-Overlay
- `SceneKitView.updateTargets()`: `scene.chordDataMap[uniqueKey]?.name` statt uniqueKey als Label
- `ScreenTarget.id` bleibt uniqueKey (stabil für ForEach-Diffing), `.name` ist jetzt der echte Akkordname

### Verbesserung – Lock-On visuell
- `TimelineView(.animation)` treibt Pulsieren: 1 Hz (weit) → 2 Hz (nah), Amplitude 0 → ±12 %
- Nähe-Skalierung: Grundgröße +31/+40 %, zusätzlich bis +70 % im Nahbereich
- Glow-Radius: 2 pt (weit) → 18 pt (nah)
- Linienbreite: 1.5 pt → 3.0 pt bei Annäherung
- `CornerArm` Vorzeichenfehler für TR/BR behoben

---

## [3.2.0] – 2026-03-26

### Feature – Lock-On Targeting System
- `TargetingSystem.swift` neu: `ScreenTarget`, `TargetingOverlayModel`, `TargetingOverlayView`, `TargetReticle`, `CornerBrackets`
- Akkord-Nodes werden jährlich alle 3 Frames via `SCNView.projectPoint()` in Screen-Space projiziert
- Maximal 15 nächste Akkorde werden angezeigt; fade-out ab 400 m, weg ab 700 m
- Autopilot-Ziel wird cyan hervorgehoben; normale Targets weiß
- `TargetingOverlayModel` wird auf Render-Thread befüllt, auf Main Thread publiziert
- `SceneKitView` erhält `targetingModel`-Parameter; `ContentView` erstellt das Model als `@StateObject`
- Overlay ist `allowsHitTesting(false)` – blockiert keine Eingaben

---

## [3.1.0] – 2026-03-26

### Architektur – FlightPhysics entkoppelt
- `FlightPhysics.swift` neu: `FlightState`, `InputState`, `FlightPhysics` – kein SceneKit, keine Abhängigkeiten
- `FlightController`: keine `SCNNode`-Referenz mehr; hält nur noch `FlightState` und baut `InputState`
- `SceneKitView`: liest `flightController.state` und schreibt Position + Orientierung auf `cameraNode`
- `HarmonyScene`: `autopilotEngine` auf `private(set)` hochgestuft; `pendingCameraReset` statt direkter `cameraNode.position`-Manipulation in Layouts
- `SCNVector3+Math`: `init(_ v: simd_float3)` Convenience-Init hinzugefügt

### Fixes – Fluggefühl
- **Ein-Frame-Lag entfernt**: `forward`/`right` werden jetzt direkt aus `yaw`/`pitch` berechnet, kein `camera.worldTransform`-Roundtrip mehr
- **Float↔CGFloat-Conversions eliminiert**: Physik durchgängig in `simd_float3` (Float32)
- **Pitch-Limit**: Pitch wird auf ±85° begrenzt – verhindert Gimbal-Lock und abruptes Umschlagen der Steuerung

---

## [3.0.0] – 2026-03-26

### Architektur
- `AutopilotEngine` als eigenständiger `struct` in `HarmonyShared` extrahiert
  – kein SceneKit, kein AppSettings, kein UI
  – verwendet `simd_float3` statt `SCNVector3`
- `HarmonyScene`: Autopilot-Logik vollständig delegiert; interne Properties
  `autopilotVisited`, `autopilotVisitedMax`, `lastAutopilotActiveChord` entfernt
- `autopilotTarget` und `autopilotNextChordName` sind jetzt computed properties (keine `didSet`-Kopplung)
- `Package.swift`: swift-tools-version 6.0 → 5.10, macOS 15 → 13 (keine Features benötigten 15+)

### Fixes
- `pendingEdgeRebuild = true` nur noch wenn tatsächlich ein Chunk geladen wurde (war: jedes Frame)
- Debug-Print auf Render-Thread entfernt

---

## [2.5.0] – 2026-03-26

### Features
- Voice Leading per Toggle schaltbar (Menü: STIMMFÜHRUNG)
- `AppSettings.voiceLeadingEnabled`

---

## [2.3.0] – 2026-03-25

### Features
- Harmony Codex als kuratierter Flachkreis (Radius 1000, 24 Akkorde)
- Chord-Sichtbarkeit: Creation-time Deduplication (keine Runtime-Visibility-Änderungen)
- Orphan-Promotion bei Chunk-Unload
- Autopilot HUD: zeigt nächsten Zielakkord
- Autopilot-Pitch-Fix (Vorzeichen entfernt)
- Autopilot-Loop-Fix: suffix(2)-Retry + excludingNames im Fallback

### Fixes
- Unsichtbare Akkorde triggerten trotzdem MIDI (Proximity prüft jetzt opacity)

---

## [2.0.0] – 2026-03-24

### Features
- Status Quo kuratiertes Layout (Easter Egg)
- Gamepad: Gyro + Touchpad als MIDI CC
- Bass Hold-Modus
- Chord-Typ-Filter (maj7, m7, dom7, m7b5, dim7 etc.)
- Key-Center-Filter
- Velocity-Slider für alle MIDI-Kanäle

---

## [1.0.0] – 2026-03-23

### Initial
- 3D Infinite-World Chord-Navigation via SceneKit
- PS5 DualSense Gamepad-Steuerung
- CoreMIDI Virtual Output (CH1 Akkorde, CH2 Bass, CH3 Melodie)
- Chunk-basiertes LOD-System
- Akkord-Netzwerke als .txt-Dateien (Jazz, Bach, Blues, Coltrane, Diatonisch u. a.)
