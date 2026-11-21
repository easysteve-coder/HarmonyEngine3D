import Darwin

// MARK: – AudioCoreDeepSpaceFDNMatrix
//
// S-08b (`.agent_handoff/latest_codex.md`, Runde 059), Teil 2: reine,
// zustandslose Ordnung-8-Feedback-Matrix fuer `AudioCoreDeepSpaceFDNTail`
// (`SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 7.3: "orthogonale Feedback-
// Matrix"). Walsh-Hadamard-Matrix der Ordnung 8 (Sylvester-Konstruktion
// H_{2N} = [[H_N, H_N], [H_N, -H_N]], H_1 = [1]) — neben der Householder-
// Reflexion eine der beiden im Auftrag genannten, frei dokumentierten
// Standardkonstruktionen fuer verlustfreie FDN-Feedback-Matrizen (siehe
// z. B. Jean-Marc Jot, "An Analysis/Synthesis Approach to Real-Time
// Artificial Reverberation", bzw. Julius O. Smith, "Physical Audio Signal
// Processing", Abschnitt "Feedback Delay Networks", die Householder- und
// Hadamard-Matrizen als Standardkonstruktionen fuer energieerhaltende FDN-
// Matrizen nennen — frei dokumentierte Formelbeschreibungen, kein
// proprietaerer Code).
//
// Gewaehlt statt Householder: eine Ordnung-8-Hadamard-Matrix (8 ist eine
// Zweierpotenz) hat eine feste, rein additive +-1-Struktur ohne
// Reflexionsvektor-Wahl und ist per Konstruktion EXAKT orthogonal
// (H^T H = 8 * I) statt nur naeherungsweise wie eine beliebig gewaehlte
// Householder-Reflexion — einfacher zu begruenden und zu testen
// (`||Mx|| == ||x||` gilt fuer die normalisierte Matrix exakt, nicht nur
// im Erwartungswert).
//
// Realtime-Vertrag (korrigiert, S-08b-fix, Finding S-08b-01): der
// Renderpfad `AudioCoreDeepSpaceFDNTail.process(left:right:)` ruft
// ausschliesslich `apply(_:into:)` auf, das in einen vom Aufrufer bei
// `init`/`prepare(sampleRate:)` fest angelegten Puffer schreibt und selbst
// keine Allokation vornimmt. Die vorherige Behauptung, das Anlegen von
// Zwischen-Arrays in `process` sei "nicht anders" als die Zwischenwerte in
// `AudioCoreDeepSpaceEarlyReflections`/`AudioCoreDeepSpaceDiffuser", war
// falsch: beide Bestandstypen haben in `process` keine einzige
// Array-Konstruktion. Per SIL (`swiftc -O -wmo -emit-sil`) belegt: vor
// diesem Fix alloziierte allein `apply(_:) -> [Float]` ein Ausgabe-Array
// pro Aufruf, zusaetzlich zu den beiden allozierenden Zwischenwerten in
// `AudioCoreDeepSpaceFDNTail.process`. `apply(_:) -> [Float]` bleibt als
// bequeme, allozierende Form fuer Tests/Nicht-Renderpfad-Aufrufer
// bestehen, leitet aber intern auf `apply(_:into:)` weiter (eine
// Implementierung, keine Logikduplikation) und wird vom Renderpfad nicht
// mehr aufgerufen.

enum AudioCoreDeepSpaceFDNMatrix: Sendable {

    /// Ordnung der Matrix (Anzahl Delaylinien in `AudioCoreDeepSpaceFDNTail`).
    static let order = 8

    // Walsh-Hadamard-Matrix der Ordnung 8 (Sylvester-Konstruktion),
    // Eintraege ausschliesslich +-1. Fest und deterministisch.
    private static let hadamard8: [[Float]] = [
        [ 1,  1,  1,  1,  1,  1,  1,  1],
        [ 1, -1,  1, -1,  1, -1,  1, -1],
        [ 1,  1, -1, -1,  1,  1, -1, -1],
        [ 1, -1, -1,  1,  1, -1, -1,  1],
        [ 1,  1,  1,  1, -1, -1, -1, -1],
        [ 1, -1,  1, -1, -1,  1, -1,  1],
        [ 1,  1, -1, -1, -1, -1,  1,  1],
        [ 1, -1, -1,  1, -1,  1,  1, -1],
    ]

    // 1/sqrt(8) macht die Matrix orthonormal: ||Mx|| == ||x|| fuer jedes x
    // (Energieerhaltung, Kern des FDN-Stabilitaetsarguments).
    private static let normalization: Float = 1.0 / Float(order).squareRoot()

    /// Wendet die orthonormale 8x8-Hadamard-Matrix auf `input` an und
    /// schreibt das Ergebnis in den vom Aufrufer bereitgestellten `output`-
    /// Puffer. Alloziiert selbst nichts — das ist die vom Renderpfad
    /// genutzte Form. Erwartet genau `order` Elemente in beiden Puffern;
    /// bei abweichender Groesse bleibt `output` unveraendert (defensiver
    /// Fallback statt Trap — dieser Typ ist rein intern und wird nur von
    /// `AudioCoreDeepSpaceFDNTail` mit exakt `order` Elementen aufgerufen).
    static func apply(_ input: [Float], into output: inout [Float]) {
        guard input.count == order, output.count == order else { return }

        for row in 0..<order {
            var sum: Float = 0
            for col in 0..<order {
                let x = input[col]
                sum += hadamard8[row][col] * (x.isFinite ? x : 0)
            }
            let scaled = sum * normalization
            output[row] = scaled.isFinite ? scaled : 0
        }
    }

    /// Allozierende Bequemlichkeitsform fuer Tests/Nicht-Renderpfad-Aufrufer
    /// — legt genau ein Ausgabe-Array an und delegiert die eigentliche
    /// Berechnung an `apply(_:into:)` (eine Implementierung, keine
    /// Logikduplikation). Erwartet genau `order` Elemente; bei abweichender
    /// Groesse wird `input` unveraendert zurueckgegeben (defensiver
    /// Fallback statt Trap, wie bisher).
    static func apply(_ input: [Float]) -> [Float] {
        guard input.count == order else { return input }

        var output = [Float](repeating: 0, count: order)
        apply(input, into: &output)
        return output
    }
}
