import SwiftUI

struct RootView: View {
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var player: SessionPlayer
    @AppStorage("afterglow.didWelcome.v1") private var didWelcome = false
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            DiscoverView()
                .tabItem { Label("Discover", systemImage: "circle.hexagongrid") }.tag(0)
            JournalView()
                .tabItem { Label("Reflect", systemImage: "book.closed") }.tag(1)
            SettingsView(lightStatus: LightFeature.statusExplanation, onEraseHistory: { history.eraseAll() })
                .tabItem { Label("About", systemImage: "circle.dotted") }.tag(2)
        }
        .toolbarBackground(AfterglowTheme.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let warning = player.lightShutdownWarning {
                TorchShutdownWarningView(detail: warning, onAcknowledge: player.acknowledgeLightShutdownWarning)
            }
        }
        .sheet(isPresented: Binding(get: { !didWelcome }, set: { if !$0 { didWelcome = true } })) {
            WelcomeView { didWelcome = true }
                .interactiveDismissDisabled()
        }
    }
}

private struct WelcomeView: View {
    var onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Eyebrow(text: "A small space for yourself")
                    .padding(.top, 40)
                GlowOrb(size: 240)
                VStack(spacing: 14) {
                    Text("Afterglow")
                        .agFont(48, weight: .regular, design: .serif)
                    Text("Arrive. Listen. Reflect.")
                        .agFont(17).foregroundStyle(AfterglowTheme.muted)
                    Text("Choose a soundscape, take a little time, and keep a note of what you notice. There is nothing you need to achieve.")
                        .agFont(16).lineSpacing(5)
                        .foregroundStyle(AfterglowTheme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
                VStack(alignment: .leading, spacing: 13) {
                    Label("Works offline, without an account", systemImage: "wifi.slash")
                    Label("Original sound, no subscription", systemImage: "waveform")
                    Label("A private journal on your device", systemImage: "lock")
                }
                .agFont(14).foregroundStyle(AfterglowTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20).background(AfterglowTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                Text(LightFeature.statusExplanation)
                    .agFont(12).foregroundStyle(AfterglowTheme.muted)
                    .lineSpacing(3).multilineTextAlignment(.center)
                PrimaryButton(title: "Make a little space", symbol: "arrow.right", action: onContinue)
            }
            .padding(28)
            .padding(.bottom, 20)
        }
        .afterglowScreen()
    }
}
