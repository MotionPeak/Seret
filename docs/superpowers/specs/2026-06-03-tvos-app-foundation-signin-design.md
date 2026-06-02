# Seret tvOS App — Foundation & Device-Code Sign-In (Plan 7a)

**Status:** Draft for review
**Date:** 2026-06-03
**Owner:** Shahar Solomons
**Scope of this document:** Plan **7a** — the first native UI. Stands up the `SeretTV` (tvOS) app, the XcodeGen project, the VLCKit integration *approach*, the Secrets mechanism, and the **device-code sign-in** screen wired to the finished `DebridCore` auth brain. Browse (7b) and playback (7c) are separate slices, sketched in §2 only.
**Parent spec:** [`2026-06-02-seret-design.md`](2026-06-02-seret-design.md) (§4 architecture, §5.2 RealDebrid, §6 screens, §10 tooling).

---

## 1. Summary

`DebridCore` is feature-complete (Plans 1–6, 110 tests, merged). Plan 7 puts the first native **tvOS** UI on it. Per the brainstorm, Plan 7 is built as **three vertical slices**, each its own spec → plan → subagent-driven build, exactly like Plan 6.

**This slice (7a)** delivers a `SeretTV` app that:
- launches in the tvOS simulator,
- shows the **device-code sign-in** screen (big `user_code` + `real-debrid.com/device` + QR),
- completes a **real Real-Debrid auth round-trip**, persisting tokens to the **Keychain**,
- lands on a placeholder signed-in **Home stub**, and
- supports **Sign Out** back to sign-in.

It deliberately stops there. Its larger job is to stand up the **foundation every later slice builds on**: the XcodeGen project, the `DebridCore` linkage, the Secrets mechanism, the app shell + session wiring, and a *decided* VLCKit integration approach.

**The one architectural rule holds:** no networking/parsing/RD/TMDB/subtitle logic in the app target — it all already lives in `DebridCore`. 7a is UI + thin glue only.

---

## 2. Plan 7 at a glance (context — only 7a is specced here)

| Slice | Delivers | New external dep | Verified by |
|---|---|---|---|
| **7a (this spec)** | Project foundation + **device-code sign-in** → Keychain → Home stub | none (RD public client, no secret) | tvOS simulator screenshot + real RD auth round-trip |
| **7b** | Library browse — Home (Continue Watching / Recently Added) · Movies · Shows · Detail · Show/episodes, wired to `LibraryService` | **TMDB API key** | simulator + real RD library with TMDB art |
| **7c** | Player — VLCKit `VideoPlayerEngine` impl, controls, track menus, on-demand subtitles, resume/save | **OpenSubtitles key**, **TVVLCKit** integrated here | playback in simulator |

Slices sequence so each new key-dependency is introduced only when first needed; 7a has **zero external blockers** and can start immediately.

---

## 3. Scope of 7a

**In:**
- `project.yml` (XcodeGen) generating `Seret.xcodeproj` (gitignored), with a `SeretTV` tvOS target linking the local `DebridCore` package.
- `Secrets.xcconfig` mechanism (gitignored) + committed `Secrets.example.xcconfig` template. Empty of values for 7a (RD needs no secret); plumbing proven for 7b/7c keys.
- VLCKit integration **approach decided + scaffolded** (`Frameworks/`, `Scripts/fetch-frameworks.sh`, runpath) — but **not integrated** (no VLCKit code until 7c).
- App shell: `@main` app, `RootView` session routing, a Home **stub**, a Settings screen with **Sign Out**.
- The **device-code sign-in** screen + the model that drives the RD device-code flow against `DebridCore`.
- One unit test for the sign-in model's state machine; tvOS-simulator verification of the screen.

**Out (later slices / stages):**
- Any library, browse, detail, or player UI (7b/7c). Home is a stub.
- Actually linking/using VLCKit (7c).
- iPhone/iPad target (`SeretMobile`) — Plan 8.
- `DebridUI` shared-tokens module — introduced only when a second app exists (Plan 8); not now.

---

## 4. Project foundation

### 4.1 Repo layout additions
```
project.yml                       # XcodeGen → Seret.xcodeproj (gitignored)
Secrets.example.xcconfig          # committed template (key names, empty values)
Secrets.xcconfig                  # gitignored (real values; empty for 7a)
Scripts/fetch-frameworks.sh       # pinned TVVLCKit.xcframework download (used in 7c)
Frameworks/                       # gitignored; populated by the script in 7c
.swiftlint.yml  .swiftformat       # committed configs
Apps/SeretTV/
  SeretTVApp.swift                # @main; builds the shared RealDebridSession; hosts RootView
  Shell/
    RootView.swift                # observes SessionState → SignIn | Home
    HomeStubView.swift            # "Signed in ✓ — library lands in 7b" + Settings entry
    SettingsView.swift            # account placeholder + Sign Out
  Auth/
    SignInView.swift              # device-code screen (code + URL + QR + status)
    SignInModel.swift             # @MainActor @Observable; drives the flow
    AuthFlow.swift                # protocol seam over RealDebridAuthClient + session (testability)
    QRCode.swift                  # CIQRCodeGenerator → Image helper
  Resources/
    Assets.xcassets               # App Icon + Top Shelf (tvOS-required)
```
`.gitignore` gains: `Seret.xcodeproj/`, `Secrets.xcconfig`, `Frameworks/`, `*.xcuserstate`.

### 4.2 XcodeGen `project.yml` (mirrors the Nikud setup)
- `name: Seret`; `options.bundleIdPrefix: com.solomons.seret`; `createIntermediateGroups: true`.
- `packages: DebridCore: { path: Packages/DebridCore }`.
- Target **`SeretTV`**: `type: application`, `platform: tvOS`, `deploymentTarget: "18.0"`, `sources: [Apps/SeretTV]`, `dependencies: [{ package: DebridCore }]`.
- Settings (base): `PRODUCT_BUNDLE_IDENTIFIER: com.solomons.seret.tv`, `SWIFT_VERSION: "6.0"`, `SWIFT_STRICT_CONCURRENCY: complete`, `GENERATE_INFOPLIST_FILE: YES` (+ `INFOPLIST_KEY_*` for app name / Top Shelf), `CODE_SIGN_STYLE: Automatic`, `DEVELOPMENT_TEAM: ML9HDN3QZS`, `TARGETED_DEVICE_FAMILY: 3` (tvOS), `ASSETCATALOG_COMPILER_APPICON_NAME: App Icon & Top Shelf Image`, and `LD_RUNPATH_SEARCH_PATHS: ["$(inherited)", "@executable_path/Frameworks"]` (ready for the 7c embedded framework).
- `configFiles: { Debug: Secrets.xcconfig, Release: Secrets.xcconfig }` so TMDB/OpenSubtitles keys (7b/7c) arrive as build settings → Info.plist → readable at runtime. (For 7a the file exists but carries no values.)
- `Frameworks/` and the VLCKit `dependencies:` entry are **added in 7c**, not now.

### 4.3 VLCKit integration — Risk R2 resolved (decided now, integrated in 7c)
**Decision:** vendor the official **`TVVLCKit.xcframework` (stable 3.x)** into a gitignored `Frameworks/`, fetched by a **pinned** `Scripts/fetch-frameworks.sh` from `download.videolan.org`, and embed it via XcodeGen:
```yaml
dependencies:
  - framework: Frameworks/TVVLCKit.xcframework
    embed: true
    codeSign: true
```
This is **the exact pattern Nikud uses for `llama.xcframework`** (`embed: true`, `codeSign: true`, `@executable_path/Frameworks` runpath).

**Why this over the alternatives:**
- **CocoaPods** (`pod 'TVVLCKit'`) is the official *stable* channel — but its podspec only downloads the same official `.xcframework`. Adopting Pods adds a second package manager + an `.xcworkspace` that fights the clean XcodeGen flow. Rejected.
- **Community SPM wrappers** (`virtualox/vlckit-spm` = VLCKit **4.0-alpha**; `tylerjonesio/vlckit-spm` = 3.5.1) add a third-party maintenance dependency on the critical playback path, and 4.0 is pre-release. Rejected for a "built to last" foundation.
- **Vendored official XCFramework** uses the first-party stable binary, no extra tooling, mirrors the owner's existing Nikud setup. **Chosen.**

**Deviation from Nikud (justified):** Nikud commits its `.xcframework`; Seret **fetches** it via a pinned script instead, because Seret is a **public** repo and TVVLCKit is large. The script pins a specific stable version (and ideally a checksum) so builds are reproducible without bloating git.

**Version:** stable **3.x** (`VLCMediaPlayer` API). VLCKit 4.0 is alpha; revisit when it ships stable.

**Timing:** the embedding + a one-line link-smoke is the **first task of 7c**. The Nikud precedent makes this low-risk, so 7a stays lean and reaches a green, screenshot-verified sign-in fastest. (Can be pulled forward into 7a if we want R2 retired earlier — owner's call; default is 7c.)

---

## 5. Sign-in feature design

### 5.1 The `DebridCore` API this consumes (already built + tested)
- `RealDebridAuthClient.startDeviceCode()` → `RDDeviceCode { deviceCode, userCode, verificationURL, interval, expiresIn }`.
- `pollCredentials(deviceCode:…)` → `RDDeviceCredentials { clientID, clientSecret }` (resolves once the user authorizes; encapsulates the poll cadence).
- `requestToken(deviceCode:…)` → `RDToken { accessToken, refreshToken, expiresIn, tokenType }`.
- `RealDebridSession` (`actor`, conforms `AccessTokenProviding`): `establish(token:deviceCredentials:)` persists via `KeychainTokenStore` (service `com.solomons.seret.realdebrid`); `validAccessToken()` returns a fresh token (refreshing as needed) or throws; `signOut()` clears.

(Exact parameter lists are confirmed against the source at plan time; the shapes above are from the public surface.)

### 5.2 `AuthFlow` seam (for testability)
A small protocol the model depends on, so the model's state transitions are unit-testable without the network:
```swift
@MainActor protocol AuthFlow {
    func begin() async throws -> RDDeviceCode                 // startDeviceCode
    func awaitSignIn(_ code: RDDeviceCode) async throws       // poll → requestToken → session.establish
}
```
`LiveAuthFlow` wraps `RealDebridAuthClient` + the shared `RealDebridSession`. A `FakeAuthFlow` in tests returns a canned `RDDeviceCode` then succeeds/fails on demand.

### 5.3 `SignInModel` (`@MainActor @Observable`)
State: `enum Phase { case idle, requestingCode, awaitingAuthorization(RDDeviceCode), establishing, signedIn, failed(String) }`.
Flow: `idle → requestingCode` (`begin()`) → `awaitingAuthorization(code)` (view shows `userCode` + URL + QR) → `awaitSignIn(code)` resolves → `establishing → signedIn` (flips the app's `SessionState`). Errors → `failed(message)` with a **Try again** action. Honors `expiresIn` (offer "get a new code" on timeout). The long-running wait is a single `await` (cadence lives in `DebridCore`), keeping the model trivial and cancellable on view disappearance.

### 5.4 `SignInView` (tvOS)
Centered layout: short instruction ("On your phone or computer, go to **real-debrid.com/device** and enter:"), the **`userCode`** rendered large, a **QR** to `verificationURL` (CoreImage `CIQRCodeGenerator`, scaled up), and a status line ("Waiting for authorization…" / error). Minimal focusable controls (a **Try again** button on failure/timeout). Auto-advances on success — no button press to continue.

### 5.5 App entry + session
`SeretTVApp` builds **one** `RealDebridSession(auth: .init(), tokens: KeychainTokenStore())` and injects it (environment) — it's the shared `AccessTokenProviding` that 7b's `TorrentsClient` and 7c's playback will consume. `RootView` resolves `SessionState (.unknown → .signedIn / .signedOut)` at launch from persisted credentials (validating/refreshing lazily; offline-with-stored-creds still counts as signed-in and lets later calls retry), then shows `HomeStubView` or `SignInView`. `SettingsView` → **Sign Out** calls `session.signOut()` and flips back to `.signedOut`.

---

## 6. Key flow — sign-in
```
launch → RootView resolves SessionState
   ├─ signedIn  → HomeStubView
   └─ signedOut → SignInView
SignInView → model.begin() → startDeviceCode()
   → show userCode + QR + verificationURL
   → awaitSignIn(): pollCredentials → requestToken → session.establish (Keychain)
   → SessionState = .signedIn → HomeStubView
Settings → Sign Out → session.signOut() → SessionState = .signedOut → SignInView
```

---

## 7. Error handling & edge cases
- **Auth timeout** (`expiresIn` elapsed before authorize) → `failed` with **Get a new code** (restarts at `begin()`).
- **Network failure during sign-in** → `failed` with **Try again**; never crash, never leave a half-state.
- **Cancellation** (view disappears) → the awaiting task is cancelled; no dangling poll.
- **Already signed in on relaunch** → skip sign-in via persisted credentials; a failed silent refresh routes back to `SignInView`.
- **tvOS Keychain volatility** — tvOS does not guarantee long-term Keychain persistence (the system can evict items). In the simulator it persists across relaunch (covered by the DoD). On real hardware, eviction simply means an occasional re-sign-in; the device-code flow is cheap, so this degrades gracefully (Stage 3 CloudKit can harden it later). Not a 7a blocker.
- **Never log** the RD token, refresh token, or device `client_secret`.

---

## 8. Testing & verification
- **Unit (in the app target):** one `SignInModel` test driving the phase machine against `FakeAuthFlow` — happy path (`idle → … → signedIn`) and a failure path (`→ failed`, then retry). Auth/network logic itself is already covered in `DebridCore`; we don't re-test it here.
- **`DebridCore` suite stays green** (`swift test --package-path Packages/DebridCore`) — unchanged by 7a.
- **Zero warnings:** `xcodebuild … build 2>&1 | grep -i warning` prints nothing.
- **Simulator (source of truth):**
  ```bash
  xcodegen generate
  xcodebuild -scheme SeretTV \
    -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build
  ```
  Launch in the Simulator → **screenshot** the sign-in screen showing a real `user_code` + QR → complete a **real** device-code authorization against the owner's RD account → **screenshot** the signed-in Home stub. **No "done" claim without these screenshots** (owner rule).

---

## 9. Definition of Done — 7a
- [ ] `xcodegen generate` + `xcodebuild` for `SeretTV` succeed, **zero warnings**.
- [ ] App launches in the tvOS simulator; **sign-in screen renders a real device code + QR** (screenshot).
- [ ] A **real RD device-code round-trip** authorizes; tokens persist to Keychain; relaunch stays signed-in; **Sign Out** returns to sign-in (screenshots).
- [ ] `DebridCore` tests still green; **no networking/RD/parsing logic in the app target** (the one architectural rule).
- [ ] `Secrets.example.xcconfig` committed; real `Secrets.xcconfig`, `Frameworks/`, and `Seret.xcodeproj` gitignored.
- [ ] VLCKit approach recorded (this spec) and scaffolded (`Scripts/fetch-frameworks.sh` present, runpath set) — integration itself deferred to 7c.

---

## 10. Open questions / deferred
- **SwiftLint/SwiftFormat build-phase enforcement** — configs committed in 7a; wiring them as a run-script build phase can land in 7a or 7b (low risk; flagged so it isn't forgotten).
- **Top Shelf / App Icon art** — tvOS requires an App Icon (layered) + Top Shelf image to build/run. 7a ships placeholder art; real art is a polish task.
- **`RealDebridSession` launch-state API** — whether RootView routes via `validAccessToken()` (network) or a cheaper "have stored credentials?" read is settled at plan time against the session's actual surface.
- **Exact device-code method signatures** — confirmed against `RealDebridAuthClient`/`RealDebridSession` source when writing the plan.
