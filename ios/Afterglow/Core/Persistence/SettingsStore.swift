import Combine
import Foundation

/// Small user preferences kept in the app's own UserDefaults (declared in PrivacyInfo, reason CA92.1).
@MainActor
final class SettingsStore: ObservableObject {
    private enum Key {
        static let soundscape = "settings.defaultSoundscape"
        static let volume = "settings.volume"
        static let minutes = "settings.defaultMinutes"
    }

    static let minuteRange = 1...120

    @Published var defaultSoundscape: Soundscape {
        didSet { defaults.set(defaultSoundscape.rawValue, forKey: Key.soundscape) }
    }

    @Published var volume: Float {
        didSet {
            let clamped = min(max(volume, 0), 1)
            if clamped != volume { volume = clamped }
            defaults.set(clamped, forKey: Key.volume)
        }
    }

    @Published var defaultMinutes: Int {
        didSet {
            let clamped = min(max(defaultMinutes, Self.minuteRange.lowerBound), Self.minuteRange.upperBound)
            if clamped != defaultMinutes { defaultMinutes = clamped }
            defaults.set(clamped, forKey: Key.minutes)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultSoundscape = defaults.string(forKey: Key.soundscape).flatMap(Soundscape.init(rawValue:)) ?? .ember
        let storedVolume = (defaults.object(forKey: Key.volume) as? NSNumber)?.floatValue ?? 0.7
        volume = min(max(storedVolume, 0), 1)
        let storedMinutes = (defaults.object(forKey: Key.minutes) as? NSNumber)?.intValue ?? 10
        defaultMinutes = min(max(storedMinutes, Self.minuteRange.lowerBound), Self.minuteRange.upperBound)
    }
}
