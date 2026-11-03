import Combine
import Foundation

enum HistoryFileError: Error, Equatable {
    case unsupportedVersion(Int)
}

/// Reads and writes the history archive as JSON. Stateless so it can be tested against a temp dir.
enum HistoryFile {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Returns an empty archive when no file exists yet. Throws on unreadable or corrupt data.
    static func load(from url: URL, fileManager: FileManager = .default) throws -> HistoryArchive {
        guard fileManager.fileExists(atPath: url.path) else { return HistoryArchive() }
        let data = try Data(contentsOf: url)
        let archive = try makeDecoder().decode(HistoryArchive.self, from: data)
        guard archive.version <= HistoryArchive.currentVersion else {
            throw HistoryFileError.unsupportedVersion(archive.version)
        }
        return archive
    }

    static func save(_ archive: HistoryArchive, to url: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try makeEncoder().encode(archive)
        #if os(iOS)
        // Sessions can finish while the device is locked, so "until first unlock" is the
        // strongest protection class that still allows the background write.
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
    }

    /// Moves an unreadable file aside so the user's data is preserved for recovery instead of
    /// being overwritten by the next save.
    @discardableResult
    static func quarantine(_ url: URL, fileManager: FileManager = .default, now: Date = Date()) -> URL? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let stamp = Int(now.timeIntervalSince1970)
        let destination = url.deletingPathExtension().appendingPathExtension("corrupt-\(stamp).json")
        do {
            try fileManager.moveItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var sessions: [SessionRecord] = []
    @Published private(set) var journal: [JournalEntry] = []
    @Published private(set) var lastError: String?

    let fileURL: URL
    /// True when the file on disk came from a newer app version; saving would destroy it.
    @Published private(set) var writesBlocked = false
    private let now: () -> Date
    private let calendar: Calendar

    nonisolated static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Afterglow", isDirectory: true).appendingPathComponent("history.json")
    }

    init(fileURL: URL = HistoryStore.defaultFileURL, now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.fileURL = fileURL
        self.now = now
        self.calendar = calendar
        reload()
    }

    var stats: HistoryStats {
        HistoryStats.compute(sessions: sessions, now: now(), calendar: calendar)
    }

    func reload() {
        do {
            let archive = try HistoryFile.load(from: fileURL)
            sessions = archive.sessions.sorted { $0.startedAt > $1.startedAt }
            journal = archive.journal.sorted { $0.createdAt > $1.createdAt }
            writesBlocked = false
            lastError = nil
        } catch HistoryFileError.unsupportedVersion(let version) {
            // Never overwrite data written by a newer build.
            sessions = []
            journal = []
            writesBlocked = true
            lastError = "Your history was saved by a newer version of Afterglow (format \(version)). Update the app to see it."
        } catch {
            HistoryFile.quarantine(fileURL, now: now())
            sessions = []
            journal = []
            lastError = "Your history file could not be read, so a backup was kept and a fresh history was started."
        }
    }

    /// Each mutation returns `false` (and sets `lastError`) when nothing was saved. Blocked or
    /// failed writes leave the in-memory state unchanged, so the UI never shows unsaved data as saved.
    @discardableResult
    func record(_ record: SessionRecord) -> Bool {
        guard record.isWorthRecording, !sessions.contains(where: { $0.id == record.id }) else { return false }
        return commit {
            $0.sessions.insert(record, at: 0)
            $0.sessions.sort { $0.startedAt > $1.startedAt }
        }
    }

    @discardableResult
    func deleteSession(id: UUID) -> Bool {
        commit {
            $0.sessions.removeAll { $0.id == id }
            for index in $0.journal.indices where $0.journal[index].sessionID == id {
                $0.journal[index].sessionID = nil
            }
        }
    }

    @discardableResult
    func addJournal(text: String, mood: Mood? = nil, sessionID: UUID? = nil) -> JournalEntry? {
        let entry = JournalEntry(createdAt: now(), sessionID: sessionID, mood: mood, text: text)
        guard !entry.isEmpty else { return nil }
        guard commit({ $0.journal.insert(entry, at: 0) }) else { return nil }
        return entry
    }

    /// Saving an entry whose text and mood are both empty deletes it.
    @discardableResult
    func updateJournal(_ entry: JournalEntry) -> Bool {
        guard let index = journal.firstIndex(where: { $0.id == entry.id }) else { return false }
        var updated = entry
        updated.text = JournalEntry.sanitize(entry.text)
        updated.updatedAt = now()
        return commit {
            if updated.isEmpty {
                $0.journal.remove(at: index)
            } else {
                $0.journal[index] = updated
            }
        }
    }

    @discardableResult
    func deleteJournal(id: UUID) -> Bool {
        commit { $0.journal.removeAll { $0.id == id } }
    }

    func journalEntry(forSession sessionID: UUID) -> JournalEntry? {
        journal.first { $0.sessionID == sessionID }
    }

    func session(id: UUID) -> SessionRecord? {
        sessions.first { $0.id == id }
    }

    /// Explicit user request: this is the only path allowed to replace a newer-format file.
    @discardableResult
    func eraseAll() -> Bool {
        let wasBlocked = writesBlocked
        writesBlocked = false
        let erased = commit { $0 = HistoryArchive() }
        if !erased { writesBlocked = wasBlocked }
        return erased
    }

    func dismissError() {
        lastError = nil
    }

    private static let blockedMessage = "Your history was saved by a newer version of Afterglow, so nothing can be saved until you update the app."

    /// Applies `change` to a copy, writes it, and only then publishes it.
    private func commit(_ change: (inout HistoryArchive) -> Void) -> Bool {
        guard !writesBlocked else {
            lastError = Self.blockedMessage
            return false
        }
        var archive = HistoryArchive(sessions: sessions, journal: journal)
        change(&archive)
        do {
            try HistoryFile.save(archive, to: fileURL)
        } catch {
            lastError = "Afterglow could not save your history: \(error.localizedDescription)"
            return false
        }
        sessions = archive.sessions
        journal = archive.journal
        lastError = nil
        return true
    }
}
