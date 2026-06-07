# Remove from Library — Design

**Date:** 2026-06-07
**Branch:** `feat/stage2-search-add`
**Apps:** SeretTV (tvOS) + SeretMobile (iOS/iPadOS)

## Summary

Add a "Remove from Library" action that **permanently deletes** an item from the
user's Real-Debrid account. The Seret library *is* the RD `/torrents` list, so the
only meaningful "remove" is a real RD delete. Because one movie/show maps to one or
more torrents (multiple quality versions, season-pack episodes), removal deletes
**every** torrent backing the item. A confirmation dialog always precedes deletion.

Decisions locked during brainstorming:

- **Remove = delete from Real-Debrid** (destructive, irreversible; re-add means searching again).
- **Both apps**, on the current `feat/stage2-search-add` branch.
- **Surfaces:** detail-screen menu **and** a quick grid gesture (context menu on both
  platforms), each gated by a confirmation dialog.
- **Purge watch progress** on remove (no dead Continue-Watching tiles).
- **Optimistic UI**: drop the tile / pop the detail screen immediately on success; no
  full library re-fetch.

## Behavior

- Removal deletes the **unique set** of `torrentID`s backing the item:
  - Movie → `item.sources[].torrentID`
  - Show → `item.seasons[].episodes[].source.torrentID`
- RD deletes are **idempotent**: a `404` (torrent already gone) counts as success, so a
  partially-deleted item can be cleanly finished.
- If any non-404 delete fails, the operation **throws** and the persisted snapshot is
  left untouched, so the UI re-syncs to reality (item may still appear with remaining
  sources). The user sees an error alert; the item is not dropped from the UI.
- On full success: persisted snapshot is rewritten without the item, the item's
  watch-progress entries are purged, and the item is dropped from the in-memory library
  state so every view updates at once.

## Layers

### 1. DebridCore — `LibraryService.remove(_ item: MediaItem)`

File: `Packages/DebridCore/Sources/DebridCore/Library/LibraryService.swift`

- Collect unique `torrentID`s from the item (movie sources + show episode sources).
- Call `TorrentsClient.deleteTorrent(id:)` for each; treat `404` as success
  (idempotent). Any other failure → throw without mutating the snapshot.
- On success, load the current `LibrarySnapshot`, remove the item by `id`, persist via
  `LibrarySnapshotStore`.
- `TorrentsClient.deleteTorrent(id:)` already exists — no new RD endpoint needed. The
  404-as-success handling lives in `LibraryService` (or a thin helper) so the raw client
  stays a faithful HTTP wrapper.

### 2. DebridCore — `WatchProgressStore.deleteProgress(forContentKeys: [String])` (new)

File: `Packages/DebridCore/Sources/DebridCore/Persistence/WatchProgressStore.swift`

- Batch delete of `WatchProgress` rows whose `contentKey` is in the given set.
- Content keys are derived with the existing `WatchKey` helpers:
  - Movie: `WatchKey.content(forMovie:)`
  - Show episodes: `WatchKey.content(forShow:episode:)` for every episode.

### 3. DebridUI — `LibraryStore.remove(item:)` (single orchestration point)

File: `Shared/DebridUI/Sources/DebridUI/Library/LibraryStore.swift`

- New seam `LibraryRemoving` (conformed by `LibraryService`) exposing
  `func remove(_ item: MediaItem) async throws`. `LibraryProviding` is extended or a
  sibling protocol is added — whichever keeps the existing `LibraryProviding` consumers
  unchanged.
- `LibraryStore` gains an injected watch-store reference (from `AppSession`) so it can
  purge progress as part of removal.
- New observable `removal` state: `idle / removing(MediaItem) / failed(String)` for
  spinner + error-alert binding.
- `remove(item:)`:
  1. set `removing(item)`
  2. `try await library.remove(item)`
  3. purge watch progress for the item's content keys
  4. drop the item from `movies`/`shows` in place
  5. on throw → `failed(message)`, item stays.
- This is the **only** entry point both the grid and the detail screen call, keeping
  published state in one place.

### 4. App UI (tvOS + iOS)

**Grid quick gesture (context menu, both platforms):**

- tvOS: `.contextMenu` on `PosterCard` / within `PosterGrid`
  (`Apps/SeretTV/Library/PosterCard.swift`, `PosterGrid.swift`).
- iOS: `.contextMenu` on the poster button in `LibraryGrid`
  (`Apps/SeretMobile/Library/LibraryGrid.swift`). (Swipe-to-delete does not fit a
  `LazyVGrid`; context menu is the consistent gesture on both.)
- Action → `.confirmationDialog` → on confirm call `libraryStore.remove(item:)`. Tile
  vanishes on success; `.alert` on failure.

**Detail screen:**

- tvOS: `MovieDetailView` / `ShowDetailView`
  (`Apps/SeretTV/Detail/`); iOS: `MovieDetail` / `ShowDetail`
  (`Apps/SeretMobile/Detail/`).
- A "Remove from Library" entry in an overflow `Menu` (destructive role), gated by a
  confirmation dialog.
- The detail screen receives a remove closure wired to the shared
  `libraryStore.remove(item:)` (injected from the shell that owns `AppSession`). On
  success the screen dismisses/pops to the grid; on failure it shows an alert and stays.

### 5. Wiring

- `AppSession.enterSignedIn()` already builds `LibraryStore(library: service)` and holds
  `watchProgressStore`. Update it to inject the watch store into `LibraryStore` and to
  pass a remove closure down to the detail screens (both apps construct `DetailStore`
  per-screen with deps that originate from `AppSession`).

## Testing

**DebridCore (`swift test`, host-free, VLCKit-free):**

- `LibraryService.remove`:
  - multi-source movie deletes all torrents + drops from snapshot
  - multi-torrent show deletes the unique torrent set
  - `404` on a delete is treated as success
  - a non-404 failure throws and **preserves** the snapshot
- `WatchProgressStore.deleteProgress(forContentKeys:)` removes the right rows and leaves
  others intact.

**DebridUI:**

- `LibraryStore.remove` view-model tests: success drops the item; failure sets the error
  and keeps the item; watch purge is invoked with the correct keys.

**App layer:**

- Build both targets clean (0 warnings).
- On-device confirmation of a real RD deletion is **owner-pending** (same DoD as the
  player work — can't verify destructive RD calls from the sim safely without a throwaway
  item).

## Out of scope (YAGNI)

- Undo / trash / restore.
- Bulk multi-select removal.
- A separate local "hidden" layer (rejected in brainstorming — remove is a true RD delete).
- Removing a single quality version while keeping others (removal is per-item, all
  sources).
