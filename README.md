# Seret

**Seret** (Hebrew *סרט*, "film") is a free, self-contained media app for **Apple TV, iPhone, and iPad** — a Plex replacement powered by [Real-Debrid](https://real-debrid.com). It talks directly to the Real-Debrid API (no media server, no Synology, no Plex Pass), recognizes and organizes your library via [TMDB](https://www.themoviedb.org), fetches subtitles via [OpenSubtitles](https://www.opensubtitles.com), shows ratings via [OMDb](https://www.omdbapi.com), and plays everything on-device with [VLCKit](https://code.videolan.org/videolan/VLCKit).

One brain, three faces: all logic lives in the pure, tested `DebridCore` Swift package; each platform gets native SwiftUI on top.

---

## Requirements

- **macOS** with **Xcode 16+** (Swift 6)
- **[XcodeGen](https://github.com/yonsm/XcodeGen)** — `brew install xcodegen` (the `.xcodeproj` is generated, not committed)
- A **[Real-Debrid](https://real-debrid.com)** account (premium) to actually stream

## API keys & accounts you'll need

Seret talks to a few external services. **None of these keys ship with the repo — you supply your own.** Some are required, some just light up extra features.

| Service | Key / account | Required? | Get it from | What it powers |
|---|---|---|---|---|
| **Real-Debrid** | Your RD account (sign in inside the app) | **Required** | [real-debrid.com](https://real-debrid.com) | Streaming. Sign in on first launch via device-code, or paste a personal API token from [real-debrid.com/apitoken](https://real-debrid.com/apitoken). No developer key needed. |
| **TMDB** | `TMDB_API_KEY` (v3) | **Required** | [themoviedb.org → Settings → API](https://www.themoviedb.org/settings/api) | Title recognition, posters, metadata, browse rows. |
| **OpenSubtitles** | `OPENSUBTITLES_API_KEY` + account login in Settings | Optional | [opensubtitles.com/consumers](https://www.opensubtitles.com/en/consumers) | Subtitle search/download. Empty key = subtitles off. |
| **OMDb** | `OMDB_API_KEY` | Optional | [omdbapi.com/apikey.aspx](https://www.omdbapi.com/apikey.aspx) (free tier = 1,000/day) | IMDb / Rotten Tomatoes / Metacritic ratings on detail screens. Empty key = ratings off. |

> ⚠️ **Never commit your keys.** They go in `Secrets.xcconfig`, which is **gitignored**. Only the blank `Secrets.example.xcconfig` template is tracked. Don't paste real keys into committed files, issues, or PRs.

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

# 3. Vendor the VLCKit framework (~500 MB unified xcframework)
./Scripts/fetch-frameworks.sh

# 4. Generate the Xcode project
xcodegen generate

# 5. Open and run
open Seret.xcodeproj
#   Schemes: SeretTV (Apple TV) · SeretMobile (iPhone / iPad)
```

On first launch, sign in with your Real-Debrid account (device-code, or paste a personal API token).

## Build & test from the CLI

```bash
# The brain (no simulator needed) — fast unit tests
swift test --package-path Packages/DebridCore
swift test --package-path Shared/DebridUI

# The apps
xcodebuild -scheme SeretMobile -destination 'generic/platform=iOS Simulator' build
xcodebuild -scheme SeretTV    -destination 'generic/platform=tvOS Simulator' build
```

## Architecture

```
DebridCore (pure Swift, no UI, no VLCKit, unit-tested)
  Networking · RealDebrid (auth + resources) · Metadata (parse + TMDB + OMDb)
  Library (grouping + enrich) · Subtitles (OpenSubtitles) · Persistence (SwiftData) · Playback
        ▲                                        ▲
   SeretTV (tvOS)                          SeretMobile (iOS / iPadOS)
   sidebar · focus · VLCKit                tab bar / split · VLCKit
        └──────────── shared DebridUI (view-models, seams, design tokens) ───────────┘
```

The rule: networking, parsing, and RD/TMDB/OpenSubtitles/OMDb logic live in `DebridCore`. Only UI and the VLCKit engine are per-platform.

## License

Personal project. Not affiliated with Real-Debrid, TMDB, OpenSubtitles, or OMDb. You are responsible for your own use of those services and of any content you stream.
