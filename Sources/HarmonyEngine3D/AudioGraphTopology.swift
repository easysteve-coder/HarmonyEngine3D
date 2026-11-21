import Foundation

// MARK: – AudioGraphSendTapPoint
//
// Beschreibt rein deklarativ, an welchem Punkt im Signalfluss eines Kanals
// ein späterer gemeinsamer Echo-/Space-Send (S-07b/S-09, S-08) abgreifen
// soll. Reine Beschreibung ohne AVAudioEngine-Abhängigkeit — S-07a
// verbindet noch keinen Kanal tatsächlich mit `AudioEngine.sharedEchoSendBus`/
// `sharedSpaceSendBus`; das legt erst der jeweilige Umsetzungsslice fest,
// gebunden an genau diesen Abgriffspunkt.
enum AudioGraphSendTapPoint: Equatable {
    /// Abgriff direkt hinter dem Kanal-Gain, vor jeglicher kanalspezifischer
    /// Dynamikverarbeitung.
    case postGain
    /// Abgriff VOR einem kanalspezifischen Dynamikprozessor (z. B. dem
    /// CH1-Kompressor `AudioEngine.compressorBass`), damit der gemeinsame
    /// Send diesen Prozessor nicht durchläuft.
    case preChannelDynamics
}

/// Geplanter Send-Abgriffspunkt für einen einzelnen Kanal (0 = Chord,
/// 1 = Bass, 2 = Melody, 3 = ChordTone — siehe `AudioOutput`-Kanalmodell).
struct AudioGraphChannelSendPlan: Equatable {
    let channel: Int
    let tapPoint: AudioGraphSendTapPoint
}

// MARK: – AudioGraphSendTopology
//
// Statischer Plan für die spätere Anbindung an `sharedEchoSendBus`/
// `sharedSpaceSendBus` (S-07b/S-09, S-08): legt fest, wo jeder Kanal seinen
// künftigen Echo-/Space-Send abgreifen soll. CH1 (Bass) ist nach Stephans
// Entscheidung (2026-07-30, Option A) `preChannelDynamics` — der bestehende
// CH1-Kompressor bleibt auf den CH1-Dry-Pfad beschränkt und darf den
// gemeinsamen Raumfeed nicht verändern. Alle anderen Kanäle besitzen keinen
// vergleichbaren Dynamikprozessor und greifen direkt hinter ihrem Gain ab.
enum AudioGraphSendTopology {
    static let plan: [AudioGraphChannelSendPlan] = [
        AudioGraphChannelSendPlan(channel: 0, tapPoint: .postGain),
        AudioGraphChannelSendPlan(channel: 1, tapPoint: .preChannelDynamics),
        AudioGraphChannelSendPlan(channel: 2, tapPoint: .postGain),
        AudioGraphChannelSendPlan(channel: 3, tapPoint: .postGain),
    ]

    static func tapPoint(forChannel channel: Int) -> AudioGraphSendTapPoint? {
        plan.first(where: { $0.channel == channel })?.tapPoint
    }
}
