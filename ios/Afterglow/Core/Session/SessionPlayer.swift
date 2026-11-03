import AVFoundation
import Combine
import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum SessionNotice: Hashable, Identifiable {
    case interrupted
    case headphonesDisconnected
    case audioUnavailable(String)
    case thermalWarning
    case lightStopped(String)
    case lightUnavailable(String)

    var id: String {
        switch self {
        case .interrupted: return "interrupted"
        case .headphonesDisconnected: return "headphones"
        case .audioUnavailable: return "audio"
        case .thermalWarning: return "thermal"
        case .lightStopped: return "light"
        case .lightUnavailable: return "light-unavailable"
        }
    }

    var message: String {
        switch self {
        case .interrupted:
            return "Your session was paused by another sound on your device. Resume whenever you're ready."
        case .headphonesDisconnected:
            return "Headphones disconnected, so the session paused."
        case .audioUnavailable(let detail):
            return "Sound isn't available right now. \(detail)"
        case .thermalWarning:
            return "Your device is getting warm. Afterglow has paused to let it cool down."
        case .lightStopped(let detail):
            return "Light turned off. \(detail)"
        case .lightUnavailable(let detail):
            return detail
        }
    }
}

/// Owns one meditation session at a time: timing, audio, system interruptions and history.
/// All lifecycle edges (pause, resume, completion, early end, interruption, route loss, thermal
/// pressure, termination) converge on a few private methods so cleanup is never skipped.
@MainActor
final class SessionPlayer: ObservableObject {
    @Published private(set) var phase: SessionPhase = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var configuration: SessionConfiguration?
    @Published private(set) var notice: SessionNotice?
    @Published private(set) var lastRecord: SessionRecord?

    var duration: TimeInterval { configuration?.duration ?? 0 }
    var remaining: TimeInterval { max(0, duration - elapsed) }
    var progress: Double { duration > 0 ? min(1, elapsed / duration) : 0 }
    /// True only while the torch is actually being driven for this session.
    @Published private(set) var isLightActive = false
    /// Set whenever the hardware rejected a torch-off request, so the light may still be on.
    /// Persistent: start, reset, notices and their dismissal never clear it; only
    /// `acknowledgeLightShutdownWarning()` (the user confirming the torch is off) does. While set,
    /// no new light run can start.
    @Published private(set) var lightShutdownWarning: String?

    private let history: HistoryStore
    private let audio: AmbientAudioControlling
    private let clock: () -> TimeInterval
    private let wallClock: () -> Date
    private let thermalState: () -> ProcessInfo.ThermalState
    private let center: NotificationCenter
    private let usesTimer: Bool
    private let nowPlaying: NowPlayingController?
    private var timeline: SessionTimeline?
    private var startedAt: Date?
    private var ticker: Timer?
    private var observers: [NSObjectProtocol] = []
    private var torch: TorchController?
    private var lightUsedThisSession = false
    private let makeTorch: @MainActor () -> TorchController
    private let lightCatalog: [LightProtocol]
    private let lightBuildEnabled: Bool

    init(
        history: HistoryStore,
        audio: AmbientAudioControlling? = nil,
        clock: @escaping () -> TimeInterval = MonotonicClock.now,
        wallClock: @escaping () -> Date = Date.init,
        thermalState: @escaping () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState },
        notificationCenter: NotificationCenter = .default,
        usesTimer: Bool = true,
        integratesWithSystemMedia: Bool = true,
        lightCatalog: [LightProtocol] = LightProtocolCatalog.available,
        lightBuildEnabled: Bool = LightFeature.buildAllowsLight,
        makeTorch: (@MainActor () -> TorchController)? = nil
    ) {
        self.history = history
        self.audio = audio ?? AmbientAudioEngine(notificationCenter: notificationCenter)
        self.clock = clock
        self.wallClock = wallClock
        self.thermalState = thermalState
        center = notificationCenter
        self.usesTimer = usesTimer
        self.lightCatalog = lightCatalog
        self.lightBuildEnabled = lightBuildEnabled
        self.makeTorch = makeTorch ?? { TorchController(clock: clock, thermalState: thermalState, notificationCenter: notificationCenter) }
        nowPlaying = integratesWithSystemMedia ? NowPlayingController() : nil
        nowPlaying?.onPlay = { [weak self] in self?.resume() }
        nowPlaying?.onPause = { [weak self] in self?.pause() }
        self.audio.onUnexpectedStop = { [weak self] detail in
            guard let self else { return }
            Task { @MainActor in self.systemPause(.interruption, notice: .audioUnavailable(detail)) }
        }
        observeSystemEvents()
    }

    deinit {
        ticker?.invalidate()
        for observer in observers { center.removeObserver(observer) }
    }

    // MARK: - Public controls

    func start(_ configuration: SessionConfiguration) {
        if phase.isActive { finish(.endedEarly) }
        notice = nil
        lastRecord = nil
        guard thermalState() != .critical else {
            notice = .thermalWarning
            return
        }
        do {
            try audio.prepare(soundscape: configuration.soundscape, volume: configuration.volume, mixWithOthers: configuration.mixWithOtherAudio)
            try audio.play(fadeIn: 3)
        } catch {
            audio.stop()
            timeline = nil
            self.configuration = nil
            sync()
            notice = .audioUnavailable(error.localizedDescription)
            return
        }
        discardTorch()
        lightUsedThisSession = false
        var timeline = SessionTimeline(duration: configuration.duration)
        timeline.start(at: clock())
        self.timeline = timeline
        self.configuration = configuration
        startedAt = wallClock()
        sync()
        startTicker()
        if configuration.useExperimentalLight {
            if let reason = startLight(protocolID: configuration.lightProtocolID) {
                notice = .lightUnavailable(reason.message)
            }
        }
    }

    func pause() {
        pauseSession(.user, fadeOut: 0.8, notice: nil)
    }

    func resume() {
        guard var timeline, case .paused = timeline.phase else { return }
        guard thermalState() != .critical else {
            notice = .thermalWarning
            return
        }
        do {
            try audio.play(fadeIn: 1.5)
        } catch {
            notice = .audioUnavailable(error.localizedDescription)
            return
        }
        timeline.resume(at: clock())
        self.timeline = timeline
        notice = nil
        sync()
        startTicker()
    }

    /// Ends the session before its planned duration. Saved to history if long enough.
    func end() {
        finish(.endedEarly)
    }

    /// Returns to idle after a finished session (or abandons an active one).
    func reset() {
        if phase.isActive { finish(.endedEarly) }
        timeline = nil
        configuration = nil
        startedAt = nil
        lastRecord = nil
        notice = nil
        sync()
    }

    func setVolume(_ volume: Float) {
        configuration?.volume = min(max(volume, 0), 1)
        audio.setVolume(volume)
    }

    func dismissNotice() {
        notice = nil
    }

    /// Advances time; call sites include the internal ticker, foreground re-entry and tests.
    func tick() {
        guard var timeline else { return }
        let completed = timeline.tick(at: clock())
        self.timeline = timeline
        if completed {
            complete()
        } else {
            sync()
        }
    }

    // MARK: - Light (research builds only)

    /// Starts the torch for the running session. `start(_:)` calls this when the configuration
    /// has `useExperimentalLight`, which the UI sets only after this session's screening and
    /// consent. Returns why light cannot run, or nil once the torch is on. Light never restarts
    /// by itself: after any stop it stays off until a new session is deliberately started.
    @discardableResult
    func startLight(protocolID: String?) -> LightUnavailableReason? {
        guard phase == .running else { return .sessionNotRunning }
        // Only a configuration the UI built after this session's screening and consent may light.
        guard configuration?.useExperimentalLight == true else { return .consentMissing }
        guard !lightUsedThisSession else { return .alreadyUsedThisSession }
        guard lightShutdownWarning == nil else { return .shutdownUnconfirmed }
        let decision = LightGate.evaluate(
            buildAllowsLight: lightBuildEnabled,
            protocolID: protocolID,
            catalog: lightCatalog,
            screeningPassed: true,
            consentedThisSession: true,
            thermal: thermalState()
        )
        guard case .success(let light) = decision else {
            if case .failure(let reason) = decision { return reason }
            return .noProtocolAvailable
        }
        lightUsedThisSession = true
        discardTorch()
        // A fresh controller per run means a callback from an earlier run can never touch this one.
        let torch = makeTorch()
        torch.onStop = { [weak self, weak torch] reason in
            guard let self, let torch, torch === self.torch else { return }
            self.handleLightStop(reason)
        }
        self.torch = torch
        do {
            try torch.start(light, allowedCatalog: lightCatalog)
        } catch {
            // Capture a failed off request from inside start before the cleanup retry can mask it.
            reportUnconfirmedOff()
            discardTorch()
            return .hardware(error as? TorchError ?? .configurationFailed(error.localizedDescription))
        }
        isLightActive = torch.isRunning
        return nil
    }

    func stopLight() {
        stopLight(.requested)
    }

    /// The user confirmed the flashlight is physically off. The only normal way to clear the warning.
    func acknowledgeLightShutdownWarning() {
        lightShutdownWarning = nil
    }

    // MARK: - Lifecycle internals

    private func systemPause(_ reason: PauseReason, notice newNotice: SessionNotice) {
        // The system has usually silenced output already, so stop without a fade.
        pauseSession(reason, fadeOut: 0, notice: newNotice)
    }

    private func pauseSession(_ reason: PauseReason, fadeOut: TimeInterval, notice newNotice: SessionNotice?) {
        // Settle a session that is already due, so a late pause can't swallow its completion.
        tick()
        guard var timeline, timeline.pause(reason, at: clock()) else { return }
        self.timeline = timeline
        audio.pause(fadeOut: fadeOut)
        let hadLight = isLightActive
        stopLight(.requested)
        stopTicker()
        if let newNotice {
            notice = newNotice
        } else if hadLight, torch?.offCommandError == nil {
            notice = .lightStopped("It stays off for the rest of this session.")
        }
        sync()
    }

    private func complete() {
        audio.finish(withChime: true)
        teardownAfterSession()
        saveRecord()
    }

    private func finish(_ outcome: SessionOutcome) {
        guard var timeline, timeline.end(outcome, at: clock()) else { return }
        self.timeline = timeline
        if case .finished(.completed) = timeline.phase {
            audio.finish(withChime: true)
        } else {
            audio.finish(withChime: false)
        }
        teardownAfterSession()
        saveRecord()
    }

    private func teardownAfterSession() {
        stopLight(.requested)
        stopTicker()
        sync()
    }

    private func saveRecord() {
        guard let timeline, let configuration, let startedAt, case .finished(let outcome) = timeline.phase else { return }
        let record = SessionRecord(
            presetID: configuration.presetID,
            title: configuration.title,
            soundscape: configuration.soundscape,
            startedAt: startedAt,
            plannedDuration: configuration.duration,
            listenedDuration: timeline.elapsed(at: clock()),
            outcome: outcome
        )
        guard record.isWorthRecording else { return }
        history.record(record)
        lastRecord = record
    }

    private func stopLight(_ reason: TorchStopReason) {
        torch?.hardStop(reason)
        isLightActive = false
        reportUnconfirmedOff()
    }

    private func discardTorch() {
        torch?.onStop = nil
        reportUnconfirmedOff()
        torch?.hardStop(.requested)
        reportUnconfirmedOff()
        torch = nil
        isLightActive = false
    }

    /// If the off command itself failed, raise the persistent warning instead of implying the
    /// light is off. A later successful off request does not clear it: only the user can.
    private func reportUnconfirmedOff() {
        guard let error = torch?.offCommandError, lightShutdownWarning == nil else { return }
        lightShutdownWarning = "Afterglow could not confirm that the flashlight turned off (\(error.localizedDescription)). Turn the phone away or cover the torch, then switch it off in Control Center or restart the phone."
    }

    private func handleLightStop(_ reason: TorchStopReason) {
        isLightActive = false
        reportUnconfirmedOff()
        // Never tell the user the light turned off when the off request failed.
        guard torch?.offCommandError == nil else { return }
        switch reason {
        case .requested:
            break
        case .finished:
            notice = .lightStopped("The light sequence finished. Audio continues.")
        case .timeout:
            notice = .lightStopped("It reached its time limit.")
        case .appInactive:
            notice = .lightStopped("Afterglow left the screen.")
        case .thermal:
            notice = .lightStopped("Your device is warm.")
        case .failure(let error):
            notice = .lightStopped(error.localizedDescription)
        }
    }

    private func sync() {
        let now = clock()
        let newPhase = timeline?.phase ?? .idle
        let phaseChanged = newPhase != phase
        if phaseChanged { phase = newPhase }
        elapsed = timeline?.elapsed(at: now) ?? 0
        // The system extrapolates progress from the rate, so only push on state changes.
        // With the user's own music mixed in, Afterglow must not claim Now Playing or the
        // lock-screen controls: they would control only the silent bed, not the music.
        if phaseChanged {
            let owned = phase.isActive && configuration?.mixWithOtherAudio != true
            nowPlaying?.update(configuration: owned ? configuration : nil, elapsed: elapsed, isPlaying: phase.isRunning)
        }
    }

    private func startTicker() {
        stopTicker()
        guard usesTimer else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: - System events

    private func observeSystemEvents() {
        add(AVAudioSession.interruptionNotification) { player, note in player.handleInterruption(note) }
        add(AVAudioSession.routeChangeNotification) { player, note in player.handleRouteChange(note) }
        add(ProcessInfo.thermalStateDidChangeNotification) { player, _ in player.handleThermalChange() }
        #if canImport(UIKit)
        add(UIApplication.willEnterForegroundNotification) { player, _ in player.tick() }
        add(UIApplication.willTerminateNotification) { player, _ in player.finish(.interrupted) }
        #endif
    }

    private func add(_ name: Notification.Name, handler: @escaping @MainActor (SessionPlayer, Notification) -> Void) {
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self, note)
            }
        })
    }

    func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let rawType = (info[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            systemPause(.interruption, notice: .interrupted)
        case .ended:
            let rawOptions = (info[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            if options.contains(.shouldResume), phase == .paused(.interruption) {
                resume()
            }
        @unknown default:
            break
        }
    }

    func handleRouteChange(_ note: Notification) {
        guard let rawReason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue,
              AVAudioSession.RouteChangeReason(rawValue: rawReason) == .oldDeviceUnavailable else { return }
        systemPause(.routeChange, notice: .headphonesDisconnected)
    }

    func handleThermalChange() {
        switch thermalState() {
        case .critical:
            systemPause(.interruption, notice: .thermalWarning)
        case .serious:
            if isLightActive { stopLight(.thermal) }
        default:
            break
        }
    }
}
