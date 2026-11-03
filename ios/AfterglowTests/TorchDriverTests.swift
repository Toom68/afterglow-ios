import XCTest
@testable import Afterglow

/// Thread-safe torch double for real-time playback tests.
final class RecordingTorch: TorchDevice, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Float] = []
    var hasTorch: Bool { true }
    var isTorchAvailable: Bool { true }
    var maxAvailableLevel: Float { 1 }

    var levels: [Float] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
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

    func testEveryFlashArrivesEvenWhileTheMainThreadIsBusy() {
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
