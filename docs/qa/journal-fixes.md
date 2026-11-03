> This is a task-time record. See [final build status and issue disposition](../BUILD-STATUS.md) for the reconciled final source and remaining Mac/device verification.

# Journal UI fixes — `ios/Afterglow/Views/JournalView.swift`

- **Date:** 2026-10-31.
- **Scope:** only `Views/JournalView.swift` was edited. No Core, project or other View files changed.
- **Kept from Root's work:** the `.agFont` / `@ScaledMetric` font migration, and the `createdEntry` retry state.
- **Verification so far:** tree-sitter-swift (0.7.4) parses the file with 0 ERROR or MISSING nodes, plus a manual static review.
- **Not done:** no Swift compiler, Xcode, simulator or device run. Everything in "Unverified" below still needs a Mac.

## Changes

### 1. Unsaved reflections survive accidental cancellation (`JournalEditor`)
- **Baseline:** the editor stores the original text (`sanitize`d) and the original mood.
- **`hasUnsavedChanges`** is true when either:
  - the text or mood differs from the baseline (whitespace-only edits don't count), or
  - a save attempt changed the in-memory journal but the write wasn't confirmed (`pendingWrite`).
- **Swipe-down:** `.interactiveDismissDisabled(hasUnsavedChanges)` blocks it while the draft is unsaved.
- **Cancel button:** when dirty, it opens a confirmation dialog — "Discard reflection" / "Discard changes" (destructive) or "Keep writing". The message warns more strongly if saving is blocked.
- **`discard()`:** if an earlier save had already changed the in-memory journal but failed to write, it rolls that back:
  - a newly inserted entry is deleted;
  - an edited entry is restored to its original content.

  This stops a later, unrelated successful write from persisting content the user chose to throw away.
- **Also:** added `.scrollDismissesKeyboard(.interactively)`.

### 2. Respect `HistoryStore.writesBlocked`
- **New `WritesBlockedNotice` card:** persistent, not dismissible, and read by VoiceOver as one element. It shows the store's message plus "can't be saved until you update the app; nothing overwritten".
- **Where it appears:** at the top of the Reflect tab (replacing the dismissible error card while blocked) and inside the editor.
- **Disabled while blocked:**
  - "Write a reflection"
  - the editor's Save button (`canSave` requires `!writesBlocked`)
  - "Delete reflection" in the editor
  - context-menu Delete

  Before this change, saving after dismissing the error looked successful but nothing was written.
- **Still allowed:** viewing, editing for reading, and sharing.
- **The one route out:** Settings → Erase. That is the only `HistoryStore` path permitted to replace a newer-format file.

### 3. Retrying a failed save never duplicates an entry
- **How retries work:** `save()` targets `createdEntry ?? entry`. If that entry is still in `history.journal`, it calls `updateJournal`. Otherwise it calls `addJournal` exactly once and remembers the returned entry in `createdEntry`, so every retry after that is an update.
- **Edge case also covered:** an edited entry that was removed elsewhere. It is re-added once, keeping its `sessionID`, and retries don't re-add it again.
- **How success is judged:** `lastError == nil && !writesBlocked` after the call. `persist()` clears `lastError` on success and sets it on failure, so a stale error from launch doesn't block a successful save.
- **Error display:** errors appear only after a save attempt, labelled "Not saved". The button changes to "Try saving again".

### 4. Small fixes from `docs/qa/ui-review.md`
- **Context-menu Delete** now asks for confirmation (P2-4) — "Delete" / "Keep it", with a note that exported copies are separate.
- **Per-entry share** (`shareText(for:)`) now includes the date and mood, so mood-only entries no longer share an empty string (P3).

## Requests for other owners (not done — outside this file)
1. **HistoryStore (native engineer).**
   - Make `writesBlocked` `@Published`. Today the view only refreshes because `lastError` (published) changes at the same time in `reload()` / `eraseAll()`.
   - Have `addJournal` / `updateJournal` / `deleteJournal` return a success or failure result, or roll back their in-memory change when `persist()` fails. The UI then wouldn't need to infer success from `lastError`, or compensate in `discard()`.
2. **SessionFlowView (Root).** The post-session reflection still:
   - discards typed text from the `xmark` button or "Return without a reflection" without confirming (review P1-1);
   - doesn't check `writesBlocked` before "Save and return".

   Apply the same pattern there: confirm discard, `interactiveDismissDisabled`, and disable Save with a notice while blocked.

## Unverified — needs a Mac (Xcode 15+/16, iOS 17 simulator or device)
- [ ] Builds without errors or warnings (overload resolution for the ternary dialog/button titles; `if var updated = …, history.journal.contains { $0.id == updated.id }`).
- [ ] Swipe-down on the composer is blocked once text or a mood is entered, and allowed when empty or unchanged.
- [ ] Cancel with a dirty draft shows the discard dialog; "Keep writing" keeps the text; Discard closes it.
- [ ] Simulated write failure (e.g. a read-only `history.json` directory or an injected `fileURL`):
  - Save shows "Not saved…" and "Try saving again".
  - Repeated retries leave exactly one entry in `history.journal` and on disk after recovery.
  - Discard after a failure leaves no orphan entry.
- [ ] `writesBlocked` (seed `history.json` with `"version": 2`):
  - Reflect tab shows the persistent notice with no Dismiss button.
  - "Write a reflection", Save and Delete are disabled.
  - Settings → Erase clears the block and the UI re-enables.
- [ ] VoiceOver reads the blocked notice as one element and announces "Not saved" errors. Dynamic Type at the largest accessibility sizes keeps the editor and notice usable.
- [ ] Context-menu Delete confirmation and share content on device.
