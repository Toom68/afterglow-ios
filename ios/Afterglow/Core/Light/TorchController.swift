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
        case .protocolRejected: return "This light sequence is not allowed in this build."
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
}

/// Controls only the torch: no frames are captured and no capture session is created.
final class SystemTorchDevice: TorchDevice {
    private let device: AVCaptureDevice?

    init(device: AVCaptureDevice? = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)) {
        self.device = device
    }

    var hasTorch: Bool { device?.hasTorch ?? false }
    var isTorchAvailable: Bool { device?.isTorchAvailable ?? false }
    var maxAvailableLevel: Float { AVCaptureDevice.maxAvailableTorchLevel }

    func setLevel(_ level: Float) throws {
        guard let device, device.hasTorch else { throw TorchError.noTorch }
        do {
            try device.lockForConfiguration()
        } catch {
            throw TorchError.configurationFailed(error.localizedDescription)
        }
        defer { device.unlockForConfiguration() }
        if level <= 0 {
            if device.torchMode != .off { device.torchMode = .off }
            return
        }
        guard device.isTorchAvailable else { throw TorchError.torchUnavailable }
        do {
            try device.setTorchModeOn(level: level)
        } catch {
            throw TorchError.configurationFailed(error.localizedDescription)
        }
    }
}

/// Single owner of torch playback. Runs one allowed `LightProtocol` with unvalidated engineering
/// bounds and an immediate stop request on every exit path. The bounds below limit glare, heat
/// and runaway timers; they are NOT a claim that any light exposure is safe. A stop is a software
/// request: if the off command fails it is reported via `offCommandError`, and behaviour after a
/// crash or OS-level failure can only be established on real hardware.
///
/// Timing: each level change is scheduled for its exact boundary, computed from the absolute
/// start time (no cumulative drift), on a strict zero-leeway main-queue timer. Requested times
/// are therefore close to nominal, but main-thread load, `lockForConfiguration` latency and the
/// LED driver add jitter that has NOT been measured. Only a photodiode can establish emitted
/// timing, brightness and stop latency.
@MainActor
final class TorchController {
    /// Unvalidated engineering ceiling on any requested torch level.
    nonisolated static let brightnessCeiling: Float = 0.2
    /// Unvalidated engineering limit on the light part of any protocol.
    nonisolated static let maximumLightDuration: TimeInterval = 5 * 60
    /// Absolute wall-clock watchdog for a run, regardless of the protocol.
    nonisolated static let hardTimeout: TimeInterval = 10 * 60
    /// Shortest step accepted (main-thread scheduling resolution), not an exposure bound.
    nonisolated static let minimumStepDuration: TimeInterval = 0.1

    private(set) var isRunning = false
    private(set) var lastStopReason: TorchStopReason?
    private(set) var currentLevel: Float = 0
    private(set) var protocolInUse: LightProtocol?
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
    private var timer: DispatchSourceTimer?
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
        timer?.cancel()
        watchdog?.cancel()
        try? device.setLevel(0)
        for observer in observers { center.removeObserver(observer) }
    }

    /// Starts `light` only if it is in `allowedCatalog` and well formed. Throws configuration
    /// errors synchronously; an off request has been issued whenever this throws (check
    /// `offCommandError` to see whether it was accepted).
    func start(_ light: LightProtocol, allowedCatalog: [LightProtocol] = LightProtocolCatalog.available) throws {
        hardStop(.requested, notify: false)
        guard allowedCatalog.contains(light),
              light.isWellFormed(minimumStepDuration: Self.minimumStepDuration, levelCeiling: Self.brightnessCeiling, maximumLightDuration: Self.maximumLightDuration)
        else { throw TorchError.protocolRejected }
        guard device.hasTorch else { throw TorchError.noTorch }
        guard device.isTorchAvailable else { throw TorchError.torchUnavailable }
        guard thermalState().rawValue < ProcessInfo.ThermalState.serious.rawValue else { throw TorchError.thermal }

        // Prove the torch can be commanded off before ever turning it on.
        if let offCommandError { throw offCommandError }

        generation += 1
        protocolInUse = light
        startedAt = clock()
        isRunning = true
        lastStopReason = nil
        observeInterruptions()
        armWatchdog()
        step()
        if !isRunning, case .failure(let error)? = lastStopReason { throw error }
    }

    /// Cancels all pending callbacks, then requests torch off. Idempotent.
    func hardStop(_ reason: TorchStopReason = .requested) {
        hardStop(reason, notify: true)
    }

    /// Applies the level for the current instant and schedules the next boundary. Exposed so
    /// tests (and a stalled timer) can drive it; calling it early or late is harmless.
    func step() {
        guard isRunning, let light = protocolInUse else { return }
        let elapsed = clock() - startedAt
        if elapsed >= Self.hardTimeout { return hardStop(.timeout) }
        if thermalState().rawValue >= ProcessInfo.ThermalState.serious.rawValue { return hardStop(.thermal) }
        guard let relative = light.relativeLevel(at: elapsed) else { return hardStop(.finished) }
        if relative > 0 {
            guard device.isTorchAvailable else { return hardStop(.failure(.torchUnavailable)) }
            // An adapter may withdraw its request cap; stop rather than compensate.
            guard device.maxAvailableLevel > 0 else { return hardStop(.thermal) }
        }
        let ceiling = min(Self.brightnessCeiling, light.peakTorchLevel, device.maxAvailableLevel)
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
        guard let boundary = light.nextBoundary(after: elapsed) else { return hardStop(.finished) }
        schedule(at: boundary)
    }

    private func schedule(at boundary: TimeInterval) {
        timer?.cancel()
        timer = nil
        guard schedulesTimers else { return }
        let delay = max(0, boundary - (clock() - startedAt))
        let token = generation
        let source = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        source.schedule(deadline: .now() + delay, leeway: .nanoseconds(0))
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == token else { return }
                self.step()
            }
        }
        timer = source
        source.resume()
    }

    private func armWatchdog() {
        watchdog?.cancel()
        watchdog = nil
        guard schedulesTimers, let light = protocolInUse else { return }
        // Fires slightly after the protocol should have ended, in case step scheduling stalls.
        let limit = min(Self.hardTimeout, light.totalDuration + 1)
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
        timer?.cancel()
        timer = nil
        watchdog?.cancel()
        watchdog = nil
        isRunning = false
        protocolInUse = nil
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
        currentLevel = 0
        guard wasRunning else { return }
        lastStopReason = reason
        if notify { onStop?(reason) }
    }

    private func observeInterruptions() {
        let stopForThermal: (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.thermalState().rawValue >= ProcessInfo.ThermalState.serious.rawValue {
                    self.hardStop(.thermal)
                }
            }
        }
        observers.append(center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main, using: stopForThermal))
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
