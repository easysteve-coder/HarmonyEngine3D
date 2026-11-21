import HarmonyShared

// MARK: – ValidatedHarmonyMap
//
// Wrapper-Typ, der beweist, dass eine `HarmonyMap` `HarmonyMapValidator`
// ohne Errors durchlaufen hat (Warnings sind erlaubt). Der Initializer ist
// modul-intern — nur `HarmonyMapDocument.validatedSnapshot()` innerhalb von
// `HarmonyAuthoring` kann Instanzen erzeugen, damit ein "validierter
// Snapshot" nicht ohne echte Validation vorgetaeuscht werden kann.

public struct ValidatedHarmonyMap {
    public let map: HarmonyMap
    public let diagnostics: HarmonyMapValidator.Result

    init(map: HarmonyMap, diagnostics: HarmonyMapValidator.Result) {
        self.map = map
        self.diagnostics = diagnostics
    }
}
