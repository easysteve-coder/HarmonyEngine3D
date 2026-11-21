import Foundation
import simd
import HarmonyShared

// MARK: – Chord-Interaction Value-Typen
//
// SceneKit-frei (Runde 026 / E-06a). Kein AppSettings-Zugriff, kein SCNNode,
// kein MIDIManager, kein AudioOutput, kein OutputCoordinator — HarmonyScene
// baut die Werte aus ihren eigenen Daten und wendet die zurückgegebenen
// Actions an.

/// Ein Chord-Knoten-Kandidat für einen Frame. `visible` steuert nur, ob der
/// Kandidat in die Proximity-Auswertung eingeht — die Chord-Daten selbst
/// bleiben auch für unsichtbare Knoten verfügbar, damit ein Knoten, der im
/// selben Frame unsichtbar wird UND den Trigger-Radius verlässt, trotzdem
/// korrekt deaktiviert werden kann (identisch zum bisherigen Verhalten, das
/// `chordDataMap[key]` unabhängig von Sichtbarkeit gelesen hat).
struct ChordInteractionCandidate {
    let key:      String
    let position: simd_float3
    let chord:    ChordData
    let visible:  Bool
}

/// Pro-Frame-Konfiguration, aus AppSettings/HarmonyScene-Zustand gebaut.
/// Radien sind bereits fertig berechnet (0.65×/1×/3× chordTrigger) — die
/// Runtime kennt AppSettings nicht und multipliziert nichts selbst.
struct ChordInteractionConfig {
    let entryRadius:         Float
    let exitRadius:          Float
    let approachRadius:      Float
    let triggersArmed:       Bool
    let voiceLeadingEnabled: Bool
    let chordOctaveShift:    Int
}

struct ChordInteractionInput {
    let candidates:      [ChordInteractionCandidate]
    let cameraPosition:  simd_float3
    let config:           ChordInteractionConfig
}

/// Von HarmonyScene anzuwendende SceneKit-/Datenschicht-Effekte.
/// `updateChordData` ist kein reiner Render-Effekt, sondern eine
/// chordDataMap-Aktualisierung (voice-geführte, noch nicht oktavverschobene
/// Noten) — sie muss trotzdem hier stehen, weil HarmonyScene die einzige
/// Instanz ist, die chordDataMap besitzt (siehe Doku am Enum-Fall).
enum InteractionRenderEffect {
    // Chord (Runde 026 / E-06a)
    case resetApproachGlow(key: String)
    case setApproachGlow(key: String, proximity: Float)
    case setHighlighted(key: String, active: Bool)
    case triggerHarmonicImpulse(key: String)
    /// chord: voice-geführte, NICHT oktavverschobene ChordData. HarmonyScene
    /// schreibt `chordDataMap[key] = chord`, damit `activeChordNotes`/
    /// `nearestChordNotes` (die direkt aus chordDataMap lesen) die aktuell
    /// klingende Voicing widerspiegeln — identisch zum bisherigen
    /// `chordDataMap[new] = voicedData`.
    case updateChordData(key: String, chord: ChordData)

    // Portal/Bass (Runde 027 / E-06b) — eigener Node-Pool (bassPortalNodes)
    // und eigene Helfer (setPortalApproachGlow etc.) in HarmonyScene, daher
    // eigene Fälle statt Wiederverwendung der Chord-Fälle.
    case resetPortalApproachGlow(key: String)
    case setPortalApproachGlow(key: String, proximity: Float)
    case setPortalHighlighted(key: String, active: Bool)

    // Cloud/Melody (Runde 027 / E-06b)
    case resetCloudApproachGlow(key: String)
    case setCloudApproachGlow(key: String, proximity: Float)
    case setCloudHighlighted(key: String, active: Bool)
}

/// Von HarmonyScene über die bestehenden Callbacks zu feuernde Ereignisse.
/// ChordData in `.chordActivated`/`.chordDeactivated` trägt bereits die
/// vollständig aufgelösten (voice-geführten + oktavverschobenen) Noten,
/// bereit zum Senden.
enum InteractionOutputEvent {
    // Chord (Runde 026 / E-06a)
    case nearestChord(name: String, proximity: Float)
    case chordActivated(ChordData)
    case chordDeactivated(ChordData)

    // Portal/Bass (Runde 027 / E-06b). bassNote nil = kein Approach-Kandidat
    // (HarmonyScene formatiert den Notennamen selbst via noteNameStr(_:) —
    // die Runtime kennt keine Anzeige-/Formatierungslogik).
    case nearestPortal(bassNote: Int?, proximity: Float)
    case bassNoteOn(Int)
    case bassNoteOff(Int)

    // Cloud/Melody (Runde 027 / E-06b)
    case nearestCloud(name: String, proximity: Float)
    case melodyNoteWithVelocity(note: Int, velocity: UInt8)
    case melodyNoteOff(Int)
}

// MARK: – Portal/Bass-Interaction Value-Typen (Runde 027 / E-06b)
//
// `bassNote` ist optional: die Original-Semantik erlaubt einen Trigger-
// Übergang auf ein Portal ohne bekannte Bass-Note (dann bleibt `.setHighlighted`
// im RenderEffect trotzdem gesetzt, nur `.bassNoteOn` bleibt aus) — Kandidaten
// werden bewusst nicht gefiltert, identisch zum bisherigen
// `bassPortalPositions.map { ... }` ohne `compactMap`-Guard auf `portalBassNote`.

struct PortalInteractionCandidate {
    let key:      String
    let position: simd_float3
    let bassNote: Int?
}

struct PortalInteractionConfig {
    let entryRadius:    Float
    let exitRadius:     Float
    let approachRadius: Float
    let triggersArmed:  Bool
    let bassHoldMode:      Bool
    let bassOctaveShift:   Int
}

struct PortalInteractionInput {
    let candidates:     [PortalInteractionCandidate]
    let cameraPosition: simd_float3
    let config:          PortalInteractionConfig
}

// MARK: – Cloud/Melody-Interaction Value-Typen (Runde 027 / E-06b)

struct CloudInteractionCandidate {
    let key:      String
    let position: simd_float3
}

/// `now` wird von HarmonyScene übergeben (`Date().timeIntervalSinceReferenceDate`)
/// statt von der Runtime selbst gelesen — hält die Runtime deterministisch/testbar.
struct CloudInteractionConfig {
    let entryRadius:    Float
    let exitRadius:     Float
    let approachRadius: Float
    let triggersArmed:  Bool
    let melodyTempo:    Double
    let melodyVelMax:   Float
    let energyLevel:    Float
    let now:            TimeInterval
}

struct CloudInteractionInput {
    let candidates:     [CloudInteractionCandidate]
    let cameraPosition: simd_float3
    let config:          CloudInteractionConfig
}

/// Eine einzelne, geordnete Aktion. HarmonyScene wendet die Rückgabe-Arrays
/// von `updateChord(...)`/`updatePortal(...)`/`updateCloud(...)` in exakt der
/// gelieferten Reihenfolge an — die relative Reihenfolge zwischen
/// RenderEffects und OutputEvents ist bewusst erhalten (z. B. `updateChordData`
/// vor `chordActivated`, `triggerHarmonicImpulse` nach `chordActivated`,
/// `melodyNoteOff` für den Vorgängerton vor `melodyNoteWithVelocity` — jeweils
/// identisch zu den bisherigen `update*Proximity`-Methoden).
enum InteractionAction {
    case renderEffect(InteractionRenderEffect)
    case outputEvent(InteractionOutputEvent)
}

// MARK: – InteractionRuntime
//
// SceneKit-freier Kern für Chord-, Portal-/Bass- und Cloud-/Melody-Proximity
// und -Trigger (Runde 026 / E-06a Chord, Runde 027 / E-06b Portal+Cloud).
// Besitzt je Kanal eine TriggerEngine plus VoiceLeadingEngine (Chord) bzw.
// MelodyEngine (Cloud) als eigenen, über Frames persistenten Zustand — alle
// waren zuvor Felder auf HarmonyScene. Verwendet ProximityTracker (bereits
// SceneKit-frei, zustandslos) unverändert weiter.
//
// Musikalische Semantik unverändert: gleicher Entry-/Exit-/Approach-Radius je
// Kanal, gleiches Voice-Leading, gleicher Octave-Shift-Clamp 0...127, gleiche
// MelodyEngine-Tick-/Stop-/Reset-Sequenzierung — die Runtime trifft dieselben
// Entscheidungen wie zuvor `HarmonyScene.update{Chord,Portal,Cloud}
// Proximity(_:)`, nur ohne SceneKit-/AppSettings-Kopplung.

/// Snapshot der bei CH0-Aktivierung tatsächlich gesendeten (oktavverschobenen)
/// Noten UND des zugehörigen Akkordnamens — beide aus demselben Zeitpunkt
/// (Runde 039 / V-00b.1, Supervisor-Nachlauf zu Fable-5-Review Finding A2).
/// Vorher speicherte der Snapshot nur die Noten; ein Deactivation-Event nach
/// Kandidatenverlust (der Knoten ist im aktuellen Frame nicht mehr Teil der
/// Kandidatenliste, `byKey[old]` daher `nil`) trug dann `name: ""` statt des
/// ursprünglich aktivierten Namens. `OutputCoordinator` leert
/// `soundingChordName` aber nur bei `soundingChordName == chord.name` — ein
/// leerer Name ließ den alten HUD-Namen unverändert stehen, obwohl MIDI
/// bereits korrekt beendet war.
private struct ChordOutputSnapshot {
    let name:      String
    let midiNotes: [Int]
}

struct InteractionRuntime {

    private var triggerEngine      = TriggerEngine()
    private var voiceLeadingEngine = VoiceLeadingEngine()
    private(set) var lastApproachKey: String? = nil
    private var outputSnapshotByKey: [String: ChordOutputSnapshot] = [:]

    // Portal/Bass (Runde 027 / E-06b)
    private var portalTriggerEngine = TriggerEngine()
    private var lastApproachPortalKey: String? = nil
    private var bassOutputNotesByKey: [String: Int] = [:]

    /// Explizite Menge TATSAECHLICH klingender Bass-Noten je Portal-Key
    /// (Runde 062 / Gate 10). Im Gegensatz zu `bassOutputNotesByKey` — einem
    /// reinen "zuletzt gesendet"-Snapshot, dessen Eintraege beim `noteOff`
    /// NICHT entfernt werden — wird hier bei jedem tatsaechlich gesendeten
    /// `bassNoteOff` (gleich aus welchem Pfad: Trigger-Verlassen, Nachhol-Off
    /// bei `bassHoldMode`-Aus, Chunk-Entladen) der Eintrag ausgetragen. Nur
    /// so laesst sich der Nachhol-Off berechnen, ohne Offs fuer laengst
    /// verstummte Noten zu erzeugen.
    private var soundingBassNotesByKey: [String: Int] = [:]

    /// Zuletzt beobachteter `bassHoldMode`-Wert, um den Uebergang
    /// true -> false frame-uebergreifend zu erkennen (Runde 062 / Gate 10).
    /// `nil` vor der ersten Beobachtung, damit der allererste Frame nie einen
    /// Uebergang ausloest.
    private var previousBassHoldMode: Bool? = nil

    // Cloud/Melody (Runde 027 / E-06b)
    private var cloudTriggerEngine = TriggerEngine()
    private var lastApproachCloudKey: String? = nil
    private var melodyEngine = MelodyEngine()

    var activeKey: String? { triggerEngine.activeKey }
    var portalActiveKey: String? { portalTriggerEngine.activeKey }
    var cloudActiveKey: String? { cloudTriggerEngine.activeKey }
    var currentMelodyPresetName: String { melodyEngine.currentPresetName }

    /// Zuletzt gesendete (oktavverschobene) Noten für einen Key — für
    /// symmetrisches NoteOff aus Reload-/Reset-Pfaden, ohne den Eintrag zu
    /// entfernen (identisch zum bisherigen `chordOutputNotes[key]`-Lesen).
    func outputNotes(forKey key: String) -> [Int]? { outputSnapshotByKey[key]?.midiNotes }

    /// Entfernt den Snapshot für einen Key (Knoten wird aus der Szene
    /// entladen) und liefert die Noten zurück — identisch zum bisherigen
    /// `chordOutputNotes.removeValue(forKey:)` in `unloadChunk`. Der Name
    /// wird mitentfernt (ein Wert, siehe `ChordOutputSnapshot`), aber nicht
    /// separat zurückgegeben — `unloadChunk` bezieht den Namen weiterhin aus
    /// `chordDataMap`, das zum Aufrufzeitpunkt noch denselben Knoten kennt.
    @discardableResult
    mutating func removeOutputNotes(forKey key: String) -> [Int]? {
        outputSnapshotByKey.removeValue(forKey: key)?.midiNotes
    }

    /// Setzt nur den Trigger zurück (kein VoiceLeading-/Approach-Reset) —
    /// für `unloadChunk`, das gezielt nur den entladenen Knoten betrifft.
    mutating func clearActiveTrigger() {
        triggerEngine.reset()
    }

    /// Löscht `lastApproachKey` nur, wenn er dem gegebenen Key entspricht —
    /// identisch zum bisherigen `if lastApproachChordName == n { ... = nil }`.
    mutating func clearApproach(ifEquals key: String) {
        if lastApproachKey == key { lastApproachKey = nil }
    }

    // ── Portal/Bass-API (Runde 027 / E-06b) ───────────────────────────────

    /// Zuletzt gesendete (oktavverschobene) Bass-Note für einen Portal-Key —
    /// für symmetrisches NoteOff aus `reloadAllChunks()`, ohne den Eintrag zu
    /// entfernen (identisch zum bisherigen `bassOutputNotes[key]`-Lesen).
    func bassOutputNote(forKey key: String) -> Int? { bassOutputNotesByKey[key] }

    /// Entfernt den Bass-Snapshot für einen Key (Portal wird aus der Szene
    /// entladen) und liefert die Note NUR zurück, wenn sie zu diesem
    /// Zeitpunkt tatsächlich noch klang (Runde 063 / Finding 062-01).
    ///
    /// Vor dieser Runde lieferte die Funktion den reinen
    /// `bassOutputNotesByKey`-Snapshot zurück — dessen Einträge bleiben nach
    /// einem `noteOff` bestehen. Ein im Hold-Modus klingendes, aber nicht
    /// mehr aktives Portal wurde beim Entladen seines Chunks dadurch NICHT
    /// beendet: `unloadChunk` sendet das Off nur für das gerade aktive
    /// Portal, der Snapshot-Wert wäre für jedes andere Portal ungenutzt
    /// verworfen worden — die Note klang unerreichbar weiter.
    /// `soundingBassNotesByKey` ist die alleinige Quelle der Wahrheit
    /// darüber, ob eine Note wirklich klingt (siehe Feld-Dokumentation);
    /// der `bassOutputNotesByKey`-Snapshot wird weiterhin ausgetragen, sein
    /// Wert fließt aber nicht mehr in den Rückgabewert ein.
    @discardableResult
    mutating func removeBassOutputNote(forKey key: String) -> Int? {
        let soundingNote = soundingBassNotesByKey.removeValue(forKey: key)
        bassOutputNotesByKey.removeValue(forKey: key)
        return soundingNote
    }

    /// Nur den Portal-Trigger zurücksetzen — für `unloadChunk`.
    mutating func clearActivePortalTrigger() {
        portalTriggerEngine.reset()
    }

    /// Löscht `lastApproachPortalKey` nur, wenn er dem gegebenen Key entspricht.
    mutating func clearPortalApproach(ifEquals key: String) {
        if lastApproachPortalKey == key { lastApproachPortalKey = nil }
    }

    // ── Cloud/Melody-API (Runde 027 / E-06b) ──────────────────────────────

    /// Nur den Cloud-Trigger zurücksetzen — für `unloadChunk`.
    mutating func clearActiveCloudTrigger() {
        cloudTriggerEngine.reset()
    }

    /// Löscht `lastApproachCloudKey` nur, wenn er dem gegebenen Key entspricht.
    mutating func clearCloudApproach(ifEquals key: String) {
        if lastApproachCloudKey == key { lastApproachCloudKey = nil }
    }

    /// Beendet die aktive Melodie-Note (Durchreiche zu `MelodyEngine.stop()`)
    /// — für `reloadAllChunks()`/`unloadChunk()`, bevor der Trigger-/
    /// Melody-Zustand zurückgesetzt wird.
    @discardableResult
    mutating func stopMelody() -> Int? { melodyEngine.stop() }

    /// Registriert eine neue Wolke — Durchreiche zu `MelodyEngine.addCloud`.
    mutating func addCloud(key: String, root: Int) {
        melodyEngine.addCloud(key: key, root: root)
    }

    /// Entfernt eine Wolke vollständig — Durchreiche zu `MelodyEngine.removeCloud`.
    mutating func removeCloud(_ key: String) {
        melodyEngine.removeCloud(key)
    }

    @discardableResult
    mutating func nextMelodyPreset() -> String { melodyEngine.nextPreset() }

    @discardableResult
    mutating func prevMelodyPreset() -> String { melodyEngine.prevPreset() }

    /// Vollständiger Reset aller drei Kanäle (Trigger + VoiceLeading/Melody +
    /// Approach) — für `reloadAllChunks()`. Die Output-Snapshots
    /// (`outputSnapshotByKey`/`bassOutputNotesByKey`) bleiben bewusst
    /// unangetastet (identisch zum bisherigen Verhalten: weder
    /// `chordOutputNotes` noch `bassOutputNotes` wurden beim Reload geleert,
    /// nur einzelne Einträge bei `unloadChunk`). Cloud-Registrierungen
    /// (`addCloud`/`removeCloud`) bleiben ebenfalls erhalten — `MelodyEngine.
    /// reset()` betrifft nur `lastNote`/`lastTickTime`, identisch zum
    /// bisherigen `melodyEngine.reset()`.
    mutating func resetAll() {
        triggerEngine.reset()
        voiceLeadingEngine.reset()
        lastApproachKey = nil
        portalTriggerEngine.reset()
        lastApproachPortalKey = nil
        cloudTriggerEngine.reset()
        lastApproachCloudKey = nil
        melodyEngine.reset()
        // Runde 062 / Gate 10: anders als bassOutputNotesByKey (reiner
        // "zuletzt gesendet"-Snapshot) IST soundingBassNotesByKey Trigger-
        // artiger Zustand — nach einem vollständigen Reset gibt es keinen
        // aktiven Portal-Trigger mehr, der eine Note als "aktiv, daher vom
        // Nachhol-Off ausgenommen" markieren könnte.
        soundingBassNotesByKey.removeAll()
    }

    /// Pro-Frame-Update für den Chord-Kanal. Mutiert nur eigenen Zustand,
    /// keine SceneKit-/AppSettings-Seiteneffekte — die zurückgegebenen
    /// Actions müssen von HarmonyScene angewendet werden.
    mutating func updateChord(_ input: ChordInteractionInput) -> [InteractionAction] {
        var actions: [InteractionAction] = []
        let byKey = Dictionary(uniqueKeysWithValues: input.candidates.map { ($0.key, $0) })

        let proximityCandidates = input.candidates
            .filter { $0.visible }
            .map { ProximityCandidate(key: $0.key, position: $0.position) }

        let result = ProximityTracker.evaluate(
            candidates:     proximityCandidates,
            cameraPos:      input.cameraPosition,
            activeKey:      triggerEngine.activeKey,
            entryRadius:    input.config.entryRadius,
            exitRadius:     input.config.exitRadius,
            approachRadius: input.config.approachRadius
        )

        // ── Annäherungs-Glow & nearestChord-Ereignis ──────────────────────
        let newApproachKey = result.approach?.key
        if newApproachKey != lastApproachKey {
            if let old = lastApproachKey {
                actions.append(.renderEffect(.resetApproachGlow(key: old)))
            }
            lastApproachKey = newApproachKey
        }
        if let ap = result.approach {
            actions.append(.renderEffect(.setApproachGlow(key: ap.key, proximity: ap.proximity)))
            let name = byKey[ap.key]?.chord.name ?? ""
            actions.append(.outputEvent(.nearestChord(name: name, proximity: ap.proximity)))
        } else {
            actions.append(.outputEvent(.nearestChord(name: "", proximity: 0)))
        }

        // ── Trigger-Übergang ───────────────────────────────────────────────
        // Solange nicht scharf (Spawn-Sicherheit): kein Trigger-Wechsel.
        let transition = triggerEngine.update(newKey: input.config.triggersArmed ? result.trigger : nil)
        guard transition.hasChange else { return actions }

        if let old = transition.deactivated {
            actions.append(.renderEffect(.setHighlighted(key: old, active: false)))
            // Symmetrisches NoteOff aus dem Output-Snapshot (Runde 038 /
            // V-00b, Fable-5-Review Finding A2, vervollständigt Runde 039 /
            // V-00b.1): `outputSnapshotByKey[old]` ist die alleinige Quelle
            // für BEIDE Werte — Name und Noten stammen aus demselben
            // Aktivierungszeitpunkt, nicht mehr getrennt (Name aus
            // `byKey[old]`, das bei Kandidatenverlust `nil` ist). Vorher
            // trug das Deactivation-Event nach Kandidatenverlust zwar die
            // richtigen Noten, aber `name: ""` — `OutputCoordinator` leert
            // `soundingChordName` nur bei `soundingChordName == chord.name`,
            // ein leerer Name ließ den HUD-Namen also stehen. Der frühere
            // Fallback auf `cand.chord.midiNotes` bleibt entfernt: sobald
            // einmal aktiviert ist der Snapshot ohnehin immer gesetzt (siehe
            // `.activated`-Zweig unten) — fehlt er, gibt es nichts zu beenden.
            if let snapshot = outputSnapshotByKey[old] {
                actions.append(.outputEvent(.chordDeactivated(ChordData(name: snapshot.name, midiNotes: snapshot.midiNotes))))
            }
        }
        if let new = transition.activated {
            actions.append(.renderEffect(.setHighlighted(key: new, active: true)))
            if let cand = byKey[new] {
                let voiced     = voiceLeadingEngine.apply(
                    newNotes: cand.chord.midiNotes,
                    enabled:  input.config.voiceLeadingEnabled
                )
                let voicedData = ChordData(name: cand.chord.name, midiNotes: voiced)
                actions.append(.renderEffect(.updateChordData(key: new, chord: voicedData)))

                let shift       = input.config.chordOctaveShift
                let outputNotes = voiced.map { max(0, min($0 + shift * 12, 127)) }
                outputSnapshotByKey[new] = ChordOutputSnapshot(name: voicedData.name, midiNotes: outputNotes)
                actions.append(.outputEvent(.chordActivated(ChordData(name: voicedData.name, midiNotes: outputNotes))))
            }
            // Render-only Nachbarschafts-Antwort — beeinflusst nie Trigger/Notes.
            actions.append(.renderEffect(.triggerHarmonicImpulse(key: new)))
        }

        return actions
    }

    /// Pro-Frame-Update für den Portal-/Bass-Kanal (Runde 027 / E-06b).
    /// Identische Struktur zu `updateChord(_:)`, aber ohne VoiceLeading und
    /// mit `bassHoldMode`-Gate beim Verlassen statt unbedingtem NoteOff.
    mutating func updatePortal(_ input: PortalInteractionInput) -> [InteractionAction] {
        var actions: [InteractionAction] = []

        // Nachhol-noteOff beim Ausschalten von bassHoldMode (Runde 062 /
        // Gate 10). Läuft VOR der Proximity-/Trigger-Auswertung dieses
        // Frames und unabhängig von `transition.hasChange`, damit ein reiner
        // Modus-Wechsel ohne Kandidatenänderung nicht übersprungen wird. Die
        // Note des zu Frame-Beginn aktiven Portals bleibt ausgenommen — sie
        // klänge im Trigger-Modus ebenfalls weiter, bis das Portal verlassen
        // wird. `soundingBassNotesByKey` ist die einzig korrekte Quelle
        // dafür, welche Noten wirklich klingen — `bassOutputNotesByKey` wäre
        // hier die Falle aus dem Handoff (Eintrag bleibt nach `noteOff`
        // stehen, würde Geister-Offs erzeugen).
        if previousBassHoldMode == true, !input.config.bassHoldMode {
            let keepKey = portalTriggerEngine.activeKey
            for key in soundingBassNotesByKey.keys.sorted() where key != keepKey {
                if let note = soundingBassNotesByKey.removeValue(forKey: key) {
                    actions.append(.outputEvent(.bassNoteOff(note)))
                }
            }
        }
        previousBassHoldMode = input.config.bassHoldMode

        let byKey = Dictionary(uniqueKeysWithValues: input.candidates.map { ($0.key, $0) })

        let proximityCandidates = input.candidates.map { ProximityCandidate(key: $0.key, position: $0.position) }

        let result = ProximityTracker.evaluate(
            candidates:     proximityCandidates,
            cameraPos:      input.cameraPosition,
            activeKey:      portalTriggerEngine.activeKey,
            entryRadius:    input.config.entryRadius,
            exitRadius:     input.config.exitRadius,
            approachRadius: input.config.approachRadius
        )

        // ── Annäherungs-Glow & nearestPortal-Ereignis ─────────────────────
        let newApproachKey = result.approach?.key
        if newApproachKey != lastApproachPortalKey {
            if let old = lastApproachPortalKey {
                actions.append(.renderEffect(.resetPortalApproachGlow(key: old)))
            }
            lastApproachPortalKey = newApproachKey
        }
        if let ap = result.approach {
            actions.append(.renderEffect(.setPortalApproachGlow(key: ap.key, proximity: ap.proximity)))
            let bassNote = byKey[ap.key]?.bassNote
            actions.append(.outputEvent(.nearestPortal(bassNote: bassNote, proximity: ap.proximity)))
        } else {
            actions.append(.outputEvent(.nearestPortal(bassNote: nil, proximity: 0)))
        }

        // ── Trigger-Übergang ───────────────────────────────────────────────
        let transition = portalTriggerEngine.update(newKey: input.config.triggersArmed ? result.trigger : nil)
        guard transition.hasChange else { return actions }

        if let old = transition.deactivated {
            actions.append(.renderEffect(.setPortalHighlighted(key: old, active: false)))
            if !input.config.bassHoldMode, let outputNote = bassOutputNotesByKey[old] {
                actions.append(.outputEvent(.bassNoteOff(outputNote)))
                soundingBassNotesByKey.removeValue(forKey: old)
            }
            // bassHoldMode == true: Note bleibt bewusst klingen, Eintrag in
            // soundingBassNotesByKey bleibt bestehen (Runde 062 / Gate 10).
        }
        if let new = transition.activated {
            actions.append(.renderEffect(.setPortalHighlighted(key: new, active: true)))
            if let note = byKey[new]?.bassNote {
                let shift  = input.config.bassOctaveShift
                let output = max(0, min(note + shift * 12, 127))
                bassOutputNotesByKey[new] = output
                soundingBassNotesByKey[new] = output
                actions.append(.outputEvent(.bassNoteOn(output)))
            }
        }

        return actions
    }

    /// Pro-Frame-Update für den Cloud-/Melody-Kanal (Runde 027 / E-06b).
    /// `melodyEngine` wird vollständig intern mutiert (`resetCloudIndex`/
    /// `stop`/`reset`/`tick`) — im Gegensatz zu `chordDataMap` (Chord-Kanal)
    /// lebt kein Teil des Melody-Zustands außerhalb der Runtime, daher sind
    /// dafür keine RenderEffects nötig.
    mutating func updateCloud(_ input: CloudInteractionInput) -> [InteractionAction] {
        var actions: [InteractionAction] = []

        let proximityCandidates = input.candidates.map { ProximityCandidate(key: $0.key, position: $0.position) }

        let result = ProximityTracker.evaluate(
            candidates:     proximityCandidates,
            cameraPos:      input.cameraPosition,
            activeKey:      cloudTriggerEngine.activeKey,
            entryRadius:    input.config.entryRadius,
            exitRadius:     input.config.exitRadius,
            approachRadius: input.config.approachRadius
        )

        // ── Annäherungs-Glow & nearestCloud-Ereignis ──────────────────────
        let newApproachKey = result.approach?.key
        if newApproachKey != lastApproachCloudKey {
            if let old = lastApproachCloudKey {
                actions.append(.renderEffect(.resetCloudApproachGlow(key: old)))
            }
            lastApproachCloudKey = newApproachKey
        }
        if let ap = result.approach {
            actions.append(.renderEffect(.setCloudApproachGlow(key: ap.key, proximity: ap.proximity)))
            actions.append(.outputEvent(.nearestCloud(name: "Melodie", proximity: ap.proximity)))
        } else {
            actions.append(.outputEvent(.nearestCloud(name: "", proximity: 0)))
        }

        // ── Trigger-Übergang ───────────────────────────────────────────────
        let transition = cloudTriggerEngine.update(newKey: input.config.triggersArmed ? result.trigger : nil)
        if transition.hasChange {
            if let old = transition.deactivated {
                actions.append(.renderEffect(.setCloudHighlighted(key: old, active: false)))
            }
            if let new = transition.activated {
                actions.append(.renderEffect(.setCloudHighlighted(key: new, active: true)))
                melodyEngine.resetCloudIndex(new)
            }
            // CH2: Off-Event vor dem Reset senden – stop() liefert lastNote einmalig.
            if let offNote = melodyEngine.stop() {
                actions.append(.outputEvent(.melodyNoteOff(offNote)))
            }
            melodyEngine.reset()
        }
        guard let cloudName = cloudTriggerEngine.activeKey else { return actions }

        // ── Proximity-Fade → MelodyEngine ─────────────────────────────────
        let proximity = result.triggerProximity ?? 0.0

        // Vorgängerton sichern, BEVOR tick() lastNote überschreibt.
        let prevNote = melodyEngine.lastNote

        if let tick = melodyEngine.tick(
            cloudKey:    cloudName,
            proximity:   proximity,
            tempo:       input.config.melodyTempo,
            velMax:      input.config.melodyVelMax,
            energyLevel: input.config.energyLevel,
            now:         input.config.now
        ) {
            // CH2: Off für den Vorgängerton vor On für den neuen Ton.
            if prevNote >= 0 {
                actions.append(.outputEvent(.melodyNoteOff(prevNote)))
            }
            actions.append(.outputEvent(.melodyNoteWithVelocity(note: tick.note, velocity: tick.velocity)))
        } else if proximity <= 0.08, let offNote = melodyEngine.stop() {
            // CH2: Off beim Verlassen der Cloud — letzter Ton beendet.
            actions.append(.outputEvent(.melodyNoteOff(offNote)))
        }

        return actions
    }
}
