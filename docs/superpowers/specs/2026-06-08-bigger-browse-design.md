# Bigger, Better Browse — Design

**Date:** 2026-06-08
**Branch:** build on current (`feat/profiles`); stage only browse-related paths.
**Status:** Approved

## Problem

The Movies/TV browse tabs feel thin and the content looks "weird": obscure titles with
inflated ratings. Root cause is **how TMDB is queried**, not TMDB's data:
- The "Popular" rails sort by `vote_average.desc` with only a 300-vote floor → surfaces
  obscure films rated 8.7 by a few hundred fans, not the recognizable greats.
- "Trending" uses a per-genre `popularity.desc` discover sort, not TMDB's real trending lists.
- Only 8 genres, ~20 titles per rail, everything loaded up front.

An IMDb scraper is **not** a solution: IMDb has no public trending/discover API, and scraping
is fragile/ToS-gray. The fix is to query TMDB the way it's meant to be queried, and to broaden
the surface. TMDB is the same catalog Stremio/most debrid apps use.

## Goal

A deep, mostly-personalized browse with far more to scroll, showing **mainstream global**
content (recognizable titles regardless of origin — high vote floors, real endpoints, no
language filter).

## Structure — keep segments, enrich them

Five segments (a focusable picker, as today), each a vertical stack of horizontal rails. The
`DiscoverStore.Row` model (id, title, hits) already supports arbitrary rail titles.

| Segment | Rails |
|---|---|
| **For You** | `Because you watched {X}` (watched seeds, up to 6), then `More like {Y}` (library seeds, up to 4), deduped across rails. Empty → falls back to Trending rails so it's never blank. |
| **Trending** | `Trending Today`, `Trending This Week` (real `/trending`), then `Trending in {Genre}` for every genre (discover `popularity.desc`). |
| **New** | `New This Month` (overall, date-windowed), then `New in {Genre}` per genre. Vote floor raised (~50) so it's not junk. |
| **Popular** | `Popular in {Genre}` per genre (`popularity.desc`, vote floor ~300). |
| **Top Rated** | `Top Rated of All Time` (curated `/top_rated`), `Best of the 2010s / 2000s / 90s` decade rails, then `Top {Genre}` per genre with a hard vote floor (~1,500). |

- **All genres**: ~19 movie / ~16 TV TMDB genres (vs 8 today).
- **More per rail**: fetch **2 pages (~40 titles)** per rail instead of 20.
- **Default landing segment**: For You.
- **Mainstream global**: no `with_original_language` filter; quality comes from vote floors +
  curated endpoints.

## Loading — lazy per-segment

Today `DiscoverStore.load()` fetches every segment's rails up front; that won't scale to 5×
the rails. New model:

- A segment's rails load the first time it's selected (`loadSegment(_:)`), then are cached in
  memory for the session (instant on return).
- Rails within a segment load in parallel via a `TaskGroup`, **concurrency-capped** (~8 in
  flight) to stay polite to TMDB.
- Per-rail failure degrades silently (the rail is omitted). A segment with zero successful
  rails shows the existing retry state.
- For You loads after seeds resolve; if there are no seeds, it renders the Trending rails as a
  fallback.

## Recommendations seeding

New seam so For You is testable without real data:

```swift
public protocol RecommendationSeedProviding: Sendable {
    /// Seed titles for the given kind: watched titles first (most recent), then library titles.
    func seeds(kind: MediaKind, limit: Int) async -> [RecommendationSeed]
}
public struct RecommendationSeed: Sendable, Equatable {
    public let tmdbID: Int
    public let title: String
}
```

- Production conformance composes the **watch store** (`recentlyWatched()`) and the
  **library store** (owned items), filtered to `kind`, watched-first, deduped by `tmdbID`,
  truncated to `limit`. `AppSession` builds it at sign-in and injects it into each
  `DiscoverStore`.
- `DiscoverStore` calls TMDB `/recommendations` per seed → one rail each
  (`Because you watched {title}` for watched seeds, `More like {title}` for library seeds),
  dropping titles already owned-and-watched and deduping across rails.

## TMDB endpoints to add (`DebridCore/TMDBClient`)

- `/trending/movie/{day|week}`, `/trending/tv/{day|week}`
- curated `/movie/top_rated`, `/tv/top_rated`
- `/movie/upcoming` (reserved; not in the initial rail set — omit unless a rail needs it)
- `/movie/{id}/recommendations`, `/tv/{id}/recommendations`
- `page` param on discover/search-style calls; a `voteCountFloor` param on the genre rails
- decade rails reuse `discover` with `primary_release_date` (movies) / `first_air_date` (TV)
  windows + a vote floor + `vote_average.desc` (or `popularity.desc`) sort

All new client methods decode-tested under the `MockTests` serialized parent.

## Files

**DebridCore**
- `Metadata/TMDBClient.swift` — new endpoints + `page`/`voteCountFloor` params (modify)
- `Metadata/TMDBModels.swift` — reuse `TMDBSearchResult`/`TMDBSearchResponse` (trending &
  recommendations return the same result shape); no new model expected
- Tests: `TMDBClientTests.swift` (extend) — new endpoint URLs + decoding

**DebridUI**
- `Search/DiscoverStore.swift` — 5-segment enum, lazy `loadSegment(_:)`, all-genres list,
  curated + decade + For-You rails, seed wiring (modify)
- `Search/RecommendationSeedProviding.swift` — new seam + production conformance
- `Shell/AppSession.swift` — compose the seed provider, inject into the two `DiscoverStore`s
  (modify)
- Tests: `DiscoverStoreTests.swift` (extend) — lazy per-segment load, all-genre coverage,
  decade rails, For-You seeding + dedup + empty-fallback (fakes)

**Apps (both)**
- `Apps/SeretTV/Browse/BrowseScreen.swift`, `Apps/SeretMobile/Browse/BrowseScreen.swift` —
  call `loadSegment(selected)` on segment change instead of one up-front `load()` (modify).
  Rail rendering already iterates `browse.rows`, so churn is small.

## Build slices (for the plan)

1. **DebridCore endpoints** — trending / top_rated / recommendations / page+vote-floor params + tests.
2. **DiscoverStore redesign** — 5 segments, lazy per-segment load, all genres, curated + decade rails + tests.
3. **For You** — `RecommendationSeedProviding` seam + conformance + rails + `AppSession` wiring + tests.
4. **Apps** — lazy-load-on-segment-change in both `BrowseScreen`s; build both targets.

## Testing

Host-free `swift test` for all logic (DebridCore + DiscoverStore + seed provider). SwiftUI
views verified by the owner's simulator screenshot (this env can't launch the sim).

## Out of scope

- Changing the Home tab (Continue Watching / Recently Added) — unchanged.
- Per-rail infinite pagination on horizontal scroll (we fetch a fixed 2 pages per rail).
- Language/region UI toggle (locked to mainstream-global for now).
- `/movie/upcoming` "Coming Soon" rail unless a later tweak wants it.
