# Seret — Design Spec

**Status:** Draft for review
**Date:** 2026-06-02
**Owner:** Shahar Solomons
**Scope of this document:** Stage 1 (the shared core + the Apple TV and iPhone/iPad apps, browse · organize · play). Stages 2–3 are sketched in the Roadmap but specced separately later.

---

## 1. Vision

**Seret** (Hebrew: *סרט*, "film") is a free, self-contained media app for **Apple TV, iPhone, and iPad** that replaces Plex — and eventually Debrid Media Manager — for a **Real-Debrid**-powered library.

Today the user adds a title in DMM (**Instant RD**), a Zurg+rclone mount exposes it to a Plex Media Server on a Synology NAS, and Plex plays it on the Apple TV. Seret **collapses that entire stack**: the app talks **directly to the Real-Debrid API**, recognizes and organizes titles itself via **TMDB**, fetches subtitles via **OpenSubtitles**, and plays everything on-device with **VLCKit** — no media server, no Synology in the playback path, no Plex Pass.

### Guiding principle
> One brain, three faces. All logic lives once in a tested, UI-free Swift package; each platform gets native UI on top. We share the brain, not the screens.

This is the decision that keeps three apps from becoming three messes, and it is the backbone of the "neat, elegant, built to last" goal.

---

## 2. Goals & Non-Goals

### Goals (Stage 1)
- **G1** — Sign in to Real-Debrid with the Apple-TV-native **device-code** flow (no on-screen keyboard pain).
- **G2** — Read the user's RD library and **organize it automatically** into Movies and Shows (poster wall, season→episode tree) using TMDB.
- **G3** — **Play any file** RD holds — MKV / x265 / DTS / TrueHD / ASS subs — via VLCKit, with no server transcoding.
- **G4** — **Subtitles**: use embedded tracks instantly; fetch external Hebrew/English subs on demand from OpenSubtitles.
- **G5** — **Resume**: remember watch position per title (local in Stage 1; cross-device in Stage 3).
- **G6** — Ship the same experience on **tvOS and iOS/iPadOS** from the shared core.

### Non-Goals (Stage 1 — deferred)
- **N1** — In-app search and **adding** content to RD (the DMM replacement). → Stage 2.
- **N2** — Cross-device sync of watch progress. → Stage 3 (foundation laid now).
- **N3** — Downloading files to the device for true offline playback.
- **N4** — Multi-user / accounts beyond the single owner's RD account.
- **N5** — An AVPlayer fast-path for hardware-decodable files. → Stage 3 (seam laid now).

---

## 3. Roadmap

| Stage | Delivers | Replaces | Notes |
|---|---|---|---|
| **1 (this spec)** | `DebridCore` + Apple TV app + iPhone/iPad app — browse, organize, play | **Plex** | Sequenced so a runnable tvOS build lands early, then iOS |
| **2** | In-app **search → Instant RD** Add flow across all apps | **DMM** | Needs research: torrent indexing + RD cache-check is the one genuinely hard, longevity-sensitive piece |
| **3** | Polish: cross-device Continue Watching (CloudKit), richer organization (collections/genres), AVPlayer fast-path | — | Foundations (SwiftData+CloudKit, `VideoPlayerEngine` seam) are laid in Stage 1 |

---

## 4. Architecture

```
                         ┌──────────────────────────────┐
                         │          DebridCore          │   pure Swift • no UI • no VLCKit
                         │  (one shared, tested brain)  │   fully unit-testable
                         ├──────────────────────────────┤
                         │ Networking   HTTPClient       │
                         │ RealDebrid   auth + resources │
                         │ Metadata     parse→match→group│
                         │ Subtitles    SubtitleProvider │
                         │ Library      LibraryService   │
                         │ Persistence  SwiftData store  │
                         │ Playback     VideoPlayerEngine│ (protocol only)
                         └───────────────┬──────────────┘
              ┌──────────────────────────┼──────────────────────────┐
              ▼                          ▼                          ▼
     ┌─────────────────┐       ┌──────────────────┐      (shared design tokens +
     │   SeretTV (tvOS)│       │ Seret (iOS/iPad)  │       small components in
     │  sidebar · focus│       │ tab bar · split   │       DebridUI, optional)
     │  VLCKit player  │       │ VLCKit player     │
     └─────────────────┘       └──────────────────┘
```

- **`DebridCore`** is a local Swift package. It knows nothing about SwiftUI, UIKit, or VLCKit. Everything that can be wrong about talking to Real-Debrid, recognizing a title, or fetching a subtitle is testable here without launching an app.
- **Playback** is special: VLCKit is platform-specific (`TVVLCKit` vs `MobileVLCKit`) and is UIKit-bound, so `DebridCore` only defines the **`VideoPlayerEngine` protocol** and the playback *model*. The concrete VLCKit engine + the SwiftUI player view live in each app target (or a thin per-platform module).
- **UI is native per platform.** tvOS uses a sidebar + the focus engine; iOS uses a tab bar (iPhone) / `NavigationSplitView` sidebar (iPad). A small optional **`DebridUI`** module holds shared design tokens (colors, type scale, the poster/chip components) where reuse is clean — never forced.

### Repository layout (target)
```
Seret/
├── CLAUDE.md                  # project north-star (build/run/test, conventions, decisions)
├── README.md
├── project.yml                # XcodeGen — generates Seret.xcodeproj (not committed)
├── .swiftlint.yml  .swiftformat
├── Secrets.example.xcconfig   # template; real Secrets.xcconfig is gitignored
├── Packages/
│   └── DebridCore/            # the shared brain (SPM, pure, tested)
│       ├── Package.swift
│       ├── Sources/DebridCore/{Networking,RealDebrid,Metadata,Subtitles,Library,Persistence,Playback,Models}
│       └── Tests/DebridCoreTests/
├── Apps/
│   ├── SeretTV/               # tvOS target (SwiftUI + TVVLCKit)
│   └── SeretMobile/           # iOS/iPadOS target (SwiftUI + MobileVLCKit)
├── Shared/
│   └── DebridUI/              # optional shared SwiftUI tokens + components
└── docs/superpowers/specs/    # this spec
```

---

## 5. DebridCore — component design

### 5.1 Networking
A tiny async/await `HTTPClient` over `URLSession`: typed requests, JSON decode, uniform error mapping (transport vs HTTP-status vs decode), retry-with-backoff for `429`/`503`. No third-party networking dependency.

### 5.2 RealDebrid
**Auth — OAuth2 device-code flow, public open-source client `X245A4XAIBGVM` (no secret, free):**
1. `GET /oauth/v2/device/code?client_id=…&new_credentials=yes` → `device_code`, `user_code`, `verification_url` (`real-debrid.com/device`), `interval`, `expires_in`.
2. App shows `user_code` + URL (tvOS: big on-screen code; we can also render a QR to the verification URL).
3. Poll `GET /oauth/v2/device/credentials?client_id=…&code={device_code}` every `interval`s → once authorized returns a **per-user** `client_id` + `client_secret`.
4. `POST /oauth/v2/token` (`grant_type=http://oauth.net/grant_type/device/1.0`, the per-user client id/secret, `code=device_code`) → `access_token` (~1h), `refresh_token`.
5. Persist tokens + per-user credentials in the **Keychain**. Refresh transparently before/after `401`.

**Resources** (`Authorization: Bearer …`, base `https://api.real-debrid.com/rest/1.0`):
- `GET /user` — account + premium status/expiry (surfaced in Settings; warn when expiring).
- `GET /torrents?page&limit` — the library (paginated; iterate all pages).
- `GET /torrents/info/{id}` — files[] + the unrestricted-ready `links[]` for a torrent.
- `POST /unrestrict/link` — turn an RD restricted link into a **direct streamable URL** (what VLCKit plays). Resolved **lazily, at play time** (links can expire), never stored long-term.
- *(Stage 2: `POST /torrents/addMagnet` + `/selectFiles/{id}` for the Add flow.)*

> **CORS note:** DMM proxies RD through `cors.debridmediamanager.com` only because browsers enforce CORS. Native apps have no such limit — Seret calls `api.real-debrid.com` directly. Confirmed live against the account.

### 5.3 Metadata (recognize & organize)
- **`FilenameParser`** — extracts title, year, season, episode, resolution, source, video codec, audio, release group, edition from RD filenames (port of the well-trodden parse-torrent-title logic; heavily unit-tested with real-world release names).
- **`TMDBClient`** — `search/movie`, `search/tv`, `movie/{id}`, `tv/{id}`, `tv/{id}/season/{n}`; images from `image.tmdb.org/t/p/…`. Free API key (provided via Secrets, never committed).
- **`MetadataService`** — orchestrates: for each RD torrent → enumerate video files → parse → classify movie vs episode → match to TMDB → **group** into a clean library:
  - **Movie** → one `MediaItem` with one-or-more `MediaFile` "versions" (e.g., a 1080p and a 4K cut).
  - **Show** → `MediaItem(show)` → `Season` → `Episode`, each episode bound to its `MediaFile`.
- Results (TMDB data + the torrent→TMDB mapping) are **cached in SwiftData**, so after the first build the library is instant and offline-readable; new RD torrents are reconciled incrementally.

### 5.4 Subtitles
- **`protocol SubtitleProvider`** — `search(for:languages:)` and `download(_:)`. Stage 1 ships **`OpenSubtitlesProvider`** (`api.opensubtitles.com/api/v1`, Api-Key + login; respects the free tier's daily download cap with clear UI feedback). The seam means a dedicated Israeli-Hebrew provider can be added later without touching the player.
- **Embedded** subtitle/audio tracks need no provider — VLCKit enumerates them from the file; we just present them.

### 5.5 Library & Persistence

> **As-built** (see [`2026-06-02-library-persistence-design.md`](2026-06-02-library-persistence-design.md)) — the library cache and watch progress are split **by durability**, not modelled as one relational schema. This supersedes the earlier "everything is a SwiftData `@Model`" sketch.

- **Library cache → a Codable `LibrarySnapshot` file.** The enriched `[MediaItem]` value-type graph, persisted to a device-local JSON file, **never CloudKit-synced**. The library is derived from RD and fully rebuildable, so it's cached as a snapshot rather than a parallel `@Model` graph. Loaded instantly and offline; refreshed incrementally by `LibraryService` (cheap when the torrent set is unchanged; on a delta, re-groups and enriches **only new** items). The code's playable-source type is **`MediaSource`** (this draft earlier called it `MediaFile`).
- **Watch progress → a relational SwiftData `@Model` `WatchProgress`** — the one piece of precious, frequently-updated user state. **CloudKit-ready** (every property defaulted, no unique constraints, no required relationships) so Stage 3 cross-device sync is a config flip. Keyed by a stable `contentKey` (a movie's id, or show-id + episode-id) plus the `sourceKey` of the file played; carries `positionSeconds`/`durationSeconds`/`finished`/`updatedAt`. Behind a `WatchProgressStore` (`@ModelActor`).

RD remains the **source of truth for what exists**; the snapshot is a **rebuildable cache** and `WatchProgress` is the **user-state** layer (later: watchlist).

### 5.6 Playback
`protocol VideoPlayerEngine`: `load(url:headers:)`, `play/pause/seek`, **track enumeration & selection** (audio + subtitle), `addExternalSubtitle(url:)`, periodic time + state callbacks. `DebridCore` owns the protocol and the playback *model*; the **VLCKit engine** is implemented per app target. The seam is what lets Stage 3 add an AVPlayer fast-path for hardware-decodable files behind the same interface.

**As-built ([`2026-06-03-video-player-engine-design.md`](2026-06-03-video-player-engine-design.md)):** alongside the `VideoPlayerEngine` protocol + the playback value-type model (`PlaybackState`/`PlaybackTime`/`MediaTrack`/`PlaybackEvent`), `DebridCore` ships a **`PlaybackCoordinator`** — a small, stateless bridge to `WatchProgressStore` (`resumePosition(contentKey:)` and best-effort `record(...)`, marking a title finished at ~95%). This keeps Resume / Continue-Watching logic in the shared brain rather than re-implemented per app; the app drives it (throttling save calls) and wires the engine's events to it.

---

## 6. The apps (Stage 1 UI — validated via mockups)

Shared navigation model: **sidebar** (tvOS, iPad via `NavigationSplitView`) / **tab bar** (iPhone) → Home · Movies · Shows · Search · (Add, Stage 2) · Settings.

| Screen | Direction (approved) | Key elements |
|---|---|---|
| **Sign-in** | Device-code | Big `user_code` + `real-debrid.com/device` + QR; auto-advances on authorize |
| **Home** | Sidebar hybrid | Compact featured hero + rows: Continue Watching, Recently Added |
| **Detail** | Backdrop-forward | Full-bleed art, Resume/Play, synopsis, **quality/source chips** (`2160p · HEVC · DTS-HD · subs HE/EN · 24.3 GB · ⚡ RD cached`) |
| **Show** | Season picker + episode rows | Thumbnail, watch-progress bar, synopsis, Play/Resume |
| **Player** | VLCKit + track menu | Scrubber, controls; **Subtitles** menu = embedded tracks + "Search OpenSubtitles…"; **Audio** track switch |

tvOS gets the focus engine (poster focus scale + ring); iOS/iPad get touch + adaptive layout. The detail/player screens go full-bleed (sidebar tucks away) for immersion.

---

## 7. Key flows

**Sign-in:** device/code → show code → poll credentials → token → Keychain → load `/user`.

**Build library:** `GET /torrents` (all pages) → `MetadataService` parse/match/group (cache in SwiftData) → render Home/Movies/Shows. Incremental on subsequent launches (only reconcile new/removed torrents).

**Play:** select `MediaFile` → `POST /unrestrict/link` (lazy, at play time) → direct URL → `engine.load` → restore `WatchProgress` → play; observe time → persist progress.

**Subtitle on demand:** in player, "Search OpenSubtitles…" → `SubtitleProvider.search` (he/en) → pick → `download` → temp file → `engine.addExternalSubtitle`.

---

## 8. Error handling & edge cases

- **Token expiry** → silent refresh; only force re-auth if refresh fails.
- **RD rate limits / 5xx** → backoff + retry; user-visible only if persistent.
- **Unrestrict fails / link dead** → re-fetch `torrents/info`, retry; if the torrent is gone from RD, mark the item unavailable (don't crash the library).
- **No TMDB match** → show the cleaned filename gracefully; allow a manual "match to…" later; never block playback on metadata.
- **Unplayable file** (rare with VLCKit) → surface a clear error + the offending codec, offer to pick another version if one exists.
- **Empty library** (current state of the fresh account) → friendly first-run state pointing at how content arrives (and, in Stage 2, the Add flow).
- **Offline** → SwiftData cache renders the library read-only; playback needs network (RD is remote).

---

## 9. Testing strategy

`DebridCore` is built test-first; the protocol seams make it possible:
- **`FilenameParser`** — large table of real release names → expected fields (the highest-ROI tests).
- **`MetadataService`** — grouping logic against mocked `TMDBClient` (movie vs season pack vs single episode vs mixed).
- **`RealDebridClient`** — auth state machine + resource decoding against a mocked `HTTPClient` (recorded RD JSON fixtures).
- **`OpenSubtitlesProvider`** — search/download against mocked HTTP; daily-cap handling.
- **`LibraryService` / persistence** — reconcile add/remove; watch-progress round-trip.
- Framework: **Swift Testing** (Swift 6.3). UI/snapshot tests come with the app targets later; manual verification in the **tvOS/iOS simulators** before any "done" claim.

---

## 10. Tooling & project setup

- **XcodeGen** `project.yml` generates `Seret.xcodeproj` (not committed — no `.xcodeproj` rot). Matches the Nikud setup.
- **Swift 6.3**, strict concurrency on. **SwiftUI** throughout. **`DebridCore`** as a local SPM package.
- **SwiftLint + SwiftFormat** with committed configs (`brew install swiftlint swiftformat`) — enforced in a build phase.
- **VLCKit**: integrate `TVVLCKit` / `MobileVLCKit` (SPM binary target or CocoaPods — to confirm during setup; see Risks).
- **Secrets** (TMDB key, OpenSubtitles key) via `Secrets.xcconfig` (gitignored) with a committed `Secrets.example.xcconfig` template. RD needs no secret (public client); the user's RD tokens live in the Keychain at runtime.

---

## 11. Security & privacy

- **No secrets in the repo.** RD tokens → Keychain. TMDB/OpenSubtitles keys → gitignored xcconfig.
- **Never log the RD token** or unrestricted URLs.
- Single-user, personal-use **client** (in the spirit of Infuse/VLC): it plays content the owner already accesses through their own paid Real-Debrid account. Seret stores nothing on anyone's server.

---

## 12. Risks & open questions

| # | Risk / question | Plan |
|---|---|---|
| R1 | **Stage 2 indexing** — finding torrents to Add and checking RD cache (RD removed `instantAvailability`) | Research spike at Stage 2; lean on DMM's open-source approach; pluggable indexer seam |
| R2 | **VLCKit distribution** — cleanest SPM vs CocoaPods integration for TV/Mobile XCFrameworks | Confirm during project setup; isolate behind the `VideoPlayerEngine` seam either way |
| R3 | **SwiftData + CloudKit** constraints (optional/defaulted props, no unique) | Models already designed to comply |
| R4 | **OpenSubtitles** free-tier daily cap + Hebrew quality | Clear UI feedback; Israeli provider can slot in behind `SubtitleProvider` |
| R5 | **API keys** provisioning (TMDB, OpenSubtitles) | One-time setup task; document in CLAUDE.md |
| R6 | **Bundle IDs / signing team** | Confirm with owner at setup (placeholder `com.solomons.seret[.tv]`) |

---

## 13. Definition of Done — Stage 1

- [ ] Device-code sign-in works on a real Apple TV + iPhone; tokens persist and refresh.
- [ ] RD library loads and is auto-organized into Movies + Shows with TMDB art.
- [ ] Any RD file plays via VLCKit with working embedded + on-demand OpenSubtitles subtitles and audio-track switching.
- [ ] Watch progress persists and Resume works (per device).
- [ ] Both apps run from the shared `DebridCore`; core has meaningful unit-test coverage.
- [ ] Verified in the tvOS and iOS simulators with screenshots; `DebridCore` tests green.
