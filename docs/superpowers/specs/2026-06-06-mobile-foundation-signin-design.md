# Seret — Shared Presentation Layer + iOS/iPadOS Foundation & Sign-In (Plan 8a)

**Status:** Draft for review
**Date:** 2026-06-06
**Owner:** Shahar Solomons
**Scope of this document:** Plan **8a** — the first slice of the iPhone/iPad app. Extracts a shared presentation layer (`DebridUI`) out of the tvOS app (a behaviour-preserving refactor), then stands up the universal **`SeretMobile`** target: the XcodeGen wiring, the adaptive shell, and a touch **sign-in** screen wired to the finished `DebridCore` brain + the proven sign-in machine. Library/Detail (8b) and the `MobileVLCKit` player (8c) are separate slices, sketched in §3.
**Parent spec:** [`2026-06-02-seret-design.md`](2026-06-02-seret-design.md) (§4 architecture, §6 the apps). **Sibling:** [`2026-06-03-tvos-app-foundation-signin-design.md`](2026-06-03-tvos-app-foundation-signin-design.md) — the tvOS analogue this mirrors.

## 1. Summary

`DebridCore` (Plans 1–6, 130 tests) and the full **`SeretTV`** tvOS app (Plans 7a–7c + the VLCKit 4.x player) are merged to `main`. Plan 8 puts the second native UI — a **universal iPhone/iPad app** — on the same brain.

Per the brainstorm, Plan 8 is built as **three vertical slices**, each its own spec → plan → subagent-driven build, exactly like Plan 7.

**This slice (8a)** does two things:

1. **Extract `DebridUI`** — a shared SwiftUI **presentation layer** (view-models, models, provider seams, utilities, and the genuinely cross-platform SwiftUI components) pulled out of `Apps/SeretTV/` into `Shared/DebridUI`, which both apps depend on. This is a **behaviour-preserving refactor**: the tvOS app keeps working and every existing test stays green. It lands first, as its own reviewable step.
2. **Stand up `SeretMobile`** — a universal (iPhone + iPad) app target that launches in both simulators, runs the **touch sign-in** flow (device-code default + paste-token fallback) to a real RD auth round-trip → Keychain, and lands on an **adaptive Movies/Shows/Settings shell** (empty content stubs; library lands in 8b). Sign Out returns to sign-in.

**The owner chose "promote everything to shared now"** (vs. duplicating per app, or sharing only `DebridCore`): the cleanest end-state, accepting an up-front refactor. 8a does the full extraction so 8b/8c become thin iOS **View** layers over already-shared logic.

**The one architectural rule holds:** no networking/parsing/RD/TMDB/subtitle logic in any app target — it all lives in `DebridCore`. `DebridUI` is presentation (state + components); the app targets are platform Views + thin glue.

## 2. Decisions locked in the brainstorm (drive 8a–8c)

| Decision | Choice | Slice it bites |
|---|---|---|
| iPad coverage | **Fully universal now** — every screen adaptive (iPhone + iPad designed together) | 8a shell, 8b, 8c |
| Top-level nav | **Movies / Shows split** — iPhone tab bar `[Movies · Shows · Settings]`; iPad `NavigationSplitView` sidebar `[Movies, Shows, Settings]` | 8a |
| Visual language | **Monochrome, poster-forward** (mirror tvOS): dark, titles as plain text below posters, no accent colour — artwork carries the colour | 8a tokens, 8b |
| Grid density | iPhone portrait **3 columns**; iPad **~5 columns** (adaptive `LazyVGrid`) | 8b |
| Sign-in | **Device-code default + paste-token fallback** (mirror tvOS); touch-adapted — **no QR** (same device), an "Open Real-Debrid" button instead | 8a |
| Player gestures | **Balanced** — tap toggles controls, double-tap sides ±10s, drag to scrub (no brightness/volume swipes in v1) | 8c |
| AirPlay / PiP | **Deferred** — hard with VLCKit (not AVPlayer); big-screen is served by the `SeretTV` app | 8c+ |

## 3. Plan 8 at a glance (only 8a is specced here)

| Slice | Delivers | New external dep | Verified by |
|---|---|---|---|
| **8a (this spec)** | `DebridUI` extraction (tvOS stays green) + universal `SeretMobile` foundation + **touch sign-in** → Keychain → adaptive shell | none (RD public client / token; keys already present) | iPhone **and** iPad simulator screenshots + real RD auth round-trip + tvOS regression green |
| **8b** | Library browse — Movies · Shows · Detail · Show/episodes, adaptive grid, wired to the shared `LibraryStore`/`DetailStore` | none (TMDB key already present) | iPhone + iPad sim with a real RD library + TMDB art |
| **8c** | Player — `MobileVLCKit` engine on the unified `VLCKit.xcframework`, touch transport + Balanced gestures, track menus, on-demand subtitles, resume/save | `MobileVLCKit` slice of the already-vendored unified framework | playback on a real iPhone/iPad |

8a has **zero external blockers** — the extraction is internal and the auth path needs no secret — so it can start immediately.

## 4. Part 1 — the `DebridUI` extraction (behaviour-preserving)

### 4.1 What `DebridUI` is

A local Swift package, **`Shared/DebridUI`**, depending on `DebridCore`. It is the **shared presentation layer**:

- **View-models / app state** — `@MainActor @Observable` types that drive Views: `AppSession`, `SignInModel`, `AuthFlow` (seam), `SettingsModel`, `LibraryStore`, `DetailStore`, `PlayerModel`.
- **Provider seams** — `LibraryProviding`, `MediaDetailsProviding`, `WatchProgressProviding` (protocol seams over `DebridCore` for testable view-models).
- **Models** — `PlaybackRequest` and similar UI-facing value types.
- **Cross-platform SwiftUI components & tokens** — only components that compile for **iOS + tvOS (+ macOS, for `swift test`)**: e.g. `QualityChips`, `BackdropBackground`, `Timecode`, the design tokens (palette/spacing/type scale), and a poster **image** view. Shared **design tokens** are introduced here (formerly implicit in tvOS).
- **Utilities** — `OpenSubtitlesAccount`, `Secrets` accessor, `QRCode` (generic; tvOS uses it, iOS doesn't). *(Player-only, UIKit/VLCKit-bound helpers like `ThumbnailProvider` are **not** here — they stay with the player and are reconsidered in 8c, §9.)*

> **Naming note:** the parent spec reserved `Shared/DebridUI` for "design tokens + small components." 8a **broadens** it to the full shared presentation layer (view-models included). Alternative name `SeretKit` — flagged for the spec review; default is `DebridUI`.

### 4.2 The promotion rule (what stays per-app)

> A type promotes to `DebridUI` **iff** it is platform-agnostic — it compiles for iOS **and** tvOS (and macOS for tests) and embodies no platform idiom. Anything that uses a **tvOS-only API** (`.buttonStyle(.card)`, the focus engine, Siri-remote input) or a **platform-specific layout** stays in its app target.

Consequently, these **stay in `Apps/SeretTV/`** (and get iOS counterparts in 8a–8c, not here):

- **Platform Views / screens:** `RootView`, `LibraryShell`, `SignInView`, `LibraryScreen`, `DetailView`/`MovieDetailView`/`ShowDetailView`, `SettingsView`, `EpisodeRow`, `PosterGrid`, `PosterCard` (uses `.card`) — tvOS layouts/focus.
- **The whole player View + engine:** `PlayerView`, `PlayerOverlays`, `ScrubPad`, `TrackMenuPanel`, `VLCKitVideoPlayerEngine`, `VLCVideoView` — Siri-remote UI + UIKit/VLCKit. (Engine sharing is reconsidered in 8c — see §9.)
- `SeretTVApp.swift` (`@main`), `Resources/Assets.xcassets`.

`PosterCard` splits: the **poster image** (AsyncImage + `TMDBClient.imageURL`, the no-art fallback) promotes to a shared `PosterImage`; the **interaction wrapper** (tvOS `.card` lift vs. iOS tap) stays per-app. Finalised in 8b.

### 4.3 Tests move with their subjects

The tvOS app-hosted tests that exercise **shared logic** move into `Shared/DebridUI/Tests/DebridUITests/` and run host-free under **`swift test`** (a strict upgrade — no app host, no simulator):

- `SignInModelTests`, `SettingsModelTests`, `LibraryStoreTests`, `DetailStoreTests`, `PlayerModelTests`, and the `Fakes.swift` helpers → `DebridUITests`.
- `SeretTVTests` keeps only **tvOS-View smoke** (`SmokeTests` analogue).

`DebridUI`'s `Package.swift` sets the same deployment floor as `DebridCore` (iOS/tvOS 18, **macOS 14**) so these suites run on the dev Mac. (View-models import `Observation` + `DebridCore`, no UIKit — they compile for macOS. The UIKit/VLCKit engine never enters `DebridUI`.)

### 4.4 `project.yml` changes

- Add the package: `packages: { DebridCore: { path: Packages/DebridCore }, DebridUI: { path: Shared/DebridUI } }`.
- `SeretTV` gains `- package: DebridUI` and **drops** the now-moved sources (its `sources: [Apps/SeretTV]` shrinks naturally as files relocate).
- `DebridUI` depends on `DebridCore` (in its `Package.swift`).

### 4.5 Refactor safety

Behaviour-preserving, landed in dependency order, **full tvOS suite + `swift test` green after each move**, tvOS app builds throughout. The merged 7c player (owner-confirmed on the Apple TV) is the known-good baseline this must not regress. This part lands as its own commits/PR before any iOS code.

## 5. Part 2 — the `SeretMobile` app

### 5.1 XcodeGen target (mirrors `SeretTV`, universal)

```yaml
SeretMobile:
  type: application
  platform: iOS
  deploymentTarget: "18.0"
  sources: [Apps/SeretMobile]
  dependencies:
    - package: DebridCore
    - package: DebridUI
  settings:
    base:
      PRODUCT_NAME: Seret
      PRODUCT_BUNDLE_IDENTIFIER: com.solomons.seret.mobile
      SWIFT_VERSION: "6.0"
      SWIFT_STRICT_CONCURRENCY: complete
      TARGETED_DEVICE_FAMILY: "1,2"        # iPhone + iPad (universal)
      CODE_SIGN_STYLE: Automatic
      DEVELOPMENT_TEAM: ML9HDN3QZS
      INFOPLIST_KEY_UILaunchScreen_Generation: YES
      # orientations: iPhone portrait + landscape, iPad all — player forces landscape in 8c
  configFiles: { Debug: Secrets.xcconfig, Release: Secrets.xcconfig }
  info: { properties: { TMDBAPIKey: "$(TMDB_API_KEY)", OpenSubtitlesAPIKey: "$(OPENSUBTITLES_API_KEY)" } }
  scheme: { testTargets: [SeretMobileTests] }
```
- **VLCKit is *not* linked in 8a** — the unified `VLCKit.xcframework` (already vendored, supports iOS) is embedded into `SeretMobile` in **8c**, the same `embed: true, codeSign: true` pattern as `SeretTV`. `LD_RUNPATH_SEARCH_PATHS` includes `@executable_path/Frameworks` now, ready.
- **Device signing** mirrors tvOS: simulator builds run under automatic signing; a real device needs the team carrying an Apple Development cert (`7NY9RRS56S`), set in the Xcode GUI. (`ML9HDN3QZS` has only Developer-ID.)
- `SeretMobileTests`: app-hosted `bundle.unit-test`, `@testable import` the app, `TEST_HOST` on the `Seret.app` binary — same shape as `SeretTVTests`.

### 5.2 App entry + adaptive shell

`SeretMobileApp.swift` (`@main`) mirrors `SeretTVApp`: builds the shared `AppSession(realDebrid: RealDebridSession(store: KeychainTokenStore()))`, guards on `XCTestConfigurationFilePath` (renders `Color.clear` under test so no network fires), hosts `RootView` via `.environment(session)`.

```
Apps/SeretMobile/
  SeretMobileApp.swift          # @main; shared AppSession; XCTest guard
  Shell/
    RootView.swift              # observes AppSession.state → SignInView | MainShell
    MainShell.swift             # size-class adaptive: TabView (compact) | NavigationSplitView (regular)
    SectionStub.swift           # 8a empty state per tab ("Library lands in 8b"); replaced in 8b
    SettingsView.swift          # iOS Form: Account (Sign Out) · Subtitles (OpenSubtitles login) · About
  Auth/
    SignInView.swift            # touch device-code + token entry (uses shared SignInModel)
    SafariSheet.swift           # SFSafariViewController wrapper for real-debrid.com/device
  Resources/
    Assets.xcassets             # iOS App Icon + accent (system)
```

`MainShell` reads `@Environment(\.horizontalSizeClass)`:
- **compact (iPhone):** `TabView` with three tabs — Movies, Shows, Settings — each a `NavigationStack` (drill-down lands in 8b).
- **regular (iPad):** `NavigationSplitView` — sidebar `[Movies, Shows, Settings]` + a detail column. Same three destinations.

In 8a, Movies/Shows render `SectionStub`; **Settings is real**.

### 5.3 Touch `SignInView`

Drives the **shared `SignInModel`** (the same phase machine tvOS uses) — no new auth logic. Phases → touch UI:

- `idle`/`requestingCode` → `ProgressView("Preparing sign-in…")`.
- `awaitingAuthorization(code)` → the `user_code` (large monospaced) + **"Open Real-Debrid"** button opening `code.verificationURL` in an `SFSafariViewController` sheet (no QR — same device) + a "Copy code" affordance + "Waiting for authorization…". A secondary **"Use a Real-Debrid token instead"** button.
- `validatingToken` → `ProgressView`.
- `failed(msg)` → message + **Try Again** + token fallback.
- **Token entry** (sheet): a `TextField` (`.autocorrectionDisabled`, `.textInputAutocapitalization(.never)`, paste-friendly) → `SignInModel.signInWithToken` → `validateToken` → `establishStaticToken`. The durable path past the device-code throttle.

### 5.4 Settings (iOS)

An iOS `Form` mirroring `SettingsModel`: **Account** (signed-in indicator + Sign Out → `AppSession` clears Keychain → back to sign-in), **Subtitles** (OpenSubtitles account login, needed in 8c; reuses `SettingsModel`/`OpenSubtitlesAccount`), **About** (version).

## 6. Key flow — sign-in (touch)

```
launch → AppSession.state
  ├─ signedIn (Keychain token) ─────────────→ MainShell (Movies/Shows/Settings)
  └─ signedOut → SignInView
        ├─ device-code:  show user_code → [Open Real-Debrid] → SFSafari → authorize
        │                 → poll → tokens → Keychain → signedIn
        └─ token:        paste token → validateToken → establishStaticToken
                          → Keychain → signedIn
  Sign Out (Settings) → AppSession clears Keychain → signedOut → SignInView
```

## 7. Error handling & edge cases

- **Device-code throttle (RD 403):** the known failure mode — surfaced as a clear message with **Try Again** and the **token** path prominent (token bypasses it). Mirrors tvOS.
- **No network:** sign-in shows a retryable error; shell (when signed in) shows the cached state — full library handling is 8b.
- **Token invalid:** `validateToken` failure → inline message in the token sheet; stay on the sheet.
- **Rotation / multitasking:** browse supports portrait + landscape; iPad split view handled by `NavigationSplitView`; Slide Over/compact-width on iPad falls back to the compact (`TabView`) layout via the size class — one code path.
- **Relaunch:** valid Keychain token → straight to the shell (no sign-in flash); `Color.clear` under test.

## 8. Testing & verification

- **`swift test` (dev Mac):** `DebridCore` (130) **+ new `DebridUI` suites** (the migrated view-model tests) green, zero warnings — host-free.
- **tvOS regression:** `SeretTV` builds; `SeretTVTests` (View-smoke) green; app runs unchanged (the refactor changed no behaviour).
- **iOS build:** `xcodegen generate` + `xcodebuild` for `SeretMobile` succeed, zero warnings.
- **iPhone simulator:** sign-in renders a real device code; **token path** authorizes; lands on the **tab-bar** shell; Sign Out returns — screenshots.
- **iPad simulator:** same, landing on the **split-view** shell — screenshots (proves the adaptive shell on both idioms).
- **Owner-pending (on-device):** real iPhone/iPad sign-in + shell, same as the tvOS DoD (the sim can't sign device builds).

## 9. Definition of Done — 8a

- [ ] `Shared/DebridUI` exists; all shareable view-models/models/seams/utilities + cross-platform components moved out of `SeretTV` per the promotion rule (§4.2); no tvOS-only API in the cross-platform module.
- [ ] `SeretTV` builds + runs unchanged; **all prior tvOS tests green** (shared-logic suites now under `swift test` in `DebridUI`, View-smoke in `SeretTVTests`).
- [ ] `swift test` green for `DebridCore` **and** `DebridUI`; zero warnings.
- [ ] `SeretMobile` builds; launches on **iPhone sim and iPad sim**; sign-in (device-code or token) → Movies/Shows/Settings shell; **Sign Out** → sign-in; tab bar (iPhone) / split view (iPad) confirmed by screenshots.
- [ ] The one architectural rule holds: no RD/TMDB/parse/subtitle logic in `SeretMobile`/`SeretTV`/`DebridUI` Views beyond calling `DebridCore`.
- [ ] `Secrets.example.xcconfig` unchanged-and-valid; `Seret.xcodeproj`, `Secrets.xcconfig`, `Frameworks/` gitignored.
- [ ] Owner-pending item recorded: on-device iPhone/iPad sign-in + shell.

## 10. Open questions / deferred

- **Shared module name** — `DebridUI` (broadened) vs. `SeretKit`. Confirm in review.
- **Player engine sharing (8c):** the unified VLCKit 4.x makes one `VLCKitVideoPlayerEngine` for iOS + tvOS plausible — promote to a `Shared/SeretPlayer` (UIKit, iOS+tvOS, no macOS) vs. keep per-app. Decided in 8c.
- **`PosterCard` split** — shared `PosterImage` + per-platform interaction; finalised in 8b.
- **Brand accent** — staying monochrome (mirrors tvOS); revisit if a signature colour is wanted (would retrofit tvOS too).
- **AirPlay / PiP** — deferred (VLCKit limitation); big-screen via `SeretTV`. Possible in Stage 3 behind an AVPlayer fast-path for hardware-decodable files.
- **Background audio / Now Playing** — nice-to-have, VLCKit-specific work; deferred past 8c.
