import Foundation

enum PauseReason: String, Codable, Hashable {
    /// The user tapped pause.
    case user
    /// The system interrupted audio (call, alarm, Siri, another app taking the audio session).
    case interruption
    /// The output route went away (e.g. headphones unplugged). Apple guidance is to pause.
    case routeChange
}

enum SessionOutcome: String, Codable, Hashable {
    case completed
    case endedEarly
    case interrupted
}

enum SessionPhase: Hashable {
    case idle
    case running
    case paused(PauseReason)
    case finished(SessionOutcome)

    var isActive: Bool {
        switch self {
        case .running, .paused: return true
        case .idle, .finished: return false
        }
    }

    var isRunning: Bool { self == .running }
}

/// Pure, clock-injected session timing state machine. All times are monotonic seconds supplied
/// by the caller, so it is deterministic and unit-testable. Invalid transitions are rejected
/// (return `false`) instead of corrupting state.
struct SessionTimeline: Hashable {
    let duration: TimeInterval
    private(set) var phase: SessionPhase = .idle
    private(set) var accumulated: TimeInterval = 0
    private(set) var runningSince: TimeInterval?

    init(duration: TimeInterval) {
        self.duration = max(0, duration)
    }

    func elapsed(at now: TimeInterval) -> TimeInterval {
        let live = runningSince.map { max(0, now - $0) } ?? 0
        return min(duration, accumulated + live)
    }

    func remaining(at now: TimeInterval) -> TimeInterval {
        max(0, duration - elapsed(at: now))
    }

    func progress(at now: TimeInterval) -> Double {
        duration > 0 ? elapsed(at: now) / duration : 1
    }

    @discardableResult
    mutating func start(at now: TimeInterval) -> Bool {
        guard phase == .idle else { return false }
        phase = .running
        runningSince = now
        accumulated = 0
        return true
    }

    @discardableResult
    mutating func pause(_ reason: PauseReason, at now: TimeInterval) -> Bool {
        guard phase == .running else {
            // A system interruption while already user-paused keeps the user reason.
            return false
        }
        if completeIfDue(at: now) { return false }
        accumulated = elapsed(at: now)
        runningSince = nil
        phase = .paused(reason)
        return true
    }

    @discardableResult
    mutating func resume(at now: TimeInterval) -> Bool {
        guard case .paused = phase else { return false }
        phase = .running
        runningSince = now
        return true
    }

    /// Advances the timeline; returns `true` exactly once, on the tick that completes the session.
    @discardableResult
    mutating func tick(at now: TimeInterval) -> Bool {
        guard phase == .running else { return false }
        return completeIfDue(at: now)
    }

    /// Ends the session early (user or unrecoverable failure). Returns `false` if not active.
    @discardableResult
    mutating func end(_ outcome: SessionOutcome, at now: TimeInterval) -> Bool {
        guard phase.isActive else { return false }
        accumulated = elapsed(at: now)
        runningSince = nil
        phase = .finished(accumulated >= duration ? .completed : outcome)
        return true
    }

    private mutating func completeIfDue(at now: TimeInterval) -> Bool {
        guard elapsed(at: now) >= duration else { return false }
        accumulated = duration
        runningSince = nil
        phase = .finished(.completed)
        return true
    }
}
