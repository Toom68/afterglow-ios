import SwiftUI
import Combine

struct SessionFlowView: View {
    private let sequence: [SessionPreset]
    @State private var sequenceIndex = 0
    private var preset: SessionPreset { sequence[sequenceIndex] }
    private var isJourney: Bool { sequence.count > 1 }
    private var hasTorchHardware: Bool { SystemTorchDevice().hasTorch }
    @EnvironmentObject private var player: SessionPlayer
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var stage = Stage.prepare
    @State private var minutes: Int
    @State private var soundscape: Soundscape
    @State private var intention = ""
    @State private var reflection = ""
    @State private var mood: Mood?
    @State private var experimentalLight = false
    @State private var showingScreening = false
    @State private var confirmEnd = false
    @State private var ownMusic = false
    @State private var endedJourneyEarly = false
    @State private var savedReflection: JournalEntry?
    @State private var confirmingDiscard = false

    private enum Stage { case prepare, listen, reflect }

    init(preset: SessionPreset, journey: [SessionPreset] = []) {
        self.sequence = journey.isEmpty ? [preset] : Array(journey.prefix(5))
        _minutes = State(initialValue: preset.defaultMinutes)
        _soundscape = State(initialValue: preset.soundscape)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .prepare: preparation
                case .listen: listening
                case .reflect: integration
                }
            }
            .afterglowScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if stage == .listen && experimentalLight { endJourney() }
                        else if stage == .listen { confirmEnd = true }
                        else { requestClose() }
                    } label: {
                        Image(systemName: "xmark").agFont(14, weight: .medium)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(stage == .listen ? "End session" : "Close")
                }
                ToolbarItem(placement: .principal) {
                    Eyebrow(text: stage == .prepare ? "Make a little space" : stage == .listen ? "Your moment" : "Carry it with you")
                }
            }
            .confirmationDialog("End this session?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("End and reflect", action: endJourney)
                Button("Keep listening", role: .cancel) { }
            }
            .alert("Discard these notes?", isPresented: $confirmingDiscard) {
                if stage == .reflect && !history.writesBlocked {
                    Button("Save and return", action: saveReflection)
                }
                Button("Discard", role: .destructive, action: close)
                Button("Keep editing", role: .cancel) { }
            } message: {
                Text("Your unsaved intention or reflection will be lost.")
            }
            .sheet(isPresented: $showingScreening) {
                LightScreeningView { experimentalLight = true }
            }
            // Subscribe to events rather than view rendering: completion must advance an audio
            // journey while the screen is locked too. Scheduling on main also lets the player
            // finish writing the previous record before a new session replaces its state.
            .onReceive(player.$phase.receive(on: DispatchQueue.main)) { phase in
                guard stage == .listen else { return }
                if case .finished(let outcome) = phase {
                    if outcome == .completed && isJourney && !endedJourneyEarly && sequenceIndex + 1 < sequence.count {
                        sequenceIndex += 1
                        minutes = preset.defaultMinutes
                        soundscape = preset.soundscape
                        player.reset()
                        begin()
                    } else {
                        stage = .reflect
                    }
                }
            }
            .onDisappear {
                if player.phase.isActive { player.end() }
                player.reset()
            }
            .interactiveDismissDisabled()
            .safeAreaInset(edge: .top, spacing: 0) {
                if let warning = player.lightShutdownWarning {
                    TorchShutdownWarningView(detail: warning, onAcknowledge: player.acknowledgeLightShutdownWarning)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if stage == .listen && experimentalLight {
                    Button(role: .destructive, action: endJourney) {
                        Label("STOP LIGHT & SESSION", systemImage: "stop.fill")
                            .agFont(14, weight: .bold)
                            .frame(maxWidth: .infinity, minHeight: 62)
                            .background(Color.red.opacity(0.18), in: RoundedRectangle(cornerRadius: 18))
                    }
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(AfterglowTheme.background)
                }
            }
        }
    }

    private var preparation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 10) {
                    if isJourney {
                        Eyebrow(text: "Journey · \(sequence.count) sessions · \(sequence.reduce(0) { $0 + $1.defaultMinutes }) minutes", color: AfterglowTheme.lavender)
                    }
                    TagPill(title: preset.intent.title, symbol: preset.symbolName, tint: accent)
                    Text(preset.title).agFont(39, weight: .regular, design: .serif)
                    Text(preset.subtitle).agFont(15).foregroundStyle(AfterglowTheme.muted).lineSpacing(4)
                }
                GlowOrb(tint: accent, size: 170).frame(maxWidth: .infinity).padding(.vertical, -18)
                if !isJourney {
                 VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("01", "Choose your time")
                    HStack(spacing: 10) {
                        ForEach(preset.durationOptionsMinutes, id: \.self) { option in
                            Button { minutes = option } label: {
                                Text("\(option) min").agFont(14, weight: .medium)
                                    .frame(maxWidth: .infinity, minHeight: 46)
                                    .background(minutes == option ? accent.opacity(0.16) : AfterglowTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(minutes == option ? accent.opacity(0.6) : .clear))
                                    .foregroundStyle(minutes == option ? accent : AfterglowTheme.muted)
                            }.buttonStyle(.plain)
                                .accessibilityAddTraits(minutes == option ? [.isSelected] : [])
                        }
                    }
                 }

                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("02", "Choose a sound")
                    Picker("Soundscape", selection: $soundscape) {
                        ForEach(Soundscape.allCases) { sound in
                            Text(sound.title).tag(sound)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(soundscape.summary).agFont(12).foregroundStyle(AfterglowTheme.muted)
                    HStack {
                        Image(systemName: "speaker.wave.1").accessibilityHidden(true)
                        Slider(value: $settings.volume, in: 0...1)
                            .accessibilityLabel("Session volume")
                        Image(systemName: "speaker.wave.3").accessibilityHidden(true)
                    }
                    .agFont(12).foregroundStyle(AfterglowTheme.muted)
                    Text("Start with your phone volume low. Adjust it once the sound begins.")
                        .agFont(11).foregroundStyle(AfterglowTheme.muted)
                    Toggle("Use my own music instead", isOn: $ownMusic)
                        .agFont(13)
                    if ownMusic {
                        Text("Start music in your music app, then return here. Afterglow’s sound will be muted and the session timer will run alongside it. Afterglow cannot control or download your music.")
                            .agFont(12).foregroundStyle(AfterglowTheme.muted).lineSpacing(4)
                    }
                }
                } else {
                    AfterglowCard {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(sequence.enumerated()), id: \.offset) { index, item in
                                HStack {
                                    Text("\(index + 1). \(item.title)")
                                    Spacer()
                                    Text("\(item.defaultMinutes) min").foregroundStyle(AfterglowTheme.muted)
                                }.agFont(13)
                            }
                            Text("Sessions use their default durations and sounds. You can end the journey at any time.")
                                .agFont(11).foregroundStyle(AfterglowTheme.muted).lineSpacing(3)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("03", "An intention, if you like")
                    TextField("What would you like to make room for?", text: $intention, axis: .vertical)
                        .agFont(14).lineLimit(2...4)
                        .padding(17).background(AfterglowTheme.surface, in: RoundedRectangle(cornerRadius: 15))
                        .onChange(of: intention) { _, value in
                            if value.count > 500 { intention = String(value.prefix(500)) }
                        }
                }

                AfterglowCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Experimental light", systemImage: "flashlight.on.fill")
                                .agFont(14, weight: .medium)
                            Spacer()
                            TagPill(title: experimentalLight ? "OPTED IN" : "OFF", tint: experimentalLight ? AfterglowTheme.gold : AfterglowTheme.muted)
                        }
                        Text("Flashing light can trigger seizures and other adverse effects, including in people without a known history. This original prototype sequence is unvalidated and is not Lumenate’s method.")
                            .agFont(12).foregroundStyle(AfterglowTheme.muted).lineSpacing(4)
                        if LightFeature.isAvailable && hasTorchHardware && !isJourney && preset.intent != .sleep {
                            Button(experimentalLight ? "Turn light off" : "Review risks and opt in") {
                                if experimentalLight { experimentalLight = false } else { showingScreening = true }
                            }
                            .agFont(13, weight: .medium).tint(AfterglowTheme.gold)
                            .frame(minHeight: 44)
                        } else {
                            Text(isJourney ? "Journeys are audio only in this prototype." : preset.intent == .sleep ? "Sleep sessions are audio only. Light use requires staying awake and able to stop." : !hasTorchHardware ? "The torch is unavailable on this device or simulator. Use audio only." : LightFeature.statusExplanation)
                                .agFont(11).foregroundStyle(AfterglowTheme.gold)
                        }
                    }
                }

                Text(experimentalLight
                     ? "Stay seated in a clear, quiet space. Keep eyes closed when the torch is facing you. Turn the phone away or cover the torch to interrupt exposure immediately. You can stop the session at any time."
                     : "Find a comfortable position. You can keep your eyes open or closed, and breathe naturally. There is no particular state to reach.")
                    .agFont(12).foregroundStyle(AfterglowTheme.muted).lineSpacing(4)
                if experimentalLight {
                    Text("There is a 10-second positioning delay, then at most 30 seconds of light. Audio continues afterward. Pausing or leaving the app keeps light off for the rest of that session.")
                        .agFont(12).foregroundStyle(AfterglowTheme.gold).lineSpacing(4)
                }
                PrimaryButton(title: experimentalLight ? "Begin with experimental light" : "Begin audio session", symbol: "play.fill", action: begin)
                Text("\(minutes) MIN  ·  \(soundscape.title.uppercased())  ·  OFFLINE")
                    .agFont(9, design: .monospaced).tracking(1)
                    .foregroundStyle(AfterglowTheme.muted).frame(maxWidth: .infinity)
            }
            .padding(24).padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var listening: some View {
        ScrollView {
            VStack(spacing: 27) {
                VStack(spacing: 10) {
                    Text(preset.title).agFont(32, weight: .regular, design: .serif)
                    Text((ownMusic ? "Your own music" : soundscape.title) + (experimentalLight ? (player.isLightActive ? " · Experimental light test" : " · Light test stopped, audio continues") : " · Audio session"))
                        .agFont(12).foregroundStyle(AfterglowTheme.muted)
                    if isJourney {
                        Text("JOURNEY  \(sequenceIndex + 1) / \(sequence.count)")
                            .agFont(10, design: .monospaced).tracking(1.5).foregroundStyle(AfterglowTheme.lavender)
                    }
                }.padding(.top, 26)
                ZStack {
                    GlowOrb(tint: accent, size: 270)
                    Circle().stroke(accent.opacity(0.08), lineWidth: 2)
                        .frame(width: 245, height: 245)
                    Circle().trim(from: 0, to: min(max(player.progress, 0), 1))
                        .stroke(accent.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 245, height: 245)
                }
                .accessibilityHidden(true)
                VStack(spacing: 9) {
                    Text(player.phase == .idle ? "--:--" : clock(player.remaining))
                        .agFont(44, weight: .ultraLight, design: .monospaced).monospacedDigit()
                        .accessibilityLabel("Time remaining")
                        .accessibilityValue(player.phase == .idle ? "Not started" : "\(Int(player.remaining / 60)) minutes and \(Int(player.remaining) % 60) seconds")
                    Text(player.phase == .idle ? "NOT STARTED" : player.phase.isRunning ? "REMAINING" : "PAUSED")
                        .agFont(9, design: .monospaced).tracking(2.8)
                        .foregroundStyle(AfterglowTheme.muted)
                }
                Text(guidance)
                    .agFont(21, weight: .regular, design: .serif)
                    .foregroundStyle(AfterglowTheme.muted).multilineTextAlignment(.center)
                    .frame(minHeight: 65).padding(.horizontal, 20)
                if let notice = player.notice {
                    VStack(spacing: 10) {
                        Text(notice.message).agFont(12).lineSpacing(3)
                        Button("Dismiss message") { player.dismissNotice() }.agFont(12, weight: .medium)
                    }
                    .foregroundStyle(AfterglowTheme.gold).padding(16)
                    .background(AfterglowTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                }
                if player.phase == .idle {
                    PrimaryButton(title: "Try starting again", symbol: "play.fill", action: begin)
                    QuietButton(title: "Back to preparation") { player.reset(); stage = .prepare }
                } else {
                 Button {
                    if player.phase.isRunning { player.pause() } else { player.resume() }
                } label: {
                    Image(systemName: player.phase.isRunning ? "pause.fill" : "play.fill")
                        .agFont(23).foregroundStyle(AfterglowTheme.background)
                        .frame(width: 76, height: 76).background(AfterglowTheme.gold, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.phase.isRunning ? (experimentalLight ? "Pause session and stop light" : "Pause session") : (experimentalLight ? "Resume audio only" : "Resume session"))
                }
                if ownMusic {
                    Text("Pause and stop affect Afterglow’s timer and light. Control your music in its own app.")
                        .agFont(11).foregroundStyle(AfterglowTheme.muted).multilineTextAlignment(.center)
                }
                if !experimentalLight {
                    Button("End this moment") { confirmEnd = true }
                        .agFont(13).foregroundStyle(AfterglowTheme.muted)
                        .frame(minHeight: 44)
                }
                Text("Breathe naturally. Stop whenever you need to.")
                    .agFont(11).foregroundStyle(AfterglowTheme.muted)
            }
            .frame(maxWidth: .infinity).padding(24)
        }
    }

    private var integration: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                GlowOrb(tint: AfterglowTheme.sage, size: 150).frame(maxWidth: .infinity).padding(.vertical, -10)
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "A moment, made")
                    Text("Take your time\ncoming back.")
                        .agFont(36, weight: .regular, design: .serif)
                    Text("Notice the room around you. There’s no need to find meaning in everything you felt, or to have felt anything at all.")
                        .agFont(14).foregroundStyle(AfterglowTheme.muted).lineSpacing(5)
                }
                if let record = player.lastRecord {
                    TagPill(title: "\(listenedTime(record.listenedDuration)) with \(record.title)", symbol: "checkmark", tint: AfterglowTheme.sage)
                }
                if !intention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    AfterglowCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Eyebrow(text: "You made room for", color: AfterglowTheme.sage)
                            Text(intention).agFont(17, weight: .regular, design: .serif).lineSpacing(4)
                        }
                    }
                }
                MoodPicker(selection: $mood)
                VStack(alignment: .leading, spacing: 12) {
                    Text("What would you like to remember?").agFont(15, weight: .medium)
                    TextEditor(text: $reflection)
                        .agFont(15).lineSpacing(5).scrollContentBackground(.hidden)
                        .frame(minHeight: 150).padding(12)
                        .background(AfterglowTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                        .accessibilityLabel("Session reflection")
                        .onChange(of: reflection) { _, value in
                            if value.count > 9_000 { reflection = String(value.prefix(9_000)) }
                        }
                    Text("Private on this device. Writing is optional.")
                        .agFont(11).foregroundStyle(AfterglowTheme.muted)
                }
                if let error = history.lastError {
                    Text(error).agFont(12).foregroundStyle(AfterglowTheme.gold)
                }
                if history.writesBlocked {
                    Text("Saving is unavailable because this device has history from a newer version of Afterglow. Update the app, or explicitly erase local history in About before writing new reflections.")
                        .agFont(12).foregroundStyle(AfterglowTheme.gold)
                }
                PrimaryButton(title: "Save and return", symbol: "arrow.right", action: saveReflection)
                    .disabled(history.writesBlocked).opacity(history.writesBlocked ? 0.45 : 1)
                QuietButton(title: "Return without a reflection", action: requestClose)
            }.padding(24).padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var accent: Color { AfterglowTheme.accent(for: preset.intent.title) }

    private var guidance: String {
        if player.phase == .idle { return "Your session hasn’t started yet." }
        if !player.phase.isRunning { return "There’s room to pause." }
        if player.elapsed < 20 { return "Let your attention arrive." }
        if player.remaining < 30 { return "Notice what’s here, just now." }
        switch preset.intent {
        case .calm: return "Let the sound be somewhere to rest."
        case .focus: return "Wandering is natural. Gently return."
        case .sleep: return "Nothing else needs doing right now."
        case .reflect: return "Notice, without needing an answer."
        }
    }

    private func fieldLabel(_ number: String, _ title: String) -> some View {
        HStack(spacing: 10) {
            Text(number).agFont(10, design: .monospaced).foregroundStyle(accent)
            Text(title).agFont(15, weight: .medium)
        }
    }

    private func begin() {
        var configuration = SessionConfiguration(preset: preset, minutes: minutes, volume: settings.volume)
        configuration.soundscape = soundscape
        configuration.volume = ownMusic ? 0 : settings.volume
        configuration.mixWithOtherAudio = ownMusic
        configuration.useExperimentalLight = experimentalLight
        stage = .listen
        player.start(configuration)
    }

    private func saveReflection() {
        guard !history.writesBlocked else { return }
        var text = reflection.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIntention = intention.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedIntention.isEmpty {
            text = "Intention: \(trimmedIntention)" + (text.isEmpty ? "" : "\n\n\(text)")
        }
        if !text.isEmpty || mood != nil {
            if var existing = savedReflection {
                existing.text = text
                existing.mood = mood
                history.updateJournal(existing)
                savedReflection = existing
            } else {
                savedReflection = history.addJournal(text: text, mood: mood, sessionID: player.lastRecord?.id)
            }
            if history.lastError != nil { return }
        }
        close()
    }

    private func close() {
        endedJourneyEarly = true
        if let savedReflection, history.lastError != nil {
            history.deleteJournal(id: savedReflection.id)
        }
        if player.phase.isActive { player.end() }
        player.reset()
        dismiss()
    }

    private func requestClose() {
        if !reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || mood != nil || !intention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            confirmingDiscard = true
        } else {
            close()
        }
    }

    private func endJourney() {
        endedJourneyEarly = true
        player.end()
        stage = .reflect
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(ceil(seconds)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func listenedTime(_ seconds: TimeInterval) -> String {
        let value = Int(seconds / 60)
        if value == 0 { return "Less than a minute" }
        return value == 1 ? "1 minute" : "\(value) minutes"
    }
}

private struct LightScreeningView: View {
    @Environment(\.dismiss) private var dismiss
    var onOptIn: () -> Void
    @State private var adult = false
    @State private var noRiskFactors = false
    @State private var understandsRisk = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Eyebrow(text: "Read before every light session")
                    Text("Flashing light\nhas real risks.")
                        .agFont(34, weight: .regular, design: .serif)
                    Text("It can trigger a seizure even without a known history. Closed eyes, a low brightness setting, or passing this checklist do not make the exposure safe.")
                        .agFont(15).lineSpacing(4)
                    AfterglowCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Keep light mode off if any apply, or you are unsure:")
                                .agFont(14, weight: .semibold)
                            Text("A personal or family history of seizures or epilepsy; twitching, blackouts, confusion, or severe dizziness with flicker; unexplained blackouts or morning jerks; brain injury, brain surgery, tumour, or other neurological conditions; light sensitivity, light-triggered migraine, or eye conditions; bipolar disorder, psychosis, mania, panic attacks, dissociation, suicidality, or another condition that could be worsened by altered perception; pregnancy; alcohol or sedative withdrawal; or medication or substance use that may change seizure risk or light sensitivity.")
                                .agFont(13).foregroundStyle(AfterglowTheme.muted).lineSpacing(4)
                            Text("This is a conservative prototype checklist, not medical clearance or an exhaustive clinical screening tool. If uncertain, use audio only and ask a qualified clinician.")
                                .agFont(12).foregroundStyle(AfterglowTheme.gold).lineSpacing(4)
                        }
                    }
                    Text("Stay awake and seated in a safe place, with eyes closed while the torch faces you and nobody else exposed to it. Do not use while driving, sleep-deprived, intoxicated, or alone if you have any concern about your response. Stop immediately for discomfort, distress, headache, nausea, twitching, confusion, faintness, or unusual symptoms. Seek urgent medical care for a seizure or loss of consciousness, and medical advice before any further light exposure after a suspected reaction.")
                        .agFont(13).foregroundStyle(AfterglowTheme.muted).lineSpacing(4)
                    Text(LightFeature.experimentalDisclosure + "\n\nReview the method report in the source package before testing. The emitted output must be measured without exposing anyone’s eyes first.")
                        .agFont(13).foregroundStyle(AfterglowTheme.gold).lineSpacing(4)
                    Toggle("I am 18 or older", isOn: $adult)
                    Toggle("None of the listed risk factors apply and I am not unsure", isOn: $noRiskFactors)
                    Toggle("I understand the residual risks and choose this experimental mode for this session", isOn: $understandsRisk)
                    Text("Keep the stop control within reach. Turning the phone away or covering the torch interrupts exposure while you stop the session.")
                        .agFont(12).foregroundStyle(AfterglowTheme.muted).lineSpacing(4)
                    PrimaryButton(title: "Opt in for this session") {
                        onOptIn()
                        dismiss()
                    }
                    .disabled(!adult || !noRiskFactors || !understandsRisk)
                    .opacity(adult && noRiskFactors && understandsRisk ? 1 : 0.4)
                    QuietButton(title: "Use audio only") { dismiss() }
                }
                .agFont(14).padding(24)
            }
            .navigationTitle("Experimental light").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .afterglowScreen()
        }
    }
}
