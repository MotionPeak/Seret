# DebridUI Extraction Implementation Plan (Plan 8a · Part 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the shared *presentation-logic* layer (view-models, provider seams, models, utilities) out of `Apps/SeretTV/` into a new `Shared/DebridUI` Swift package that both apps depend on — a behaviour-preserving refactor that leaves the tvOS app working and every test green.

**Architecture:** A new local SPM package `DebridUI` sits between `DebridCore` (pure logic) and the app targets (platform Views). It holds the `@MainActor @Observable` view-models, the protocol seams over `DebridCore`, UI-facing value types, and small utilities — everything that is platform-agnostic. Promoted types become `public`. Their unit tests move with them and run **host-free under `swift test`** (a strict upgrade over the current app-hosted runs). The tvOS app keeps only its platform Views + the VLCKit engine and gains `import DebridUI`.

**Tech Stack:** Swift 6 (strict concurrency), Swift Package Manager, XcodeGen, Swift Testing. No new third-party deps.

---

## Scope

This is **Part 1 of 2** for slice 8a. It moves the **logic layer only**. Shared SwiftUI **components** (`PosterImage`/`PosterCard` split, `QualityChips`, `BackdropBackground`) and the player **engine** are deliberately *not* moved here — they migrate in 8b/8c alongside the iOS Views that consume them (the spec already defers the `PosterCard` split to 8b). This keeps Part 1 a clean, low-risk, test-protected refactor with no SwiftUI-component churn.

**Definition of Done (Part 1):**
- `Shared/DebridUI` exists; the files in §"File Map → MOVE" live there and are `public`.
- `SeretTV` builds and runs unchanged; `import DebridUI` added where needed.
- `swift test` green for **DebridCore** (130) **and** the new **DebridUI** suites; zero warnings.
- `SeretTVTests` trimmed to tvOS-View smoke; the moved suites run under `swift test`.
- No behaviour change anywhere.

## File Map

**MOVE to `Shared/DebridUI/Sources/DebridUI/`** (mirror the concern subfolders):

| From `Apps/SeretTV/` | Concern |
|---|---|
| `Support/Timecode.swift` | utility |
| `Support/Secrets.swift` | utility (reads `Bundle.main` Info.plist) |
| `Support/OpenSubtitlesAccount.swift` | utility |
| `Auth/QRCode.swift` | utility (CoreImage; tvOS-only consumer, but generic) |
| `Playback/PlaybackRequest.swift` | model |
| `Library/LibraryProviding.swift` | seam |
| `Detail/MediaDetailsProviding.swift` | seam |
| `Detail/WatchProgressProviding.swift` | seam |
| `Auth/AuthFlow.swift` | view-model seam |
| `Auth/SignInModel.swift` | view-model |
| `Library/LibraryStore.swift` | view-model |
| `Detail/DetailStore.swift` | view-model |
| `Shell/SettingsModel.swift` | view-model |
| `Playback/PlayerModel.swift` | view-model (VLCKit-free) |
| `Shell/AppSession.swift` | session root |

**MOVE tests to `Shared/DebridUI/Tests/DebridUITests/`:** `SignInModelTests`, `SettingsModelTests`, `LibraryStoreTests`, `DetailStoreTests`, `PlayerModelTests`, `Fakes.swift`.

**STAYS in `Apps/SeretTV/`** (tvOS Views / focus / Siri / UIKit-VLCKit): `SeretTVApp`, all of `Shell/RootView`,`LibraryShell`,`SettingsView`; `Auth/SignInView`; all of `Library/LibraryScreen`,`PosterGrid`,`PosterCard`; all `Detail/*View`,`EpisodeRow`,`QualityChips`,`BackdropBackground`; all of `Playback/PlayerView`,`PlayerOverlays`,`ScrubPad`,`TrackMenuPanel`,`ThumbnailProvider`,`VLCKitVideoPlayerEngine`,`VLCVideoView`; `Resources/`. `SeretTVTests/SmokeTests.swift` stays.

## The Move Recipe (used by Tasks 2–6)

Every move task follows the same behaviour-preserving procedure. "The files" = the batch named in the task.

1. **`git mv`** each file from `Apps/SeretTV/<sub>/X.swift` to `Shared/DebridUI/Sources/DebridUI/<sub>/X.swift` (preserves history).
2. **Make the cross-module API `public`** in each moved file: the type (`public final class`/`public struct`/`public protocol`/`public enum`), its `init`, and any property/method/case referenced from the app target or another moved file. `@Observable`/`@MainActor` are kept as-is (e.g. `@MainActor @Observable public final class SignInModel`). Leave purely-internal helpers `internal`.
3. **Add `import DebridUI`** to every `Apps/SeretTV` file that references a moved type (the compiler lists them).
4. **Regenerate + verify green** (see the Verify block below). Iterate on `public`/`import` until the build and both test suites pass with zero warnings.
5. **Commit** the batch.

**Verify block** (run after every task):
```bash
cd /Users/shaharsolomons/Documents/Code/Seret
xcodegen generate                                   # refresh project after moving sources
swift test --package-path Packages/DebridCore       # DebridCore stays green
swift test --package-path Shared/DebridUI           # new module + migrated suites
xcodebuild build -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV' -quiet
```
Expected: all green, **zero warnings**. (Run the `xcodebuild test` for `SeretTV` in the final task; per-batch the build smoke + `swift test` is enough and far faster.)

> **Guard rail:** if a file you move fails to compile for **macOS** under `swift test` because it imports **UIKit** (or uses a tvOS-only API), it does **not** belong in `DebridUI` — move it back to `Apps/SeretTV` and note it. All files in the MOVE list are expected to be UIKit-free; this guard catches surprises.

---

### Task 1: Scaffold the `DebridUI` package and wire it in

**Files:**
- Create: `Shared/DebridUI/Package.swift`
- Create: `Shared/DebridUI/Sources/DebridUI/DebridUI.swift` (placeholder so the target compiles)
- Create: `Shared/DebridUI/Tests/DebridUITests/PackageSmokeTests.swift`
- Modify: `project.yml`

- [ ] **Step 1: Create `Package.swift`** — same deployment floor as `DebridCore` so `swift test` runs on the Mac.

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DebridUI",
    platforms: [.iOS(.v18), .tvOS(.v18), .macOS(.v14)],
    products: [.library(name: "DebridUI", targets: ["DebridUI"])],
    dependencies: [.package(path: "../../Packages/DebridCore")],
    targets: [
        .target(name: "DebridUI", dependencies: [.product(name: "DebridCore", package: "DebridCore")]),
        .testTarget(name: "DebridUITests", dependencies: ["DebridUI"]),
    ]
)
```

- [ ] **Step 2: Create the placeholder source** `Shared/DebridUI/Sources/DebridUI/DebridUI.swift`:

```swift
// DebridUI — shared presentation layer (view-models, seams, models, utilities).
// Populated by the extraction tasks that follow.
import DebridCore
```

- [ ] **Step 3: Create a smoke test** `Shared/DebridUI/Tests/DebridUITests/PackageSmokeTests.swift`:

```swift
import Testing
@testable import DebridUI

@Test func moduleLoads() { #expect(true) }
```

- [ ] **Step 4: Wire the package into `project.yml`.** Under `packages:` add `DebridUI`, and add it to `SeretTV`'s `dependencies:`.

```yaml
packages:
  DebridCore:
    path: Packages/DebridCore
  DebridUI:
    path: Shared/DebridUI
# ... in target SeretTV:
    dependencies:
      - package: DebridCore
      - package: DebridUI
      - framework: Frameworks/VLCKit.xcframework
        embed: true
        codeSign: true
```

- [ ] **Step 5: Verify green.**

```bash
cd /Users/shaharsolomons/Documents/Code/Seret
swift test --package-path Shared/DebridUI            # 1 test passes
xcodegen generate
xcodebuild build -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV' -quiet
```
Expected: `swift test` PASS (1 test); `SeretTV` builds, zero warnings.

- [ ] **Step 6: Commit.**

```bash
git add Shared/DebridUI project.yml
git commit -m "feat(8a): scaffold DebridUI shared package + wire into SeretTV"
```

---

### Task 2: Move the leaf layer (utilities · model · seams)

Lowest-dependency files first. **Files to move** (apply the Move Recipe): `Support/Timecode.swift`, `Support/Secrets.swift`, `Support/OpenSubtitlesAccount.swift`, `Auth/QRCode.swift`, `Playback/PlaybackRequest.swift`, `Library/LibraryProviding.swift`, `Detail/MediaDetailsProviding.swift`, `Detail/WatchProgressProviding.swift`.

- [ ] **Step 1: `git mv` the eight files** into `Shared/DebridUI/Sources/DebridUI/` under `Support/`, `Playback/`, `Library/`, `Detail/` respectively.

```bash
cd /Users/shaharsolomons/Documents/Code/Seret
git mv Apps/SeretTV/Support/Timecode.swift Shared/DebridUI/Sources/DebridUI/Support/Timecode.swift
git mv Apps/SeretTV/Support/Secrets.swift Shared/DebridUI/Sources/DebridUI/Support/Secrets.swift
git mv Apps/SeretTV/Support/OpenSubtitlesAccount.swift Shared/DebridUI/Sources/DebridUI/Support/OpenSubtitlesAccount.swift
git mv Apps/SeretTV/Auth/QRCode.swift Shared/DebridUI/Sources/DebridUI/Support/QRCode.swift
git mv Apps/SeretTV/Playback/PlaybackRequest.swift Shared/DebridUI/Sources/DebridUI/Playback/PlaybackRequest.swift
git mv Apps/SeretTV/Library/LibraryProviding.swift Shared/DebridUI/Sources/DebridUI/Library/LibraryProviding.swift
git mv Apps/SeretTV/Detail/MediaDetailsProviding.swift Shared/DebridUI/Sources/DebridUI/Detail/MediaDetailsProviding.swift
git mv Apps/SeretTV/Detail/WatchProgressProviding.swift Shared/DebridUI/Sources/DebridUI/Detail/WatchProgressProviding.swift
```

- [ ] **Step 2: Make each moved type `public`** (type + `init` + referenced members). Example for a seam and a value type:

```swift
public protocol LibraryProviding: Sendable {
    func loadCached() async -> [MediaItem]
    func refresh() async throws -> [MediaItem]
}

public struct PlaybackRequest: Hashable, Sendable {
    public let contentKey: String
    public let title: String
    // ...existing stored properties → public...
    public init(contentKey: String, title: String /* ...*/) { /* ...*/ }
}
```
QRCode's helper becomes `public enum QRCode { public static func image(from: String) -> Image? }`. `Timecode` → `public func timecode(_:)` (or `public enum`). Apply the same pattern to `Secrets`, `OpenSubtitlesAccount`, `MediaDetailsProviding`, `WatchProgressProviding`.

- [ ] **Step 3: Add `import DebridUI`** to the `SeretTV` files the compiler flags (e.g. `SignInView`, `LibraryScreen`, `DetailView`/`MovieDetailView`/`ShowDetailView`, `PlayerView`, `SettingsView`, `LibraryShell`, and the moved view-models in later tasks).

- [ ] **Step 4: Verify green** — run the Verify block. Iterate on `public`/`import` until zero warnings.

- [ ] **Step 5: Commit.**

```bash
git add -A && git commit -m "refactor(8a): move utilities, PlaybackRequest, and provider seams to DebridUI"
```

---

### Task 3: Move the auth view-models

**Files to move** (Move Recipe): `Auth/AuthFlow.swift`, `Auth/SignInModel.swift`.

- [ ] **Step 1: `git mv`** both into `Shared/DebridUI/Sources/DebridUI/Auth/`.

```bash
git mv Apps/SeretTV/Auth/AuthFlow.swift Shared/DebridUI/Sources/DebridUI/Auth/AuthFlow.swift
git mv Apps/SeretTV/Auth/SignInModel.swift Shared/DebridUI/Sources/DebridUI/Auth/SignInModel.swift
```

- [ ] **Step 2: Make public.** `public protocol AuthFlow` (+ its methods); `@MainActor @Observable public final class SignInModel` with `public init(...)`, `public var phase`, `public var attempt`, `public func run() async`, `public func retry()`, `public func signInWithToken(_:) async`. Keep the `Phase`/`RDDeviceCode`-facing enums `public` if referenced by Views.

- [ ] **Step 3: Add `import DebridUI`** to `Auth/SignInView.swift` (and any other flagged file).

- [ ] **Step 4: Verify green** — Verify block.

- [ ] **Step 5: Commit.**

```bash
git add -A && git commit -m "refactor(8a): move AuthFlow + SignInModel to DebridUI"
```

---

### Task 4: Move the library + detail view-models

**Files to move** (Move Recipe): `Library/LibraryStore.swift`, `Detail/DetailStore.swift`.

- [ ] **Step 1: `git mv`** into `Shared/DebridUI/Sources/DebridUI/Library/` and `.../Detail/`.

```bash
git mv Apps/SeretTV/Library/LibraryStore.swift Shared/DebridUI/Sources/DebridUI/Library/LibraryStore.swift
git mv Apps/SeretTV/Detail/DetailStore.swift Shared/DebridUI/Sources/DebridUI/Detail/DetailStore.swift
```

- [ ] **Step 2: Make public.** `@MainActor @Observable public final class LibraryStore` / `DetailStore` with `public init`, public state (e.g. `items`, `phase`, `selectedSeason`) and public methods (`load()`, `refresh()`, `select(...)`, etc. — match the existing names exactly). These depend on the seams moved in Task 2 (already public).

- [ ] **Step 3: Add `import DebridUI`** to `LibraryScreen`, `LibraryShell`, `DetailView`/`MovieDetailView`/`ShowDetailView`, `EpisodeRow` (whatever the compiler flags).

- [ ] **Step 4: Verify green** — Verify block.

- [ ] **Step 5: Commit.**

```bash
git add -A && git commit -m "refactor(8a): move LibraryStore + DetailStore to DebridUI"
```

---

### Task 5: Move the settings + player view-models

**Files to move** (Move Recipe): `Shell/SettingsModel.swift`, `Playback/PlayerModel.swift`.

- [ ] **Step 1: `git mv`** into `Shared/DebridUI/Sources/DebridUI/Shell/` and `.../Playback/`.

```bash
git mv Apps/SeretTV/Shell/SettingsModel.swift Shared/DebridUI/Sources/DebridUI/Shell/SettingsModel.swift
git mv Apps/SeretTV/Playback/PlayerModel.swift Shared/DebridUI/Sources/DebridUI/Playback/PlayerModel.swift
```

- [ ] **Step 2: Make public.** `@MainActor @Observable public final class SettingsModel` / `PlayerModel` with `public init` and the members the Views call (e.g. `PlayerModel.load()`, `play()`, `pause()`, `seek(to:)`, `state`, `time`, `tracks`, `selectExternalSubtitle(...)`, `retry()`, `tryAnotherVersion()` — match exact existing signatures). `PlayerModel` references the `VideoPlayerEngine` **protocol** (in `DebridCore`, already public) — the concrete VLCKit engine stays in `SeretTV`, injected in; confirm the initializer takes the protocol, not the concrete type.

- [ ] **Step 3: Add `import DebridUI`** to `SettingsView`, `PlayerView`, `PlayerOverlays`, `TrackMenuPanel`, `ScrubPad` (as flagged).

- [ ] **Step 4: Verify green** — Verify block. (The `PlayerModel` macOS-compile via `swift test` confirms it is genuinely VLCKit/UIKit-free.)

- [ ] **Step 5: Commit.**

```bash
git add -A && git commit -m "refactor(8a): move SettingsModel + PlayerModel to DebridUI"
```

---

### Task 6: Move `AppSession` (the session root)

Moved last because it composes the others. **File to move** (Move Recipe): `Shell/AppSession.swift`.

- [ ] **Step 1: `git mv`** into `Shared/DebridUI/Sources/DebridUI/Shell/`.

```bash
git mv Apps/SeretTV/Shell/AppSession.swift Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift
```

- [ ] **Step 2: Make public.** `@MainActor @Observable public final class AppSession` with `public init(realDebrid:)`, public state (e.g. `state`/`isSignedIn`), and the factory/methods the app calls (`makePlayer(...)`, `signOut()`, `makeSignInModel()`, `makeLibraryStore()`, etc. — match exact names). Its `init` signature must stay identical so `SeretTVApp` keeps working: `AppSession(realDebrid: RealDebridSession(store: KeychainTokenStore()))`.

- [ ] **Step 3: Add `import DebridUI`** to `SeretTVApp.swift` and `RootView.swift`.

- [ ] **Step 4: Verify green** — Verify block.

- [ ] **Step 5: Commit.**

```bash
git add -A && git commit -m "refactor(8a): move AppSession to DebridUI — logic layer fully shared"
```

---

### Task 7: Relocate the shared-logic test suites

Move the unit tests that exercise the now-shared view-models out of the app-hosted `SeretTVTests` into the host-free `DebridUITests`.

**Files:**
- Move: `Apps/SeretTVTests/{SignInModelTests,SettingsModelTests,LibraryStoreTests,DetailStoreTests,PlayerModelTests,Fakes}.swift` → `Shared/DebridUI/Tests/DebridUITests/`
- Delete: `Shared/DebridUI/Tests/DebridUITests/PackageSmokeTests.swift` (Task 1 placeholder, now redundant)
- Keep: `Apps/SeretTVTests/SmokeTests.swift`

- [ ] **Step 1: `git mv` the six files.**

```bash
cd /Users/shaharsolomons/Documents/Code/Seret
for f in SignInModelTests SettingsModelTests LibraryStoreTests DetailStoreTests PlayerModelTests Fakes; do
  git mv "Apps/SeretTVTests/$f.swift" "Shared/DebridUI/Tests/DebridUITests/$f.swift"
done
git rm Shared/DebridUI/Tests/DebridUITests/PackageSmokeTests.swift
```

- [ ] **Step 2: Retarget the imports.** In each moved test, change `@testable import Seret` → `@testable import DebridUI`. The `Fakes` (fake `AuthFlow`, fake providers, fake `VideoPlayerEngine`) become the module's test doubles; mark anything they expose `public` only if a non-test target needs it (tests `@testable`-import, so usually no change needed).

- [ ] **Step 3: Verify green.**

```bash
swift test --package-path Shared/DebridUI            # the migrated suites now run host-free
xcodegen generate
xcodebuild test -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV' -quiet
```
Expected: `swift test` runs the migrated suites green; `SeretTVTests` (now smoke-only) green; zero warnings.

- [ ] **Step 4: Commit.**

```bash
git add -A && git commit -m "refactor(8a): move shared-logic test suites to DebridUITests (host-free)"
```

---

### Task 8: Add design tokens + full verification

Introduce the shared monochrome design tokens (the foundation 8b's adaptive Views consume) and run the complete verification.

**Files:**
- Create: `Shared/DebridUI/Sources/DebridUI/Theme/Tokens.swift`

- [ ] **Step 1: Write the failing test** `Shared/DebridUI/Tests/DebridUITests/TokensTests.swift`:

```swift
import Testing
import SwiftUI
@testable import DebridUI

@Test func posterAspectRatioIsTwoThirds() {
    #expect(Tokens.posterAspect == 2.0 / 3.0)
}
```

- [ ] **Step 2: Run it — verify it fails.**

```bash
swift test --package-path Shared/DebridUI --filter TokensTests
```
Expected: FAIL — `Tokens` not found.

- [ ] **Step 3: Implement `Tokens`** — the monochrome, poster-forward language pulled from the tvOS app (no accent colour; artwork carries colour):

```swift
import SwiftUI

/// Shared design tokens. Monochrome + poster-forward — see the 8a brainstorm.
public enum Tokens {
    public static let posterAspect: CGFloat = 2.0 / 3.0      // 2:3 posters
    public static let gridSpacing: CGFloat = 12
    public static let cornerRadius: CGFloat = 6
    public static let chipFill = Color.white.opacity(0.12)   // QualityChips capsule
    public static let watchedTint = Color.green
}
```

- [ ] **Step 4: Run the token test — verify it passes.**

```bash
swift test --package-path Shared/DebridUI --filter TokensTests
```
Expected: PASS.

- [ ] **Step 5: Full green sweep.**

```bash
cd /Users/shaharsolomons/Documents/Code/Seret
swift test --package-path Packages/DebridCore        # 130 green
swift test --package-path Shared/DebridUI            # all migrated suites + tokens green
xcodegen generate
xcodebuild build -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV' -quiet
xcodebuild test  -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV' -quiet
```
Expected: every command green, **zero warnings**. `Apps/SeretTV/` now contains only Views + the VLCKit engine + `SeretTVApp` + `Resources`.

- [ ] **Step 6: Commit.**

```bash
git add -A && git commit -m "feat(8a): add shared DebridUI design tokens; full extraction green"
```

---

## Self-Review

- **Spec coverage (§4 of the spec):** §4.1 shared layer → Tasks 2–6 + 8 (tokens). §4.2 promotion rule → File Map + the macOS-compile guard rail. §4.3 tests move host-free → Task 7. §4.4 `project.yml` → Task 1. §4.5 refactor safety (green after each move) → the Verify block on every task + Task 8 full sweep. Components/engine deferral → Scope note. **No gaps.**
- **Placeholders:** none — every task names exact files, exact `git mv` commands, the `public` pattern, and exact verify commands. The per-file `public` symbol list is compiler-driven by design (the Move Recipe makes this explicit, not vague).
- **Type consistency:** `DebridUI` module name, `AppSession(realDebrid:)` init, and `VideoPlayerEngine` protocol injection are referenced consistently across Tasks 1, 5, 6. View-model method names are instructed to "match exact existing signatures" rather than invented.
