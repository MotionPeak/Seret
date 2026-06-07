# Trailers — Slice 1 (Extraction Foundation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the shared foundation for reliable trailers: resolve a YouTube key to a direct,
AVPlayer-playable stream URL (via YouTubeKit, in DebridUI), a persisted "autoplay trailers"
setting, and a `TrailerModel` view-model both apps will consume — all behind seams so it's
testable and so the UI slices can build on a proven base.

**Architecture:** YouTubeKit (new SPM dep in `DebridUI`) parses YouTube's player JS + solves the
cipher to return a direct `googlevideo.com/videoplayback` URL (360p progressive — the only muxed
format YouTube serves). A `TrailerStreamResolving` seam wraps it so view-models stay testable
without the library. `TrailerModel` chains the existing `TrailerProviding` (TMDB → YouTube key)
with the new resolver (key → URL). `AppSession` vends both + a `TrailerSettingsModel`.

**Tech Stack:** Swift 6, SwiftPM, Swift Testing. YouTubeKit (github.com/alexeichhorn/YouTubeKit).
DebridUI tested via `swift test`. The brain `DebridCore` is untouched (no-deps rule preserved).

**Branch:** `feat/stage2-search-add`. Spec: `docs/superpowers/specs/2026-06-08-trailer-playback-autoplay-design.md` (spike result confirms YouTubeKit works). Stage only the paths each task names.

**Scope note:** This is Slice 1 of 3. Slice 2 (iOS AVPlayer + auto-play UI) and Slice 3 (tvOS)
get their own plans after the extraction is verified playing in-app on the simulator.

---

## File Structure

- Modify `Shared/DebridUI/Package.swift` — add the YouTubeKit dependency.
- Create `Shared/DebridUI/Sources/DebridUI/Detail/TrailerStreamResolving.swift` — seam + `YouTubeKitStreamResolver`.
- Create `Shared/DebridUI/Sources/DebridUI/Settings/TrailerSettingsModel.swift` — persisted `autoplayTrailers`.
- Create `Shared/DebridUI/Sources/DebridUI/Detail/TrailerModel.swift` — the shared view-model.
- Modify `Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift` — compose the resolver + settings + a `makeTrailerModel` factory.
- Tests: `Shared/DebridUI/Tests/DebridUITests/TrailerSettingsModelTests.swift`, `TrailerModelTests.swift`.

---

## Task 1: Add YouTubeKit + `TrailerStreamResolving` seam

**Files:**
- Modify: `Shared/DebridUI/Package.swift`
- Create: `Shared/DebridUI/Sources/DebridUI/Detail/TrailerStreamResolving.swift`

- [ ] **Step 1: Add the dependency**

In `Shared/DebridUI/Package.swift`, add YouTubeKit to `dependencies` and to the `DebridUI` target.
The full file becomes:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DebridUI",
    platforms: [.iOS(.v18), .tvOS(.v18), .macOS(.v14)],
    products: [.library(name: "DebridUI", targets: ["DebridUI"])],
    dependencies: [
        .package(path: "../../Packages/DebridCore"),
        .package(url: "https://github.com/alexeichhorn/YouTubeKit", from: "0.4.8"),
    ],
    targets: [
        .target(name: "DebridUI", dependencies: [
            .product(name: "DebridCore", package: "DebridCore"),
            .product(name: "YouTubeKit", package: "YouTubeKit"),
        ]),
        .testTarget(name: "DebridUITests", dependencies: ["DebridUI"]),
    ]
)
```

- [ ] **Step 2: Resolve the dependency**

Run: `cd Shared/DebridUI && swift package resolve`
Expected: resolves YouTubeKit 0.4.x with no error.

- [ ] **Step 3: Create the seam + resolver**

Create `Shared/DebridUI/Sources/DebridUI/Detail/TrailerStreamResolving.swift`:

```swift
import Foundation
import YouTubeKit

/// Resolves a YouTube video key to a direct, AVPlayer-playable stream URL. Seam so `TrailerModel`
/// is testable without YouTubeKit (and so the resolver can be swapped if YouTube extraction moves).
public protocol TrailerStreamResolving: Sendable {
    /// A directly-playable stream URL for the YouTube key, or nil if extraction fails / none.
    func streamURL(youTubeKey: String) async -> URL?
}

/// `TrailerStreamResolving` backed by YouTubeKit. Returns the first PROGRESSIVE (muxed audio+video)
/// stream — YouTube serves a single 360p progressive format today, which AVPlayer plays natively.
/// Higher-res would require stitching separate adaptive streams (out of scope for trailers).
public struct YouTubeKitStreamResolver: TrailerStreamResolving {
    public init() {}

    public func streamURL(youTubeKey: String) async -> URL? {
        guard let streams = try? await YouTube(videoID: youTubeKey).streams else { return nil }
        return streams.first { $0.isProgressive }?.url
    }
}
```

- [ ] **Step 4: Build DebridUI**

Run: `cd Shared/DebridUI && swift build 2>&1 | grep -i warning; echo "exit ${PIPESTATUS[0]}"`
Expected: builds; no warnings.
(No unit test for this thin wrapper — it's third-party I/O. The live spike already proved it
resolves a real URL; Slice 2 verifies playback on the sim.)

- [ ] **Step 5: Commit**

```bash
git add Shared/DebridUI/Package.swift Shared/DebridUI/Package.resolved \
        Shared/DebridUI/Sources/DebridUI/Detail/TrailerStreamResolving.swift
git commit -m "feat(ui): YouTubeKit trailer stream resolver behind a TrailerStreamResolving seam"
```

---

## Task 2: `TrailerSettingsModel` (persisted autoplay toggle)

**Files:**
- Create: `Shared/DebridUI/Sources/DebridUI/Settings/TrailerSettingsModel.swift`
- Test: `Shared/DebridUI/Tests/DebridUITests/TrailerSettingsModelTests.swift`

Mirrors `SubtitleSettingsModel` exactly (UserDefaults-backed `@Observable`).

- [ ] **Step 1: Write the failing test**

Create `Shared/DebridUI/Tests/DebridUITests/TrailerSettingsModelTests.swift`:

```swift
import Testing
import Foundation
@testable import DebridUI

@MainActor
@Suite struct TrailerSettingsModelTests {
    private func freshDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "trailer-test-\(UUID().uuidString)")!
        return d
    }

    @Test func defaultsToOn() {
        let m = TrailerSettingsModel(defaults: freshDefaults())
        #expect(m.autoplayTrailers == true)
    }

    @Test func persistsAcrossInstances() {
        let d = freshDefaults()
        let m1 = TrailerSettingsModel(defaults: d)
        m1.autoplayTrailers = false
        let m2 = TrailerSettingsModel(defaults: d)   // re-read from the same defaults
        #expect(m2.autoplayTrailers == false)
    }
}
```

- [ ] **Step 2: Run, verify FAIL**

Run: `cd Shared/DebridUI && swift test --filter TrailerSettingsModelTests`
Expected: FAIL — no `TrailerSettingsModel`.

- [ ] **Step 3: Implement**

Create `Shared/DebridUI/Sources/DebridUI/Settings/TrailerSettingsModel.swift`:

```swift
import Foundation
import Observation

/// Observable, `UserDefaults`-persisted trailer preferences. Lives on `AppSession`; the Settings UI
/// binds to it and `TrailerModel` reads it. Mirrors `SubtitleSettingsModel`.
@MainActor
@Observable
public final class TrailerSettingsModel {
    /// Auto-play a muted trailer on the detail backdrop. Default on.
    public var autoplayTrailers: Bool { didSet { defaults.set(autoplayTrailers, forKey: Self.key) } }

    private let defaults: UserDefaults
    private static let key = "seret.autoplayTrailers"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        autoplayTrailers = defaults.object(forKey: Self.key) as? Bool ?? true
    }
}
```

- [ ] **Step 4: Run, verify PASS**

Run: `cd Shared/DebridUI && swift test --filter TrailerSettingsModelTests`
Expected: 2 pass.

- [ ] **Step 5: Commit**

```bash
git add Shared/DebridUI/Sources/DebridUI/Settings/TrailerSettingsModel.swift \
        Shared/DebridUI/Tests/DebridUITests/TrailerSettingsModelTests.swift
git commit -m "feat(ui): persisted TrailerSettingsModel (autoplayTrailers, default on)"
```

---

## Task 3: `TrailerModel` view-model

**Files:**
- Create: `Shared/DebridUI/Sources/DebridUI/Detail/TrailerModel.swift`
- Test: `Shared/DebridUI/Tests/DebridUITests/TrailerModelTests.swift`

Chains key-resolution (`TrailerProviding`) → stream-resolution (`TrailerStreamResolving`) into a
`@MainActor @Observable` state machine the UI consumes. The ~4s delay, mute, and full-screen are
the UI's job (Slice 2); this model owns *resolution* + the autoplay-enabled flag.

- [ ] **Step 1: Write the failing test**

Create `Shared/DebridUI/Tests/DebridUITests/TrailerModelTests.swift`:

```swift
import Testing
import Foundation
import DebridCore
@testable import DebridUI

private struct FakeTrailers: TrailerProviding {
    let key: String?
    func trailerKey(tmdbID: Int, kind: MediaKind) async -> String? { key }
}
private struct FakeResolver: TrailerStreamResolving {
    let url: URL?
    func streamURL(youTubeKey: String) async -> URL? { url }
}

@MainActor
@Suite struct TrailerModelTests {
    private func model(key: String?, url: URL?, autoplay: Bool = true) -> TrailerModel {
        TrailerModel(trailers: FakeTrailers(key: key),
                     resolver: FakeResolver(url: url),
                     autoplayEnabled: { autoplay })
    }

    @Test func resolvesToReadyURL() async {
        let m = model(key: "abc", url: URL(string: "https://v/1.mp4")!)
        await m.prepare(tmdbID: 1, kind: .movie)
        #expect(m.state == .ready(URL(string: "https://v/1.mp4")!))
        #expect(m.autoplayAllowed == true)
    }

    @Test func noTrailerKeyIsUnavailable() async {
        let m = model(key: nil, url: URL(string: "https://v/1.mp4")!)
        await m.prepare(tmdbID: 1, kind: .movie)
        #expect(m.state == .unavailable)
    }

    @Test func extractionFailureIsUnavailable() async {
        let m = model(key: "abc", url: nil)
        await m.prepare(tmdbID: 1, kind: .movie)
        #expect(m.state == .unavailable)
        #expect(m.youTubeKey == "abc")   // key kept for the deep-link fallback
    }

    @Test func autoplayDisabledFlagReflectsSetting() async {
        let m = model(key: "abc", url: URL(string: "https://v/1.mp4")!, autoplay: false)
        await m.prepare(tmdbID: 1, kind: .movie)
        #expect(m.autoplayAllowed == false)   // ready, but auto-play suppressed by the setting
    }
}
```

- [ ] **Step 2: Run, verify FAIL**

Run: `cd Shared/DebridUI && swift test --filter TrailerModelTests`
Expected: FAIL — no `TrailerModel`.

- [ ] **Step 3: Implement**

Create `Shared/DebridUI/Sources/DebridUI/Detail/TrailerModel.swift`:

```swift
import DebridCore
import Foundation
import Observation

/// Resolves a title's trailer to a playable stream URL for both apps. State machine:
/// `idle → resolving → ready(URL)` (playable) or `→ unavailable` (no key / extraction failed →
/// the UI shows nothing inline and the Trailer button deep-links to YouTube using `youTubeKey`).
@MainActor
@Observable
public final class TrailerModel {
    public enum State: Equatable { case idle, resolving, ready(URL), unavailable }

    public private(set) var state: State = .idle
    /// The YouTube key, once resolved — drives the deep-link fallback even when extraction fails.
    public private(set) var youTubeKey: String?

    private let trailers: TrailerProviding
    private let resolver: TrailerStreamResolving
    private let autoplayEnabled: @MainActor () -> Bool

    public init(trailers: TrailerProviding,
                resolver: TrailerStreamResolving,
                autoplayEnabled: @escaping @MainActor () -> Bool) {
        self.trailers = trailers
        self.resolver = resolver
        self.autoplayEnabled = autoplayEnabled
    }

    /// True only when a stream is ready AND the user's autoplay setting is on — gates the muted
    /// backdrop auto-play. (The Trailer button plays regardless of this, full-screen.)
    public var autoplayAllowed: Bool {
        if case .ready = state { return autoplayEnabled() }
        return false
    }

    /// The playable stream URL when ready, else nil.
    public var streamURL: URL? { if case .ready(let u) = state { return u } else { return nil } }

    public func prepare(tmdbID: Int, kind: MediaKind) async {
        state = .resolving
        guard let key = await trailers.trailerKey(tmdbID: tmdbID, kind: kind) else {
            state = .unavailable
            return
        }
        youTubeKey = key
        if let url = await resolver.streamURL(youTubeKey: key) {
            state = .ready(url)
        } else {
            state = .unavailable
        }
    }
}
```

- [ ] **Step 4: Run, verify PASS**

Run: `cd Shared/DebridUI && swift test --filter TrailerModelTests`
Expected: 4 pass.

- [ ] **Step 5: Commit**

```bash
git add Shared/DebridUI/Sources/DebridUI/Detail/TrailerModel.swift \
        Shared/DebridUI/Tests/DebridUITests/TrailerModelTests.swift
git commit -m "feat(ui): TrailerModel resolves key→stream URL with deep-link fallback state"
```

---

## Task 4: Compose in `AppSession`

**Files:**
- Modify: `Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift`

`AppSession` already vends `trailers: TrailerProviding?` and `public let subtitleSettings`. Add a
trailer-settings model (survives sign-out, like `subtitleSettings`), a stream resolver (built at
sign-in), and a `makeTrailerModel(...)` factory the detail screens call.

- [ ] **Step 1: Add stored properties**

Next to `public let subtitleSettings = SubtitleSettingsModel()`, add:

```swift
    /// Trailer auto-play preference, persisted; survives sign-out (a device setting).
    public let trailerSettings = TrailerSettingsModel()
```

Next to `private var streamSource` / `addService`, add:

```swift
    private var trailerResolver: TrailerStreamResolving?
```

- [ ] **Step 2: Build the resolver at sign-in**

In `enterSignedIn()`, after `trailers = TMDBTrailerService(client: tmdb)`, add:

```swift
        trailerResolver = YouTubeKitStreamResolver()
```

In `enterSignedOut()`, alongside the other resets, add:

```swift
        trailerResolver = nil
```

- [ ] **Step 3: Add the factory**

Near `makeAddStore(...)`, add:

```swift
    /// Vend a `TrailerModel` for a title (nil while signed out). Chains the TMDB key provider with
    /// the YouTubeKit resolver and reads the persisted autoplay setting.
    public func makeTrailerModel() -> TrailerModel? {
        guard let trailers, let trailerResolver else { return nil }
        return TrailerModel(trailers: trailers, resolver: trailerResolver,
                            autoplayEnabled: { [trailerSettings] in trailerSettings.autoplayTrailers })
    }
```

- [ ] **Step 4: Build DebridUI + run the suite**

Run: `cd Shared/DebridUI && swift build 2>&1 | grep -i warning; echo "build ${PIPESTATUS[0]}"`
Then: `cd Shared/DebridUI && swift test 2>&1 | tail -3`
Expected: builds with no warnings; all tests pass (new TrailerModel/TrailerSettings suites + the
existing suites). If the pre-existing SwiftUICore CLI-link flake blocks `swift test`, fall back to
`swift build` + the app build in Slice 2.

- [ ] **Step 5: Commit**

```bash
git add Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift
git commit -m "feat(ui): AppSession vends TrailerModel + trailerSettings"
```

---

## Self-Review Notes

- **Spec coverage (Slice 1):** YouTubeKit extraction (Task 1) · `TrailerStreamResolving` seam (Task 1) ·
  360p-progressive selection (Task 1) · persisted autoplay setting (Task 2) · `TrailerModel` state
  machine with deep-link-fallback `youTubeKey` (Task 3) · AppSession composition + factory (Task 4).
  Slices 2–3 (AVPlayer inline/fullscreen, 4s cross-fade, unmute, Settings UI, both apps, fallback
  wiring) are deliberately deferred to their own plans, gated on this proven base.
- **Type consistency:** `TrailerStreamResolving.streamURL(youTubeKey:) -> URL?`,
  `YouTubeKitStreamResolver`, `TrailerSettingsModel.autoplayTrailers`, `TrailerModel`
  (`.idle/.resolving/.ready(URL)/.unavailable`, `streamURL`, `youTubeKey`, `autoplayAllowed`,
  `prepare(tmdbID:kind:)`), `AppSession.makeTrailerModel()` — consistent across tasks.
- **DebridCore untouched:** YouTubeKit lives only in DebridUI; the brain's no-deps rule holds.
- **No unit test for the YouTubeKit wrapper:** intentional (third-party I/O, proven by the live
  spike); `TrailerModel` is fully tested via a fake resolver.
