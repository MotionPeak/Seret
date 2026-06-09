# Seret · סרט

**Seret** (Hebrew *סרט*, "film") is a free, self-contained streaming app for **Apple TV, iPhone, and iPad** — a Plex replacement powered by [Real-Debrid](https://real-debrid.com). It talks **directly** to the Real-Debrid API (no media server, no Synology, no Plex Pass, no rclone mount), recognizes and organizes your library via [TMDB](https://www.themoviedb.org), plays everything on-device with [VLCKit](https://code.videolan.org/videolan/VLCKit), pulls subtitles from [OpenSubtitles](https://www.opensubtitles.com), ratings from [OMDb](https://www.omdbapi.com), and keeps your progress in sync across devices with iCloud.

It replaces this whole stack — `DMM → Real-Debrid → Zurg + rclone mount → Plex Server (Synology) → Plex app` — with a single native app. Seret is the app *and* the server *and* the organizer, all on-device.

> **One brain, three faces.** All logic lives once in the pure, fully-tested `DebridCore` Swift package. Each platform gets *native* SwiftUI on top. Share the brain, not the screens.

---

## Features

| Area | What it does |
|---|---|
| **Library** | Reads your Real-Debrid torrents, groups them into movies & shows (season-pack expansion, cross-torrent show merge, dedup), and enriches each with TMDB posters, metadata, and episode data. Cache-first — opens instantly, refreshes in the background, only new content hits TMDB. |
| **Playback** | On-device **VLCKit 4 (Metal)** player that plays what AVPlayer can't — MKV, x265/HEVC, DTS/TrueHD, ASS subtitles. Resume from where you left off, swipe/click to seek, version picker, retry / try-another-version. |
| **Subtitles** | On-demand Hebrew & English subtitles via OpenSubtitles, with downloads cached locally so the daily quota isn't re-spent. Remembers your last-used audio + subtitle track **by language** and re-applies it automatically. |
| **Browse / Discover** | Lazy, segmented browse — genres, decades, trending, top-rated, recommendations, plus a personalized **For You** rail seeded from what you've watched. Rails render progressively as they load. |
| **Profiles** | Netflix-style **Who's Watching** — multiple profiles on one shared Real-Debrid account, each with its own avatar, Continue Watching, and My List. Add / edit / delete profiles. |
| **Sync** | **iCloud (CloudKit)** cross-device sync of watch progress — start on the Apple TV, finish on your iPhone. Resume position and Continue Watching follow you, with a local-only fallback when no iCloud account is present. |
| **Ratings & trailers** | IMDb / Rotten Tomatoes / Metacritic ratings (OMDb) on detail screens, plus in-app trailers. |
| **Downloads** | Save titles for offline-style playback. |

### Platforms

- **SeretTV** — Apple TV (tvOS): focus-driven sidebar, Siri-remote transport, episode peek strip.
- **SeretMobile** — universal iPhone + iPad app: adaptive `TabView` (iPhone) / `NavigationSplitView` (iPad), touch gesture player (tap = controls, double-tap = ±10s, drag = scrub).

---

## Requirements

- **macOS** with **Xcode 16+** (Swift 6, strict concurrency)
- **[XcodeGen](https://github.com/yonsm/XcodeGen)** — `brew install xcodegen` (the `.xcodeproj` is generated, not committed)
- A premium **[Real-Debrid](https://real-debrid.com)** account to actually stream
- ~500 MB of disk for the vendored VLCKit framework

## API keys & accounts you'll need

Seret talks to a few external services. **None of these keys ship with the repo — you supply your own.** Some are required, some just light up extra features.

| Service | Key / account | Required? | Get it from | What it powers |
|---|---|---|---|---|
| **Real-Debrid** | Your RD account (sign in inside the app) | **Required** | [real-debrid.com](https://real-debrid.com) | Streaming. Sign in on first launch via device-code, or paste a personal API token from [real-debrid.com/apitoken](https://real-debrid.com/apitoken). No developer key needed. |
| **TMDB** | `TMDB_API_KEY` (v3) | **Required** | [themoviedb.org → Settings → API](https://www.themoviedb.org/settings/api) | Title recognition, posters, metadata, browse rows. |
| **OpenSubtitles** | `OPENSUBTITLES_API_KEY` + account login in Settings | Optional | [opensubtitles.com/consumers](https://www.opensubtitles.com/en/consumers) | Subtitle search/download. Empty key = subtitles off. |
| **OMDb** | `OMDB_API_KEY` | Optional | [omdbapi.com/apikey.aspx](https://www.omdbapi.com/apikey.aspx) (free tier = 1,000/day) | IMDb / Rotten Tomatoes / Metacritic ratings on detail screens. Empty key = ratings off. |

> ⚠️ **Never commit your keys.** They go in `Secrets.xcconfig`, which is **gitignored**. Only the blank `Secrets.example.xcconfig` template is tracked. Don't paste real keys into committed files, issues, or PRs. Seret never logs RD tokens or unrestricted URLs.

## Setup

```bash
# 1. Clone
git clone https://github.com/MotionPeak/Seret.git
cd Seret

# 2. Create your secrets file from the template, then fill in your keys
cp Secrets.example.xcconfig Secrets.xcconfig
#   edit Secrets.xcconfig:
#     TMDB_API_KEY          = your_tmdb_v3_key        (required)
#     OPENSUBTITLES_API_KEY = your_opensubtitles_key  (optional)
#     OMDB_API_KEY          = your_omdb_key           (optional)

# 3. Vendor the VLCKit framework (~500 MB unified xcframework — has tvOS + iOS slices)
./Scripts/fetch-frameworks.sh

# 4. Generate the Xcode project (must re-run after any project.yml or framework change)
xcodegen generate

# 5. Open and run
open Seret.xcodeproj
#   Schemes: SeretTV (Apple TV) · SeretMobile (iPhone / iPad)
```

On first launch, sign in with your Real-Debrid account — either the on-screen device-code, or paste a personal API token (recommended on a real Apple TV; see Troubleshooting).

## Build & test from the CLI

```bash
# The brain & shared UI — fast, no simulator needed
swift test --package-path Packages/DebridCore     # the pure logic brain
swift test --package-path Shared/DebridUI         # view-models + seams (host-free)

# Zero-warning bar — this must print nothing
swift build --package-path Packages/DebridCore 2>&1 | grep -i warning

# The apps (compile / build for simulator)
xcodebuild -scheme SeretMobile -destination 'generic/platform=iOS Simulator'  build
xcodebuild -scheme SeretTV     -destination 'generic/platform=tvOS Simulator' build
```

## Architecture

```
                 DebridCore  (pure Swift · no UI · no VLCKit · unit-tested)
   Networking · RealDebrid (auth + resources) · Metadata (parse + TMDB + OMDb)
   Library (group + enrich) · Subtitles (OpenSubtitles) · Persistence (SwiftData + CloudKit)
   Playback (VideoPlayerEngine seam + PlaybackCoordinator)
                         ▲                              ▲
                         │                              │
        ┌────────────────┴───────┐        ┌─────────────┴──────────────┐
        │  SeretTV (tvOS)        │        │  SeretMobile (iOS / iPadOS) │
        │  sidebar · focus       │        │  tab bar / split · touch    │
        └────────────────┬───────┘        └─────────────┬──────────────┘
                         │                              │
        Shared/DebridUI  (view-models · provider seams · design tokens)
        Shared/SeretPlayer (VLCKitVideoPlayerEngine + VLCVideoView — both platforms)
```

**The rule:** networking, parsing, and all RD / TMDB / OpenSubtitles / OMDb logic live in `DebridCore`. View-models and seams live in `Shared/DebridUI`. The VLCKit engine lives in `Shared/SeretPlayer`. Only the actual screens are per-platform. If you're about to put logic in an app target — stop, it belongs in `DebridCore`.

| Module | Kind | Responsibility |
|---|---|---|
| `Packages/DebridCore` | Swift package (no deps, no UI) | The brain: networking, RD auth + resources, recognition, library grouping, TMDB/OMDb enrichment, subtitles, SwiftData persistence + CloudKit, playback coordination |
| `Shared/DebridUI` | Shared source | View-models (`AppSession`, `LibraryStore`, `DetailStore`, `PlayerModel`, `SettingsModel`…), provider seams, design tokens |
| `Shared/SeretPlayer` | Shared source | `VLCKitVideoPlayerEngine` + `VLCVideoView` (VLCKit is platform-specific, kept out of the brain) |
| `Apps/SeretTV` | tvOS app | Focus-driven SwiftUI screens |
| `Apps/SeretMobile` | iOS / iPadOS app | Adaptive touch SwiftUI screens |

## Repo layout

```
Packages/DebridCore/        ← THE BRAIN (all logic + Swift Testing suites)
Shared/DebridUI/            ← shared view-models, seams, design tokens
Shared/SeretPlayer/         ← shared VLCKit engine + video view
Apps/SeretTV/               ← tvOS app + tests
Apps/SeretMobile/           ← iPhone / iPad app + tests
Scripts/                    ← fetch-frameworks.sh, asset/icon generators
docs/superpowers/           ← design specs + per-slice implementation plans
project.yml                 ← XcodeGen project definition (generates Seret.xcodeproj)
Secrets.example.xcconfig    ← committed template (copy to gitignored Secrets.xcconfig)
CLAUDE.md                   ← contributor guide / design rationale
```

## Branches

`main` is the integrated, working branch — it carries the tvOS and iOS/iPad apps, the VLCKit player, browse/Discover, profiles, CloudKit sync, downloads, ratings, trailers, and subtitles. Feature branches (`feat/*`, `fix/*`) are kept on the remote for in-flight work and history; in-progress **Stage 2 (in-app Search → Instant RD Add)** lives on `feat/stage2-search-add`.

## Troubleshooting

- **Real-Debrid sign-in says "busy, wait a minute" / returns 403.** RD hard-throttles the device-code endpoint, and a real Apple TV's fingerprint can get a *persistent* 403 on the shared client. **Fix: use "Use a Real-Debrid token instead"** on the sign-in screen — paste a personal token from [real-debrid.com/apitoken](https://real-debrid.com/apitoken). This bypasses device-code entirely and is the recommended path on Apple TV. Don't repeatedly retry device-code — it extends the cooldown.
- **`VLCLibrary.h modified since module file` after updating VLCKit.** Re-run `./Scripts/fetch-frameworks.sh`, then in Xcode do **Product → Clean Build Folder** (mandatory after any framework version swap), then rebuild.
- **`xcodebuild` reports "found no destinations."** Your installed simulator runtime is older than the SDK. Install the matching simulator runtime (e.g. the iOS 26.5 runtime for the 26.5 SDK).
- **Project won't open / targets missing.** Run `xcodegen generate` — the `.xcodeproj` is generated from `project.yml` and is not committed.

## Roadmap

1. **Stage 1 — off Plex** *(done):* the `DebridCore` brain + the tvOS and iPhone/iPad apps — browse · organize · play, with profiles and CloudKit Continue-Watching sync.
2. **Stage 2 — off DMM** *(in progress):* in-app search → Instant RD Add, so you never leave the app to add content.
3. **Stage 3:** richer organization, an AVPlayer fast-path for hardware-decodable files, and broader sync.

## License

Personal project. Not affiliated with Real-Debrid, TMDB, OpenSubtitles, or OMDb. You are responsible for your own use of those services and of any content you stream.
