import Darwin

// MARK: – AudioCoreWavetableBank
//
// S-04a (`.agent_handoff/latest_codex.md`, Runde 049): kleine, rein
// prozedurale Factory-Wellenform-Bank fuer Source A des Atmospheric-Synth-
// Fundaments (`SYNTH_ARCHITECTURE_PLAN.md`, Abschnitt 6.1/6.2). Beide
// Spektren werden per additiver Sinus-Synthese aus eigenen Amplitudenformeln
// erzeugt — keine Fremdassets, keine Samples, keine uebernommenen Presets
// oder Algorithmen. Deterministisch: reine Mathematik ohne Zufall, gleicher
// Aufruf erzeugt exakt dieselben Sample-Werte.
//
// Zwei musikalisch unterschiedliche Grundcharaktere (Scope B, S-04a-Handoff):
//
//   – `warmOdd`:    nur ungeradzahlige Harmonische, steile 1/n^1.5-Amplitude
//                   → weich, rund.
//   – `brightFull`: alle Harmonischen, 1/n-Amplitude (klassische
//                   Saegezahn-Reihe) → hell, obertonreich.
//
// Beide Spektren nutzen bei Phase 0 denselben Tabellenindex 0 (keine
// Zufallsphasen pro Harmonische) — das macht ein spaeteres lineares Morphing
// zwischen ihnen phasenkonsistent (siehe `AudioCoreMorphOscillator`).
//
// Jedes Spektrum bekommt dieselbe Folge absteigender Harmonischen-Obergrenzen
// als Mip-Stufen (`harmonicCaps`). Pro Stufe werden nur Harmonische bis zur
// jeweiligen Obergrenze aufsummiert und anschliessend auf Peak 1.0 normiert.

public enum AudioCoreWavetableBank {

    /// Feste Tabellenlaenge, power-of-two. 2048 Samples liegen deutlich
    /// oberhalb der fuer die hoechste Mip-Stufe (`64` Harmonische) noetigen
    /// Nyquist-Grenze der Tabelle selbst (2 × 64 = 128) und vermeiden
    /// dadurch Aliasing bereits bei der Tabellen-Erzeugung.
    public static let tableLength = 2048

    /// Absteigende Harmonischen-Obergrenzen, gemeinsam fuer beide Spektren.
    /// Index 0 = am wenigsten bandlimitiert (meiste Harmonische).
    public static let harmonicCaps: [Int] = [64, 32, 16, 8, 4, 2, 1]

    public enum PresetID {
        public static let warmOdd = "factory.warmOdd"
        public static let brightFull = "factory.brightFull"
    }

    /// Weiche, ungeradzahlige Harmonische-Reihe (Source-A-Kandidat).
    public static let warmOdd: AudioCoreWavetable = makeWavetable(
        id: PresetID.warmOdd,
        amplitude: { harmonic in
            harmonic % 2 == 1 ? 1.0 / pow(Double(harmonic), 1.5) : 0.0
        }
    )

    /// Helle, vollstaendige Harmonische-Reihe (Source-B-Kandidat, spaeter
    /// S-04b — hier bereits als zweites Factory-Spektrum fuer das Morphing
    /// von Source A verfuegbar).
    public static let brightFull: AudioCoreWavetable = makeWavetable(
        id: PresetID.brightFull,
        amplitude: { harmonic in 1.0 / Double(harmonic) }
    )

    /// Alle Factory-Spektren, stabile Reihenfolge.
    public static let factoryPresets: [AudioCoreWavetable] = [warmOdd, brightFull]

    // MARK: – Erzeugung
    //
    // Reine Erzeugungszeit-Berechnung (nicht im Realtime-Renderpfad) —
    // Allokation und Schleifen ueber `sin()` sind hier unproblematisch.

    private static func makeWavetable(id: String, amplitude: (Int) -> Double) -> AudioCoreWavetable {
        let levels = harmonicCaps.map { cap in
            makeMipLevel(maxHarmonic: cap, amplitude: amplitude)
        }
        return AudioCoreWavetable(id: id, tableLength: tableLength, mipLevels: levels)
    }

    private static func makeMipLevel(maxHarmonic: Int, amplitude: (Int) -> Double) -> AudioCoreWavetableMipLevel {
        var samples = [Float](repeating: 0, count: tableLength)
        let angleStep = 2.0 * Double.pi / Double(tableLength)

        for harmonic in 1...maxHarmonic {
            let amp = amplitude(harmonic)
            guard amp != 0 else { continue }
            for i in 0..<tableLength {
                samples[i] += Float(amp * sin(angleStep * Double(harmonic) * Double(i)))
            }
        }

        var peak: Float = 0
        for value in samples { peak = max(peak, abs(value)) }
        if peak > 0 {
            let scale = 1.0 / peak
            for i in 0..<tableLength { samples[i] *= scale }
        }

        return AudioCoreWavetableMipLevel(maxHarmonic: maxHarmonic, samples: samples)
    }
}
