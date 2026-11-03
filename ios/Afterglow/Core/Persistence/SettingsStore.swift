import Combine
import Foundation

/// Small user preferences kept in the app's own UserDefaults (declared in PrivacyInfo, reason CA92.1).
@MainActor
final class SettingsStore: ObservableObject {
    private enum Key {
        static let soundscape = "settings.defaultSoundscape"
        static let volume = "settings.volume"
        static let minutes = "settings.defaultMinutes"
        static let lightBrightness = "settings.light.brightness"
        static let lightProgram = "settings.light.program"
        static let lightCustomStartHz = "settings.light.customStartHz"
        static let lightCustomEndHz = "settings.light.customEndHz"
        static let lightPreferred = "settings.light.preferred"
        static let lightScreenedAt = "settings.light.screenedAt"
    }

    static let minuteRange = 1...120
    static let brightnessRange: ClosedRange<Float> = 0.05...1
    /// Program choice meaning "the one recommended for the session's intent".
    static let automaticProgram = "auto"

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

    /// Requested torch level at full program intensity.
    @Published var lightBrightness: Float {
        didSet {
            let clamped = min(max(lightBrightness, Self.brightnessRange.lowerBound), Self.brightnessRange.upperBound)
            if clamped != lightBrightness { lightBrightness = clamped }
            defaults.set(clamped, forKey: Key.lightBrightness)
        }
    }

    /// `automaticProgram`, a catalog program ID, or `LightProgramCatalog.customID`.
    @Published var lightProgramChoice: String {
        didSet { defaults.set(lightProgramChoice, forKey: Key.lightProgram) }
    }

    @Published var customStartHz: Double {
        didSet { defaults.set(Self.clampHz(customStartHz), forKey: Key.lightCustomStartHz) }
    }

    @Published var customEndHz: Double {
        didSet { defaults.set(Self.clampHz(customEndHz), forKey: Key.lightCustomEndHz) }
    }

    /// Whether light was switched on last time, so it stays the default.
    @Published var lightPreferred: Bool {
        didSet { defaults.set(lightPreferred, forKey: Key.lightPreferred) }
    }

    /// When the light safety check was last completed.
    @Published var lightScreenedAt: Date? {
        didSet { defaults.set(lightScreenedAt, forKey: Key.lightScreenedAt) }
    }

    var lightScreeningIsCurrent: Bool { LightScreening.isCurrent(screenedAt: lightScreenedAt) }

    /// The program the user picked, or nil for "automatic".
    var chosenLightProgram: LightProgram? {
        if lightProgramChoice == LightProgramCatalog.customID {
            return .custom(startHz: Self.clampHz(customStartHz), endHz: Self.clampHz(customEndHz))
        }
        return LightProgramCatalog.program(id: lightProgramChoice)
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultSoundscape = defaults.string(forKey: Key.soundscape).flatMap(Soundscape.init(rawValue:)) ?? .ember
        let storedVolume = (defaults.object(forKey: Key.volume) as? NSNumber)?.floatValue ?? 0.7
        volume = min(max(storedVolume, 0), 1)
        let storedMinutes = (defaults.object(forKey: Key.minutes) as? NSNumber)?.intValue ?? 10
        defaultMinutes = min(max(storedMinutes, Self.minuteRange.lowerBound), Self.minuteRange.upperBound)
        let storedBrightness = (defaults.object(forKey: Key.lightBrightness) as? NSNumber)?.floatValue ?? 0.6
        lightBrightness = min(max(storedBrightness, Self.brightnessRange.lowerBound), Self.brightnessRange.upperBound)
        lightProgramChoice = defaults.string(forKey: Key.lightProgram) ?? Self.automaticProgram
        customStartHz = Self.clampHz((defaults.object(forKey: Key.lightCustomStartHz) as? NSNumber)?.doubleValue ?? 10)
        customEndHz = Self.clampHz((defaults.object(forKey: Key.lightCustomEndHz) as? NSNumber)?.doubleValue ?? 6)
        lightPreferred = defaults.bool(forKey: Key.lightPreferred)
        lightScreenedAt = defaults.object(forKey: Key.lightScreenedAt) as? Date
    }

    static func clampHz(_ hz: Double) -> Double {
        let range = LightBounds.standard.frequencyRange
        return hz.isFinite ? min(max(hz, range.lowerBound), range.upperBound) : range.lowerBound
    }
}
