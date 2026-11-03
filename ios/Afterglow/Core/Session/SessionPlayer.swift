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
    /// The rendered light plan for the current session, once light has started.
    @Published private(set) var lightPlan: LightPlan?
    /// The user switched light off mid-session; it stays off until they switch it back on.
    @Published private(set) var lightSuspendedByUser = false
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
    /// Set when light stopped for warmth, a time limit or a hardware fault: it stays off.
    private var lightBlockedThisSession = false
    private var screenKeptAwake = false
    private let makeTorch: @MainActor () -> TorchController
    private let lightBuildEnabled: Bool
    private let lightLeadIn: TimeInterval
    private let isAppActive: @MainActor () -> Bool
    private let keepScreenAwake: @MainActor (Bool) -> Void

    /// Dark pause before light comes back after a resume or returning to the app.
    static let lightResumeHold: TimeInterval = 4

    /// Measured flash timing for the current light run.
    var lightTiming: TorchDriver.Stats? { torch?.timingStats }

    /// Nominal flash frequency right now, while light is on.
    var lightFrequency: Double? {
        guard isLightActive, let plan = lightPlan, let t = torch?.planElapsed else { return nil }
        return plan.frequency(at: t)
    }

    init(
        history: HistoryStore,
        audio: AmbientAudioControlling? = nil,
        clock: @escaping () -> TimeInterval = MonotonicClock.now,
        wallClock: @escaping () -> Date = Date.init,
        thermalState: @escaping () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState },
        notificationCenter: NotificationCenter = .default,
        usesTimer: Bool = true,
        integratesWithSystemMedia: Bool = true,
        lightBuildEnabled: Bool = LightFeature.buildAllowsLight,
        lightLeadIn: TimeInterval = 15,
        isAppActive: (@MainActor () -> Bool)? = nil,
        keepScreenAwake: (@MainActor (Bool) -> Void)? = nil,
        makeTorch: (@MainActor () -> TorchController)? = nil
    ) {
        self.history = history
        self.audio = audio ?? AmbientAudioEngine(notificationCenter: notificationCenter)
        self.clock = clock
        self.wallClock = wallClock
        self.thermalState = thermalState
        center = notificationCenter
        self.usesTimer = usesTimer
        self.lightBuildEnabled = lightBuildEnabled
        self.lightLeadIn = lightLeadIn
        self.isAppActive = isAppActive ?? Self.systemAppIsActive
        self.keepScreenAwake = keepScreenAwake ?? Self.systemKeepScreenAwake
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

    private static func systemAppIsActive() -> Bool {
        #if canImport(UIKit)
        return UIApplication.shared.applicationState == .active
        #else
        return true
        #endif
    }

    /// Light sessions are eyes-closed and hands-off, so the screen must not auto-lock.
    private static func systemKeepScreenAwake(_ awake: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = awake
        #endif
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
        lightBlockedThisSession = false
        lightSuspendedByUser = false
        lightPlan = nil
        var timeline = SessionTimeline(duration: configuration.duration)
        timeline.start(at: clock())
        self.timeline = timeline
        self.configuration = configuration
        startedAt = wallClock()
        sync()
        startTicker()
        if configuration.useLight, let reason = startLight() {
            notice = .lightUnavailable(reason.message)
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
        resumeLightIfWanted()
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
        lightPlan = nil
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

    // MARK: - Light (Debug builds only)

    /// Starts (or restarts) the torch for the running session at the session's current point,
    /// after `holdOff` seconds of darkness. `start(_:)` calls this when the configuration has
    /// `useLight`, which the UI sets only after a current safety check. Returns why light cannot
    /// run, or nil when the torch is running or the light part of the session is already over.
    @discardableResult
    func startLight(holdOff: TimeInterval = 0) -> LightUnavailableReason? {
        guard phase == .running, let configuration, let timeline else { return .sessionNotRunning }
        guard configuration.useLight else { return .consentMissing }
        guard !lightBlockedThisSession else { return .stoppedThisSession }
        guard lightShutdownWarning == nil else { return .shutdownUnconfirmed }
        let requested = configuration.lightProgram ?? LightProgramCatalog.recommended(for: configuration.intent ?? .calm)
        let program: LightProgram
        switch LightGate.evaluate(buildAllowsLight: lightBuildEnabled, program: requested, consented: true, thermal: thermalState()) {
        case .success(let allowed): program = allowed
        case .failure(let reason): return reason
        }
        let sleepy = configuration.intent == .sleep || program.id == LightProgramCatalog.sleep.id
        let plan = LightPlan.forSession(
            program: program,
            sessionDuration: configuration.duration,
            brightness: min(max(configuration.lightBrightness, 0.05), TorchController.bounds.brightnessCeiling),
            leadIn: lightLeadIn,
            maximumLight: sleepy ? LightProgramCatalog.sleepLightLimit : nil
        )
        let offset = timeline.elapsed(at: clock())
        discardTorch()
        lightPlan = plan
        guard offset < plan.totalDuration else { return nil }
        // A fresh controller per run means a callback from an earlier run can never touch this one.
        let torch = makeTorch()
        torch.onStop = { [weak self, weak torch] reason in
            guard let self, let torch, torch === self.torch else { return }
            self.handleLightStop(reason)
        }
        self.torch = torch
        do {
            try torch.start(plan, at: offset, holdOff: holdOff)
        } catch {
            // Capture a failed off request from inside start before the cleanup retry can mask it.
            reportUnconfirmedOff()
            discardTorch()
            return .hardware(error as? TorchError ?? .configurationFailed(error.localizedDescription))
        }
        isLightActive = torch.isRunning
        return nil
    }

    /// Mid-session light switch. Off stays off until switched back on; on resumes the program
    /// where the session is now, after a short dark pause.
    func setLightEnabled(_ enabled: Bool) {
        guard configuration?.useLight == true else { return }
        lightSuspendedByUser = !enabled
        if enabled {
            if phase == .running, let reason = startLight(holdOff: Self.lightResumeHold) {
                notice = .lightUnavailable(reason.message)
            }
        } else {
            stopLight(.requested)
        }
    }

    /// Changes the torch brightness of the running session immediately.
    func setLightBrightness(_ brightness: Float) {
        let level = min(max(brightness, 0.05), TorchController.bounds.brightnessCeiling)
        configuration?.lightBrightness = level
        torch?.setPeakLevel(level)
    }

    func stopLight() {
        stopLight(.requested)
    }

    private func resumeLightIfWanted() {
        guard phase == .running, configuration?.useLight == true, !isLightActive, !lightSuspendedByUser,
              !lightBlockedThisSession, lightShutdownWarning == nil, isAppActive() else { return }
        if let reason = startLight(holdOff: Self.lightResumeHold) {
            notice = .lightUnavailable(reason.message)
        }
    }

    func handleBecameActive() {
        tick()
        resumeLightIfWanted()
    }

    /// The user confirmed the flashlight is physically off. The only normal way to clear the warning.
    func acknowledgeLightShutdownWarning() {
        // Drop the controller that failed, so its stale error cannot raise the warning again.
        torch?.onStop = nil
        torch?.hardStop(.requested)
        torch = nil
        isLightActive = false
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
        stopLight(.requested)
        stopTicker()
        if let newNotice { notice = newNotice }
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
            notice = .lightStopped("The light program finished. Audio continues.")
        case .appInactive:
            // Comes back by itself, after a dark pause, when Afterglow is on screen again.
            break
        case .timeout:
            lightBlockedThisSession = true
            notice = .lightStopped("It reached its time limit.")
        case .thermal:
            lightBlockedThisSession = true
            notice = .lightStopped("Your device is warm.")
        case .failure(let error):
            lightBlockedThisSession = true
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
        let awake = phase.isActive && configuration?.useLight == true
        if awake != screenKeptAwake {
            screenKeptAwake = awake
            keepScreenAwake(awake)
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
        add(UIApplication.didBecomeActiveNotification) { player, _ in player.handleBecameActive() }
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
