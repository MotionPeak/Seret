# CLAUDE.md — Seret

> Guidance for Claude (and humans) working in this repo. Read this first.
> Full design rationale: [`docs/superpowers/specs/2026-06-02-seret-design.md`](docs/superpowers/specs/2026-06-02-seret-design.md). Per-plan implementation plans live in [`docs/superpowers/plans/`](docs/superpowers/plans/).

## What Seret is

**Seret** (Hebrew *סרט*, "film") is a **free, self-contained media app for Apple TV, iPhone, and iPad** — a Plex replacement powered by **Real-Debrid**. It talks **directly to the Real-Debrid API** (no media server, no Synology, no Plex Pass), **recognizes & organizes** titles via **TMDB**, fetches subtitles via **OpenSubtitles**, and plays everything on-device with **VLCKit**.

It replaces this old stack: `DMM (Instant RD) → Real-Debrid → Zurg+rclone mount → Plex Server (Synology) → Plex app`. Seret is the app *and* the server *and* the organizer, all on-device.

## Status — **Plans 1–6 + 7a + 7b + 7c DONE** — `DebridCore` brain feature-complete **and the `SeretTV` tvOS app (sign-in + library grids + Detail/episodes + real VLCKit player) merged to `main`**; Home / Search-Add (Stage 2) / Plan 8 (iPhone-iPad) next

**The `DebridCore` package is real, on `main` ([github.com/MotionPeak/Seret](https://github.com/MotionPeak/Seret)) — 122 tests green, zero warnings.** Built test-first via the superpowers pipeline (brainstorm → spec → one plan per slice → subagent-driven TDD), each plan adversarially reviewed (spec + code-quality + final) before a fast-forward merge to `main`.

**Done & merged:**
- **Plan 1 — RD auth:** `HTTPClient`/`HTTPError`, device-code `RealDebridAuthClient`, `TokenStore`+`KeychainTokenStore`+`InMemoryTokenStore`, `RealDebridSession` (transparent, concurrency-coalesced refresh).
- **Plan 2 — RD resources:** `Torrent`/`TorrentFile`/`TorrentInfo`(+`primaryVideoFile`/`selectedFilesWithLinks`)/`UnrestrictedLink`; `TorrentsClient` (`torrents`/`info`/`unrestrict`/`playableURL`); `AccessTokenProviding` seam (RealDebridSession conforms).
- **Plan 3 — recognition:** `FilenameParser` → `ParsedRelease` (cached regexes); `TMDBClient` (`searchMovie`/`searchTV`/`movieDetails`/`tvDetails`/static `imageURL`) + `TMDBModels`.
- **Plan 4 — library grouping:** `MediaItem`/`Season`/`Episode`/`MediaSource`/`MediaKind`; `LibraryBuilder.group([TorrentInfo]) -> [MediaItem]` (movies, single episodes, season-pack expansion, cross-torrent show merge, dedup, empty-show filter — pure, no I/O).
- **Plan 5 — TMDB enrichment + RD-fetch glue:** `MetadataEnricher` (`enrich(_ item:)` single-match + concurrent order-preserving batch `enrich(_:)` with graceful per-item degradation) + `MediaItem.withMetadata(...)` (TMDB-rekeyed `id`, keeps parsed title when a match's title is blank); `TorrentsClient.allTorrents()` (paginated) / `allTorrentInfos()` (concurrent info fan-out, skips failures). Pure data layer — TMDB mocked in tests.
- **Plan 6 slice 1 — persistence:** `LibrarySnapshot` Codable file cache + `LibrarySnapshotStore` (atomic, degrades to nil); `WatchProgress` `@Model` + `WatchState` DTO + `WatchKey` + `WatchProgressStore` (`@ModelActor`, CloudKit-ready); pure `LibraryReconciler` (torrent-id delta + carry-over); `LibraryService` (cache-first `loadCached()` + incremental `refresh()` — only new content hits TMDB). **SwiftData is the package's first dependency** (its test suites must nest under the `SwiftDataSuite` serialized parent — see Testing).
- **Plan 6 slice 2 — subtitles:** `SubtitleProvider` seam + `SubtitleQuery`/`SubtitleResult`/`SubtitleError` (+ `.movie`/`.episode` domain query builders); `OpenSubtitlesProvider` (`actor`: `search` → `download` to a **path-safe** temp file; lazy login + cached JWT; daily-cap → `.dailyCapReached`; one-shot 401 re-login; login auth-fail → `.notAuthenticated`); `HTTPClient` gained JSON-body `post(_:json:)` + raw-bytes `data(_:)`. Search prefers `tmdb_id`; transport mocked in tests.
- **Plan 6 slice 3 — VideoPlayerEngine:** the playback seam — a `@MainActor VideoPlayerEngine` protocol (load/play/seek, track enumeration+selection, `addExternalSubtitle`, `events: AsyncStream<PlaybackEvent>`) + playback model (`PlaybackState`/`PlaybackTime`/`MediaTrack`/`PlaybackEvent`) + `PlaybackCoordinator` (resume + best-effort save via `WatchProgressStore`, finished at ~95%). Protocol + model only (no VLCKit/UI in the package); the VLCKit engine + player view ship with the app (Plan 7).

### ▶ RESUME HERE — Plan 7 sliced 7a/7b/7c; **7a + 7b (i + ii) + 7c ALL DONE & merged to `main`**

Plan 7 (first native UI) ships as vertical slices. **All merged to `main` 2026-06-03, subagent-driven (per-task spec+quality reviews + a final whole-branch review each):**
- **7a — foundation + device-code sign-in:** the `SeretTV` app — XcodeGen `project.yml`, `AuthFlow` seam + `SignInModel` phase machine + `SignInView`/QR, `AppSession` + `RootView` shell (sign-in → Keychain → Sign Out), placeholder assets, Secrets/lint scaffold. One brain change: `RealDebridAuthClient.awaitCredentials(for:)` (device-code poll loop). RD auth **verified live** (owner authorized; device "Apple TV" in their RD account).
- **7b-i — library grids:** sidebar `NavigationSplitView` (Movies · Shows · Settings) → TMDB poster grids. `Secrets.tmdbAPIKey` (managed Info.plist ← `Secrets.xcconfig`) → `TMDBClient`; `LibraryProviding` seam + `LibraryStore` (`@Observable`: cache-first `loadCached()` + background `refresh()`, split by `kind`, loading/empty/failed states, cancellation-guarded `load()`); `AppSession.enterSignedIn()` composes `TMDBClient`+`TorrentsClient(realDebrid)`+`MetadataEnricher`+`LibraryBuilder`+`LibrarySnapshotStore`→`LibraryService`→`LibraryStore`; `PosterCard`/`PosterGrid` (`AsyncImage` + `TMDBClient.imageURL`), `LibraryScreen` (states), `LibraryShell` (Button-row sidebar — **tvOS has no `List(selection:)`**); `HomeStubView` removed; `SettingsView` adapted to a sidebar destination. **No DebridCore change.** DebridCore 112 + 9 app tests green, zero warnings. **The TMDB v3 key is already in the gitignored `Secrets.xcconfig`.**
- **7b-ii — library drill-down (Detail + episodes):** `PosterCard` now pushes `DetailView` (value-based `NavigationStack` in `LibraryShell`). `DetailStore` (`@MainActor @Observable`, mirrors `LibraryStore`) renders instantly from the cached `MediaItem`, then fetches TMDB **details on-demand**, cached per session — the `LibrarySnapshot` is untouched. **Movie:** backdrop hero, year·runtime·genres, overview, quality chips, **Versions** list (best plays by default). **Show:** focusable season picker + vertical episode list (still·title·synopsis·progress·✓). **Play/Resume** builds a `PlaybackRequest` → `PlayerPlaceholderView` (the 7c seam — no playback yet). **Mark Watched/Unwatched** writes `WatchProgress`. New seams `MediaDetailsProviding`/`WatchProgressProviding`; `AppSession` vends both + a shared `WatchProgressStore`. **Brain additions:** `Hashable` on domain models (value-nav), pure source ranker (`[MediaSource].bestFirst()`/`.best`), `TMDBClient.tvSeasonDetails(tvID:season:)` + `TMDBSeasonDetails`/`TMDBEpisodeDetails` + public inits on detail DTOs. **DebridCore 122 tests** green, zero warnings; app compiles clean; 8 `DetailStoreTests` (fakes, app-hosted). **Owner-pending:** ⌘U app-test run + Movie/Show Detail sim screenshots (this dev env can't launch the tvOS sim — see Gotchas).

**Deferred formality (7a + 7b-i + 7b-ii):** the app's own DoD **screenshots** (sign-in code → grids → Detail) await the owner's Xcode — two blockers: (1) live data needs **one cold RD device-code sign-in** (RD rate-limits `device/code` HARD — see Gotchas), and (2) **this dev env can't launch the tvOS sim at all** (PTY error — see Gotchas), so `xcodebuild test` + previews must run from the Xcode GUI (⌘U). Code is verified by `swift test` (brain, 122 green) + `xcodebuild build-for-testing` (app compiles, zero warnings) + adversarial review.

**▶ Plan 7c (VLCKit player) — DONE & merged to `main` (`cae005c`) 2026-06-04.** Shipped subagent-driven (10 tasks; per-task spec + code-quality reviews + a final whole-branch review): vendored **TVVLCKit 3.6.0** xcframework + `VLCKitVideoPlayerEngine` (nonisolated `VLCMediaPlayerDelegate` → `MainActor.assumeIsolated`) + `PlayerModel` (`unrestrict`→load→resume-seek→play→throttled-5s save; long-lived `consumeEvents` loop + cancellation-guarded `loadCurrentSource`; on-demand he/en OpenSubtitles w/ diff-based new-track selection; retry/try-another-version; **15 unit tests with fakes, VLCKit-free**) + SwiftUI `PlayerView` (Siri-remote transport + track menu + loading/error/retry overlays) + generic `KeychainSecretStore` (the only new `DebridCore` source file; plus a `stop()` method on `VideoPlayerEngine`) + `OPENSUBTITLES_API_KEY` chain + Settings login form (`SettingsModel`) + `AppSession.makePlayer` factory. `PlayerPlaceholderView` removed (its `timecode` → shared `Support/Timecode.swift`). **124 DebridCore + 35 app tests green, zero warnings.** Notable choices: the player is presented by swapping the existing value-nav `navigationDestination(for: PlaybackRequest)` body (NOT a `fullScreenCover` — identical UX, far less risk than threading a closure through the 6 `NavigationLink(value:)` play sites); `PlaybackRequest` gained a `contentKey` so per-episode progress keys correctly. ⚠️ **Owner-pending:** the on-device DoD (real RD-stream playback + screenshots need the Apple TV / Xcode `⌘U` — the sim can't verify actual video) and OpenSubtitles credentials (put the API key in the gitignored `Secrets.xcconfig` + add the account in Settings; an empty key keeps subtitles disabled by design). **▶ NEXT:** Home (hero + Continue Watching [`WatchProgressStore.recentlyWatched()` exists] + Recently Added [needs `addedAt` on `MediaItem`]); Search/Add (Stage 2); **Plan 8** = iPhone/iPad (`MobileVLCKit`).

**Decisions now LOCKED (from 7a):** module name **`Seret`**; bundle `com.solomons.seret.tv`; **device signing needs a team with an Apple Development cert** — `ML9HDN3QZS` has only a Developer-ID (macOS-distribution) cert, the personal team `7NY9RRS56S` has the dev cert (signed via Xcode GUI); VLCKit = vendored official `TVVLCKit.xcframework` (stable 3.x) fetched by `Scripts/fetch-frameworks.sh`, embedded via XcodeGen like Nikud's `llama.xcframework` (wired in 7c); `project.yml` mirrors Nikud. The tvOS app's unit-test target is app-hosted (`@testable import Seret`) and `@main` guards on `XCTestConfigurationFilePath` so tests fire no network.

## The one architectural rule

> **One brain, three faces.** All logic lives once in `DebridCore` (a pure, UI-free, fully-tested Swift package). Each platform gets *native* UI on top. **Share the brain, not the screens.**

If you're tempted to put networking, parsing, RD/TMDB/OpenSubtitles logic, or models in an app target — stop. It belongs in `DebridCore`. The only thing that legitimately lives per-platform is UI and the **VLCKit engine** (VLCKit is platform-specific and UIKit-bound).

## Architecture

```
DebridCore (pure Swift, no UI, no VLCKit, unit-tested)
  ✓ Networking   ✓ RealDebrid(auth+resources)   ✓ Metadata(parse + TMDB)   ✓ Library(grouping + enrich)
  ✓ Subtitles(SubtitleProvider + OpenSubtitles)   ✓ Persistence(SwiftData cache + WatchProgress)   ✓ Playback(VideoPlayerEngine + PlaybackCoordinator)
        ▲                                   ▲
   SeretTV (tvOS)                     Seret (iOS/iPadOS)        ⋯ not built yet (Plan 7–8)
   sidebar · focus · TVVLCKit         tab bar / split · MobileVLCKit
        └──────── optional shared DebridUI (design tokens) ────────┘
```
✓ = built & merged · ⋯ = planned. Enrichment (`MetadataEnricher`) ✓ built (Plan 5).

## Tech stack

- **Swift 6.3**, strict concurrency (Swift 6 language mode). **SwiftUI** for the apps. Package deployment floor **iOS/tvOS 18, macOS 14** (so `swift test` runs on the dev Mac).
- **DebridCore**: local Swift Package, **no third-party deps**, no UI. Tests in **Swift Testing**.
- **Playback**: **VLCKit** (`TVVLCKit` / `MobileVLCKit`) behind a `VideoPlayerEngine` protocol (Plan 6). Raw AVPlayer can't play RD's MKV/x265/DTS — that's why VLCKit.
- **Persistence**: **SwiftData**, models CloudKit-ready (later cross-device sync is a config flip). Plan 6.
- **Project (apps)**: **XcodeGen** (`project.yml`) generates `Seret.xcodeproj` — not committed. Created in Plan 7.

## Repo layout

```
Packages/DebridCore/Sources/DebridCore/   ← THE BRAIN (exists; put all logic here)
  Networking/   RealDebrid/   Metadata/   Library/   Subtitles/   Persistence/   Playback/
Packages/DebridCore/Tests/DebridCoreTests/   ← Swift Testing suites
  Support/MockURLProtocol.swift · MockTests.swift (serialized parent for network-mock suites) · SwiftDataSuite.swift (serialized parent for SwiftData suites)
docs/superpowers/specs/   ← the design spec
docs/superpowers/plans/   ← one implementation plan per slice (Plans 1–6 written)
CLAUDE.md   .gitignore
— NOT yet created (Plan 7+): Apps/SeretTV/, Apps/SeretMobile/, Shared/DebridUI/, project.yml, Secrets.xcconfig
```

## Build / run / test

**Now (package-only — there is no Xcode project yet):**
```bash
swift test --package-path Packages/DebridCore                              # the whole brain; fast, no simulator
swift build --package-path Packages/DebridCore 2>&1 | grep -i warning      # must print NOTHING — zero-warning bar
```
Run the **full** suite (not just `--filter`) before merging. Any new suite that uses `MockURLProtocol` MUST be nested under the `MockTests` serialized parent (`extension MockTests { @Suite struct … { init() { MockURLProtocol.handler = nil } } }`) — Swift Testing runs separate suites in parallel and they share the mock's global handler. **SwiftData suites must nest under the serialized `SwiftDataSuite` parent** — per-suite `.serialized` is NOT enough once there are two SwiftData suites; they would run concurrently with each other (Swift Testing's `.serialized` only orders tests *within* a suite). Two concurrent in-memory `ModelContainer`s intermittently SIGSEGV the test runner (~17% crash rate). Nest them as `extension SwiftDataSuite { @Suite struct … { … } }`, exactly as `MockTests` works for network-mock suites. Pure suites (no network, no SwiftData) stay plain top-level structs.

**Later (once app targets exist — Plan 7):** `xcodegen generate` → `xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build`. **Verify UI in the actual simulator (screenshot) before claiming done** — the simulator is the source of truth, not a browser.

## External services & secrets

| Service | Auth | Notes |
|---|---|---|
| **Real-Debrid** | OAuth2 **device-code**, public client `X245A4XAIBGVM` (no secret) | Per-user tokens → **Keychain**. Resource base `https://api.real-debrid.com/rest/1.0`; OAuth base `…/oauth/v2`. |
| **TMDB** | Free API key (v3 `api_key` query param) | Needed only at app-wiring (Plan 7); the package mocks it in tests. Put in `Secrets.xcconfig` (gitignored). |
| **OpenSubtitles** | API key + login | `api.opensubtitles.com/api/v1`. Free tier has a daily download cap. Plan 6. |

**Never commit secrets. Never log RD tokens or unrestricted URLs.** (The TMDB key rides in the query string — fine, nothing logs it; just don't add request-URL logging on resource calls.)

## Domain glossary

- **Real-Debrid (RD)** — premium link/“debrid” service; turns cached torrents into direct HTTPS streams.
- **unrestrict** — RD call that converts a restricted link → a direct streamable URL (resolved lazily, at play time; links expire).
- **DMM** — Debrid Media Manager (debridmediamanager.com), the open-source web app the owner adds content with today.
- **Zurg + rclone** — tools that currently mount RD as a filesystem for Plex; Seret makes them unnecessary.
- **Instant RD** — DMM's "add this cached torrent to my RD account now" action (the later Add flow that replaces DMM).

## Key decisions (why)

- **No server / direct-to-RD** — DMM proves a pure client works; native apps skip even DMM's CORS proxy.
- **VLCKit, not AVPlayer** — AVPlayer can't open MKV/x265/DTS/ASS; Plex only worked by transcoding on a server we don't have.
- **TMDB** for recognize/organize; **OpenSubtitles** for subs (behind a `SubtitleProvider` seam so an Israeli-Hebrew source can slot in later).
- **SwiftData (+CloudKit-ready)** — local cache + user state over RD-as-source-of-truth; cross-device sync later for free.
- **Device-code auth** — the native Apple-TV sign-in pattern; zero keyboard pain.

## Conventions (followed throughout — keep doing these)

- **TDD:** failing test → minimal impl → green → commit. Small atomic commits (`feat(core):` / `refactor(core):` / `fix(core):` / `test(core):`).
- **Swift 6 value types, `Sendable`**, immutable `let` fields + public memberwise inits on models; protocol seams for injection (`AccessTokenProviding`, later `SubtitleProvider`/`VideoPlayerEngine`).
- **Zero warnings.** Cache compiled regexes / expensive things as `static let`. Tests assert real values, not just non-nil.
- **One responsibility per file**; new logic goes in the matching `DebridCore` subfolder.

## Gotchas

- VLCKit is **Objective-C + per-platform** (`TVVLCKit` ≠ `MobileVLCKit`). Wrap behind `VideoPlayerEngine`; keep `DebridCore` VLCKit-free.
- RD **rate-limits**; refresh tokens on `401`; unrestricted links **expire** (resolve at play time, never store).
- **RD throttles `oauth/v2/device/code?new_credentials=yes` HARD.** A burst of device-code generations (e.g. repeated tvOS test launches / Try-Again taps) gets a bare **HTTP 403** `{"error":null,"error_code":null}` with an undocumented, long ("undefined") cooldown — *not* the documented 250 req/min REST limit (that returns 429). A real user signs in **once** and never trips it, so when verifying the tvOS sign-in **do NOT relaunch/retry repeatedly** — it locks you out for a long while (root-caused the hard way in Plan 7a). The simulator and a real Apple TV share one bucket (same OS TLS fingerprint); curl/host has a separate, unthrottled bucket — handy to generate a code out-of-band for verification. `SignInModel.message(for:)` maps 403/429 to a clear "Real-Debrid is busy, wait a minute" message.
- Swift Testing runs suites **in parallel** — network-mock suites must nest under `MockTests` (serialized) or they race on the shared handler.
- SwiftData+CloudKit (Plan 6) needs **all properties optional or defaulted, no unique constraints**.
- RD removed `instantAvailability`; cache-checking for the later Add flow needs research.
- **`xcodebuild test` / SwiftUI previews fail at runner-launch with `Pseudo Terminal Setup Error, ErrorCode 7, Errno 6 ("Device not configured")`** on `appletvsimulator26.5` during long agent sessions — this is the known **Claude.app pty-pool exhaustion** (Claude leaks ptys; **fix = restart the Claude desktop app**, then retry). It persisted in-session here (disabling the Bash sandbox didn't help — only a Claude restart frees the pool), which is why a multi-subagent session can't run app tests until restarted. What works WITHOUT a restart: `swift test` (DebridCore — no sim) and `xcodebuild build`/`build-for-testing` (compile, no launch). So app-target unit tests (`⌘U`) + sim screenshots run either after a Claude restart or straight from the Xcode GUI.

## Open follow-ups (non-blocking, from reviews)

- DRY the video-extension set — duplicated in `LibraryBuilder.isVideoPath`, `TorrentInfo.primaryVideoFile`, `FilenameParser.stripExtension` → one shared constant.
- `RealDebridSession`: add a concurrent-refresh-coalescing test (behavior verified by inspection, not yet by a test).
- `TMDBSearchResult.year`: guard against a sub-4-char date string.
- Enrichment v2: title-similarity scoring (currently takes the first TMDB result); backdrops via a `details` call.
- `TorrentsClient.allTorrentInfos()` fans out **unbounded** (one `info` call per torrent) and `MetadataEnricher.enrich(_:)` likewise — add a concurrency cap once RD/TMDB rate-limit behavior is characterized (flagged in Plan 5 review; `// TODO` in `TorrentsClient`).
- `LibraryService.refresh()`: `hasDelta` derives cached torrent ids from library *items*, so an RD account holding torrents that yield no item (non-video/empty) triggers a full refresh every cycle (perf-only — TMDB stays bounded via carry-over). To make the cheap path exact, persist the seen-torrent-id set in `LibrarySnapshot`.
- Retire the `DebridCore.name` smoke scaffolding once real app entry points exist (Plan 7).

## Working style (owner = Shahar)

- **Optimize for the long run** — choose the approach that ages well, allows polish, and scales; lead with that, not the smallest diff. Direct, no fluff.
- **Verify before claiming done** — run it; for UI, screenshot the simulator. Evidence before assertions.
- **Git:** commit locally; **don't push without asking** (owner has chosen "merge to main + push" after each reviewed plan, but ask each time). Branch before working on `main`. Never push secrets.
- Between **03:00–07:00** the owner should be asleep — if it's that late, wrap to a clean committed state and say so; don't start new substantive work.

## Roadmap (milestone view)

1. **Stage 1 (in progress)** — `DebridCore` brain (Plans 1–6) + the tvOS & iOS/iPad apps (Plans 7–8): browse · organize · play. → off Plex.
2. **Stage 2** — in-app search → Instant RD Add flow. → off DMM. *(hard part: torrent indexing + RD cache-check.)*
3. **Stage 3** — CloudKit Continue-Watching sync, richer organization, AVPlayer fast-path for hardware-decodable files.
