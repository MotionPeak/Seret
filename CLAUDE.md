# CLAUDE.md — Seret

> Guidance for Claude (and humans) working in this repo. Read this first.
> Full design rationale lives in [`docs/superpowers/specs/2026-06-02-seret-design.md`](docs/superpowers/specs/2026-06-02-seret-design.md).

## What Seret is

**Seret** (Hebrew *סרט*, "film") is a **free, self-contained media app for Apple TV, iPhone, and iPad** — a Plex replacement powered by **Real-Debrid**. It talks **directly to the Real-Debrid API** (no media server, no Synology, no Plex Pass), **recognizes & organizes** titles via **TMDB**, fetches subtitles via **OpenSubtitles**, and plays everything on-device with **VLCKit**.

It replaces this old stack: `DMM (Instant RD) → Real-Debrid → Zurg+rclone mount → Plex Server (Synology) → Plex app`. Seret is the app *and* the server *and* the organizer, all on-device.

## Status

**Greenfield — Stage 1 in planning.** Design approved; spec written. No code scaffolded yet. Next step: implementation plan (superpowers `writing-plans`).

## The one architectural rule

> **One brain, three faces.** All logic lives once in `DebridCore` (a pure, UI-free, fully-tested Swift package). Each platform gets *native* UI on top. **Share the brain, not the screens.**

If you're tempted to put networking, parsing, RD/TMDB/OpenSubtitles logic, or models in an app target — stop. It belongs in `DebridCore`. The only thing that legitimately lives per-platform is UI and the **VLCKit engine** (VLCKit is platform-specific and UIKit-bound).

## Architecture (see spec §4–5)

```
DebridCore (pure Swift, no UI, no VLCKit, unit-tested)
  Networking · RealDebrid(auth+resources) · Metadata(parse→match→group)
  Subtitles(SubtitleProvider) · Library · Persistence(SwiftData) · Playback(VideoPlayerEngine protocol)
        ▲                                   ▲
   SeretTV (tvOS)                     Seret (iOS/iPadOS)
   sidebar · focus · TVVLCKit         tab bar / split · MobileVLCKit
        └──────── optional shared DebridUI (design tokens) ────────┘
```

## Tech stack

- **Swift 6.3**, strict concurrency. **SwiftUI** everywhere. **tvOS / iOS / iPadOS 26+** targets.
- **DebridCore**: local Swift Package, no UI dependencies. Tests in **Swift Testing**.
- **Playback**: **VLCKit** (`TVVLCKit` / `MobileVLCKit`) behind `VideoPlayerEngine`. (Raw AVPlayer can't play RD's MKV/x265/DTS — that's why VLCKit.)
- **Persistence**: **SwiftData**, models CloudKit-ready (Stage-3 sync is a config flip).
- **Project**: **XcodeGen** (`project.yml`) generates `Seret.xcodeproj` — it is **not committed**.
- **Lint/format**: **SwiftLint + SwiftFormat** (committed configs, build-phase enforced).

## Repo layout

```
Packages/DebridCore/   ← the shared brain (start here for any logic)
Apps/SeretTV/          ← tvOS UI + TVVLCKit engine
Apps/SeretMobile/      ← iOS/iPadOS UI + MobileVLCKit engine
Shared/DebridUI/       ← optional shared SwiftUI tokens/components
docs/superpowers/specs/← design docs
project.yml            ← regenerate the Xcode project from this
Secrets.xcconfig       ← gitignored; copy from Secrets.example.xcconfig
```

## Build / run / test (intended — created during Stage-1 setup)

```bash
# Generate the Xcode project from project.yml (after any target/file change)
xcodegen generate

# Test the brain (fast, no simulator)
swift test --package-path Packages/DebridCore

# Build/run an app (or open Seret.xcodeproj in Xcode and pick a simulator)
xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build
xcodebuild -scheme Seret   -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

**Always verify UI changes in the actual simulator (screenshot) before claiming done.** For a tvOS/iOS app the simulator is the source of truth — not a browser.

## External services & secrets

| Service | Auth | Notes |
|---|---|---|
| **Real-Debrid** | OAuth2 **device-code**, public client `X245A4XAIBGVM` (no secret) | Per-user tokens → **Keychain**. Base `https://api.real-debrid.com/rest/1.0`. |
| **TMDB** | Free API key | In `Secrets.xcconfig` (gitignored). Recognize/organize + art. |
| **OpenSubtitles** | API key + login | `api.opensubtitles.com/api/v1`. Free tier has a daily download cap. |

**Never commit secrets. Never log RD tokens or unrestricted URLs.**

## Domain glossary

- **Real-Debrid (RD)** — premium link/“debrid” service; turns cached torrents into direct HTTPS streams.
- **unrestrict** — RD call that converts a restricted link → a direct streamable URL (resolved lazily, at play time).
- **DMM** — Debrid Media Manager (debridmediamanager.com), the open-source web app the user adds content with today.
- **Zurg + rclone** — the tools that currently mount RD as a filesystem for Plex; Seret makes them unnecessary.
- **Instant RD** — DMM's "add this cached torrent to my RD account now" action (the Stage-2 Add flow).

## Key decisions (why)

- **No server / direct-to-RD** — DMM proves a pure client works; native apps skip even DMM's CORS proxy. (spec §4, §5.2)
- **VLCKit, not AVPlayer** — AVPlayer can't open MKV/x265/DTS/ASS; Plex only worked by transcoding on a server we don't have. (spec §5.6)
- **TMDB** for recognize/organize; **OpenSubtitles** for subs (behind a `SubtitleProvider` seam so an Israeli-Hebrew source can be added later). (spec §5.3–5.4)
- **SwiftData (+CloudKit-ready)** — local cache + user state over RD-as-source-of-truth; cross-device sync later for free. (spec §5.5)
- **Device-code auth** — the native Apple-TV sign-in pattern; zero keyboard pain. (spec §5.2)

## Gotchas

- VLCKit is **Objective-C + per-platform** (`TVVLCKit` ≠ `MobileVLCKit`). Wrap it behind `VideoPlayerEngine`; keep `DebridCore` VLCKit-free.
- RD **rate-limits**; refresh tokens on `401`; unrestricted links **expire** (resolve at play time, don't store).
- SwiftData+CloudKit requires **all properties optional or defaulted, no unique constraints** — already honored in the models.
- RD removed `instantAvailability`; cache-checking for the Stage-2 Add flow needs research (see spec R1).

## Working style (owner preferences)

- **Optimize for the long run** — choose the approach that ages well, allows polish, and scales; lead with that, not the smallest diff.
- **Verify before claiming done** — run it, screenshot the simulator; evidence before assertions.
- **Git**: commit locally; **don't push** to deploy-connected repos without asking. Branch before working on a default branch.

## Roadmap

1. **Stage 1** (current) — `DebridCore` + tvOS + iOS/iPad: browse · organize · play. → off Plex.
2. **Stage 2** — search → Instant RD Add flow. → off DMM. *(hard part: indexing + RD cache-check)*
3. **Stage 3** — CloudKit Continue-Watching sync, richer organization, AVPlayer fast-path.
