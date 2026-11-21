import Foundation

// MARK: – SynthVoiceEngine
//
// W-03b1 (`.agent_handoff/latest_codex.md`, Runde 070): Auswahl des
// Stimmtyps, den `SynthNode.VoicePool` rendert.
//
//   .legacy       → `AudioCoreVoice`             (Oszillator + Biquad + ADSR, seit S-02b)
//   .atmospheric  → `AudioCoreAtmosphericVoice`  (W-01, Runde 066)
//
// Produkt-Default seit W-03b2 (Runde 071, Stephan-Entscheidung 2026-08-02):
// `.atmospheric`. Er steht in `AppSettings.AudioConfig.voiceEngine` — das ist
// die einzige Stelle, die beantwortet, welche Stimme beim Start klingt.
// `SynthParams.voiceEngine` traegt weiterhin `.legacy` als neutralen
// Vorkonfigurationswert; die Begruendung dieser Trennung steht dort.
//
// Der Legacy-Pfad bleibt ueber dieselbe Einstellung waehlbar und klingt dann
// bit-identisch zum Stand `13e5eaf` (Regressionstest in
// `SynthVoiceEngineTests`).
//
// ---------------------------------------------------------------------------
// Warum ein Tag-Enum und ZWEI vorgehaltene Pools — und nicht ein Protokoll
// ---------------------------------------------------------------------------
//
// Dieser Typ ist bewusst NUR ein Etikett. Er transportiert keine Stimme, er
// benennt nur, welcher der beiden gleichzeitig vorgehaltenen Pools in
// `SynthNode.VoicePool` gerade rendert. Die drei erwogenen Alternativen und
// warum sie verworfen wurden:
//
// 1. Protokoll mit existentiellem Boxing (`[any SynthVoiceRendering]`) —
//    verworfen. Ein Existential mit einem Payload dieser Groesse liegt auf dem
//    Heap (`AudioCoreAtmosphericVoice` passt nicht in den 3-Wort-Inline-Puffer),
//    jede Mutation im Renderpfad kann eine Kopie ausloesen, und jeder Aufruf
//    kostet eine Indirektion ueber die Witness Table. Das reisst genau die
//    Allokations- und Dispatchfreiheit ein, die S-08b-fix und W-03a
//    hergestellt haben.
//
// 2. Ein Enum MIT Payload (`enum PooledVoice { case legacy(AudioCoreVoice)
//    case atmospheric(AudioCoreAtmosphericVoice) }`) in einem Array —
//    verworfen, obwohl der Dispatch statisch waere. Swift kann den Payload
//    eines Enums nicht in-place mutieren: jeder Zugriff im Renderpfad waere
//    `switch` mit `var`-Bindung, Mutation der lokalen Kopie und Rueckschreiben
//    — zwei Kopien des vollstaendigen Payloads pro Stimme und Block, plus
//    ARC-Retain/Release auf die in der Stimme liegenden Wavetable-Puffer. Der
//    Speichervorteil waere zudem gering: ein Enum-Array kostet
//    `n * max(a, b)`, zwei Pools kosten `n * (a + b)`, und `a`
//    (`AudioCoreVoice`, reine Skalare) ist gegenueber `b` klein.
//
// 3. Generische Funktion ueber ein Voice-Protokoll — verworfen. Sie waere
//    statisch, ABER nur solange der Optimizer spezialisiert. Faellt die
//    Spezialisierung aus, bleibt der generische Pfad mit Witness-Table-
//    Aufrufen uebrig, und zwar ohne Warnung und ohne dass ein Test das
//    bemerkt. Der Realtime-Vertrag darf nicht von einer Optimizer-Heuristik
//    abhaengen.
//
// Gewaehlt: zwei getrennte, gleichzeitig vorgehaltene Arrays konkreten Typs
// plus dieses Tag. Der Renderpfad verzweigt EINMAL PRO BLOCK auf das Tag und
// laeuft danach in einer monomorphen Schleife ueber ein Array eines konkreten
// Structs — direkter Aufruf, in-place Mutation ueber den Array-Subscript, kein
// Boxing, keine Witness Table, keine Allokation. Der Preis ist der Speicher
// des inaktiven Pools und etwas Codeverdopplung in `VoicePool`; beides ist
// laut Handoff-Vorgabe ausdruecklich nachrangig gegenueber dem
// Realtime-Vertrag.

/// Welcher Stimmtyp im `SynthNode`-Renderpfad aktiv ist.
///
/// `rawValue` ist der Persistenzschluessel in `AppSettings`
/// (`he3d.audio.voiceEngine`) — Werte duerfen nicht umnummeriert werden.
enum SynthVoiceEngine: Int, CaseIterable, Codable {

    /// `AudioCoreVoice` — der bis W-03b2 klingende Bestandspfad.
    case legacy = 0

    /// `AudioCoreAtmosphericVoice` — die in W-01 zusammengesetzte Stimme.
    case atmospheric = 1
}
