# Installing Afterglow on an iPhone

This guide takes the Afterglow source from a Windows PC to a Mac, builds it in Xcode, runs the tests, and installs it on your own iPhone with a **free Apple Account (Personal Team)**. A paid Apple Developer Program membership and TestFlight are optional and covered at the end.

> **Status.** The project was written on Windows. It has **not** been compiled, its XCTest suites have **not** been run, and nothing has been tried on an iPhone. Syntax, project structure, metadata, script and ZIP checks are recorded separately in [build status](BUILD-STATUS.md). A first Mac build may reveal compiler or SDK issues; Xcode on a Mac (or a real GitHub Actions run) is still required for verification.

## 1. What you need

| Item | Requirement |
| --- | --- |
| Mac | A macOS version that runs **Xcode 16 or newer** (Xcode 16 needs macOS Sonoma 14.5 or later; newer Xcode versions need newer macOS). Check Apple's [Xcode system requirements](https://developer.apple.com/xcode/system-requirements/). |
| Xcode | **16.0 or newer**, from the Mac App Store. The project uses Xcode 16's synchronized folders (project format 77); Xcode 15 cannot open it. To run on a phone, Xcode must also support that phone's iOS version, so prefer the latest release. |
| iPhone | iOS **17.0 or newer**, plus a USB/USB-C cable. |
| Apple Account | Any Apple Account (the one you use for iCloud works). No paid membership is needed for steps 1–6. |
| Disk space | Roughly 40 GB free for Xcode, an iOS simulator runtime and build files. |

Afterglow has no third-party dependencies, no package manager step, no account, and no network services.

## 2. Move the source from Windows to the Mac

On Windows, from the repository folder:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/package-source.ps1
```

This writes `dist/Afterglow-source-<version>-<date>.zip` and a matching `.sha256` file. The ZIP contains `ios/`, `docs/`, `scripts/`, `.github/` and the README. The script leaves out per-user Xcode state, build output and signing material (`xcuserdata`, `DerivedData`, `*.mobileprovision`, `*.p12`, `*.cer`, `*.p8`, `.env*`, export options). The project itself contains **no signing team, certificate or secret**: `DEVELOPMENT_TEAM` is empty and signing is set to Automatic, so whoever opens it chooses their own team.

Copy the ZIP to the Mac (Google Drive, AirDrop, USB stick, …). On the Mac, optionally verify it, then unzip:

```sh
cd ~/Downloads
shasum -a 256 Afterglow-source-*.zip   # compare with the .sha256 file
unzip Afterglow-source-*.zip           # or double-click the ZIP in Finder
```

On a Mac or Linux machine you can make the same package with `bash scripts/package-source.sh`.

## 3. First launch of Xcode

1. Install Xcode from the App Store and open it once. Accept the licence and let it install its components.
2. When asked which platforms to install, include **iOS**. If you skipped it, open **Xcode › Settings › Components** and install the iOS simulator runtime.

## 4. Open the project and run the tests

1. Open `ios/Afterglow.xcodeproj` (double-click it, or **File › Open…** in Xcode).
2. In the toolbar, make sure the scheme is **Afterglow** and choose any **iPhone simulator** (for example, *iPhone 16*) as the run destination.
3. Press **⌘U** (**Product › Test**). Xcode builds the app and runs the unit tests in `ios/AfterglowTests`. The Test navigator (**⌘6**) shows results.
4. Press **⌘R** to run the app in the simulator. Audio plays through the Mac's speakers. The simulator has no flashlight, so light mode reports that the torch is unavailable.

The same build and tests can run from Terminal:

```sh
bash scripts/ci-test.sh
```

It prints the Xcode version, builds an unsigned Release build for a generic iPhone, then runs the tests on the newest available iPhone simulator. No signing is needed for this.

If the first build fails, the error navigator (**⌘5**) lists the problems. Because the code has never been compiled, small fixes (a missing import, an availability annotation) may be needed.

## 5. Sign with your free Personal Team

1. **Xcode › Settings › Accounts**, press **+**, choose **Apple Account**, and sign in. Xcode creates a *Personal Team* for you.
2. In the project navigator, select the blue **Afterglow** project, then the **Afterglow** target, then the **Signing & Capabilities** tab.
3. Leave **Automatically manage signing** ticked and set **Team** to *Your Name (Personal Team)*.
4. Change **Bundle Identifier** from `com.yourname.afterglow` to something unique to you, such as `com.janedoe.afterglow`. Bundle identifiers are global; if Xcode says it "cannot be registered", pick another one.
5. The **AfterglowTests** target needs a team only if you run tests on a physical phone. Set the same team there if Xcode asks.

Afterglow uses background audio (declared in `Info.plist`), local files and `UserDefaults`. The current code does not request camera or microphone capture, record media, or use a network service. Torch availability, configuration failures and device behavior still require testing on your phone.

## 6. Install on your iPhone

1. Connect the iPhone to the Mac with a cable, unlock it, and tap **Trust** if asked.
2. In Xcode's run-destination menu, choose your iPhone. The first time, Xcode may spend several minutes preparing the device.
3. If Xcode reports that **Developer Mode** is required: on the iPhone open **Settings › Privacy & Security › Developer Mode**, turn it on, restart when prompted, and confirm after the restart.
4. Press **⌘R**. Xcode builds, signs with your Personal Team and installs the app.
5. The first launch may be blocked with "Untrusted Developer". On the iPhone, open **Settings › General › VPN & Device Management**, select your Apple Account under *Developer App*, and tap **Trust**. Then open Afterglow again.

### Free-account limits

- **Seven-day provisioning.** Apps signed by a Personal Team stop launching after 7 days. Reconnect the phone and press **⌘R** again to reinstall; your history and journal are kept as long as you do not delete the app.
- A free account can have only a few of its own apps installed on a device at once (currently three) and can register a limited number of new bundle identifiers per week.
- Capabilities such as push notifications, iCloud and App Groups need a paid membership. Afterglow uses none of them.

Apple's description of what a free account can do: [About your developer account](https://developer.apple.com/help/account/basics/about-your-developer-account/).

## 7. Audio-only versus development light builds

| Build | How you get it | Light |
| --- | --- | --- |
| **Debug** | **⌘R** from Xcode (the default Run configuration). | Compiled with `AFTERGLOW_LIGHT_RESEARCH`. The UI may offer an **experimental, unvalidated** torch test after a fresh per-session risk screen. |
| **Release** | **Product › Archive**, or **Product › Scheme › Edit Scheme… › Run › Build Configuration › Release**. | Light is compiled out of availability; the app is audio-only. |

The only light sequence in the code is an **engineering smoke test** chosen by the project as arbitrary hardware-test values: nominal 3 Hz, 50 % duty cycle, a requested torch level of 0.02, at most 30 seconds of light after a 10-second delay, and stop on pause, interruption, leaving the app, heat or any torch error. **These are not a safe dose, not a treatment and not taken from any study.** Requested timing is scheduled on the main thread; what the LED actually emits (timing, jitter, brightness, stop latency) has not been measured.

Before anyone looks at the light:

1. Point the phone's back away from all faces (for example, face-down on a table with the torch visible from the side, or aimed at a wall).
2. Start a light session and confirm the 10-second delay, the flashing, the 30-second end, and that **pause**, **stop**, switching apps, locking the screen, a phone call and Control Center all switch the torch off immediately and it does not come back on after resuming.
3. Read [the science and safety report](research/science-and-safety.md). Flashing light can trigger seizures, including in people with no known history. Do not use light if any screening item applies or you are unsure, and never while driving or moving.

To switch light off in Debug builds as well, remove `AFTERGLOW_LIGHT_RESEARCH` from **Build Settings › Active Compilation Conditions › Debug** of the Afterglow project.

## 8. Optional later: paid membership and TestFlight

TestFlight and the App Store require the [Apple Developer Program](https://developer.apple.com/programs/enroll/) (paid, yearly). After enrolling:

1. In **Signing & Capabilities**, change **Team** to your paid team and keep automatic signing. Use a bundle identifier you own.
2. In [App Store Connect](https://appstoreconnect.apple.com), **Apps › + › New App**: platform iOS, name, primary language, the same bundle identifier, and any SKU.
3. Choose **Any iOS Device (arm64)** as the destination and run **Product › Archive** (this uses the Release configuration, so light is unavailable).
4. In the Organizer window that opens, select the archive, **Distribute App › App Store Connect › Upload**, and accept the default signing options.
5. Each new upload needs a higher build number: raise **Build** (`CURRENT_PROJECT_VERSION`) in the target's **General** tab; raise **Version** (`MARKETING_VERSION`) for user-visible releases.
6. When processing finishes, add testers in App Store Connect under **TestFlight**. Internal testers (members of your team) can test right away; external testers require Beta App Review.

Already prepared in the project: a 1024 × 1024 opaque app icon, `ITSAppUsesNonExemptEncryption = NO` (no export-compliance prompt), a privacy manifest (`PrivacyInfo.xcprivacy`: no tracking, no collected data, `UserDefaults` reason `CA92.1`), background audio mode, portrait iPhone layout. Still needed for a public release: a privacy policy URL, App Store screenshots and description, medical-claim-free marketing copy, and, if light were ever enabled in Release, the optical/device measurements and review described in the science report.

## 9. Continuous integration (optional)

`.github/workflows/ios.yml` runs on GitHub's `macos-15` runners: it calls `scripts/ci-test.sh` (unsigned Release device build plus simulator tests) and then packages the source ZIP as a build artifact. It needs no secrets and does not sign or upload anything. To pin a specific Xcode, set a repository variable `XCODE_APP` (for example `Xcode_16.4`). This workflow has not been run yet.

## 10. Troubleshooting

| Symptom | Fix |
| --- | --- |
| "The project … cannot be opened because it is in a future Xcode project file format" | Update to Xcode 16 or newer. |
| "Failed to register bundle identifier" / "No profiles for … were found" | Choose a different, unique bundle identifier and make sure a Team is selected (step 5). |
| "iPhone is not available" / "iOS x.y is not installed" | Update Xcode, or install the matching platform in **Xcode › Settings › Components**. |
| "Developer Mode disabled" | Step 6.3. |
| "Untrusted Developer" on the phone | Step 6.5. |
| App stops opening after a week | Personal Team profile expired: reconnect and press **⌘R**. |
| No sound | Check the ring/silent switch is not the cause (Afterglow uses the playback category, so it should play in silent mode), the volume, and whether another app holds audio. |
| Light option missing | Expected in Release builds, in the simulator, on devices without a torch, in sleep sessions and in journeys. |
