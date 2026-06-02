# Seret — Library Persistence (SwiftData cache + WatchProgress) — Design

**Status:** Draft for review
**Date:** 2026-06-02
**Owner:** Shahar Solomons
**Context:** First of three slices completing **Plan 6** ("finish the brain before the apps"): **persistence → subtitles → `VideoPlayerEngine`**. Refines/supersedes parts of [`2026-06-02-seret-design.md`](2026-06-02-seret-design.md) §5.5. Built test-first in `DebridCore`; no UI.

---

## 1. Goal

Make the library **load instantly and offline** from a local cache, **refresh against Real-Debrid incrementally** (only genuinely-new content costs a TMDB call), and **persist per-title watch progress** for Resume and Continue Watching — all inside `DebridCore`.

After this slice the app (Plan 7) can: open → render the cached library immediately → refresh in the background; and: play → restore position → record progress.

## 2. Scope

**In:**
- `LibrarySnapshot` (Codable) + a file-backed `LibrarySnapshotStore` — the offline library cache.
- `WatchProgress` SwiftData `@Model` (CloudKit-ready) + `WatchProgressStore`.
- `LibraryService` — cache-first load + incremental refresh orchestration.
- `Codable` conformance for the domain value types (so they can be snapshotted).

**Out (deliberately):**
- CloudKit **sync wiring** — Stage 3. The model is *shaped* ready (this slice), but no `CloudKit` container is enabled.
- Watchlist / "watched" library filtering UI — later.
- App UI — Plan 7+. Subtitles and `VideoPlayerEngine` — the other two Plan 6 slices.
- Fetching info for *only the new* torrents on refresh — a future optimization (see §6).

## 3. Decisions (from brainstorming)

1. **Split persistence by durability.** The library cache is **rebuildable, device-local** → a **file** (never rides CloudKit). Watch progress is **precious, frequently-updated, sync-bound** → **SwiftData** `@Model`. Keeping the cache out of the SwiftData store is what guarantees only user-state syncs in Stage 3.
2. **The library cache is a Codable snapshot, not relational `@Model`s.** This supersedes spec §5.5's `MediaItem`/`MediaFile`/`Episode` tables. Rationale: the library is derived from RD+TMDB and always rebuildable; mirroring it into a parallel `@Model` graph (plus bidirectional mapping) is maintenance cost for no durability benefit. The snapshot reuses the existing value types directly — zero impedance.
3. **Cache-first + incremental refresh.** RD stays the source of truth for *what exists*; grouping re-runs cheaply for correctness; the one rate-limited resource (TMDB) is touched **only for new content**.

## 4. Components (`DebridCore`)

New folders match the spec's target layout: `Persistence/` and `Library/` (which already holds `LibraryBuilder`, `MetadataEnricher`). This slice introduces `DebridCore`'s **first dependency** — `import SwiftData` (an Apple system framework, allowed per spec §4's "Persistence: SwiftData store"; the package's macOS 14 floor already supports it). `DebridCore` stays UI- and VLCKit-free.

### 4.1 `LibrarySnapshot` — `Persistence/LibrarySnapshot.swift`
A `Codable`, `Sendable` value type:
- `schemaVersion: Int` — bump to invalidate old caches across model changes.
- `builtAt: Date` — for staleness display / debugging.
- `items: [MediaItem]` — the enriched library. **Self-sufficient for display and playback offline:** quality/codec chips come from `MediaSource.parsed`; the `restrictedLink` for play-time unrestrict is already in `MediaSource`. No raw `TorrentInfo` is retained.

Requires **`Codable` conformance** added to the pure domain value types: `MediaSource`, `Episode`, `Season`, `MediaItem`, `ParsedRelease` (and any enums `ParsedRelease` nests). `MediaKind` is already `Codable`. These are pure data → synthesized `Codable`, no custom coding.

### 4.2 `LibrarySnapshotStore` — `Persistence/LibrarySnapshotStore.swift`
File-backed, injectable directory (Application Support in the app; a temp dir in tests):
- `save(_ snapshot: LibrarySnapshot) throws` — atomic write (write-temp-then-rename).
- `load() -> LibrarySnapshot?` — returns `nil` on missing / unreadable / decode-failure / `schemaVersion` mismatch (→ caller rebuilds). Never throws on a bad cache.

### 4.3 `WatchProgress` — `Persistence/WatchProgress.swift`
A SwiftData `@Model`, **CloudKit-ready** (every property defaulted, **no** `@Attribute(.unique)`, no required relationships):
- `contentKey: String = ""` — stable per-title key. **Movie** → the item's id (`"movie:tmdb:693134"`). **Episode** → `"\(show.id):\(episode.id)"` (`"show:tmdb:1399:s1e2"`) — note `Episode.id` alone (`"s1e2"`) is not globally unique, so the show id is prepended.
- `sourceKey: String = ""` — the file actually played: `"\(torrentID)#\(fileID ?? -1)"`.
- `positionSeconds: Double = 0`, `durationSeconds: Double = 0`, `finished: Bool = false`, `updatedAt: Date = .now`.

A small `Sendable` value-type DTO (`WatchState`) + key-derivation helpers are exposed so the app and tests don't touch SwiftData types directly. Key derivation lives next to the model.

### 4.4 `WatchProgressStore` — `Persistence/WatchProgressStore.swift`
Wraps a SwiftData `ModelContainer`/`ModelContext` (injected; in-memory in tests):
- `progress(forContentKey:) -> WatchState?` — for Resume.
- `record(contentKey:sourceKey:position:duration:finished:)` — **find-or-create upsert** (dedupe by `contentKey` in code, since CloudKit forbids a unique constraint).
- `recentlyWatched(limit:) -> [WatchState]` — unfinished, has-progress, sorted by `updatedAt` desc (Continue Watching).

### 4.5 `LibraryService` — `Library/LibraryService.swift`
The brain's top-level library API. Dependencies injected (existing protocol seams where available): `TorrentsClient`, `LibraryBuilder`, `MetadataEnricher`, `LibrarySnapshotStore`.
- `loadCached() -> [MediaItem]?` — decode the snapshot (instant, offline).
- `refresh() async throws -> [MediaItem]` — incremental (§5), writes a fresh snapshot, returns the updated library.

## 5. Key flows

**Launch:** `loadCached()` → render immediately (offline-capable) → `refresh()` in background → re-render. First run (no cache): `refresh()` cold-builds.

**Incremental refresh:**
1. List RD torrents (cheap, paginated) → current torrent-id set.
2. Diff against the cached library's torrent ids (from each `MediaSource.torrentID`). **No delta → the cache is current; stop.** (The common refresh costs one cheap list call — no `info` fetches, no TMDB.)
3. Delta exists → `allTorrentInfos()` → `LibraryBuilder.group(...)` (pure, correct cross-torrent show-merge) → **carry over cached TMDB metadata** for items whose content already exists in the cache (matched on stable identity — e.g. shared RD torrent source); **enrich only the new items** via `MetadataEnricher`. Removed torrents simply aren't in the fresh set. → write snapshot → return.

This caps TMDB to new content (retiring the Plan 5 unbounded-fan-out follow-up for enrichment) and makes the steady-state refresh nearly free.

**Play / Resume:** at play time the app resolves the unrestricted link (existing `playableURL`); on the player's periodic callbacks it calls `WatchProgressStore.record(...)`. Resume reads `progress(forContentKey:)`; Continue Watching reads `recentlyWatched(...)`.

## 6. Error handling & edge cases

- **Corrupt / version-mismatched snapshot** → `load()` returns `nil` → rebuild from RD. Never crash.
- **Refresh fails** (offline / RD down / decode) → `refresh()` throws; the app keeps showing `loadCached()` and surfaces a non-fatal "couldn't refresh." The cache is the resilience layer.
- **`WatchProgress` write failure** → swallowed; never interrupts playback.
- **SwiftData container init failure** → degrade to a no-progress mode (Resume disabled) rather than taking down the library; the snapshot cache is independent of SwiftData, so the library still loads.
- **`contentKey` re-key edge:** an item unmatched today (parsed-fallback id) that TMDB later matches changes id → its old `WatchProgress` is orphaned. Rare; accepted for Stage 1.
- **Future optimization (out of scope):** retaining RD facts to fetch info for *only* new torrents on a delta. Needs `Encodable` on the RD wire models (currently `Decodable`-only) or a persistence-owned projection; deferred until RD-info volume warrants it.

## 7. Testing (test-first; Swift Testing)

- **Codable round-trip:** the value types + `LibrarySnapshot` encode→decode equal.
- **`LibrarySnapshotStore`:** save→load round-trip; missing file → `nil`; corrupt bytes → `nil`; `schemaVersion` mismatch → `nil`; atomic overwrite leaves a valid file.
- **`LibraryService` incremental** (mocked `TorrentsClient` + a TMDB **spy**): cached library + {torrent added / removed / unchanged} → correct merged library, **and the spy proves enrichment runs only for new items** (zero TMDB calls when nothing changed).
- **`LibraryService` cold build** (no cache) and **offline** (refresh throws → `loadCached()` still returns the library).
- **`WatchProgressStore`** (fresh **in-memory `ModelContainer`** per test — SwiftData runs on the macOS 14 test host): record→read round-trip; upsert dedupe by `contentKey`; `recentlyWatched` ordering + unfinished filter; `finished` flag.
- Network-touching suites nest under the serialized `MockTests` parent (existing convention).

## 8. Spec reconciliation

Patch `2026-06-02-seret-design.md` §5.5: the library cache is a **snapshot** (not relational `MediaItem`/`MediaFile`/`Episode` `@Model`s); **`WatchProgress` is the single relational `@Model`**. Note the code uses **`MediaSource`** (the spec's "`MediaFile`").

## 9. Open questions for the plan

- Exact snapshot **on-disk format** (JSON for v1; a compact binary format only if size warrants) and location (Application Support/Seret/).
- The precise **carry-over identity** used in step 5.3 to match freshly-grouped items to cached enriched ones (shared torrent source vs a stable pre-enrichment key) — pick the most robust; cover with a test.
- Whether `LibraryService.refresh()` returns the whole library or emits an **async stream** (cache then refreshed) — favor the simplest API the Plan 7 UI can consume.
