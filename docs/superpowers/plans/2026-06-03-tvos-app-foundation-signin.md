# Seret tvOS App — Foundation & Device-Code Sign-In (Plan 7a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the `SeretTV` tvOS app on the finished `DebridCore` brain and ship a real device-code sign-in → Keychain → signed-in Home stub, with Sign Out.

**Architecture:** XcodeGen generates `Seret.xcodeproj` (gitignored) with a `SeretTV` tvOS target linking the local `DebridCore` package. The app is **UI + thin glue only** — all RD/networking logic stays in `DebridCore`. A `SignInModel` (`@MainActor @Observable`) drives the device-code flow through an `AuthFlow` seam; `AppSession` owns the shared `RealDebridSession` and routes `RootView` between sign-in and Home.

**Tech Stack:** Swift 6 (strict concurrency complete), SwiftUI (tvOS 18), XcodeGen, Swift Testing, CoreImage (QR), the local `DebridCore` Swift package.

**Source spec:** [`docs/superpowers/specs/2026-06-03-tvos-app-foundation-signin-design.md`](../specs/2026-06-03-tvos-app-foundation-signin-design.md)

---

## Plan-time decisions (resolved against the live source — read before starting)

Two spec open questions (§195–199) were resolved against the actual `DebridCore` source:

1. **The poll cadence does NOT live in `DebridCore` yet.** `RealDebridAuthClient.pollCredentials(deviceCode:)` is a **single attempt** that returns `nil` while pending — *not* a loop. The spec (§5.3) assumed "cadence lives in DebridCore". **Decision (owner-approved): add a small, tested `awaitCredentials(for:)` poll loop to `DebridCore`** (Task 1). This honors the one architectural rule (no RD-flow logic in the app target) and the spec's design intent, and gets real `MockURLProtocol` coverage. It is the only change to the brain.

2. **Launch routing (spec §198) uses `validAccessToken()` with error discrimination — no brain change.** `RealDebridSession.validAccessToken()` throws `RealDebridSessionError.notSignedIn` **only** when there are zero stored credentials. So at launch: success → `signedIn`; `.notSignedIn` → `signedOut`; `HTTPError.status` (server rejected the refresh token, spec §165) → `signedOut`; any other/transport error (offline with stored creds, spec §143) → `signedIn` (optimistic, later calls retry). This is faithful to the spec with no new session API.

**Confirmed signatures (do not guess — these are exact):**
- `RealDebridAuthClient.init(http: HTTPClient = .init())`; `static let openSourceClientID = "X245A4XAIBGVM"`.
- `func startDeviceCode(clientID:String = openSourceClientID) async throws -> RDDeviceCode`
- `func pollCredentials(deviceCode:String, clientID:String = …) async throws -> RDDeviceCredentials?` (nil while pending; throws on denied/expired)
- `func requestToken(deviceCode:String, credentials:RDDeviceCredentials) async throws -> RDToken`
- `RDDeviceCode { deviceCode, userCode, interval, expiresIn, verificationURL }` (Decodable, **no public init** — package tests use the internal memberwise init via `@testable`; the app test decodes from JSON)
- `RDDeviceCredentials { clientID, clientSecret }` (Codable, public init)
- `actor RealDebridSession`: `init(auth: = .init(), store: TokenStore, …)`; `func establish(token:RDToken, deviceCredentials:RDDeviceCredentials) throws`; `func validAccessToken() async throws -> String`; `func signOut() throws`. Conforms `AccessTokenProviding`.
- `KeychainTokenStore(service: "com.solomons.seret.realdebrid")` is the default service.
- `HTTPError`: `.transport(String)`, `.status(code:Int, body:String)`, `.decoding(String)` (public, Equatable).

**Branch:** continue on the existing `feat/tvos-foundation-signin` (already checked out). **Commit per task; do not push without asking the owner.** Commit-message scopes: `feat(core):` for the DebridCore task, `feat(tvos):` / `build(tvos):` / `test(tvos):` / `chore(tvos):` for the app.

---

## File Structure

**DebridCore (one change — the brain):**
- Modify: `Packages/DebridCore/Sources/DebridCore/RealDebrid/RealDebridAuthClient.swift` — add `RealDebridAuthError` + `awaitCredentials(for:clientID:sleep:)`.
- Modify: `Packages/DebridCore/Tests/DebridCoreTests/RealDebridAuthClientTests.swift` — add poll-loop tests + a sequential stub helper.

**Repo scaffolding (committed unless noted):**
- `.gitignore` (add `Frameworks/`), `Secrets.example.xcconfig`, `Secrets.xcconfig` (gitignored, created locally), `.swiftlint.yml`, `.swiftformat`, `Scripts/fetch-frameworks.sh` (scaffold; not run in 7a), `Scripts/make-placeholder-assets.swift` (generator).

**XcodeGen + app (`Apps/SeretTV/`):**
- `project.yml` (gitignored output `Seret.xcodeproj`).
- `Apps/SeretTV/SeretTVApp.swift` — `@main`; builds `AppSession`; hosts `RootView`. One responsibility: composition root.
- `Apps/SeretTV/Shell/AppSession.swift` — `@MainActor @Observable`; owns `RealDebridSession`, session state, vends the sign-in model. Launch resolution + sign-out.
- `Apps/SeretTV/Shell/RootView.swift` — switches state → SignIn | Home.
- `Apps/SeretTV/Shell/HomeStubView.swift` — "Signed in ✓" + Settings entry.
- `Apps/SeretTV/Shell/SettingsView.swift` — account placeholder + Sign Out.
- `Apps/SeretTV/Auth/AuthFlow.swift` — protocol seam + `LiveAuthFlow` (thin glue over `RealDebridAuthClient` + `RealDebridSession`).
- `Apps/SeretTV/Auth/SignInModel.swift` — `@MainActor @Observable` phase machine.
- `Apps/SeretTV/Auth/SignInView.swift` — device-code screen (code + URL + QR + status).
- `Apps/SeretTV/Auth/QRCode.swift` — `CIQRCodeGenerator` → `Image` helper.
- `Apps/SeretTV/Resources/Assets.xcassets/…` — App Icon & Top Shelf (generated placeholder art).
- `Apps/SeretTVTests/SignInModelTests.swift` — the one required unit test (+ `FakeAuthFlow`).

---

## Pre-flight (do once, before Task 3)

- [ ] **Confirm tooling**

```bash
which xcodegen || brew install xcodegen
xcodegen --version           # expect 2.x
xcrun simctl list devices available | grep -i "Apple TV"
```
Expected: `xcodegen` resolves, and at least one **Apple TV** simulator is listed. If the device name differs from `Apple TV 4K (3rd generation)`, use the listed name in every `-destination` below.

---

## Task 1: DebridCore — `awaitCredentials` poll loop (the one brain change)

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/RealDebrid/RealDebridAuthClient.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/RealDebridAuthClientTests.swift`

Run all commands from the repo root (`/Users/shaharsolomons/Documents/Code/Seret`).

- [ ] **Step 1: Write the failing tests**

Add a file-scope sequential-stub helper and two `@Test`s. Open `RealDebridAuthClientTests.swift`. Add this **above** the `extension MockTests {` line:

```swift
/// Serves canned responses in order; repeats the final one once exhausted.
/// Lets one stub drive a multi-poll loop (pending → … → authorized).
private final class SequenceStub: @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [(Int, String)]
    private var i = 0
    init(_ steps: [(Int, String)]) { self.steps = steps }
    func install() {
        MockURLProtocol.handler = { [self] request in
            lock.lock()
            let (status, json) = steps[min(i, steps.count - 1)]
            i += 1
            lock.unlock()
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
    }
}
```

Then add these two tests **inside** the `@Suite struct RealDebridAuthClientTests { … }` body (e.g. after `refreshDecodes`):

```swift
@Test func awaitCredentialsResolvesAfterPending() async throws {
    SequenceStub([
        (400, #"{"error":"authorization_pending"}"#),
        (400, #"{"error":"authorization_pending"}"#),
        (200, #"{"client_id":"CID","client_secret":"CSECRET"}"#),
    ]).install()
    let client = RealDebridAuthClient(http: HTTPClient(session: .mock))
    let code = RDDeviceCode(deviceCode: "DC", userCode: "WXYZ",
                            interval: 5, expiresIn: 1800,
                            verificationURL: "https://real-debrid.com/device")
    let creds = try await client.awaitCredentials(for: code, sleep: { _ in })
    #expect(creds.clientID == "CID")
    #expect(creds.clientSecret == "CSECRET")
}

@Test func awaitCredentialsThrowsWhenCodeExpires() async {
    MockURLProtocol.stub(status: 400, json: #"{"error":"authorization_pending"}"#)
    let client = RealDebridAuthClient(http: HTTPClient(session: .mock))
    let code = RDDeviceCode(deviceCode: "DC", userCode: "WXYZ",
                            interval: 5, expiresIn: 10,
                            verificationURL: "https://real-debrid.com/device")
    await #expect(throws: RealDebridAuthError.deviceCodeExpired) {
        _ = try await client.awaitCredentials(for: code, sleep: { _ in })
    }
}
```

(`RDDeviceCode`'s memberwise init is reachable because this test file already does `@testable import DebridCore`.)

- [ ] **Step 2: Run the tests to verify they fail**

```bash
swift test --package-path Packages/DebridCore \
  --filter RealDebridAuthClientTests 2>&1 | tail -20
```
Expected: FAIL — compile errors `cannot find 'RealDebridAuthError'` / `value of type 'RealDebridAuthClient' has no member 'awaitCredentials'`.

- [ ] **Step 3: Add the error type + the poll loop**

In `RealDebridAuthClient.swift`, add the error enum just below `import Foundation`:

```swift
public enum RealDebridAuthError: Error, Equatable {
    /// The device code's `expiresIn` budget elapsed before the user authorized.
    case deviceCodeExpired
}
```

Then add this method inside the `RealDebridAuthClient` struct, after `refresh(token:credentials:)`:

```swift
    /// Polls `pollCredentials` on the code's `interval` until the user authorizes
    /// (returns credentials) or the code's `expiresIn` budget is exhausted
    /// (throws `.deviceCodeExpired`). The RD poll **cadence lives here in the brain**
    /// so app UI just `await`s this once. `sleep` is injectable for instant tests;
    /// production uses `Task.sleep`, which makes the wait cancellable.
    public func awaitCredentials(
        for code: RDDeviceCode,
        clientID: String = openSourceClientID,
        sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async throws -> RDDeviceCredentials {
        let interval = max(1, code.interval)
        var remaining = code.expiresIn
        while true {
            if let credentials = try await pollCredentials(deviceCode: code.deviceCode,
                                                           clientID: clientID) {
                return credentials
            }
            guard remaining > 0 else { throw RealDebridAuthError.deviceCodeExpired }
            let step = min(interval, remaining)
            try await sleep(.seconds(step))
            remaining -= step
        }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
swift test --package-path Packages/DebridCore \
  --filter RealDebridAuthClientTests 2>&1 | tail -20
```
Expected: PASS (all `RealDebridAuthClientTests`, including the two new ones).

- [ ] **Step 5: Run the FULL suite + zero-warning check (the merge bar)**

```bash
swift test --package-path Packages/DebridCore 2>&1 | tail -5
swift build --package-path Packages/DebridCore 2>&1 | grep -i warning || echo "NO WARNINGS"
```
Expected: all tests pass (112 total — was 110), and `NO WARNINGS`.

- [ ] **Step 6: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/RealDebrid/RealDebridAuthClient.swift \
        Packages/DebridCore/Tests/DebridCoreTests/RealDebridAuthClientTests.swift
git commit -m "feat(core): RealDebridAuthClient.awaitCredentials — device-code poll loop (cadence in the brain)"
```

---

## Task 2: Repo scaffolding — gitignore, secrets, lint configs, fetch-frameworks scaffold

**Files:**
- Modify: `.gitignore`
- Create: `Secrets.example.xcconfig` (committed), `Secrets.xcconfig` (gitignored), `.swiftlint.yml`, `.swiftformat`, `Scripts/fetch-frameworks.sh`

- [ ] **Step 1: Add `Frameworks/` to `.gitignore`**

The existing `.gitignore` already ignores `Seret.xcodeproj/` and `Secrets.xcconfig`. Add the vendored-frameworks line. Insert after the `# CocoaPods …` block:

```gitignore
# Vendored frameworks — TVVLCKit.xcframework is fetched by Scripts/fetch-frameworks.sh (Plan 7c)
Frameworks/
```

- [ ] **Step 2: Commit the Secrets template**

Create `Secrets.example.xcconfig`:

```xcconfig
// Secrets.example.xcconfig — TEMPLATE (committed). Copy to Secrets.xcconfig (gitignored) and fill in.
//
// Plan 7a (sign-in): Real-Debrid uses the public open-source device-code client
//   (X245A4XAIBGVM) — NO secret is required here. This file exists to prove the
//   build-settings plumbing that later slices use.
//
// Plan 7b (library):   TMDB_API_KEY = your_tmdb_v3_key
// Plan 7c (subtitles): OPENSUBTITLES_API_KEY = your_opensubtitles_key
```

- [ ] **Step 3: Create the real (gitignored) Secrets file**

Create `Secrets.xcconfig` (this is gitignored; it must exist locally because `project.yml` references it as a config file). For 7a it carries no values:

```xcconfig
// Secrets.xcconfig — gitignored. Copied from Secrets.example.xcconfig.
// 7a: no values needed (RD uses the public device-code client). Add TMDB/OpenSubtitles keys in 7b/7c.
```

- [ ] **Step 4: Commit the lint/format configs (not wired to a build phase — spec §10)**

Create `.swiftlint.yml`:

```yaml
# .swiftlint.yml — committed in 7a. Build-phase enforcement is deferred (spec §10);
# run manually with `swiftlint` for now.
disabled_rules:
  - todo
opt_in_rules:
  - empty_count
  - first_where
excluded:
  - Packages/DebridCore/.build
  - Seret.xcodeproj
line_length:
  warning: 140
  error: 200
```

Create `.swiftformat`:

```
--swiftversion 6.0
--indent 4
--maxwidth 140
--exclude Packages/DebridCore/.build,Seret.xcodeproj
```

- [ ] **Step 5: Scaffold the VLCKit fetch script (NOT run in 7a)**

Create `Scripts/fetch-frameworks.sh`:

```bash
#!/usr/bin/env bash
#
# fetch-frameworks.sh — vendors the pinned TVVLCKit.xcframework into Frameworks/
# (gitignored). DECIDED in Plan 7a (spec §4.3); USED for the first time in Plan 7c.
# NOT required for 7a's sign-in build.
#
# Approach: first-party stable VLCKit 3.x binary from videolan.org, vendored +
# embedded via XcodeGen (mirrors Nikud's llama.xcframework setup). Plan 7c finalizes
# the exact tarball URL + sha256 and flips this on.
set -euo pipefail

VLCKIT_VERSION="3.6.0"          # stable 3.x (VLCMediaPlayer API). Revisit at VLCKit 4.0 stable.
DEST_DIR="Frameworks"
PINNED_URL=""                   # Plan 7c: exact https://download.videolan.org/... tarball URL
EXPECTED_SHA256=""              # Plan 7c: sha256 of the tarball (reproducible builds)

if [[ -z "$PINNED_URL" || -z "$EXPECTED_SHA256" ]]; then
  echo "fetch-frameworks: TVVLCKit pin not finalized (Plan 7c sets PINNED_URL + EXPECTED_SHA256)." >&2
  echo "  Intended: TVVLCKit ${VLCKIT_VERSION} -> ${DEST_DIR}/TVVLCKit.xcframework" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo "Downloading TVVLCKit ${VLCKIT_VERSION}…"
curl -fL "$PINNED_URL" -o "$tmp/vlckit.tar.xz"
echo "${EXPECTED_SHA256}  $tmp/vlckit.tar.xz" | shasum -a 256 -c -
tar -xJf "$tmp/vlckit.tar.xz" -C "$tmp"
# Plan 7c: move the extracted TVVLCKit.xcframework into "$DEST_DIR".
echo "Done."
```

Make it executable:

```bash
chmod +x Scripts/fetch-frameworks.sh
```

- [ ] **Step 6: Commit**

```bash
git add .gitignore Secrets.example.xcconfig .swiftlint.yml .swiftformat Scripts/fetch-frameworks.sh
git commit -m "chore(tvos): scaffold secrets, lint/format configs, and VLCKit fetch script (7c)"
```
(`Secrets.xcconfig` is intentionally **not** added — it is gitignored.)

---

## Task 3: XcodeGen project + minimal app + placeholder assets → first zero-warning build

This task proves the whole toolchain (XcodeGen → app target → test target → tvOS simulator build) with a trivial `@main`, **before** any sign-in code. The `@main` here is a stepping stone; Task 6 replaces it with the real shell.

**Files:**
- Create: `project.yml`, `Apps/SeretTV/SeretTVApp.swift` (temporary), `Apps/SeretTVTests/SmokeTests.swift`, `Scripts/make-placeholder-assets.swift`, and (generated) `Apps/SeretTV/Resources/Assets.xcassets/…`

- [ ] **Step 1: Write `project.yml`**

Create `project.yml`:

```yaml
name: Seret
options:
  bundleIdPrefix: com.solomons.seret
  createIntermediateGroups: true
  deploymentTarget:
    tvOS: "18.0"
packages:
  DebridCore:
    path: Packages/DebridCore
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
targets:
  SeretTV:
    type: application
    platform: tvOS
    deploymentTarget: "18.0"
    sources:
      - path: Apps/SeretTV
    dependencies:
      - package: DebridCore
    settings:
      base:
        PRODUCT_NAME: Seret
        PRODUCT_BUNDLE_IDENTIFIER: com.solomons.seret.tv
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_CFBundleDisplayName: Seret
        CODE_SIGN_STYLE: Automatic
        DEVELOPMENT_TEAM: ML9HDN3QZS
        TARGETED_DEVICE_FAMILY: "3"
        ASSETCATALOG_COMPILER_APPICON_NAME: "App Icon & Top Shelf Image"
        LD_RUNPATH_SEARCH_PATHS:
          - "$(inherited)"
          - "@executable_path/Frameworks"
    configFiles:
      Debug: Secrets.xcconfig
      Release: Secrets.xcconfig
    scheme:
      testTargets:
        - SeretTVTests
  SeretTVTests:
    type: bundle.unit-test
    platform: tvOS
    deploymentTarget: "18.0"
    sources:
      - path: Apps/SeretTVTests
    dependencies:
      - target: SeretTV
      - package: DebridCore
    settings:
      base:
        SWIFT_STRICT_CONCURRENCY: complete
```

> **Test host:** the `- target: SeretTV` dependency makes XcodeGen wire `SeretTVTests` as an **app-hosted** unit test (it sets `TEST_HOST`/`BUNDLE_LOADER` and the scheme's host application automatically), which is what lets `@testable import Seret` resolve the app's symbols. If `xcodebuild … test` later fails to find the host, add these to the `SeretTVTests` `settings.base` and re-generate:
> ```yaml
>         TEST_HOST: "$(BUILT_PRODUCTS_DIR)/Seret.app/Seret"
>         BUNDLE_LOADER: "$(TEST_HOST)"
> ```
> Because the host app launches during testing, Task 6's `@main` guards against driving the live (network-firing) UI under tests — see Task 6, Step 5.

- [ ] **Step 2: Write the temporary `@main`**

Create `Apps/SeretTV/SeretTVApp.swift`:

```swift
import SwiftUI

@main
struct SeretTVApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Seret")
                .font(.largeTitle)
        }
    }
}
```

- [ ] **Step 3: Write a smoke test (proves the test target builds + runs)**

Create `Apps/SeretTVTests/SmokeTests.swift`:

```swift
import Testing
@testable import Seret

@Test func appTargetLinks() {
    #expect(Bool(true))
}
```

- [ ] **Step 4: Write the placeholder-asset generator**

Create `Scripts/make-placeholder-assets.swift`. It writes the full tvOS **App Icon & Top Shelf Image** brand-asset tree (every `Contents.json` + correctly-sized placeholder PNGs) under `Apps/SeretTV/Resources/Assets.xcassets`. Real art is a later polish drop-in (spec §197).

```swift
#!/usr/bin/env swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = "Apps/SeretTV/Resources/Assets.xcassets"
let fm = FileManager.default

func write(_ rel: String, _ text: String) {
    let url = URL(fileURLWithPath: "\(root)/\(rel)")
    try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! text.data(using: .utf8)!.write(to: url)
}

func png(_ rel: String, _ w: Int, _ h: Int,
         bg: (Double, Double, Double), dot: Bool) {
    let url = URL(fileURLWithPath: "\(root)/\(rel)")
    try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let cs = CGColorSpaceCreateDeviceRGB()
    // Opaque (no alpha) — tvOS App Store icons must not have an alpha channel,
    // else actool warns and breaks the zero-warning bar.
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(red: bg.0, green: bg.1, blue: bg.2, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    if dot {
        let d = Double(min(w, h)) * 0.5
        ctx.setFillColor(red: 0.96, green: 0.78, blue: 0.30, alpha: 1)   // Seret amber
        ctx.fillEllipse(in: CGRect(x: (Double(w) - d) / 2, y: (Double(h) - d) / 2, width: d, height: d))
    }
    let img = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

let info = #"{"author":"xcode","version":1}"#

// Catalog root
write("Contents.json", "{\n  \"info\" : \(info)\n}\n")

// --- App Icon brand-asset set ---
write("App Icon & Top Shelf Image.brandassets/Contents.json", """
{
  "assets" : [
    { "filename" : "App Icon.imagestack", "idiom" : "tv", "role" : "primary-app-icon", "size" : "400x240" },
    { "filename" : "App Icon - App Store.imagestack", "idiom" : "tv", "role" : "primary-app-icon", "size" : "1280x768" },
    { "filename" : "Top Shelf Image Wide.imageset", "idiom" : "tv", "role" : "top-shelf-image-wide", "size" : "2320x720" },
    { "filename" : "Top Shelf Image.imageset", "idiom" : "tv", "role" : "top-shelf-image", "size" : "1920x720" }
  ],
  "info" : \(info)
}
""")

// Helper: a 2-layer imagestack (Back + Front), each layer a full-size image.
func imagestack(_ name: String, _ w: Int, _ h: Int) {
    let base = "App Icon & Top Shelf Image.brandassets/\(name).imagestack"
    write("\(base)/Contents.json", """
    {
      "info" : \(info),
      "layers" : [
        { "filename" : "Front.imagestacklayer" },
        { "filename" : "Back.imagestacklayer" }
      ]
    }
    """)
    for (layer, dot, bg) in [("Front", true, (0.08, 0.10, 0.13)),
                             ("Back", false, (0.05, 0.06, 0.08))] {
        let lp = "\(base)/\(layer).imagestacklayer"
        write("\(lp)/Contents.json", "{\n  \"info\" : \(info)\n}\n")
        write("\(lp)/Content.imageset/Contents.json", """
        {
          "images" : [ { "filename" : "icon.png", "idiom" : "tv", "scale" : "1x" } ],
          "info" : \(info)
        }
        """)
        png("\(lp)/Content.imageset/icon.png", w, h, bg: bg, dot: dot)
    }
}

imagestack("App Icon", 400, 240)
imagestack("App Icon - App Store", 1280, 768)

// Helper: a top-shelf imageset (1x + 2x).
func topShelf(_ name: String, _ w: Int, _ h: Int) {
    let base = "App Icon & Top Shelf Image.brandassets/\(name).imageset"
    write("\(base)/Contents.json", """
    {
      "images" : [
        { "filename" : "shelf@1x.png", "idiom" : "tv", "scale" : "1x" },
        { "filename" : "shelf@2x.png", "idiom" : "tv", "scale" : "2x" }
      ],
      "info" : \(info)
    }
    """)
    png("\(base)/shelf@1x.png", w, h, bg: (0.06, 0.07, 0.09), dot: true)
    png("\(base)/shelf@2x.png", w * 2, h * 2, bg: (0.06, 0.07, 0.09), dot: true)
}

topShelf("Top Shelf Image Wide", 2320, 720)
topShelf("Top Shelf Image", 1920, 720)

print("Wrote placeholder asset catalog to \(root)")
```

- [ ] **Step 5: Generate the assets**

```bash
swift Scripts/make-placeholder-assets.swift
find "Apps/SeretTV/Resources/Assets.xcassets" -name "*.png" | wc -l
```
Expected: prints the "Wrote placeholder asset catalog…" line, and `8` PNGs.

- [ ] **Step 6: Generate the Xcode project and build**

```bash
xcodegen generate
xcodebuild -scheme SeretTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  build 2>&1 | tee /tmp/seret-build.log | grep -iE 'warning:|error:' || echo "NO WARNINGS/ERRORS"
tail -1 /tmp/seret-build.log
```
Expected: `NO WARNINGS/ERRORS`, and the build log ends with `** BUILD SUCCEEDED **`. If `actool` warns about the icon, fix the offending `Contents.json` size/role in the generator and re-run Step 5–6 until clean.

- [ ] **Step 7: Run the smoke test (proves the test action works)**

```bash
xcodebuild -scheme SeretTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  test 2>&1 | tail -8
```
Expected: `** TEST SUCCEEDED **` (the `appTargetLinks` test passes).

- [ ] **Step 8: Commit**

```bash
git add project.yml Apps/SeretTV/SeretTVApp.swift Apps/SeretTVTests/SmokeTests.swift \
        Scripts/make-placeholder-assets.swift "Apps/SeretTV/Resources/Assets.xcassets"
git commit -m "build(tvos): XcodeGen project + tvOS target + placeholder assets — first green simulator build"
```

---

## Task 4: `AuthFlow` seam + `SignInModel` + the required unit test

**Files:**
- Create: `Apps/SeretTV/Auth/AuthFlow.swift`, `Apps/SeretTV/Auth/SignInModel.swift`
- Test: `Apps/SeretTVTests/SignInModelTests.swift`

- [ ] **Step 1: Write the failing unit test**

Create `Apps/SeretTVTests/SignInModelTests.swift`:

```swift
import Testing
import Foundation
import DebridCore
@testable import Seret

private func makeDeviceCode() -> RDDeviceCode {
    let json = #"""
    {"device_code":"DC","user_code":"WXYZ-1234","interval":5,
     "expires_in":1800,"verification_url":"https://real-debrid.com/device"}
    """#
    return try! JSONDecoder().decode(RDDeviceCode.self, from: Data(json.utf8))
}

@MainActor
final class FakeAuthFlow: AuthFlow {
    var beginError: Error?
    var signInError: Error?
    private(set) var beginCalls = 0
    private(set) var awaitCalls = 0

    func begin() async throws -> RDDeviceCode {
        beginCalls += 1
        if let beginError { throw beginError }
        return makeDeviceCode()
    }

    func awaitSignIn(_ code: RDDeviceCode) async throws {
        awaitCalls += 1
        if let signInError { throw signInError }
    }
}

@MainActor
@Suite struct SignInModelTests {
    @Test func happyPathReachesSignedIn() async {
        var signedIn = false
        let fake = FakeAuthFlow()
        let model = SignInModel(flow: fake, onSignedIn: { signedIn = true })
        await model.run()
        #expect(model.phase == .signedIn)
        #expect(signedIn)
        #expect(fake.beginCalls == 1)
        #expect(fake.awaitCalls == 1)
    }

    @Test func failureThenRetrySucceeds() async {
        var signedInCount = 0
        let fake = FakeAuthFlow()
        fake.signInError = HTTPError.transport("offline")
        let model = SignInModel(flow: fake, onSignedIn: { signedInCount += 1 })

        await model.run()
        guard case .failed = model.phase else {
            #expect(Bool(false), "expected .failed, got \(model.phase)")
            return
        }
        #expect(signedInCount == 0)

        fake.signInError = nil
        model.retry()
        await model.run()
        #expect(model.phase == .signedIn)
        #expect(signedInCount == 1)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild -scheme SeretTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  test 2>&1 | tail -15
```
Expected: FAIL — `cannot find type 'AuthFlow'` / `cannot find 'SignInModel'`.

- [ ] **Step 3: Write the `AuthFlow` seam + `LiveAuthFlow`**

Create `Apps/SeretTV/Auth/AuthFlow.swift`:

```swift
import DebridCore

/// The two device-code steps the sign-in model depends on, so its phase machine
/// is unit-testable without the network. `LiveAuthFlow` is the real implementation;
/// tests use a `FakeAuthFlow`. All RD/networking lives in `DebridCore` (the brain) —
/// this is thin glue only.
@MainActor
protocol AuthFlow {
    /// Start the device-code flow → the user-facing code + verification URL.
    func begin() async throws -> RDDeviceCode
    /// Wait for the user to authorize, then mint + persist tokens. One long await.
    func awaitSignIn(_ code: RDDeviceCode) async throws
}

@MainActor
struct LiveAuthFlow: AuthFlow {
    let auth: RealDebridAuthClient
    let session: RealDebridSession

    func begin() async throws -> RDDeviceCode {
        try await auth.startDeviceCode()
    }

    func awaitSignIn(_ code: RDDeviceCode) async throws {
        let credentials = try await auth.awaitCredentials(for: code)
        let token = try await auth.requestToken(deviceCode: code.deviceCode, credentials: credentials)
        try await session.establish(token: token, deviceCredentials: credentials)
    }
}
```

- [ ] **Step 4: Write the `SignInModel` phase machine**

Create `Apps/SeretTV/Auth/SignInModel.swift`:

```swift
import DebridCore
import Observation

/// Drives the device-code sign-in as an observable phase machine. The long wait is
/// a single `await flow.awaitSignIn(_:)`, so the whole flow cancels cleanly when the
/// view disappears. No RD/networking logic here — it delegates to `AuthFlow`.
@MainActor
@Observable
final class SignInModel {
    enum Phase: Equatable {
        case idle
        case requestingCode
        case awaitingAuthorization(RDDeviceCode)
        case establishing
        case signedIn
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// Bumped by `retry()`; drives the view's `.task(id:)` so a retry restarts the run.
    private(set) var attempt = 0

    private let flow: AuthFlow
    private let onSignedIn: () -> Void

    init(flow: AuthFlow, onSignedIn: @escaping () -> Void) {
        self.flow = flow
        self.onSignedIn = onSignedIn
    }

    /// Run the full flow once. Safe to call again after `.failed` (retry).
    func run() async {
        phase = .requestingCode
        do {
            let code = try await flow.begin()
            phase = .awaitingAuthorization(code)
            try await flow.awaitSignIn(code)
            phase = .establishing
            phase = .signedIn
            onSignedIn()
        } catch is CancellationError {
            // View disappeared mid-wait — leave state untouched, no dangling work.
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    func retry() { attempt += 1 }

    /// User-facing message. Never interpolates the raw error (no token/secret leakage).
    static func message(for error: Error) -> String {
        switch error {
        case RealDebridAuthError.deviceCodeExpired:
            return "That code expired before you signed in. Try again to get a new one."
        default:
            return "Couldn't reach Real‑Debrid. Check your connection and try again."
        }
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
xcodebuild -scheme SeretTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  test 2>&1 | tail -10
```
Expected: `** TEST SUCCEEDED **` (`happyPathReachesSignedIn` + `failureThenRetrySucceeds` + smoke test pass).

- [ ] **Step 6: Commit**

```bash
git add Apps/SeretTV/Auth/AuthFlow.swift Apps/SeretTV/Auth/SignInModel.swift \
        Apps/SeretTVTests/SignInModelTests.swift
git commit -m "feat(tvos): AuthFlow seam + SignInModel phase machine (unit-tested)"
```

---

## Task 5: `QRCode` helper + `SignInView`

**Files:**
- Create: `Apps/SeretTV/Auth/QRCode.swift`, `Apps/SeretTV/Auth/SignInView.swift`

This task adds UI only; it's verified by the compile here and by the simulator screenshot in Task 7.

- [ ] **Step 1: Write the QR helper**

Create `Apps/SeretTV/Auth/QRCode.swift`:

```swift
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Generates a crisp QR `Image` from a string (e.g. the RD verification URL).
enum QRCode {
    private static let context = CIContext()

    static func image(from string: String, scale: CGFloat = 12) -> Image? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
              let cg = context.createCGImage(output, from: output.extent) else {
            return nil
        }
        return Image(decorative: cg, scale: 1, orientation: .up)
    }
}
```

- [ ] **Step 2: Write the device-code screen**

Create `Apps/SeretTV/Auth/SignInView.swift`:

```swift
import DebridCore
import SwiftUI

/// The device-code sign-in screen. Renders `SignInModel.phase`; runs the flow via
/// `.task(id: model.attempt)` so it auto-cancels on disappear and restarts on retry.
struct SignInView: View {
    let model: SignInModel

    var body: some View {
        ZStack {
            switch model.phase {
            case .idle, .requestingCode:
                ProgressView("Preparing sign‑in…")
                    .font(.title2)
            case .awaitingAuthorization(let code):
                deviceCode(code)
            case .establishing, .signedIn:
                ProgressView("Signing in…")
                    .font(.title2)
            case .failed(let message):
                failure(message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: model.attempt) { await model.run() }
    }

    private func deviceCode(_ code: RDDeviceCode) -> some View {
        VStack(spacing: 48) {
            Text("Sign in to Real‑Debrid")
                .font(.largeTitle.bold())
            HStack(alignment: .center, spacing: 80) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("On your phone or computer, go to")
                        .font(.title3).foregroundStyle(.secondary)
                    Text(displayURL(code.verificationURL))
                        .font(.title.bold())
                    Text("and enter this code:")
                        .font(.title3).foregroundStyle(.secondary)
                    Text(code.userCode)
                        .font(.system(size: 96, weight: .heavy, design: .monospaced))
                }
                if let qr = QRCode.image(from: code.verificationURL) {
                    qr.resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 300, height: 300)
                        .padding(20)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            Label("Waiting for authorization…", systemImage: "hourglass")
                .font(.title3).foregroundStyle(.secondary)
        }
        .padding(80)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 32) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 72)).foregroundStyle(.yellow)
            Text(message)
                .font(.title2).multilineTextAlignment(.center).frame(maxWidth: 800)
            Button("Try Again") { model.retry() }
                .font(.title3)
        }
        .padding(80)
    }

    /// "https://real-debrid.com/device" → "real-debrid.com/device".
    private func displayURL(_ raw: String) -> String {
        guard let comps = URLComponents(string: raw), let host = comps.host else { return raw }
        return host + comps.path
    }
}
```

- [ ] **Step 3: Verify it compiles (build only)**

`SignInView`/`QRCode` aren't referenced by `@main` yet, so confirm they compile by building:

```bash
xcodegen generate
xcodebuild -scheme SeretTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  build 2>&1 | tee /tmp/seret-build.log | grep -iE 'warning:|error:' || echo "NO WARNINGS/ERRORS"
tail -1 /tmp/seret-build.log
```
Expected: `NO WARNINGS/ERRORS` and `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Apps/SeretTV/Auth/QRCode.swift Apps/SeretTV/Auth/SignInView.swift
git commit -m "feat(tvos): device-code SignInView + QR helper"
```

---

## Task 6: `AppSession` + `RootView` + Home/Settings → full shell wired to `@main`

**Files:**
- Create: `Apps/SeretTV/Shell/AppSession.swift`, `Apps/SeretTV/Shell/RootView.swift`, `Apps/SeretTV/Shell/HomeStubView.swift`, `Apps/SeretTV/Shell/SettingsView.swift`
- Modify: `Apps/SeretTV/SeretTVApp.swift` (replace the temporary body)

- [ ] **Step 1: Write `AppSession` (composition root + session state)**

Create `Apps/SeretTV/Shell/AppSession.swift`:

```swift
import DebridCore
import Observation

/// Owns the one shared `RealDebridSession` and the app's coarse auth state. It is the
/// `AccessTokenProviding` source that 7b's library + 7c's playback will consume.
@MainActor
@Observable
final class AppSession {
    enum State: Equatable { case unknown, signedIn, signedOut }

    private(set) var state: State = .unknown
    let realDebrid: RealDebridSession

    private var cachedSignInModel: SignInModel?

    init(realDebrid: RealDebridSession) {
        self.realDebrid = realDebrid
    }

    /// Resolve launch state from persisted credentials. `validAccessToken()` throws
    /// `.notSignedIn` ONLY when there are no stored credentials, which lets us treat
    /// offline-with-credentials as optimistically signed in (spec §143) while a server
    /// rejection of the refresh token routes back to sign-in (spec §165).
    func resolve() async {
        do {
            _ = try await realDebrid.validAccessToken()
            state = .signedIn
        } catch RealDebridSessionError.notSignedIn {
            state = .signedOut
        } catch HTTPError.status(_, _) {
            // RD actively rejected the stored/refresh token → must re-authenticate.
            state = .signedOut
        } catch {
            // Transport/offline but credentials exist: stay signed in; later calls retry.
            state = .signedIn
        }
    }

    /// One stable sign-in model per signed-out episode; dropped on success.
    func signInModel() -> SignInModel {
        if let cachedSignInModel { return cachedSignInModel }
        let model = SignInModel(
            flow: LiveAuthFlow(auth: RealDebridAuthClient(), session: realDebrid),
            onSignedIn: { [weak self] in self?.markSignedIn() })
        cachedSignInModel = model
        return model
    }

    func markSignedIn() {
        state = .signedIn
        cachedSignInModel = nil
    }

    func signOut() async {
        try? await realDebrid.signOut()
        cachedSignInModel = nil
        state = .signedOut
    }
}
```

- [ ] **Step 2: Write `RootView`**

Create `Apps/SeretTV/Shell/RootView.swift`:

```swift
import SwiftUI

/// Resolves launch state, then routes between sign-in and the (stub) Home.
struct RootView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        switch session.state {
        case .unknown:
            ProgressView()
                .task { await session.resolve() }
        case .signedOut:
            SignInView(model: session.signInModel())
        case .signedIn:
            HomeStubView()
        }
    }
}
```

- [ ] **Step 3: Write `HomeStubView`**

Create `Apps/SeretTV/Shell/HomeStubView.swift`:

```swift
import SwiftUI

/// Placeholder signed-in screen. The real library lands in Plan 7b.
struct HomeStubView: View {
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 32) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 96)).foregroundStyle(.green)
            Text("Signed in ✓")
                .font(.largeTitle.bold())
            Text("Your library lands here in 7b.")
                .font(.title3).foregroundStyle(.secondary)
            Button {
                showingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape").font(.title3)
            }
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingSettings) { SettingsView() }
    }
}
```

- [ ] **Step 4: Write `SettingsView` (Sign Out)**

Create `Apps/SeretTV/Shell/SettingsView.swift`:

```swift
import SwiftUI

/// Account placeholder + Sign Out. Signing out flips `AppSession` back to `.signedOut`,
/// which routes `RootView` to a fresh `SignInView`.
struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 40) {
            Text("Settings")
                .font(.largeTitle.bold())
            Text("Signed in to Real‑Debrid.")
                .font(.title3).foregroundStyle(.secondary)
            Button(role: .destructive) {
                Task {
                    await session.signOut()
                    dismiss()
                }
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.title3)
            }
            Button("Done") { dismiss() }
                .font(.title3)
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 5: Replace `@main` with the real shell**

Replace the entire contents of `Apps/SeretTV/SeretTVApp.swift`:

```swift
import DebridCore
import SwiftUI

@main
struct SeretTVApp: App {
    @State private var session = AppSession(
        realDebrid: RealDebridSession(store: KeychainTokenStore()))

    var body: some Scene {
        WindowGroup {
            if Self.isRunningTests {
                // The app launches as the unit-test host; don't drive the live
                // (network-firing) sign-in UI during tests.
                Color.clear
            } else {
                RootView()
                    .environment(session)
            }
        }
    }

    /// Xcode sets this env var in the host process during `xcodebuild test`
    /// (true for both XCTest and Swift Testing runs).
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
```

- [ ] **Step 6: Build (zero warnings) + re-run tests**

```bash
xcodegen generate
xcodebuild -scheme SeretTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  build 2>&1 | tee /tmp/seret-build.log | grep -iE 'warning:|error:' || echo "NO WARNINGS/ERRORS"
tail -1 /tmp/seret-build.log
xcodebuild -scheme SeretTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  test 2>&1 | tail -8
```
Expected: `NO WARNINGS/ERRORS`, `** BUILD SUCCEEDED **`, then `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Apps/SeretTV/Shell Apps/SeretTV/SeretTVApp.swift
git commit -m "feat(tvos): AppSession + RootView shell — sign-in → Keychain → Home stub → Sign Out"
```

---

## Task 7: tvOS simulator verification + real RD round-trip (Definition of Done)

No "done" claim without the screenshots below (owner rule). This task runs the app, captures the sign-in screen, completes a **real** authorization against the owner's RD account, and verifies persistence + sign-out.

**Files:** none (verification only).

- [ ] **Step 1: Boot the simulator and install the app**

```bash
xcrun simctl boot "Apple TV 4K (3rd generation)" 2>/dev/null || true
open -a Simulator
xcodebuild -scheme SeretTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  -derivedDataPath build build
xcrun simctl install booted \
  "$(find build/Build/Products -name 'Seret.app' -maxdepth 3 | head -1)"
xcrun simctl launch booted com.solomons.seret.tv
```
Expected: the app launches to the sign-in screen showing a **real** `user_code` + QR.

- [ ] **Step 2: Screenshot the sign-in screen**

```bash
xcrun simctl io booted screenshot /tmp/seret-7a-signin.png
```
Expected: `/tmp/seret-7a-signin.png` shows the instruction, `real-debrid.com/device`, a large user code, and a QR. **Confirm a real code rendered** (not a placeholder).

- [ ] **Step 3: Complete a real authorization**

On a phone/computer, open `https://real-debrid.com/device`, enter the displayed code, and approve (owner's RD account). The app should auto-advance (no button press) → "Signing in…" → Home stub.

- [ ] **Step 4: Screenshot the signed-in Home stub**

```bash
xcrun simctl io booted screenshot /tmp/seret-7a-home.png
```
Expected: `/tmp/seret-7a-home.png` shows "Signed in ✓".

- [ ] **Step 5: Verify Keychain persistence across relaunch**

```bash
xcrun simctl terminate booted com.solomons.seret.tv
xcrun simctl launch booted com.solomons.seret.tv
xcrun simctl io booted screenshot /tmp/seret-7a-relaunch.png
```
Expected: `/tmp/seret-7a-relaunch.png` lands **directly on Home** (no sign-in) — tokens persisted to the Keychain and `validAccessToken()` succeeded.

- [ ] **Step 6: Verify Sign Out returns to sign-in**

Navigate to Settings → Sign Out (use the Simulator remote: `Hardware ▸ Apple TV Remote`, or `xcrun simctl` UI). Then:

```bash
xcrun simctl io booted screenshot /tmp/seret-7a-signedout.png
```
Expected: `/tmp/seret-7a-signedout.png` shows the sign-in screen again with a fresh code.

- [ ] **Step 7: Final guardrails — zero warnings + DebridCore still green + no RD logic in the app**

```bash
xcodebuild -scheme SeretTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  build 2>&1 | grep -iE 'warning:' || echo "ZERO WARNINGS"
swift test --package-path Packages/DebridCore 2>&1 | tail -3
grep -rnE 'URLSession|api\.real-debrid|URLRequest|JSONDecoder\(\)\.decode' Apps/SeretTV || echo "NO NETWORKING/PARSING IN APP TARGET"
```
Expected: `ZERO WARNINGS`; DebridCore suite passes (112 tests); `NO NETWORKING/PARSING IN APP TARGET` (the one architectural rule holds — the app only calls `DebridCore`).

- [ ] **Step 8: Present evidence to the owner**

Share the four screenshots (`signin`, `home`, `relaunch`, `signedout`) and the guardrail output. **Do not** mark 7a done without them. (Pushing the branch is the owner's call — ask first.)

---

## Definition of Done — 7a (mirrors spec §9)

- [ ] `xcodegen generate` + `xcodebuild` for `SeretTV` succeed, **zero warnings** (Tasks 3, 6, 7).
- [ ] Sign-in screen renders a real device code + QR — screenshot (Task 7, Step 2).
- [ ] Real RD device-code round-trip authorizes; tokens persist to Keychain; relaunch stays signed in; Sign Out returns to sign-in — screenshots (Task 7, Steps 3–6).
- [ ] `DebridCore` tests green (112); **no networking/RD/parsing logic in the app target** (Tasks 1, 7).
- [ ] `Secrets.example.xcconfig` committed; `Secrets.xcconfig`, `Frameworks/`, `Seret.xcodeproj` gitignored (Task 2).
- [ ] VLCKit approach recorded (spec) + scaffolded (`Scripts/fetch-frameworks.sh` present, `@executable_path/Frameworks` runpath set in `project.yml`) — integration deferred to 7c (Tasks 2, 3).

---

## Self-review notes

- **Spec coverage:** §4.2 project.yml → Task 3; §4.3 VLCKit scaffold → Tasks 2–3; §5.2 AuthFlow → Task 4; §5.3 SignInModel → Task 4; §5.4 SignInView → Task 5; §5.5 app entry + session → Task 6; §7 error/edge handling → `SignInModel.message` + `AppSession.resolve` (Tasks 4, 6); §8 unit test + simulator verification → Tasks 4, 7. All DoD items mapped above.
- **Type consistency:** `AuthFlow.begin()/awaitSignIn(_:)`, `SignInModel.Phase`/`run()`/`retry()`/`attempt`, `AppSession.state/resolve()/signInModel()/markSignedIn()/signOut()`, and `RealDebridAuthClient.awaitCredentials(for:clientID:sleep:)` are used identically everywhere they appear.
- **Deviations from spec (intentional, owner-approved):** (1) 7a touches `DebridCore` once to add the tested poll loop (spec said "unchanged" under the wrong assumption that cadence already existed). (2) Launch routing uses `validAccessToken()` error discrimination rather than a new "have credentials?" API — no extra brain surface.

---

## As-built & verification notes (post-execution, 2026-06-03)

Executed subagent-driven (fresh implementer + spec review + code-quality review per task). All 6 build tasks committed on `feat/tvos-foundation-signin` (not pushed); DebridCore 112 tests green; app builds zero-warning; `SignInModel` tests pass.

**As-built deltas from the plan above (the code is the source of truth):**
- **Module name is `Seret`** (because `PRODUCT_NAME: Seret`), not `SeretTV` — tests use `@testable import Seret` (fixed in the snippets above).
- **Test target is app-hosted** with explicit `TEST_HOST`/`BUNDLE_LOADER`/`GENERATE_INFOPLIST_FILE` + `SWIFT_VERSION` (XcodeGen's auto-host pointed at the target name, not the `Seret.app/Seret` product binary). The plan flagged this as a contingency; it became required.
- **`.establishing` phase dropped** from `SignInModel.Phase` (code-review: it was set synchronously right before `.signedIn`, so SwiftUI never rendered it — dead observable state). `SignInView`'s switch is the 5 real phases.
- **Model creation moved out of `RootView.body`** into `AppSession.enterSignedOut()` (code-review: building the model in `body` is a state-mutation-during-view-update smell). `AppSession.signInModel` is now an observable `private(set)` built on the signed-out transition.
- **Sign-out reordered** in `SettingsView` to `dismiss()` then `await signOut()` (avoid dismissing a torn-down presenter).
- **`fetch-frameworks.sh` hardened** (post-`tar` `exit 1` guard + `curl --retry`) and **the asset generator** got a repo-root guard + fail-fast `try!` and opaque (`noneSkipLast`) PNGs (tvOS icons must have no alpha or actool warns).
- **`displayURL` keeps the query string** (future-proofing).
- **Added `feat(tvos)` commit `2f5da22`:** clearer sign-in message for RD `403/429` rate-limit (see Task 7 note below).

**Task 7 verification outcome:**
- A long red-herring: the app's sign-in showed "Couldn't reach Real-Debrid". Root-caused NOT to code/TLS/IPv6/the simulator, but to **RD's edge rate-limiting `oauth/v2/device/code?new_credentials=yes`** — dozens of debug requests tripped RD's throttle → a bare HTTP 403 (RD docs: 250 req/min REST limit returns 429; the device-code endpoint's 403 throttle is undocumented / "undefined" duration). Proven: the app's own `URLSession` pulled a clean **200** from that endpoint (and all RD endpoints + Google) once the throttle eased.
- **Live RD auth round-trip CONFIRMED** (first non-mocked validation): via the unthrottled host path, the owner authorized on their phone (device named "Apple TV" in RD) → `device/code` → `device/credentials` (per-user client_id+secret) → `token` (real `Bearer` access_token, `expires_in` 86400s, refresh present). Confirms `RealDebridAuthClient` + `RealDebridSession.establish` endpoints/params/shapes all match live RD.
- **Still pending (cosmetic, not functional):** the app capturing its *own* DoD screenshots (live code screen → signed-in Home → relaunch-persists → Sign Out). Blocked only by RD's throttle on the app fingerprint; one clean app sign-in once it's cold (overnight) completes them.
- **Lesson (recorded):** do NOT hammer RD's `device/code` endpoint while testing — it throttles to a bare 403 fast and the cooldown is long. A real user signs in once and never trips it.
