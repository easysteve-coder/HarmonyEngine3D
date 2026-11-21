import Foundation
import HarmonyAudioCore

// MARK: – Waveform
//
// Wellenform des Oszillators. Eigenschaft von SynthNode/AudioCoreVoice — nicht der AudioEngine.
// Wird via SynthParams.waveform beim NoteOn in AudioCoreVoice.configure() eingefroren
// (uebersetzt via Waveform.audioCoreWaveform, siehe AudioCoreMapping.swift).
// Snapshot-Semantik: Laufende Voices behalten ihre Wellenform bis zum Voice-Ende.

enum Waveform: UInt8, CaseIterable, Codable {
    case sine     = 0   // Sinus + 2. Harmonische (85 % / 15 %) — warm, rund
    case saw      = 1   // Sägezahn — brillant, reich an Obertönen
    case square   = 2   // Rechteck — hohl, nasaler Charakter
    case triangle = 3   // Dreieck — weich, sinusähnlich aber mit Charakter
}

// MARK: – SynthParams
//
// Klangkonfiguration eines SynthNode-Kanals.
// Enthält: Wellenform, Filter (Cutoff/Resonanz), ADSR-Hüllkurve, Stimmanzahl.
//
// SynthParams trennt Klangverhalten vom Routing der AudioEngine.
// Die Engine übergibt SynthParams beim prepare()-Aufruf und wertet ihn nicht aus.
//
// Wirkungsbereich:
//   – Wellenform, Filter und ADSR gelten für neue NoteOns (Snapshot-Semantik via configure()).
//   – Laufende Voices: ADSR und Wellenform wurden bei configure() eingefroren; gelten bis Voice-Ende.
//   – maxVoices: nach prepare() fixiert; Live-Änderungen haben keine Wirkung.
//
// Live-Updates: über NoteEventQueue als .paramUpdate(SynthParams)-Event.
// Der Audio-Thread übernimmt neue Parameter lock-free vor der nächsten NoteOn.

struct SynthParams {

    /// Wellenform des Oszillators (Snapshot-Semantik).
    var waveform: Waveform = .sine

    /// ADSR Attack-Zeit in Millisekunden.
    var attackMs:  Float = 20.0

    /// ADSR Decay-Zeit in Millisekunden.
    var decayMs:   Float = 100.0

    /// ADSR Sustain-Pegel (0…1).
    var sustain:   Float = 0.70

    /// ADSR Release-Zeit in Millisekunden.
    var releaseMs: Float = 300.0

    /// Maximale Stimmanzahl im Voice-Pool.
    /// Wird einmalig beim prepare()-Aufruf gesetzt und ist danach nicht mehr live-änderbar
    /// (Voice-Array ist nach dem Aufbau fixiert).
    var maxVoices: Int = 16

    /// Filter-Cutoff, normiert 0…1 → logarithmisch auf 20…20.000 Hz abgebildet.
    /// 1.0 = voll geöffnet (Bypass: Koeffizienten werden auf Identity gesetzt).
    var filterCutoff:    Float = 1.0

    /// Filter-Resonanz, normiert 0…1 → Q 0.5…20.
    /// 0.0 = kein Resonanz-Peak (Q = 0.5). Höhere Werte erzeugen ausgeprägten Formant.
    var filterResonance: Float = 0.0

    // MARK: – Unison
    //
    // Mehrere leicht verstimmte Stimmen pro NoteOn erzeugen einen breiteren,
    // „fetteren" Klang ohne externe Prozessoren.
    //
    // Wirkung:
    //   unisonVoices = 1: kein Unison, identisch mit bisherigem Verhalten.
    //   unisonVoices = 2: zwei Stimmen, symmetrisch um 0 verstimmt.
    //   unisonVoices = 3: drei Stimmen (−detune / 0 / +detune).
    //
    // Amplitude: pro Voice skaliert mit 1/unisonVoices → konstante Gesamtlautstärke.
    //
    // Stereo-Spread: jede Voice erhält eine eigene Pan-Position (berechnet in AudioCoreVoice.configure()).
    //   Spread = 0 → alle Voices mittig. Spread = 1 → volle Stereo-Breite.
    //   WICHTIG: Zu große Stereo-Breite im Bass kann zu instabilem Low-End führen.
    //   Bass-Standardwert: spread ≤ 0.35 empfohlen.

    /// Anzahl der Unison-Stimmen pro NoteOn (1 = kein Unison).
    var unisonVoices: Int   = 1

    /// Maximale Verstimmung der äußersten Unison-Stimmen in Cent.
    /// Beispiel: unisonDetune = 10.0 → äußere Stimmen ±10 Cent verstimmt.
    var unisonDetune: Float = 0.0

    /// Stereo-Verteilung der Unison-Stimmen (0 = Mono / 1 = volle Breite).
    var unisonSpread: Float = 0.0

    // MARK: – Stimmtyp (W-03b1)
    //
    // Welchen Stimmtyp der VoicePool rendert. Bewusst Teil von SynthParams und
    // kein eigenes Queue-Event: die Umschaltung nutzt damit exakt den
    // bestehenden Snapshot-/Command-Pfad (updateParams → NoteEventQueue
    // .paramUpdate → VoicePool.applyParams auf dem Audio-Thread) und braucht
    // weder eine neue Ereignisart noch einen zweiten Serialisierungsweg.
    //
    // Wirkung: ein Wechsel schaltet im Rendercallback zwischen zwei bereits
    // vorgehaltenen Pools um (kein Pool-/Graph-Aufbau dort, siehe
    // SynthNode.VoicePool.switchEngine).
    //
    // ── Warum dieser Default `.legacy` BLEIBT, obwohl W-03b2 den Default
    //    auf die Atmospheric Voice gekippt hat ───────────────────────────
    //
    // Der Produkt-Default — welche Stimme beim Start klingt — liegt in
    // `AppSettings.AudioConfig.voiceEngine` und ist dort `.atmospheric`.
    // Von dort reist er ueber `AudioEngine.applyVoiceEngine` in jeden
    // `SynthParams`-Snapshot, den die Engine bildet; `SynthParams.defaults`
    // liegt auf diesem Weg nicht.
    //
    // `SynthParams.defaults` ist etwas anderes: der neutrale Parametersatz
    // eines Kanals ohne Konfiguration. Er wird an genau zwei Stellen
    // wirksam — als Default-Argument von `SynthNode.prepare()` (dort baut er
    // den Pool auf, bevor der erste echte Snapshot ankommt; es klingt zu
    // diesem Zeitpunkt nichts) und als Basis der Tests.
    //
    // Er bleibt aus zwei Gruenden `.legacy`:
    //   1. Er ist der Anker des Bit-Identitaets-Nachweises. Die
    //      Szenariofolge in `SynthVoiceEngineTests.legacyScenarioChecksum()`
    //      muss unveraendert gegen den Stand `13e5eaf` uebersetzbar
    //      bleiben — sie darf `SynthVoiceEngine` also nicht erwaehnen und
    //      haengt damit an diesem Default.
    //   2. Die uebrigen Bestandstests (Live-Parameter, NoteEventQueue,
    //      S-01-Baseline) pinnen Legacy-Verhalten. Ein Kippen hier wuerde
    //      sie stillschweigend auf einen anderen DSP-Pfad umlenken.

    /// Aktiver Stimmtyp des Voice-Pools (neutraler Vorkonfigurationswert,
    /// nicht der Produkt-Default — siehe `AppSettings.AudioConfig`).
    var voiceEngine: SynthVoiceEngine = .legacy

    // MARK: – Space-Send (W-03c)
    //
    // Wie viel jede Stimme in den gemeinsamen Raum (`SpaceSendBus` →
    // `DeepSpaceReturnNode`) schickt. Beide Werte reisen wie `voiceEngine`
    // als Feld dieses Snapshots über den bestehenden Command-Pfad
    // (updateParams → NoteEventQueue → VoicePool.applyParams) — kein zweiter
    // Serialisierungsweg, kein neuer Ereignistyp.
    //
    // Aufgeteilt in zwei Größen, weil sie an verschiedenen Stellen wirken:
    //
    //   – `spaceSend` ist der Basiswert des Modulationsziels `spaceSend` der
    //     Atmospheric Voice. Er geht in `AudioCoreAtmosphericVoiceParameters`
    //     und wird dort von der Modulationsmatrix ADDITIV verschoben; die
    //     Stimme macht das Ergebnis als `spaceSendLevel` sichtbar.
    //   – `spaceSendChannelGain` ist der Kanalfader auf dem Sendweg, also der
    //     Faktor, der aus dem Send einen Post-Fader-Send macht
    //     (`AudioGraphSendTopology`: `postGain`). Er darf nicht in
    //     `spaceSend` eingerechnet werden — sonst würde er nur den Basiswert
    //     skalieren und den modulierten Anteil unberührt lassen.
    //
    // Die Legacy-Voice hat kein Space-Send-Ziel und speist den Raum
    // deshalb nicht (siehe SynthNode.VoicePool).
    //
    // Beide Defaults sind die NEUTRALEN Werte des Werttyps, nicht der
    // Produkt-Default — dieselbe Trennung wie bei `voiceEngine` (siehe oben).
    // `spaceSend = 0` heißt "kein Raum" und hält damit jede bestehende
    // Baseline und jeden Bit-Identitäts-Anker unverändert gültig. Den
    // produktiv verwendeten Sendpegel setzt `AudioEngine.synthParams(from:)`.

    /// Basis-Sendpegel in den gemeinsamen Raum, 0…1 (neutraler
    /// Vorkonfigurationswert, nicht der Produktwert).
    var spaceSend: Float = 0.0

    /// Kanalfader auf dem Sendweg, 0…1. 1,0 = Send unabgeschwächt.
    var spaceSendChannelGain: Float = 1.0

    // MARK: – Performance-Makros (W-05)
    //
    // Die vier Makros Motion/Color/Space/Focus als Feld dieses Snapshots —
    // aus demselben Grund wie `voiceEngine` und `spaceSend`: sie nutzen damit
    // exakt den bestehenden Command-Pfad (updateParams → NoteEventQueue
    // .paramUpdate → VoicePool.applyParams) und brauchen weder eine neue
    // Ereignisart noch einen zweiten Serialisierungsweg. Der SPSC-Vertrag der
    // NoteEventQueue bleibt unberührt.
    //
    // Die Makros sind global und nicht pro Kanal: es ist ein Instrument mit
    // vier Kanälen, kein Rack aus vier Instrumenten — dieselbe Begründung wie
    // bei `AppSettings.AudioConfig.voiceEngine`. Ein Makrowechsel erzeugt
    // deshalb je einen Snapshot für alle vier Kanäle.
    //
    // Die Legacy-Voice kennt keine Makros und ignoriert das Feld; wirksam
    // wird es ausschließlich über `atmosphericVoiceParameters` (siehe
    // AudioCoreMapping.swift) und dort über die Modulationsmatrix.
    //
    // Default ist der neutrale Werttyp-Default (alle vier auf 0), nicht ein
    // Produkt-Default — dieselbe Trennung wie bei `voiceEngine`/`spaceSend`.
    // Er hält jede bestehende Baseline und jeden Bit-Identitäts-Anker gültig:
    // ein Makrowert 0 liefert in der Matrix einen Beitrag von ±0,0.

    /// Aktueller Stand der vier Performance-Makros (neutraler
    /// Vorkonfigurationswert; den Live-Wert setzt `AudioEngine.applyMacroValues`).
    var macros: AudioCoreMacroValues = .defaults

    /// Standard-Werte, gelten für alle vier Kanäle wenn kein Preset angegeben.
    static let defaults = SynthParams()
}
