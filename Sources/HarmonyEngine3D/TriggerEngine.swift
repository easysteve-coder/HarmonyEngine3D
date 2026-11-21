import Foundation

// MARK: – TriggerTransition
//
// Beschreibt den Zustandsübergang nach einem Trigger-Update.
// HarmonyScene reagiert auf den Übergang mit SceneKit-Calls und Callbacks –
// TriggerEngine selbst tut nichts außer den Übergang zu beschreiben.

struct TriggerTransition {
    let deactivated: String?   // Key des zuvor aktiven Objekts (nil = keines)
    let activated:   String?   // Key des neu aktiven Objekts   (nil = keines)

    var hasChange: Bool { deactivated != nil || activated != nil }

    static let unchanged = TriggerTransition(deactivated: nil, activated: nil)
}

// MARK: – TriggerEngine
//
// Einfacher Zustandsautomat für einen Trigger-Kanal (Akkord / Portal / Wolke).
// Verwaltet den aktiven Key und erkennt Übergänge.
//
// Kein AppSettings-Zugriff. Kein SceneKit. Kein MIDI.
// HarmonyScene besitzt je eine Instanz pro Kanal.

struct TriggerEngine {

    private(set) var activeKey: String? = nil

    // Liefert den Übergang zurück. Wenn der neue Key identisch ist, passiert nichts.
    mutating func update(newKey: String?) -> TriggerTransition {
        guard newKey != activeKey else { return .unchanged }
        let old   = activeKey
        activeKey = newKey
        return TriggerTransition(deactivated: old, activated: newKey)
    }

    // Zustand zurücksetzen ohne Übergang (z. B. bei Netzwerkwechsel / Chunk-Reload).
    // HarmonyScene ist verantwortlich, zugehörige Callbacks vorher zu feuern.
    mutating func reset() {
        activeKey = nil
    }
}
