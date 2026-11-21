import Foundation
import Accelerate

// MARK: – OfflineSynthMetrics
//
// S-01 (`.agent_handoff/latest_codex.md`, Runde 045), Scope B: robuste
// Metriken aus einem `OfflineRenderResult`. Reiner Testhelfer — kein
// Produktcode, keine Fremddependency (Accelerate ist ein System-Framework).

struct OfflineSynthMetrics {
    let sampleRate: Double
    let frameCount: Int
    let channelCount: Int

    let peakAbsolute: Float
    let rms: Float
    let dcOffset: Float
    let nonFiniteSampleCount: Int
    let totalEnergy: Float
    let tailEnergy: Float
    let tailWindowFrames: Int

    /// Erster/letzter Frame-Index (0-basiert), an dem |Sample| > `silenceThreshold`
    /// in mindestens einem Kanal liegt. `nil`, wenn das gesamte Signal unterhalb
    /// der Schwelle bleibt (vollstaendige Stille).
    let firstAboveSilenceFrame: Int?
    let lastAboveSilenceFrame: Int?
    let silenceThreshold: Float

    /// Pearson-Korrelationskoeffizient zwischen L und R, Bereich −1…1.
    /// Dokumentierte Ersatzmetrik: `nil`, wenn ein Kanal (nahezu) keine
    /// Varianz hat (z. B. vollstaendige Stille) — Korrelation ist dort
    /// mathematisch undefiniert (Division durch ~0), nicht 0 oder NaN.
    let stereoCorrelation: Float?

    /// Spektraler Schwerpunkt (Hz) ueber ein Hann-gefenstertes Segment ab
    /// `firstAboveSilenceFrame`, via `vDSP.DiscreteFourierTransform` auf dem
    /// linken Kanal. `nil` bei zu kurzem oder zu leisem Restsignal.
    let spectralCentroidHz: Float?
}

enum OfflineSynthMetricsCalculator {

    static func compute(_ result: OfflineRenderResult,
                         silenceThreshold: Float = 1e-4,
                         tailWindowFrames: Int) -> OfflineSynthMetrics {
        let frameCount = result.frameCount
        guard frameCount > 0 else {
            return OfflineSynthMetrics(sampleRate: result.sampleRate, frameCount: 0, channelCount: 2,
                                       peakAbsolute: 0, rms: 0, dcOffset: 0, nonFiniteSampleCount: 0,
                                       totalEnergy: 0, tailEnergy: 0, tailWindowFrames: 0,
                                       firstAboveSilenceFrame: nil, lastAboveSilenceFrame: nil,
                                       silenceThreshold: silenceThreshold, stereoCorrelation: nil,
                                       spectralCentroidHz: nil)
        }

        var nonFinite = 0
        for sample in result.left  where !sample.isFinite { nonFinite += 1 }
        for sample in result.right where !sample.isFinite { nonFinite += 1 }

        // Nicht-finite Samples wuerden vDSP-Reduktionen (max/rms/mean) global
        // verfaelschen (NaN propagiert durch die gesamte Reduktion) — deshalb
        // laufen die folgenden Metriken ueber finite Ersatzwerte (0.0), waehrend
        // `nonFiniteSampleCount` das reale Ausmass separat dokumentiert.
        let safeLeft  = nonFinite > 0 ? result.left.map  { $0.isFinite ? $0 : 0 } : result.left
        let safeRight = nonFinite > 0 ? result.right.map { $0.isFinite ? $0 : 0 } : result.right

        let peak = max(vDSPMaxAbs(safeLeft), vDSPMaxAbs(safeRight))
        let dc = (vDSPMean(safeLeft) + vDSPMean(safeRight)) / 2
        let rms = sqrtf((vDSPMeanSquare(safeLeft) + vDSPMeanSquare(safeRight)) / 2)
        let totalEnergy = vDSPSumSquares(safeLeft) + vDSPSumSquares(safeRight)

        let tailWindow = min(tailWindowFrames, frameCount)
        let tailEnergy: Float
        if tailWindow > 0 {
            let tailStart = frameCount - tailWindow
            tailEnergy = vDSPSumSquares(Array(safeLeft[tailStart...])) + vDSPSumSquares(Array(safeRight[tailStart...]))
        } else {
            tailEnergy = 0
        }

        var firstAbove: Int?
        var lastAbove: Int?
        for i in 0..<frameCount where abs(safeLeft[i]) > silenceThreshold || abs(safeRight[i]) > silenceThreshold {
            if firstAbove == nil { firstAbove = i }
            lastAbove = i
        }

        let stereoCorrelation = pearsonCorrelation(safeLeft, safeRight)

        let spectralCentroid = firstAbove.flatMap {
            spectralCentroidHz(of: safeLeft, startingAt: $0, sampleRate: result.sampleRate)
        }

        return OfflineSynthMetrics(
            sampleRate: result.sampleRate,
            frameCount: frameCount,
            channelCount: 2,
            peakAbsolute: peak,
            rms: rms,
            dcOffset: dc,
            nonFiniteSampleCount: nonFinite,
            totalEnergy: totalEnergy,
            tailEnergy: tailEnergy,
            tailWindowFrames: tailWindow,
            firstAboveSilenceFrame: firstAbove,
            lastAboveSilenceFrame: lastAbove,
            silenceThreshold: silenceThreshold,
            stereoCorrelation: stereoCorrelation,
            spectralCentroidHz: spectralCentroid
        )
    }

    // MARK: – vDSP-Reduktionen

    private static func vDSPMaxAbs(_ buffer: [Float]) -> Float {
        guard !buffer.isEmpty else { return 0 }
        var result: Float = 0
        vDSP_maxmgv(buffer, 1, &result, vDSP_Length(buffer.count))
        return result
    }

    private static func vDSPMean(_ buffer: [Float]) -> Float {
        guard !buffer.isEmpty else { return 0 }
        var result: Float = 0
        vDSP_meanv(buffer, 1, &result, vDSP_Length(buffer.count))
        return result
    }

    private static func vDSPMeanSquare(_ buffer: [Float]) -> Float {
        guard !buffer.isEmpty else { return 0 }
        var result: Float = 0
        vDSP_measqv(buffer, 1, &result, vDSP_Length(buffer.count))
        return result
    }

    private static func vDSPSumSquares(_ buffer: [Float]) -> Float {
        guard !buffer.isEmpty else { return 0 }
        var result: Float = 0
        vDSP_svesq(buffer, 1, &result, vDSP_Length(buffer.count))
        return result
    }

    private static func pearsonCorrelation(_ a: [Float], _ b: [Float]) -> Float? {
        guard a.count == b.count, a.count > 1 else { return nil }
        let meanA = vDSPMean(a)
        let meanB = vDSPMean(b)
        var covariance: Float = 0
        var varianceA: Float = 0
        var varianceB: Float = 0
        for i in 0..<a.count {
            let da = a[i] - meanA
            let db = b[i] - meanB
            covariance += da * db
            varianceA += da * da
            varianceB += db * db
        }
        // Ersatzmetrik-Fall: (nahezu) keine Varianz in einem Kanal (Stille,
        // reiner DC-Trend oder identisch-konstantes Signal) → Korrelation ist
        // mathematisch undefiniert. `nil` statt NaN/0, siehe Feld-Dokumentation oben.
        guard varianceA > 1e-12, varianceB > 1e-12 else { return nil }
        return covariance / sqrtf(varianceA * varianceB)
    }

    /// Spektraler Schwerpunkt (Hz) ueber ein Hann-gefenstertes Segment,
    /// beginnend bei `startingAt`. Fensterlaenge: groesste Zweierpotenz
    /// ≤ verfuegbarer Restlaenge, begrenzt auf 256…4096 Samples. Liefert
    /// `nil`, wenn weniger als 256 Samples verfuegbar sind.
    private static func spectralCentroidHz(of samples: [Float], startingAt start: Int, sampleRate: Double) -> Float? {
        let available = samples.count - start
        guard available >= 256 else { return nil }

        var windowLength = 4096
        while windowLength > available { windowLength /= 2 }
        guard windowLength >= 256 else { return nil }

        guard let dft = try? vDSP.DiscreteFourierTransform(count: windowLength,
                                                            direction: .forward,
                                                            transformType: .complexComplex,
                                                            ofType: Float.self) else { return nil }

        var segment = Array(samples[start..<(start + windowLength)])
        var window = [Float](repeating: 0, count: windowLength)
        vDSP_hann_window(&window, vDSP_Length(windowLength), Int32(vDSP_HANN_NORM))
        for i in 0..<windowLength { segment[i] *= window[i] }

        let zeroImaginary = [Float](repeating: 0, count: windowLength)
        let (real, imag) = dft.transform(real: segment, imaginary: zeroImaginary)

        // Nur die untere Haelfte der Bins (0…Nyquist) traegt eindeutige
        // Frequenzinformation eines reellen Signals; die obere Haelfte sind
        // Spiegelfrequenzen (negative Frequenzen der Complex-Complex-DFT).
        let binCount = windowLength / 2
        let binWidth = Float(sampleRate) / Float(windowLength)

        var weightedSum: Float = 0
        var magnitudeSum: Float = 0
        for bin in 0..<binCount {
            let magnitude = sqrtf(real[bin] * real[bin] + imag[bin] * imag[bin])
            weightedSum += Float(bin) * binWidth * magnitude
            magnitudeSum += magnitude
        }
        guard magnitudeSum > 1e-6 else { return nil }
        return weightedSum / magnitudeSum
    }
}
