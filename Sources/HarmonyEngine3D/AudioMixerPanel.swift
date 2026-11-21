import SwiftUI

// MARK: – AudioMixerPanel
//
// Live-Sounddesign-Konsole: 4 Kanal-Strips (Chord / Bass / Melody / Chord-Tone).
// Bindet direkt an AppSettings.shared.audio.* → auto-save (500 ms debounce).
// Live-Anwendung auf AudioEngine via Combine-Subscription in AppModel.
//
// Hotkey: M (keyCode 46) in FlightController.
// zIndex 50 – unter ControlsOverlay (100).
//
// Optik-Version 2: dunkles Hardware-Mischpult-Design.
//   – Charcoal-Gehäuse mit gestuftem Rahmen
//   – Farbige Kanalmarkierungen oben (3 px Akzentbalken)
//   – Physisch anmutende Knöbe (RadialGradient + vollständiger Track-Ring)
//   – Breiter Fader-Thumb mit Riffel-Detail
//   – Sektion-Labels weiß/off-white mit farbigem Akzentbalken links

// MARK: – Farb-Tokens

private enum MixerColor {
    // Gehäuse
    static let bodyTop    = Color(red: 0.13, green: 0.13, blue: 0.16)
    static let bodyMid    = Color(red: 0.09, green: 0.09, blue: 0.11)
    static let bodyBot    = Color(red: 0.07, green: 0.07, blue: 0.09)

    // Rahmen (oben hell, unten dunkel → Lichteinfall von oben)
    static let rimTop     = Color(white: 0.30)
    static let rimBot     = Color(white: 0.06)

    // Knob-Kappe
    static let knobCapHi  = Color(white: 0.26)
    static let knobCapLo  = Color(white: 0.14)
    static let knobRim    = Color(white: 0.35)

    // Text
    static let labelFg    = Color(white: 0.72)
    static let dimFg      = Color(white: 0.42)
    static let sectionFg  = Color(white: 0.58)

    // Trennlinie
    static let divider    = Color(white: 0.18)
    static let channelDiv = Color(white: 0.11)
}

// MARK: – AudioMixerPanel

struct AudioMixerPanel: View {

    let onClose: () -> Void
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            mixerHeader
            // Trennlinie unter Header: hell oben / dunkel unten (Rille-Effekt)
            ZStack {
                Rectangle().fill(MixerColor.rimBot).frame(height: 1)
                Rectangle().fill(MixerColor.rimTop).frame(height: 1)
                    .offset(y: -1)
            }
            .frame(height: 1)

            HStack(alignment: .top, spacing: 0) {
                ChannelStrip(
                    title: "CHORD",
                    color: Color(red: 0.68, green: 0.40, blue: 1.00),
                    config: $settings.audio.chord
                )
                channelDivider
                ChannelStrip(
                    title: "BASS",
                    color: Color(red: 0.20, green: 0.88, blue: 0.88),
                    config: $settings.audio.bass
                )
                channelDivider
                ChannelStrip(
                    title: "MELODY",
                    color: Color(red: 1.00, green: 0.58, blue: 0.18),
                    config: $settings.audio.melody
                )
                channelDivider
                ChannelStrip(
                    title: "CHORD TONE",
                    color: Color(red: 0.30, green: 0.90, blue: 0.45),
                    config: $settings.audio.chordTone
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [MixerColor.bodyTop, MixerColor.bodyMid, MixerColor.bodyBot],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    // Gestufter Rahmen: äußere helle Linie + innere dunkle Linie → Tiefenwirkung
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [MixerColor.rimTop, MixerColor.rimBot],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.5
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(MixerColor.rimBot, lineWidth: 1)
                        .padding(1.5)
                )
        )
        .frame(width: 1040)
        .shadow(color: .black.opacity(0.75), radius: 36, x: 0, y: -14)
    }

    private var channelDivider: some View {
        // Zwei-Linien-Rille zwischen Kanal-Strips
        ZStack {
            Rectangle().fill(MixerColor.rimBot).frame(width: 1)
            Rectangle().fill(MixerColor.rimTop).frame(width: 1)
                .offset(x: 1)
        }
        .frame(width: 2)
    }

    private var mixerHeader: some View {
        HStack(spacing: 10) {
            // Linke Akzentmarkierung (Studiogeräte haben oft ein farbiges Stripe-Detail)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.90, green: 0.60, blue: 0.15),
                                 Color(red: 0.70, green: 0.40, blue: 0.10)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 3, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 1.5))

            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12))
                .foregroundColor(MixerColor.dimFg)

            Text("mixer.title", bundle: .module)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(Color(red: 0.90, green: 0.75, blue: 0.45))   // Amber-Label
                .tracking(4)

            Spacer()

            Button(action: onClose) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(white: 0.22), Color(white: 0.12)],
                                center: .init(x: 0.40, y: 0.35),
                                startRadius: 0, endRadius: 14
                            )
                        )
                    Circle()
                        .stroke(Color(white: 0.32), lineWidth: 1)
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(MixerColor.dimFg)
                }
                .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.16, blue: 0.20),
                         Color(red: 0.11, green: 0.11, blue: 0.14)],
                startPoint: .top, endPoint: .bottom
            )
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 14, bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0, topTrailingRadius: 14
                )
            )
        )
    }
}

// MARK: – ChannelStrip

private struct ChannelStrip: View {

    let title:  String
    let color:  Color
    @Binding var config: ChannelFXConfig

    @State private var tap1Open = false
    @State private var tap2Open = false
    @State private var tap3Open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Farbiger Akzentbalken oben (LED-Markierung pro Kanal) ────────
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.55)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(height: 3)

            // ── Kanal-Header: Titel + Volume-Fader ───────────────────────────
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundColor(color)
                        .tracking(2.5)
                    Text("mixer.vol", bundle: .module)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(MixerColor.dimFg)
                        .tracking(2)
                }
                Spacer()
                VFaderView(
                    value: Binding(get: { config.channelVolume }, set: { config.channelVolume = $0 }),
                    color: color,
                    height: 72
                )
                Text(String(format: "%d%%", Int(config.channelVolume * 100)))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(color)
                    .frame(width: 36, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(
                // Leicht abgehobenes Inset-Panel für den Header-Bereich
                MixerColor.bodyBot
                    .overlay(
                        Rectangle()
                            .fill(MixerColor.rimTop.opacity(0.18))
                            .frame(height: 1),
                        alignment: .bottom
                    )
            )

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    panSection
                    sectionDivider
                    reverbSection
                    sectionDivider
                    delaySection
                    sectionDivider
                    adsrSection
                    sectionDivider
                    filterSection
                    sectionDivider
                    oscillatorSection
                    sectionDivider
                    unisonSection
                    Color.clear.frame(height: 14)
                }
            }
        }
        .frame(minWidth: 230, maxWidth: .infinity)
    }

    // MARK: – Pan

    private var panSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "mixer.section.pan", color: color)

            HStack(spacing: 10) {
                Text("L", bundle: .module)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(MixerColor.dimFg)
                KnobView(
                    value: Binding(get: { config.pan }, set: { config.pan = $0 }),
                    range: -1...1, color: color, size: 40
                )
                Text("R", bundle: .module)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(MixerColor.dimFg)
                Spacer()
                Text(panDisplayString)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(color)
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var panDisplayString: String {
        let p = config.pan
        if abs(p) < 0.02 { return "  C" }
        let pct = Int((abs(p) * 100).rounded())
        return p < 0 ? "L\(pct)" : "R\(pct)"
    }

    // MARK: – Reverb

    private var reverbSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "mixer.section.reverb", color: color)

            HStack {
                Text("mixer.reverb.preset", bundle: .module)
                    .panelLabel()
                Spacer()
                Picker("", selection: Binding(
                    get: { config.reverbPreset },
                    set: { config.reverbPreset = $0 }
                )) {
                    ForEach(reverbPresets, id: \.id) { p in
                        Text(p.name).tag(p.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)
                .tint(color)
                .foregroundStyle(color)
                .colorScheme(.dark)
            }

            HStack(spacing: 14) {
                KnobView(
                    value: Binding(get: { config.reverbMix }, set: { config.reverbMix = $0 }),
                    range: 0...1, color: color, size: 40
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text("mixer.reverb.mix", bundle: .module)
                        .panelLabel()
                    Text(String(format: "%d%%", Int(config.reverbMix * 100)))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(color)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: – Delay Taps

    private var delaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "mixer.section.delay", color: color)

            DelayTapRow(
                number: 1, color: color,
                isOpen: $tap1Open,
                time:     Binding(get: { config.delay1Time },     set: { config.delay1Time = $0 }),
                feedback: Binding(get: { config.delay1Feedback }, set: { config.delay1Feedback = $0 }),
                mix:      Binding(get: { config.delay1Mix },      set: { config.delay1Mix = $0 }),
                pan:      Binding(get: { config.delay1Pan },      set: { config.delay1Pan = $0 })
            )
            DelayTapRow(
                number: 2, color: color,
                isOpen: $tap2Open,
                time:     Binding(get: { config.delay2Time },     set: { config.delay2Time = $0 }),
                feedback: Binding(get: { config.delay2Feedback }, set: { config.delay2Feedback = $0 }),
                mix:      Binding(get: { config.delay2Mix },      set: { config.delay2Mix = $0 }),
                pan:      Binding(get: { config.delay2Pan },      set: { config.delay2Pan = $0 })
            )
            DelayTapRow(
                number: 3, color: color,
                isOpen: $tap3Open,
                time:     Binding(get: { config.delay3Time },     set: { config.delay3Time = $0 }),
                feedback: Binding(get: { config.delay3Feedback }, set: { config.delay3Feedback = $0 }),
                mix:      Binding(get: { config.delay3Mix },      set: { config.delay3Mix = $0 }),
                pan:      Binding(get: { config.delay3Pan },      set: { config.delay3Pan = $0 })
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: – ADSR

    private var adsrSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "mixer.section.adsr", color: color)

            PanelSlider(
                label: "mixer.adsr.attack",
                color: color,
                value: Binding(get: { config.attack }, set: { config.attack = $0 }),
                range: 0...1,
                format: .adsrQuadratic(maxMs: 2000)
            )
            PanelSlider(
                label: "mixer.adsr.decay",
                color: color,
                value: Binding(get: { config.decay }, set: { config.decay = $0 }),
                range: 0.001...2.0,
                format: .seconds
            )
            PanelSlider(
                label: "mixer.adsr.sustain",
                color: color,
                value: Binding(get: { config.sustain }, set: { config.sustain = $0 }),
                range: 0...1,
                format: .percent
            )
            PanelSlider(
                label: "mixer.adsr.release",
                color: color,
                value: Binding(get: { config.release }, set: { config.release = $0 }),
                range: 0.1...4.0,
                format: .seconds
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: – Filter

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "mixer.section.filter", color: color)

            PanelSlider(
                label: "mixer.filter.cutoff",
                color: color,
                value: Binding(get: { config.filterCutoff }, set: { config.filterCutoff = $0 }),
                range: 0...1,
                format: .frequency
            )

            HStack(spacing: 10) {
                Text("mixer.filter.resonance", bundle: .module)
                    .panelLabel()
                    .frame(width: 72, alignment: .leading)
                KnobView(
                    value: Binding(get: { config.filterResonance }, set: { config.filterResonance = $0 }),
                    range: 0...1, color: color, size: 34
                )
                Text(String(format: "%d%%", Int(config.filterResonance * 100)))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(color)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: – Oszillator

    private var oscillatorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "mixer.section.osc", color: color)

            HStack {
                Text("mixer.osc.waveform", bundle: .module)
                    .panelLabel()
                Spacer()
                Picker("", selection: Binding(get: { config.waveform }, set: { config.waveform = $0 })) {
                    Text("Sine",     bundle: .module).tag(Waveform.sine)
                    Text("Saw",      bundle: .module).tag(Waveform.saw)
                    Text("Square",   bundle: .module).tag(Waveform.square)
                    Text("Triangle", bundle: .module).tag(Waveform.triangle)
                }
                .pickerStyle(.menu)
                .frame(width: 110)
                .tint(color)
                .foregroundStyle(color)
                .colorScheme(.dark)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: – Unison
    //
    // Mehrere leicht verstimmte Stimmen pro NoteOn.
    // Voices: Anzahl der Unison-Stimmen (1 = kein Unison).
    // Detune: Verstimmung der äußersten Stimmen in Cent.
    // Spread: Stereo-Verteilung der Stimmen (0 = Mono, 1 = volle Breite).
    //
    // WICHTIG — Bass: Spread ≤ 0.35 empfohlen.

    private var unisonSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "mixer.section.unison", color: color)

            HStack {
                Text("mixer.unison.voices", bundle: .module)
                    .panelLabel()
                Spacer()
                Picker("", selection: Binding(
                    get: { config.unisonVoices },
                    set: { config.unisonVoices = $0 }
                )) {
                    Text("1", bundle: .module).tag(1)
                    Text("2", bundle: .module).tag(2)
                    Text("3", bundle: .module).tag(3)
                }
                .pickerStyle(.segmented)
                .frame(width: 90)
                .colorScheme(.dark)
            }

            PanelSlider(
                label: "mixer.unison.detune",
                color: color,
                value: Binding(get: { config.unisonDetune }, set: { config.unisonDetune = $0 }),
                range: 0...20,
                format: .adsr(scale: 1, unit: " ct"),
                note: "Cent"
            )

            PanelSlider(
                label: "mixer.unison.spread",
                color: color,
                value: Binding(get: { config.unisonSpread }, set: { config.unisonSpread = $0 }),
                range: 0...1,
                format: .percent
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var sectionDivider: some View {
        // Zwei-Linien-Rille: dunkle Linie + helle Gegenlinie → eingravierter Effekt
        ZStack {
            Rectangle().fill(MixerColor.divider).frame(height: 1)
            Rectangle().fill(MixerColor.rimTop.opacity(0.10)).frame(height: 1)
                .offset(y: 1)
        }
        .frame(height: 1)
    }

    private struct ReverbPreset: Identifiable {
        let id: Int; let name: String
    }
    private let reverbPresets: [ReverbPreset] = [
        .init(id: 0,  name: "Small Room"),   .init(id: 1,  name: "Medium Room"),
        .init(id: 2,  name: "Large Room"),   .init(id: 3,  name: "Medium Hall"),
        .init(id: 4,  name: "Large Hall"),   .init(id: 5,  name: "Plate"),
        .init(id: 6,  name: "Med Chamber"),  .init(id: 7,  name: "Lrg Chamber"),
        .init(id: 8,  name: "Cathedral"),    .init(id: 9,  name: "Large Room 2"),
        .init(id: 10, name: "Med Hall 2"),   .init(id: 11, name: "Med Hall 3"),
    ]
}

// MARK: – DelayTapRow (einzeln collapsible)

private struct DelayTapRow: View {

    let number: Int
    let color:  Color
    @Binding var isOpen:   Bool
    @Binding var time:     Float
    @Binding var feedback: Float
    @Binding var mix:      Float
    @Binding var pan:      Float

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            Button(action: {
                withAnimation(.easeInOut(duration: 0.16)) { isOpen.toggle() }
            }) {
                HStack(spacing: 8) {
                    // Kleine LED-artige Markierung
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isOpen ? color : color.opacity(0.30))
                        .frame(width: 3, height: 10)

                    Text("TAP \(number)", bundle: .module)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(isOpen ? color : color.opacity(0.60))
                        .tracking(1.5)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            // Track
                            RoundedRectangle(cornerRadius: 2)
                                .fill(MixerColor.dimFg.opacity(0.20))
                            // Fill
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color.opacity(0.55))
                                .frame(width: geo.size.width * CGFloat(mix))
                        }
                    }
                    .frame(height: 4)

                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(MixerColor.dimFg)
                        .frame(width: 14)
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 5)

            if isOpen {
                VStack(alignment: .leading, spacing: 8) {
                    PanelSlider(label: "mixer.delay.time",     color: color, value: $time,
                                range: 0.001...2.0, format: .seconds)
                    PanelSlider(label: "mixer.delay.feedback", color: color, value: $feedback,
                                range: 0...1, format: .percent)
                    PanelSlider(label: "mixer.delay.mix",      color: color, value: $mix,
                                range: 0...1, format: .percent)

                    HStack(spacing: 10) {
                        Text("mixer.delay.pan", bundle: .module)
                            .panelLabel()
                            .frame(width: 60, alignment: .leading)
                        KnobView(value: $pan, range: -1...1, color: color, size: 34)
                        Text(String(format: "%+.2f", pan))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(color)
                        Spacer()
                    }
                }
                .padding(.top, 4)
                .padding(.leading, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(isOpen ? color.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: – PanelSlider

private struct PanelSlider: View {

    enum Format {
        case percent
        case seconds
        case normalized
        case frequency                           // 0…1 normiert → 20…20.000 Hz (log.)
        case adsr(scale: Float, unit: String)    // normiert × scale → Anzeige + Einheit
        case adsrQuadratic(maxMs: Float)         // quadratische Kurve: value² × maxMs + 1 → ms
        // Anzeigewert entspricht dem in AudioEngine.synthParams(from:) berechneten Wert.
    }

    let label:   LocalizedStringKey
    let color:   Color
    @Binding var value: Float
    let range:   ClosedRange<Float>
    let format:  Format
    var note:    String? = nil

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(label, bundle: .module)
                    .panelLabel()
                if let note {
                    Text("(\(note))", bundle: .module)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(MixerColor.dimFg.opacity(0.70))
                }
                Spacer()
                Text(displayString)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(color)
                    .frame(width: 60, alignment: .trailing)
            }
            Slider(value: $value, in: range)
                .tint(color)
        }
    }

    private var displayString: String {
        switch format {
        case .percent:
            return "\(Int((value * 100).rounded()))%"
        case .seconds:
            return String(format: "%.3fs", value)
        case .normalized:
            return String(format: "%.2f", value)
        case .frequency:
            let hz = Int(20.0 * pow(1000.0, max(0, min(value, 1.0))))
            return hz >= 1000 ? String(format: "%.1fkHz", Float(hz) / 1000.0) : "\(hz) Hz"
        case let .adsr(scale, unit):
            let v = Int((value * scale).rounded())
            return "\(v)\(unit)"
        case let .adsrQuadratic(maxMs):
            let ms = Int((pow(value, 2.0) * maxMs + 1.0).rounded())
            return "\(ms) ms"
        }
    }
}

// MARK: – KnobView
//
// Hardware-Optik: RadialGradient-Kappe (Lichteinfall von oben-links) +
// vollständiger Track-Ring (Gesamtweg sichtbar) + farbiger Aktiv-Bogen.
// Indikator: kleiner Punkt auf der Kappe (rotiert).

private struct KnobView: View {

    @Binding var value: Float
    let range:  ClosedRange<Float>
    let color:  Color
    let size:   CGFloat

    @State private var dragOrigin: (Float, CGFloat)? = nil

    private var normalized: Float {
        guard range.upperBound > range.lowerBound else { return 0 }
        return (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        ZStack {
            // ── Physische Kappe (Gradient → Lichteinfall von oben-links) ────
            Circle()
                .fill(
                    RadialGradient(
                        colors: [MixerColor.knobCapHi, MixerColor.knobCapLo],
                        center: .init(x: 0.38, y: 0.32),
                        startRadius: 0,
                        endRadius: size * 0.65
                    )
                )

            // ── Kappen-Rand ──────────────────────────────────────────────────
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [MixerColor.knobRim, Color(white: 0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )

            // ── Vollständiger Track-Ring (zeigt Gesamtweg) ───────────────────
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(color.opacity(0.18), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(135))

            // ── Aktiver Bogen ────────────────────────────────────────────────
            Circle()
                .trim(from: 0, to: CGFloat(normalized) * 0.75)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(135))

            // ── Indikator-Punkt auf der Kappe ────────────────────────────────
            Circle()
                .fill(color)
                .frame(width: 4, height: 4)
                .shadow(color: color.opacity(0.80), radius: 2)
                .offset(y: -(size / 2 - 6))
                .rotationEffect(.degrees(Double(normalized) * 270 - 135))
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if dragOrigin == nil { dragOrigin = (value, g.location.y) }
                    guard let (startVal, startY) = dragOrigin else { return }
                    let span  = range.upperBound - range.lowerBound
                    let delta = Float(startY - g.location.y) / 120.0 * span
                    value = max(range.lowerBound, min(range.upperBound, startVal + delta))
                }
                .onEnded { _ in dragOrigin = nil }
        )
        .cursor(.resizeUpDown)
    }
}

// MARK: – VFaderView
//
// Hardware-Optik: dunkle Track-Nut mit Riffelmarkierungen, breiter Fader-Thumb
// mit hellem Griffstreifen und Abschattung links/rechts.

private struct VFaderView: View {

    @Binding var value: Float
    let color:  Color
    let height: CGFloat

    @State private var dragOrigin: (Float, CGFloat)? = nil

    var body: some View {
        GeometryReader { geo in
            let trackH = geo.size.height
            let fillH  = CGFloat(value) * trackH

            ZStack(alignment: .bottom) {
                // ── Track-Nut (leicht eingetieft: dunkle Füllung + heller Rand oben) ──
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(white: 0.06))
                    .frame(width: 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(white: 0.22), lineWidth: 1)
                            .frame(width: 10)
                    )
                    .frame(maxWidth: .infinity)

                // ── Füll-Bogen (aktiver Level) ───────────────────────────────
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.35))
                    .frame(width: 10, height: max(0, fillH))
                    .frame(maxWidth: .infinity)

                // ── Fader-Thumb ───────────────────────────────────────────────
                ZStack {
                    // Thumb-Körper
                    RoundedRectangle(cornerRadius: 5)
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.34), Color(white: 0.20)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                    // Griffstreifen (mittig, hell)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.90), color.opacity(0.55)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(width: 18, height: 2)
                    // Rand
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(
                            LinearGradient(
                                colors: [Color(white: 0.45), Color(white: 0.14)],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
                .frame(width: 24, height: 14)
                .offset(y: -fillH + 7)
                .frame(maxWidth: .infinity)
                .shadow(color: .black.opacity(0.55), radius: 3, x: 0, y: 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if dragOrigin == nil { dragOrigin = (value, g.location.y) }
                        guard let (startVal, startY) = dragOrigin else { return }
                        let delta = Float(startY - g.location.y) / Float(trackH)
                        value = max(0, min(1, startVal + delta))
                    }
                    .onEnded { _ in dragOrigin = nil }
            )
            .cursor(.resizeUpDown)
        }
        .frame(width: 28, height: height)
    }
}

// MARK: – SectionLabel
//
// Hardware-Panel-Stil: kleiner farbiger Akzentbalken links + off-white Text.

private struct SectionLabel: View {
    let text:  LocalizedStringKey
    let color: Color
    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color.opacity(0.75))
                .frame(width: 2, height: 9)
            Text(text, bundle: .module)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(MixerColor.sectionFg)
                .tracking(3)
        }
    }
}

// MARK: – Text-Modifier (file-private)

fileprivate extension Text {
    func panelLabel() -> some View {
        self.font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundColor(MixerColor.labelFg)
    }
}

// MARK: – Cursor-Modifier (macOS)

fileprivate extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}
