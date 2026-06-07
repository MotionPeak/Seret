# Request Download (uncached titles) — Design

**Date:** 2026-06-07
**Branch:** `feat/stage2-search-add`
**Apps:** SeretTV (tvOS) + SeretMobile (iOS/iPadOS)
**Builds on:** Stage 2 (Search → Instant RD Add); extends the `StreamSource` + add path.

## Problem

When a title has **no cached Real-Debrid version**, the detail screen is a dead end — it
shows the backdrop + trailer but no Play button ("only pic"). Today the library *is* the
set of RD torrents already `downloaded`, the search source (`CometStreamSource`) is
hardwired to `cachedOnly:true`, and the add flow **deletes + rejects** any torrent that
isn't instantly cached. So there is no path to "get me this title."

## Goal

Let the user **request a download** for a non-playable title: the app finds a torrent
(including uncached), adds it to Real-Debrid, RD downloads it server-side, the app shows
progress, and the title becomes a normal playable library item when it's ready — with a
notification when it finishes.

**Explicitly NOT in scope:** true stream-while-downloading / sequential piece playback.
Real-Debrid downloads whole files server-side and exposes no sequential streaming; once a
torrent reaches `downloaded` (100%) its links work, not before. "Request + wait + play"
is the model.

## Decisions (locked in brainstorming)

- **Outcome:** request → RD downloads → progress shown → Play enabled when ready. No
  mid-download playback.
- **Entry points:** both **Browse/Search** titles (not in library) **and Library** titles
  whose source went stale/uncached (a "Re-download" action). Anywhere a title isn't
  playable.
- **Version pick:** **auto-pick best** (one tap), with **Try another version** if it
  stalls/fails. No mandatory chooser.
- **Progress UX:** live progress on the **detail screen** + a **"Downloading" badge** on
  the library poster + a **push notification** when ready.
- **Platforms:** **both apps**, shared brain. tvOS background-notification is best-effort
  (see Slice 3).

## Core model

> A "requested download" is just an **RD torrent that isn't `downloaded` yet, anchored to a
> TMDB title.** RD is the source of truth for progress; a small persisted record links the
> torrent to the title the user requested it for, so the badge/notification survive app
> restarts and resume monitoring (RD keeps downloading while the app is closed).

## Flow

1. Title not playable → user taps **Request Download** (detail screen).
2. Query Comet for **all** versions (drop `cachedOnly`) → **auto-pick best** by
   quality → health → size.
3. `addMagnet(best)` → `selectFiles(video)` — **keep the torrent** (do not delete on
   non-instant; the opposite of today's `add`).
4. Persist a `DownloadRequest { contentKey/tmdbID, torrentID, infoHash, kind, title,
   requestedAt }`.
5. `DownloadMonitor` polls RD `info(id:)` → emits progress; UI shows "Downloading NN%"
   on the detail screen and a badge in the library.
6. On `downloaded`: the title flows into the normal library refresh as a playable item;
   the request record is cleared; Play appears; a notification fires.
7. On a terminal status (`dead`/`virus`/`magnet_error`) or a stall (no progress over a
   window): surface **Try another version** (picks the next-best candidate, deletes the
   stalled torrent).

## Architecture — DebridCore (brain; pure, VLCKit-free, TDD)

Each unit small, single-purpose, behind a seam:

- **Uncached discovery** — extend `StreamSource`/`CometStreamSource` to fetch uncached
  candidates (a `cachedOnly:false` query; e.g. `streams(for:cachedOnly:)` or a sibling
  `allStreams(for:)`). Returns `CachedStream`-style candidates with parsed quality, size,
  and seeder/health when Comet provides it.
- **Best-uncached picker** — pure ranker: **quality → health → size**; falls back to
  quality+size when no health signal. Reuses/extends the existing `[MediaSource].bestFirst()`
  ranking idea, adapted to candidate streams.
- **RequestDownloadService** — `addMagnet → selectFiles(video)`; **keeps** the torrent;
  returns the torrent id + initial status; maps RD terminal statuses to a typed failure so
  the UI can "try another." (Sibling to the existing instant-only `RealDebridAddService`,
  or a new mode on it.)
- **DownloadsStore** — persisted `DownloadRequest` records (SwiftData `@Model`,
  CloudKit-ready like `WatchProgress`: all properties defaulted, no unique constraints).
  Survives restarts; drives badge + notification.
- **DownloadMonitor** — given active requests, polls RD `info(id:)` for status + progress;
  emits progress updates; detects completion (`downloaded`) and terminal failure; clears a
  record once its title is playable in the library. Poll cadence injected for testability.

**Library integration:** a requested torrent, once `downloaded`, appears in the normal
`LibraryService.refresh()` as a playable item — no special library path needed for the
*finished* state. The *in-progress* state lives in `DownloadsStore`/`DownloadMonitor` and is
overlaid on the UI.

## Architecture — UI (shared DebridUI + both apps)

- **`DownloadStore`** (DebridUI, `@MainActor @Observable`) — exposes active downloads +
  per-title progress on `DownloadsStore`/`DownloadMonitor`; provides `request(for:)`,
  `tryAnother(for:)`, `cancel(for:)`.
- **`DetailStore`** gains: `requestDownload()`, observed progress/state for the current
  title, `tryAnother()`, `cancel()`.
- **Detail screen (MovieDetail/ShowDetail · MovieDetailView/ShowDetailView):** when not
  playable, render **Request Download**; once requested, a **"Downloading NN%"** row with
  **Try another version** + **Cancel**; auto-flip to Play/Resume when ready; inline error
  on stall ("That release stalled — Try another version").
- **Library grid (LibraryGrid · PosterGrid/PosterCard):** a **"Downloading" badge +
  progress ring** overlay for titles with an active request; clears when playable.

## Notifications

- **Slice 2 (foreground):** when `DownloadMonitor`'s poll detects completion while the app
  is active, fire a **local notification** ("<title> is ready to watch") and flip the UI.
  Requires the one-time notification authorization.
- **Slice 3 (background):** iOS `BGAppRefreshTask` periodically polls RD for active requests
  and notifies on completion when the app is closed. **tvOS has no reliable background
  refresh** — there, notify on next foreground when completion is detected. This limitation
  is stated, not faked.

## Error handling

- No uncached results → "No version available to download."
- RD add rejected / terminal status → "Try another version" (next-best candidate; delete the
  failed torrent).
- Stall = RD `progress` not advancing over a window **or** a terminal status.
- Offline → keep the record; resume polling when connectivity returns.
- Cancel → delete the RD torrent + clear the record.

## Delivery slices (each its own plan)

1. **Brain** — uncached discovery + picker + RequestDownloadService + DownloadsStore +
   DownloadMonitor, fully TDD with fakes. **Preceded by a research spike** (risks #1–#2).
2. **UI, both apps** — Request Download + live progress + library badge + ready→Play +
   foreground local notification. Build-clean both apps; on-device verification owner-pending.
3. **Background notifications** — iOS `BGAppRefreshTask` polling + reliable background
   notification; tvOS best-effort (on-foreground).

## Risks — research BEFORE building Slice 1

These underpin the whole feature; the plan's research phase must confirm them with real
calls before committing to the full build:

1. **Does Comet return uncached torrents** with `cachedOnly:false`? If not, an alternate
   indexer is needed. **Make-or-break.**
2. **Will RD reliably download an uncached magnet** added via `addMagnet`+`selectFiles`
   (timing, health-dependence, rejection cases)? Confirm with one real hash.
3. **Does Comet expose seeder/health** for ranking? If not, picker falls back to
   quality+size (degrade gracefully, no blocker).

**Recommendation:** spike #1–#2 first; if Comet can't surface uncached, rethink the source
before any UI work.

## Testing

- **Brain (`swift test`, host-free):** uncached discovery (mocked Comet), picker ranking
  (quality/health/size + fallback), RequestDownloadService keeps-torrent-on-non-instant +
  maps terminal status, DownloadMonitor progress→completion→failure transitions + record
  clearing, DownloadsStore persistence (under the `SwiftDataSuite` serialized parent).
- **UI:** build-clean both targets (0 warnings); shared `DownloadStore` view-model tests
  with fakes.
- **On-device (owner-pending):** a real uncached RD download (request → progress → ready →
  Play) + the completion notification — can't be exercised safely from the sim, same DoD
  pattern as the player.

## Out of scope (YAGNI)

- Stream-while-downloading / sequential playback (RD can't; would mean a different backend).
- A mandatory version chooser (auto-pick + try-another only).
- Download queue management UI beyond per-title cancel/try-another.
- Cross-device download sync (the `DownloadsStore` is CloudKit-ready for later, not wired now).
