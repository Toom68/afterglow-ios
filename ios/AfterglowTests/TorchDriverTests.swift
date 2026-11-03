import XCTest
@testable import Afterglow

/// Thread-safe torch double for real-time playback tests.
final class RecordingTorch: TorchDevice, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Float] = []
    private var exclusive = 0
    private var exclusiveEver = false
    var hasTorch: Bool { true }
    var isTorchAvailable: Bool { true }
    var maxAvailableLevel: Float { 1 }

    var levels: [Float] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    /// (currently held, ever held)
    var exclusiveState: (held: Bool, ever: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (exclusive > 0, exclusiveEver)
    }

    func beginExclusiveControl() throws {
        lock.lock()
        exclusive += 1
        exclusiveEver = true
        lock.unlock()
    }

    func endExclusiveControl() {
        lock.lock()
        exclusive = max(0, exclusive - 1)
        lock.unlock()
    }

    func setLevel(_ level: Float) throws {
        lock.lock()
        recorded.append(level)
        lock.unlock()
    }
}

/// Real-time tests of the dedicated playback thread.
final class TorchDriverTests: XCTestCase {
    private func makeDriver(_ plan: LightPlan, torch: RecordingTorch, onStop: @escaping (TorchStopReason) -> Void = { _ in }) -> TorchDriver {
        TorchDriver(
            plan: plan,
            device: torch,
            clock: MonotonicClock.now,
            thermalState: { .nominal },
            startedAt: MonotonicClock.now(),
            holdUntil: 0,
            peak: plan.peakTorchLevel,
            ceiling: 1,
            hardTimeout: TorchController.hardTimeout,
            onStop: onStop
        )
    }

    private func steady(_ hz: Double, seconds: TimeInterval, peak: Float = 0.5) -> LightPlan {
        LightPlan(program: .custom(startHz: hz, endHz: hz), preparationDelay: 0, lightDuration: seconds, peakTorchLevel: peak, fadeIn: 0, fadeOut: 0)
    }

    func testInstantaneousDeviceCommandsWhileMainThreadIsBusy() {
        let torch = RecordingTorch()
        let finished = expectation(description: "finished")
        let driver = makeDriver(steady(10, seconds: 1.5), torch: torch) { reason in
            XCTAssertEqual(reason, .finished)
            finished.fulfill()
        }
        driver.start()
        // Simulate heavy screen work: block the main thread for most of the run.
        Thread.sleep(forTimeInterval: 1.0)
        wait(for: [finished], timeout: 5)

        let flashes = torch.levels.filter { $0 > 0 }.count
        XCTAssertEqual(flashes, 15, "10 Hz for 1.5 s is 15 flashes, none dropped")
        XCTAssertEqual(driver.stats.dropped, 0)
        XCTAssertLessThan(driver.stats.averageLateness, 0.03)
        // Strict alternation: on, off, on, off...
        let changes = torch.levels
        for (index, level) in changes.enumerated() {
            if index > 0, level == 0, changes[index - 1] == 0 { continue }
            XCTAssertEqual(level > 0, index % 2 == 0, "edge \(index) breaks the on/off rhythm")
        }
    }

    func testCancelGuaranteesNoFurtherCommands() {
        let torch = RecordingTorch()
        let driver = makeDriver(steady(10, seconds: 10), torch: torch)
        driver.start()
        Thread.sleep(forTimeInterval: 0.35)
        driver.cancel()
        let count = torch.levels.count
        XCTAssertGreaterThan(count, 0)
        Thread.sleep(forTimeInterval: 0.35)
        XCTAssertEqual(torch.levels.count, count, "Nothing after cancel")
    }

    func testHoldsTheHardwareLockForTheRunAndAlwaysReleasesIt() {
        let torch = RecordingTorch()
        let driver = makeDriver(steady(10, seconds: 10), torch: torch)
        driver.start()
        Thread.sleep(forTimeInterval: 0.25)
        XCTAssertTrue(torch.exclusiveState.held, "Locked once for the whole run")
        driver.cancel()
        XCTAssertFalse(torch.exclusiveState.held, "Released by cancel")

        let finishedTorch = RecordingTorch()
        let finished = expectation(description: "finished")
        makeDriver(steady(10, seconds: 0.3), torch: finishedTorch) { _ in finished.fulfill() }.start()
        wait(for: [finished], timeout: 3)
        XCTAssertTrue(finishedTorch.exclusiveState.ever)
        XCTAssertFalse(finishedTorch.exclusiveState.held, "Released when the plan ends")
    }

    func testReportsPositiveAPICommandReturnRate() {
        let torch = RecordingTorch()
        let driver = makeDriver(steady(12, seconds: 10), torch: torch)
        driver.start()
        Thread.sleep(forTimeInterval: 2.0)
        let rate = driver.stats.achievedRate ?? 0
        driver.cancel()
        XCTAssertEqual(rate, 12, accuracy: 0.6)
    }

    func testBrightnessChangeAppliesToLaterFlashes() {
        let torch = RecordingTorch()
        let driver = makeDriver(steady(10, seconds: 10, peak: 0.8), torch: torch)
        driver.start()
        Thread.sleep(forTimeInterval: 0.3)
        driver.setPeak(0.2)
        Thread.sleep(forTimeInterval: 0.3)
        driver.cancel()
        let lit = torch.levels.filter { $0 > 0 }
        XCTAssertEqual(lit.first ?? 0, 0.8, accuracy: 1e-6)
        XCTAssertEqual(lit.last ?? 0, 0.2, accuracy: 1e-6)
    }

    func testHoldKeepsTheTorchDarkFirst() {
        let torch = RecordingTorch()
        let plan = steady(10, seconds: 10)
        let driver = TorchDriver(
            plan: plan, device: torch, clock: MonotonicClock.now, thermalState: { .nominal },
            startedAt: MonotonicClock.now(), holdUntil: 0.5, peak: 0.5, ceiling: 1,
            hardTimeout: TorchController.hardTimeout, onStop: { _ in }
        )
        driver.start()
        Thread.sleep(forTimeInterval: 0.35)
        XCTAssertTrue(torch.levels.allSatisfy { $0 == 0 }, "Dark during the hold")
        Thread.sleep(forTimeInterval: 0.4)
        driver.cancel()
        XCTAssertTrue(torch.levels.contains { $0 > 0 })
    }
}

/// Virtual clock and adversarial adapter. Only the playback thread advances virtual time;
/// snapshots are synchronized so the test thread can inspect blocked calls safely.
final class AdversarialTorch: TorchDevice, @unchecked Sendable {
    struct Command { let level: Float; let issued: TimeInterval; let returned: TimeInterval }
    private let lock = NSLock()
    private var time: TimeInterval = 0
    private var recorded: [Command] = []
    var positiveDelay: TimeInterval = 0
    var offDelay: TimeInterval = 0
    var capabilityDelay: TimeInterval = 0
    var rejectPositive = false
    var rejectOffCount = 0
    var beforePositive: (() -> Void)?
    var beforeAcquire: (() -> Void)?
    var beforeOff: (() -> Void)?
    var beforeRelease: (() -> Void)?
    var caps: [Float] = [1]
    private var capReads = 0
    func beginExclusiveControl() throws { beforeAcquire?() }
    func endExclusiveControl() { beforeRelease?() }
    var hasTorch: Bool { true }
    var isTorchAvailable: Bool { advance(capabilityDelay); return true }
    var maxAvailableLevel: Float {
        lock.lock(); defer { lock.unlock() }
        let cap = caps[min(capReads, caps.count - 1)]
        capReads += 1
        return cap
    }
    var now: TimeInterval { lock.lock(); defer { lock.unlock() }; return time }
    var commands: [Command] { lock.lock(); defer { lock.unlock() }; return recorded }
    func advance(_ delay: TimeInterval) { lock.lock(); time += delay; lock.unlock() }
    func setLevel(_ level: Float) throws {
        let issued = now
        if level > 0 { beforePositive?() } else { beforeOff?() }
        advance(level > 0 ? positiveDelay : offDelay)
        lock.lock()
        recorded.append(Command(level: level, issued: issued, returned: time))
        lock.unlock()
        if level == 0, rejectOffCount > 0 {
            rejectOffCount -= 1
            throw TorchError.configurationFailed("off rejected")
        }
        if level > 0, rejectPositive { throw TorchError.configurationFailed("on rejected") }
    }
}

final class TorchDriverAdversarialTests: XCTestCase {
    private func plan(_ hz: Double = 10, duration: TimeInterval = 1, peak: Float = 0.5, fade: TimeInterval = 0) -> LightPlan {
        LightPlan(program: .custom(startHz: hz, endHz: hz), preparationDelay: 0,
                  lightDuration: duration, peakTorchLevel: peak, fadeIn: fade, fadeOut: fade)
    }
    private func driver(_ plan: LightPlan, _ torch: AdversarialTorch,
                        timeout: TimeInterval = 100,
                        thermal: @escaping () -> ProcessInfo.ThermalState = { .nominal },
                        stop: @escaping (TorchStopReason) -> Void) -> TorchDriver {
        TorchDriver(plan: plan, device: torch, clock: { torch.now }, thermalState: thermal,
                    startedAt: 0, holdUntil: 0, peak: plan.peakTorchLevel, ceiling: 1,
                    hardTimeout: timeout, waitForDelay: { torch.advance($0) }, onStop: stop)
    }

    func testFinalOnPlanIsOffBeforeCallbackEvenWithMainDeliveryWithheld() {
        let torch = AdversarialTorch()
        let workerReturned = DispatchSemaphore(value: 0)
        let delivered = expectation(description: "main callback")
        let playback = driver(plan(1, duration: 0.02), torch) { reason in
            XCTAssertEqual(reason, .finished)
            XCTAssertEqual(torch.commands.last?.level, 0)
            workerReturned.signal()
            DispatchQueue.main.async { delivered.fulfill() }
        }
        playback.start()
        // Main delivery is withheld while this thread waits; worker off must already exist.
        XCTAssertEqual(workerReturned.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(torch.commands.map(\.level), [0.5, 0])
        XCTAssertEqual(torch.commands.last?.issued ?? -1, 0.02, accuracy: 1e-9)
        wait(for: [delivered], timeout: 2)
    }

    func testSlowCommandsStopWithoutCatchUpAtTenAndTwentyHz() {
        for hz in [10.0, 20.0] {
            for delay in [0.09, 0.6] {
                let torch = AdversarialTorch()
                torch.positiveDelay = delay
                let stopped = expectation(description: "overrun")
                let playback = driver(plan(hz, duration: 2), torch) { reason in
                    XCTAssertEqual(reason, .cannotKeepUp)
                    stopped.fulfill()
                }
                playback.start()
                wait(for: [stopped], timeout: 2)
                XCTAssertEqual(torch.commands.filter { $0.level > 0 }.count, 1)
                XCTAssertEqual(torch.commands.last?.level, 0)
                XCTAssertEqual(playback.stats.dropped, Int(2 * hz) - 1)
                XCTAssertLessThan(torch.now, 2)
            }
        }
    }

    func testBothIntervalsRemainAtLeastPlannedLengthWithSmallCommandLatency() {
        for hz in [10.0, 20.0] {
            let torch = AdversarialTorch()
            torch.positiveDelay = 0.001
            torch.offDelay = 0.001
            let stopped = expectation(description: "finished")
            let playback = driver(plan(hz, duration: 1), torch) { _ in stopped.fulfill() }
            playback.start()
            wait(for: [stopped], timeout: 2)
            let commands = torch.commands
            for index in 1..<commands.count {
                // Final emergency off has priority over interval preservation.
                if index == commands.count - 1 { continue }
                XCTAssertGreaterThanOrEqual(commands[index].issued - commands[index - 1].returned,
                                            0.5 / hz - 1e-9)
            }
            XCTAssertEqual(commands.last?.level, 0)
            XCTAssertLessThanOrEqual(torch.now, 1.001 + 1e-9)
        }
    }

    func testExpiredPlanNeverIssuesNewPositiveCommandIncludingStalledCapabilityQuery() {
        for delay in [0.03, 0.8] {
            let torch = AdversarialTorch()
            torch.capabilityDelay = delay
            let stopped = expectation(description: "expired")
            let playback = driver(plan(1, duration: 0.02), torch) { reason in
                XCTAssertEqual(reason, .finished)
                stopped.fulfill()
            }
            playback.start()
            wait(for: [stopped], timeout: 2)
            XCTAssertTrue(torch.commands.allSatisfy { $0.level == 0 })
            XCTAssertEqual(playback.stats.dropped, 1)
        }
    }

    func testThermalTimeoutAndOnFailureAllRequestOffBeforeCallback() {
        for mode in 0..<3 {
            let torch = AdversarialTorch()
            torch.rejectPositive = mode == 2
            let stopped = expectation(description: "exit")
            let playback = driver(plan(), torch, timeout: mode == 1 ? 0.02 : 100,
                                  thermal: { mode == 0 && torch.now >= 0.02 ? .serious : .nominal }) { reason in
                XCTAssertEqual(torch.commands.last?.level, 0)
                if mode == 0 { XCTAssertEqual(reason, .thermal) }
                if mode == 1 { XCTAssertEqual(reason, .timeout) }
                if mode == 2 { XCTAssertEqual(reason, .failure(.configurationFailed("on rejected"))) }
                stopped.fulfill()
            }
            playback.start()
            wait(for: [stopped], timeout: 2)
            XCTAssertTrue(torch.commands.contains { $0.level > 0 })
            XCTAssertEqual(torch.commands.last?.level, 0)
        }
    }

    func testPositiveCallReturningAfterPlanEndStopsWithoutAnotherPositiveRequest() {
        let torch = AdversarialTorch()
        torch.positiveDelay = 0.8
        let stopped = expectation(description: "command exceeded duration")
        let playback = driver(plan(10, duration: 0.2), torch) { reason in
            XCTAssertEqual(reason, .cannotKeepUp)
            stopped.fulfill()
        }
        playback.start()
        wait(for: [stopped], timeout: 2)
        XCTAssertEqual(torch.commands.map(\.level), [0.5, 0])
        XCTAssertEqual(playback.stats.dropped, 1)
        XCTAssertEqual(torch.commands.last?.issued ?? -1, 0.8, accuracy: 1e-9)
    }

    func testOffEdgeRejectionSurvivesSuccessfulTerminationRetry() {
        let torch = AdversarialTorch()
        torch.rejectOffCount = 1
        let stopped = expectation(description: "off rejection")
        let playback = driver(plan(), torch) { reason in
            XCTAssertEqual(reason, .failure(.configurationFailed("off rejected")))
            stopped.fulfill()
        }
        playback.start()
        wait(for: [stopped], timeout: 2)
        XCTAssertEqual(playback.offCommandError, .configurationFailed("off rejected"))
        XCTAssertEqual(torch.commands.last?.level, 0)
        XCTAssertEqual(torch.commands.filter { $0.level == 0 }.count, 2)
    }

    func testTerminationOffRejectionIsRetainedEvenIfRetrySucceeds() {
        let torch = AdversarialTorch()
        torch.rejectOffCount = 1
        let stopped = expectation(description: "finished with off warning")
        let playback = driver(plan(1, duration: 0.02), torch) { _ in stopped.fulfill() }
        playback.start()
        wait(for: [stopped], timeout: 2)
        XCTAssertEqual(playback.offCommandError, .configurationFailed("off rejected"))
        XCTAssertEqual(torch.commands.map(\.level), [0.5, 0, 0])
    }

    func testBothTerminationOffRequestsCanFailAndErrorStillPublishes() {
        let torch = AdversarialTorch()
        torch.rejectOffCount = 2
        let stopped = expectation(description: "both off attempts rejected")
        let playback = driver(plan(1, duration: 0.02), torch) { _ in stopped.fulfill() }
        playback.start()
        wait(for: [stopped], timeout: 2)
        XCTAssertEqual(playback.offCommandError, .configurationFailed("off rejected"))
        XCTAssertEqual(torch.commands.map(\.level), [0.5, 0, 0], "Recorded attempts do not establish darkness")
    }

    func testStatsPeakAndCancelRequestDoNotWaitForBlockedHardware() {
        for phase in 0..<4 {
            let torch = AdversarialTorch()
            let entered = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            let block = { entered.signal(); _ = release.wait(timeout: .now() + 3) }
            switch phase {
            case 0: torch.beforeAcquire = block
            case 1: torch.beforePositive = block
            case 2: torch.beforeOff = block
            default: torch.beforeRelease = block
            }
            let playback = driver(plan(1, duration: 0.02), torch) { _ in }
            playback.start()
            XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
            let start = MonotonicClock.now()
            _ = playback.stats
            playback.setPeak(0.08)
            playback.requestCancel()
            XCTAssertLessThan(MonotonicClock.now() - start, 0.1)
            release.signal()
            playback.cancel() // No commands follow the serialized shutdown barrier.
            XCTAssertEqual(torch.commands.map(\.level), phase == 0 ? [0] : [0.5, 0])
            XCTAssertNil(playback.offCommandError)
        }
    }

    func testInvalidCapsNeverIssuePositiveRequests() {
        for cap in [Float(-0.5), 0, .nan, .infinity] {
            let torch = AdversarialTorch()
            torch.caps = [cap]
            let stopped = expectation(description: "invalid cap")
            let playback = driver(plan(), torch) { reason in
                XCTAssertEqual(reason, .thermal)
                stopped.fulfill()
            }
            playback.start()
            wait(for: [stopped], timeout: 2)
            XCTAssertEqual(torch.commands.map(\.level), [0])
        }
    }

    func testThermalChangeDuringCapabilityQueryPreventsPositiveAdmission() {
        let torch = AdversarialTorch()
        torch.capabilityDelay = 0.03
        let stopped = expectation(description: "thermal admission")
        let playback = driver(plan(), torch, thermal: { torch.now >= 0.02 ? .serious : .nominal }) { reason in
            XCTAssertEqual(reason, .thermal)
            stopped.fulfill()
        }
        playback.start()
        wait(for: [stopped], timeout: 2)
        XCTAssertEqual(torch.commands.map(\.level), [0])
    }

    func testStableInstantaneousAdapterCompletesLongPlansAtTenAndTwentyHz() {
        for hz in [10.0, 20.0] {
            let torch = AdversarialTorch()
            let stopped = expectation(description: "stable virtual minute")
            let playback = driver(plan(hz, duration: 60), torch) { reason in
                XCTAssertEqual(reason, .finished)
                stopped.fulfill()
            }
            playback.start()
            wait(for: [stopped], timeout: 2)
            XCTAssertEqual(playback.stats.flashes, Int(60 * hz))
            XCTAssertEqual(playback.stats.dropped, 0)
            XCTAssertEqual(torch.now, 60, accuracy: 1e-9)
            XCTAssertEqual(torch.commands.last?.level, 0)
        }
    }

    func testSmallPersistentCommandLatencyEventuallyStopsRatherThanCompresses() {
        let torch = AdversarialTorch()
        torch.positiveDelay = 0.001
        torch.offDelay = 0.001
        let stopped = expectation(description: "sustained latency")
        let playback = driver(plan(20, duration: 60), torch) { reason in
            XCTAssertEqual(reason, .cannotKeepUp)
            stopped.fulfill()
        }
        playback.start()
        wait(for: [stopped], timeout: 2)
        XCTAssertGreaterThan(playback.stats.flashes, 1)
        XCTAssertGreaterThan(playback.stats.dropped, 0)
        XCTAssertLessThan(torch.now, 60)
        XCTAssertEqual(torch.commands.last?.level, 0)
    }

    func testAdapterCapIsSampledOncePerPositiveEdgeAndWithdrawalStopsPlayback() {
        let torch = AdversarialTorch()
        torch.caps = [0.08, 0]
        let stopped = expectation(description: "cap withdrawn")
        let playback = driver(plan(10, peak: 0.5), torch) { reason in
            XCTAssertEqual(reason, .thermal)
            stopped.fulfill()
        }
        playback.start()
        wait(for: [stopped], timeout: 2)
        XCTAssertEqual(torch.commands.map(\.level), [0.08, 0, 0])
        XCTAssertEqual(playback.stats.flashes, 1)
        XCTAssertEqual(playback.stats.dropped, 9)
    }

    func testCancelBeforeStartStillShutsDownOnWorker() {
        let torch = AdversarialTorch()
        let playback = driver(plan(), torch) { _ in XCTFail("Cancelled callback") }
        playback.requestCancel()
        playback.start()
        playback.cancel()
        XCTAssertEqual(torch.commands.map(\.level), [0])
    }

    func testExplicitAdapterRequestNeverRoundsUpIncludingFadeBoundaries() {
        for level in [Float(0.0001), 0.0249, 0.025, 0.0499, 0.05, 0.0501, 0.0749, 0.08, 0.0999, 1] {
            XCTAssertEqual(SystemTorchDevice.requestLevel(level), level)
            XCTAssertLessThanOrEqual(SystemTorchDevice.requestLevel(level), level)
        }
        let torch = AdversarialTorch()
        let stopped = expectation(description: "fade")
        let rendered = plan(10, duration: 0.3, peak: 0.05, fade: 1)
        let playback = driver(rendered, torch) { _ in stopped.fulfill() }
        playback.start()
        wait(for: [stopped], timeout: 2)
        let positive = torch.commands.filter { $0.level > 0 }
        XCTAssertEqual(positive.first?.level ?? 0, 0.025, accuracy: 1e-6)
        for (command, edge) in zip(positive, rendered.edges.filter { $0.level > 0 }) {
            XCTAssertLessThanOrEqual(command.level, edge.level * rendered.peakTorchLevel)
        }
    }
}

@MainActor
final class TorchControllerAdversarialTests: XCTestCase {
    private var plan: LightPlan {
        LightPlan(program: .custom(startHz: 10, endHz: 10), preparationDelay: 0,
                  lightDuration: 1, peakTorchLevel: 0.5, fadeIn: 0, fadeOut: 0)
    }

    func testStepRejectsInvalidCapsWithoutPositiveCommands() throws {
        for cap in [Float(-0.5), 0, .nan, .infinity] {
            let hardware = AdversarialTorch()
            hardware.caps = [cap]
            let controller = TorchController(device: hardware, clock: { hardware.now },
                                             notificationCenter: NotificationCenter(), schedulesTimers: false)
            try controller.start(plan)
            XCTAssertFalse(controller.isRunning)
            XCTAssertEqual(controller.lastStopReason, .thermal)
            XCTAssertTrue(hardware.commands.allSatisfy { $0.level == 0 })
        }
    }

    func testStepSamplesCapOnceAndStopsOnSubsequentWithdrawal() throws {
        let hardware = AdversarialTorch()
        hardware.caps = [0.08, 0]
        let controller = TorchController(device: hardware, clock: { hardware.now },
                                         notificationCenter: NotificationCenter(), schedulesTimers: false)
        try controller.start(plan)
        XCTAssertEqual(hardware.commands.last?.level, 0.08)
        hardware.advance(0.05)
        controller.step()
        hardware.advance(0.05)
        controller.step()
        XCTAssertEqual(controller.lastStopReason, .thermal)
        XCTAssertEqual(hardware.commands.map(\.level), [0, 0.08, 0, 0])
    }

    func testQueuedCompletionFromPriorRunCannotStopRestart() async throws {
        let hardware = AdversarialTorch()
        let released = DispatchSemaphore(value: 0)
        hardware.beforeRelease = { released.signal() }
        let controller = TorchController(device: hardware, notificationCenter: NotificationCenter())
        var callbacks = 0
        controller.onStop = { _ in callbacks += 1 }
        let short = LightPlan(program: .custom(startHz: 1, endHz: 1), preparationDelay: 0,
                              lightDuration: 0.02, peakTorchLevel: 0.5, fadeIn: 0, fadeOut: 0)
        try controller.start(short)
        // Withhold old main callback until a new generation owns playback.
        XCTAssertEqual(released.wait(timeout: .now() + 2), .success)
        let long = LightPlan(program: .custom(startHz: 1, endHz: 1), preparationDelay: 0,
                             lightDuration: 10, peakTorchLevel: 0.08, fadeIn: 0, fadeOut: 0)
        try controller.start(long)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(controller.isRunning)
        XCTAssertEqual(callbacks, 0, "Old queued completion cannot stop or notify the new run")
        controller.hardStop()
        XCTAssertEqual(callbacks, 1)
        XCTAssertEqual(hardware.commands.last?.level, 0)
    }
}
