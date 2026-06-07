# Show All Versions (DMM-style version list) — Design

**Date:** 2026-06-07
**Branch:** `feat/stage2-search-add`
**Apps:** SeretTV (tvOS) + SeretMobile (iOS/iPadOS)
**Builds on:** Stage 2 (Search → Add) + Request Download (uncached titles).

## Problem

The Add screen either auto-picks the best version (one Play tap) or, when nothing is
instantly cached, shows a single **Request Download** button. The user can't *see* what
versions exist — unlike Debrid Media Manager, which lists every torrent for a title (cached
"Instant RD" + uncached "DL with RD") to browse and pick from.

## Goal

Let the user browse and pick from **all** matching versions on the Add screen — cached and
uncached — like DMM, while keeping the simple one-tap default.

## Key constraint (researched 2026-06-07)

Real-Debrid **removed the bulk `instantAvailability` endpoint in Nov 2024** (legal pressure;
see comet#243, ElfHosted blog). There is **no live per-hash cache check** anymore. Comet
exposes its own ElfCache knowledge via the stream `name` prefix `[RD⚡]` (cached) / `[RD⬇️]`
(uncached) — already parsed into `CachedStream.isCached`. That marker is the cache-status
source of truth for the UI (same signal DMM-style tools use now). The *real* status is only
resolved by adding: an instant hash plays immediately, an uncached one downloads.

## Decisions (locked)

- **Auto-pick + "Show all versions" expander.** Keep the one-tap primary action (Play best
  instant / Request Download best uncached). Add a "Show all versions" expander that reveals
  the full cached+uncached list with badges to browse/pick.
- **Cache status from Comet's `isCached`** (⚡ Instant / ⬇️ Download). No RD check.
- **Tap a row:** ⚡ instant → add + play now (existing path); ⬇️ uncached → start *that
  version's* download via `DownloadStore.request(... candidates: [stream])`.

## Architecture

One Comet query with `includeUncached: true` (cachedOnly:false) returns **both** cached and
uncached candidates, ranked + title/year-gated, each carrying `isCached`. So the full list is
the existing `AddStore.uncachedCandidates()` data; the only brain-side change is to surface it
as observable state.

- **`AddStore`** — add `private(set) var allVersions: [CachedStream]` + `loadAllVersions()`
  (populates it from the uncached-inclusive query). Pure addition; `uncachedCandidates()` stays
  for the auto-pick request path.
- **`CacheBadge`** (per app) — a small ⚡ Instant / ⬇️ Download capsule.
- **Add screen (both apps)** — a "Show all versions" expander (in both the has-cached and
  no-cached states) → renders `add.allVersions` rows: quality chips · size · languages · badge.
  Tap forks on `isCached`: play (instant) vs `downloadStore.request([stream])` (uncached).

## Out of scope (already in flight)

- Library "downloading" badge tiles (`DownloadStore.activeTiles`) and the ready notification
  (`DownloadNotifier`) — being built separately.
- True per-hash RD cache check / DMM-index parity — not feasible without the removed endpoint.

## Testing

- **Brain (`swift test`):** `AddStore.loadAllVersions()` populates `allVersions` from the
  source (ranked, gated, uncached-inclusive); empty on error. Fakes only.
- **UI:** both apps build clean (0 warnings); on-device version-list + tap behaviour
  owner-pending (needs the live RD token, same DoD pattern as the rest of Stage 2).
