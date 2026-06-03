# Seret tvOS — Library Grids (Plan 7b-i)

**Status:** Draft for review
**Date:** 2026-06-03
**Owner:** Shahar Solomons
**Scope of this document:** Plan **7b-i** — the first library UI. Replaces 7a's signed-in Home stub with a **sidebar nav shell** (Movies · Shows · Settings) that renders the user's real Real-Debrid library as **Movies and Shows poster grids**, wired through the finished `DebridCore.LibraryService` with TMDB art. The **Detail** screen + **Show/episodes** drill-down are **7b-ii** (separate slice). The player is **7c**.
**Parent spec:** [`2026-06-02-seret-design.md`](2026-06-02-seret-design.md) (§6 screens, §5.5 library & persistence, §7 build-library flow). **Builds on:** [`2026-06-03-tvos-app-foundation-signin-design.md`](2026-06-03-tvos-app-foundation-signin-design.md) (the `SeretTV` app, `AppSession`, `RootView`, sign-in — all merged to `main`).

---

## 1. Summary

7a put the `SeretTV` app + device-code sign-in on the `DebridCore` brain. **7b-i puts the first real library UI on it:** after sign-in, a tvOS `NavigationSplitView` sidebar (**Movies · Shows · Settings**) lands on a **Movies grid** of the user's RD library rendered with **TMDB poster art**; the **Shows grid** likewise.

This is the **first time the RD → group → enrich (TMDB) → render pipeline runs end-to-end against the live account** — every layer was mocked until now. Proving that pipeline live (and seeing the real library with art) is the slice's whole point.

**The one architectural rule holds:** no RD/TMDB/parsing logic in the app target — `DebridCore.LibraryService` does all of it. 7b-i is the sidebar shell + two grids + a thin observable `LibraryStore` view-model + the TMDB-key config plumbing.

---

## 2. Scope of 7b-i

**In:**
- **Nav shell** (tvOS `NavigationSplitView`): sidebar **Movies · Shows · Settings**, landing on Movies. Replaces 7a's `HomeStubView` as the `.signedIn` root; **Settings** is the existing 7a screen (with Sign Out).
- **`LibraryStore`** (`@MainActor @Observable`): runs `LibraryService` cache-first (`loadCached()` → instant) + background `refresh()`; exposes `movies`/`shows` (the library split by `MediaItem.kind`) + a coarse `state`.
- **Composition root:** assemble `TMDBClient(apiKey:)` + `TorrentsClient(tokens:)` + `MetadataEnricher` + `LibraryBuilder` + `LibrarySnapshotStore` → `LibraryService`, built once on sign-in.
- **TMDB v3 API key** plumbing: `Secrets.xcconfig` `TMDB_API_KEY` → an XcodeGen-managed `Info.plist` entry → read once at runtime → handed to `TMDBClient`.
- **`PosterGrid` + `PosterCard`** SwiftUI components (focusable poster art + title/year fallback), driven by `[MediaItem]`; `AsyncImage` for poster loading via `TMDBClient.imageURL`.
- **Loading / empty / refresh-error** states.
- One **`LibraryStore` unit test** (app target, against a fake library seam) + tvOS-simulator verification (the real library renders with posters).

**Out (later slices / stages):**
- **Detail screen** (full-bleed backdrop, Resume/Play, synopsis, quality/source chips) and **Show/episodes** drill-down → **7b-ii**. In 7b-i, selecting a poster is a **no-op** (grids are browse-only).
- **Home** (featured hero + Continue Watching + Recently Added) → a later slice — Continue Watching needs 7c playback history, and Recently Added needs an `addedAt` date that `MediaItem` doesn't yet carry.
- **Search / Add** → Stage 2.
- **Player / VLCKit** → 7c.

---

## 3. Design

### 3.1 Nav shell — `RootView.signedIn` → `LibraryShell`

`RootView`'s `.signedIn` branch swaps `HomeStubView()` for a new `LibraryShell`:
- A tvOS `NavigationSplitView` with a **sidebar** listing a `Section` enum: `.movies`, `.shows`, `.settings`. Default selection `.movies`.
- The **detail column** shows the selected screen: `MoviesScreen` / `ShowsScreen` (both `PosterGrid` over the store's `movies`/`shows`), or the existing `SettingsView`.
- `Settings` keeps 7a's Sign Out; signing out flips `AppSession` back to `.signedOut` → `RootView` routes to `SignInView` (unchanged from 7a).

`HomeStubView` is removed (its job is done). No full-bleed/immersive layout yet (that arrives with Detail/Player).

### 3.2 `LibraryStore` (`@MainActor @Observable`) + a testable seam

A single observable store is the UI's source of truth, mirroring 7a's `SignInModel`/`AuthFlow` pattern:

```swift
// Plain Sendable seam (NOT @MainActor): LibraryService is a Sendable struct with
// nonisolated methods; the @MainActor LibraryStore calls it across the boundary.
protocol LibraryProviding: Sendable {
    func loadCached() -> [MediaItem]?
    func refresh() async throws -> [MediaItem]
}
// LibraryService already has these exact signatures → conforms via an app-side
// `extension LibraryService: LibraryProviding {}`.

@MainActor @Observable final class LibraryStore {
    enum State: Equatable { case loading, loaded, empty, failed(String) }
    private(set) var state: State = .loading
    private(set) var movies: [MediaItem] = []
    private(set) var shows: [MediaItem] = []
    private let library: LibraryProviding
    init(library: LibraryProviding) { self.library = library }

    func load() async { /* cache-first then refresh — see §5 */ }
    func retry() { /* re-run load() via a bumped task id, like SignInModel.attempt */ }
}
```

- `load()`: `loadCached()` → if non-nil, `apply(items)` immediately (instant render); then `try await refresh()` in the same `Task` → `apply(updated)`. If `refresh()` throws **and** there was no cache → `.failed`; if it throws but a cache is showing → keep the cache + a subtle retry affordance.
- `apply(_:)`: split by `kind` into `movies`/`shows`; `state = items.isEmpty ? .empty : .loaded`.
- The `LibraryProviding` seam keeps the store unit-testable with a `FakeLibrary` (no RD/TMDB/network), exactly as `FakeAuthFlow` did for `SignInModel`.

### 3.3 Pipeline composition (the brain wiring)

`AppSession` builds **one** `LibraryStore` when it enters the signed-in state (vended like `signInModel`, dropped on sign-out), assembling the brain:

```swift
let tmdb = TMDBClient(apiKey: Secrets.tmdbAPIKey)
let torrents = TorrentsClient(tokens: realDebrid)        // realDebrid is AccessTokenProviding
let service = LibraryService(torrents: torrents,
                             builder: LibraryBuilder(),
                             enricher: MetadataEnricher(tmdb: tmdb),
                             store: LibrarySnapshotStore(directory: cachesDirectory))
// LibraryStore(library: service)   // via the LibraryProviding conformance
```

`cachesDirectory` = the app's Caches dir (`FileManager.default.url(for: .cachesDirectory, …)`). This is thin glue — the app assembles brain objects and reads a config value; it contains no RD/TMDB logic.

### 3.4 TMDB key wiring (config → runtime)

The v3 key lives in `Secrets.xcconfig` (gitignored, already populated): `TMDB_API_KEY = …`. To reach runtime:
- **`project.yml`:** switch the `SeretTV` target from `GENERATE_INFOPLIST_FILE: YES` to an **XcodeGen-managed `Info.plist`** via the target's `info:` block (`path:` + `properties:`), carrying the existing keys (`CFBundleDisplayName`, the tvOS app-icon/Top-Shelf settings stay build-settings) **plus** `TMDBAPIKey: $(TMDB_API_KEY)`. The build substitutes the xcconfig value into the generated plist.
- **Runtime:** a small app-side `enum Secrets { static var tmdbAPIKey: String { Bundle.main.object(forInfoDictionaryKey: "TMDBAPIKey") as? String ?? "" } }`. A missing/empty key is surfaced loudly in DEBUG (assertion + on-screen "TMDB key missing" state) so it's caught immediately, never silently shipping blank art.

This is the same Secrets mechanism 7a proved (configFiles → build settings); 7b-i just surfaces one value to runtime. No secret is committed (the key stays in the gitignored xcconfig; `Secrets.example.xcconfig` documents the name).

### 3.5 Image loading

Poster/backdrop URLs come from `TMDBClient.imageURL(path:size:)` (a pure static helper). Grids use `w500` posters. SwiftUI **`AsyncImage`** loads them — it rides `URLCache` for transparent disk/memory caching, which is enough for 7b-i's scroll. A `PosterCard` shows the art, or a graceful **title + year placeholder** card when `posterPath` is nil or the load fails (no broken-image affordance). (A bespoke prefetching image cache is a possible later optimization — out of scope here.)

### 3.6 Grid screens — `PosterGrid` + `PosterCard`

- **`PosterCard(item:)`** — a focusable poster tile: `AsyncImage` poster (2:3) with the title/year placeholder fallback, title label beneath. tvOS's focus engine provides the poster **scale + focus ring** natively (the card is a `Button`/`.focusable`). In 7b-i the button action is empty (browse-only); 7b-ii wires it to Detail.
- **`PosterGrid(items:)`** — a `ScrollView` + `LazyVGrid` of `PosterCard`s (adaptive columns sized for tvOS posters). Used by both `MoviesScreen(items: store.movies)` and `ShowsScreen(items: store.shows)`.
- Empty/loading/error are rendered by the screen based on `store.state` (a shared `LibraryStateView` for the non-content states).

### 3.7 States (per `LibraryStore.state`)

- **`.loading`** (cold first run, no cache) → a simple centered progress view.
- **`.loaded`** → the grid.
- **`.empty`** (RD account has no video content) → a friendly first-run message ("Nothing in your Real-Debrid library yet — add content and pull to refresh", phrased for tvOS; no pull gesture — see refresh below).
- **`.failed(message)`** → if no cache, a message + **Try Again** (re-runs `load()`); if a cache is showing, the grid stays and a subtle banner/retry appears instead.

**Refresh affordance:** `load()` runs automatically when the shell first appears. A manual refresh (tvOS has no pull-to-refresh) is a small **Refresh** control in the sidebar or a Play/Menu-button affordance — exact placement decided at plan time; auto-on-appear is the baseline.

---

## 4. The `DebridCore` API this consumes (confirmed against source)

- `LibraryService(torrents:builder:enricher:store:reconciler:)`; `loadCached() -> [MediaItem]?` (sync, instant, offline); `refresh() async throws -> [MediaItem]` (incremental — only new content hits TMDB; throws on RD/network failure).
- `TorrentsClient(http: = .init(), tokens: any AccessTokenProviding)` — `AppSession.realDebrid` (a `RealDebridSession`) conforms.
- `TMDBClient(apiKey: String, http: = .init())`; `static func imageURL(path: String?, size: String = "w500") -> URL?`.
- `MetadataEnricher(tmdb: TMDBClient)`; `LibraryBuilder(parser: = .init())`; `LibrarySnapshotStore(directory: URL)`.
- `MediaItem { id, kind: MediaKind(.movie/.show), title, year: Int?, sources, seasons, tmdbID: Int?, posterPath: String?, backdropPath: String?, overview: String? }` — `Identifiable`, `Sendable`.

No `DebridCore` change is required for 7b-i. (Contrast 7a, which added one method.)

---

## 5. Key flow

```
sign-in (7a) → AppSession state = .signedIn
   → RootView shows LibraryShell, which reads AppSession's LibraryStore
   → LibraryStore.load():
        loadCached()  → [MediaItem]? → if present: render grids INSTANTLY
        refresh()     → (background) reconcile vs RD; only new items hit TMDB; persist
                      → apply(updated): split by kind → movies / shows; state = .loaded/.empty
   → sidebar: Movies (default) / Shows / Settings
   → poster focus = tvOS scale+ring; selecting a poster = no-op in 7b-i (Detail = 7b-ii)
Settings → Sign Out (7a) → .signedOut → SignInView
```

---

## 6. Error handling & edge cases

- **Empty RD library** → `.empty` first-run message (correct, not an error). Verifies fine even on an empty account.
- **Refresh fails (RD/network)** with a cache present → keep showing the cache + a subtle retry; never blank the library.
- **Refresh fails with no cache** → `.failed` + Try Again.
- **No TMDB match for an item** → `MediaItem` keeps the parsed title; the card shows the title/year placeholder. Never blocks the grid.
- **Offline with a cache** → `loadCached()` renders read-only; `refresh()` throws and is swallowed (cache stays).
- **Missing/empty TMDB key** → loud DEBUG assertion + an on-screen "TMDB key missing" state (so it can't silently ship blank art).
- **RD device-code throttle** is a 7a/sign-in concern, not here (7b-i runs only when already signed in). Library calls use the resource API + a valid token.
- **Never log** the RD token or unrestricted URLs (none are resolved here anyway — unrestrict is a play-time/7c concern).

---

## 7. Testing & verification

- **Unit (app target):** one `LibraryStore` test driving the state machine against a `FakeLibrary` (conforming `LibraryProviding`) — cache-first (`loadCached` non-nil → instant `.loaded`, split by kind), refresh updates the items, and a refresh-failure-with-cache keeps `.loaded`. Library/RD/TMDB logic itself is already covered in `DebridCore`; we don't re-test it.
- **`DebridCore` suite stays green** (`swift test --package-path Packages/DebridCore`) — unchanged by 7b-i.
- **Zero warnings:** `xcodebuild … build` prints no compiler warnings (the benign `appintentsmetadataprocessor` note excepted).
- **Simulator (source of truth):** launch the signed-in app in the tvOS simulator → the **real RD library renders as Movies/Shows poster grids with real TMDB art** → screenshot. Exercise sidebar switching (Movies ↔ Shows ↔ Settings) and Sign Out. **No "done" claim without the screenshot** (owner rule).
  - *Prereq:* the RD account must hold video content to see a populated grid (the owner's DMM/Plex-on-RD account does). An empty account verifies the `.empty` state, which is also correct.
  - *Note:* avoid the 7a device-code throttle — sign in once; 7b-i's library calls are a different, unthrottled endpoint.

---

## 8. Definition of Done — 7b-i

- [ ] `xcodegen generate` + `xcodebuild` for `SeretTV` succeed, **zero warnings**.
- [ ] Signed-in app shows a **sidebar (Movies · Shows · Settings)** landing on Movies; Settings/Sign Out still work.
- [ ] The **real RD library renders as Movies + Shows poster grids with TMDB art** (screenshot); `loadCached()` makes a warm relaunch instant.
- [ ] Loading / empty / refresh-error states behave per §3.7 / §6.
- [ ] One `LibraryStore` unit test green; `DebridCore` tests still green; **no networking/RD/TMDB/parsing logic in the app target** (the one architectural rule).
- [ ] TMDB key flows `Secrets.xcconfig` → Info.plist → runtime → `TMDBClient`; **no secret committed** (`Secrets.xcconfig` gitignored; `Secrets.example.xcconfig` documents `TMDB_API_KEY`).

---

## 9. Open questions / deferred

- **Poster selection / Detail** — a no-op in 7b-i; wired to the Detail screen in **7b-ii**.
- **Home** (hero + Continue Watching + Recently Added) — a later slice; needs 7c watch-history and an `addedAt` on `MediaItem` (a small future `DebridCore` add) for "Recently Added" ordering.
- **Manual refresh placement** on tvOS (sidebar control vs a Menu-button affordance) — settled at plan time; auto-on-appear is the baseline.
- **Image caching** — `AsyncImage` + `URLCache` for now; a bespoke prefetch cache is a possible later polish if grid scrolling needs it.
- **`Info.plist` migration** — moving `SeretTV` from `GENERATE_INFOPLIST_FILE` to an XcodeGen-managed plist must re-carry the keys 7a relied on (display name, app-icon name); confirmed at plan time against the 7a `project.yml`.
