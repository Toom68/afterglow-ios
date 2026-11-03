> This is a task-time record. See [final build status and issue disposition](../BUILD-STATUS.md) for the reconciled final source and remaining Mac/device verification.

# Afterglow iOS — UI / integration review (read-only)

- **Date:** 2026-10-31.
- **Snapshot:** working tree as of local 23:28. Files reviewed:
  - App: `App/AfterglowApp.swift`
  - Views: `Views/RootView.swift`, `Components.swift`, `DiscoverView.swift`, `JourneyView.swift`, `SessionFlowView.swift`, `JournalView.swift`, `SettingsView.swift`
  - Core, for integration only: `SessionPlayer`, `SessionTimeline`, `SessionModels`, `HistoryStore`/`HistoryModels`, `SettingsStore`, `AmbientAudioEngine`, `LightPolicy`, `NowPlayingController`
  - Project files: `Info.plist`, `PrivacyInfo.xcprivacy`, `Assets.xcassets`
- **Method:** static reading only. **Xcode was not run.** Nothing here is compile-, runtime- or visually verified. Statements marked *(verify)* need a build or device check.
- **Caveat:** the Core and Root agents are still editing. Line numbers will drift, so each finding also names the symbol or code it refers to.
- **Severity:**
  - **P0** — blocks a build, or causes user data loss / a broken advertised feature.
  - **P1** — likely bug or significant user impact.
  - **P2** — should fix before release.
  - **P3** — polish.

## API availability checked against Apple docs (developer.apple.com JSON, accessed 2026-10-31)

| API used | iOS introduced | Used at |
|---|---|---|
| `ContentUnavailableView` (incl. `.search(text:)`) | **17.0** | DiscoverView.swift:157,159 |
| `onChange(of:initial:_:)` (two-parameter closure form) | **17.0** | SessionFlowView.swift:65,161,302; JournalView.swift:208 |
| `ToolbarItemPlacement.topBarLeading` | 14.0 | SessionFlowView.swift:45 |
| `Button(_:systemImage:role:action:)` | 15.0 | JournalView.swift:66 |
| `Button(_:systemImage:action:)` | 14.0 | JourneyView.swift:44,46; JournalView.swift:64 |
| `toolbarBackground(_:for:)` | 16.0 | RootView.swift:17; Components.swift:157 |
| `ShareLink`, `ViewThatFits`, `scrollContentBackground`, `TextField(_:text:axis:)` | 16.0 | JournalView, SessionFlowView |
| `App` protocol | declared `@MainActor @preconcurrency` | AfterglowApp.swift |

Conclusions:
- **The deployment target must be iOS 17.0 or later.** There is no `.xcodeproj` / `project.yml` / `Package.swift` in the tree yet, so this cannot be checked. When the project is created, set `IPHONEOS_DEPLOYMENT_TARGET = 17.0`.
- Because `App` is `@MainActor`, constructing the `@MainActor` stores (`HistoryStore`, `SettingsStore`, `SessionPlayer`) inside `AfterglowApp.init` is isolation-correct.

---

## P0

### P0-1 Views use `SessionConfiguration` members that don't exist
- **Where:** SessionFlowView.swift:342–343, in `begin()`:
  ```swift
  configuration.mixWithOtherAudio = ownMusic
  configuration.useExperimentalLight = experimentalLight
  ```
- **Problem:** `SessionConfiguration` (SessionModels.swift:128–155) only declares `presetID`, `title`, `soundscape`, `duration` and `volume`. This is a compile error until Core adds the two members. The coordinator says this is expected while Core is mid-change.
- **Fix:** keep it on the final-tree checklist. Core should add:
  ```swift
  var mixWithOtherAudio = false
  var useExperimentalLight = false
  ```
  These must be `Codable`/`Hashable`-safe (they are, as defaulted stored `Bool`s).

### P0-2 "Use my own music" is broken by the audio-session configuration
- **Where:**
  - UI: SessionFlowView.swift:133–138 (toggle), 341–342.
  - Core: AmbientAudioEngine.swift:104, `prepare()`:
    ```swift
    session.setCategory(.playback, mode: .default, options: [])
    ```
    and :114, `setActive(true)`.
- **Problem:** `.playback` with no options is a non-mixable category.
  - If music is already playing when the user taps Begin, activating Afterglow's session **interrupts the user's music**.
  - If the user starts music after Begin (as the on-screen copy tells them to), the music app activates its session. Afterglow then receives `AVAudioSession.interruptionNotification .began`, and `SessionPlayer.handleInterruption` → `systemPause(.interruption, notice: .interrupted)` pauses the session and shows "paused by another sound".
  - Either way the feature cannot work. Setting volume to 0 doesn't help.
- **Fix (Core):**
  - When `configuration.mixWithOtherAudio` is true, use `setCategory(.playback, options: [.mixWithOthers])`, or `.ambient`. Better: don't start the synth/engine at all and run only the timer.
  - Ignore interruptions that come from other mixable apps while in that mode.
  - Pass the flag into `AmbientAudioControlling.prepare`.
  - Note: with no active audio, the app will be suspended in the background, so the timer won't tick and the completion/chime won't fire until the app is foregrounded. That is acceptable if the UI copy says so, or keep a silent mixable engine running.
  - *(verify on device)*

### P0-3 Journal writes silently lost when the history file is from a newer version
- **Where:**
  - HistoryStore.swift:173–175: `persist()` does `guard !writesBlocked else { return }`.
  - JournalView.swift:43: `Dismiss` calls `history.dismissError()`.
  - JournalView.swift:245 and SessionFlowView.swift:363 decide success by `history.lastError == nil`.
- **Problem:** when `reload()` finds a newer-format file it sets `writesBlocked = true` plus an error message.
  - If the user taps **Dismiss**, `lastError` becomes nil. Every later `addJournal`/`updateJournal` then updates memory only, returns without writing, and leaves `lastError` nil. The UI dismisses as if saved, and everything is gone on next launch.
  - If the user does not dismiss, the stale message makes Save look permanently broken.
- **Fix (Core):**
  - Make the mutators return a result (`throws`, or `Bool`), and have `persist()` set `lastError` (or throw) when `writesBlocked`.
  - In the Views, check that result rather than global `lastError`.
  - Alternatively, disable the composer and show a persistent banner while `writesBlocked`.

---

## P1

### P1-1 Typed reflection is discarded without confirmation
- **Where:** SessionFlowView.swift:47 (toolbar `xmark` calls `close()` whenever `stage != .listen`) and :312 (`QuietButton("Return without a reflection", action: close)`).
- **Problem:** in the reflect stage, one tap throws away the mood, the reflection text and the intention. The intention exists only in `@State`, and is only saved as a prefix inside the reflection.
- **Fix:** if `!reflection.isEmpty || mood != nil`, show a `confirmationDialog` with Save / Discard / Keep writing. Consider saving the intention-only entry automatically, or always saving the session's intention into the entry.

### P1-2 `JournalEditor` creates a duplicate entry on retry after a failed save
- **Where:** JournalView.swift:237–246, `save()`.
- **Problem:** `HistoryStore.addJournal` (HistoryStore.swift:127–133) inserts into `journal` **before** `persist()`. If the write fails, `lastError` is set and the sheet stays open. Tapping Save again calls `addJournal` again, so there are two in-memory entries, and both are written once disk recovers.
- **Note:** SessionFlowView already avoids this with `savedReflection` (lines 355–362).
- **Fix:** apply the same pattern in `JournalEditor`: keep `@State var saved: JournalEntry?` and switch to `updateJournal` after the first insert. Or have Core roll back the insert on persist failure.

### P1-3 Journey auto-advance depends on SwiftUI `onChange`, so it will likely stall when the phone is locked
- **Where:** SessionFlowView.swift:65–77. Inside `onChange(of: player.phase)` it does `sequenceIndex += 1; player.reset(); begin()`. Related Core code: `SessionPlayer.complete()` → `audio.finish(withChime: true)` → `stop()` after 8 s (AmbientAudioEngine.swift:130–142), which deactivates the audio session.
- **Problem:** journeys are long (up to 5 × 45 min) and will normally run with the screen locked.
  - The next session only starts if SwiftUI delivers the view update and runs `onChange` while backgrounded.
  - Once the chime tail ends, audio deactivates and the app becomes eligible for suspension.
  - *(Inference; verify on device.)* Likely result: silence after session 1 until the user unlocks.
- **Fix (Core + Views):**
  - Move the queue into `SessionPlayer`, e.g. `start(journey: [SessionConfiguration])`, and advance inside `complete()` without tearing the engine down.
  - The View should only observe `currentIndex`. That also gives a proper transition (see P2-5).

### P1-4 A failed `start()` leaves the user on a dead "PAUSED" screen
- **Where:** SessionFlowView.swift:344–345 sets `stage = .listen` **before** calling `player.start(configuration)`.
- **Problem:** `SessionPlayer.start` (SessionPlayer.swift:104–127) returns early with only a `notice` when thermal state is `.critical`, or when `audio.prepare`/`play` throws. The phase stays `.idle`, so:
  - The screen shows "PAUSED".
  - The play button calls `resume()`, which no-ops because there is no timeline.
  - The ring and clock show 00:00.
  - "End this moment" → `player.end()` no-ops, then the user lands in the reflect stage for a session that never happened.
- **Fix:** after `player.start(...)`, only move to `.listen` if `player.phase.isActive`; otherwise stay in prepare and show `player.notice` there. Better still, make `start` return `Bool` or throw.

### P1-5 No Dynamic Type support anywhere in the UI
- **Where:** every text style uses `.font(.system(size: N…))`, which ignores the user's text-size setting. Examples:
  - Components.swift:52, 69, 89, 109, 123, 127
  - DiscoverView.swift:76, 144, 211–216
  - SessionFlowView.swift:94–335
  - JournalView.swift throughout
  - SettingsView.swift throughout
  - JourneyView.swift throughout
- **Problem:** users who rely on larger text get no scaling. Many sizes are already 9–11 pt, below the HIG minimum of 11 pt:
  - `Eyebrow` 10 pt mono
  - `TagPill` 11 pt
  - the "MIN · OFFLINE" captions at 9 pt (SessionFlowView.swift:195, DiscoverView.swift:216)
  - MoodPicker labels at 9 pt (JournalView.swift:162)
  - the PAUSED/REMAINING label at 9 pt (SessionFlowView.swift:229)
- **Fix:**
  - Use semantic styles (`.body`, `.subheadline`, `.caption`), or `Font.system(.title, design: .serif)` / `.system(.caption, design: .monospaced)` for serif and mono variants.
  - Use `@ScaledMetric` for fixed frames (mood buttons, duration chips, `GlowOrb` size).
  - Raise the 9–10 pt captions to `.caption2` or larger.
  - Test with Accessibility XL sizes: the 3-chip duration `HStack` (SessionFlowView.swift:101) and the segmented Soundscape picker will need `ViewThatFits` or a vertical fallback.

### P1-6 The light-mode UI doesn't use Core's `LightScreening` / `LightGate` / `startLight`
- **Where:**
  - UI: `LightScreeningView` (SessionFlowView.swift:387 onward) has three aggregate toggles and sets the boolean `experimentalLight`; `begin()` sets `configuration.useExperimentalLight`.
  - Core: `SessionPlayer.startLight(protocolID:screening:consentedThisSession:)` (SessionPlayer.swift:194) needs a completed per-question `LightScreening` (LightPolicy.swift:49–84) and a protocol ID. Nothing in the Views calls it.
- **Problem:**
  - In a research build with a validated protocol, light either never starts or bypasses the gate, depending on how Core interprets `useExperimentalLight`.
  - The copy also contradicts Core. The UI says "This original prototype sequence is unvalidated" (SessionFlowView.swift:174) and "The sequence is an original, unvalidated engineering prototype". Core says Afterglow "does not invent light parameters" and ships an empty catalog (LightPolicy.swift:3–5, 39).
- **User impact today:** low. `LightFeature.isAvailable` is false in release builds, so the opt-in button is hidden.
- **Fix:**
  - Build the screening sheet from `LightScreening.Question.allCases` with explicit Yes/No per question.
  - Pass the result plus the per-session consent into `player.startLight` after `start`, and surface `LightUnavailableReason`.
  - Align the copy with `LightFeature.statusExplanation`.

---

## P2

1. **Light card shown on every prepare screen in release** (SessionFlowView.swift:166–187).
   - Problem: in a build where light can never be enabled, an audio-only meditation shows a seizure-risk card mentioning an "unvalidated prototype sequence" and Lumenate. That is alarming and confusing.
   - Fix: hide the card when `!LightFeature.isAvailable`. The About tab already explains the light status.
2. **Brand / third-party naming inside product UI.**
   - Where: "not Lumenate's method" (SessionFlowView.swift:174); "inspired by … Lumenate", the method description and the lumenate.co link (SettingsView.swift:16, 25–27, 60–68).
   - Research (`docs/research/product.md` §11) recommends a clean-room product without Lumenate names. Nominative reference in About may be acceptable, but needs legal review; remove it from session screens.
   - Also, SettingsView.swift:69 points end users to "The source package includes detailed product and science reports…". That is internal wording and doesn't belong in shipped UI.
3. **Reflection draft not persisted.**
   - Where: `reflection`/`intention`/`mood` are `@State` only (SessionFlowView.swift:15–17; JournalEditor :182–183).
   - Problem: a long session often ends with the phone locked; if the app is terminated before the user returns, the draft is lost.
   - Fix: `@SceneStorage` for the drafts, or autosave a draft entry.
4. **Journal delete has no confirmation or undo from the context menu** (JournalView.swift:66). The editor path does confirm (:220, 227).
   - Fix: add a `confirmationDialog`, or an undo toast.
5. **Abrupt journey transitions.**
   - Problem: `player.reset()` then `begin()` immediately rebuilds the engine. `prepare()` → `teardownGraph()` cuts the completion chime and 5 s fade started by `complete()`. The user hears a chime fragment and then a hard cut into a 3 s fade-in.
   - Fix: covered by P1-3 (queue inside the player with a crossfade).
6. **Journal → session link is only to the last journey segment.**
   - `player.lastRecord` is cleared by each `reset()` during advance (SessionPlayer.swift:163), so the reflection links only the final session.
   - The integration header "N minutes with X" (SessionFlowView.swift:283–285) also shows only the last segment.
   - Fix: accumulate the journey's record IDs and total minutes.
7. **`SettingsStore.defaultSoundscape` / `defaultMinutes` are never read or editable** (SettingsStore.swift:14–32).
   - SessionFlowView always uses preset defaults (lines 29–30), and there is no settings UI. This is dead code or a missing feature.
   - Fix: decide which; remove, or add pickers in About.
8. **Core `deleteSession(id:)` and `stats.currentStreakDays` have no UI.** If a single session can't be deleted, history is all-or-nothing (Settings → Erase).
   - Fix: add swipe/context delete on "Recent moments" (JournalView.swift:71–76).
9. **Prepare-screen controls vs own-music mode.**
   - With `ownMusic` on, the soundscape picker and volume slider are still shown and active, but the configuration forces `volume = 0` (SessionFlowView.swift:341).
   - Fix: disable or hide them when `ownMusic` is true.
   - Also, `player.setVolume` exists (SessionPlayer.swift:168) but there is no in-session volume control.
10. **`Journey` identity issues** (JourneyView.swift:27, `ForEach(Array(selected.enumerated()), id: \.offset)`).
    - Removing or reordering items reuses offsets as identities, so animations and VoiceOver focus jump. The same preset can be added more than once, so the preset ID alone isn't unique either.
    - Fix: wrap each item as `struct Item: Identifiable { let id = UUID(); let preset: SessionPreset }`.

---

## P3 (polish / accessibility details)

- Toolbar close button frame is 40×40 (SessionFlowView.swift:50); HIG minimum is 44×44.
- Timer accessibility (SessionFlowView.swift:225–227): use `.accessibilityValue(...)` plus `.accessibilityAddTraits(.updatesFrequently)` instead of a label that changes every tick.
- Pause button label "Pause session and stop light" (SessionFlowView.swift:252) is shown even for audio-only sessions. Make it conditional on `experimentalLight`.
- Pluralisation and zero values:
  - "1 minutes with…", and "0 minutes" for sessions under 60 s (SessionFlowView.swift:284).
  - "0m" in Recent moments (JournalView.swift:135).
  - Fix: use `Duration.formatted(.units(...))` or inflection (`^[\(n) minute](inflect: true)`).
- `exportText` is rebuilt on every render and embeds `Date()` (JournalView.swift:8–20), so it is O(n) per body evaluation. Fix: build it lazily, e.g. a `Transferable` with a `DataRepresentation`, or compute it on tap.
- Mood-only entries share an empty string (JournalView.swift:65). Fix: include the mood/date in the shared text.
- Category chips are hard-coded strings (DiscoverView.swift:142) and are matched against `SessionIntent.title` via `caseInsensitiveCompare`. Derive them from `SessionIntent.allCases` so they can't drift.
- `Int(history.stats.totalMinutes)` is redundant; it is already `Int` (DiscoverView.swift:179). `history.stats` recomputes over all sessions on every access, and the practice card reads it twice.
- `toolbarBackground(_:for: .tabBar)` is applied to the `TabView` itself (RootView.swift:17–18). Apple's examples apply tab-bar toolbar modifiers to the tab content views. *(verify visually)*
- Segmented `Picker` with `Label(title, systemImage:)` items (SessionFlowView.swift:117–122): segmented controls render either text or an image per segment, so the visible result may be icon-only or text-only. *(verify visually)* Use `Text` items if titles must show.
- `JournalEditor` / reflection `TextEditor` inside a `ScrollView` has no keyboard dismissal. Add `.scrollDismissesKeyboard(.interactively)` (iOS 16), or a toolbar Done button.
- Welcome sheet (RootView.swift:54) leads with the long "light not available / seizures" paragraph for an audio-only app. Consider moving it to About.

---

## Core-side risks noticed while checking integration (owned by Core; not a UI review target)

- **Swift 6 language mode:** `deinit` in `@MainActor` classes touches isolated, non-Sendable stored properties:
  - `SessionPlayer.deinit` (`ticker`, `observers`; SessionPlayer.swift:97–100)
  - `NowPlayingController.deinit` (`targets`; NowPlayingController.swift:26–28)

  Expect warnings in Swift 5 mode and errors in Swift 6 mode. Since the app-level objects never deinit, consider `isolated deinit` (Swift 6.2) or remove the cleanup. *(verify with the chosen toolchain)*
- **`MainActor.assumeIsolated` in `MPRemoteCommand` handlers** (NowPlayingController.swift:51) assumes they are delivered on the main thread. If not, it traps at runtime. *(verify)*
- **`UIApplication.willTerminateNotification`** (SessionPlayer.swift:332) is not delivered when a suspended app is killed, so interrupted sessions are usually not recorded. That's acceptable, but don't rely on it for journal drafts (see P2-3).

---

## Product gaps relative to research (`docs/research/product.md`, §9 and §11)

| Research MVP item | Status in current UI |
|---|---|
| Safety onboarding | Welcome sheet only. Fine for audio-only; the light screening needs per-question flow (P1-6) |
| Setup / how-to tutorial (posture, headphones, environment) | **Missing**; only one line of copy on Discover |
| Library by intent, duration selector | Present (5 presets, Calm/Focus/Sleep/Reflect) |
| Favourites | Present (`@AppStorage` CSV) |
| Offline | Inherent (procedural audio) |
| Bring-your-own-audio mode | Present in UI but **broken** (P0-2) |
| Post-session journal + mood | Present; discard risk (P1-1), draft loss (P2-3), duplicate-on-retry in editor (P1-2) |
| Journal export / self-serve erase | Present (ShareLink text, Erase all). Per-entry delete only via the editor or context menu; no per-session delete (P2-8) |
| Journeys (queue ≤5, **saved**, a differentiator) | Present and persisted. Transitions are abrupt and background advance is at risk (P1-3, P2-5); per-session duration can't be edited |
| Recommender / AI guide | Out of MVP scope (V2), as recommended |
| Sudden-motion auto-stop (light) | N/A while light is disabled |

## Suggested order of fixes

1. Core: P0-1, P0-2 and P0-3. Make the persistence API return success or failure.
2. Views: P1-1, P1-2 and P1-4 (small, local changes).
3. Core + Views: P1-3 (player-owned journey queue, which also fixes P2-5 and P2-6).
4. Views: P1-5 Dynamic Type pass.
5. P1-6 together with the release decision on the light card (P2-1, P2-2).
6. Then the remaining P2 and P3 items.
7. Once an Xcode project exists: build for iOS 17 and run the Accessibility Inspector at XXL text sizes.
