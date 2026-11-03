# Afterglow native core and light-consent review

Review completed: **31 October 2026**, against the final Core API v2 source and the persistent shutdown-warning follow-up. This was a read-only app review; the reviewer wrote only this report and did not commit changes.

**No unresolved source-level blocker was identified after reconciliation.** The package can accurately be described as an untested source prototype prepared for later Mac/device validation. This is not a build pass, a release approval, or approval for human light exposure. No Xcode compilation, XCTest execution, simulator session, iPhone test, optical measurement or clinical validation occurred in this review. `swift` and `xcodebuild` were not available on this Windows host.

## Prioritized residual limitations

### P2 ? The watchdog shares the main queue with pulse scheduling

Locations: `ios/Afterglow/Core/Light/TorchController.swift`, `schedule(at:)` and `armWatchdog()`.

Both the pulse timer and the watchdog are main-queue dispatch sources. If the main queue stalls while the LED is on, neither can command off until execution resumes. Absolute deadlines prevent cumulative scheduling drift; zero leeway and `.strict` do not establish real-time delivery. The watchdog helps if boundary scheduling is lost while the main queue remains serviceable. It does not independently protect against a main-thread stall or process failure.

The misleading ?guaranteed hard stop? and ?guaranteed off whenever this throws? wording was removed. Keep the distinction between requested software bounds and measured optical behaviour. Before any eye-directed use, measure pulse widths, missed edges, worst-case on intervals and stop latency under load. A different execution queue would also require measurement and would not supply a medical safety guarantee. This is an explicit verification limitation, not an outstanding source blocker for preparing the source package.

### P3 ? The hardware-limit seam must not be read as optical telemetry

Location: `TorchController.swift`, `TorchDevice.maxAvailableLevel` and `SystemTorchDevice.maxAvailableLevel`.

The real implementation returns the static `AVCaptureDevice.maxAvailableTorchLevel` constant. Apple describes it as a parameter value for requesting the available maximum, not a measurement of per-device emitted intensity. The fake device's mutable maximum does not prove that production hardware supplies equivalent dynamic telemetry through that constant. The coordinator corrected the comments to identify the request sentinel accurately, and that change was re-read.

Keep the independent protocol/requested-level cap, thermal checks, availability checks and command-error handling. Do not infer calibrated brightness or thermal output tracking from this seam or its fake-device tests. This is a nonblocking documentation/measurement qualification; the actual smoke-test request remains capped by its own peak level.

## Findings resolved and re-read in the final source

| Original priority | Finding and concrete failure | Resolution verified in source |
| --- | --- | --- |
| P1 | `HistoryStore.swift`, `SettingsStore.swift` and `SessionPlayer.swift` used Combine observation symbols without explicit Combine imports. | All three now import Combine. This removes the identified source-level import risk; it is not an observed compiler result. |
| P1 | `LightUnavailableReason` was used as `Result`'s failure type without `Error`; associated torch errors also needed compatible conformance. | `LightPolicy.swift` now declares `LightUnavailableReason: Error, Hashable`; `TorchError` and stop reasons are Hashable. |
| P1 | `AmbientSynth.render` passed inout voice fields to an instance helper that implicitly borrowed the same struct. | `AmbientSynth.swift` now uses `Self.renderVoice` and a stateless `private static` helper, removing the avoidable exclusivity conflict. |
| P1 | The remote media callback used `MainActor.assumeIsolated` without a documented actor-delivery guarantee. | `NowPlayingController.swift:53` now explicitly creates a main-actor Task. Main-queue timer/notification callbacks have a different execution guarantee and are not the same issue. |
| P1 | `SessionPlayer.startLight` supplied screening/consent as unconditional truth, allowing a direct call after starting an audio-only session. | `SessionPlayer.startLight(protocolID:)` now checks the current configuration's explicit light opt-in, then the one-use latch and shutdown-warning latch. A source test exercises refusal for an audio-only session. |
| P1 | Failed torch-off writes were swallowed, and ordinary state/messages could assert darkness without establishing that the command succeeded. | `TorchController.hardStop(_:notify:)` cancels callbacks first, attempts off twice and exposes `offCommandError`. `SessionPlayer` captures it in independent `lightShutdownWarning` state, including errors during start/cleanup. It does not prefix this warning with ?Light turned off.? |
| P1 | A shutdown warning could be overwritten by a pause notice or disappear when moving to reflection/dismissing the player. | `lightShutdownWarning` survives start, reset, notice dismissal and later successful off attempts. It blocks new light until `acknowledgeLightShutdownWarning()`. `RootView.swift:20` and `SessionFlowView.swift:101` render fixed warning banners; `Components.swift:152` supplies shutdown instructions and an explicit ?Torch is off? acknowledgement. |
| P1 | The emergency light stop could fall below the fold, and top close asked for confirmation while exposure continued. | `SessionFlowView` pins STOP LIGHT & SESSION in a bottom safe-area inset. Top close immediately ends a light session. The subtitle now says the test ?stopped? rather than treating the scheduling Boolean as confirmed darkness. |
| P2 | Own-music mode mixed audio but continued publishing Afterglow metadata/remote controls for its silent bed. | `SessionPlayer.sync()` suppresses ownership for `mixWithOtherAudio`; `NowPlayingController.update` clears metadata and disables commands when not owned. UI explains that its pause affects this session, not the external music app. Actual system routing is untested. |
| P3 | The UI classified Lumenate sequences as proprietary when the research established only non-disclosure. | `SettingsView.swift:27` now says ?undisclosed? and retains the explicit absence of treatment/equivalence claims. |

These fixes were implemented by the app owners and re-read by the reviewer. No claim is made that their tests have run.

## Final native behaviour reviewed

### Build gate and numerical contract

`LightProtocolCatalog.validated` remains empty. A separate `unvalidatedEngineeringTest` entry describes the coordinator's arbitrary smoke test: nominal 3 Hz, 50% duty, requested level 0.02, 30 seconds of light after a 10-second positioning delay. Those values are **not a safe dose, not a literature-validated protocol, and not a Lumenate reproduction**. The catalog/disclosure say that physical timing and brightness are unmeasured.

The project sets `AFTERGLOW_LIGHT_RESEARCH` in Debug only (`project.pbxproj`, Debug configuration); the shared scheme's Archive action uses Release (`Afterglow.xcscheme:87`). The default Release gate refuses light, and its experimental catalog is empty. Constructor/catalog overrides are internal test seams, not user controls; do not expose them as a release bypass. No validated entry was manufactured to enable the feature.

The smoke test's peak/duration are more restrictive than the controller's general engineering ceilings. The active allowlist, not the larger generic ceilings, defines the offered test. `LightProtocol.isWellFormed` rejects non-finite and out-of-range step/peak/duration values; the controller separately requires exact membership in its allowed catalog. None of this is clinical dose validation.

### Scheduling, cancellation and lifecycle

- Pulse boundaries are computed from the absolute start time. Late callbacks evaluate the level for the current instant instead of replaying missed flashes. Floating-point boundary tolerance is explicit, and the test source checks the nominal smoke sequence's final boundary and edge count.
- All controller state is main-actor-owned. Every start/stop changes a generation number; scheduled callbacks compare their captured generation before touching output. Stop invalidates both sources before requesting off. The player creates a fresh controller for a new light run and identity-checks stop callbacks, preventing an older run's callback from updating the replacement.
- The positioning delay is represented as an off interval in the same cancellable run. Stopping during that delay removes the scheduled first on edge. No separate delayed closure is allowed to relight an abandoned session.
- The controller refuses missing/unavailable hardware and serious/critical thermal state. It checks temperature at boundaries and observes thermal changes. It does not automatically restart when the device cools.
- `willResignActive`, `didEnterBackground` and termination notifications request off. Audio-session interruption also requests off. The player pauses on interruption and on `.oldDeviceUnavailable` route loss; its ordinary resume path restarts audio/timing, not light. The one-use latch rejects another light run within the same session.
- Other audio-route change reasons do not independently stop the player. That is the reviewed coverage boundary, not a promise that every route transition was tested. Verify speaker/headphone/Bluetooth/AirPlay transitions and audio-engine configuration changes on devices.
- End, completion and reset converge on torch cleanup before history persistence. The shutdown-warning latch is separate from ordinary notices, so a normal interruption message cannot erase it. New audio-only sessions may still run while the warning remains, but new light is refused.

A request accepted by the API is still not optical evidence. Neither `currentLevel == 0` nor `isLightActive == false` is proof of darkness; these are software state, with explicit off-error reporting alongside them. The warning persists for the lifetime of the player object, not across arbitrary process/OS failure. The user acknowledgement is a human confirmation, not a sensor measurement.

### Permission and hardware handling

The implementation uses torch configuration directly; it does not create a capture input/session, capture frames, or call `requestAccess`. `Info.plist` has no camera-usage string. The missing string is not, by itself, a demonstrated defect in this torch-only design. Do not describe a recording-permission dialog or a delayed permission callback as a tested part of the current flow. Fresh install, camera-denied/restricted device states, managed restrictions, unavailable hardware and API failures still require device verification. If capture or explicit permission requests are later added, both privacy metadata and cancellation review must be revisited.

## Consent and scientific claims

The SwiftUI light selection defaults off and its screening state is local to the presented flow. Opt-in requires adult status, no listed/uncertain risk factors, and explicit acceptance of residual risk. The native player now requires that current session's resulting opt-in flag. It is an internal Boolean contract rather than a separately validated consent instrument; do not deserialize a previously saved opt-in as future consent or reuse it if new entry points/import features are added.

The consent text correctly warns that seizures can occur without known history, closed eyes/low brightness/checklist completion do not make exposure safe, and the sequence is original and unvalidated with no established therapeutic benefit. It covers the main neurological, medication, pregnancy, fatigue/withdrawal and psychological precautions from [the science report](../research/science-and-safety.md), tells uncertain users to choose audio only, and directs stopping and medical assessment after suspected reactions. It does not invent a clinically safe exposure.

Broader bipolar/mania/eye-condition precautions are explicitly conservative prototype exclusions, not validated individual seizure predictions. Qualified medical review of final wording remains required before public use. The checklist is not a diagnostic test, and this review has not clinically validated it.

Light opt-in is unavailable for sleep presets and multi-session journeys. This avoids encouraging sleep/unattended exposure or chained light sessions. The permanent audio-only path is useful, and the app makes no supported claim of neural-state control, psychedelic equivalence, insomnia treatment or durable clinical benefit. Engineering settings disclosed to the user must continue to be labelled as requests, not measured output.

## Clock investigation: a rejected false positive

`MonotonicClock.swift:7` uses `clock_gettime_nsec_np(CLOCK_MONOTONIC)`. Apple's Darwin manual explicitly states that this clock continues to increment while asleep. Linux suspend semantics must not be applied to report a false Darwin bug. `CLOCK_MONOTONIC_RAW` additionally excludes frequency/time adjustments and maps to `mach_continuous_time`; choosing it could make an unadjusted-clock intent clearer, but the current sleep-counting claim is supported by the Darwin manual.

## Verification performed and remaining work

Performed here: read final Core/consent/UI/test source, inspect build flags and shared scheme, parse `Info.plist` and `PrivacyInfo.xcprivacy` with Python's plist parser, and parse the scheme XML. These structural files parsed successfully; Archive is configured for Release. The shell build script was read, not executed.

`LightTests.swift` includes source cases for catalog rejection, finite-parameter validation, positioning delay, boundary arithmetic, requested-level caps, completion/timeout, no late-step relight, thermal/unavailable hardware and failed off requests. `SessionPlayerTests.swift` includes per-session opt-in, audio-only refusal, no light restart on resume/interruption, and the updated persistent-warning cases. In particular, the obsolete ordinary-notice expectation was replaced with tests for warning survival, blocking new light, acknowledgement, route-loss pause and start failure. Their existence is not a passing test result. Manual-clock/fake-device tests do not exercise actual dispatch jitter, notification delivery, the LED driver or SwiftUI layout.

Before using the light test, complete the relevant items in [the Mac/device checklist](MAC-CHECKLIST.md):

1. On a Mac with the intended Xcode/iOS SDK, run `scripts/ci-test.sh`: Release generic-device build and Debug simulator tests. Inspect warnings/concurrency diagnostics and build both configurations. Confirm Release has no light entry at runtime. No live Mac build was requested or performed in this session.
2. On supported physical hardware, first point the torch away from everyone's eyes. Verify the nominal delay, emitted pulse train, output, stop latency and worst-case on intervals with suitable optical instruments. Test under UI/main-thread load, low power, thermal pressure and configuration contention. No numerical safe dose is supplied by this report.
3. Exercise stop/pause/close during the positioning delay, on/off intervals and sequence completion; inject off-command failure; verify the persistent banner through pause, reflection, dismissal, reset and a new session. Confirm new light is blocked until explicit acknowledgement and that ordinary notices cannot hide the warning.
4. Exercise app switching, Control Center, screen lock, calls/Siri/alarms, headphone/Bluetooth loss, other route transitions, audio-service reset, unavailable torch and serious/critical thermal state. Confirm no automatic relight and no previous-run callback crossing into another session.
5. Verify fresh-install and restricted/denied camera states for the actual torch-only implementation. If its permission model changes, test delayed grant/denial, cancellation and backgrounding before any start is allowed.
6. Check the fixed stop and warning banners on small phones, large accessibility text and VoiceOver, with the phone oriented for closed-eye use. The source arrangement improves reachability; only device/UI testing can establish it.
7. Establish actual behaviour after crash, termination and OS intervention. An in-process watchdog or deinitializer cannot guarantee shutdown after every failure. Optical hazard assessment, prospective adverse-event monitoring and medical review remain separate requirements before any broader use or safety/benefit claim.

## Primary API references

All external references were checked on 31 October 2026. Medical studies and official manufacturer warnings are cited individually in the linked science report.

- [Apple: ObservableObject](https://developer.apple.com/documentation/combine/observableobject) and [Published](https://developer.apple.com/documentation/combine/published).
- [Apple: MPRemoteCommand.addTarget(handler:)](https://developer.apple.com/documentation/mediaplayer/mpremotecommand/addtarget%28handler%3A%29) and [Actor.assumeIsolated](https://developer.apple.com/documentation/swift/actor/assumeisolated(_:file:line:)).
- [Apple: Run Loops / Timer Sources](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Multithreading/RunLoopManagement/RunLoopManagement.html).
- [Apple Libc: clock_gettime manual](https://github.com/apple-oss-distributions/Libc/blob/main/gen/clock_gettime.3) and [implementation](https://github.com/apple-oss-distributions/Libc/blob/main/gen/clock_gettime.c).
- [Apple: isTorchAvailable](https://developer.apple.com/documentation/avfoundation/avcapturedevice/istorchavailable), [maxAvailableTorchLevel](https://developer.apple.com/documentation/avfoundation/avcapturedevice/maxavailabletorchlevel), and [setTorchModeOn(level:)](https://developer.apple.com/documentation/avfoundation/avcapturedevice/settorchmodeon%28level%3A%29).
- [Apple: requesting media capture permission](https://developer.apple.com/documentation/avfoundation/avcapturedevice/requestaccess%28for%3Acompletionhandler%3A%29).
- [Apple WWDC22: media metadata and playback interactions](https://developer.apple.com/videos/play/wwdc2022/110338/), including non-mixable-session eligibility for Now Playing.
