# Seret TV — Gold Glass skin, Home tab, focus hero + spinner fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the tvOS app (`Apps/SeretTV`) up to the iPhone/iPad "Gold Glass" visual language — gold-accented skin, animated splash, a Home tab, and a focus-reactive top hero on Movies/TV — while fixing the infinite-spinner bug on the browse feed.

**Architecture:** tvOS gets its own `DesignSystem` (palette/logo/wordmark mirror of the mobile kit) plus new `Home` and `Browse/HeroBanner` views. All data comes from already-wired shared stores in `Shared/DebridUI` (`DiscoverStore`, `HomeStore`, `LibraryStore`) — no new wiring in `AppSession`. The spinner fix is a one-line `.task` plus a retry path; everything else is additive UI verified by build + tvOS-sim screenshots.

**Tech Stack:** Swift 6 / SwiftUI (tvOS), Swift Testing (`@Test`/`#expect`), XcodeGen project, `swift test` for the host-free `DebridCore`/`DebridUI` packages, `xcodebuild` for the app.

**Spec:** `docs/superpowers/specs/2026-06-07-seret-tv-gold-glass-design.md`

**Branch:** `feat/stage2-search-add` (work happens here; do NOT push without asking the owner).

**Reconciliation note:** Tasks 2–5 resurrect the reverted commit `9580271`. Read each original file with `git show 9580271:<path>` but APPLY edits against the *current* post-revert source — the surrounding code moved 91 commits since. Never blind-cherry-pick.

**Verification reality:** SwiftUI tvOS views are not unit-tested; only store logic is (`swift test`). UI tasks are verified by a clean `xcodebuild build` (0 warnings) and tvOS-sim screenshots. Real RD-stream playback stays owner-pending. pty caveat: if the tvOS sim throws "Pseudo Terminal Setup Error 7/6" mid-session, restart Claude.app (see `reference_xcode_pty_error.md`).

---

## File Structure

**Create (all under `Apps/SeretTV/`):**
- `DesignSystem/Theme.swift` — Gold Glass palette + `CanvasBackground` (from `9580271`).
- `DesignSystem/Brand.swift` — `SeretMark`, `Wordmark`, `PlayTriangle` (from `9580271`).
- `DesignSystem/Modifiers.swift` — `.goldGlow(_:opacity:)` view modifier.
- `Brand/SplashView.swift` — animated launch splash (from `9580271`).
- `Home/HomeScreen.swift` — Home tab (hero + Continue Watching + Recently Added).
- `Home/HomeRail.swift` — tvOS titled horizontal rail + `LandscapeProgressCard` + `GoldProgressBar`.
- `Browse/HeroBanner.swift` — focus-reactive full-bleed backdrop hero + the focus PreferenceKey.

**Modify:**
- `Shell/RootView.swift` — gate the shell behind the splash on first launch.
- `Shell/LibraryShell.swift` — add Home tab (first), gold tab tint.
- `Browse/BrowseScreen.swift` — call `browse.load()`, retry on failure, host `HeroBanner`, publish focus.
- `Detail/*`, `Playback/*`, `Shell/SettingsView.swift`, `Auth/SignInView.swift` — gold accents (Task 5).

**Test (host-free package tests):**
- `Shared/DebridUI/Tests/DebridUITests/DiscoverStoreTests.swift` — add retry-from-failed coverage.

---

## Task 1: Fix the infinite spinner + retry path

**Why:** `BrowseScreen` never calls `browse.load()`, so `DiscoverStore` stays `.idle` and the feed spins forever. Add the load trigger and a retry button for the failure case.

**Files:**
- Test: `Shared/DebridUI/Tests/DebridUITests/DiscoverStoreTests.swift`
- Modify: `Apps/SeretTV/Browse/BrowseScreen.swift`

- [ ] **Step 1: Write a failing test for the retry path**

Add to `DiscoverStoreTests.swift` (uses the existing `FakeDiscover` + `movie(_:)` helpers in that file):

```swift
@Test func retryAfterFailureReloads() async {
    let fake = FakeDiscover()
    fake.trendingMovie = .failure(.boom)
    fake.newMovie = .failure(.boom)
    fake.topRatedMovie = .failure(.boom)
    let store = DiscoverStore(kind: .movie, discover: fake)
    await store.load()
    #expect(store.state == .failed)            // all rows empty → failed

    // Recover the source, then reload: load() must re-run from .failed.
    fake.trendingMovie = .success([movie(1)])
    await store.load()
    #expect(store.state == .loaded)
    #expect(store.rows.first?.hits.first?.result.id == 1)
}
```

- [ ] **Step 2: Run it — verify it passes already (guards confirm the seam)**

Run: `cd Shared/DebridUI && swift test --filter DiscoverStoreTests.retryAfterFailureReloads`
Expected: PASS — `load()` already guards `state == .idle || .failed`, so this locks the retry contract the UI depends on. (If it FAILS, the store guard regressed — fix the store, not the test.)

- [ ] **Step 3: Wire the browse load + retry into `BrowseScreen`**

In `Apps/SeretTV/Browse/BrowseScreen.swift`, replace the `rows` computed view with a version that loads on appear and offers retry on failure:

```swift
@ViewBuilder private var rows: some View {
    if let browse {
        switch browse.state {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                .task(id: kind) { await browse.load() }   // ← the fix: kick off the feed
        case .failed:
            VStack(spacing: 28) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 64))
                    .foregroundStyle(.secondary)
                Text("Couldn't load.").font(.title3)
                Button("Retry") { Task { await browse.load() } }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 40) {
                    segmentPicker(browse).padding(.leading, 60)
                    ForEach(browse.rows) { row in
                        rail(title: row.title, hits: row.hits, cam: false)
                    }
                }
                .padding(.vertical, 20)
            }
        }
    }
}
```

Note: `.task(id: kind)` on the `.idle/.loading` branch fires once when the spinner first appears; `load()` self-guards against double-runs. Keep the existing search `.task(id: query)` untouched.

- [ ] **Step 4: Build the app — verify it compiles**

Run: `xcodebuild -project Seret.xcodeproj -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`, 0 warnings. (Regenerate with `xcodegen generate` first if project files are stale.)

- [ ] **Step 5: Commit**

```bash
git add Apps/SeretTV/Browse/BrowseScreen.swift Shared/DebridUI/Tests/DebridUITests/DiscoverStoreTests.swift
git commit -m "fix(tvos): load browse feed on appear + retry on failure (no more infinite spinner)"
```

---

## Task 2: tvOS design tokens (Theme + Modifiers + CanvasBackground)

**Files:**
- Create: `Apps/SeretTV/DesignSystem/Theme.swift`
- Create: `Apps/SeretTV/DesignSystem/Modifiers.swift`

- [ ] **Step 1: Create `Theme.swift`** — copy verbatim from the reverted commit (already validated to build):

Run `git show 9580271:Apps/SeretTV/DesignSystem/Theme.swift` and write its exact contents to `Apps/SeretTV/DesignSystem/Theme.swift`. It defines `Color(hex:alpha:)`, `enum Theme.Palette` (gold `0xEBC11D`, canvas `0x08080A`, `goldGradient`, `markGradient`, `canvasGlow`, text colors), and `struct CanvasBackground`.

- [ ] **Step 2: Create `Modifiers.swift`** — the gold-glow helper the brand + hero use:

```swift
import SwiftUI

extension View {
    /// Soft gold bloom behind a view. `radius` 0 disables.
    func goldGlow(_ radius: CGFloat, opacity: Double = 0.5) -> some View {
        shadow(color: Theme.Palette.gold.opacity(radius > 0 ? opacity : 0), radius: radius)
    }
}
```

- [ ] **Step 3: Regenerate project + build**

Run: `xcodegen generate && xcodebuild -project Seret.xcodeproj -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`, 0 warnings. (XcodeGen auto-includes new files under `Apps/SeretTV/`; confirm `project.yml` globs that path.)

- [ ] **Step 4: Commit**

```bash
git add Apps/SeretTV/DesignSystem/Theme.swift Apps/SeretTV/DesignSystem/Modifiers.swift
git commit -m "feat(tvos): Gold Glass design tokens (palette, canvas, goldGlow)"
```

---

## Task 3: tvOS Brand (SeretMark + Wordmark)

**Files:**
- Create: `Apps/SeretTV/DesignSystem/Brand.swift`

- [ ] **Step 1: Create `Brand.swift`** — write verbatim from `git show 9580271:Apps/SeretTV/DesignSystem/Brand.swift`. It defines `PlayTriangle: Shape`, `SeretMark: View` (gold play-triangle with glow), and `Wordmark: View` (Hebrew סֶרֶט nikud hero + Latin SERET subtitle, RTL layout, gold glow).

- [ ] **Step 2: Build**

Run: `xcodebuild -project Seret.xcodeproj -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`, 0 warnings.

- [ ] **Step 3: Commit**

```bash
git add Apps/SeretTV/DesignSystem/Brand.swift
git commit -m "feat(tvos): SeretMark logo + סֶרֶט/SERET wordmark"
```

---

## Task 4: Animated splash on launch

**Files:**
- Create: `Apps/SeretTV/Brand/SplashView.swift`
- Modify: `Apps/SeretTV/Shell/RootView.swift`

- [ ] **Step 1: Create `SplashView.swift`** — write verbatim from `git show 9580271:Apps/SeretTV/Brand/SplashView.swift`. It is a `View` taking `onFinished: () -> Void`, runs a ~1.6s mark-bloom → wordmark-rise sequence, and honors `accessibilityReduceMotion`.

- [ ] **Step 2: Gate the shell behind the splash in `RootView.swift`**

Show the splash once per launch, before resolving into the shell. Replace `RootView.body`:

```swift
struct RootView: View {
    @Environment(AppSession.self) private var session
    @State private var splashDone = false

    var body: some View {
        ZStack {
            switch session.state {
            case .unknown:
                Color.black.ignoresSafeArea().task { await session.resolve() }
            case .signedOut:
                if let model = session.signInModel { SignInView(model: model) }
            case .signedIn:
                LibraryShell()
            }
            if !splashDone {
                SplashView { splashDone = true }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: splashDone)
    }
}
```

The splash overlays everything while `session.resolve()` runs underneath, then fades out — so launch never shows a bare spinner.

- [ ] **Step 3: Build**

Run: `xcodebuild -project Seret.xcodeproj -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`, 0 warnings.

- [ ] **Step 4: Sim-verify the splash**

Boot the tvOS sim, install & launch SeretTV, capture a screenshot during/after the splash. Expected: black screen → gold `SeretMark` blooms in → סֶרֶט wordmark rises → fades to sign-in/shell.

- [ ] **Step 5: Commit**

```bash
git add Apps/SeretTV/Brand/SplashView.swift Apps/SeretTV/Shell/RootView.swift
git commit -m "feat(tvos): animated Gold Glass launch splash"
```

---

## Task 5: Gold accents across existing screens

**Why:** Make the app read as "Gold Glass" everywhere, not just the splash. Reconcile the reverted accent edits against current code.

**Files (modify):**
- `Apps/SeretTV/Shell/LibraryShell.swift` — `.tint(Theme.Palette.gold)` on the `TabView`.
- `Apps/SeretTV/Browse/BrowseScreen.swift` — `CanvasBackground()` behind content; gold segment pills (`.tint(seg == selected ? Theme.Palette.gold : .gray)` instead of `.yellow`).
- `Apps/SeretTV/Auth/SignInView.swift` — `Wordmark()` header + `CanvasBackground()`.
- `Apps/SeretTV/Shell/SettingsView.swift` — `CanvasBackground()` + gold section accents.
- `Apps/SeretTV/Detail/*` and `Apps/SeretTV/Playback/*` — gold watched-checks, episode progress, player scrubber/overlay tints.

- [ ] **Step 1: Diff the reverted accent edits for reference**

Run: `git show 9580271 -- Apps/SeretTV/Shell/SettingsView.swift Apps/SeretTV/Auth/SignInView.swift Apps/SeretTV/Detail Apps/SeretTV/Playback Apps/SeretTV/Library/LibraryScreen.swift` and read each hunk. Re-apply the *intent* (swap ad-hoc colors → `Theme.Palette.gold`, add `CanvasBackground()`) onto current source. Where current code differs structurally, adapt by hand.

- [ ] **Step 2: Apply tab tint + browse canvas + gold pills**

In `LibraryShell.swift`, add `.tint(Theme.Palette.gold)` to the `TabView`. In `BrowseScreen.swift`, wrap the `Group` content in `ZStack { CanvasBackground(); ... }` and change the segment-picker tint from `.yellow`/`.gray` to `Theme.Palette.gold`/`.gray`.

- [ ] **Step 3: Apply wordmark sign-in + settings/detail/player accents** per Step 1's reference, file by file.

- [ ] **Step 4: Build**

Run: `xcodebuild -project Seret.xcodeproj -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`, 0 warnings.

- [ ] **Step 5: Sim-verify** — screenshot sign-in (wordmark), Settings, and a Detail screen; confirm gold accents + dark canvas.

- [ ] **Step 6: Commit**

```bash
git add Apps/SeretTV
git commit -m "feat(tvos): gold accents app-wide (tabs, canvas, pills, sign-in, settings, detail, player)"
```

---

## Task 6: tvOS Home rail + cards

**Why:** The Home tab needs tvOS-native (focusable, no `.pressable()`) rail + landscape progress card components. Mobile's versions use touch idioms; build tvOS equivalents.

**Files:**
- Create: `Apps/SeretTV/Home/HomeRail.swift`

- [ ] **Step 1: Create `HomeRail.swift`** with a titled rail, a gold progress bar, and a landscape progress card:

```swift
import DebridCore
import DebridUI
import SwiftUI

/// Thin gold progress capsule (resume fraction).
struct GoldProgressBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(Theme.Palette.gold)
                    .frame(width: max(0, min(1, fraction)) * g.size.width)
                    .goldGlow(6, opacity: 0.7)
            }
        }
        .frame(height: 6)
    }
}

/// 16:9 landscape card with resume progress — a focusable card button.
struct LandscapeProgressCard: View {
    let title: String
    let subtitle: String
    let imageURL: URL?
    let fraction: Double
    var width: CGFloat = 460

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottom) {
                AsyncImage(url: imageURL) { $0.resizable().aspectRatio(contentMode: .fill) }
                    placeholder: { Rectangle().fill(Theme.Palette.surface2) }
                    .frame(width: width, height: width * 9 / 16).clipped()
                GoldProgressBar(fraction: fraction).frame(width: width)
            }
            Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                .frame(width: width, alignment: .leading)
            if !subtitle.isEmpty {
                Text(subtitle).font(.caption).foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1).frame(width: width, alignment: .leading)
            }
        }
    }
}

/// A titled horizontal rail. Content is a row of focusable cards.
struct HomeRail<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.bold()).padding(.leading, 60)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 40) { content }
                    .padding(.horizontal, 60).padding(.vertical, 40)
            }
            .scrollClipDisabled()
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project Seret.xcodeproj -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`, 0 warnings.

- [ ] **Step 3: Commit**

```bash
git add Apps/SeretTV/Home/HomeRail.swift
git commit -m "feat(tvos): Home rail + landscape progress card + gold progress bar"
```

---

## Task 7: Home tab

**Files:**
- Create: `Apps/SeretTV/Home/HomeScreen.swift`
- Modify: `Apps/SeretTV/Shell/LibraryShell.swift`

- [ ] **Step 1: Create `HomeScreen.swift`** (tvOS adaptation of the mobile Home — focusable cards via `NavigationLink(value:)`/`.card`, full-bleed hero, reads shared `session.home`):

```swift
import DebridCore
import DebridUI
import SwiftUI

/// Home tab: featured hero (most recent Continue item) + Continue Watching + Recently Added,
/// composed on the shared `session.home`. Cards push library Detail.
struct HomeScreen: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        ZStack {
            CanvasBackground()
            content
        }
        .task { await rebuild() }
        .onChange(of: session.libraryStore?.movies) { _, _ in Task { await rebuild() } }
        .onChange(of: session.libraryStore?.shows) { _, _ in Task { await rebuild() } }
    }

    @ViewBuilder private var content: some View {
        if let home = session.home, !(home.continueWatching.isEmpty && home.recentlyAdded.isEmpty) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 50) {
                    hero(home)
                    if !home.continueWatching.isEmpty {
                        HomeRail(title: "Continue Watching") {
                            ForEach(home.continueWatching) { hi in
                                NavigationLink(value: hi.item) {
                                    LandscapeProgressCard(title: hi.item.title, subtitle: hi.subtitle,
                                                          imageURL: backdropURL(hi.item), fraction: hi.fraction)
                                }.buttonStyle(.card)
                            }
                        }
                    }
                    if !home.recentlyAdded.isEmpty {
                        HomeRail(title: "Recently Added") {
                            ForEach(home.recentlyAdded) { item in
                                NavigationLink(value: item) {
                                    posterCard(item)
                                }.buttonStyle(.card)
                            }
                        }
                    }
                }
                .padding(.vertical, 40)
            }
        } else {
            empty
        }
    }

    @ViewBuilder private func hero(_ home: HomeStore) -> some View {
        if let f = home.featured {
            NavigationLink(value: f.item) {
                ZStack(alignment: .bottomLeading) {
                    AsyncImage(url: backdropURL(f.item)) { $0.resizable().aspectRatio(contentMode: .fill) }
                        placeholder: { Rectangle().fill(Theme.Palette.surface1) }
                        .frame(height: 620).frame(maxWidth: .infinity).clipped()
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: Theme.Palette.canvas.opacity(0.7), location: 0.6),
                        .init(color: Theme.Palette.canvas, location: 1.0),
                    ], startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 14) {
                        Text(f.subtitle.isEmpty ? "Continue Watching" : "Continue · \(f.subtitle)")
                            .font(.caption.weight(.semibold)).tracking(2).foregroundStyle(Theme.Palette.gold)
                        Text(f.item.title).font(.system(size: 52, weight: .heavy))
                            .foregroundStyle(Theme.Palette.textPrimary).lineLimit(2)
                        HStack(spacing: 10) { Image(systemName: "play.fill"); Text("Resume") }
                            .font(.title3.weight(.semibold)).foregroundStyle(.black)
                            .padding(.vertical, 14).padding(.horizontal, 40)
                            .background(Theme.Palette.goldGradient, in: Capsule())
                            .goldGlow(16, opacity: 0.4)
                    }
                    .padding(60)
                }
            }
            .buttonStyle(.card)
        }
    }

    private func posterCard(_ item: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            AsyncImage(url: TMDBClient.imageURL(path: item.posterPath, size: "w500")) {
                $0.resizable().aspectRatio(contentMode: .fill)
            } placeholder: { Rectangle().fill(Theme.Palette.surface2) }
                .frame(width: 220, height: 330).clipped()
            Text(item.title).font(.callout.weight(.semibold)).lineLimit(1)
                .frame(width: 220, alignment: .leading)
        }
    }

    private var empty: some View {
        VStack(spacing: 18) {
            SeretMark(glow: false).frame(width: 90).opacity(0.5)
            Text("Nothing here yet").font(.title2).foregroundStyle(Theme.Palette.textSecondary)
            Text("Play something and it'll show up here.").font(.body)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func rebuild() async {
        guard let library = session.libraryStore, let home = session.home else { return }
        await home.rebuild(movies: library.movies, shows: library.shows)
    }

    private func backdropURL(_ i: MediaItem) -> URL? {
        TMDBClient.imageURL(path: i.backdropPath ?? i.posterPath, size: "w1280")
    }
}
```

- [ ] **Step 2: Add Home as the first tab in `LibraryShell.swift`**

Insert before the Movies tab inside the `TabView`:

```swift
Tab("Home", systemImage: "house") { HomeScreen() }
```

So the order is **Home · Movies · TV · My Library · Settings**. The existing `.task(id: session.libraryStore?.attempt ?? -1) { await session.libraryStore?.load() }` already populates the library that `HomeScreen.rebuild()` consumes.

- [ ] **Step 3: Build**

Run: `xcodebuild -project Seret.xcodeproj -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`, 0 warnings.

- [ ] **Step 4: Sim-verify** — sign in (owner's RD token if available; otherwise verify the empty/`SeretMark` state renders without crashing). Screenshot the Home tab; confirm hero + rails (or graceful empty state).

- [ ] **Step 5: Commit**

```bash
git add Apps/SeretTV/Home/HomeScreen.swift Apps/SeretTV/Shell/LibraryShell.swift
git commit -m "feat(tvos): Home tab — hero + Continue Watching + Recently Added"
```

---

## Task 8: Focus-reactive top hero on Movies/TV

**Why:** The headline feature — a full-bleed backdrop that crossfades to whatever poster the remote is focused on, with gold + סֶרֶט styling.

**Files:**
- Create: `Apps/SeretTV/Browse/HeroBanner.swift`
- Modify: `Apps/SeretTV/Browse/BrowseScreen.swift`

- [ ] **Step 1: Spike the focus mechanism (5 min, throwaway)**

In a scratch view, confirm focus reporting from inside a nested `ScrollView`/`LazyHStack` works via `.focused($focus)` per-tile + `.onChange(of: focus)`. If bindings don't propagate cleanly through the lazy stacks, fall back to a `FocusedValueKey` or the `PreferenceKey` below. Record which approach worked in the commit message. Delete the scratch view.

- [ ] **Step 2: Create `HeroBanner.swift`** — the hero view + a preference key for focus reporting:

```swift
import DebridCore
import DebridUI
import SwiftUI

/// Tiles publish their hit up to the hero via this preference when focused.
struct FocusedHitKey: PreferenceKey {
    static let defaultValue: SearchHit? = nil
    static func reduce(value: inout SearchHit?, nextValue: () -> SearchHit?) {
        if let next = nextValue() { value = next }
    }
}

/// Full-bleed backdrop hero. Crossfades when `hit` changes.
struct HeroBanner: View {
    let hit: SearchHit?
    var height: CGFloat = 620

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
            LinearGradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: Theme.Palette.canvas.opacity(0.75), location: 0.62),
                .init(color: Theme.Palette.canvas, location: 1.0),
            ], startPoint: .top, endPoint: .bottom)
            if let hit {
                VStack(alignment: .leading, spacing: 12) {
                    Text("סֶרֶט").font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Theme.Palette.gold)
                        .environment(\.layoutDirection, .rightToLeft)
                        .goldGlow(14, opacity: 0.5)
                    Text(hit.result.displayTitle).font(.system(size: 56, weight: .heavy))
                        .foregroundStyle(Theme.Palette.textPrimary).lineLimit(2)
                    if let overview = hit.result.overview, !overview.isEmpty {
                        Text(overview).font(.title3).foregroundStyle(Theme.Palette.textSecondary)
                            .lineLimit(2).frame(maxWidth: 1100, alignment: .leading)
                    }
                }
                .padding(60)
                .transition(.opacity)
                .id(hit.id)   // drive the crossfade on change
            }
        }
        .frame(height: height).frame(maxWidth: .infinity).clipped()
        .animation(.easeInOut(duration: 0.35), value: hit?.id)
    }

    @ViewBuilder private var backdrop: some View {
        let path = hit?.result.backdropPath ?? hit?.result.posterPath
        AsyncImage(url: TMDBClient.imageURL(path: path, size: "w1280")) {
            $0.resizable().aspectRatio(contentMode: .fill)
        } placeholder: { Rectangle().fill(Theme.Palette.surface1) }
            .id(hit?.id)
            .transition(.opacity)
    }
}
```

NOTE: confirm `TMDBSearchResult` exposes `backdropPath` and `overview`. If `backdropPath` is absent on the search model, use `posterPath` only and drop the `?? posterPath` (adjust during Step 4 build).

- [ ] **Step 3: Wire the hero + focus reporting into `BrowseScreen.swift`**

Add `@State private var featuredHit: SearchHit?`. Pin `HeroBanner(hit: featuredHit)` above the rails inside `loaded`/results, and collect the preference at the screen level:

```swift
// inside `rows` .loaded and inside resultsGrid container:
.onPreferenceChange(FocusedHitKey.self) { featuredHit = $0 ?? featuredHit }
```

Make `BrowseTile` publish on focus. Add to `BrowseTile`:

```swift
@FocusState private var focused: Bool
// on the NavigationLink:
.focused($focused)
.preference(key: FocusedHitKey.self, value: focused ? hit : nil)
```

Seed `featuredHit` with the first available hit when `.loaded` so the hero isn't blank before the user moves focus:

```swift
.onChange(of: browse.state) { _, s in
    if s == .loaded, featuredHit == nil { featuredHit = browse.rows.first?.hits.first }
}
```

Layout: in `.loaded`, the hero is the first child of the `LazyVStack` (above `segmentPicker`); rails scroll beneath it.

- [ ] **Step 4: Build**

Run: `xcodebuild -project Seret.xcodeproj -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`, 0 warnings. Fix any `backdropPath`/`overview` model mismatches here.

- [ ] **Step 5: Sim-verify the crossfade** — launch, focus the Movies feed, move the remote across posters, screenshot two different focused titles. Expected: hero backdrop + title + סֶרֶט crossfades to the focused poster.

- [ ] **Step 6: Commit**

```bash
git add Apps/SeretTV/Browse/HeroBanner.swift Apps/SeretTV/Browse/BrowseScreen.swift
git commit -m "feat(tvos): focus-reactive top hero banner on Movies/TV (crossfades to focused title)"
```

---

## Task 9: Full verification pass

- [ ] **Step 1: Package tests green**

Run: `cd Shared/DebridUI && swift test 2>&1 | tail -15` and `cd Shared/DebridCore && swift test 2>&1 | tail -5` (paths per repo layout).
Expected: all green, 0 failures.

- [ ] **Step 2: Clean app build, 0 warnings**

Run: `xcodebuild -project Seret.xcodeproj -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV' clean build 2>&1 | tail -8`
Expected: `** BUILD SUCCEEDED **`, 0 warnings.

- [ ] **Step 3: Capture the proof screenshots** — splash, Home (hero + rails), Movies feed populated (no spinner), Movies hero crossfading on focus. Share with the owner.

- [ ] **Step 4: Final summary commit (docs only, if any handoff notes)** — leave code commits as the per-task commits above. Do NOT push; ask the owner first.

---

## Self-Review

**Spec coverage:**
- Spinner fix → Task 1. ✓
- tvOS token strategy (local mirror) → Task 2. ✓
- Gold Glass skin (logo/wordmark/splash/accents) → Tasks 3, 4, 5. ✓
- Home tab (hero + Continue Watching + Recently Added) → Tasks 6, 7. ✓
- Focus-reactive top hero on Browse → Task 8. ✓
- Verification (tests + build + sim screenshots) → Task 9 (+ per-task sim checks). ✓
- Error handling (failure/retry, backdrop fallback, empty Home) → Task 1 (retry), Task 8 (`surface1` fallback), Task 7 (`empty`). ✓

**Placeholder scan:** No "TBD"/"handle edge cases" — each code step shows real code. The two model-shape unknowns (`backdropPath`/`overview` on `TMDBSearchResult`; XcodeGen glob) are flagged with an explicit resolve-at-build instruction rather than left vague.

**Type consistency:** `Theme.Palette.*`, `goldGlow(_:opacity:)`, `SeretHit`→`SearchHit`, `HomeStore.featured/continueWatching/recentlyAdded`, `DiscoverStore.load()/state/rows` all match the verified source. `LandscapeProgressCard`/`HomeRail`/`GoldProgressBar` defined in Task 6 and consumed in Task 7. `FocusedHitKey`/`HeroBanner` defined and consumed in Task 8.

**Risk follow-ups in-plan:** focus mechanism spiked first (Task 8 Step 1); reverted edits reconciled not cherry-picked (Tasks 2–5); tab-order change verified (Task 7 Step 4).
