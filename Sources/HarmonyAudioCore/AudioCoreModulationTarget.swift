// MARK: – AudioCoreModulationTarget
//
// S-05b (`.agent_handoff/latest_codex.md`, Runde 053), Scope A: feste,
// interne Core-Zielmenge fuer Modulationsrouten. Bewusst als geschlossenes
// Enum statt freier Strings modelliert (Handoff-Vorgabe) — die Menge ist
// klein und vorausschauend gewaehlt (Morph/Textur/Filter/Mix/Huellentiefe/
// Space-Send-Platzhalter), erraet aber nicht die ganze Spaeter-Architektur.
// Welches reale Voice-/Graph-Feld ein Ziel am Ende antreibt, entscheidet ein
// spaeterer Verdrahtungsslice (Nicht-Scope S-05b).

public enum AudioCoreModulationTarget: Sendable, Equatable, Hashable, CaseIterable {
    /// Morph-Position zwischen zwei Wavetables (Source A/B).
    case morphPosition
    /// Ausgangspegel der gefaerbten Textur-Quelle (Source C).
    case textureLevel
    /// Tiefpass-Cutoff.
    case filterCutoff
    /// Mix-/Blend-Anteil im `AudioCoreMixer`.
    case mixDepth
    /// Zusaetzliche Modulationstiefe der Amp-Huelle.
    case ampEnvelopeDepth
    /// Zusaetzliche Modulationstiefe der Mod-Huelle.
    case modEnvelopeDepth
    /// Platzhalter fuer einen kuenftigen Echo-/Hall-Send (Space Engine, A3).
    case spaceSend
}
