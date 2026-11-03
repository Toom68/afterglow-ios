import Foundation

struct SessionRecord: Identifiable, Codable, Hashable {
    /// Sessions shorter than this that were not completed are treated as accidental and not saved.
    static let minimumRecordedDuration: TimeInterval = 30

    var id: UUID
    var presetID: String
    var title: String
    var soundscape: Soundscape
    var startedAt: Date
    var plannedDuration: TimeInterval
    var listenedDuration: TimeInterval
    var outcome: SessionOutcome

    init(
        id: UUID = UUID(),
        presetID: String,
        title: String,
        soundscape: Soundscape,
        startedAt: Date,
        plannedDuration: TimeInterval,
        listenedDuration: TimeInterval,
        outcome: SessionOutcome
    ) {
        self.id = id
        self.presetID = presetID
        self.title = title
        self.soundscape = soundscape
        self.startedAt = startedAt
        self.plannedDuration = max(0, plannedDuration)
        self.listenedDuration = min(max(0, listenedDuration), max(0, plannedDuration))
        self.outcome = outcome
    }

    var isWorthRecording: Bool {
        outcome == .completed || listenedDuration >= Self.minimumRecordedDuration
    }
}

enum Mood: Int, Codable, CaseIterable, Identifiable, Hashable {
    case heavy = 1
    case unsettled
    case neutral
    case settled
    case bright

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .heavy: return "Heavy"
        case .unsettled: return "Unsettled"
        case .neutral: return "Neutral"
        case .settled: return "Settled"
        case .bright: return "Bright"
        }
    }

    var symbolName: String {
        switch self {
        case .heavy: return "cloud.rain"
        case .unsettled: return "wind"
        case .neutral: return "circle"
        case .settled: return "leaf"
        case .bright: return "sun.max"
        }
    }
}

struct JournalEntry: Identifiable, Codable, Hashable {
    static let maximumLength = 10_000

    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var sessionID: UUID?
    var mood: Mood?
    var text: String

    init(id: UUID = UUID(), createdAt: Date = Date(), sessionID: UUID? = nil, mood: Mood? = nil, text: String) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.sessionID = sessionID
        self.mood = mood
        self.text = JournalEntry.sanitize(text)
    }

    static func sanitize(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumLength))
    }

    var isEmpty: Bool { text.isEmpty && mood == nil }
}

struct HistoryStats: Hashable {
    var totalSessions: Int
    var completedSessions: Int
    var totalMinutes: Int
    var currentStreakDays: Int

    static let empty = HistoryStats(totalSessions: 0, completedSessions: 0, totalMinutes: 0, currentStreakDays: 0)

    /// A streak counts consecutive calendar days with at least one saved session, ending today,
    /// or ending yesterday if nothing has been done yet today.
    static func compute(sessions: [SessionRecord], now: Date = Date(), calendar: Calendar = .current) -> HistoryStats {
        let totalSeconds = sessions.reduce(0) { $0 + $1.listenedDuration }
        let days = Set(sessions.map { calendar.startOfDay(for: $0.startedAt) })
        var streak = 0
        var cursor = calendar.startOfDay(for: now)
        if !days.contains(cursor), let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) {
            cursor = yesterday
        }
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return HistoryStats(
            totalSessions: sessions.count,
            completedSessions: sessions.filter { $0.outcome == .completed }.count,
            totalMinutes: Int((totalSeconds / 60).rounded(.down)),
            currentStreakDays: streak
        )
    }
}

/// On-disk format. `version` lets future releases migrate without losing user data.
struct HistoryArchive: Codable, Hashable {
    static let currentVersion = 1

    var version: Int = HistoryArchive.currentVersion
    var sessions: [SessionRecord] = []
    var journal: [JournalEntry] = []
}
