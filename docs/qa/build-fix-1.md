# Build fix 1: font initialization and immutable light constants

This follow-up addresses the first Mac compiler screenshot supplied by the user.

## App build error

Xcode reported "Missing argument for parameter 'wrappedValue' in call" in `Components.swift`.
The `AfterglowScaledFont` property declared `@ScaledMetric(relativeTo: .body)` without an
initial wrapped value, even though its custom initializer already constructs `_size`
with `ScaledMetric(wrappedValue: size, relativeTo: .body)`.

The declaration is now `@ScaledMetric private var size: CGFloat`. The explicit
initializer still supplies both the requested font size and `.body` scaling reference.
Dynamic Type behavior is preserved.

For the quickest repair in an existing Mac checkout, make that one-line replacement
in `ios/Afterglow/Views/Components.swift`, save, and press Command-R again.

Apple API reference: <https://developer.apple.com/documentation/swiftui/scaledmetric>.

## Test warnings

The same screenshot showed three actor-isolation warnings in `LightTests.swift` for
references to the controller's static limits. The four immutable numeric constants
in `TorchController` are now explicitly `nonisolated`. Their values and controller
behavior are unchanged; mutable controller state and methods remain `@MainActor`.

## Applying the complete repair on the Mac

The updated source archive contains both changes. To keep the signing settings
already chosen in Xcode, replace only these two files in the existing project folder:

- `ios/Afterglow/Views/Components.swift`
- `ios/Afterglow/Core/Light/TorchController.swift`

The separate `Afterglow-build-fix-1.zip` also contains only those replacement files
and a short README. Do not replace `Afterglow.xcodeproj/project.pbxproj` in the existing
Mac project: that is where the user's selected signing team and bundle identifier live.

## Verification boundary

The original Windows checks were structural checks and did not type-check SwiftUI.
This repair is based on the reported compiler diagnostic and Apple's initializer
signature. Local follow-up checks are recorded in `build-fix-1-validation.json`.
The Windows workspace has no Xcode SDK, so the repaired app and XCTest target still
need a new Xcode build on the Mac. No successful Mac build or device run is claimed.
