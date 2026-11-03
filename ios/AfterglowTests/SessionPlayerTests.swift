import AVFoundation
import XCTest
@testable import Afterglow

final class FakeAudio: AmbientAudioControlling {
    enum Call: Equatable {
        case prepare(Soundscape, Float)
        case play
        case pause
        case finish(chime: Bool)
        case stop
        case volume(Float)
    }

    var onUnexpectedStop: ((String) -> Void)?
    var calls: [Call] = []
    var failPrepare = false
    var failPlay = false

    struct Failure: LocalizedError {
        var errorDescription: String? { "Simulated audio failure." }
    }

    var lastMixWithOthers: Bool?

    func prepare(soundscape: Soundscape, volume: Float, mixWithOthers: Bool) throws {
        if failPrepare { throw Failure() }
        lastMixWithOthers = mixWithOthers
        calls.append(.prepare(soundscape, volume))
    }

    func play(fadeIn: TimeInterval) throws {
        if failPlay { throw Failure() }
        calls.append(.play)
    }

    func pause(fadeOut: TimeInterval) { calls.append(.pause) }
    func finish(withChime: Bool) { calls.append(.finish(chime: withChime)) }
    func stop() { calls.append(.stop) }
    func setVolume(_ volume: Float) { calls.append(.volume(volume)) }
}

@MainActor
final class SessionPlayerTests: XCTestCase {
    private var now: TimeInterval = 1_000
    private var thermal: ProcessInfo.ThermalState = .nominal
    private var audio: FakeAudio!
    private var history: HistoryStore!
    private var player: SessionPlayer!
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        audio = FakeAudio()
        history = HistoryStore(fileURL: directory.appendingPathComponent("history.json"))
        player = SessionPlayer(
            history: history,
            audio: audio,
            clock: { [unowned self] in self.now },
            thermalState: { [unowned self] in self.thermal },
            notificationCenter: NotificationCenter(),
            usesTimer: false,
            integratesWithSystemMedia: false
        )
    }

    override func tearDown() async throws {
        player = nil
        try? FileManager.default.removeItem(at: directory)
    }

    private var tenMinutes: SessionConfiguration {
        SessionConfiguration(presetID: "settle", title: "Settle In", soundscape: .tide, duration: 600, volume: 0.5)
    }

    private func interruption(_ type: AVAudioSession.InterruptionType, shouldResume: Bool = false) -> Notification {
        var info: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: NSNumber(value: type.rawValue)]
        if shouldResume {
            info[AVAudioSessionInterruptionOptionKey] = NSNumber(value: AVAudioSession.InterruptionOptions.shouldResume.rawValue)
        }
        return Notification(name: AVAudioSession.interruptionNotification, object: nil, userInfo: info)
    }

    func testCompletedSessionPlaysChimeAndIsRecorded() {
        player.start(tenMinutes)
        XCTAssertEqual(player.phase, .running)
        XCTAssertEqual(audio.calls, [.prepare(.tide, 0.5), .play])

        now += 300
        player.tick()
        XCTAssertEqual(player.elapsed, 300, accuracy: 0.001)
        XCTAssertEqual(player.progress, 0.5, accuracy: 0.001)

        now += 300
        player.tick()
        XCTAssertEqual(player.phase, .finished(.completed))
        XCTAssertEqual(audio.calls.last, .finish(chime: true))
        XCTAssertEqual(history.sessions.count, 1)
        XCTAssertEqual(history.sessions.first?.outcome, .completed)
        XCTAssertEqual(history.sessions.first?.listenedDuration, 600)
        XCTAssertEqual(player.lastRecord, history.sessions.first)

        now += 10
        player.tick()
        XCTAssertEqual(history.sessions.count, 1, "Completion must be recorded once")
    }

    func testPauseAndResumeExcludePausedTime() {
        player.start(tenMinutes)
        now += 60
        player.pause()
        XCTAssertEqual(player.phase, .paused(.user))
        XCTAssertEqual(audio.calls.last, .pause)

        now += 3_600
        player.tick()
        XCTAssertEqual(player.elapsed, 60, accuracy: 0.001)

        player.resume()
        XCTAssertEqual(player.phase, .running)
        now += 30
        player.tick()
        XCTAssertEqual(player.elapsed, 90, accuracy: 0.001)
        XCTAssertEqual(player.remaining, 510, accuracy: 0.001)
    }

    func testEndingEarlyRecordsPartialSessionWithoutChime() {
        player.start(tenMinutes)
        now += 120
        player.end()
        XCTAssertEqual(player.phase, .finished(.endedEarly))
        XCTAssertEqual(audio.calls.last, .finish(chime: false))
        XCTAssertEqual(history.sessions.first?.listenedDuration, 120)
        XCTAssertEqual(history.sessions.first?.outcome, .endedEarly)
    }

    func testVeryShortAbandonedSessionIsNotRecorded() {
        player.start(tenMinutes)
        now += 5
        player.end()
        XCTAssertTrue(history.sessions.isEmpty)
        XCTAssertNil(player.lastRecord)
    }

    func testInterruptionPausesAndResumesWhenSystemAllows() {
        player.start(tenMinutes)
        now += 30
        player.handleInterruption(interruption(.began))
        XCTAssertEqual(player.phase, .paused(.interruption))
        XCTAssertEqual(player.notice, .interrupted)

        now += 120
        player.handleInterruption(interruption(.ended, shouldResume: true))
        XCTAssertEqual(player.phase, .running)
        XCTAssertNil(player.notice)
        XCTAssertEqual(player.elapsed, 30, accuracy: 0.001)
    }

    func testInterruptionEndWithoutResumeHintStaysPaused() {
        player.start(tenMinutes)
        player.handleInterruption(interruption(.began))
        player.handleInterruption(interruption(.ended))
        XCTAssertEqual(player.phase, .paused(.interruption))
    }

    func testInterruptionEndNeverOverridesUserPause() {
        player.start(tenMinutes)
        player.pause()
        player.handleInterruption(interruption(.began))
        player.handleInterruption(interruption(.ended, shouldResume: true))
        XCTAssertEqual(player.phase, .paused(.user))
    }

    func testHeadphonesUnpluggedPauses() {
        player.start(tenMinutes)
        let note = Notification(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey: NSNumber(value: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue)]
        )
        player.handleRouteChange(note)
        XCTAssertEqual(player.phase, .paused(.routeChange))
        XCTAssertEqual(player.notice, .headphonesDisconnected)

        let newDevice = Notification(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey: NSNumber(value: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue)]
        )
        player.resume()
        player.handleRouteChange(newDevice)
        XCTAssertEqual(player.phase, .running, "Plugging headphones in must not pause")
    }

    func testCriticalThermalStatePausesAndBlocksResume() {
        player.start(tenMinutes)
        thermal = .critical
        player.handleThermalChange()
        XCTAssertEqual(player.phase, .paused(.interruption))
        XCTAssertEqual(player.notice, .thermalWarning)

        player.resume()
        XCTAssertEqual(player.phase, .paused(.interruption))

        thermal = .fair
        player.resume()
        XCTAssertEqual(player.phase, .running)
    }

    func testAudioFailureKeepsPlayerIdle() {
        audio.failPrepare = true
        player.start(tenMinutes)
        XCTAssertEqual(player.phase, .idle)
        XCTAssertEqual(player.notice, .audioUnavailable("Simulated audio failure."))
        XCTAssertEqual(audio.calls, [.stop])
    }

    func testUnexpectedAudioStopPauses() async {
        player.start(tenMinutes)
        audio.onUnexpectedStop?("Output lost.")
        for _ in 0..<50 where player.phase == .running {
            await Task.yield()
        }
        XCTAssertEqual(player.phase, .paused(.interruption))
        XCTAssertEqual(player.notice, .audioUnavailable("Output lost."))
    }

    func testStartingNewSessionEndsPreviousOne() {
        player.start(tenMinutes)
        now += 120
        player.start(SessionConfiguration(preset: PresetCatalog.all[0]))
        XCTAssertEqual(player.phase, .running)
        XCTAssertEqual(history.sessions.first?.outcome, .endedEarly)
        XCTAssertEqual(player.elapsed, 0)
    }

    func testResetReturnsToIdle() {
        player.start(tenMinutes)
        now += 600
        player.tick()
        player.reset()
        XCTAssertEqual(player.phase, .idle)
        XCTAssertNil(player.configuration)
        XCTAssertEqual(player.elapsed, 0)
    }

    private var appActive = true
    private var screenAwake = false
    private var lastTorch: TorchController?

    private func makeLightPlayer(buildEnabled: Bool, torch: FakeTorch) -> SessionPlayer {
        SessionPlayer(
            history: history,
            audio: audio,
            clock: { [unowned self] in self.now },
            thermalState: { [unowned self] in self.thermal },
            notificationCenter: NotificationCenter(),
            usesTimer: false,
            integratesWithSystemMedia: false,
            lightBuildEnabled: buildEnabled,
            lightLeadIn: 2,
            isAppActive: { [unowned self] in self.appActive },
            keepScreenAwake: { [unowned self] in self.screenAwake = $0 },
            makeTorch: { [unowned self] in
                let controller = TorchController(device: torch, clock: { self.now }, thermalState: { self.thermal }, notificationCenter: NotificationCenter(), schedulesTimers: false)
                self.lastTorch = controller
                return controller
            }
        )
    }

    /// Steps the latest torch through a few flash cycles of simulated time.
    private func driveTorch(seconds: TimeInterval = 0.5) {
        for _ in 0..<Int(seconds / 0.01) {
            now += 0.01
            lastTorch?.step()
        }
    }

    private var lightSession: SessionConfiguration {
        var configuration = tenMinutes
        configuration.useLight = true
        configuration.lightBrightness = 0.8
        return configuration
    }

    func testReleaseBuildRefusesLightAndStaysAudioOnly() {
        let torch = FakeTorch()
        let player = makeLightPlayer(buildEnabled: false, torch: torch)
        player.start(lightSession)
        XCTAssertEqual(player.phase, .running, "Audio continues when light is refused")
        XCTAssertFalse(player.isLightActive)
        XCTAssertEqual(player.notice, .lightUnavailable(LightUnavailableReason.disabledInThisBuild.message))
        XCTAssertTrue(torch.levels.allSatisfy { $0 == 0 })
    }

    func testAudioOnlySessionNeverTouchesTorch() {
        let torch = FakeTorch()
        let player = makeLightPlayer(buildEnabled: true, torch: torch)
        player.start(tenMinutes)
        XCTAssertFalse(player.isLightActive)
        XCTAssertTrue(torch.levels.isEmpty)
        XCTAssertFalse(screenAwake, "Audio sessions may let the screen lock")
    }

    func testLightRunsTheRecommendedProgramAtTheChosenBrightness() {
        let torch = FakeTorch()
        let player = makeLightPlayer(buildEnabled: true, torch: torch)
        player.start(lightSession)
        XCTAssertTrue(player.isLightActive)
        XCTAssertEqual(player.lightPlan?.program.id, LightProgramCatalog.relax.id, "Settle In is a calm session")
        XCTAssertEqual(torch.current, 0, "Dark during the lead-in")
        XCTAssertTrue(screenAwake, "Light sessions keep the screen awake")

        now += 2 + 60
        driveTorch()
        XCTAssertTrue(torch.levels.contains { $0 > 0 })
        XCTAssertTrue(torch.levels.allSatisfy { $0 <= 0.8 + 1e-6 })
        let hz = player.lightFrequency ?? 0
        XCTAssertTrue((6...10).contains(hz), "\(hz) Hz")

        player.end()
        XCTAssertFalse(player.isLightActive)
        XCTAssertEqual(torch.current, 0)
        XCTAssertFalse(screenAwake)
    }

    func testBrightnessChangesApplyDuringTheSession() {
        let torch = FakeTorch()
        let player = makeLightPlayer(buildEnabled: true, torch: torch)
        player.start(lightSession)
        player.setLightBrightness(0.3)
        now += 2 + 60
        driveTorch()
        XCTAssertTrue(torch.levels.contains { $0 > 0 })
        XCTAssertTrue(torch.levels.allSatisfy { $0 <= 0.3 + 1e-6 })
    }

    func testPauseStopsLightAndResumeBringsItBackAfterDarkHold() {
        let torch = FakeTorch()
        let player = makeLightPlayer(buildEnabled: true, torch: torch)
        player.start(lightSession)
        now += 30
        player.tick()
        player.pause()
        XCTAssertFalse(player.isLightActive)
        XCTAssertEqual(torch.current, 0)
        XCTAssertNil(player.notice)

        now += 100
        player.resume()
        XCTAssertEqual(player.phase, .running)
        XCTAssertTrue(player.isLightActive)
        XCTAssertEqual(torch.current, 0, "Dark first after resuming")
        let litBefore = torch.levels.filter { $0 > 0 }.count
        now += SessionPlayer.lightResumeHold
        driveTorch()
        XCTAssertGreaterThan(torch.levels.filter { $0 > 0 }.count, litBefore, "Picks up the program where the session is")
    }

    func testLightWaitsUntilAfterglowIsOnScreen() {
        let torch = FakeTorch()
        let player = makeLightPlayer(buildEnabled: true, torch: torch)
        player.start(lightSession)
        player.pause()
        appActive = false
        player.resume()
        XCTAssertFalse(player.isLightActive, "Never relight from the lock screen")
        appActive = true
        player.handleBecameActive()
        XCTAssertTrue(player.isLightActive)
    }

    func testUserCanSwitchLightOffAndBackOn() {
        let torch = FakeTorch()
        let player = makeLightPlayer(buildEnabled: true, torch: torch)
        player.start(lightSession)
        player.setLightEnabled(false)
        XCTAssertFalse(player.isLightActive)
        XCTAssertTrue(player.lightSuspendedByUser)
        player.pause()
        player.resume()
        XCTAssertFalse(player.isLightActive, "Stays off until switched back on")
        player.setLightEnabled(true)
        XCTAssertTrue(player.isLightActive)
        XCTAssertFalse(player.lightSuspendedByUser)
    }

    func testWarmthStopsLightForTheRestOfTheSession() {
        let torch = FakeTorch()
        let player = makeLightPlayer(buildEnabled: true, torch: torch)
        player.start(lightSession)
        thermal = .serious
        player.handleThermalChange()
        XCTAssertFalse(player.isLightActive)
        XCTAssertEqual(player.notice, .lightStopped("Your device is warm."))
        thermal = .nominal
        player.pause()
        player.resume()
        XCTAssertFalse(player.isLightActive)
        XCTAssertEqual(player.startLight(), .stoppedThisSession)
    }

    func testInterruptionStopsLightAndEndTurnsItOff() {
        let torch = FakeTorch()
        let player = makeLightPlayer(buildEnabled: true, torch: torch)
        player.start(lightSession)
        player.handleInterruption(interruption(.began))
        XCTAssertFalse(player.isLightActive)
        XCTAssertEqual(torch.current, 0)
        player.handleInterruption(interruption(.ended, shouldResume: true))
        XCTAssertEqual(player.phase, .running)
        XCTAssertTrue(player.isLightActive, "Light comes back with the session")

        let second = FakeTorch()
        let other = makeLightPlayer(buildEnabled: true, torch: second)
        other.start(lightSession)
        XCTAssertTrue(other.isLightActive)
        other.end()
        XCTAssertFalse(other.isLightActive)
        XCTAssertEqual(second.current, 0)
    }

    func testLightNeedsTheOptIn() {
        let torch = FakeTorch()
        let player = makeLightPlayer(buildEnabled: true, torch: torch)
        player.start(tenMinutes)
        XCTAssertEqual(player.startLight(), .consentMissing)
        XCTAssertTrue(torch.levels.isEmpty)
    }

    func testInvalidCustomProgramIsRefused() {
        let torch = FakeTorch()
        let player = makeLightPlayer(buildEnabled: true, torch: torch)
        var configuration = lightSession
        configuration.lightProgram = .custom(startHz: 30, endHz: 40)
        player.start(configuration)
        XCTAssertFalse(player.isLightActive)
        XCTAssertEqual(player.notice, .lightUnavailable(LightUnavailableReason.invalidProgram.message))
        XCTAssertTrue(torch.levels.isEmpty)
    }

    func testSleepLightSwitchesItselfOff() {
        let torch = FakeTorch()
        let player = makeLightPlayer(buildEnabled: true, torch: torch)
        var configuration = SessionConfiguration(preset: PresetCatalog.preset(id: "wind-down")!, minutes: 45)
        configuration.useLight = true
        player.start(configuration)
        XCTAssertEqual(player.lightPlan?.program.id, LightProgramCatalog.sleep.id)
        XCTAssertEqual(player.lightPlan?.lightDuration, LightProgramCatalog.sleepLightLimit)
    }

    func testUnconfirmedTorchOffRaisesPersistentWarningNotALightOffNotice() {
        let torch = FakeTorch()
        let player = makeLightPlayer(buildEnabled: true, torch: torch)
        player.start(lightSession)
        XCTAssertNil(player.lightShutdownWarning)
        torch.failOff = true
        player.end()
        XCTAssertNotNil(player.lightShutdownWarning)
        XCTAssertTrue(player.lightShutdownWarning?.contains("could not confirm") == true)
        if case .lightStopped? = player.notice {
            XCTFail("Must not claim the light turned off when the off request failed")
        }
    }

    func testShutdownWarningSurvivesResetNewStartAndNoticeDismissal() {
        let torch = FakeTorch()
        let player = makeLightPlayer(buildEnabled: true, torch: torch)
        player.start(lightSession)
        torch.failOff = true
        player.pause()
        let warning = player.lightShutdownWarning
        XCTAssertNotNil(warning)

        torch.failOff = false
        player.dismissNotice()
        player.resume()
        XCTAssertFalse(player.isLightActive, "No relight while the warning is unresolved")
        player.handleInterruption(interruption(.began))
        player.end()
        player.reset()
        XCTAssertEqual(player.lightShutdownWarning, warning, "A later successful off must not clear it")

        player.start(lightSession)
        XCTAssertEqual(player.phase, .running, "Audio still works")
        XCTAssertFalse(player.isLightActive, "No new light while the warning is unresolved")
        XCTAssertEqual(player.notice, .lightUnavailable(LightUnavailableReason.shutdownUnconfirmed.message))
        XCTAssertEqual(player.lightShutdownWarning, warning)
        player.dismissNotice()
        XCTAssertEqual(player.lightShutdownWarning, warning)
    }

    func testAcknowledgementClearsWarningAndAllowsLightAgain() {
        let torch = FakeTorch()
        let player = makeLightPlayer(buildEnabled: true, torch: torch)
        player.start(lightSession)
        torch.failOff = true
        player.end()
        XCTAssertNotNil(player.lightShutdownWarning)

        torch.failOff = false
        player.acknowledgeLightShutdownWarning()
        XCTAssertNil(player.lightShutdownWarning)
        player.start(lightSession)
        XCTAssertTrue(player.isLightActive)
    }

    func testOffFailureDuringLifecyclePauseIsWarned() {
        let torch = FakeTorch()
        let player = makeLightPlayer(buildEnabled: true, torch: torch)
        player.start(lightSession)
        torch.failOff = true
        player.handleRouteChange(Notification(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey: NSNumber(value: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue)]
        ))
        XCTAssertEqual(player.phase, .paused(.routeChange))
        XCTAssertEqual(player.notice, .headphonesDisconnected)
        XCTAssertNotNil(player.lightShutdownWarning)
    }

    func testOffFailureWhileStartingLightIsWarned() {
        let torch = FakeTorch()
        torch.failOff = true
        let player = makeLightPlayer(buildEnabled: true, torch: torch)
        player.start(lightSession)
        XCTAssertEqual(player.phase, .running)
        XCTAssertFalse(player.isLightActive)
        XCTAssertNotNil(player.lightShutdownWarning)
        XCTAssertTrue(torch.levels.isEmpty, "Never turned on")
    }

    func testWarmDeviceRefusesLight() {
        let torch = FakeTorch()
        let player = makeLightPlayer(buildEnabled: true, torch: torch)
        thermal = .serious
        player.start(lightSession)
        XCTAssertEqual(player.phase, .running)
        XCTAssertFalse(player.isLightActive)
        XCTAssertEqual(player.notice, .lightUnavailable(LightUnavailableReason.deviceThermalState.message))
    }

    func testMissingTorchHardwareIsReported() {
        let torch = FakeTorch()
        torch.hasTorch = false
        let player = makeLightPlayer(buildEnabled: true, torch: torch)
        player.start(lightSession)
        XCTAssertFalse(player.isLightActive)
        XCTAssertEqual(player.notice, .lightUnavailable(LightUnavailableReason.hardware(.noTorch).message))
    }

    func testMixWithOthersIsPassedToAudio() {
        var configuration = tenMinutes
        configuration.mixWithOtherAudio = true
        player.start(configuration)
        XCTAssertEqual(audio.lastMixWithOthers, true)
    }
}
