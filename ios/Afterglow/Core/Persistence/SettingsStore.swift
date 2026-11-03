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
        static let customDuty = "settings.light.customDuty"
        static let quickMinutes = "settings.quick.minutes"
        static let quickLeadIn = "settings.quick.leadIn"
        static let quickFades = "settings.quick.fades"
        static let quickSound = "settings.quick.sound"
    }

    /// Sound choices for the Light tab besides the soundscapes.
    enum QuickSound {
        static let silent = "silent"
        static let ownMusic = "own-music"
    }

    static let quickLeadInOptions: [TimeInterval] = [0, 5, 15, 30]

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

    /// Share of each flash cycle the torch is on, for the custom program.
    @Published var customDuty: Double {
        didSet { defaults.set(Self.clampDuty(customDuty), forKey: Key.customDuty) }
    }

    /// Light tab: session length in minutes.
    @Published var quickMinutes: Int {
        didSet {
            let clamped = min(max(quickMinutes, Self.minuteRange.lowerBound), Self.minuteRange.upperBound)
            if clamped != quickMinutes { quickMinutes = clamped }
            defaults.set(clamped, forKey: Key.quickMinutes)
        }
    }

    /// Light tab: seconds of darkness before the first flash.
    @Published var quickLeadIn: TimeInterval {
        didSet { defaults.set(quickLeadIn, forKey: Key.quickLeadIn) }
    }

    /// Light tab: fade the light in and out.
    @Published var quickFades: Bool {
        didSet { defaults.set(quickFades, forKey: Key.quickFades) }
    }

    /// Light tab: a `Soundscape` raw value, `QuickSound.silent` or `QuickSound.ownMusic`.
    @Published var quickSound: String {
        didSet { defaults.set(quickSound, forKey: Key.quickSound) }
    }

    var lightScreeningIsCurrent: Bool { LightScreening.isCurrent(screenedAt: lightScreenedAt) }

    /// The program the user picked, or nil for "automatic".
    var chosenLightProgram: LightProgram? {
        if lightProgramChoice == LightProgramCatalog.customID {
            return .custom(startHz: Self.clampHz(customStartHz), endHz: Self.clampHz(customEndHz), dutyCycle: Self.clampDuty(customDuty))
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
        customDuty = Self.clampDuty((defaults.object(forKey: Key.customDuty) as? NSNumber)?.doubleValue ?? 0.5)
        let storedQuickMinutes = (defaults.object(forKey: Key.quickMinutes) as? NSNumber)?.intValue ?? 20
        quickMinutes = min(max(storedQuickMinutes, Self.minuteRange.lowerBound), Self.minuteRange.upperBound)
        quickLeadIn = (defaults.object(forKey: Key.quickLeadIn) as? NSNumber)?.doubleValue ?? 0
        quickFades = (defaults.object(forKey: Key.quickFades) as? NSNumber)?.boolValue ?? false
        quickSound = defaults.string(forKey: Key.quickSound) ?? Soundscape.drift.rawValue
    }

    static func clampHz(_ hz: Double) -> Double {
        let range = LightBounds.standard.frequencyRange
        return hz.isFinite ? min(max(hz, range.lowerBound), range.upperBound) : range.lowerBound
    }

    static func clampDuty(_ duty: Double) -> Double {
        let range = LightBounds.standard.dutyRange
        return duty.isFinite ? min(max(duty, range.lowerBound), range.upperBound) : 0.5
    }

    /// The Light tab's session, built from its saved choices.
    func quickLightConfiguration() -> SessionConfiguration {
        let soundscape = Soundscape(rawValue: quickSound) ?? .drift
        var configuration = SessionConfiguration(preset: PresetCatalog.quickLight, minutes: quickMinutes, volume: volume)
        configuration.soundscape = soundscape
        configuration.mixWithOtherAudio = quickSound == QuickSound.ownMusic
        if Soundscape(rawValue: quickSound) == nil { configuration.volume = 0 }
        configuration.useLight = lightScreeningIsCurrent
        configuration.lightProgram = chosenLightProgram ?? LightProgramCatalog.recommended(for: PresetCatalog.quickLight.intent)
        configuration.lightBrightness = lightBrightness
        configuration.lightLeadIn = quickLeadIn
        configuration.lightFades = quickFades
        return configuration
    }
}
