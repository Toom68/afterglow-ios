import AVFoundation
import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum TorchError: LocalizedError, Hashable {
    case noTorch
    case torchUnavailable
    case configurationFailed(String)
    case protocolRejected
    case thermal

    var errorDescription: String? {
        switch self {
        case .noTorch: return "This device has no usable flashlight (the Simulator never does)."
        case .torchUnavailable: return "The flashlight is in use or temporarily unavailable."
        case .configurationFailed(let detail): return "The flashlight could not be configured: \(detail)"
        case .protocolRejected: return "This light program is outside the allowed limits."
        case .thermal: return "Light stopped because the device is getting warm."
        }
    }
}

enum TorchStopReason: Hashable {
    case finished
    case requested
    case timeout
    case appInactive
    case thermal
    case cannotKeepUp
    case failure(TorchError)
}

/// Hardware seam so the controller can be tested without a camera.
protocol TorchDevice: AnyObject {
    var hasTorch: Bool { get }
    var isTorchAvailable: Bool { get }
    /// Adapter request cap used by the controller and test doubles. The system adapter returns
    /// Apple's maximum-level request sentinel, not measured dynamic output or thermal telemetry.
    var maxAvailableLevel: Float { get }
    /// Level 0 turns the torch off.
    func setLevel(_ level: Float) throws
    /// Holds the hardware configuration lock across many `setLevel` calls, so fast flashing
    /// doesn't pay the lock/unlock cost on every edge. Balanced by `endExclusiveControl()`.
    func beginExclusiveControl() throws
    func endExclusiveControl()
}

extension TorchDevice {
    func beginExclusiveControl() throws {}
    func endExclusiveControl() {}
}

/// Controls only the torch: no frames are captured and no capture session is created.
/// Not internally synchronised: callers serialise access (see `TorchDriver`).
final class SystemTorchDevice: TorchDevice, @unchecked Sendable {
    private let device: AVCaptureDevice?
    private var holdsLock = false

    init(device: AVCaptureDevice? = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)) {
        self.device = device
    }

    var hasTorch: Bool { device?.hasTorch ?? false }
    var isTorchAvailable: Bool { device?.isTorchAvailable ?? false }
    var maxAvailableLevel: Float { AVCaptureDevice.maxAvailableTorchLevel }

    func beginExclusiveControl() throws {
        guard let device, !holdsLock else { return }
        do {
            try device.lockForConfiguration()
        } catch {
            throw TorchError.configurationFailed(error.localizedDescription)
        }
        holdsLock = true
    }

    func endExclusiveControl() {
        guard let device, holdsLock else { return }
        holdsLock = false
        device.unlockForConfiguration()
    }

    func setLevel(_ level: Float) throws {
        guard let device, device.hasTorch else { throw TorchError.noTorch }
        let lockedHere = !holdsLock
        if lockedHere {
            do {
                try device.lockForConfiguration()
            } catch {
                throw TorchError.configurationFailed(error.localizedDescription)
            }
        }
        defer { if lockedHere { device.unlockForConfiguration() } }
        if level <= 0 {
            if device.torchMode != .off { device.torchMode = .off }
            return
        }
        guard device.isTorchAvailable else { throw TorchError.torchUnavailable }
        // Use Apple's explicit-level API for every positive request. Plain .on toggles
        // have no verified amplitude-preservation contract on our supported devices.
        do {
            try device.setTorchModeOn(level: Self.requestLevel(level))
        } catch {
            throw TorchError.configurationFailed(error.localizedDescription)
        }
    }

    /// No minimum or rounding step: sub-5% fades must not exceed the selected request.
    /// Unsupported positive requests are reported as errors by the platform, never raised.
    static func requestLevel(_ level: Float) -> Float {
        guard level.isFinite else { return 0 }
        return min(max(level, 0), 1)
    }
}

/// Single owner of torch playback. Runs one `LightPlan` within `LightBounds` and issues an
/// immediate stop request on every exit path. A stop is a software request: if the off command
/// fails it is reported via `offCommandError`.
///
/// API commands run on a dedicated thread. Scheduling and platform latency can cause an
/// overrun stop; neither software timestamps nor command success measure optical output.
@MainActor
final class TorchController {
    nonisolated static let bounds = LightBounds.standard
    /// Absolute watchdog on the plan clock, regardless of the plan.
    nonisolated static let hardTimeout: TimeInterval = LightBounds.standard.maximumLightDuration + 5 * 60

    private(set) var isRunning = false
    private(set) var lastStopReason: TorchStopReason?
    private(set) var currentLevel: Float = 0
    private(set) var planInUse: LightPlan?
    /// Plan time (seconds from session start) the torch is currently at, while running.
    var planElapsed: TimeInterval? { isRunning ? clock() - startedAt : nil }
    /// Set when the most recent off request was rejected by the hardware, i.e. the light may
    /// still be on. Cleared by the next successful off request.
    private(set) var offCommandError: TorchError?
    var onStop: (@MainActor (TorchStopReason) -> Void)?

    private let device: TorchDevice
    private let clock: () -> TimeInterval
    private let center: NotificationCenter
    private let thermalState: () -> ProcessInfo.ThermalState
    private let schedulesTimers: Bool
    private var startedAt: TimeInterval = 0
    /// Plan time before which the torch is held off (a dark pause after resuming).
    private var holdUntil: TimeInterval = 0
    private var peakOverride: Float?
    private var driver: TorchDriver?
    private var watchdog: DispatchSourceTimer?
    /// Incremented on every start/stop so a timer event from an earlier run is ignored.
    private var generation = 0
    private var observers: [NSObjectProtocol] = []

    init(
        device: TorchDevice = SystemTorchDevice(),
        clock: @escaping () -> TimeInterval = MonotonicClock.now,
        thermalState: @escaping () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState },
        notificationCenter: NotificationCenter = .default,
        schedulesTimers: Bool = true
    ) {
        self.device = device
        self.clock = clock
        self.thermalState = thermalState
        center = notificationCenter
        self.schedulesTimers = schedulesTimers
    }

    deinit {
        driver?.cancel()
        watchdog?.cancel()
        try? device.setLevel(0)
        for observer in observers { center.removeObserver(observer) }
    }

    /// Starts `plan` at plan time `offset` (session seconds already elapsed), keeping the torch
    /// dark for `holdOff` seconds first. Throws configuration errors synchronously; an off
    /// request has been issued whenever this throws (check `offCommandError`).
    func start(_ plan: LightPlan, at offset: TimeInterval = 0, holdOff: TimeInterval = 0) throws {
        hardStop(.requested, notify: false)
        guard plan.isWellFormed(bounds: Self.bounds), offset.isFinite, holdOff.isFinite,
              offset < plan.totalDuration
        else { throw TorchError.protocolRejected }
        guard device.hasTorch else { throw TorchError.noTorch }
        guard device.isTorchAvailable else { throw TorchError.torchUnavailable }
        guard thermalState().rawValue < ProcessInfo.ThermalState.serious.rawValue else { throw TorchError.thermal }

        // Prove the torch can be commanded off before ever turning it on.
        if let offCommandError { throw offCommandError }

        generation += 1
        planInUse = plan
        peakOverride = nil
        let hold = max(0, holdOff)
        let start = max(0, offset)
        startedAt = clock() + hold - start
        holdUntil = start
        isRunning = true
        lastStopReason = nil
        observeInterruptions()
        armWatchdog()
        if schedulesTimers {
            startDriver(plan: plan)
        } else {
            step()
            if !isRunning, case .failure(let error)? = lastStopReason { throw error }
        }
    }

    /// Changes the brightness of the running plan from its next flash onward.
    func setPeakLevel(_ level: Float) {
        guard isRunning, level.isFinite, level > 0 else { return }
        peakOverride = min(level, Self.bounds.brightnessCeiling)
        driver?.setPeak(min(level, Self.bounds.brightnessCeiling))
    }

    /// API-command timing recorded by the playback thread, not optical measurements.
    var timingStats: TorchDriver.Stats? { driver?.stats }

    /// Cancels all pending callbacks, then requests torch off. Idempotent.
    func hardStop(_ reason: TorchStopReason = .requested) {
        hardStop(reason, notify: true)
    }

    /// Applies the level for the current instant. Used instead of the playback thread when
    /// `schedulesTimers` is false, so unit tests can drive time deterministically.
    func step() {
        guard isRunning, let plan = planInUse else { return }
        let elapsed = clock() - startedAt
        if elapsed >= Self.hardTimeout { return hardStop(.timeout) }
        if thermalState().rawValue >= ProcessInfo.ThermalState.serious.rawValue { return hardStop(.thermal) }
        guard let planned = plan.relativeLevel(at: elapsed) else { return hardStop(.finished) }
        let relative = elapsed < holdUntil ? 0 : planned
        var adapterCap: Float = 0
        if relative > 0 {
            guard device.isTorchAvailable else { return hardStop(.failure(.torchUnavailable)) }
            adapterCap = device.maxAvailableLevel
            guard adapterCap.isFinite, adapterCap > 0 else { return hardStop(.thermal) }
            let admissionTime = clock() - startedAt
            if admissionTime >= Self.hardTimeout { return hardStop(.timeout) }
            if admissionTime >= plan.totalDuration { return hardStop(.finished) }
            if thermalState().rawValue >= ProcessInfo.ThermalState.serious.rawValue { return hardStop(.thermal) }
            if admissionTime >= (plan.nextBoundary(after: elapsed) ?? plan.totalDuration) { return hardStop(.cannotKeepUp) }
        }
        let ceiling = min(Self.bounds.brightnessCeiling, peakOverride ?? plan.peakTorchLevel, adapterCap)
        let level = relative <= 0 ? 0 : relative * ceiling
        if level != currentLevel {
            do {
                try device.setLevel(level)
                currentLevel = level
            } catch let error as TorchError {
                return hardStop(.failure(error))
            } catch {
                return hardStop(.failure(.configurationFailed(error.localizedDescription)))
            }
        }
        if plan.nextBoundary(after: elapsed) == nil { return hardStop(.finished) }
    }

    /// Hands playback to a dedicated thread; its stop reasons come back on the main actor.
    private func startDriver(plan: LightPlan) {
        let token = generation
        let driver = TorchDriver(
            plan: plan,
            device: device,
            clock: clock,
            thermalState: thermalState,
            startedAt: startedAt,
            holdUntil: holdUntil,
            peak: plan.peakTorchLevel,
            ceiling: Self.bounds.brightnessCeiling,
            hardTimeout: Self.hardTimeout,
            onStop: { [weak self] reason in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.generation == token, self.isRunning else { return }
                        self.hardStop(reason)
                    }
                }
            }
        )
        self.driver = driver
        driver.start()
    }

    private func armWatchdog() {
        watchdog?.cancel()
        watchdog = nil
        guard schedulesTimers, let plan = planInUse else { return }
        // Fires slightly after the plan should have ended, in case step scheduling stalls.
        let limit = min(Self.hardTimeout, plan.totalDuration - (clock() - startedAt) + 1)
        let token = generation
        let source = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        source.schedule(deadline: .now() + limit, leeway: .milliseconds(10))
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == token, self.isRunning else { return }
                self.hardStop(.timeout)
            }
        }
        watchdog = source
        source.resume()
    }

    private func hardStop(_ reason: TorchStopReason, notify: Bool) {
        let wasRunning = isRunning
        generation += 1
        // Join serialized worker shutdown before reusing the hardware. Hardware calls have
        // no bounded latency; UI stats and brightness state use a separate lock.
        driver?.cancel()
        let workerOffError = driver?.offCommandError
        driver = nil
        watchdog?.cancel()
        watchdog = nil
        isRunning = false
        planInUse = nil
        for observer in observers { center.removeObserver(observer) }
        observers.removeAll()
        // Always request off, even if we believe it is already off, and retry once.
        offCommandError = nil
        for attempt in 1...2 {
            do {
                try device.setLevel(0)
                offCommandError = nil
                break
            } catch {
                offCommandError = error as? TorchError ?? .configurationFailed(error.localizedDescription)
                if attempt == 2 { break }
            }
        }
        // A successful cleanup retry must not erase an earlier worker off rejection before
        // SessionPlayer has had the chance to persist its shutdown warning.
        if let workerOffError { offCommandError = workerOffError }
        currentLevel = 0
        guard wasRunning else { return }
        lastStopReason = reason
        if notify { onStop?(reason) }
    }

    private func observeInterruptions() {
        observers.append(center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.thermalState().rawValue >= ProcessInfo.ThermalState.serious.rawValue {
                    self.hardStop(.thermal)
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hardStop(.requested) }
        })
        #if canImport(UIKit)
        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification, UIApplication.willTerminateNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.hardStop(.appInactive) }
            })
        }
        #endif
    }
}
