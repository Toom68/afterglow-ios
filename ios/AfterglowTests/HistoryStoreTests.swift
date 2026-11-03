import XCTest
@testable import Afterglow

@MainActor
final class HistoryStoreTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL { directory.appendingPathComponent("history.json") }
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore(now: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> HistoryStore {
        HistoryStore(fileURL: fileURL, now: { now }, calendar: calendar)
    }

    private func record(minutesListened: Double, outcome: SessionOutcome = .completed, startedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> SessionRecord {
        SessionRecord(presetID: "settle", title: "Settle In", soundscape: .ember, startedAt: startedAt, plannedDuration: 600, listenedDuration: minutesListened * 60, outcome: outcome)
    }

    func testRecordsPersistAcrossLaunches() {
        let store = makeStore()
        let saved = record(minutesListened: 10)
        store.record(saved)
        let entry = store.addJournal(text: "  Felt lighter.  ", mood: .settled, sessionID: saved.id)

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.sessions, [saved])
        XCTAssertEqual(reloaded.journal.count, 1)
        XCTAssertEqual(reloaded.journal.first?.text, "Felt lighter.")
        XCTAssertEqual(reloaded.journal.first?.id, entry?.id)
        XCTAssertEqual(reloaded.journalEntry(forSession: saved.id)?.mood, .settled)
        XCTAssertNil(reloaded.lastError)
    }

    func testAccidentalShortSessionsAreNotRecorded() {
        let store = makeStore()
        store.record(record(minutesListened: 0.2, outcome: .endedEarly))
        XCTAssertTrue(store.sessions.isEmpty)
        store.record(record(minutesListened: 1, outcome: .endedEarly))
        XCTAssertEqual(store.sessions.count, 1)
    }

    func testDuplicateRecordIsIgnored() {
        let store = makeStore()
        let saved = record(minutesListened: 10)
        store.record(saved)
        store.record(saved)
        XCTAssertEqual(store.sessions.count, 1)
    }

    func testSessionsAreNewestFirst() {
        let store = makeStore()
        let older = record(minutesListened: 5, startedAt: Date(timeIntervalSince1970: 1_000))
        let newer = record(minutesListened: 5, startedAt: Date(timeIntervalSince1970: 2_000))
        store.record(newer)
        store.record(older)
        XCTAssertEqual(store.sessions.map(\.id), [newer.id, older.id])
    }

    func testEmptyJournalEntriesAreDiscarded() {
        let store = makeStore()
        XCTAssertNil(store.addJournal(text: "   \n  "))
        XCTAssertTrue(store.journal.isEmpty)
        XCTAssertNotNil(store.addJournal(text: "", mood: .neutral), "A mood alone is a valid check-in")
    }

    func testUpdatingAndDeletingJournal() throws {
        let store = makeStore()
        var entry = try XCTUnwrap(store.addJournal(text: "First"))
        entry.text = "Second thoughts"
        store.updateJournal(entry)
        XCTAssertEqual(makeStore().journal.first?.text, "Second thoughts")

        entry.text = " "
        store.updateJournal(entry)
        XCTAssertTrue(store.journal.isEmpty, "Clearing an entry removes it")

        let other = try XCTUnwrap(store.addJournal(text: "Keep?"))
        store.deleteJournal(id: other.id)
        XCTAssertTrue(makeStore().journal.isEmpty)
    }

    func testJournalTextIsBounded() throws {
        let store = makeStore()
        let entry = try XCTUnwrap(store.addJournal(text: String(repeating: "a", count: JournalEntry.maximumLength + 50)))
        XCTAssertEqual(entry.text.count, JournalEntry.maximumLength)
    }

    func testDeletingSessionKeepsJournalButUnlinksIt() throws {
        let store = makeStore()
        let saved = record(minutesListened: 10)
        store.record(saved)
        store.addJournal(text: "Note", sessionID: saved.id)
        store.deleteSession(id: saved.id)
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertEqual(store.journal.count, 1)
        XCTAssertNil(store.journal.first?.sessionID)
    }

    func testCorruptFileIsQuarantinedNotOverwritten() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)

        let store = makeStore()
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertNotNil(store.lastError)
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.contains("corrupt") }
        XCTAssertEqual(backups.count, 1)
        let backup = directory.appendingPathComponent(backups[0])
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "not json")
    }

    func testNewerFormatIsNeverOverwritten() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let future = #"{"version": 99, "sessions": [], "journal": []}"#
        try Data(future.utf8).write(to: fileURL)

        let store = makeStore()
        XCTAssertTrue(store.writesBlocked)
        store.record(record(minutesListened: 10))
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), future)

        store.eraseAll()
        XCTAssertEqual(try HistoryFile.load(from: fileURL), HistoryArchive())
    }

    func testBlockedWritesAreRefusedEvenAfterDismissingTheError() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let future = #"{"version": 99, "sessions": [], "journal": []}"#
        try Data(future.utf8).write(to: fileURL)

        let store = makeStore()
        store.dismissError()
        XCTAssertNil(store.lastError)

        XCTAssertNil(store.addJournal(text: "Will this save?"))
        XCTAssertTrue(store.journal.isEmpty, "Unsaved entries must not appear saved")
        XCTAssertNotNil(store.lastError, "The refusal must be visible")

        store.dismissError()
        XCTAssertFalse(store.updateJournal(JournalEntry(text: "x")))
        XCTAssertFalse(store.record(record(minutesListened: 10)))
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertNotNil(store.lastError)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), future)
    }

    func testFailedSaveRollsBackInMemoryChange() throws {
        // A plain file where the parent folder should be makes every save fail.
        try Data("not a folder".utf8).write(to: directory)
        let store = makeStore()
        XCTAssertNil(store.lastError, "Nothing on disk yet, so loading succeeds")

        XCTAssertNil(store.addJournal(text: "Lost?"))
        XCTAssertTrue(store.journal.isEmpty)
        XCTAssertFalse(store.record(record(minutesListened: 10)))
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertNotNil(store.lastError)
    }

    func testStatsAndStreak() {
        let day: TimeInterval = 86_400
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let sessions = [
            record(minutesListened: 10, startedAt: now.addingTimeInterval(-60)),
            record(minutesListened: 5, outcome: .endedEarly, startedAt: now.addingTimeInterval(-day)),
            record(minutesListened: 10, startedAt: now.addingTimeInterval(-2 * day)),
            record(minutesListened: 10, startedAt: now.addingTimeInterval(-5 * day))
        ]
        let stats = HistoryStats.compute(sessions: sessions, now: now, calendar: calendar)
        XCTAssertEqual(stats.totalSessions, 4)
        XCTAssertEqual(stats.completedSessions, 3)
        XCTAssertEqual(stats.totalMinutes, 35)
        XCTAssertEqual(stats.currentStreakDays, 3)
    }

    func testStreakSurvivesUntilEndOfNextDay() {
        let day: TimeInterval = 86_400
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let yesterday = [record(minutesListened: 10, startedAt: now.addingTimeInterval(-day))]
        XCTAssertEqual(HistoryStats.compute(sessions: yesterday, now: now, calendar: calendar).currentStreakDays, 1)
        let lapsed = [record(minutesListened: 10, startedAt: now.addingTimeInterval(-2 * day))]
        XCTAssertEqual(HistoryStats.compute(sessions: lapsed, now: now, calendar: calendar).currentStreakDays, 0)
        XCTAssertEqual(HistoryStats.compute(sessions: [], now: now, calendar: calendar), .empty)
    }
}
