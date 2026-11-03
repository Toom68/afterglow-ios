# Build and delivery status

Prepared on **31 October 2026** for the user's later Mac session. The deliverable is an **untested iOS source prototype**, with research and installation instructions. It is not a signed IPA, TestFlight build, App Store release, verified Lumenate replacement, or approval for eye-directed light exposure.

## First Mac build follow-up

The user's first Xcode build reported a missing `ScaledMetric` wrapped value and three
actor-isolation warnings in the light tests. [Build fix 1](qa/build-fix-1.md) corrects
the font property declaration and marks four immutable controller constants
`nonisolated`. The updated package includes the repair. A successful Xcode build and
device run are still pending; the original structural checks below did not catch
this type-checking error.

## Team outcomes

The coordinator used two Devin workers and one Codex worker through Orca, reusing the same workers for follow-up review and fixes. The coordinator authored and integrated the SwiftUI app screens and handled source validation, packaging and Drive delivery.

| Task | Outcome and evidence | Remaining boundary |
| --- | --- | --- |
| Product research | Delivered [product report](research/product.md), covering the official website, all 84 public support articles, store listings, terms, privacy, app workflows and Nova. | Desk research only; no hands-on account, paid content or waveform extraction. Explicit unknowns remain in the report. |
| Methods, evidence and safety research | Delivered [science report](research/science-and-safety.md), with primary studies, controls, limitations, current safety synthesis and source URLs. | No validated generic equivalence, safe dose, therapeutic claim or physical measurement established. |
| Native iOS foundation and packaging | Delivered SwiftUI-compatible native Core, a real shared-scheme Xcode project, 11 original presets, four procedural soundscapes, persistence, lifecycle controls, tests, scripts and [installation guide](INSTALL-IOS.md). | Written and reviewed on Windows; compilation and runtime verification remain pending. |
| UI review | Delivered [snapshot findings](qa/ui-review.md). Coordinator addressed the important integration, save, cancellation, Dynamic Type, start-failure, queue-event and light-control findings. | Full visual/accessibility testing and background behavior still need Xcode and an iPhone. The snapshot's original issue labels are historical, not the final disposition. |
| Journal repairs | Delivered focused fixes and [repair report](qa/journal-fixes.md): discard confirmation, blocked-write UI, save retry behavior, delete confirmation and mood-aware sharing. Core was then changed to publish only successful transactions. | Failure-injection and real UI checks remain unrun; the repair report's original requests are resolved by the final Core/UI integration. |
| Native/light review | Delivered [final review](qa/core-review.md), reconciled against final files. No unresolved source-level blocker was identified for preparing this untested source package. | Main-queue scheduling is best effort, not real-time protection. Physical output, latency and optical exposure remain unmeasured. |
| Persistent shutdown-warning follow-up | Added a separate warning that survives pause, end, reset, new session and ordinary notice dismissal, blocks further light, and requires explicit acknowledgement. Fixed banners appear in player and main app. Regression tests were authored. | A requested hardware-off command is not a measurement of darkness; real failure behavior still needs device testing. |

## Checks actually performed

The machine-readable record is [windows-validation.json](qa/windows-validation.json).

- Parsed **25 Swift files** with tree-sitter-swift: no syntax-error files. This does not resolve SDK types or prove compilation.
- Parsed the Xcode project: **27 objects**, valid internal references, app/test targets, synchronized source groups, and shared scheme. Verified the research flag is absent from Release and Archive uses Release.
- Parsed two plist/privacy files, two scheme/workspace XML files and four asset catalog JSON files.
- Inspected the original app icon: 1024 × 1024, RGB without alpha.
- Passed Bash syntax checks for both shell scripts through Ubuntu WSL, PowerShell parser checks for the Windows package script, and CI YAML structure checks.
- Successfully ran the Windows source-package script. ZIP integrity, portable forward-slash paths, expected project/docs, no path traversal, and LF shell scripts passed inspection. The final package is regenerated after documentation reconciliation.

There are **79 XCTest methods authored**. They were **not executed**. No Xcode compile, simulator app run, physical iPhone run, optical measurement, signed build, TestFlight upload or GitHub Actions run was performed. No remote Git repository was created or published.

## What to do later on the Mac

Download and unzip `Afterglow-source-0.1.0-20261031.zip`, then start with the root README and [installation guide](INSTALL-IOS.md). Install an appropriate Xcode, build/test in the simulator, and use your free Personal Team to install on your own iPhone. Free signing needs renewal through Xcode after seven days. A paid Developer Program account is optional for this personal testing route.

Run the [Mac checklist](qa/MAC-CHECKLIST.md) before treating the app as verified. Debug contains only an explicitly unvalidated engineering torch test; Release remains audio only. The first physical checks must point the torch away from people and animals. Software tests cannot establish a clinically safe exposure or Lumenate-equivalent effects.

See the [feature matrix](FEATURE-MATRIX.md) for commercial features not reproduced, including undisclosed waveforms, paid narration/music, the AI Guide, subscriptions and Nova hardware support.
