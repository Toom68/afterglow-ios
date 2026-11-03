# Lumenate — Product Research (mobile app + Nova)

- **Research date (all sources accessed):** 2026-10-31
- **Method:** desk research of public, official sources only — lumenate.co, support.lumenate.co (Intercom help centre, all 84 articles across 6 collections), Apple App Store (GB) listing and Apple iTunes Lookup API, Google Play (GB) listing, the official App Privacy Policy, App Terms, and the Medical Risk Information PDF.
- **Access limitations (read this first):**
  - The app was **not installed**, no account was created, and no paid/free session was played. Nothing here is based on hands-on use.
  - Store screenshots and website images were **not inspected visually** (only alt-text/captions came through), so UI layout claims are taken from support-article text.
  - No session audio, light-sequence data, scripts, music or artwork was accessed or copied. Session names appear only where official public text names them.
- **Evidence labels used throughout:**
  - **[F]** Observed fact, stated in an official source (cited).
  - **[R]** Third-party user review shown on an official store or shop page. Anecdotal, not verified.
  - **[I]** Inference by the researcher. Plausible but not confirmed.
  - **[U]** Unknown / proprietary. Not publicly documented.

---

## 1. Executive summary

Lumenate (Lumenate Growth Ltd, Bristol, UK) is a subscription wellbeing app. It strobes the phone's **flashlight/torch** at "research-driven frequencies" onto the user's **closed eyes**, synced with guided audio and music. The goal is a "deeply meditative, semi-psychedelic state" via **flicker light stimulation (FLS) / neural entrainment** [F: site home, science page; support "Introduction to the science"]. The light is plain white. All colours and imagery are produced by the user's own visual system [F: "How the experience is generated"].

The product has three pillars: **Explore** (introspection/perspective), **Relax** (de-stress, presence) and **Sleep** (lower frequencies, "typically around the 3 Hz range") [F: "How can Lumenate help me to explore, relax and sleep better?"].

Core feature set (as of 2026-10-31):
- A curated library of almost 50 experiences. Longest single session is about 30 min. New releases every 1–2 months [F].
- Celebrity content: Rosamund Pike as voice and Creative Director; a 9-session John Lennon *Mind Games* special-mix series [F: store listings].
- **Choose Your Own Soundtrack (CYOS):** light-only mode with configurable length and intensity profile, used with your own music [F].
- **Journeys:** queue up to 5 sessions into one seamless experience. Launched in iOS 7.0.0, 9 Jul 2026 [F].
- **Favourites:** launched in iOS 7.2.0, 30 Jul 2026 [F].
- **Lumenate Guide (AI, Beta):** uses OpenAI. It does "Help Me Choose" session recommendation and pre-session intention setting. Store copy also mentions "integration" [F].
- **Personal Journal** [F, store copy; very little detail public].
- **Offline downloads** per session [F].
- **Safety screening during onboarding**, plus Medical Risk Info in Settings [F].
- **Lumenate Nova:** a BLE light mask with 4 independently controlled LEDs, controlled by the app. Offline core sequences, Group Session for up to 5 masks, OTA firmware updates. £99 on sale, £130 regular [F].

Monetisation:
- 7-day free trial, then monthly/yearly auto-renewing subscription. Pricing is shown only on the in-app paywall and varies by region [F].
- Nova bundle: 1-year web subscription at £30, renewing at £60 [F].
- Kickstarter backers got lifetime access [F].
- "Access for All" free-access scheme via survey [F].

---

## 2. Source register

Every URL below was accessed on **2026-10-31**. The "Source date" column is the date the source shows itself (Intercom `lastUpdatedDate`, policy "last updated", store version dates), or "undated".

### 2.1 Official website (lumenate.co — Shopify; © 2026)

| # | Page | URL | Source date |
|---|------|-----|-------------|
| W1 | Home | https://lumenate.co | undated (© 2026) |
| W2 | The Lumenate App | https://lumenate.co/pages/the-lumenate-app | undated |
| W3 | Nova (marketing) | https://lumenate.co/pages/lumenate-nova | undated |
| W4 | Nova (product/shop) | https://lumenate.co/products/lumenate-nova | undated; 209 reviews shown |
| W5 | Science | https://lumenate.co/pages/the-science | undated |
| W6 | Benefits | https://lumenate.co/pages/benefits | undated |
| W7 | About (timeline) | https://lumenate.co/pages/about | undated |
| W8 | FAQ | https://lumenate.co/pages/faq | undated |
| W9 | Access for All | https://lumenate.co/pages/access-for-all | undated |
| W10 | Download (store links) | https://lumenate.co/pages/download | undated |
| W11 | App Privacy Policy | https://lumenategrowth.com/app-privacy-policy/ (serves lumenate.co) | **Last updated 04 Feb 2026** |
| W12 | App Terms | https://lumenategrowth.com/app-terms/ | **Last updated 30/10/26** (30 Oct 2026) |
| W13 | Medical Risk Information (PDF) | https://cdn.shopify.com/s/files/1/1004/0511/7302/files/Lumenate-Medical-Risk-Information.pdf?v=1787163740 | PDF title "…Safety Screening Flow Information 1_12_2025" (1 Dec 2025) |
| W14 | Web subscription portal (Stripe) | https://payments.lumenate.co/p/login/28EeVdeH1cUx7YD4jf1B600 | not opened (login) |

### 2.2 App stores

| # | Source | URL | Source date / key data |
|---|--------|-----|------------------------|
| S1 | Apple App Store (GB) | https://apps.apple.com/gb/app/lumenate-explore-relax/id1538397461 | v7.10.0, 19 Oct 2026; 4.7★ / 3.4k ratings; 18+; 544.7 MB; Health & Fitness; "Supports SharePlay" |
| S2 | Apple iTunes Lookup API | https://itunes.apple.com/lookup?id=1538397461&country=gb | first release 2021-02-21; current 2026-10-19; min iOS 15.0; 24 listed languages |
| S3 | Google Play (GB) | https://play.google.com/store/apps/details?id=com.lumenate.lumenateaa&hl=en_GB&gl=GB | Updated 29 Sept 2026; 4.7★ / 8.84k reviews; 1M+ downloads; PEGI 3 |

Note: the App Store link on W10 points to the `tt` storefront, with the same app id 1538397461.

### 2.3 Official support centre (support.lumenate.co, Intercom)

Collections: FAQs (40), Lumenate App (6), Lumenate Nova (18), Science Behind Lumenate (7), Benefits (5), Guidance for Immersive Experiences (8).
Base URL for every article: `https://support.lumenate.co/en/articles/<slug>`.

| Slug | Last updated |
|------|-------------|
| 15819298-journeys | 2026-07-09 |
| 16220457-lumenate-guide | 2026-08-05 |
| 16346598-can-i-favourite-sessions | 2026-08-12 |
| 9354057-how-do-i-turn-off-vibrate-haptics-ios-only | 2026-08-12 |
| 16393202-i-can-t-play-a-session-download-failed | 2026-08-13 |
| 11744116-can-i-play-my-own-music | 2026-01-16 |
| 11790841-is-there-a-way-to-turn-music-audio-off | 2026-01-16 |
| 11790859-how-many-sessions-experiences-are-there | 2025-07-17 |
| 11750257 / 11790854 (padlock / session not playing) | 2025-07-10 / 2025-07-17 |
| 9354100-when-is-the-next-session-being-released | 2024-05-20 |
| 9335440-when-will-the-app-be-translated-to-my-language | 2024-05-16 |
| 10174430-i-still-have-questions-how-can-i-get-support | 2026-01-16 |
| 9354059-is-the-app-free-to-use | 2025-10-17 |
| 9454836-how-much-does-the-app-cost | 2025-11-21 |
| 12580070-understanding-subscription-types | 2026-07-14 |
| 9335397-i-ve-lost-access-to-my-subscription | 2026-07-14 |
| 9354061-is-the-subscription-cross-platform | 2026-10-16 |
| 9335073-how-do-i-cancel-my-subscription | 2026-01-19 |
| 11848597-how-do-i-cancel-my-in-app-subscription-and-request-a-refund | 2026-01-19 |
| 9335386-how-do-i-get-a-refund | 2026-01-19 |
| 11739280-i-ve-been-charged-during-my-free-trial | 2025-10-02 |
| 12639001-lifetime-access | 2026-01-19 |
| 12639109-1-year-kickstarter-web-subscription | 2026-01-23 |
| 13432060-1-year-subscription-nova-bundle | 2026-10-08 |
| 9335079-access-for-all | 2026-01-16 |
| 9335382-how-do-i-delete-my-account | 2026-01-16 |
| 9335388-how-do-i-change-my-email-address | 2025-11-26 |
| 12918109-how-do-i-connect-to-my-nova | 2026-05-08 |
| 12918154-i-m-struggling-to-connect-my-nova-what-might-be-going-wrong | 2026-09-15 |
| 13512963-how-do-i-access-nova-free-core-light-sequences | 2026-09-24 |
| 13431688-does-nova-require-a-subscription | 2026-01-28 |
| 13431643-how-does-the-nova-experience-differ-from-the-phone | 2026-01-19 |
| 13431654-can-i-connect-multiple-novas-to-one-phone | 2026-01-19 |
| 13438091-how-do-i-run-a-session-with-multiple-people-at-the-same-time | 2026-01-20 |
| 13431714-does-nova-have-in-built-speakers | 2026-01-19 |
| 13545728-how-do-i-update-my-nova | 2026-01-28 |
| 13483466-my-nova-won-t-turn-on | 2026-09-26 |
| 13484255-my-nova-won-t-charge-to-100 | 2026-01-23 |
| 13452332-how-do-i-clean-and-look-after-my-nova | 2026-01-21 |
| 13431625-does-nova-ship-to-my-country | 2026-04-14 |
| 13438060-understanding-expected-delivery-times | 2026-09-25 |
| 13532827-when-will-i-receive-the-tracking-number-for-my-nova-order | 2026-07-01 |
| 11749402 / 11749128-where-can-i-buy-the-lumenate-nova | 2026-01-20 |
| 12639265-kickstarter-backer-survey / 13239169-kickstarter-eu-tax-payments | 2026-01-19 / 2025-12-26 |
| 9335089 how-should-i-be-holding-my-phone; 9335094 maximise-immersion; 9335095 what-should-i-be-doing; 9335097/9335129 what-to-look-out-for; 9335101 how-often | 2024-05-16 |
| 10174357 correct-environment; 10174464 what-position | 2024-11-21 |
| 9357930-what-can-i-purchase-to-make-experiencing-lumenate-easier | 2026-01-16 |
| 9335105-does-it-damage-my-eyes | 2025-07-10 |
| 9354071-is-the-brightness-of-the-light-safe; 9354063 side-effects; 9354095 under-18; 9354084 how-often-can-i-use; 9335438 long-term | 2024-05-20 |
| 9335111 side-effects-long-term; 11749934 is-lumenate-safe | 2025-08-20 / 2025-07-10 |
| 9335140 intro-science; 9335148 neural-entrainment; 9335149 subjective-effects; 9335150 how-experience-generated; 9335121/9335151 explore-relax-sleep | 2025-10-15 |
| 9335144-flicker-light-stimulation-fls | 2025-10-09 |
| 9335120 improve-my-life; 9335136 how-long-benefits; 9335137 what-benefits-others | 2024-05-16 |

**Staleness warning:** many usage/safety articles date from May 2024. Numbers inside them may be out of date, e.g. "750,000 downloads" and "200,000 hours" in 9335137. Treat them as historical.

---

## 3. Company and context

- Lumenate Growth Ltd: company no. 12254320, registered in Bristol. ICO reg. ZA854929 [F: W11, W12]. Founders "Jay & Tom", former Jaguar Land Rover engineers [F: W7].
- Timeline [F: W7]:
  - Group light events in Bristol, cut short by COVID.
  - Pivot to a phone-based experience in Apr 2020; app built from Aug 2020.
  - Beckley Waves investment Dec 2020.
  - Rosamund Pike joins as investor and Creative Director, Feb 2021.
  - Public launch Mar 2021. Apple shows first release as 2021-02-21 [F: S2].
- Scale claims:
  - "Trusted by a million minds" (registered and completed at least one session) [F: W1].
  - Google Play shows 1M+ downloads [F: S3].
  - "94% report a positive impact" — survey of 170 customers with 2+ months and 10+ sessions [F: W1/W6].
- Science positioning: cites Bartossek et al. 2021, Montgomery et al. 2024, Schwartzman et al. 2019 and an fMRI thalamocortical study. Says it supports research at Leiden, UCSF, Macquarie, FU Berlin, Imperial and Liège [F: W5]. Regulatory stance: "not a medical device" under FD&C Act §201(h) [F: S1, W12].
- Release cadence: iOS ships roughly weekly to fortnightly. Versions 6.2.4 (4 Mar) through 7.10.0 (19 Oct 2026), mostly "small fixes" [F: S1]. Notable notes:
  - 7.0.0 (9 Jul 2026) "Introducing Journeys".
  - 7.2.0 (30 Jul 2026) new poetry experience (Kahlil Gibran, "On Self-Knowledge") plus Favourites.
- Language: the app and sessions are English only; translation is "long-term vision" [F: 9335440, 2024-05-16]. The Apple listing shows 24 language codes [F: S2]. [I] These are probably store-metadata locales, not translated content.

---

## 4. Observable main flows

### 4.1 Acquisition → install → account

1. Install from App Store or Google Play [F: W10]. Requires iOS 15.0+. iPhone only, "Not verified for macOS" [F: S1, S2].
2. **Account creation is mandatory** before using the services. You must accept the Terms when creating it, and only one account per person is allowed [F: W12 §1.3, §3.2].
3. Sign-in methods: email, Apple, Google or Facebook [F: 13432060]. The privacy policy also mentions Twitter/Instagram/TikTok social login [F: W11 §2]. [U] Which providers are live today is unconfirmed.
   - Sign in with Apple plus Hide My Email cannot be used on Android [F: 9354061].
4. Data collected at signup: name, email, "approximate age segment" [F: W11 §1; W12 §3.2].

### 4.2 Onboarding and safety screening

- The **Photosensitivity Warning and Medical Risk Information are presented during account creation**, along with the safety criteria. The user confirms they are 18+ and meet the criteria [F: W12 §3.4, §4.3, §4.3.9; W8 "Is Lumenate safe?"].
- Exclusion criteria (same list on the website gate and in the Terms) [F: W1 modal, W12 §4.3]:
  - Under 18.
  - Personal or family history of epilepsy.
  - Prior twitching, absence, confusion or severe dizziness from flicker or screens.
  - Unexplained blackouts, or morning head/limb jerks.
  - Brain injury, brain surgery or brain tumour.
  - Pregnancy.
  - Sleep deprivation, alcohol or sedative withdrawal, or seizure-lowering medication.
  - Psychosis, severe panic attacks, severe dissociation, or feeling suicidal.
  - Acknowledging that it may trigger fits, migraines, headaches or motion sickness.
- The Medical Risk Info PDF (7 pp.) covers [F: W13]:
  - Photosensitive epilepsy prevalence: about 1 in 4,000; 90% have their first seizure before 20.
  - Warning symptoms, and the in-session mitigation "cover one eye, drop the phone or turn it face-down".
  - A long list of medication classes that lower seizure threshold.
  - Alcohol withdrawal, mental-health exclusions, and references.
- After onboarding, Medical Risk Info is always available in **Settings** [F: 9335114].
- [U] Exact screen order is not public: whether screening comes before or after the paywall or trial offer, whether there are personalisation or goal questions, and whether there is a setup tutorial.
  - [F] Two related mentions exist. A "Learn More About Lumenate" section on the home screen covers setup [9335136, 2024]. "Discover Lumenate", "Discover Nova" and an "Instructional Series" exist as sessions [15819298].
  - [I] These act as the post-signup tutorial content.
- [I] The 7-day trial asks for payment details at start and is handled via the store [F: 9354059]. That strongly suggests a **paywall/trial step in or right after onboarding**, as is standard for RevenueCat apps (RevenueCat is named in W11 §6).

### 4.3 Home / navigation

- Tabs and screens named in support text [F]:
  - iOS home tab is **"For You"**, with favourites at the top [16346598].
  - Android home is the **"Experience"** tab [16346598].
  - A **Library** exists; on Android you can favourite from library thumbnails [16346598].
  - A **Settings** tab shows a red dot when a Nova firmware update is available [13545728].
  - The home screen shows a "Help Me Choose" entry for the AI Guide [16220457] and a **current Journey summary card** [15819298].
- Settings items named in support [F]:
  - "Support Centre" button at the top, which opens in-app chat (Intercom) [10174430].
  - Account > Subscription Information > Redeem/Restore / Redeem a Web Subscription / Cancel subscription [12580070, 9335073, 13432060].
  - Web Login (enter code) [13432060].
  - Lumenate Nova section: Connect to a new Nova, Update Nova, and Device Settings (offline sequence selection, Check for Updates, Forget Nova) [12918109, 13545728, 13512963, 12918154].
  - Medical Risk Info [9335114].
  - Haptics toggle [9354057].
- The Terms reference an **"Unlock All Content"** page in settings that shows subscription options [F: W12 §9.4].
- [U] Full tab bar inventory and the presence of a profile, stats or streaks screen are not documented. [I] There is likely a progress/history view: the change-email article warns users would lose "sessions you've done or previous journal entries" [F: 9335388].

### 4.4 Library and categories

- Top-level intents: **Explore / Relax / Sleep** [F: W1, W6, 9335121].
- Category names quoted in support: **"Relax and De-Stress"** and **"Sleep Better"** [F: 11744116].
- Content volume: "almost 50 unique experiences" (as of 2025-07-17) [F: 11790859]. Cadence goal: one new session every 1–2 months [F: 9354100, 2024].
- Durations:
  - Longest single session is "around 30 minutes" [F: 15819298].
  - [R] A Nova shop reviewer says some sessions are about 10 min, longest about 20–30 [W4].
  - [R] A 2021 App Store reviewer said sessions felt like 5-minute blocks, with the strobe fading out and back every 5 minutes [S1]. Old and anecdotal, but a hint at sequence construction.
- Session types and named items (names only; no content accessed):
  - *Choose Your Own Soundtrack* (Meditative / Relaxed / Intense sequence; adjustable or endless length) and *CYOS (Sleep)* [F: 11744116, 11790841].
  - *Discover Lumenate*, *Discover Nova*, *Instructional Series* [F: 15819298].
  - *Vocal Toning* [F: 15819298].
  - John Lennon *Mind Games* Special Mixes — 9 sessions, with additional instrumentation by Sean Ono Lennon [F: S1, S3].
  - Guided meditations voiced by Rosamund Pike [F: W1, S1].
  - Kahlil Gibran poetry experience "On Self-Knowledge" [F: S1 v7.2.0].
  - Store copy lists "Guided Sessions" (goals and contentment), "Better Sleep" custom sessions, "Open Explorations" and "Guiding Soundtracks" [F: S1].
- Free vs paid split:
  - The Terms describe a **"Basic Subscription"** with limited features and a **Paid Subscription** [F: W12 §9].
  - The Nova shop says the app "offers a limited number of free sessions" [F: W4].
  - [R] One reviewer reports "just two sessions are free" [W4].
  - [U] The exact free set is unknown.

### 4.5 Session preparation (session detail page)

Elements on the session page that support articles mention [F]:
- Title, description, and a **heart / favourite** button. On iOS it sits next to the title; on Android it is further down the page [16346598].
- **Duration selector.** Sessions in a Journey have one, and CYOS length is customisable [15819298, 11744116]. [I] Many standard sessions offer more than one length (e.g. 10/20 min). Reviews mention "10 minute session" and "20 minute session" [R: S1].
- **"Available Offline" toggle**, found below the description, to download before playing [16393202]. Support also calls this "Download Session" [F: S3 developer reply].
- **AI Guide [Beta] toggle.** When on, it helps explore thoughts and emotions and set an intention before the session [16220457].
- **Add to Journey** button at bottom-left, next to "Play Session". The icon switches between plus and tick [15819298].
- **Options menu at top-right** (iOS) containing "Start Group Session" for Nova. On Android, a blue button at the top [13438091].
- **"Play Session"** primary CTA [15819298].
- Pre-session guidance content (support articles, also the "Learn More About Lumenate" home section) [F]:
  - Dark, quiet room.
  - Good headphones.
  - Avoid alcohol ("reduces entrainment" per their EEG studies).
  - Comfortable position. Five recommended postures are listed.
  - Phone 5–10 cm from the face, torch centred between the eyes, elbow supported.
  - Accessories: neck phone holder or phone clamp.
  - Set an intention but "go with the flow".

### 4.6 Playback

- Start: tap Play. **Audio starts first; the light begins about 1–2 minutes in** [F: 11790854, 12918154].
- **Accidental-pause protection:** the play screen shows a **padlock / long-press** control, so pausing requires a long press [F: 11790854, 11750257].
- Eyes are closed and the torch faces them [F: 9357863].
- Haptics (iOS only) can be toggled from a small top-right menu on the experience screen or in Settings. With Nova, haptics stop if the phone screen locks (an iOS limitation) [F: 9354057].
- Audio:
  - Off on all sessions — iOS only.
  - Mixing in background music from another app — CYOS only [F: 11790841].
  - [R] A Play reviewer notes that with your own music the light "is not programmed to match the music" [S3].
- Nova mode: a Nova icon at top-right turns blue when the mask is active [F: 12918154]. [R] One reviewer complains the app sends confusing messages about whether it is using the mask or the phone light [S3].
- **Journeys playback:** up to 5 sessions back-to-back that "transition elegantly", and can run more than 2 hours [F: 15819298].
  - Can't be saved yet [F].
  - Excluded: Discover Lumenate, Discover Nova, Instructional Series.
  - Not yet supported on iOS: Vocal Toning, CYOS, CYOS Sleep [F].
  - Editing: swipe-left to remove; iOS uses Edit plus drag; Android drags directly or uses Clear all [F].
  - Recommended arc: Grounding → Core experience → Meditative transition [F].
- **SharePlay** is listed as supported on the App Store [F: S1]. [U] It is unclear what is shared (audio sync? light?).
- **Sudden Motion Detection** is mentioned as "not currently supported for offline [Nova] sequences" [F: 13512963]. That implies it is active in app-driven sessions.
  - [I] It probably stops or dims the light when the phone or mask detects a sudden movement, such as a dropped phone or a jerk. This lines up with the medical advice to drop the phone if symptoms appear.
  - [U] Thresholds, sensor (phone IMU vs mask) and behaviour are not public.
- [U] Proprietary: flicker frequencies per session (besides the "around 3 Hz" Sleep guidance), waveform/duty cycle, ramping, the intensity-to-distance model, audio/light sync format, and how Nova's 4 LEDs are used spatially.

### 4.7 Post-session: journaling and integration

- **Personal Journal — "Reflect on your thoughts"** is listed as a premium feature [F: S1, S3]. Journal entries persist per account, and users lose them if the account is recreated [F: 9335388].
- AI Guide store copy: "Personalize your experience, set intentions **and integration**" [F: S1, S3]. The support article only documents *finding a session* and *preparing / intention setting* [F: 16220457].
  - [I] Integration (post-session reflection) may exist as a journal prompt or a Guide chat, or may be marketing copy ahead of the feature.
- [U] Not documented anywhere public:
  - Whether a journal prompt appears automatically after a session.
  - Whether there are mood check-ins, rating, tags, streaks, history or calendar.
  - Whether entries can be exported or searched.
- **Gap to close first** if this matters: needs hands-on observation, or official screenshots inspected visually.

### 4.8 AI guide ("Lumenate Guide", Beta)

All facts from 16220457 (2026-08-05) and W11 §3:
- Powered by **OpenAI via the Enterprise API**. Labelled **Beta**. Premium feature: the Nova bundle copy says "Access Premium features, such as our AI Guide" [W1 modal].
- Two entry points:
  1. **Help Me Choose** on the home screen. The user describes how they feel and what they want, and the Guide predicts the best-fitting session.
  2. **AI Guide [Beta] toggle** on a session page. Helps explore thoughts and emotions and set an intention.
- After the library is exhausted, Support suggests using the Guide to "guide to an intention and then use a pre-existing session" [11790859]. The Guide recommends from the catalogue; it does not generate sessions.
- Safety framing:
  - Not a replacement for therapy.
  - Avoid it if struggling with mental illness.
  - Don't share personally identifiable information.
  - "Responses are generated by AI and shouldn't be taken as direct advice."
- Data handling:
  - Lumenate does **not retain chat content** unless the user **flags** messages through an in-app flagging feature.
  - OpenAI processes messages and keeps them for up to 30 days.
  - A DPA is in place, and US-transfer safeguards are claimed.
- [U] Not public: model and version, system prompt, the catalogue-matching method (tags vs embeddings), conversation length limits, and whether past chats or journal feed into recommendations.

### 4.9 Account, subscription and support flows

- **Trial:** 7 days with full access. Payment details are captured at start, and the user must cancel ≥24 h before the trial ends [F: 9354059, 9335073].
- **Plans:** monthly or yearly auto-renewing. Price is local and only shown on the paywall [F: 9454836]. Terms §9.6 says yearly is a fixed 12-month contract, with a renewal reminder ≥7 days before [F: W12].
- **Purchase channels** [F: 12580070]:
  - In-app via Apple or Google.
  - Web via Stripe: Nova bundle 1-year, or 30-day intro.
  - Kickstarter 1-year (£30 renewal) or Lifetime.
- Web-to-app linking [F: 13432060]:
  - A "Magic Login" email button, or Settings > Web Login code (`xxxx-xxxx`).
  - Fallback: Subscription Information > Redeem/Restore > "Redeem a Web Subscription".
  - The Stripe billing account is separate from the app account.
- **Restore** button sits at the bottom-left of the paywall [F: 9335397].
- Subscriptions are **cross-platform** (iOS ↔ Android) via the same account [F: 9354061, 2026-10-16].
- **Account deletion** and **email change** are both manual, via support chat or email. Email change means delete and recreate (progress and journal lost) [F: 9335382, 9335388].
- **Support:** in-app Intercom chat from Settings, plus email support@lumenate.co / support@lumenategrowth.com [F: 10174430]. Feature and session requests go through chat with the keywords "feature request" or "session request" [F].

---

## 5. Pricing (as publicly observable)

| Item | Price / terms | Evidence |
|---|---|---|
| App download | Free | [F] S1, S3, W8 |
| Free trial | 7 days, full access, card required, cancel ≥24 h before end | [F] 9354059 |
| Basic (free) tier | "limited access to certain basic features"; "limited number of free sessions" | [F] W12 §9.2, W4 |
| Monthly / yearly in-app | **Not published.** Varies by locale; shown only on paywall | [F] 9454836. [R] one App Store review mentions "£9.99 a month" (unverified, undated in extract) |
| Nova bundle 1-yr web subscription | £30 for year 1 (50% off), renews at **£60/yr** | [F] W1 modal, 13432060 |
| Nova without bundle | Free 30 days of Premium can be claimed; after that, limited free sessions | [F] W1 modal, 13431688 |
| Kickstarter 1-yr | renews at £30 | [F] 12639109 |
| Lifetime | Kickstarter-only add-on; "currently aim to only include this with the Kickstarter campaign" | [F] 12639001 |
| Access for All | Free access for those who can't afford it; Typeform survey, reply within 10 days | [F] W9, S1 |
| Nova hardware | **£99** sale (regular £130); ships US/EU/UK/CA/AU/NZ | [F] W4, 13431625 |
| Refunds | In-app → Apple/Google; web → contact Lumenate | [F] 9335386, 11848597 |

Naming inconsistency: the stores say **"Lumenate Plus"**, while the website and Terms say **"Premium"**. In-app it is "Unlock All Content" [F: S1/S3 vs W1/W12].

---

## 6. Offline, privacy and data

### 6.1 Offline

- App: sessions can be downloaded per session with the "Available Offline" toggle. This is a premium feature ("Offline Access: Download sessions for use without Wi-Fi") [F: S1, 16393202].
  - [R] A Play reviewer (Jul 2026) thought it needed internet. Support replied that downloads are available with a subscription [S3].
  - [U] Not documented: bulk download, storage size per session, and whether offline playback needs periodic entitlement checks. App binary is 544.7 MB [F: S2]. [I] Some content may be bundled.
- Nova: one 10-minute **light-only** core sequence (Relaxed, Explore or Sleep) can be saved to the mask and played without a phone (power + "+" held 2 s). It is free with no subscription. Sudden Motion Detection is not supported in this mode [F: 13512963, 2026-09-24].

### 6.2 Privacy (policy W11, 04 Feb 2026, and store disclosures)

- Controller: Lumenate Growth Ltd, under UK GDPR and EU GDPR [F].
- Data categories:
  - Identity (name), contact (email), profile (username/password, approximate age segment).
  - Limited payment metadata via Stripe or the app stores.
  - Technical/usage analytics (frequency, page engagement, session length).
  - Marketing preferences, ad click-through attribution, feedback, and Guide inputs [F].
- Processors named: **RevenueCat** (subscriptions), **Mixpanel** (analytics), **Adjust** (attribution), **OpenAI** (Guide), **Stripe** (web payments), plus a "customer support platform provider" [F]. [I] The support provider is Intercom ("We run on Intercom" on the help centre).
- Adjust data: hashed IP, IDFA/GAID, install/open, in-app events, ad views/clicks. Its fraud product also uses touch, accelerometer, gyroscope, battery and light-sensor data [F].
- Push and email marketing are consent-based [F].
- Apple privacy label [F: S1]:
  - Data used to track you: Purchases, Identifiers, Usage Data, Other.
  - Linked to you: Purchases, Coarse Location, Contact Info (email, name), Identifiers (User ID, Device ID), Usage (product interaction, advertising), Diagnostics, Other.
  - Not linked: crash and performance data.
- Google Play Data safety [F: S3]:
  - "No data shared with third parties".
  - Collects Location, Personal info "and 4 others".
  - Encrypted in transit; deletion can be requested.
- [I] The Apple label (tracking via purchases and identifiers) and Play's "no data shared" claim are inconsistent in emphasis. A recreation should aim for a stricter, simpler posture.
- [U] Not stated in the privacy policy: whether **journal entries** are encrypted, where they are stored, or whether they are excluded from analytics. Journal data is not explicitly addressed.
- [R] One Nova shop reviewer claims they received a data-breach notification after purchase [W4]. No official statement was found during this research. Unverified; flag for legal/security due diligence only.

---

## 7. Lumenate Nova (related hardware)

| Attribute | Detail | Evidence |
|---|---|---|
| Form factor | Soft, lightweight sleep-mask design with breathable fabric; detachable, hand-washable eye cushion; carry bag | [F] W3, W4, 13452332 |
| Light engine | **4 independently controlled high-precision LEDs**; "spatial light sequencing", higher intensity and consistency than a phone | [F] W3, 13431643 |
| Controls | On-mask buttons: power "O", brightness "+" and "−". Play/pause and brightness from the mask | [F] W3, 13512963 |
| Battery / charge | About 10 h, "around 40 sessions"; USB-C | [F] W3 |
| Connectivity | Bluetooth Low Energy to the Lumenate app only (pair in-app, not in OS settings) | [F] 12918109, 13431714 |
| Audio | **No speakers**; audio plays from the phone; designed to fit with headphones | [F] 13431714 |
| Status LED | Flashing white = searching for a known device; solid blue = paired; alternating blue/white = needs reset | [F] 12918154 |
| Factory reset | Hold + and − for about 3 s while flashing white | [F] 12918154 |
| Firmware | OTA via app (Settings > Lumenate Nova > Update Nova); the app checks on every connect | [F] 13545728 |
| Offline mode | One saved 10-min light-only core sequence | [F] 13512963 |
| Multi-device | Up to **5 Novas per phone**. **Group Session** runs one session on all of them, with each participant going through the safety screening. iOS is GA; Android is Beta | [F] 13431654, 13438091, W4 |
| Guest mode | [R] reviewer describes a "guest mode" with medical advice for trying someone else's Nova | [R] W4 |
| Subscription | Not required for the core sequences plus select free intro sessions; full library needs Premium | [F] 13431688 |
| Availability | Kickstarter, then public launch "January" (2026, inferred from article dates); ships to US/EU/UK/CA/AU/NZ from UK and US (Atlanta) warehouses | [F] 11749402, 13438060; [I] year |
| Known issues | Battery % display bug in the app (fix promised 23/01/26). "Won't turn on" firmware bug from a button combination, OTA fix noted "01/09/26" (UK date format → 1 Sep 2026 [I]). Kickstarter EU customs-fee problems | [F] 13484255, 13483466, 13239169 |
| Certification | "Extensive certification process" covering optical, chemical/material and EMC | [F] W4 |
| Reported pain points | Comfort beyond about 15 min; BLE pairing reliability | [R] W4, S3 |

[U] Not public: LED wavelength and colour temperature, max luminance at the eye, BLE GATT protocol, sequence file format, the mask IMU spec (for motion detection), firmware architecture, and weight.

---

## 8. Safety design (cross-cutting)

Observed controls [F]:
1. 18+ age gate (rationale: 90% of photosensitive epilepsy presents before 18) [9354095].
2. A full exclusion questionnaire with acknowledgement in onboarding, plus a website purchase gate for Nova [W12 §4.3, W1].
3. Medical Risk Info always reachable in Settings.
4. Eyes-closed usage only. The brightness claim: peak about ⅓ of a cloudy day at 7 cm, reduced 90–95% by closed lids; phones must meet IEC 62471 [9354071, 9335105].
5. A delayed light start (1–2 min of audio first).
6. A long-press pause lock, which prevents accidental *pause* (not a safety stop). [I] A recreation should provide an instant, large stop affordance instead.
7. Sudden Motion Detection (see 4.6).
8. Group Session re-screens every participant.
9. Medical Advisory Board of a psychiatrist and a neurologist [9335111].
10. An instruction to stop on any discomfort; no fixed usage cap [9335112].

---

## 9. Feature matrix

Legend:
- **Tier:** Free / Trial+Premium / Nova / n.a.
- **Evidence:** F / R / I / U, as defined at the top.
- **Recreate?** **MVP** = original recreation, MVP scope; **V2** = later; **No** = do not recreate (legal or proprietary) or not applicable.

| Area | Feature | Tier | Platform notes | Evidence | Recreate? |
|---|---|---|---|---|---|
| Account | Mandatory account (email / Apple / Google / Facebook) | All | Apple+HME not usable on Android | F | MVP (email + Apple/Google) |
| Onboarding | Photosensitivity warning + exclusion questionnaire + 18+ confirmation | All | — | F | **MVP (must)** |
| Onboarding | Medical risk info in Settings | All | — | F | **MVP (must)**, written originally with own medical review |
| Onboarding | Setup/how-to content (Discover / Instructional Series / Learn More) | Free | — | F/I | MVP (original how-to) |
| Onboarding | Trial/paywall step | — | RevenueCat | I | V2 (monetisation) |
| Home | For You / Experience home with favourites at top | All | Naming differs iOS/Android | F | MVP |
| Home | Current Journey summary card | Premium | — | F | V2 |
| Library | Explore / Relax / Sleep categorisation; sub-categories e.g. "Relax and De-Stress", "Sleep Better" | Mixed | — | F | MVP (own taxonomy) |
| Library | ~50 curated audio+light sessions, monthly releases | Premium (some free) | — | F | MVP: small original set (5–10) |
| Library | Celebrity/licensed content (Lennon, Pike) | Premium | — | F | **No** (licensed IP) |
| Library | Poetry experiences | Premium | — | F | V2 with public-domain or commissioned texts |
| Session page | Description, duration selector | All | — | F/I | MVP |
| Session page | Favourite (heart) | All? | iOS on page; Android on thumbnail too | F | MVP |
| Session page | Available Offline toggle | Premium | — | F | MVP |
| Session page | AI Guide intention toggle | Premium | Beta | F | V2 |
| Session page | Add to Journey | Premium | — | F | V2 |
| Session page | Start Group Session (Nova) | Nova | iOS menu; Android blue button | F | No (hardware) / V3 |
| Playback | Torch flicker synced to audio timeline | All | — | F | **MVP (core)**; own sequence design + safety caps |
| Playback | Light starts 1–2 min after audio | All | — | F | MVP (configurable lead-in) |
| Playback | Long-press/padlock pause lock | All | — | F | MVP, plus an instant one-tap emergency stop |
| Playback | Haptics toggle | All | iOS only | F | V2 |
| Playback | Audio off | All | iOS only | F | MVP |
| Playback | CYOS: light-only, choose profile (meditative / relaxed / intense), length or endless, own music | Premium | Not in Journeys on iOS | F | **MVP** (low content cost) |
| Playback | Sudden Motion Detection auto-stop | All (not Nova offline) | — | F (exists) / U (how) | **MVP (safety)**, own design using phone IMU |
| Playback | SharePlay | ? | iOS | F (listed) / U | No / V3 |
| Playback | Journeys: queue ≤5 sessions, reorder, remove, seamless transitions, ≤2 h+ | Premium | Not savable | F | V2 (add "save" as a differentiator) |
| Post-session | Personal journal | Premium | — | F (exists) / U (UX) | MVP (local-first, private) |
| Post-session | AI integration / reflection | Premium? | — | F (marketing) / U | V2 |
| AI | Help Me Choose recommender | Premium | OpenAI | F | V2 (start rule-based in MVP) |
| AI | Flag message to company | Premium | — | F | V2 (with the AI feature) |
| Offline | Per-session downloads | Premium | — | F | MVP |
| Account | Cross-platform entitlement, restore purchases | Premium | — | F | V2 |
| Account | Web subscription + magic-login / code redemption | Web | Stripe | F | V2/No |
| Account | In-app deletion | — | **Not present** (manual via support) | F | **MVP (do better)**: self-serve delete + export |
| Support | In-app chat (Intercom) | All | — | F/I | V2 (email link in MVP) |
| Access | Free hardship access | — | Typeform | F | Optional policy |
| Nova | BLE mask, 4 LEDs, OTA, offline sequence, 5-device group | Nova | Android group in Beta | F | No (out of scope for software recreation; keep a device-abstraction seam) |

---

## 10. Gaps and unknowns (exact)

| # | Gap | Why it matters | How to close |
|---|---|---|---|
| G1 | Onboarding screen order, questions asked beyond safety (goals? experience level?), paywall placement | Funnel design | Hands-on install on a test device (trial, then cancel) |
| G2 | Journal UX: auto-prompt after session? fields, mood scales, history, export | Core "integration" loop | Hands-on, or official screenshots inspected visually |
| G3 | Whether AI "integration" exists beyond intention setting | Scope of AI feature | Hands-on (premium/trial) |
| G4 | Exact free-tier session list | Freemium design | Hands-on free account |
| G5 | Monthly/yearly prices per region | Pricing benchmark | Paywall observation; Apple "In-App Purchases" section did not render in fetch |
| G6 | Flicker frequencies, waveform, ramps, intensity per session (only "about 3 Hz for sleep" public) | Proprietary; must be **designed independently** from published FLS literature and safety guidance | Do **not** reverse-engineer (Terms §6.3 prohibit it); design from the literature with medical/photosensitivity review |
| G7 | Sudden Motion Detection logic | Safety feature parity | Design own; not public |
| G8 | Tab bar / stats / streaks / reminders / notifications UX | Retention features | Hands-on |
| G9 | SharePlay behaviour | Social feature | Hands-on |
| G10 | Journal and Guide data storage / encryption specifics | Privacy design | Not in policy; request from vendor or ignore |
| G11 | Torch intensity control (does the app use variable torch level, and does it adapt per device?) | Device fragmentation | Hands-on, or own engineering spike |
| G12 | Nova hardware specs (LED spectrum, luminance, BLE protocol) | Out of scope unless building hardware | — |
| G13 | Accuracy of older support figures (2024 articles) | Stale stats | Prefer 2026 sources |
| G14 | Unverified customer breach claim (W4 review) | Vendor risk only | Search ICO / official notices if relevant |

---

## 11. Recommended original recreation scope

Guiding principles:
- **Clean-room.** Use no Lumenate audio, scripts, music, artwork, session names, light sequences or copy. No decompiling or reverse-engineering: the App Terms §6.3 forbid it.
- Recreate the *category* of experience: phone-torch flicker plus audio, eyes closed. Use original content and independently designed sequences grounded in public FLS literature, reviewed by a qualified medical/photosensitivity adviser.
- **Safety first.** The safety gate is not optional. A torch-strobe app carries real seizure risk, and app-store reviewers will scrutinise it.
- **Privacy-better.** Keep the journal local and on-device by default. Ship no ad-tracking SDKs in the MVP. Offer self-serve account deletion and data export.

### 11.1 MVP (v1)

1. **Safety onboarding:**
   - 18+ gate and photosensitivity warning.
   - Exclusion checklist (original wording, medically reviewed).
   - Explicit acknowledgement.
   - Re-acknowledgement after app updates that change sequences.
   - Medical info permanently in Settings.
2. **Setup tutorial:** dark room, headphones, distance, posture, eyes closed. Include a short, low-intensity "first session" with an extended lead-in.
3. **Library:** 5–10 original sessions across Relax / Sleep / Explore, with 1–2 duration variants each, and a simple category browser.
4. **Session page:** description, duration, favourite, download-for-offline, Play.
5. **Player:**
   - Audio timeline plus a torch flicker scheduler: frequency envelope, ramp-in/out, audio lead-in before light.
   - A large instant **Stop** (single tap or shake). Optional long-press for pause only.
   - Phone-IMU **sudden-motion auto-stop**.
   - Hard global limits on frequency range and duty cycle.
   - Brightness/intensity control where the OS allows, and a session timer.
6. **Light-only "Bring your own audio" mode** (CYOS-equivalent): pick a profile (calm / balanced / intense), length or endless, and mix with other audio.
7. **Journal:** optional post-session prompt (free text plus a simple mood/intensity rating). Stored locally and encrypted at rest. List/history view; export.
8. **Favourites and history** (sessions completed).
9. **Account (optional in MVP)**, or local-only profile. Self-serve delete.

### 11.2 V2

- Queue/playlist of sessions with smooth crossfades (Journeys-equivalent) **with save** (a gap in Lumenate).
- Rule-based "help me choose" recommender (mood + time of day + goal → session). Later, an optional LLM-based guide for intention setting and post-session reflection. Requirements: explicit consent, PII warnings, no server-side chat retention by default, an in-app "report response" flow, and crisis-safe guardrails.
- Subscription and trial (RevenueCat or native StoreKit / Play Billing), restore, cross-platform entitlement.
- Haptics, reminders, streaks (non-coercive).
- In-app support link or chat.

### 11.3 Out of scope / do not recreate

- Licensed celebrity or music content (Lennon, Pike) and any Lumenate-authored sessions or names ("Choose Your Own Soundtrack", "Journeys", "Lumenate Guide", "Nova").
- Hardware mask, BLE firmware and group sessions. Keep a `LightOutput` abstraction (torch now, external device later) so hardware can be added without a rewrite.
- Medical or therapeutic claims. Mirror the "general wellbeing, not a medical device" stance, and get regulatory advice for target markets.

### 11.4 Key engineering risks to spike early

- **Torch timing precision.** iOS `AVCaptureDevice` torch and Android `CameraManager.setTorchMode` / `turnOnTorchWithStrengthLevel` have latency and jitter, and may throttle heat. Measure achievable frequencies and jitter per device class before designing sequences.
- **Background behaviour.** The torch, haptics and audio when the screen locks. Lumenate notes iOS kills haptics on lock.
- **Thermal/battery limits** for 30–120 min sessions.
- **App-store review risk** for strobe content: age rating (Apple lists 18+, Google PEGI 3 — inconsistent) and warnings in the listing.
