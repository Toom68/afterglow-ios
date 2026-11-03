# Afterglow for iPhone

An original native iOS meditation prototype, informed by public research into Lumenate. Built with SwiftUI and AVFoundation, without external app dependencies. It is independent of Lumenate and does not contain its source code, paid audio, artwork, branding, or proprietary light sequences.

**Delivery status:** this is an Xcode source project, not a signed IPA or a TestFlight release. Development and static review were performed on Windows. Xcode compilation, simulator tests, and physical iPhone verification still need to run on a Mac. Do not treat the presence of tests or a CI workflow as evidence that they have passed.

## Install on your Mac and iPhone

1. Download the source ZIP from Google Drive onto your Mac and unzip it.
2. Install the latest Xcode compatible with your Mac and your iPhone's iOS version. Launch Xcode once to install its components and iOS platform support.
3. Open `ios/Afterglow.xcodeproj` and select the **Afterglow** scheme. First choose an iPhone simulator and use **Product > Test** to run the included tests.
4. In **Xcode > Settings > Accounts**, add your existing Apple Account. A paid membership is not required for personal-device testing.
5. Select the **Afterglow** app target, open **Signing & Capabilities**, enable automatic signing, choose your **Personal Team**, and change the bundle identifier to something unique to you, such as `com.yourname.afterglow`.
6. Connect your iPhone by USB, unlock it, and trust the Mac if prompted. Enable **Developer Mode** in **Settings > Privacy & Security** if Xcode asks, following the phone's restart and confirmation prompts.
7. Choose your iPhone as the run destination and press **Run**. If iOS asks you to trust your developer profile, use the profile shown in **Settings > General > VPN & Device Management**.

Free Personal Team provisioning expires after seven days. Rebuild and reinstall through Xcode when it expires; avoid deleting the app if you want to preserve its local journal. TestFlight and App Store distribution require paid Apple Developer Program membership and additional signing and release steps. See the detailed [iOS installation guide](docs/INSTALL-IOS.md).

Official Apple references: [free account and Personal Team limits](https://developer.apple.com/help/account/basics/about-your-developer-account/), [program enrollment](https://developer.apple.com/help/account/membership/program-enrollment/), [enrolling with the Apple Developer app](https://developer.apple.com/help/account/membership/enrolling-in-the-app/).

## What is in the app

- An original session library with search, intent filters, and saved favourites.
- Original procedural ambient soundscapes, adjustable session duration and volume, and an option to continue playing music from another app.
- A journey builder that saves an ordered queue of up to five sessions. Journeys are audio only in this prototype.
- Intention setting, pause/resume/early stop, session history, and a private local journal with mood notes, editing, deletion, and sharing/export.
- An explicitly experimental, opt-in native torch mode in **Debug development builds only**, with a preparation delay, bounded output, stop controls, and interruption handling. Light is off by default, unavailable for sleep sessions and journeys, and requires a fresh risk acknowledgement each session. Release/Archive builds keep light disabled.
- Offline operation, without account creation, subscriptions, advertising, analytics, or an AI service.

The [feature comparison](docs/FEATURE-MATRIX.md) distinguishes implemented workflows from features that remain outside this prototype.

## Read before testing light

Flashing light can trigger seizures and other adverse effects, including in someone without a known history. Closing the eyes, lowering brightness, or passing a self-report checklist does not establish safety. The original sequence here is an **unvalidated engineering prototype**, not a clinically validated dose or a reconstruction of Lumenate's protocol. There are no claims of equivalent experience, medical benefit, or safety.

Start by verifying controls without exposing anyone to the torch. The Debug engineering smoke test requests nominal 3 Hz at 50% duty, a torch level capped at 0.02, a 10-second positioning delay, and at most 30 seconds of light. Those are arbitrary engineering test settings, not a validated exposure or a value set taken from a study. A device's numeric torch fraction is not a measurement of optical intensity. Physical output timing, failure behavior, device heating, and shutdown behavior have not been measured on an iPhone. The [science and safety report](docs/research/science-and-safety.md) explains the evidence, contraindication context, limitations, and required verification. Audio-only use remains available.

## Research and verification

- [Product research](docs/research/product.md): official app pages, store listings, all 84 public support articles, privacy and safety material, observed workflows, and explicit unknowns. Desk research dated 31 October 2026; no paid account or hands-on Lumenate session access.
- [Methods, evidence, and safety](docs/research/science-and-safety.md): primary studies, study controls, publicly disclosed parameters, scientific uncertainty, and iOS implementation requirements.
- [Build and delivery status](docs/BUILD-STATUS.md): checks actually run, review findings and resolutions, and work that still needs a Mac or physical device.
- [Mac verification checklist](docs/qa/MAC-CHECKLIST.md): practical build, audio, journal and device checks to run later.
- `ios/AfterglowTests`: deterministic timing, persistence, audio synthesis, and lifecycle tests. Run them in Xcode.
- `.github/workflows/ios.yml`: a macOS build/test workflow for use if you later put this project in a GitHub repository. No remote repository or CI run was created during this session.

Journal and history data stay in the app's local storage. Normal device backups may include them. Sharing a reflection exports it outside the app; deleting local data cannot delete copies you have shared or backed up.
