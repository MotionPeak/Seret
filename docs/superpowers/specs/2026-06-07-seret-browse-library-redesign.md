# Seret — Browse / My-Library Redesign (design)

**Date:** 2026-06-07
**Status:** Approved — ready for implementation plan
**Milestone:** Stage 2 follow-on. Reframes the app's information architecture around **Browse (discover + add)** vs **My Library (own + play)**, and adds a CAM/"In Theatres" section and trailers.

## Goal

Turn the **Movies** and **TV Shows** tabs into **browse** surfaces (popular releases + an in-tab search that adds to Real-Debrid), move the user's actual RD content into a dedicated **My Library** tab split by kind, flag titles already owned, surface brand-new theatrical (CAM-likely) releases in their own section, and let the user watch trailers.

## Decisions (locked with owner 2026-06-07)

| Decision | Choice |
|---|---|
| CAM logic | **By TMDB release date** — no per-title Comet cache check. "In Theatres" = `now_playing` (theatrical window, CAM-likely); "New Releases" = home-released window (real files), shown primary. A title's actual cached quality still appears on its Add screen. |
| Tab bar | **Home**(mobile) · **Movies** · **TV Shows** · **My Library** · **Settings**. tvOS has no Home → Movies · TV · Library · Settings. |
| Trailers | **iOS/iPadOS:** in-app `WKWebView` YouTube embed. **tvOS:** deep-link to the YouTube app (button hidden if it can't open — tvOS has no WebKit). |
| Scope | One pass, both apps. |
| Search scope | Per-tab: the Movies tab searches movies, the TV tab searches shows. |

## Information architecture

**Before:** Movies = RD library movies · Shows = RD library shows · Search = discover+add.
**After:** Movies = browse movies (+search) · TV Shows = browse shows (+search) · **My Library** = RD content split Movies/TV · (mobile) Home unchanged · Settings unchanged. **The standalone Search tab is removed.**

## Components

### 1. Browse screen (Movies tab / TV Shows tab) — shared, per `MediaKind`
- **Search field** pinned at top, scoped to the tab's kind. Empty query → browse rows; non-empty → search results grid (kind-filtered).
- **Browse rows** (horizontal rails / focus-safe on tvOS):
  - **Movies:** `Popular` · `In Theatres` (CAM) · `New Releases` · genre rows (Action 28, Comedy 35, Horror 27, Drama 18, Thriller 53, Sci-Fi 878, Animation 16, Crime 80).
  - **TV:** `Popular` · TV genre rows (Drama 18, Comedy 35, Crime 80, Sci-Fi & Fantasy 10765, Animation 16, Mystery 9648, Reality 10764).
- **Ownership:** each poster whose TMDB id ∈ `libraryStore.ownedTMDBIDs` shows an **"In Library" badge**; tapping it opens the owned item's **library Detail** (play) rather than the Add flow. Un-owned poster → Add flow (existing `AddFlowStore`).

### 2. My Library screen
- The current `LibraryStore` (cache-first RD content), presented split into **Movies** and **TV**: a segmented control on mobile (compact), two sections on iPad/tvOS. Reuses `LibraryStore.movies` / `.shows`, today's poster grids + Detail/play path. No new data layer — only the container moves to its own tab.

### 3. CAM / release-date sectioning (movies)
- **In Theatres** = `TMDBClient.nowPlayingMovies()` (recent theatrical → CAM-likely). Rendered as its own row, visually secondary.
- **New Releases** = `discoverMovies(releaseFrom:to:)` over a home-release window (≈ `today-300d … today-45d`, `vote_count.gte` gate, sorted by release date desc) → titles likely to have real files, shown as a primary row above genres.
- Date windows computed in the store from a `now` clock (injectable for tests). No per-title Comet calls.

### 4. Trailers
- `TMDBClient.movieVideos(id:)` / `tvVideos(id:)` → `[TMDBVideo]`; pick the first YouTube `Trailer` (fallback `Teaser`).
- A **Trailer** button on the Add screen and the library Detail (shown only when a key resolves).
- **iOS/iPadOS:** present a `TrailerView` (WKWebView → `https://www.youtube.com/embed/{key}?autoplay=1&playsinline=1`).
- **tvOS:** open `youtube://watch?v={key}` (fallback `https://youtube.com/watch?v={key}`); hide the button if `UIApplication.canOpenURL` is false.

## Architecture (one brain, three faces)

**DebridCore (pure, TDD):**
- `TMDBClient`: `popularMovies()` (`/movie/popular`), `popularTV()` (`/tv/popular`), `discoverTV(genreID:)` (`/discover/tv`), `discoverMovies(releaseFrom:to:)` (date-windowed `/discover/movie`), `movieVideos(id:)` (`/movie/{id}/videos`), `tvVideos(id:)` (`/tv/{id}/videos`).
- `TMDBVideo` model (`key`, `site`, `type`, `name`) + `[TMDBVideo].firstYouTubeTrailer`.

**DebridUI (presentation, TDD with fakes):**
- `DiscoverProviding` extended (`popular(kind:)`, `moviesByGenre`/`tvByGenre`, `nowPlaying`, `newReleases(from:to:)`). `DiscoverStore` becomes **kind-aware** (`init(kind:discover:now:)`) producing the kind's row set, concurrent load, empties dropped.
- `SearchStore` gains kind scoping (movie-only / show-only results) — the browse search uses it filtered to the tab's kind.
- `LibraryStore.ownedTMDBIDs: Set<Int>` (from `movies + shows`), for the badge / owned-navigation lookup.
- `TrailerProviding` seam + `TMDBTrailerService` → trailer key; Add/Detail stores expose `trailerKey`.
- `AppSession`: vend `moviesBrowse` + `showsBrowse` (`DiscoverStore` per kind); keep `searchStore`; `discoverStore` (old single movie store) removed/replaced.

**Apps (SeretTV + SeretMobile):**
- Rewire tab shells (`LibraryShell` / `MainShell`): Movies/TV → Browse; add My Library; remove Search tab; keep Home (mobile).
- Shared **Browse screen** per kind (search field + rows + owned badges + nav fork to Add vs library Detail).
- **My Library** screen (kind split).
- Per-platform **Trailer** presentation (iOS WKWebView, tvOS deep-link) + Trailer buttons on Add/Detail.

## Testing
- DebridCore: new TMDB endpoints (URL + decode) via `MockURLProtocol`; `TMDBVideo.firstYouTubeTrailer`.
- DebridUI: kind-aware `DiscoverStore` (movie vs TV rows, date windows, empties dropped); `SearchStore` kind scoping; `LibraryStore.ownedTMDBIDs`; `TrailerProviding` resolver. Host-free `swift test`.
- Apps: `xcodebuild build` both, zero warnings. Sim screenshots + real browse/add/play/trailer remain **owner-pending** (per prior slices).

## Out of scope / deferred
- Per-title real cache-quality bucketing (the precise CAM detection) — release-date proxy is intentional.
- A "pick another version" affordance on a *library* item whose file won't play (only the Add screen lists versions today).
- Trailer autoplay/PiP niceties; multi-trailer selection.
