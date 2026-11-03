import SwiftUI

struct JournalView: View {
    @EnvironmentObject private var history: HistoryStore
    @State private var showingComposer = false
    @State private var editingEntry: JournalEntry?
    @State private var pendingDelete: JournalEntry?

    private var exportText: String {
        var lines = ["Afterglow journal", "Exported \(Date().formatted(date: .long, time: .shortened))", ""]
        for entry in history.journal {
            lines.append(entry.createdAt.formatted(date: .long, time: .shortened))
            if let mood = entry.mood { lines.append("Feeling: \(mood.title)") }
            if let id = entry.sessionID, let session = history.session(id: id) {
                lines.append("Session: \(session.title)")
            }
            lines.append(entry.text)
            lines.append("\n---\n")
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "The moment after")
                        Text("Leave a little\nfor yourself.")
                            .agFont(37, weight: .regular, design: .serif)
                        Text("Notice what stayed with you. A word or two is enough.")
                            .agFont(14).foregroundStyle(AfterglowTheme.muted).lineSpacing(4)
                    }
                    .padding(.top, 12)

                    PrimaryButton(title: "Write a reflection", symbol: "plus") { showingComposer = true }
                        .disabled(history.writesBlocked)
                        .opacity(history.writesBlocked ? 0.45 : 1)

                    if history.writesBlocked {
                        WritesBlockedNotice(detail: history.lastError)
                    } else if let error = history.lastError {
                        AfterglowCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("A note about your data", systemImage: "exclamationmark.circle")
                                    .foregroundStyle(AfterglowTheme.gold)
                                Text(error).agFont(13).foregroundStyle(AfterglowTheme.muted)
                                Button("Dismiss") { history.dismissError() }
                                    .agFont(13).tint(AfterglowTheme.gold)
                            }
                        }
                    }

                    if history.journal.isEmpty {
                        emptyJournal
                    } else {
                        HStack {
                            SectionTitle(title: "Your reflections", detail: "\(history.journal.count)")
                            ShareLink(item: exportText) {
                                Image(systemName: "square.and.arrow.up")
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Export journal")
                        }
                        ForEach(history.journal) { entry in
                            Button { editingEntry = entry } label: { journalCard(entry) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Edit", systemImage: "pencil") { editingEntry = entry }
                                    ShareLink(item: shareText(for: entry)) { Label("Share reflection", systemImage: "square.and.arrow.up") }
                                    if !history.writesBlocked {
                                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = entry }
                                    }
                                }
                        }
                    }

                    if !history.sessions.isEmpty {
                        SectionTitle(title: "Recent moments", detail: "\(history.stats.totalMinutes) MIN TOTAL")
                        ForEach(Array(history.sessions.prefix(15))) { session in
                            sessionRow(session)
                        }
                    }
                }
                .padding(24)
                .padding(.bottom, 24)
            }
            .navigationTitle("Reflect")
            .navigationBarTitleDisplayMode(.inline)
            .afterglowScreen()
            .sheet(isPresented: $showingComposer) { JournalEditor() }
            .sheet(item: $editingEntry) { entry in JournalEditor(entry: entry) }
            .confirmationDialog(
                "Delete this reflection?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { entry in
                Button("Delete", role: .destructive) {
                    history.deleteJournal(id: entry.id)
                    pendingDelete = nil
                }
                Button("Keep it", role: .cancel) { pendingDelete = nil }
            } message: { _ in
                Text("This removes it from this device. Exported copies are separate.")
            }
        }
    }

    private func shareText(for entry: JournalEntry) -> String {
        var lines = [entry.createdAt.formatted(date: .long, time: .shortened)]
        if let mood = entry.mood { lines.append("Feeling: \(mood.title)") }
        if !entry.text.isEmpty { lines.append(entry.text) }
        return lines.joined(separator: "\n")
    }

    private var emptyJournal: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.pages")
                .agFont(38, weight: .ultraLight).foregroundStyle(AfterglowTheme.gold)
            Text("A page to come back to")
                .agFont(23, weight: .regular, design: .serif)
            Text("Reflections from your sessions will appear here. You can also write whenever you like.")
                .agFont(14).foregroundStyle(AfterglowTheme.muted)
                .multilineTextAlignment(.center).lineSpacing(4)
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.vertical, 35)
    }

    private func journalCard(_ entry: JournalEntry) -> some View {
        AfterglowCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(entry.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .agFont(11, design: .monospaced).foregroundStyle(AfterglowTheme.muted)
                    Spacer()
                    if let mood = entry.mood {
                        TagPill(title: mood.title, symbol: mood.symbolName, tint: AfterglowTheme.sage)
                    }
                }
                if !entry.text.isEmpty {
                    Text(entry.text).agFont(15).lineSpacing(5)
                        .foregroundStyle(AfterglowTheme.ink).lineLimit(5).multilineTextAlignment(.leading)
                }
                if let id = entry.sessionID, let session = history.session(id: id) {
                    Label(session.title, systemImage: "waveform")
                        .agFont(11).foregroundStyle(AfterglowTheme.muted)
                }
            }
        }
    }

    private func sessionRow(_ session: SessionRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: session.outcome == .completed ? "checkmark.circle" : "circle.lefthalf.filled")
                .foregroundStyle(AfterglowTheme.sage)
            VStack(alignment: .leading, spacing: 5) {
                Text(session.title).agFont(14)
                Text("\(session.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(session.outcome == .completed ? "Completed" : "Ended early")")
                    .agFont(10).foregroundStyle(AfterglowTheme.muted)
            }
            Spacer()
            Text("\(Int(session.listenedDuration / 60))m")
                .agFont(12, design: .monospaced).foregroundStyle(AfterglowTheme.muted)
        }
        .padding(.vertical, 10)
    }
}

struct MoodPicker: View {
    @Binding var selection: Mood?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How are you arriving here?")
                .agFont(15, weight: .medium)
            ViewThatFits(in: .horizontal) {
                moodButtons
                ScrollView(.horizontal, showsIndicators: false) { moodButtons }
            }
        }
    }

    private var moodButtons: some View {
        HStack(spacing: 8) {
            ForEach(Mood.allCases) { mood in
                Button { selection = selection == mood ? nil : mood } label: {
                    VStack(spacing: 8) {
                        Image(systemName: mood.symbolName).agFont(20, weight: .light)
                        Text(mood.title).agFont(9)
                    }
                    .foregroundStyle(selection == mood ? AfterglowTheme.gold : AfterglowTheme.muted)
                    .frame(minWidth: 49, minHeight: 66)
                    .padding(.horizontal, 3)
                    .background(selection == mood ? AfterglowTheme.gold.opacity(0.10) : AfterglowTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(selection == mood ? AfterglowTheme.gold.opacity(0.5) : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mood.title)
                .accessibilityAddTraits(selection == mood ? [.isSelected] : [])
            }
        }
    }
}

struct JournalEditor: View {
    @EnvironmentObject private var history: HistoryStore
    @Environment(\.dismiss) private var dismiss
    var entry: JournalEntry?
    @State private var text: String
    @State private var mood: Mood?
    @State private var confirmingDelete = false
    @State private var confirmingDiscard = false
    @State private var attemptedSave = false
    /// A save changed the in-memory journal but its write has not been confirmed yet.
    @State private var pendingWrite = false
    /// Entry inserted by a save whose write failed; retries update it instead of adding a duplicate.
    @State private var createdEntry: JournalEntry?
    private let baselineText: String
    private let baselineMood: Mood?

    init(entry: JournalEntry? = nil) {
        self.entry = entry
        baselineText = JournalEntry.sanitize(entry?.text ?? "")
        baselineMood = entry?.mood
        _text = State(initialValue: entry?.text ?? "")
        _mood = State(initialValue: entry?.mood)
    }

    private var isEmptyDraft: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && mood == nil
    }

    /// True while there is typed or chosen content that has not been confirmed as written to disk.
    private var hasUnsavedChanges: Bool {
        JournalEntry.sanitize(text) != baselineText || mood != baselineMood || pendingWrite
    }

    private var canSave: Bool { !isEmptyDraft && !history.writesBlocked }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text(entry == nil ? "What’s on your mind?" : "Return to this moment.")
                        .agFont(30, weight: .regular, design: .serif)
                    if history.writesBlocked {
                        WritesBlockedNotice(detail: history.lastError)
                    }
                    MoodPicker(selection: $mood)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("A note to yourself").agFont(14, weight: .medium)
                        TextEditor(text: $text)
                            .agFont(16).lineSpacing(5)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 240)
                            .padding(12)
                            .background(AfterglowTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                            .accessibilityLabel("Reflection")
                            .onChange(of: text) { _, newValue in
                                if newValue.count > JournalEntry.maximumLength {
                                    text = String(newValue.prefix(JournalEntry.maximumLength))
                                }
                            }
                        Text("Only on your device, unless you choose to share it.")
                            .agFont(11).foregroundStyle(AfterglowTheme.muted)
                    }
                    PrimaryButton(title: attemptedSave && history.lastError != nil ? "Try saving again" : "Save reflection", symbol: "checkmark", action: save)
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.45)
                    if attemptedSave, !history.writesBlocked, let error = history.lastError {
                        Label(error, systemImage: "exclamationmark.circle")
                            .agFont(12).foregroundStyle(AfterglowTheme.gold)
                            .accessibilityLabel("Not saved. \(error)")
                    }
                    if entry != nil && !history.writesBlocked {
                        Button("Delete reflection", role: .destructive) { confirmingDelete = true }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .confirmationDialog("Delete this reflection?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                                Button("Delete", role: .destructive) {
                                    if let entry { history.deleteJournal(id: entry.id) }
                                    dismiss()
                                }
                                Button("Keep it", role: .cancel) { }
                            }
                    }
                }.padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Reflection").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasUnsavedChanges { confirmingDiscard = true } else { dismiss() }
                    }
                }
            }
            .interactiveDismissDisabled(hasUnsavedChanges)
            .confirmationDialog(
                entry == nil ? "Discard this reflection?" : "Discard your changes?",
                isPresented: $confirmingDiscard,
                titleVisibility: .visible
            ) {
                Button(entry == nil ? "Discard reflection" : "Discard changes", role: .destructive, action: discard)
                Button("Keep writing", role: .cancel) { }
            } message: {
                Text(history.writesBlocked
                     ? "Afterglow can’t save right now, so anything you wrote here will be lost."
                     : "What you wrote here hasn’t been saved.")
            }
            .afterglowScreen()
        }
    }

    private func save() {
        guard canSave else { return }
        attemptedSave = true
        pendingWrite = true
        // Prefer the entry this editor already inserted, so a retry never inserts a second copy.
        if var updated = createdEntry ?? entry, history.journal.contains(where: { $0.id == updated.id }) {
            updated.text = text
            updated.mood = mood
            history.updateJournal(updated)
            if createdEntry != nil { createdEntry = updated }
        } else {
            // New entry, or the original was removed elsewhere: add once and remember it for retries.
            createdEntry = history.addJournal(text: text, mood: mood, sessionID: entry?.sessionID)
        }
        // `persist()` clears `lastError` on success and sets it on failure, so it reflects this save.
        if history.lastError == nil && !history.writesBlocked {
            pendingWrite = false
            createdEntry = nil
            dismiss()
        }
    }

    /// Leaves without saving. If an earlier attempt already changed the in-memory journal but
    /// failed to write, undo that so an unconfirmed entry is not written later by another save.
    private func discard() {
        if pendingWrite && !history.writesBlocked {
            if let createdEntry {
                history.deleteJournal(id: createdEntry.id)
            } else if let entry, history.journal.contains(where: { $0.id == entry.id }) {
                history.updateJournal(entry)
            }
        }
        dismiss()
    }
}

/// Persistent, non-dismissible notice shown while the history file belongs to a newer app version.
/// Saving is disabled because `HistoryStore` refuses to overwrite that file.
private struct WritesBlockedNotice: View {
    var detail: String?

    var body: some View {
        AfterglowCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Saving is paused", systemImage: "lock.trianglebadge.exclamationmark")
                    .agFont(15, weight: .medium)
                    .foregroundStyle(AfterglowTheme.gold)
                Text(detail ?? "Your journal was saved by a newer version of Afterglow.")
                    .agFont(13).foregroundStyle(AfterglowTheme.muted)
                Text("New reflections and changes can’t be saved until you update the app. Nothing on this device has been overwritten.")
                    .agFont(13).foregroundStyle(AfterglowTheme.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
