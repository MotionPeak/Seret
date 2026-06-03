# Seret tvOS — Library Grids (Plan 7b-i) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the signed-in Home stub with a tvOS sidebar (Movies · Shows · Settings) that renders the user's real Real-Debrid library as Movies/Shows poster grids with TMDB art, via the finished `DebridCore.LibraryService`.

**Architecture:** A thin `LibraryStore` (`@MainActor @Observable`) runs `LibraryService` cache-first (`loadCached()` instant) + background `refresh()` behind a testable `LibraryProviding` seam; `AppSession` composes the brain pipeline and vends the store on sign-in; a `NavigationSplitView` shell renders Movies/Shows as `PosterGrid`s. **App = UI + thin glue only; all RD/TMDB/parsing logic stays in `DebridCore`.**

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI (tvOS 18 — `NavigationSplitView`, `AsyncImage`, `.card` button style), the local `DebridCore` package, Swift Testing.

**Source spec:** [`docs/superpowers/specs/2026-06-03-tvos-library-grids-design.md`](../specs/2026-06-03-tvos-library-grids-design.md)
**Builds on:** Plan 7a (merged to `main`): `SeretTV` app, `AppSession`, `RootView`, `SignInView`, `SettingsView`.

---

## Plan-time facts (confirmed against the live source — do not guess)

- **Module name is `Seret`** (PRODUCT_NAME) → tests use `@testable import Seret`.
- **Branch:** work on `feat/tvos-library-grids` (already checked out; the 7b-i spec is committed there). Commit per task; **do not push without asking.** Scopes: `feat(tvos):` / `build(tvos):` / `test(tvos):` / `chore(tvos):`.
- **DebridCore API (exact):**
  - `LibraryService(torrents:builder:enricher:store:reconciler: = LibraryReconciler())`; `func loadCached() -> [MediaItem]?` (sync, instant); `func refresh() async throws -> [MediaItem]` (incremental). `LibraryService` is a `Sendable` struct.
  - `TorrentsClient(http: = .init(), tokens: any AccessTokenProviding)` — `AppSession.realDebrid` (a `RealDebridSession`) conforms to `AccessTokenProviding`.
  - `TMDBClient(apiKey: String, http: = .init())`; `static func imageURL(path: String?, size: String = "w500") -> URL?`.
  - `MetadataEnricher(tmdb: TMDBClient)`; `LibraryBuilder(parser: = .init())`; `LibrarySnapshotStore(directory: URL)`.
  - `MediaItem(id:kind:title:year:sources:seasons:tmdbID: = nil, posterPath: = nil, backdropPath: = nil, overview: = nil)` — public init; `Identifiable` (`id: String`); `kind: MediaKind` (`.movie`/`.show`). Fixtures can use empty `sources: []`, `seasons: []`.
- **Verification reality:** the *live* grid render needs a genuinely signed-in session (a real RD token in the sim Keychain). The app's device-code sign-in is rate-limited by RD (the 7a throttle), but **once signed in, the library loads via the RD *resource* API + transparent token refresh — NOT the throttled `device/code` endpoint.** So: sign in **once** when the throttle is cold, and every relaunch loads the library throttle-free. The `LibraryStore` unit test + build verify the code anytime.
- **The TMDB key is already in `Secrets.xcconfig`** (gitignored): `TMDB_API_KEY = …` (added during 7b kickoff).

---

## File Structure

**Create:**
- `Apps/SeretTV/Support/Secrets.swift` — reads `TMDBAPIKey` from Info.plist.
- `Apps/SeretTV/Library/LibraryProviding.swift` — the seam protocol + `LibraryService` conformance.
- `Apps/SeretTV/Library/LibraryStore.swift` — `@MainActor @Observable` store (cache-first + refresh + split + states).
- `Apps/SeretTV/Library/PosterCard.swift` — one focusable poster tile.
- `Apps/SeretTV/Library/PosterGrid.swift` — `LazyVGrid` of `PosterCard`s.
- `Apps/SeretTV/Library/LibraryScreen.swift` — state-aware wrapper (loading/empty/failed/grid) per tab.
- `Apps/SeretTV/Shell/LibraryShell.swift` — the `NavigationSplitView` (Movies · Shows · Settings).
- `Apps/SeretTVTests/LibraryStoreTests.swift` — the unit test + `FakeLibrary`.

**Modify:**
- `project.yml` — `SeretTV` target: managed Info.plist carrying `TMDBAPIKey`.
- `.gitignore` — add the generated `Apps/SeretTV/Info.plist`.
- `Apps/SeretTV/Shell/AppSession.swift` — vend a `LibraryStore` on sign-in (compose the pipeline).
- `Apps/SeretTV/Shell/RootView.swift` — `.signedIn` → `LibraryShell()`.
- `Apps/SeretTV/Shell/SettingsView.swift` — adjust for the sidebar context (drop the sheet's Done/dismiss).

**Remove:**
- `Apps/SeretTV/Shell/HomeStubView.swift`.

---

## Pre-flight

```bash
cd /Users/shaharsolomons/Documents/Code/Seret
git branch --show-current        # expect feat/tvos-library-grids
which xcodegen                   # 2.x
xcrun simctl list devices available | grep -i "Apple TV"   # use the listed name in -destination below
```

---

## Task 1: TMDB key plumbing (Secrets.xcconfig → Info.plist → runtime)

**Files:**
- Modify: `project.yml`, `.gitignore`
- Create: `Apps/SeretTV/Support/Secrets.swift`

- [ ] **Step 1: Switch `SeretTV` to a managed Info.plist carrying the TMDB key**

In `project.yml`, the `SeretTV` target's `settings.base` currently has `GENERATE_INFOPLIST_FILE: YES` and `INFOPLIST_KEY_CFBundleDisplayName: Seret`. Replace those two lines with an `info:` block at the target level (sibling of `settings`/`sources`), and drop both from `settings.base`. The result for the `SeretTV` target:

```yaml
  SeretTV:
    type: application
    platform: tvOS
    deploymentTarget: "18.0"
    sources:
      - path: Apps/SeretTV
    dependencies:
      - package: DebridCore
    info:
      path: Apps/SeretTV/Info.plist
      properties:
        CFBundleDisplayName: Seret
        TMDBAPIKey: "$(TMDB_API_KEY)"
    settings:
      base:
        PRODUCT_NAME: Seret
        PRODUCT_BUNDLE_IDENTIFIER: com.solomons.seret.tv
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
```

(XcodeGen sets `GENERATE_INFOPLIST_FILE: NO` automatically when `info:` is present and generates the plist at `info.path`, substituting `$(TMDB_API_KEY)` from `Secrets.xcconfig` at build time. The committed plist would only contain the *variable reference*, never the secret — so it's gitignored to avoid churn.)

- [ ] **Step 2: Gitignore the generated Info.plist**

Append to `.gitignore` (after the `Seret.xcodeproj/` line):

```gitignore
# XcodeGen-generated Info.plist (carries $(TMDB_API_KEY) ref; regenerated by `xcodegen generate`)
Apps/SeretTV/Info.plist
```

- [ ] **Step 3: Write the runtime reader — `Apps/SeretTV/Support/Secrets.swift`**

```swift
import Foundation

/// Build-time secrets surfaced into Info.plist from Secrets.xcconfig.
enum Secrets {
    /// TMDB v3 API key: `TMDB_API_KEY` (Secrets.xcconfig) → `TMDBAPIKey` (Info.plist) → here.
    static var tmdbAPIKey: String {
        let key = Bundle.main.object(forInfoDictionaryKey: "TMDBAPIKey") as? String ?? ""
        assert(!key.isEmpty,
               "TMDB_API_KEY missing — copy Secrets.example.xcconfig → Secrets.xcconfig and set it.")
        return key
    }
}
```

- [ ] **Step 4: Generate + build + verify the key reaches the bundle**

```bash
xcodegen generate
xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  -derivedDataPath /tmp/seret-dd build 2>&1 | grep -iE 'warning:|error:' | grep -v appintents || echo "NO CODE WARNINGS"
APP="$(find /tmp/seret-dd/Build/Products -name 'Seret.app' -maxdepth 3 | head -1)"
echo "TMDBAPIKey in built Info.plist: $(plutil -extract TMDBAPIKey raw "$APP/Info.plist")"
```
Expected: `NO CODE WARNINGS`, build succeeds, and `plutil` prints the **real key** (`dc31…`) — proving `Secrets.xcconfig → Info.plist` substitution works. If the build fails because the managed plist is missing a key the auto-generated one had, add it to `info.properties` (e.g. `CFBundleName: Seret`) and re-run.

- [ ] **Step 5: Commit**

```bash
git add project.yml .gitignore Apps/SeretTV/Support/Secrets.swift
git commit -m "build(tvos): surface TMDB_API_KEY via managed Info.plist → Secrets.tmdbAPIKey"
```

---

## Task 2: `LibraryProviding` seam + `LibraryStore` (TDD)

**Files:**
- Create: `Apps/SeretTV/Library/LibraryProviding.swift`, `Apps/SeretTV/Library/LibraryStore.swift`
- Test: `Apps/SeretTVTests/LibraryStoreTests.swift`

- [ ] **Step 1: Write the failing tests — `Apps/SeretTVTests/LibraryStoreTests.swift`**

```swift
import Testing
import Foundation
import DebridCore
@testable import Seret

private func movie(_ id: String, poster: String? = nil) -> MediaItem {
    MediaItem(id: id, kind: .movie, title: "Movie \(id)", year: 2024,
              sources: [], seasons: [], posterPath: poster)
}
private func show(_ id: String) -> MediaItem {
    MediaItem(id: id, kind: .show, title: "Show \(id)", year: 2023, sources: [], seasons: [])
}

private enum FakeError: Error { case boom }

/// Sendable seam double: values are fixed at init, so there's no concurrent mutation.
private final class FakeLibrary: LibraryProviding {
    let cached: [MediaItem]?
    let refreshResult: Result<[MediaItem], FakeError>
    init(cached: [MediaItem]?, refresh: Result<[MediaItem], FakeError>) {
        self.cached = cached
        self.refreshResult = refresh
    }
    func loadCached() -> [MediaItem]? { cached }
    func refresh() async throws -> [MediaItem] { try refreshResult.get() }
}

@MainActor
@Suite struct LibraryStoreTests {
    @Test func cacheFirstLoadsAndSplitsByKind() async {
        let store = LibraryStore(library: FakeLibrary(
            cached: [movie("1"), show("2")], refresh: .success([movie("1"), show("2")])))
        await store.load()
        #expect(store.state == .loaded)
        #expect(store.movies.map(\.id) == ["1"])
        #expect(store.shows.map(\.id) == ["2"])
    }

    @Test func refreshFromColdCacheLoads() async {
        let store = LibraryStore(library: FakeLibrary(cached: nil, refresh: .success([movie("1")])))
        await store.load()
        #expect(store.state == .loaded)
        #expect(store.movies.count == 1)
    }

    @Test func emptyLibraryIsEmptyState() async {
        let store = LibraryStore(library: FakeLibrary(cached: nil, refresh: .success([])))
        await store.load()
        #expect(store.state == .empty)
    }

    @Test func failureWithNoCacheIsFailed() async {
        let store = LibraryStore(library: FakeLibrary(cached: nil, refresh: .failure(.boom)))
        await store.load()
        guard case .failed = store.state else {
            #expect(Bool(false), "expected .failed, got \(store.state)"); return
        }
    }

    @Test func failureWithCacheKeepsShowingCache() async {
        let store = LibraryStore(library: FakeLibrary(cached: [movie("1")], refresh: .failure(.boom)))
        await store.load()
        #expect(store.state == .loaded)   // cache retained, not blanked
        #expect(store.movies.count == 1)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' test 2>&1 | tail -15
```
Expected: FAIL — `cannot find 'LibraryProviding'` / `cannot find 'LibraryStore'`.

- [ ] **Step 3: Write the seam — `Apps/SeretTV/Library/LibraryProviding.swift`**

```swift
import DebridCore

/// Thin seam over the brain's library API so `LibraryStore` is unit-testable without RD/TMDB.
/// Plain `Sendable` (NOT `@MainActor`): `LibraryService` is a Sendable struct with nonisolated
/// methods; the `@MainActor` store calls it across the boundary.
protocol LibraryProviding: Sendable {
    func loadCached() -> [MediaItem]?
    func refresh() async throws -> [MediaItem]
}

extension LibraryService: LibraryProviding {}
```

- [ ] **Step 4: Write the store — `Apps/SeretTV/Library/LibraryStore.swift`**

```swift
import DebridCore
import Observation

/// The library UI's single source of truth: cache-first instant render, then a background
/// refresh against RD. No RD/TMDB logic here — it delegates to `LibraryProviding`.
@MainActor
@Observable
final class LibraryStore {
    enum State: Equatable { case loading, loaded, empty, failed(String) }

    private(set) var state: State = .loading
    private(set) var movies: [MediaItem] = []
    private(set) var shows: [MediaItem] = []
    /// Bumped by `retry()`; drives the shell's `.task(id:)` so a retry re-runs `load()`.
    private(set) var attempt = 0

    private let library: LibraryProviding

    init(library: LibraryProviding) { self.library = library }

    func load() async {
        if let cached = library.loadCached() { apply(cached) } else { state = .loading }
        do {
            apply(try await library.refresh())
        } catch {
            // Keep any cache visible; only surface a failure when there's nothing to show.
            if movies.isEmpty, shows.isEmpty { state = .failed(Self.message(for: error)) }
        }
    }

    func retry() { attempt += 1 }

    private func apply(_ items: [MediaItem]) {
        movies = items.filter { $0.kind == .movie }
        shows = items.filter { $0.kind == .show }
        state = items.isEmpty ? .empty : .loaded
    }

    static func message(for error: Error) -> String {
        "Couldn't load your library. Check your connection and try again."
    }
}
```

- [ ] **Step 5: Run to verify it passes**

```bash
xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' test 2>&1 | grep -iE 'passed after|\*\* TEST' | tail -8
```
Expected: `** TEST SUCCEEDED **` (5 LibraryStore tests + the existing SignInModel/smoke tests pass).

- [ ] **Step 6: Commit**

```bash
git add Apps/SeretTV/Library/LibraryProviding.swift Apps/SeretTV/Library/LibraryStore.swift \
        Apps/SeretTVTests/LibraryStoreTests.swift
git commit -m "feat(tvos): LibraryStore (cache-first + refresh + split) over a testable LibraryProviding seam"
```

---

## Task 3: Compose the pipeline — `AppSession` vends a `LibraryStore` on sign-in

**Files:**
- Modify: `Apps/SeretTV/Shell/AppSession.swift`

- [ ] **Step 1: Add the store + pipeline composition to `AppSession`**

Apply these edits to `Apps/SeretTV/Shell/AppSession.swift`:

(a) Add `import Foundation` after `import DebridCore` (for `FileManager`/`URL`).

(b) Add a stored property after `signInModel`:

```swift
    /// The library store for the current signed-in episode (nil while signed out).
    private(set) var libraryStore: LibraryStore?
```

(c) Replace the body of `resolve()`'s two signed-in outcomes and `markSignedIn()` to route through a new `enterSignedIn()`. The full updated methods:

```swift
    func resolve() async {
        do {
            _ = try await realDebrid.validAccessToken()
            enterSignedIn()
        } catch RealDebridSessionError.notSignedIn {
            enterSignedOut()
        } catch HTTPError.status(_, _) {
            enterSignedOut()
        } catch {
            enterSignedIn()   // transport/offline with stored creds: optimistic
        }
    }

    func markSignedIn() {
        enterSignedIn()
        signInModel = nil
    }
```

(d) Add `libraryStore = nil` to `enterSignedOut()`:

```swift
    private func enterSignedOut() {
        signInModel = SignInModel(
            flow: LiveAuthFlow(auth: RealDebridAuthClient(), session: realDebrid),
            onSignedIn: { [weak self] in self?.markSignedIn() })
        libraryStore = nil
        state = .signedOut
    }
```

(e) Add the new `enterSignedIn()` + caches helper (after `enterSignedOut()`):

```swift
    /// Enter `.signedIn`, composing the DebridCore library pipeline once. Thin glue: the app
    /// assembles brain objects and reads a config value; no RD/TMDB logic lives here.
    private func enterSignedIn() {
        let tmdb = TMDBClient(apiKey: Secrets.tmdbAPIKey)
        let service = LibraryService(
            torrents: TorrentsClient(tokens: realDebrid),
            builder: LibraryBuilder(),
            enricher: MetadataEnricher(tmdb: tmdb),
            store: LibrarySnapshotStore(directory: Self.cachesDirectory))
        libraryStore = LibraryStore(library: service)
        state = .signedIn
    }

    private static var cachesDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }
```

- [ ] **Step 2: Build + run tests (no regressions)**

```bash
xcodegen generate
xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build 2>&1 | grep -iE 'warning:|error:' | grep -v appintents || echo "NO CODE WARNINGS"
xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' test 2>&1 | grep -iE '\*\* TEST' | tail -2
```
Expected: `NO CODE WARNINGS`; `** TEST SUCCEEDED **`. (The `isRunningTests` guard in `@main` means the host app never calls `resolve()`/`enterSignedIn()` under tests, so `Secrets.tmdbAPIKey`'s assert never fires in the suite.)

- [ ] **Step 3: Commit**

```bash
git add Apps/SeretTV/Shell/AppSession.swift
git commit -m "feat(tvos): AppSession composes the DebridCore library pipeline + vends LibraryStore on sign-in"
```

---

## Task 4: `PosterCard` + `PosterGrid`

**Files:**
- Create: `Apps/SeretTV/Library/PosterCard.swift`, `Apps/SeretTV/Library/PosterGrid.swift`

- [ ] **Step 1: Write `PosterCard` — `Apps/SeretTV/Library/PosterCard.swift`**

```swift
import DebridCore
import SwiftUI

/// One focusable poster tile (tvOS `.card` style gives the focus lift + ring).
/// Browse-only in 7b-i — selecting it is a no-op; Detail wires the action in 7b-ii.
struct PosterCard: View {
    let item: MediaItem

    var body: some View {
        Button(action: {}) {
            VStack(alignment: .leading, spacing: 10) {
                poster
                Text(item.title)
                    .font(.caption)
                    .lineLimit(1)
                    .frame(width: 220, alignment: .leading)
            }
        }
        .buttonStyle(.card)
    }

    @ViewBuilder private var poster: some View {
        if let url = TMDBClient.imageURL(path: item.posterPath, size: "w500") {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                placeholder
            }
            .frame(width: 220, height: 330)
            .clipped()
        } else {
            placeholder.frame(width: 220, height: 330)
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(.gray.opacity(0.3))
            .overlay {
                Text(item.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(12)
            }
    }
}
```

- [ ] **Step 2: Write `PosterGrid` — `Apps/SeretTV/Library/PosterGrid.swift`**

```swift
import DebridCore
import SwiftUI

/// A scrolling grid of poster cards. tvOS's focus engine handles poster scaling + the ring.
struct PosterGrid: View {
    let items: [MediaItem]

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 50)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 50) {
                ForEach(items) { PosterCard(item: $0) }
            }
            .padding(60)
        }
    }
}
```

- [ ] **Step 3: Build (zero warnings)**

```bash
xcodegen generate
xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build 2>&1 | grep -iE 'warning:|error:' | grep -v appintents || echo "NO CODE WARNINGS"
```
Expected: `NO CODE WARNINGS` and `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Apps/SeretTV/Library/PosterCard.swift Apps/SeretTV/Library/PosterGrid.swift
git commit -m "feat(tvos): PosterCard + PosterGrid (focusable TMDB poster tiles)"
```

---

## Task 5: `LibraryScreen` — state-aware tab content

**Files:**
- Create: `Apps/SeretTV/Library/LibraryScreen.swift`

- [ ] **Step 1: Write `LibraryScreen` — `Apps/SeretTV/Library/LibraryScreen.swift`**

```swift
import DebridCore
import SwiftUI

/// Renders one tab (Movies or Shows): the poster grid when loaded, otherwise the
/// loading / empty / failed state. `items` is the kind-filtered slice from the store;
/// `state` is the store's overall load state.
struct LibraryScreen: View {
    let title: String
    let items: [MediaItem]
    let state: LibraryStore.State
    let onRetry: () -> Void

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(title)
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            ProgressView("Loading your library…").font(.title3)
        case .failed(let msg):
            message(msg, systemImage: "exclamationmark.triangle", action: ("Try Again", onRetry))
        case .empty:
            message("Nothing in your Real‑Debrid library yet.", systemImage: "tray", action: nil)
        case .loaded:
            if items.isEmpty {
                message("No \(title.lowercased()) yet.", systemImage: "tray", action: nil)
            } else {
                PosterGrid(items: items)
            }
        }
    }

    private func message(_ text: String, systemImage: String,
                         action: (label: String, run: () -> Void)?) -> some View {
        VStack(spacing: 28) {
            Image(systemName: systemImage).font(.system(size: 64)).foregroundStyle(.secondary)
            Text(text).font(.title3).multilineTextAlignment(.center).frame(maxWidth: 700)
            if let action {
                Button(action.label, action: action.run).font(.title3)
            }
        }
    }
}
```

- [ ] **Step 2: Build (zero warnings)**

```bash
xcodegen generate
xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build 2>&1 | grep -iE 'warning:|error:' | grep -v appintents || echo "NO CODE WARNINGS"
```
Expected: `NO CODE WARNINGS` and `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Apps/SeretTV/Library/LibraryScreen.swift
git commit -m "feat(tvos): LibraryScreen — loading/empty/failed/grid per tab"
```

---

## Task 6: `LibraryShell` + wire into `RootView` (remove Home stub, adapt Settings)

**Files:**
- Create: `Apps/SeretTV/Shell/LibraryShell.swift`
- Modify: `Apps/SeretTV/Shell/RootView.swift`, `Apps/SeretTV/Shell/SettingsView.swift`
- Remove: `Apps/SeretTV/Shell/HomeStubView.swift`

- [ ] **Step 1: Write `LibraryShell` — `Apps/SeretTV/Shell/LibraryShell.swift`**

```swift
import SwiftUI

/// The signed-in root: a tvOS sidebar (Movies · Shows · Settings) over the library store.
struct LibraryShell: View {
    @Environment(AppSession.self) private var session
    @State private var selection: Section = .movies

    enum Section: Hashable { case movies, shows, settings }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Movies", systemImage: "film").tag(Section.movies)
                Label("Shows", systemImage: "tv").tag(Section.shows)
                Label("Settings", systemImage: "gearshape").tag(Section.settings)
            }
            .navigationTitle("Seret")
        } detail: {
            detail
        }
        // Loads once on appear; re-runs when the store's `retry()` bumps `attempt`.
        .task(id: session.libraryStore?.attempt ?? -1) {
            await session.libraryStore?.load()
        }
    }

    @ViewBuilder private var detail: some View {
        if let store = session.libraryStore {
            switch selection {
            case .movies:
                LibraryScreen(title: "Movies", items: store.movies,
                              state: store.state, onRetry: { store.retry() })
            case .shows:
                LibraryScreen(title: "Shows", items: store.shows,
                              state: store.state, onRetry: { store.retry() })
            case .settings:
                SettingsView()
            }
        }
    }
}
```

- [ ] **Step 2: Route `RootView.signedIn` to `LibraryShell`**

In `Apps/SeretTV/Shell/RootView.swift`, replace:

```swift
        case .signedIn:
            HomeStubView()
```
with:
```swift
        case .signedIn:
            LibraryShell()
```

- [ ] **Step 3: Adapt `SettingsView` for the sidebar (it's no longer a sheet)**

Replace the entire body of `Apps/SeretTV/Shell/SettingsView.swift` (drop `@Environment(\.dismiss)` and the Done button; Sign Out just signs out — `RootView` swaps the whole shell to `SignInView`):

```swift
import SwiftUI

/// Account screen (sidebar destination) + Sign Out. Signing out flips `AppSession` to
/// `.signedOut`, which routes `RootView` to a fresh `SignInView`.
struct SettingsView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        VStack(spacing: 40) {
            Text("Settings")
                .font(.largeTitle.bold())
            Text("Signed in to Real‑Debrid.")
                .font(.title3).foregroundStyle(.secondary)
            Button(role: .destructive) {
                Task { await session.signOut() }
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.title3)
            }
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Settings")
    }
}
```

- [ ] **Step 4: Remove the Home stub**

```bash
git rm Apps/SeretTV/Shell/HomeStubView.swift
```

- [ ] **Step 5: Generate, build (zero warnings), test**

```bash
xcodegen generate
xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build 2>&1 | grep -iE 'warning:|error:' | grep -v appintents || echo "NO CODE WARNINGS"
xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' test 2>&1 | grep -iE '\*\* TEST' | tail -2
```
Expected: `NO CODE WARNINGS`, `** BUILD SUCCEEDED **`, `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Apps/SeretTV/Shell/LibraryShell.swift Apps/SeretTV/Shell/RootView.swift Apps/SeretTV/Shell/SettingsView.swift
git commit -m "feat(tvos): NavigationSplitView library shell (Movies/Shows/Settings); replace Home stub"
```

---

## Task 7: tvOS simulator verification (live library + states)

No "done" claim without the screenshot of the real library (owner rule).

**Files:** none (verification only).

- [ ] **Step 1: Build + install + launch**

```bash
ATV=$(xcrun simctl list devices available | grep -m1 "Apple TV" | grep -oE '[0-9A-F-]{36}')
xcrun simctl boot "$ATV" 2>/dev/null || true
open -a Simulator
xcodebuild -scheme SeretTV -destination "platform=tvOS Simulator,id=$ATV" -derivedDataPath /tmp/seret-dd build
xcrun simctl install "$ATV" "$(find /tmp/seret-dd/Build/Products -name 'Seret.app' -maxdepth 3 | head -1)"
xcrun simctl launch "$ATV" com.solomons.seret.tv
```

- [ ] **Step 2: Sign in once (when RD's device-code throttle is cold)**

The sim has no stored RD credentials, so the app opens to sign-in. Complete **one** real device-code sign-in (code on screen → authorize at `real-debrid.com/device`). This persists the token to the sim Keychain. **If it shows "Real-Debrid is busy," the throttle is still warm — wait and retry once (do not hammer it).** After this, the library loads via the RD resource API + token refresh (NOT the throttled `device/code` endpoint).

- [ ] **Step 3: Screenshot the library**

```bash
sleep_loop() { for i in $(seq 1 12); do xcrun simctl spawn "$ATV" log show --last 1s >/dev/null 2>&1; done; }
sleep_loop
xcrun simctl io "$ATV" screenshot /tmp/seret-7bi-movies.png
```
Expected: the **Movies grid renders your real RD library with TMDB poster art** (or, on a genuinely empty account, the friendly empty state — also correct). Read the screenshot to confirm.

- [ ] **Step 4: Verify sidebar switching + Settings/Sign Out**

Drive the sim (Simulator frontmost; arrow keys move focus, Return selects): focus the sidebar, select **Shows** → screenshot (`/tmp/seret-7bi-shows.png`); select **Settings** → **Sign Out** → confirm it returns to the sign-in screen (`/tmp/seret-7bi-signout.png`).

- [ ] **Step 5: Final guardrails**

```bash
xcodebuild -scheme SeretTV -destination "platform=tvOS Simulator,id=$ATV" build 2>&1 | grep -iE 'warning:' | grep -v appintents || echo "ZERO WARNINGS"
swift test --package-path Packages/DebridCore 2>&1 | tail -2
grep -rnE 'URLSession|api\.real-debrid|themoviedb|JSONDecoder\(\)\.decode' Apps/SeretTV || echo "NO NETWORKING/PARSING IN APP TARGET"
```
Expected: `ZERO WARNINGS`; DebridCore suite passes; `NO NETWORKING/PARSING IN APP TARGET` (the one architectural rule holds — the app only calls `DebridCore` + `TMDBClient.imageURL`, which is a pure URL builder, not networking).

- [ ] **Step 6: Present evidence to the owner** — the Movies/Shows screenshots + guardrail output. (Pushing the branch is the owner's call — ask.)

---

## Definition of Done — 7b-i

- [ ] `xcodegen generate` + `xcodebuild` succeed, **zero warnings**.
- [ ] Signed-in app shows a **sidebar (Movies · Shows · Settings)** landing on Movies; Settings → Sign Out returns to sign-in.
- [ ] The **real RD library renders as Movies/Shows poster grids with TMDB art** (screenshot); warm relaunch is instant via `loadCached()`.
- [ ] Loading / empty / failed states behave per the spec; one `LibraryStore` unit test green; `DebridCore` tests still green.
- [ ] **No networking/RD/TMDB/parsing logic in the app target.**
- [ ] TMDB key flows `Secrets.xcconfig` → Info.plist → runtime; **no secret committed** (`Secrets.xcconfig` + generated `Info.plist` gitignored).

---

## Self-review notes

- **Spec coverage:** §3.1 nav shell → Task 6; §3.2 LibraryStore + seam → Task 2; §3.3 pipeline composition → Task 3; §3.4 TMDB key → Task 1; §3.5 image loading → Task 4 (`AsyncImage` + `TMDBClient.imageURL`); §3.6 grid screens → Tasks 4–5; §3.7 states → Task 5; §7 testing → Tasks 2 + 7. All DoD items mapped.
- **Type consistency:** `LibraryProviding.loadCached()/refresh()`, `LibraryStore.State`/`movies`/`shows`/`state`/`attempt`/`load()`/`retry()`, `LibraryScreen(title:items:state:onRetry:)`, `LibraryShell.Section`, `Secrets.tmdbAPIKey`, and `AppSession.libraryStore`/`enterSignedIn()` are used identically everywhere they appear. `MediaItem(...)` and `TMDBClient.imageURL(path:size:)` match the confirmed source.
- **No DebridCore change** (contrast 7a). The library pipeline already exists; 7b-i is composition + SwiftUI.
- **Known deferral:** poster selection is a no-op (Detail = 7b-ii); the live grid screenshot is gated on a real sign-in (RD throttle), exactly like 7a's — the unit test + build verify the code independently.
