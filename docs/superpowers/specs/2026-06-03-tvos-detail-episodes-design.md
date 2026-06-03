# Seret tvOS — Library Drill-Down: Detail + Episodes (Plan 7b-ii)

**Status:** Draft for review
**Date:** 2026-06-03
**Owner:** Shahar Solomons
**Scope of this document:** Plan **7b-ii** — the library drill-down. Selecting a poster (a **no-op** in 7b-i) opens a **Detail** screen: a **backdrop-forward** hero with Play/Resume, synopsis, and quality/source chips. **Movies** get a **Versions** list; **shows** get a **season picker** + a **vertical episode list** (still · title · synopsis · watch-progress). Rich metadata (backdrop, runtime, genres, episode names/stills) is fetched **on-demand from TMDB and cached for the session** — the saved library snapshot is **untouched**. Play hands a `PlaybackRequest` to a **placeholder** screen that **Plan 7c** replaces with the real VLCKit player. **Mark Watched/Unwatched** writes `WatchProgress`.
**Parent spec:** [`2026-06-02-seret-design.md`](2026-06-02-seret-design.md) (§6 screens, §5.5 library & persistence). **Builds on:** [`2026-06-03-tvos-library-grids-design.md`](2026-06-03-tvos-library-grids-design.md) (7b-i grids — merged) and [`2026-06-03-tvos-app-foundation-signin-design.md`](2026-06-03-tvos-app-foundation-signin-design.md) (7a app/`AppSession`/`RootView` — merged).

---

## 1. Summary

7b-i renders the Real-Debrid library as Movies/Shows poster grids; selecting a poster does nothing. 7b-ii makes the posters open. A `DetailView` (pushed onto a `NavigationStack` inside the split-view detail column) renders **instantly** from the already-cached `MediaItem`, then asynchronously enriches itself from TMDB — a **backdrop-forward** hero for the cinematic "Plex, not Zurg" feel. Movies expose every quality source as a **Versions** list (best plays by default, ranked by a pure helper in the brain). Shows expose a focusable **season picker** and a **vertical episode list** with real episode titles, stills, synopses, and per-episode **watch-progress bars**. Play/Resume builds a `PlaybackRequest` and routes to a placeholder — the clean seam Plan 7c fills with VLCKit. Because the player doesn't exist yet, **Mark Watched/Unwatched** gives the watch-progress UI a real write path (and makes it verifiable in the simulator today).

This slice is **UI-led**. The only brain changes are small, pure, and reusable: one new read-only TMDB endpoint, a source-quality ranker, and `Hashable` conformances for value-based navigation. No change to persistence, the snapshot cache, or the library pipeline.

---

## 2. Scope of 7b-ii

**In:**
- **Navigation:** wrap each grid screen in a `NavigationStack`; `PosterCard` becomes a value link (pushes its `MediaItem`); `.navigationDestination(for: MediaItem.self)` → `DetailView`, `.navigationDestination(for: PlaybackRequest.self)` → the placeholder player. Settings/sign-out shell from 7b-i is unchanged.
- **`DetailStore`** (`@MainActor @Observable`): instant base render from `MediaItem`, then on-demand rich fetch + watch-state load; silent graceful degradation — mirrors 7b-i's `LibraryStore`.
- **`MovieDetailView`:** backdrop hero, year · runtime · genres, overview, quality chips (from `MediaSource.parsed`), **Versions** list (auto-best default), Play/Resume, Mark Watched.
- **`ShowDetailView` + `EpisodeRow`:** backdrop hero, focusable **season pill picker**, **vertical episode list** (still · `N · Title` · one-line synopsis · progress bar · watched ✓), per-episode Play, per-episode Mark Watched; hero primary action targets the next in-progress/unwatched episode.
- **On-demand rich metadata** via existing `TMDBClient.movieDetails`/`tvDetails` (backdrop, runtime, genres) + **one new** `tvSeasonDetails(tvID:season:)` (episode names/stills/synopses), cached per session in the store.
- **Source ranker** (pure, in `DebridCore`): `bestSource` + `versions` over `[MediaSource]`.
- **`Hashable`** on `MediaKind`/`MediaSource`/`Episode`/`Season`/`MediaItem` (additive; enables value-based navigation).
- **Watch progress:** read via `WatchProgressStore.progress(forContentKey:)` to drive bars + Resume; **Mark Watched/Unwatched** via `record(...)`.
- **`PlaybackRequest`** seam + **`PlayerPlaceholderView`** (renders the resolved intent; 7c replaces it).
- **Composition:** `AppSession` vends a `MediaDetailsProviding` + the **shared** `WatchProgressStore`.
- **Tests** (brain + app-hosted) + **tvOS-simulator verification** (Movie + Show Detail screenshots).

**Out (later slices / stages):**
- **Real playback** — unrestrict-at-play-time, VLCKit `VideoPlayerEngine`, on-demand subtitles, resume-write — → **7c**. In 7b-ii, Play routes to a placeholder; nothing is unrestricted.
- **Persisting** backdrops / episode metadata into `LibrarySnapshot` (instant + offline rich data) → a later **"enrichment v2"** plan. 7b-ii keeps the saved cache untouched and re-fetches per session.
- **Home** (hero + Continue Watching + Recently Added) and **Search / Add** → later / Stage 2.

---

## 3. Design

### 3.1 Navigation — grid → Detail → placeholder (value-based `NavigationStack`)

Each grid screen (`MoviesScreen`/`ShowsScreen`) is wrapped in a `NavigationStack`. `PosterCard`'s body changes from `Button(action: {})` to `NavigationLink(value: item) { … }.buttonStyle(.card)` (keeps the tvOS focus lift/ring). The stack carries two destinations:

```swift
.navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
.navigationDestination(for: PlaybackRequest.self) { PlayerPlaceholderView(request: $0) }
```

Value-based navigation requires the pushed values to be `Hashable` (see §3.5 / §4). The split-view sidebar (Movies · Shows · Settings) is unchanged; only the detail column gains the stack.

### 3.2 `DetailStore` (`@MainActor @Observable`) + a testable seam

One observable store per opened title, mirroring 7b-i's `LibraryStore` + `LibraryProviding` pattern:

```swift
// Plain Sendable seam (NOT @MainActor) — TMDBClient is a Sendable struct.
protocol MediaDetailsProviding: Sendable {
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails]
}

struct TMDBDetailsService: MediaDetailsProviding { /* wraps TMDBClient */ }

@MainActor @Observable
final class DetailStore {
    enum RichState: Equatable { case idle, loading, loaded, failed }

    let item: MediaItem
    // Rich layer (nil/empty until loaded; UI falls back to MediaItem + poster):
    private(set) var richState: RichState = .idle
    private(set) var backdropPath: String?
    private(set) var runtime: Int?            // movies
    private(set) var genres: [String] = []
    private(set) var overview: String?        // details.overview ?? item.overview
    // Shows:
    private(set) var selectedSeason: Int
    private(set) var episodeMeta: [Int: [Int: TMDBEpisodeDetails]] = [:]  // season → epNo → meta
    // Watch (contentKey → state); empty is normal until 7c / a manual mark:
    private(set) var watch: [String: WatchState] = [:]

    var versions: [MediaSource] { item.sources.bestFirst() }   // movies
    var bestSource: MediaSource? { item.sources.best }

    init(item: MediaItem, details: MediaDetailsProviding, watch: WatchProgressStore)
    func load() async                                  // rich details + watch states
    func selectSeason(_ n: Int) async                  // lazy-fetch that season's episode meta
    func setWatched(_ watched: Bool, contentKey: String, source: MediaSource) async
    func playRequest(source: MediaSource, episode: Episode?) -> PlaybackRequest
}
```

`load()` renders base immediately (the view reads `item` directly), sets `richState = .loading`, then fetches details by `kind`. Failure → `richState = .failed` but the screen keeps showing base info (no error wall) — the 7b-i resilience contract.

### 3.3 Rich metadata: on-demand fetch + session cache

- **Movie:** `movieDetails(tmdbID:)` → `backdropPath`, `runtime`, `genres`, fuller `overview`. Needs `item.tmdbID`; if nil (un-enriched), skip the fetch and fall back to a poster-tinted hero.
- **Show:** `tvDetails(tmdbID:)` → `backdropPath`, `genres`, `numberOfSeasons`. Then **lazily per selected season**: `seasonEpisodes(tvID:season:)` → `[TMDBEpisodeDetails]`, cached in `episodeMeta[season]`. Only the visible season fetches; switching seasons fetches once and caches.

All of this lives only in the store for the session; nothing is written to `LibrarySnapshot`. Images load with `AsyncImage` via `TMDBClient.imageURL(path:size:)` — backdrop at `"w1280"`, stills at `"w300"`, poster fallback at `"w500"`.

### 3.4 Episode list — library-driven, TMDB-enriched by number

The episode rows are driven by **what the user owns** — `MediaItem.seasons[*].episodes`, each carrying a playable `MediaSource` — and **enriched** by TMDB **by `episode.number`**:

- Own + TMDB match → still + real title + synopsis + quality chip + progress.
- Own + no TMDB match (or season fetch failed) → `"Episode N"` + quality chip + progress (still = placeholder).
- TMDB lists it but the user doesn't own it → **not shown** (nothing to play).

This guarantees every row is playable and there are no dead entries. Seasons in the picker are `MediaItem.seasons` (what's owned), not TMDB's full season count.

### 3.5 Quality chips + Versions (ranking in the brain)

Chips render from `MediaSource.parsed` (`ParsedRelease`: `resolution`, `source`, `videoCodec`, `audioCodec`). A movie's `sources` may hold several; a pure ranker in `DebridCore` orders them:

```
qualityRank = resolution (2160 > 1080 > 720 > 480 > unknown)
           ↳ then source tier (REMUX > BluRay > WEB-DL > WEBRip > HDTV > DVDRip > unknown)
           ↳ then video codec (HEVC/x265 > x264/AVC > unknown)
           ↳ deterministic tie-break by torrentID (stable ordering)
```

`bestSource` drives the primary Play button; the **Versions** list shows all sources `bestFirst()`, each selectable to play a specific file. Episodes carry a single `source`, so Versions is movie-only.

### 3.6 Watch progress — Resume vs Play, Mark Watched/Unwatched

Keys come from the existing `WatchKey`:
- Movie: `WatchKey.content(forMovie: item)`; Episode: `WatchKey.content(forShow: item, episode:)`; file: `WatchKey.source(_ source:)`.

**Read (drives the UI):** on `load()`, fetch the movie's `WatchState`, or — for the selected season — each episode's `WatchState` (per-episode `progress(forContentKey:)`; a season is ≤ ~25 calls, acceptable).
- Progress bar: `finished` → full + ✓; else `durationSeconds > 0` → `position/duration`; else → none.
- Hero CTA: in-progress (`position > 0 && !finished`) → **Resume {mm:ss}** (primary) + **Play from start** (secondary); otherwise **Play**. For shows, the hero targets the **next** episode — first owned episode (series order) that is in-progress, else first unfinished, else S1·E1.

**Write (Mark Watched/Unwatched):** `WatchProgressStore.record(...)`:
- Watched → `positionSeconds: 0, durationSeconds: 0, finished: true`.
- Unwatched → `positionSeconds: 0, finished: false` (the store has no delete; a reset row is harmless and excluded from the future Continue-Watching feed, which filters `position > 0`).
After a write, the store refreshes that `contentKey`'s `WatchState` so the bar/CTA update immediately.

### 3.7 Playback handoff — `PlaybackRequest` + `PlayerPlaceholderView` (the 7c seam)

```swift
struct PlaybackRequest: Hashable {
    let item: MediaItem
    let source: MediaSource
    let resumeAt: Double?   // seconds; nil = from start
    let label: String       // "Dune: Part Two" · "Game of Thrones — S1·E3"
}
```

Play/Resume/episode-select builds a `PlaybackRequest` (chosen/best source + resume position) and pushes it. `PlayerPlaceholderView` renders what it received — title, chosen version's quality chips, and the resume point — under a clear "Player arrives in Plan 7c" message. **No unrestrict, no playback** in this slice. 7c swaps the placeholder destination for the VLCKit player and consumes the same `PlaybackRequest`.

### 3.8 Views — layout from the approved mockups

- **`MovieDetailView`:** full-bleed backdrop + bottom-left scrim; title large; `year · runtime · genres`; overview (≤ 3 lines); quality chips; **Play** (+ **Resume** when applicable); **Versions** disclosure; **Mark Watched** (in a `.toolbar`/menu or a secondary button).
- **`ShowDetailView`:** same hero; a horizontal **season pill row** (focusable; `Season N`); below, a **vertical list** of `EpisodeRow`s for the selected season; hero primary = Resume/Play next.
- **`EpisodeRow`:** leading 16:9 still (placeholder when missing) · `N · Title` · one-line synopsis · thin progress bar · trailing watched ✓; selecting it builds the episode's `PlaybackRequest`; a context action marks watched/unwatched.

Visual direction (backdrop-forward Detail + vertical episode list) was chosen via mockups during brainstorming.

### 3.9 Composition — `AppSession` vends details + the shared watch store

`AppSession` (the composition root) already builds the library pipeline on sign-in. It gains:
- a `MediaDetailsProviding` (`TMDBDetailsService(TMDBClient(apiKey: Secrets.tmdbAPIKey))`), and
- a reference to the **shared** `WatchProgressStore` (same `ModelContainer` the library/persistence layer uses) so Detail, and later 7c + Continue-Watching, read/write **one** store.

`DetailView` builds its `DetailStore` from these (passed via the environment, like 7b-i's `LibraryStore`).

---

## 4. The `DebridCore` API this consumes + adds (confirmed against source)

**Consumes (exists today — confirmed in source):**
- `TMDBClient.movieDetails(id:) -> TMDBMovieDetails` — has `backdropPath`, `runtime`, `genres`, `overview`, `posterPath`.
- `TMDBClient.tvDetails(id:) -> TMDBTVDetails` — has `backdropPath`, `genres`, `numberOfSeasons`, `overview`.
- `TMDBClient.imageURL(path:size:) -> URL?` (static).
- `MediaItem` (`kind`, `title`, `year`, `sources`, `seasons`, `tmdbID`, `posterPath`, `backdropPath`, `overview`), `Season(number, episodes)`, `Episode(season, number, source, id)`, `MediaSource(torrentID, fileID, restrictedLink, parsed)`.
- `WatchKey.content(forMovie:)` / `content(forShow:episode:)` / `source(_:)`.
- `WatchProgressStore.progress(forContentKey:) -> WatchState?` (read) and `record(contentKey:sourceKey:positionSeconds:durationSeconds:finished:at:)` (upsert). `WatchState` (`positionSeconds`, `durationSeconds`, `finished`, `updatedAt`).

**Adds (new in this slice — small, pure, tested):**
1. `TMDBClient.tvSeasonDetails(tvID:season:) -> TMDBSeasonDetails` (GET `tv/{id}/season/{n}`) + `TMDBSeasonDetails` and `TMDBEpisodeDetails` (`episodeNumber`, `name`, `overview`, `stillPath`, `runtime`, `airDate`) in `TMDBModels.swift`.
2. Source ranker in `Library/`: `MediaSource.qualityRank` + `Array<MediaSource>.bestFirst()` / `.best` (reads `parsed`; deterministic).
3. `Hashable` conformance added to `MediaKind`, `MediaSource`, `Episode`, `Season`, `MediaItem` (all stored properties are already `Hashable`; purely additive).

---

## 5. Key flow

1. **Grid → Detail.** Tap a `PosterCard` → `NavigationLink(value: item)` pushes the `MediaItem` → `DetailView` builds a `DetailStore`.
2. **Instant base render.** The view shows title/year/poster/overview/sources from the cached `MediaItem` immediately; `richState = .loading`.
3. **Rich fetch.** `.task` runs `store.load()`: movie → `movieDetails`; show → `tvDetails` + `seasonEpisodes(selected)`. Watch states load in parallel. Backdrop/episodes fill in; on failure the base stays.
4. **Season switch (shows).** Selecting a season pill → `selectSeason(n)` lazily fetches + caches that season's episode meta + watch states.
5. **Play / Resume / episode-select.** Build `PlaybackRequest` (best/chosen source, `resumeAt` from `WatchState`) → push → `PlayerPlaceholderView` renders the intent. (7c will play it.)
6. **Mark Watched/Unwatched.** `store.setWatched(...)` → `WatchProgressStore.record(...)` → store refreshes that key → bar/CTA update.

---

## 6. Error handling & edge cases

- **`item.tmdbID == nil`** (un-enriched) → skip rich fetch; poster-tinted hero, base info only. No error.
- **Details / season fetch fails or offline** → `richState = .failed`; screen keeps base info; episodes degrade to `"Episode N"` + quality + progress. A subtle inline retry is allowed; no blocking error wall.
- **Show season with episodes lacking a TMDB match** → those rows show number + quality + progress (placeholder still).
- **Empty watch data** (the norm until 7c) → no bars; hero shows **Play** (no Resume). Mark Watched populates it.
- **Movie with multiple sources** → best plays by default; Versions lists all. Single source → no Versions disclosure.
- **Movie with zero sources / show with zero owned episodes** → shouldn't occur (`LibraryBuilder` filters empties); defensively, Play is hidden and a "no playable source" note shows.
- **Manual Mark Watched with unknown duration** → `durationSeconds: 0`; the `finished` flag drives the full bar + ✓ (no divide-by-zero).
- **Rapid season switching** → only the selected season is in flight; cache prevents re-fetch; out-of-order responses are ignored if the selection changed.

---

## 7. Testing & verification

**Brain (`DebridCoreTests`):**
- Source ranker: resolution/source/codec ordering, ties (deterministic by torrentID), missing-field fallbacks.
- `tvSeasonDetails` decoding from a fixture (nest under the `MockTests` serialized parent — shared `MockURLProtocol` handler).
- `Hashable` sanity (equal values hash equal; distinct ids differ).

**App (`SeretTVTests`, app-hosted):**
- `DetailStore` against a `FakeDetailsProvider` + a `WatchProgressStore` over an in-memory `ModelContainer`: instant base render; rich fill on success; **graceful degrade** on provider error (base retained); best-source selection + `versions` order; lazy season fetch + cache; **Mark Watched/Unwatched** writes and the read-back updates; Resume vs Play derivation from `WatchState`; `PlaybackRequest` carries the right source + `resumeAt`.
- **Any new SwiftData test suite must nest under `SwiftDataSuite`** (the documented ≥2-suite SIGSEGV gotcha). No network in tests (existing `XCTestConfigurationFilePath` `@main` guard).

**Simulator (DoD):** verify **Movie Detail** and **Show Detail** in the tvOS simulator and **screenshot** both — now possible end-to-end because Mark Watched seeds progress without a player. The simulator is the source of truth, not a browser.

---

## 8. Definition of Done — 7b-ii

- [ ] Tapping a poster pushes a Detail screen; back returns to the grid with focus restored.
- [ ] **Movie Detail:** backdrop hero (poster fallback), year · runtime · genres, overview, quality chips, Versions list (best default), Play/Resume, Mark Watched — verified in the sim (screenshot).
- [ ] **Show Detail:** backdrop hero, focusable season picker, vertical episode list with stills/titles/synopses/progress, per-episode Play + Mark Watched, hero Resume/Play-next — verified in the sim (screenshot).
- [ ] Play/Resume/episode pushes `PlayerPlaceholderView` showing the resolved source + resume point (no playback).
- [ ] Rich metadata fetched on-demand and cached for the session; `LibrarySnapshot` untouched; degrades silently when TMDB/`tmdbID` is unavailable.
- [ ] Mark Watched/Unwatched persists via `WatchProgressStore` and updates the UI immediately.
- [ ] Brain + app tests green; **full** suite run (not just `--filter`); **zero** build warnings.

---

## 9. Open questions / deferred

- **Unwatch semantics:** reset-row (`finished:false, position:0`) vs adding a `clear(contentKey:)` delete to `WatchProgressStore`. Reset-row chosen for this slice (no API change); revisit if stale rows ever matter.
- **Episode-list watch reads:** per-episode `progress(forContentKey:)` (≤ ~25/season) is fine now; a batch `progress(forContentKeys:)` is a cheap optimization if a season ever feels slow.
- **Backdrop/episode persistence → "enrichment v2":** bake `backdropPath` + episode metadata into `LibrarySnapshot` for instant/offline rich data. Out of scope here by decision.
- **Season-level "Mark season watched"** and a movie/show **rating** display (`voteAverage` is available) — nice-to-haves, not in 7b-ii.
- **Resolve-on-play proof:** optionally unrestrict the link inside the placeholder to prove the full pipeline — deferred to 7c to keep this slice player-free.
