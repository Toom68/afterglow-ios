import SwiftUI

/// One-tap light sessions: every setting on one page, and a Go button that starts at once.
struct LightView: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var session: QuickSession?
    @State private var showingScreening = false
    /// Go was pressed before the safety check; start once its sheet has closed.
    @State private var goAfterScreening = false

    private static let torchHardwarePresent = SystemTorchDevice().hasTorch
    private var lightSelectable: Bool { LightFeature.isAvailable && Self.torchHardwarePresent }
    private var program: LightProgram {
        settings.chosenLightProgram ?? LightProgramCatalog.recommended(for: PresetCatalog.quickLight.intent)
    }
    private var isCustom: Bool { settings.lightProgramChoice == LightProgramCatalog.customID }
    private var isFixedRate: Bool { settings.customStartHz == settings.customEndHz }

    private struct QuickSession: Identifiable {
        let id = UUID()
        let configuration: SessionConfiguration
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "Light")
                        Text("Close your eyes.\nPress go.").agFont(36, weight: .regular, design: .serif)
                    }
                    goButton
                    if !lightSelectable {
                        Text(LightFeature.isAvailable ? "This device has no usable flashlight (the Simulator never does). Go starts the sound only." : LightFeature.statusExplanation)
                            .agFont(12).foregroundStyle(AfterglowTheme.gold).lineSpacing(3)
                    }
                    patternCard
                    brightnessCard
                    timingCard
                    soundCard
                    Text("Flashing light can trigger seizures, including in people with no known history. Stop immediately if you feel unwell.")
                        .agFont(11).foregroundStyle(AfterglowTheme.muted).lineSpacing(3)
                }
                .padding(24)
            }
            .afterglowScreen()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingScreening, onDismiss: {
                if goAfterScreening { goAfterScreening = false; go() }
            }) {
                LightScreeningView {
                    settings.lightScreenedAt = Date()
                    settings.lightPreferred = true
                    goAfterScreening = true
                }
            }
            .fullScreenCover(item: $session) { session in
                SessionFlowView(quickStart: session.configuration)
            }
        }
    }

    // MARK: - Go

    private var goButton: some View {
        Button(action: requestGo) {
            VStack(spacing: 6) {
                Text("GO").agFont(34, weight: .semibold)
                Text("\(program.name) · \(program.rangeDescription) · \(settings.quickMinutes) min")
                    .agFont(11, design: .monospaced)
            }
            .foregroundStyle(AfterglowTheme.background)
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(AfterglowTheme.gold, in: RoundedRectangle(cornerRadius: 28))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Go. Start light session")
    }

    private func requestGo() {
        if lightSelectable && !settings.lightScreeningIsCurrent {
            showingScreening = true
        } else {
            go()
        }
    }

    private func go() {
        var configuration = settings.quickLightConfiguration()
        configuration.useLight = configuration.useLight && lightSelectable
        session = QuickSession(configuration: configuration)
    }

    // MARK: - Settings

    private var patternCard: some View {
        AfterglowCard {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("Pattern", symbol: "waveform.path")
                Picker("Pattern", selection: $settings.lightProgramChoice) {
                    Text("Explore · \(LightProgramCatalog.explore.rangeDescription) (default)").tag(SettingsStore.automaticProgram)
                    ForEach(LightProgramCatalog.all) { program in
                        Text("\(program.name) · \(program.rangeDescription)").tag(program.id)
                    }
                    Text("Custom").tag(LightProgramCatalog.customID)
                }
                .pickerStyle(.menu).tint(AfterglowTheme.gold)
                Text(program.summary).agFont(12).foregroundStyle(AfterglowTheme.muted).lineSpacing(3)
                if isCustom {
                    Toggle("Glide between two rates", isOn: Binding(
                        get: { !isFixedRate },
                        set: { glide in settings.customEndHz = glide ? max(1, settings.customStartHz - 4) : settings.customStartHz }
                    ))
                    .agFont(13).tint(AfterglowTheme.gold)
                    if isFixedRate {
                        valueSlider("Flash rate", value: Binding(
                            get: { settings.customStartHz },
                            set: { settings.customStartHz = $0; settings.customEndHz = $0 }
                        ), in: LightBounds.standard.frequencyRange, step: 0.5, display: "\(LightProgram.format(settings.customStartHz)) Hz")
                    } else {
                        valueSlider("Start rate", value: $settings.customStartHz, in: LightBounds.standard.frequencyRange, step: 0.5, display: "\(LightProgram.format(settings.customStartHz)) Hz")
                        valueSlider("End rate", value: $settings.customEndHz, in: LightBounds.standard.frequencyRange, step: 0.5, display: "\(LightProgram.format(settings.customEndHz)) Hz")
                    }
                    valueSlider("Flash length", value: $settings.customDuty, in: LightBounds.standard.dutyRange, step: 0.05, display: "\(Int((settings.customDuty * 100).rounded()))% on")
                    if max(settings.customStartHz, settings.customEndHz) > 15 {
                        Text("Above 15 Hz is the range most likely to trigger photosensitive seizures. Use it only if you are sure you are not photosensitive.")
                            .agFont(11).foregroundStyle(AfterglowTheme.gold).lineSpacing(3)
                    }
                    Text("Interval between flashes: \(String(format: "%.0f", 1000 / settings.customStartHz)) ms\(isFixedRate ? "" : " → \(String(format: "%.0f", 1000 / settings.customEndHz)) ms").")
                        .agFont(11, design: .monospaced).foregroundStyle(AfterglowTheme.muted)
                }
            }
        }
    }

    private var brightnessCard: some View {
        AfterglowCard {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("Brightness", symbol: "sun.max")
                valueSlider("Torch", value: $settings.lightBrightness, in: SettingsStore.brightnessRange, display: "\(Int((settings.lightBrightness * 100).rounded()))%")
            }
        }
    }

    private var timingCard: some View {
        AfterglowCard {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("Timing", symbol: "timer")
                valueSlider("Length", value: Binding(
                    get: { Double(settings.quickMinutes) },
                    set: { settings.quickMinutes = Int($0.rounded()) }
                ), in: 1...60, step: 1, display: "\(settings.quickMinutes) min")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dark before the first flash").agFont(12, weight: .medium).foregroundStyle(AfterglowTheme.muted)
                    Picker("Dark before the first flash", selection: $settings.quickLeadIn) {
                        ForEach(SettingsStore.quickLeadInOptions, id: \.self) { seconds in
                            Text(seconds == 0 ? "None" : "\(Int(seconds)) s").tag(seconds)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Toggle("Fade in and out", isOn: $settings.quickFades)
                    .agFont(13).tint(AfterglowTheme.gold)
            }
        }
    }

    private var soundCard: some View {
        AfterglowCard {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("Sound", symbol: "headphones")
                Picker("Sound", selection: $settings.quickSound) {
                    ForEach(Soundscape.allCases) { sound in
                        Text(sound.title).tag(sound.rawValue)
                    }
                    Text("Silent").tag(SettingsStore.QuickSound.silent)
                    Text("My own music").tag(SettingsStore.QuickSound.ownMusic)
                }
                .pickerStyle(.menu).tint(AfterglowTheme.gold)
                if let soundscape = Soundscape(rawValue: settings.quickSound) {
                    Text(soundscape.summary).agFont(12).foregroundStyle(AfterglowTheme.muted)
                    valueSlider("Volume", value: $settings.volume, in: 0...1, display: "\(Int((settings.volume * 100).rounded()))%")
                } else if settings.quickSound == SettingsStore.QuickSound.ownMusic {
                    Text("Start your music in Spotify, Apple Music or any other app, then press Go. It keeps playing under the light.")
                        .agFont(12).foregroundStyle(AfterglowTheme.muted).lineSpacing(3)
                } else {
                    Text("Light only, no sound.").agFont(12).foregroundStyle(AfterglowTheme.muted)
                }
            }
        }
    }

    private func cardTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).agFont(14, weight: .medium)
    }

    private func valueSlider<Value: BinaryFloatingPoint>(_ title: String, value: Binding<Value>, in range: ClosedRange<Value>, step: Value.Stride? = nil, display: String) -> some View where Value.Stride: BinaryFloatingPoint {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).agFont(12, weight: .medium).foregroundStyle(AfterglowTheme.muted)
                Spacer()
                Text(display).agFont(12, design: .monospaced)
            }
            Group {
                if let step {
                    Slider(value: value, in: range, step: step)
                } else {
                    Slider(value: value, in: range)
                }
            }
            .tint(AfterglowTheme.gold)
            .accessibilityLabel(title)
            .accessibilityValue(display)
        }
    }
}
