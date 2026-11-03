import SwiftUI

private struct JourneyLaunch: Identifiable {
    let id = UUID()
    let presets: [SessionPreset]
}

struct JourneyBuilderView: View {
    @AppStorage("afterglow.journeyIDs.v1") private var storedIDs = ""
    @State private var selected: [SessionPreset] = []
    @State private var launch: JourneyLaunch?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Eyebrow(text: "One moment into the next", color: AfterglowTheme.lavender)
                Text("Go a little further.")
                    .agFont(34, weight: .regular, design: .serif)
                Text("Arrange up to five sessions. Each uses its default duration and soundscape. Your journey plays in order, with a reflection at the end.")
                    .agFont(14).foregroundStyle(AfterglowTheme.muted).lineSpacing(4)
                TagPill(title: "Audio-only journey", symbol: "headphones", tint: AfterglowTheme.lavender)
                SectionTitle(title: "Your journey", detail: "\(selected.count) / 5")
                if selected.isEmpty {
                    Text("Add a session below to begin.")
                        .agFont(14).foregroundStyle(AfterglowTheme.muted).padding(.vertical, 10)
                }
                ForEach(Array(selected.enumerated()), id: \.offset) { index, preset in
                    AfterglowCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Text(String(format: "%02d", index + 1))
                                    .agFont(12, design: .monospaced).foregroundStyle(AfterglowTheme.lavender)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(preset.title).agFont(18, weight: .regular, design: .serif)
                                    Text("\(preset.defaultMinutes) min · \(preset.soundscape.title)")
                                        .agFont(11).foregroundStyle(AfterglowTheme.muted)
                                }
                                Spacer()
                                Button { selected.remove(at: index); save() } label: {
                                    Image(systemName: "minus.circle").frame(width: 44, height: 44)
                                }.accessibilityLabel("Remove \(preset.title)")
                            }
                            HStack(spacing: 12) {
                                Button("Move up", systemImage: "arrow.up") { selected.swapAt(index, index - 1); save() }
                                    .disabled(index == 0)
                                Button("Move down", systemImage: "arrow.down") { selected.swapAt(index, index + 1); save() }
                                    .disabled(index == selected.count - 1)
                            }.agFont(11).buttonStyle(.bordered)
                        }
                    }
                }
                if !selected.isEmpty {
                    Text("\(selected.reduce(0) { $0 + $1.defaultMinutes }) minutes in total")
                        .agFont(12).foregroundStyle(AfterglowTheme.muted)
                    PrimaryButton(title: "Prepare journey", symbol: "arrow.right") {
                        launch = JourneyLaunch(presets: selected)
                    }
                }
                SectionTitle(title: "Add a moment")
                ForEach(PresetCatalog.all) { preset in
                    Button {
                        if selected.count < 5 { selected.append(preset); save() }
                    } label: {
                        HStack(spacing: 13) {
                            Image(systemName: preset.symbolName).foregroundStyle(AfterglowTheme.lavender).frame(width: 30)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(preset.title).agFont(15)
                                Text("\(preset.defaultMinutes) min · \(preset.intent.title)")
                                    .agFont(11).foregroundStyle(AfterglowTheme.muted)
                            }
                            Spacer()
                            Image(systemName: "plus.circle").frame(width: 36, height: 44)
                        }
                        .padding(.horizontal, 15).padding(.vertical, 5)
                        .background(AfterglowTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain).disabled(selected.count >= 5)
                    .opacity(selected.count >= 5 ? 0.5 : 1)
                    .accessibilityLabel("Add \(preset.title), \(preset.defaultMinutes) minutes")
                }
            }.padding(24).padding(.bottom, 24)
        }
        .navigationTitle("Your journey").navigationBarTitleDisplayMode(.inline)
        .afterglowScreen()
        .onAppear {
            selected = storedIDs.split(separator: ",").compactMap { PresetCatalog.preset(id: String($0)) }.prefix(5).map { $0 }
        }
        .fullScreenCover(item: $launch) { item in
            if let first = item.presets.first {
                SessionFlowView(preset: first, journey: item.presets)
            }
        }
    }

    private func save() {
        storedIDs = selected.map(\.id).joined(separator: ",")
    }
}
