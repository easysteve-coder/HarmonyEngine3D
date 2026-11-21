import Darwin

// MARK: – AudioCoreWavetable
//
// S-04a (`.agent_handoff/latest_codex.md`, Runde 049): Value-Speicher fuer
// eine einzelne, prozedural erzeugte Factory-Wellenform samt mehrerer
// bandlimitierter Mip-Stufen. Reiner Datentyp — keine Erzeugungslogik (siehe
// `AudioCoreWavetableBank`) und keine Oszillatorlogik (siehe
// `AudioCoreMorphOscillator`).
//
// Jede Mip-Stufe deckt einen begrenzten Harmonischenbereich ab
// (`maxHarmonic`). Ein Oszillator waehlt anhand von Grundfrequenz und
// Samplerate die am wenigsten bandlimitierte Mip-Stufe, deren hoechste
// enthaltene Harmonische noch unterhalb der Nyquist-Grenze
// (`sampleRate / 2`) liegt — so bleiben offensichtliche Aliasing-Artefakte
// bei hohen Tonhoehen aus.

public struct AudioCoreWavetableMipLevel: Sendable, Equatable {

    /// Hoechste in dieser Mip-Stufe enthaltene Harmonische (1 = nur
    /// Grundton). Dokumentiert die Nyquist-Grenze: eine Stimme mit
    /// Grundfrequenz `f` darf diese Stufe nur nutzen, wenn
    /// `maxHarmonic * f <= sampleRate / 2`.
    public let maxHarmonic: Int

    /// Tabellenwerte, Laenge == `AudioCoreWavetable.tableLength`, auf Peak
    /// 1.0 normiert.
    public let samples: [Float]

    public init(maxHarmonic: Int, samples: [Float]) {
        self.maxHarmonic = maxHarmonic
        self.samples = samples
    }
}

public struct AudioCoreWavetable: Sendable, Equatable {

    /// Stabile Kennung, z. B. `AudioCoreWavetableBank.PresetID.warmOdd`.
    public let id: String

    /// Feste Tabellenlaenge, power-of-two (Scope-Vorgabe S-04a).
    public let tableLength: Int

    /// Mip-Stufen, absteigend nach `maxHarmonic` sortiert (Index 0 = am
    /// wenigsten bandlimitiert / meiste Harmonische, letzter Index = am
    /// staerksten bandlimitiert).
    public let mipLevels: [AudioCoreWavetableMipLevel]

    public init(id: String, tableLength: Int, mipLevels: [AudioCoreWavetableMipLevel]) {
        self.id = id
        self.tableLength = tableLength
        self.mipLevels = mipLevels
    }

    // MARK: – Mip-Auswahl
    //
    // Waehlt die am wenigsten bandlimitierte Mip-Stufe, deren hoechste
    // Harmonische die Nyquist-Grenze noch nicht ueberschreitet. Rein
    // technische Aliasing-Vermeidung, keine musikalische Entscheidung.
    // Realtime-tauglich: linearer Scan ueber wenige Mip-Stufen, kein Alloc.

    public func mipLevelIndex(frequencyHz: Double, sampleRate: Double) -> Int {
        guard sampleRate > 0, !mipLevels.isEmpty else { return 0 }
        guard frequencyHz > 0 else { return 0 }
        let nyquist = sampleRate * 0.5
        for (index, level) in mipLevels.enumerated() {
            if Double(level.maxHarmonic) * frequencyHz <= nyquist {
                return index
            }
        }
        return mipLevels.count - 1
    }

    // MARK: – Sample-Lesevorgang
    //
    // Linear interpolierter Lesezugriff bei fraktionaler Phase. Phase wird
    // defensiv auf `[0, 1)` gewrappt, damit auch ein Aufrufer mit
    // ungenormter Phase keine NaN/Infinity oder Out-of-Bounds-Zugriffe
    // erzeugen kann. Kein Heap-Zugriff, kein Alloc — realtime-tauglich.
    //
    // S-04a-fix (Runde 050): eine nicht-endliche Phase (`.nan`/`.infinity`)
    // blieb nach `truncatingRemainder(dividingBy:)` selbst nicht-endlich
    // (IEEE 754: Rest von/mit NaN/Infinity ist NaN) und liess die
    // anschliessende `Double -> Int`-Konvertierung trappen. Eine
    // nicht-endliche Phase wird deshalb VOR dem Wrapping auf `0` abgebildet.

    public func sample(phase: Double, mipLevelIndex: Int) -> Float {
        guard mipLevels.indices.contains(mipLevelIndex) else { return 0 }
        let level = mipLevels[mipLevelIndex]
        guard tableLength > 0, level.samples.count == tableLength else { return 0 }

        let finitePhase = phase.isFinite ? phase : 0
        var wrapped = finitePhase.truncatingRemainder(dividingBy: 1.0)
        if wrapped < 0 { wrapped += 1.0 }

        let scaledPhase = wrapped * Double(tableLength)
        let indexFloor = Int(scaledPhase)
        let frac = Float(scaledPhase - Double(indexFloor))
        let i0 = indexFloor % tableLength
        let i1 = (indexFloor + 1) % tableLength

        let s0 = level.samples[i0]
        let s1 = level.samples[i1]
        return s0 + (s1 - s0) * frac
    }
}
