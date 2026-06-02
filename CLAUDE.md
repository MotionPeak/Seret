# CLAUDE.md — Seret

> Guidance for Claude (and humans) working in this repo. Read this first.
> Full design rationale: [`docs/superpowers/specs/2026-06-02-seret-design.md`](docs/superpowers/specs/2026-06-02-seret-design.md). Per-plan implementation plans live in [`docs/superpowers/plans/`](docs/superpowers/plans/).

## What Seret is

**Seret** (Hebrew *סרט*, "film") is a **free, self-contained media app for Apple TV, iPhone, and iPad** — a Plex replacement powered by **Real-Debrid**. It talks **directly to the Real-Debrid API** (no media server, no Synology, no Plex Pass), **recognizes & organizes** titles via **TMDB**, fetches subtitles via **OpenSubtitles**, and plays everything on-device with **VLCKit**.

It replaces this old stack: `DMM (Instant RD) → Real-Debrid → Zurg+rclone mount → Plex Server (Synology) → Plex app`. Seret is the app *and* the server *and* the organizer, all on-device.

## Status — `DebridCore` data layer complete (Plans 1–5); Plan 6 is next

**The `DebridCore` package is real, on `main` ([github.com/MotionPeak/Seret](https://github.com/MotionPeak/Seret)) — 60 tests green, zero warnings.** Built test-first via the superpowers pipeline (brainstorm → spec → one plan per slice → subagent-driven TDD), each plan adversarially reviewed (spec + code-quality + final) before a fast-forward merge to `main`.

**Done & merged:**
- **Plan 1 — RD auth:** `HTTPClient`/`HTTPError`, device-code `RealDebridAuthClient`, `TokenStore`+`KeychainTokenStore`+`InMemoryTokenStore`, `RealDebridSession` (transparent, concurrency-coalesced refresh).
- **Plan 2 — RD resources:** `Torrent`/`TorrentFile`/`TorrentInfo`(+`primaryVideoFile`/`selectedFilesWithLinks`)/`UnrestrictedLink`; `TorrentsClient` (`torrents`/`info`/`unrestrict`/`playableURL`); `AccessTokenProviding` seam (RealDebridSession conforms).
- **Plan 3 — recognition:** `FilenameParser` → `ParsedRelease` (cached regexes); `TMDBClient` (`searchMovie`/`searchTV`/`movieDetails`/`tvDetails`/static `imageURL`) + `TMDBModels`.
- **Plan 4 — library grouping:** `MediaItem`/`Season`/`Episode`/`MediaSource`/`MediaKind`; `LibraryBuilder.group([TorrentInfo]) -> [MediaItem]` (movies, single episodes, season-pack expansion, cross-torrent show merge, dedup, empty-show filter — pure, no I/O).
- **Plan 5 — TMDB enrichment + RD-fetch glue:** `MetadataEnricher` (`enrich(_ item:)` single-match + concurrent order-preserving batch `enrich(_:)` with graceful per-item degradation) + `MediaItem.withMetadata(...)` (TMDB-rekeyed `id`, keeps parsed title when a match's title is blank); `TorrentsClient.allTorrents()` (paginated) / `allTorrentInfos()` (concurrent info fan-out, skips failures). Pure data layer — TMDB mocked in tests.

### ▶ RESUME HERE — Plan 6 (NOT yet written)

**Plan 5 (TMDB enrichment) is done & merged** ([`docs/superpowers/plans/2026-06-02-tmdb-enrichment.md`](docs/superpowers/plans/2026-06-02-tmdb-enrichment.md)) — `MetadataEnricher` (`enrich(_ item:)` + concurrent batch `enrich(_:)`), `MediaItem.withMetadata(...)`, and `TorrentsClient.allTorrents()`/`allTorrentInfos()`. The brain's **data layer is feature-complete**; the app composes it in ~3 lines:
```swift
let infos   = try await torrentsClient.allTorrentInfos()
let grouped = LibraryBuilder().group(infos)
let library = await MetadataEnricher(tmdb: tmdbClient).enrich(grouped)
```

**Next — Plan 6 (needs planning first):** subtitles (OpenSubtitles, behind a `SubtitleProvider` seam) + SwiftData persistence (cache the library + watch progress) + the `VideoPlayerEngine` protocol. Brainstorm → spec → write the plan into `docs/superpowers/plans/`, then execute it the same way as the prior plans: **superpowers:subagent-driven-development** — branch off `main`, one implementer subagent per task → spec-compliance review → code-quality review (fix loops) → final whole-branch review → fast-forward merge to `main` (ask before push). **Then Plan 7** = Apple TV app — the **first UI** (needs XcodeGen + VLCKit integration + a real TMDB key) · **Plan 8** = iPhone/iPad app.

## The one architectural rule

> **One brain, three faces.** All logic lives once in `DebridCore` (a pure, UI-free, fully-tested Swift package). Each platform gets *native* UI on top. **Share the brain, not the screens.**

If you're tempted to put networking, parsing, RD/TMDB/OpenSubtitles logic, or models in an app target — stop. It belongs in `DebridCore`. The only thing that legitimately lives per-platform is UI and the **VLCKit engine** (VLCKit is platform-specific and UIKit-bound).

## Architecture

```
DebridCore (pure Swift, no UI, no VLCKit, unit-tested)
  ✓ Networking   ✓ RealDebrid(auth+resources)   ✓ Metadata(parse + TMDB)   ✓ Library(grouping + enrich)
  ⋯ Subtitles(SubtitleProvider)   ⋯ Persistence(SwiftData)   ⋯ Playback(VideoPlayerEngine protocol)
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
  Networking/   RealDebrid/   Metadata/   Library/
Packages/DebridCore/Tests/DebridCoreTests/   ← Swift Testing suites
  Support/MockURLProtocol.swift  ·  MockTests.swift (serialized parent for all network-mocked suites)
docs/superpowers/specs/   ← the design spec
docs/superpowers/plans/   ← one implementation plan per slice (Plans 1–5 written)
CLAUDE.md   .gitignore
— NOT yet created (Plan 7+): Apps/SeretTV/, Apps/SeretMobile/, Shared/DebridUI/, project.yml, Secrets.xcconfig
```

## Build / run / test

**Now (package-only — there is no Xcode project yet):**
```bash
swift test --package-path Packages/DebridCore                              # the whole brain; fast, no simulator
swift build --package-path Packages/DebridCore 2>&1 | grep -i warning      # must print NOTHING — zero-warning bar
```
Run the **full** suite (not just `--filter`) before merging. Any new suite that uses `MockURLProtocol` MUST be nested under the `MockTests` serialized parent (`extension MockTests { @Suite struct … { init() { MockURLProtocol.handler = nil } } }`) — Swift Testing runs separate suites in parallel and they share the mock's global handler. Pure (no-network) suites stay plain top-level structs.

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
- Swift Testing runs suites **in parallel** — network-mock suites must nest under `MockTests` (serialized) or they race on the shared handler.
- SwiftData+CloudKit (Plan 6) needs **all properties optional or defaulted, no unique constraints**.
- RD removed `instantAvailability`; cache-checking for the later Add flow needs research.

## Open follow-ups (non-blocking, from reviews)

- DRY the video-extension set — duplicated in `LibraryBuilder.isVideoPath`, `TorrentInfo.primaryVideoFile`, `FilenameParser.stripExtension` → one shared constant.
- `RealDebridSession`: add a concurrent-refresh-coalescing test (behavior verified by inspection, not yet by a test).
- `TMDBSearchResult.year`: guard against a sub-4-char date string.
- Enrichment v2: title-similarity scoring (currently takes the first TMDB result); backdrops via a `details` call.
- `TorrentsClient.allTorrentInfos()` fans out **unbounded** (one `info` call per torrent) and `MetadataEnricher.enrich(_:)` likewise — add a concurrency cap once RD/TMDB rate-limit behavior is characterized (flagged in Plan 5 review; `// TODO` in `TorrentsClient`).
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
