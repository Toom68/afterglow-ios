import Foundation

/// Plays a `LightPlan`'s edges on a dedicated high-priority thread, so screen updates on the
/// main thread can never delay or swallow a flash.
///
/// Edges are played strictly in order. A late "on" edge still flashes, and its "off" edge waits
/// until the flash has lasted at least `minimumOnShare` of its intended length, so a hiccup
/// shortens one dark gap slightly instead of dropping a flash. Edge times are absolute, so a
/// late edge never shifts the ones after it.
final class TorchDriver: @unchecked Sendable {
    struct Stats: Hashable {
        /// Flashes delivered.
        var flashes = 0
        /// Flashes dropped because playback fell far behind (e.g. the app was suspended).
        var dropped = 0
        var maximumLateness: TimeInterval = 0
        var totalLateness: TimeInterval = 0
        /// Time the hardware took to accept torch commands.
        var commands = 0
        var totalCommandTime: TimeInterval = 0
        var maximumCommandTime: TimeInterval = 0
        /// Actual on-times of the most recent flashes, for the achieved rate.
        var recentFlashTimes: [TimeInterval] = []

        var averageLateness: TimeInterval { flashes > 0 ? totalLateness / Double(flashes) : 0 }
        var averageCommandTime: TimeInterval { commands > 0 ? totalCommandTime / Double(commands) : 0 }

        /// Flashes per second actually delivered over the last few flashes.
        var achievedRate: Double? {
            guard recentFlashTimes.count > 1, let first = recentFlashTimes.first, let last = recentFlashTimes.last, last > first else { return nil }
            return Double(recentFlashTimes.count - 1) / (last - first)
        }

        mutating func recordFlash(at time: TimeInterval) {
            recentFlashTimes.append(time)
            if recentFlashTimes.count > 21 { recentFlashTimes.removeFirst() }
        }
    }

    /// A flash always lasts at least this share of its planned length.
    static let minimumOnShare = 0.6
    /// Further behind than this, playback resynchronises to the current instant.
    static let resyncThreshold: TimeInterval = 0.5

    private let plan: LightPlan
    private let device: TorchDevice
    private let clock: () -> TimeInterval
    private let thermalState: () -> ProcessInfo.ThermalState
    private let startedAt: TimeInterval
    private let holdUntil: TimeInterval
    private let hardTimeout: TimeInterval
    private let ceiling: Float
    private let onStop: (TorchStopReason) -> Void

    /// Held while checking `cancelled` and while issuing a torch command, so once `cancel()`
    /// returns no command is in flight and none will follow.
    private let commandLock = NSLock()
    private let wake = DispatchSemaphore(value: 0)
    private var cancelled = false
    private var peak: Float
    private var currentLevel: Float = 0
    private var statsValue = Stats()

    var stats: Stats {
        commandLock.lock()
        defer { commandLock.unlock() }
        return statsValue
    }

    init(
        plan: LightPlan,
        device: TorchDevice,
        clock: @escaping () -> TimeInterval,
        thermalState: @escaping () -> ProcessInfo.ThermalState,
        startedAt: TimeInterval,
        holdUntil: TimeInterval,
        peak: Float,
        ceiling: Float,
        hardTimeout: TimeInterval,
        onStop: @escaping (TorchStopReason) -> Void
    ) {
        self.plan = plan
        self.device = device
        self.clock = clock
        self.thermalState = thermalState
        self.startedAt = startedAt
        self.holdUntil = holdUntil
        self.peak = peak
        self.ceiling = ceiling
        self.hardTimeout = hardTimeout
        self.onStop = onStop
    }

    func start() {
        let thread = Thread { [self] in run() }
        thread.name = "Afterglow torch"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Stops playback. On return, no torch command from this driver is running or pending.
    func cancel() {
        commandLock.lock()
        cancelled = true
        device.endExclusiveControl()
        commandLock.unlock()
        wake.signal()
    }

    func setPeak(_ level: Float) {
        commandLock.lock()
        peak = level
        commandLock.unlock()
    }

    private var elapsed: TimeInterval { clock() - startedAt }

    /// Sleeps until plan time `target`; returns false if cancelled meanwhile.
    private func wait(until target: TimeInterval) -> Bool {
        let delay = target - elapsed
        if delay > 0 { _ = wake.wait(timeout: .now() + delay) }
        commandLock.lock()
        let stop = cancelled
        commandLock.unlock()
        return !stop
    }

    private func finish(_ reason: TorchStopReason) {
        commandLock.lock()
        let alreadyCancelled = cancelled
        cancelled = true
        device.endExclusiveControl()
        commandLock.unlock()
        if !alreadyCancelled { onStop(reason) }
    }

    private func run() {
        commandLock.lock()
        if cancelled { commandLock.unlock(); return }
        // If the lock can't be held, every command simply locks on its own (slower, still works).
        try? device.beginExclusiveControl()
        commandLock.unlock()

        let edges = plan.edges
        // Skip edges inside the dark hold after a resume; the torch stays off until then.
        var index = edges.firstIndex { $0.time >= holdUntil - 1e-9 } ?? edges.count
        var lastOnActual: TimeInterval?
        var lastOnPlanned: TimeInterval = 0

        while index < edges.count {
            let edge = edges[index]
            var target = edge.time
            if edge.level == 0, let onActual = lastOnActual {
                target = max(target, onActual + (edge.time - lastOnPlanned) * Self.minimumOnShare)
            }
            guard wait(until: target) else { return }

            var now = elapsed
            if now - edge.time > Self.resyncThreshold {
                // Far behind (suspended or stalled): jump to the edge in force right now.
                let skipped = edges[index..<edges.count].prefix { $0.time <= now }
                let lit = skipped.filter { $0.level > 0 }.count
                index += max(skipped.count - 1, 0)
                commandLock.lock()
                statsValue.dropped += max(lit - (edges[index].level > 0 ? 1 : 0), 0)
                commandLock.unlock()
                now = elapsed
            }
            if now >= hardTimeout { return finish(.timeout) }
            if thermalState().rawValue >= ProcessInfo.ThermalState.serious.rawValue { return finish(.thermal) }

            let current = edges[index]
            commandLock.lock()
            if cancelled { commandLock.unlock(); return }
            var failure: TorchStopReason?
            if current.level > 0 {
                if !device.isTorchAvailable { failure = .failure(.torchUnavailable) }
                else if device.maxAvailableLevel <= 0 { failure = .thermal }
            }
            if failure == nil {
                let level = current.level > 0 ? current.level * min(ceiling, peak, device.maxAvailableLevel) : 0
                if level != currentLevel {
                    let commandStart = clock()
                    do {
                        try device.setLevel(level)
                        currentLevel = level
                    } catch {
                        failure = .failure(error as? TorchError ?? .configurationFailed(error.localizedDescription))
                    }
                    let commandTime = clock() - commandStart
                    statsValue.commands += 1
                    statsValue.totalCommandTime += commandTime
                    statsValue.maximumCommandTime = max(statsValue.maximumCommandTime, commandTime)
                }
                if failure == nil, current.level > 0 {
                    let lateness = max(0, now - current.time)
                    let onAt = elapsed
                    statsValue.flashes += 1
                    statsValue.totalLateness += lateness
                    statsValue.maximumLateness = max(statsValue.maximumLateness, lateness)
                    statsValue.recordFlash(at: onAt)
                    lastOnActual = onAt
                    lastOnPlanned = current.time
                }
            }
            commandLock.unlock()
            if let failure { return finish(failure) }
            index += 1
        }
        guard wait(until: plan.totalDuration) else { return }
        finish(.finished)
    }
}
