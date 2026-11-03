import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var history: HistoryStore
    @State private var category = "All"
    @State private var query = ""
    @State private var selectedPreset: SessionPreset?
    @AppStorage("afterglow.favoriteIDs.v1") private var favoriteIDs = ""

    private var favorites: Set<String> { Set(favoriteIDs.split(separator: ",").map(String.init)) }

    private var presets: [SessionPreset] {
        PresetCatalog.all.filter { preset in
            (category == "All" || (category == "Favourites" && favorites.contains(preset.id)) || preset.intent.title.caseInsensitiveCompare(category) == .orderedSame)
            && (query.isEmpty || (preset.title + " " + preset.subtitle + " " + preset.intent.title)
                .localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    if let featured = PresetCatalog.all.first {
                        featuredCard(featured)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "headphones")
                        Text("A comfortable seat. A little time. Just you.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .agFont(12).foregroundStyle(AfterglowTheme.muted)
                    NavigationLink {
                        JourneyBuilderView()
                    } label: {
                        AfterglowCard {
                            HStack(spacing: 15) {
                                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                                    .agFont(25, weight: .ultraLight).foregroundStyle(AfterglowTheme.lavender)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Build a journey").agFont(20, weight: .regular, design: .serif)
                                    Text("Up to five moments, in your own order.")
                                        .agFont(12).foregroundStyle(AfterglowTheme.muted)
                                }
                                Spacer()
                                Image(systemName: "arrow.right").agFont(12).foregroundStyle(AfterglowTheme.muted)
                            }
                        }
                    }.buttonStyle(.plain)
                    library
                    if !history.sessions.isEmpty { practiceCard }
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "leaf").foregroundStyle(AfterglowTheme.sage)
                        Text("A session can be a pause, without needing to change how you feel. Start small and listen at a comfortable volume.")
                            .agFont(12).lineSpacing(4)
                    }
                    .foregroundStyle(AfterglowTheme.muted)
                    .padding(.vertical, 10)
                }
                .padding(24)
            }
            .afterglowScreen()
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(item: $selectedPreset) { preset in
                SessionFlowView(preset: preset)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Afterglow")
                Text("Come back\nto yourself.")
                    .agFont(39, weight: .regular, design: .serif)
                    .lineSpacing(0)
            }
            Spacer(minLength: 8)
            Image(systemName: "sun.horizon")
                .agFont(26, weight: .ultraLight)
                .foregroundStyle(AfterglowTheme.gold)
                .frame(width: 46, height: 46)
                .background(AfterglowTheme.gold.opacity(0.07), in: Circle())
                .accessibilityHidden(true)
        }
        .padding(.top, 18)
    }

    private func featuredCard(_ preset: SessionPreset) -> some View {
        Button { selectedPreset = preset } label: {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    TagPill(title: "BEGIN HERE", symbol: "sparkle", tint: AfterglowTheme.gold)
                    Spacer()
                    Text("\(preset.defaultMinutes) MIN")
                        .agFont(10, design: .monospaced).tracking(1.5)
                        .foregroundStyle(AfterglowTheme.muted)
                }
                GlowOrb(size: 200).frame(maxWidth: .infinity).padding(.vertical, -24)
                VStack(alignment: .leading, spacing: 8) {
                    Text(preset.title).agFont(30, weight: .regular, design: .serif)
                    Text(preset.subtitle).agFont(14).foregroundStyle(AfterglowTheme.muted)
                        .fixedSize(horizontal: false, vertical: true).lineSpacing(4)
                }
                HStack {
                    Text("Take a moment").agFont(14, weight: .semibold)
                    Spacer()
                    Image(systemName: "arrow.up.right").agFont(15)
                }
                .foregroundStyle(AfterglowTheme.gold)
                .padding(.top, 4)
            }
            .padding(24)
            .background(
                LinearGradient(colors: [Color(red: 0.14, green: 0.15, blue: 0.14), AfterglowTheme.surface], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 26)
            )
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(AfterglowTheme.gold.opacity(0.18)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Begin \(preset.title), \(preset.defaultMinutes) minutes")
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle(title: "Find your moment", detail: "\(PresetCatalog.all.count) SESSIONS")
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(AfterglowTheme.muted)
                TextField("Search sessions", text: $query)
                    .agFont(14).autocorrectionDisabled()
                    .accessibilityLabel("Search sessions")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .foregroundStyle(AfterglowTheme.muted).accessibilityLabel("Clear search")
                }
            }
            .padding(15).background(AfterglowTheme.surface, in: RoundedRectangle(cornerRadius: 14))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["All", "Favourites"] + SessionIntent.allCases.map(\.title), id: \.self) { item in
                        Button { category = item } label: {
                            Text(item).agFont(13, weight: .medium)
                                .padding(.horizontal, 17).padding(.vertical, 11)
                                .background(category == item ? AfterglowTheme.gold : AfterglowTheme.surface, in: Capsule())
                                .foregroundStyle(category == item ? AfterglowTheme.background : AfterglowTheme.muted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(category == item ? [.isSelected] : [])
                    }
                }
            }

            if presets.isEmpty {
                if category == "Favourites" && query.isEmpty {
                    ContentUnavailableView("Keep your favourites close", systemImage: "heart", description: Text("Tap the heart beside a session to save it here."))
                } else {
                    ContentUnavailableView.search(text: query)
                }
            } else {
                ForEach(presets) { preset in
                    SessionRow(preset: preset, isFavorite: favorites.contains(preset.id), onOpen: { selectedPreset = preset }) {
                        var updated = favorites
                        if updated.contains(preset.id) { updated.remove(preset.id) } else { updated.insert(preset.id) }
                        favoriteIDs = updated.sorted().joined(separator: ",")
                    }
                }
            }
        }
    }

    private var practiceCard: some View {
        AfterglowCard {
            VStack(alignment: .leading, spacing: 16) {
                Eyebrow(text: "Your time, well spent", color: AfterglowTheme.sage)
                HStack(alignment: .firstTextBaseline, spacing: 30) {
                    metric("\(history.stats.completedSessions)", "completed")
                    metric("\(Int(history.stats.totalMinutes))", "minutes listened")
                }
            }
        }
    }

    private func metric(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).agFont(29, weight: .regular, design: .serif)
            Text(caption).agFont(11).foregroundStyle(AfterglowTheme.muted)
        }
    }
}

private struct SessionRow: View {
    let preset: SessionPreset
    let isFavorite: Bool
    var onOpen: () -> Void
    var onFavorite: () -> Void
    private var accent: Color { AfterglowTheme.accent(for: preset.intent.title) }

    var body: some View {
        HStack(spacing: 15) {
            Button(action: onOpen) {
              HStack(spacing: 15) {
            Image(systemName: preset.symbolName)
                .agFont(23, weight: .ultraLight)
                .foregroundStyle(accent)
                .frame(width: 56, height: 68)
                .background(accent.opacity(0.075), in: RoundedRectangle(cornerRadius: 15))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(preset.title).agFont(17, weight: .regular, design: .serif)
                    .foregroundStyle(AfterglowTheme.ink)
                Text(preset.subtitle).agFont(12).foregroundStyle(AfterglowTheme.muted)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text("\(preset.intent.title.uppercased())  ·  \(preset.defaultMinutes) MIN")
                    .agFont(9, design: .monospaced).tracking(0.8)
                    .foregroundStyle(accent)
            }
            Spacer(minLength: 0)
            Image(systemName: "play.fill").agFont(11).foregroundStyle(AfterglowTheme.muted)
              }
            }.buttonStyle(.plain)
            Button(action: onFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .agFont(16).foregroundStyle(isFavorite ? AfterglowTheme.gold : AfterglowTheme.muted)
                    .frame(width: 44, height: 48)
            }.buttonStyle(.plain)
                .accessibilityLabel(isFavorite ? "Remove \(preset.title) from favourites" : "Favourite \(preset.title)")
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(AfterglowTheme.surface, in: RoundedRectangle(cornerRadius: 19))
    }
}
