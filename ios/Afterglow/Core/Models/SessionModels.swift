import Foundation

/// Original procedurally generated ambient beds. No sampled or third-party audio is used.
enum Soundscape: String, Codable, CaseIterable, Identifiable, Hashable {
    case ember
    case tide
    case drift
    case hush

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ember: return "Ember"
        case .tide: return "Tide"
        case .drift: return "Drift"
        case .hush: return "Hush"
        }
    }

    var summary: String {
        switch self {
        case .ember: return "Warm low drone with a slow swell"
        case .tide: return "Soft filtered noise rising and falling like waves"
        case .drift: return "Airy open fifths that wander gently"
        case .hush: return "Quiet pink noise for winding down"
        }
    }

    var symbolName: String {
        switch self {
        case .ember: return "flame"
        case .tide: return "water.waves"
        case .drift: return "cloud"
        case .hush: return "moon.zzz"
        }
    }
}

enum SessionIntent: String, Codable, CaseIterable, Identifiable, Hashable {
    case calm
    case focus
    case sleep
    case reflect

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calm: return "Calm"
        case .focus: return "Focus"
        case .sleep: return "Sleep"
        case .reflect: return "Reflect"
        }
    }
}

struct SessionPreset: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let intent: SessionIntent
    let soundscape: Soundscape
    let durationOptionsMinutes: [Int]
    let defaultMinutes: Int
    let symbolName: String
}

enum PresetCatalog {
    static let all: [SessionPreset] = [
        SessionPreset(
            id: "settle",
            title: "Settle In",
            subtitle: "A short pause to arrive in the present",
            intent: .calm,
            soundscape: .ember,
            durationOptionsMinutes: [5, 10, 15],
            defaultMinutes: 10,
            symbolName: "sun.haze"
        ),
        SessionPreset(
            id: "clear-mind",
            title: "Clear Mind",
            subtitle: "Steady sound to rest your attention on",
            intent: .focus,
            soundscape: .drift,
            durationOptionsMinutes: [10, 20, 30],
            defaultMinutes: 20,
            symbolName: "scope"
        ),
        SessionPreset(
            id: "low-tide",
            title: "Low Tide",
            subtitle: "Slow waves for loosening up after a long day",
            intent: .calm,
            soundscape: .tide,
            durationOptionsMinutes: [10, 15, 25],
            defaultMinutes: 15,
            symbolName: "water.waves"
        ),
        SessionPreset(
            id: "wind-down",
            title: "Wind Down",
            subtitle: "Quiet, dim, and unhurried before sleep",
            intent: .sleep,
            soundscape: .hush,
            durationOptionsMinutes: [15, 30, 45],
            defaultMinutes: 30,
            symbolName: "moon.stars"
        ),
        SessionPreset(
            id: "afterglow",
            title: "Afterglow",
            subtitle: "Listen, then write down what surfaced",
            intent: .reflect,
            soundscape: .ember,
            durationOptionsMinutes: [10, 15, 20],
            defaultMinutes: 15,
            symbolName: "sparkles"
        ),
        SessionPreset(
            id: "short-reset",
            title: "Short Reset",
            subtitle: "A few quiet minutes between one thing and the next",
            intent: .calm,
            soundscape: .tide,
            durationOptionsMinutes: [3, 5, 10],
            defaultMinutes: 5,
            symbolName: "arrow.counterclockwise"
        ),
        SessionPreset(
            id: "morning-ease",
            title: "Morning Ease",
            subtitle: "Start the day slowly, before the screen fills up",
            intent: .calm,
            soundscape: .drift,
            durationOptionsMinutes: [5, 10, 15],
            defaultMinutes: 10,
            symbolName: "sunrise"
        ),
        SessionPreset(
            id: "steady-focus",
            title: "Steady Focus",
            subtitle: "A long, even bed of sound to work alongside",
            intent: .focus,
            soundscape: .ember,
            durationOptionsMinutes: [25, 45, 60],
            defaultMinutes: 25,
            symbolName: "target"
        ),
        SessionPreset(
            id: "open-sky",
            title: "Open Sky",
            subtitle: "Wide, wandering tones for letting thoughts settle",
            intent: .reflect,
            soundscape: .drift,
            durationOptionsMinutes: [10, 20, 30],
            defaultMinutes: 20,
            symbolName: "cloud.sun"
        ),
        SessionPreset(
            id: "quiet-harbour",
            title: "Quiet Harbour",
            subtitle: "Soft waves that fade as you drift off",
            intent: .sleep,
            soundscape: .tide,
            durationOptionsMinutes: [20, 30, 45],
            defaultMinutes: 30,
            symbolName: "moon.zzz"
        ),
        SessionPreset(
            id: "night-drift",
            title: "Night Drift",
            subtitle: "A long, low hush for the middle of the night",
            intent: .sleep,
            soundscape: .hush,
            durationOptionsMinutes: [30, 45, 60],
            defaultMinutes: 45,
            symbolName: "moon"
        )
    ]

    static func preset(id: String) -> SessionPreset? {
        all.first { $0.id == id }
    }
}

struct SessionConfiguration: Codable, Hashable {
    static let minimumDuration: TimeInterval = 60
    static let maximumDuration: TimeInterval = 120 * 60

    var presetID: String
    var title: String
    var soundscape: Soundscape
    var duration: TimeInterval
    var volume: Float
    /// Lets the user's own music keep playing underneath (Afterglow's bed is usually muted then).
    var mixWithOtherAudio = false
    /// Set by the UI only after this session's risk screening and explicit consent. The player
    /// still refuses unless `LightFeature.isAvailable` (research/Debug build with an allowed protocol).
    var useExperimentalLight = false
    /// Which allowed sequence to use; nil picks the first entry of `LightProtocolCatalog.available`.
    var lightProtocolID: String?

    init(presetID: String, title: String, soundscape: Soundscape, duration: TimeInterval, volume: Float = 0.7) {
        self.presetID = presetID
        self.title = title
        self.soundscape = soundscape
        self.duration = min(max(duration, Self.minimumDuration), Self.maximumDuration)
        self.volume = min(max(volume, 0), 1)
    }

    init(preset: SessionPreset, minutes: Int? = nil, volume: Float = 0.7) {
        self.init(
            presetID: preset.id,
            title: preset.title,
            soundscape: preset.soundscape,
            duration: TimeInterval((minutes ?? preset.defaultMinutes) * 60),
            volume: volume
        )
    }
}
