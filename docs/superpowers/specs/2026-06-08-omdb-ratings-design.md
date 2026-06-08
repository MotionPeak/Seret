# OMDb Ratings on Detail Screens — Design

**Date:** 2026-06-08
**Branch:** `feat/cloudkit-sync` (build on current branch; stage only ratings-related paths)
**Status:** Approved

## Goal

Show external ratings on the movie/show detail screens of both apps (SeretTV + SeretMobile):
IMDB rating, Rotten Tomatoes score, and Metacritic score. All three come from a single
OMDb API call keyed by the IMDB id that TMDB already provides.

## Why OMDb

- IMDB has no usable public API; OMDb is the standard free bridge for IMDB ratings.
- A single OMDb lookup by IMDB id (`?i=tt…`) returns IMDB rating, Rotten Tomatoes, and
  Metacritic together in a `Ratings[]` array plus top-level fields — RT/Metacritic are
  effectively free once we call OMDb at all.
- Free tier is **1,000 requests/day** — the persistent cache (below) keeps us far under it.

## Architecture (mirrors the existing TMDB pattern)

### OMDbClient — `DebridCore/Sources/DebridCore/Metadata/OMDbClient.swift`
Reuses the existing `HTTPClient` (same as `TMDBClient`).
```swift
public struct OMDbClient: Sendable {
    public init(apiKey: String, http: HTTPClient = HTTPClient())
    public func ratings(imdbID: String) async throws -> OMDbRatings
    // GET https://www.omdbapi.com/?apikey=…&i=tt0133093
}
```

### Model — `OMDbRatings`
Decodes from both top-level fields (`imdbRating`, `Metascore`) and the `Ratings[]` array
(source `"Rotten Tomatoes"`). All optional — OMDb omits RT/Metacritic for many older or
foreign titles.
```swift
public struct OMDbRatings: Sendable, Equatable {
    public let imdb: Double?           // "8.7" → 8.7
    public let rottenTomatoes: Int?    // "88%" → 88
    public let metacritic: Int?        // "73"  → 73
}
```
A raw `OMDbResponse: Decodable` handles the wire format (string fields, `Response: "False"`
error envelope) and maps to `OMDbRatings`.

### Seam — `RatingsProviding` (DebridUI)
Separate from `MediaDetailsProviding` (different source, different failure mode, independently
testable).
```swift
public protocol RatingsProviding: Sendable {
    func ratings(imdbID: String) async throws -> OMDbRatings
}
public struct OMDbRatingsService: RatingsProviding { /* wraps OMDbClient + cache */ }
```

## DetailStore wiring

After the TMDB fetch succeeds and `imdbID` is known, fire a **separate, non-blocking** OMDb
call. The detail screen never stalls on ratings.
```swift
public private(set) var ratings: OMDbRatings?
public private(set) var ratingsState: RichState = .idle
```
On failure/timeout: `ratingsState = .failed`, `ratings = nil`, screen renders normally without
the row. Same graceful-degradation as the rest of the app. No change to `MediaDetailsProviding`.

`AppSession`/composition root injects an `OMDbRatingsService` (built with `Secrets.omdbAPIKey`)
into `DetailStore`. When the key is empty, inject a no-op provider so ratings are simply off
(mirrors the OpenSubtitles empty-key behavior).

## Caching (keeps us under the 1k/day quota)

1. **In-memory** (per session) — re-opening a detail doesn't refetch.
2. **Persistent on-disk** — small JSON file keyed by `imdbID`, **7-day TTL**. Ratings barely
   change, so each title costs ~1 call/week and the row appears instantly on revisit.

Cache lives behind `OMDbRatingsService` so `DetailStore` and the protocol stay cache-agnostic.
Cache entry: `{ imdbID, ratings, fetchedAt }`. Read → if entry fresh, return; else fetch,
store, return. Network failure with a stale entry present → return the stale entry.

## UI — native `RatingsRow` per app (follows the existing convention)

This codebase shares *logic*, not *screens*: each app has its own `Theme` design system and its
own quality-chip view (`QualityChipRow` on mobile, `QualityChips` on tvOS). So `RatingsRow` is
implemented twice — once per app — exactly like the quality chips. Both read `store.ratings`.

- **Mobile** `Apps/SeretMobile/Detail/RatingsRow.swift` — styled with `Theme` (gold accents).
  Placed below `QualityChipRow` in `MovieDetail`; below the meta line in `ShowDetail`.
- **tvOS** `Apps/SeretTV/Detail/RatingsRow.swift` — styled with raw fonts/colors like
  `QualityChips`. Placed below `QualityChips` in `MovieDetailView` hero; below the meta line in
  `ShowDetailView` hero.

Both render:

> ⭐ IMDb 8.7   🍅 88%   Ⓜ 73

- Renders only badges that have data (`OMDbRatings.hasAny` gates the row).
- Entire row hidden when `store.ratings == nil` or all three are nil.
- Metacritic label: `Ⓜ 73`. IMDb uses ⭐, Rotten Tomatoes uses 🍅.

## Secrets

- `Secrets.example.xcconfig`: add `OMDB_API_KEY =`
- `Secrets.xcconfig` (gitignored): real key
- `Secrets.swift`: `static var omdbAPIKey: String` reading Info.plist `OMDBAPIKey`, empty-string
  fallback (no assert — empty key = ratings off, like OpenSubtitles)
- `project.yml`: map `OMDBAPIKey` → `$(OMDB_API_KEY)` in both app targets' Info.plist
- **Prerequisite:** owner obtains a free key from omdbapi.com/apikey.aspx

## Testing (TDD, host-free under `swift test`)

All logic lives in DebridCore/DebridUI and is testable without a host app. SwiftUI views
(`RatingsRow`) have no unit-test infra in this repo (same as `QualityChips`) — they're verified
by the owner's simulator screenshot, matching the project's "verify UI in the sim" convention.

- `OMDbResponse` decode + map to `OMDbRatings` (DebridCore): full response; RT missing;
  all ratings missing; `Response:"False"` error; TV series response. (`MockURLProtocol` suite,
  nested under `MockTests`.)
- `OMDbRatings.hasAny`: true with any score, false when all nil.
- `OMDbRatingsCache` (DebridCore): fresh hit returns cached; expired entry returns nil from
  `cached`; `stored` returns expired entry; persists across instances (same directory).
  (Injected `now` clock + temp directory; pure, plain top-level suite.)
- `OMDbRatingsService` (DebridUI): cache miss fetches + stores; cache hit skips fetch;
  network failure with a stored (even stale) entry returns it; failure with no entry rethrows.

## Out of scope

- Showing ratings on grid/poster tiles (detail screens only).
- Trakt/Letterboxd or other rating sources.
- User-configurable rating sources.
