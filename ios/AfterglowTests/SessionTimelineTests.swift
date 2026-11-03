import XCTest
@testable import Afterglow

final class SessionTimelineTests: XCTestCase {
    func testElapsedAccumulatesAcrossPauseAndResume() {
        var timeline = SessionTimeline(duration: 600)
        XCTAssertTrue(timeline.start(at: 100))
        XCTAssertEqual(timeline.elapsed(at: 160), 60, accuracy: 0.0001)

        XCTAssertTrue(timeline.pause(.user, at: 160))
        XCTAssertEqual(timeline.phase, .paused(.user))
        XCTAssertEqual(timeline.elapsed(at: 10_000), 60, accuracy: 0.0001, "Time must not advance while paused")

        XCTAssertTrue(timeline.resume(at: 500))
        XCTAssertEqual(timeline.elapsed(at: 530), 90, accuracy: 0.0001)
        XCTAssertEqual(timeline.remaining(at: 530), 510, accuracy: 0.0001)
        XCTAssertEqual(timeline.progress(at: 530), 0.15, accuracy: 0.0001)
    }

    func testInvalidTransitionsAreRejected() {
        var timeline = SessionTimeline(duration: 60)
        XCTAssertFalse(timeline.pause(.user, at: 0))
        XCTAssertFalse(timeline.resume(at: 0))
        XCTAssertFalse(timeline.end(.endedEarly, at: 0))
        XCTAssertTrue(timeline.start(at: 0))
        XCTAssertFalse(timeline.start(at: 1), "Cannot start twice")
        XCTAssertFalse(timeline.resume(at: 1), "Cannot resume while running")
        XCTAssertTrue(timeline.pause(.user, at: 2))
        XCTAssertFalse(timeline.pause(.interruption, at: 3), "A second pause keeps the original reason")
        XCTAssertEqual(timeline.phase, .paused(.user))
    }

    func testTickCompletesExactlyOnce() {
        var timeline = SessionTimeline(duration: 60)
        timeline.start(at: 0)
        XCTAssertFalse(timeline.tick(at: 59.9))
        XCTAssertTrue(timeline.tick(at: 60))
        XCTAssertEqual(timeline.phase, .finished(.completed))
        XCTAssertFalse(timeline.tick(at: 61))
        XCTAssertEqual(timeline.elapsed(at: 5_000), 60)
    }

    func testEndingEarlyKeepsListenedTime() {
        var timeline = SessionTimeline(duration: 600)
        timeline.start(at: 0)
        XCTAssertTrue(timeline.end(.endedEarly, at: 125))
        XCTAssertEqual(timeline.phase, .finished(.endedEarly))
        XCTAssertEqual(timeline.elapsed(at: 999), 125, accuracy: 0.0001)
        XCTAssertFalse(timeline.end(.endedEarly, at: 130), "Finished sessions cannot end again")
    }

    func testEndingAfterDurationCountsAsCompleted() {
        var timeline = SessionTimeline(duration: 60)
        timeline.start(at: 0)
        XCTAssertTrue(timeline.end(.interrupted, at: 75))
        XCTAssertEqual(timeline.phase, .finished(.completed))
    }

    func testLatePauseCompletesInsteadOfPausing() {
        var timeline = SessionTimeline(duration: 60)
        timeline.start(at: 0)
        XCTAssertFalse(timeline.pause(.interruption, at: 90))
        XCTAssertEqual(timeline.phase, .finished(.completed))
    }

    func testClockGoingBackwardsNeverProducesNegativeTime() {
        var timeline = SessionTimeline(duration: 60)
        timeline.start(at: 100)
        XCTAssertEqual(timeline.elapsed(at: 50), 0)
    }
}
