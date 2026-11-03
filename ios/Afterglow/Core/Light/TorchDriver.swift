import Foundation

/// Serial API-command playback on a dedicated thread. Command returns are not optical
/// measurements. Overruns stop playback rather than compressing later on/off intervals.
final class TorchDriver: @unchecked Sendable {
    struct Stats: Hashable {
        /// Successful positive API requests, timestamped after return (not optical flashes).
        var flashes = 0
        /// Planned positive edges left unissued at termination.
        var dropped = 0
        var maximumLateness: TimeInterval = 0
        var totalLateness: TimeInterval = 0
        var commands = 0
        var totalCommandTime: TimeInterval = 0
        var maximumCommandTime: TimeInterval = 0
        var recentFlashTimes: [TimeInterval] = []
        var averageLateness: TimeInterval { flashes > 0 ? totalLateness / Double(flashes) : 0 }
        var averageCommandTime: TimeInterval { commands > 0 ? totalCommandTime / Double(commands) : 0 }
        /// Rate of successful positive API-command returns, never measured LED rate.
        var achievedRate: Double? {
            guard recentFlashTimes.count > 1, let first = recentFlashTimes.first, let last = recentFlashTimes.last, last > first else { return nil }
            return Double(recentFlashTimes.count - 1) / (last - first)
        }
        mutating func recordFlash(at time: TimeInterval) {
            recentFlashTimes.append(time)
            if recentFlashTimes.count > 21 { recentFlashTimes.removeFirst() }
        }
    }

    private let plan: LightPlan
    private let device: TorchDevice
    private let clock: () -> TimeInterval
    private let thermalState: () -> ProcessInfo.ThermalState
    private let startedAt: TimeInterval
    private let holdUntil: TimeInterval
    private let hardTimeout: TimeInterval
    private let ceiling: Float
    private let onStop: (TorchStopReason) -> Void
    /// Deterministic test seam; production waits use the cancellation semaphore.
    private let waitForDelay: ((TimeInterval) -> Void)?
    /// Never held across hardware access. UI reads and brightness updates only take this lock.
    private let state = NSCondition()
    private let wake = DispatchSemaphore(value: 0)
    private var cancelled = false
    private var started = false
    private var completed = false
    private var peak: Float
    private var statsValue = Stats()
    private var offError: TorchError?

    var stats: Stats {
        state.lock(); defer { state.unlock() }
        return statsValue
    }
    var offCommandError: TorchError? {
        state.lock(); defer { state.unlock() }
        return offError
    }

    init(plan: LightPlan, device: TorchDevice, clock: @escaping () -> TimeInterval,
         thermalState: @escaping () -> ProcessInfo.ThermalState, startedAt: TimeInterval,
         holdUntil: TimeInterval, peak: Float, ceiling: Float, hardTimeout: TimeInterval,
         waitForDelay: ((TimeInterval) -> Void)? = nil,
         onStop: @escaping (TorchStopReason) -> Void) {
        self.plan = plan
        self.device = device
        self.clock = clock
        self.thermalState = thermalState
        self.startedAt = startedAt
        self.holdUntil = holdUntil
        self.peak = peak
        self.ceiling = ceiling
        self.hardTimeout = hardTimeout
        self.waitForDelay = waitForDelay
        self.onStop = onStop
    }

    func start() {
        state.lock()
        guard !started else { state.unlock(); return }
        started = true
        state.unlock()
        let thread = Thread { [self] in run() }
        thread.name = "Afterglow torch"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Requests cancellation without waiting for an in-flight hardware operation.
    func requestCancel() {
        state.lock(); cancelled = true; state.unlock()
        wake.signal()
    }

    /// Serialized shutdown barrier used before reusing hardware. Can wait for an in-flight
    /// platform call; stats and setPeak remain available while it waits.
    func cancel() {
        requestCancel()
        state.lock()
        while started && !completed { state.wait() }
        state.unlock()
    }

    func setPeak(_ level: Float) {
        guard level.isFinite, level > 0 else { return }
        state.lock(); peak = min(level, ceiling); state.unlock()
    }

    private var elapsed: TimeInterval { clock() - startedAt }
    private var isCancelled: Bool {
        state.lock(); defer { state.unlock() }
        return cancelled
    }
    private func wait(until target: TimeInterval) -> Bool {
        let delay = min(target, plan.totalDuration, hardTimeout) - elapsed
        if delay > 0 {
            if let waitForDelay { waitForDelay(delay) }
            else { _ = wake.wait(timeout: .now() + delay) }
        }
        return !isCancelled
    }

    /// Always executes on the playback thread, before releasing exclusive control or calling
    /// out. An off rejection survives later controller retries through offCommandError.
    private func finish(_ reason: TorchStopReason, remainingFrom index: Int) {
        var error = offCommandError
        for _ in 0..<2 {
            do { try device.setLevel(0); break }
            catch let failure { error = failure as? TorchError ?? .configurationFailed(failure.localizedDescription) }
        }
        device.endExclusiveControl()
        state.lock()
        offError = error
        statsValue.dropped += plan.edges.dropFirst(index).filter { $0.level > 0 && $0.time >= holdUntil - 1e-9 }.count
        let shouldNotify = !cancelled
        completed = true
        state.broadcast()
        state.unlock()
        if shouldNotify { onStop(reason) }
    }

    private func run() {
        var index = plan.edges.firstIndex { $0.time >= holdUntil - 1e-9 } ?? plan.edges.count
        var reason: TorchStopReason = .finished
        defer { finish(reason, remainingFrom: index) }
        guard !isCancelled else { return }
        do { try device.beginExclusiveControl() }
        catch { reason = .failure(error as? TorchError ?? .configurationFailed(error.localizedDescription)); return }
        // The next edge may not shorten the planned interval measured from the previous
        // command's return. If it cannot fit, stop; never replay a backlog of stale edges.
        var previousReturn: TimeInterval?
        var previousPlanned: TimeInterval?
        while index < plan.edges.count {
            let edge = plan.edges[index]
            var target = edge.time
            if let previousReturn, let previousPlanned {
                target = max(target, previousReturn + edge.time - previousPlanned)
            }
            guard wait(until: target) else { return }
            if elapsed >= hardTimeout { reason = .timeout; return }
            if elapsed >= plan.totalDuration { return }
            if thermalState().rawValue >= ProcessInfo.ThermalState.serious.rawValue { reason = .thermal; return }
            // A full planned interval behind is an overrun, including after blocked commands.
            let end = index + 1 < plan.edges.count ? plan.edges[index + 1].time : plan.totalDuration
            if elapsed >= end { reason = .cannotKeepUp; return }
            if edge.level > 0 {
                guard device.isTorchAvailable else { reason = .failure(.torchUnavailable); return }
                guard device.maxAvailableLevel > 0 else { reason = .thermal; return }
            }
            state.lock(); let selectedPeak = peak; state.unlock()
            let level = edge.level > 0 ? edge.level * min(ceiling, selectedPeak, device.maxAvailableLevel) : 0
            // Device capability queries can also stall. Recheck immediately before admission.
            guard !isCancelled else { return }
            if elapsed >= hardTimeout { reason = .timeout; return }
            if elapsed >= plan.totalDuration { return }
            if elapsed >= end { reason = .cannotKeepUp; return }
            let commandStart = clock()
            do { try device.setLevel(level) }
            catch {
                let failure = error as? TorchError ?? .configurationFailed(error.localizedDescription)
                if level == 0 { state.lock(); offError = failure; state.unlock() }
                reason = .failure(failure)
                return
            }
            let returnedAt = elapsed
            let commandTime = max(0, clock() - commandStart)
            state.lock()
            statsValue.commands += 1
            statsValue.totalCommandTime += commandTime
            statsValue.maximumCommandTime = max(statsValue.maximumCommandTime, commandTime)
            if level > 0 {
                let lateness = max(0, returnedAt - edge.time)
                statsValue.flashes += 1
                statsValue.totalLateness += lateness
                statsValue.maximumLateness = max(statsValue.maximumLateness, lateness)
                statsValue.recordFlash(at: returnedAt)
            }
            state.unlock()
            previousReturn = returnedAt
            previousPlanned = edge.time
            index += 1
            if returnedAt >= hardTimeout { reason = .timeout; return }
            if returnedAt >= plan.totalDuration { return }
            if returnedAt >= end { reason = .cannotKeepUp; return }
        }
        if !wait(until: plan.totalDuration) { return }
        if elapsed >= hardTimeout { reason = .timeout }
    }
}
