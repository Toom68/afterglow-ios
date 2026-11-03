# Checks to run on the Mac

These checks were **not run in the Windows development session**. They verify software behavior; they do not establish clinical safety, an effective exposure, or equivalence to Lumenate.

## Build and ordinary app use

- Open `ios/Afterglow.xcodeproj` with Xcode 16 or newer, using a version that supports your phone's iOS. Build the app and run the unit tests on an iPhone simulator with iOS 17 or newer. Resolve compiler diagnostics before using a physical device.
- Build both Debug and Release. Test iPhone-sized layouts at standard and the largest accessibility text sizes, including VoiceOver and the keyboard covering the journal.
- On a physical iPhone, install using your Personal Team. Try the audio app in airplane mode; no account or network should be needed.
- Search and filter the library. Favourite a session, relaunch, and confirm it remains saved.
- Start audio, adjust volume, pause, wait, and resume. Paused time should not count as listened time. End early; an accidental session under 30 seconds should not be recorded.
- Let a session finish. Confirm it records once, plays its closing behavior, and permits reflection. Test another session immediately afterward to check that an old scheduled cleanup cannot stop new playback.
- Test unplugging headphones, a call/Siri interruption, locking and unlocking, and changing audio routes. The app must preserve an intentional user pause. The light must never restart automatically.
- Start your own music, then use the external-music option. Confirm your track continues, Afterglow is silent, and music playback controls remain sensible. Test stopping the external track and leaving/returning to the app.
- Build, reorder, remove from, and relaunch a five-session journey. Verify that a sixth cannot be added. Confirm automatic advance while the screen is locked and that ending early prevents further sessions from starting. Transitions are not claimed to be gapless.

## Journal and persistence

- Create a text note, a mood-only note, and a session reflection. Relaunch and check that each is present once.
- Edit a note and save. Begin another edit and choose Cancel; the discard confirmation should preserve the draft when cancelled and discard it only when explicitly chosen.
- Verify that a swipe dismissal cannot silently lose a dirty draft. Check the equivalent close/return controls after a session.
- Share a mood-only note and export the full journal. Verify text content and dates, and that the app requests a share destination.
- Delete one note with confirmation, then erase all history through About. Confirm persistence after relaunch.
- With a test fixture or injected test store, simulate a save failure and retry repeatedly. An error must remain visible, failed writes must not claim success, and recovery must not duplicate the entry.
- Seed a newer archive format in a test environment. Writes must be blocked with a persistent message; dismissing an error must not silently enable them. Only explicit erase may replace the newer file.

## Experimental light mechanics, without exposing eyes

Point the torch away from all people and animals. Do not use a near-eye exposure as a software acceptance test. Debug includes an unvalidated engineering sequence; Release must not expose it. Its requested settings are not a calibrated optical dose, and a low numeric brightness fraction does not establish safety.

- In the simulator, on unsupported hardware, or in Release, light should be unavailable with an explanation. Never flash on launch, in previews, or while browsing.
- On supported hardware in Debug, verify that audio is the default and no light starts before fresh per-session acknowledgement. Cancel the risk screen and confirm that light remains off.
- Deny any requested permission and check the error path. No automatic retry may unexpectedly start light after the app is inactive.
- With the torch directed safely away, verify the preparation delay, requested bounds, and automatic cutoff using an external detector or other appropriate measurement method. A successful timer callback is not a measurement of the emitted light.
- During the delay and during output, use pause, the fixed stop button, the close button, home/lock, a call interruption, and a route change. Verify physical output ceases, not just the UI label.
- Resume after each interruption and confirm no automatic relight. Begin another session and verify it again defaults to audio only. Sleep sessions and multi-session journeys must not offer light.
- Verify unavailable-torch/configuration errors and thermal handling using test seams and, where feasible, controlled hardware testing. A failed off-write must be reported as unconfirmed output, rather than claiming darkness.
- Confirm that stale timer callbacks cannot relight output after stop, reset, a new session, or completion. Test force termination separately; document actual hardware behavior rather than assuming an app notification always runs.

Optical timing, output variability across phones, photobiological exposure, seizure susceptibility and clinical outcomes require separate qualified assessment. Completing these software checks does not validate any personal or public light-use protocol.
