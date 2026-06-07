# Seret Stage 2 — Slice C (app Search/Add UI) Implementation Plan

> REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Ship the **Search → Add** UI on both apps (`SeretTV` + `SeretMobile`): a Search tab → results grid → an Add screen offering **Get best · Add & Play · More versions**, for **movies and TV shows** (TV via a season/episode picker). Built on Slice A (engine) + Slice B (DebridUI `SearchStore`/`AddStore`).

**Scope (locked with owner 2026-06-07):** Movies **and** TV; **both** apps.

**Architecture:** add one shared orchestrator in `DebridUI` (`AddFlowStore`) that resolves a picked search result's TMDB details, forks movie vs. show, owns a per-target Slice-B `AddStore`, and builds the `PlaybackRequest` for Add & Play. The app targets only render + navigate. `SearchStore.results` becomes `[SearchHit]` so each hit carries its `MediaKind` (TMDB movie/TV ids don't share a namespace, so kind can't be inferred by id).

**Run/verify:**
- DebridUI: `swift test --package-path Shared/DebridUI` (host-free) + `swift build … | grep -i warning` (nothing).
- Apps: `xcodegen generate` then `xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build` and `-scheme SeretMobile -destination 'platform=iOS Simulator,name=iPhone 17' build` — **zero warnings**. (Sim screenshots + real search/add are **owner-pending**: needs his RD token signed in + the sim, exactly like every prior app slice.)

---

## C1 — DebridUI: `SearchHit`, `AddFlowStore`, PlaybackRequest builder, AppSession factory (TDD, inline)

### C1.1 — `SearchStore.results: [SearchHit]`
- `SearchHit { let result: TMDBSearchResult; let kind: MediaKind }`, `Identifiable` (`id = "\(kind.rawValue)-\(result.id)"`), `Equatable`.
- `SearchStore`: tag movie hits `.movie`, TV hits `.show`; merge + sort by `result.voteAverage` desc; expose `results: [SearchHit]`.
- Update `SearchStoreTests`: assertions move to `results.first?.result.id` / `.kind`.

### C1.2 — `AddFlowStore` (`@MainActor @Observable`, `Shared/DebridUI/Sources/DebridUI/Add/AddFlowStore.swift`)
Drives one picked title end to end.

State:
```swift
public enum Phase: Equatable { case resolving, movie, show, resolveFailed(String) }
```
Props: `phase`, display `title/year/posterPath/backdropPath/overview`, `originalLanguage`, `imdbID`;
for show: `seasons: [Int]`, `selectedSeason: Int?`, `episodes: [TMDBEpisodeDetails]` (current season), `selectedEpisode: Int?`;
`add: AddStore?` (the inner stream/add engine for the current target).

Init (injected seams — testable):
```swift
public init(hit: SearchHit, details: MediaDetailsProviding,
            streamSource: StreamSource, add: AddProviding)
```
Methods:
- `resolve()` — movie: `movieDetails` → set imdbID/originalLanguage/display, build inner `AddStore(imdbID, .movie, origLang, …)`, `phase = .movie`, then `add.loadStreams()`. show: `tvDetails` → imdbID/origLang/seasons (`1...numberOfSeasons`), `phase = .show`; auto-select season 1 + load its episodes. Failure (no imdbID, or throw) → `.resolveFailed`.
- `selectSeason(_:)` (show) — load `seasonEpisodes`; reset `selectedEpisode`/`add`.
- `selectEpisode(_:)` (show) — build inner `AddStore(imdbID, .series(season,episode), origLang, …)`, `add.loadStreams()`.
- `addBest()/add(stream:)` — delegate to inner `add`.
- `playbackRequest(from info: TorrentInfo) -> PlaybackRequest?` — `info.primaryVideoFile()` → `MediaSource(torrentID: info.id, fileID: file.id, restrictedLink: link, parsed: FilenameParser().parse(info.filename))`; `MediaItem(id: contentKey, kind:, title:, year:, sources:[src], seasons:[], tmdbID: hit.result.id, posterPath:, backdropPath:, overview:)`; movie label = `title`, contentKey = `tmdb:\(id)`; show label = `"\(title) — S\(s)·E\(e)"`, contentKey = `tmdb:\(id):s\(s)e\(e)`; `resumeAt: nil`. (Keys are tmdb-stable; library reconciliation on the next refresh is a known follow-up.)

TDD with `FakeDetails` (movie/tv/season `Result`s), reuse `FakeStreamSource`/`FakeAdd` shape (local to the test file). Cover: movie resolve→.movie + best loaded; show resolve→.show + seasons + season-1 episodes; selectEpisode loads streams; resolveFailed on missing imdbID; playbackRequest from a downloaded `TorrentInfo`.

### C1.3 — `AppSession` factory
```swift
public func makeAddFlow(for hit: SearchHit) -> AddFlowStore? {
    guard let detailsProvider, let streamSource, let addService else { return nil }
    return AddFlowStore(hit: hit, details: detailsProvider, streamSource: streamSource, add: addService)
}
```
(`detailsProvider`/`streamSource`/`addService` already composed in `enterSignedIn`.)

**Verify:** full DebridUI suite green, zero warnings. **Commit** `feat(ui): add SearchHit + AddFlowStore orchestrator + AppSession.makeAddFlow`.

---

## C2 — SeretTV Search + Add UI

Files (new under `Apps/SeretTV/`; project.yml globs the folder, no project.yml edit):
- `Search/SearchScreen.swift` — focusable search field (`@FocusState`, `.searchable` or a `TextField`) → debounced `session.searchStore.search(query:)` → states (idle/searching/empty/failed/results) → results grid of `SearchPosterCard` (reuse `PosterCard` look; `displayTitle` + poster via `TMDBClient.imageURL`); tapping a hit pushes the Add screen (value-nav: `navigationDestination(for: SearchHit.self)`).
- `Search/AddScreen.swift` — builds `AddFlowStore` via `session.makeAddFlow(for:)` in `@State`; `.task { await flow.resolve() }`. Backdrop/poster + title/overview. Movie: action row **Get best** (`addBest`) · **Add & Play** (`addBest` then on `.added` build request → push player) · **More versions** (expander: `flow.add.ranked` rows w/ quality chips + language badge; fallback flagged). Show: season picker + episode list (reuse `EpisodeRow` look) → on episode select, same action row. Add-progress overlay (adding/added/failed) with retry.
- Wire into `Shell/LibraryShell.swift`: add `Tab("Search", systemImage: "magnifyingglass") { SearchScreen() }` (4th tab, before Settings); add `.navigationDestination(for: SearchHit.self) { AddScreen(hit: $0) }`; Add & Play reuses the existing `.navigationDestination(for: PlaybackRequest.self)`.

**Verify:** `xcodegen generate` + `xcodebuild -scheme SeretTV … build` zero warnings. **Commit** `feat(tv): Search tab + Add screen (movies + TV)`.

---

## C3 — SeretMobile Search + Add UI

Files (new under `Apps/SeretMobile/`; Gold Glass design system — use `Theme.*`, `PosterCard`, `QualityChip`, `Buttons`):
- `Search/SearchScreen.swift` — `TextField` (gold-styled) → debounced `searchStore.search` → results in the adaptive grid (reuse `LibraryGrid`/`PosterCard` look). Tapping a hit presents the Add screen (via `AppRouter` — add `var addHit: SearchHit?` to `AppRouter`, present a `fullScreenCover`/sheet from `RootView` like `detail`, so rotation-safe).
- `Search/AddScreen.swift` — `AddFlowStore` in `@State`, `.task { resolve() }`. `DetailBackdrop` + title/overview. Movie: **Get best · Add & Play · More versions** (Gold buttons; versions list w/ `QualityChipRow` + language badge; fallback flagged). Show: season `Menu`/picker + episode list (reuse `ShowDetail` episode-row look) → action row. Add & Play presents `PlayerView` (mirror `DetailScreen`'s `PlaybackPresentation` + `session.makePlayer`). Add-progress overlay + retry.
- Wire into `Shell/MainShell.swift`: add `Section.search` (icon `magnifyingglass`) — a tab on iPhone `TabView` and a sidebar row on iPad; `sectionStack`/detail routes to `SearchScreen()`.
- Wire `Shell/RootView.swift` + `Shell/AppRouter.swift`: present the Add screen full-screen (rotation-safe), and the player within it.

**Verify:** `xcodebuild -scheme SeretMobile -destination 'platform=iOS Simulator,name=iPhone 17' build` zero warnings (+ iPad destination). **Commit** `feat(mobile): Search tab + Add screen (movies + TV)`.

---

## Slice C done — verification
- [ ] `swift test --package-path Shared/DebridUI` green; zero warnings.
- [ ] `swift test --package-path Packages/DebridCore` green (Slice A/B unaffected).
- [ ] `xcodebuild build` SeretTV + SeretMobile (iPhone + iPad) — zero warnings.
- [ ] ⚠️ **OWNER-PENDING:** sign in with RD token on the sim → search a title → Get best / Add & Play / More versions → screenshots (tvOS + iPhone + iPad). Real add+play can't be verified without the token (same DoD-pending pattern as every prior app slice).

## Deferred / follow-ups
- Add & Play `contentKey` is tmdb-stable but not yet reconciled to the library item's id on refresh (progress continuity) — fix when the rekey format is pinned.
- Cache-miss `RDAddError.notInstant` → keep/remove prompt + `TorrentsClient.deleteTorrent(id:)` (surfaced as a message for now).
- After a successful add, trigger `libraryStore.refresh()` so the title appears in the library.
- TV season-pack add (one torrent → many episodes) — currently per-episode `series(s,e)`.
