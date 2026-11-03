import SwiftUI

@main
@MainActor
struct AfterglowApp: App {
    @StateObject private var history: HistoryStore
    @StateObject private var settings: SettingsStore
    @StateObject private var player: SessionPlayer

    init() {
        let history = HistoryStore()
        _history = StateObject(wrappedValue: history)
        _settings = StateObject(wrappedValue: SettingsStore())
        _player = StateObject(wrappedValue: SessionPlayer(history: history))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(history)
                .environmentObject(settings)
                .environmentObject(player)
                .preferredColorScheme(.dark)
                .tint(AfterglowTheme.gold)
        }
    }
}
