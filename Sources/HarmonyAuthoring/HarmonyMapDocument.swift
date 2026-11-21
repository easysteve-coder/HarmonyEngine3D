import Foundation
import HarmonyShared

// MARK: – DocumentOrigin
//
// Eindeutiger Dokumentursprung/-status (K-02): unterscheidet ein neues,
// ungespeichertes Dokument von einem normalen File-URL-Dokument und einem
// read-only Bundle-Template. `HarmonyMapDocumentStore` ist die einzige
// Stelle, die `origin` nach einem erfolgreichen Save/Save As aktualisiert
// (ueber `HarmonyMapDocument.markSaved(at:)`, modul-intern).

public enum DocumentOrigin: Equatable {
    case unsaved
    case file(URL)
    case readOnlyTemplate(name: String)
}

// MARK: – HarmonyMapDocument
//
// Editierbare Dokumentbasis fuer das Construction Kit (K-01 / M2).
// Haelt einen `HarmonyMap`-Draft als kanonischen musikalischen Zustand — es
// entsteht keine parallele Node-/Edge-/Layer-Semantik. Mutationen laufen
// ausschliesslich ueber `HarmonyMapCommand`, sind undo-/redo-faehig und
// aktualisieren Dirty-State, Revision und Validator-Diagnosen konsistent.
//
// Der Draft darf voruebergehend Validator-Errors enthalten (siehe
// `ARCHITECTURE_REVIEW_2026-07-26.md`) — nur `validatedSnapshot()` gated den
// Export zur Runtime auf Fehlerfreiheit; Warnings blockieren nicht.
//
// Kein SceneKit, kein AppSettings, kein UI, keine Datei-I/O.

public struct HarmonyMapDocument {

    public enum UndoRedoError: Error, Equatable, CustomStringConvertible {
        case nothingToUndo
        case nothingToRedo

        public var description: String {
            switch self {
            case .nothingToUndo: return "HarmonyMapDocument: Undo-Stack ist leer"
            case .nothingToRedo: return "HarmonyMapDocument: Redo-Stack ist leer"
            }
        }
    }

    public private(set) var origin: DocumentOrigin
    public private(set) var draft: HarmonyMap
    public private(set) var isDirty: Bool
    /// Monotoner Zaehler fuer jede erfolgreiche Draft-Aenderung (Command, Undo, Redo).
    public private(set) var revision: Int
    public private(set) var diagnostics: HarmonyMapValidator.Result

    private var undoStack: [HarmonyMap] = []
    private var redoStack: [HarmonyMap] = []

    public init(map: HarmonyMap, origin: DocumentOrigin = .unsaved) {
        self.draft = map
        self.origin = origin
        self.isDirty = false
        self.revision = 0
        self.diagnostics = HarmonyMapValidator.validate(map)
    }

    /// Bequemer Zugriff auf die Datei-URL, sofern `origin == .file(_)`. `nil`
    /// fuer ungespeicherte Dokumente und read-only Templates.
    public var documentURL: URL? {
        if case .file(let url) = origin { return url }
        return nil
    }

    /// `true` fuer aus dem Bundle geladene Templates — `save()` verweigert
    /// hier das Schreiben, `saveAs(_:to:)` erzeugt daraus eine normale Datei.
    public var isReadOnly: Bool {
        if case .readOnlyTemplate = origin { return true }
        return false
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Wird ausschliesslich von `HarmonyMapDocumentStore` nach erfolgreichem
    /// Schreiben aufgerufen (modul-intern, damit kein Aufrufer ausserhalb von
    /// `HarmonyAuthoring` den Dokumentstatus ohne echtes Schreiben faelschen
    /// kann). Setzt `origin` auf die Ziel-URL und loescht den Dirty-State —
    /// `revision` bleibt unveraendert, Speichern ist keine Draft-Mutation.
    mutating func markSaved(at url: URL) {
        origin = .file(url)
        isDirty = false
    }

    // MARK: – Commands

    /// Fuehrt `command` auf dem aktuellen Draft aus. Bei Erfolg: neuer Draft
    /// uebernommen, Redo-Stack geleert, Dirty-State gesetzt, Revision erhoeht,
    /// Diagnosen aktualisiert. Bei Fehlschlag (Command wirft): Draft, Dirty-
    /// State, Revision und beide Stacks bleiben unveraendert, der Fehler wird
    /// weitergereicht.
    public mutating func perform(_ command: HarmonyMapCommand) throws {
        let newDraft = try command.apply(to: draft)
        undoStack.append(draft)
        redoStack.removeAll()
        draft = newDraft
        isDirty = true
        revision += 1
        diagnostics = HarmonyMapValidator.validate(draft)
    }

    // MARK: – Undo / Redo

    /// Stellt den vorherigen Draft wieder her. Wirft `.nothingToUndo` bei
    /// leerem Stack, statt still no-op zu bleiben.
    public mutating func undo() throws {
        guard let previous = undoStack.popLast() else { throw UndoRedoError.nothingToUndo }
        redoStack.append(draft)
        draft = previous
        isDirty = true
        revision += 1
        diagnostics = HarmonyMapValidator.validate(draft)
    }

    /// Stellt den zuletzt rueckgaengig gemachten Draft wieder her. Wirft
    /// `.nothingToRedo` bei leerem Stack, statt still no-op zu bleiben.
    public mutating func redo() throws {
        guard let next = redoStack.popLast() else { throw UndoRedoError.nothingToRedo }
        undoStack.append(draft)
        draft = next
        isDirty = true
        revision += 1
        diagnostics = HarmonyMapValidator.validate(draft)
    }

    // MARK: – Validierter Snapshot

    /// Liefert einen validierten Snapshot fuer die Runtime, oder `nil`, wenn
    /// der aktuelle Draft Validator-Errors enthaelt. Warnings blockieren den
    /// Export nicht.
    public func validatedSnapshot() -> ValidatedHarmonyMap? {
        guard diagnostics.isAcceptable else { return nil }
        return ValidatedHarmonyMap(map: draft, diagnostics: diagnostics)
    }
}
