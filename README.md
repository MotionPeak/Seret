# Seret · סרט

**Seret** (Hebrew *סרט*, "film") is a free, self-contained streaming app for **Apple TV, iPhone, and iPad** — a Plex replacement powered by [Real-Debrid](https://real-debrid.com). It talks **directly** to the Real-Debrid API (no media server, no Synology, no Plex Pass, no rclone mount), recognizes and organizes your library via [TMDB](https://www.themoviedb.org), plays everything on-device with [VLCKit](https://code.videolan.org/videolan/VLCKit), pulls subtitles from [OpenSubtitles](https://www.opensubtitles.com), ratings from [OMDb](https://www.omdbapi.com), and keeps your progress in sync across devices with iCloud.

It replaces this whole stack — `DMM → Real-Debrid → Zurg + rclone mount → Plex Server (Synology) → Plex app` — with a single native app. Seret is the app *and* the server *and* the organizer, all on-device.

> **One brain, three faces.** All logic lives once in the pure, fully-tested `DebridCore` Swift package. Each platform gets *native* SwiftUI on top. Share the brain, not the screens.

There is no App Store build — you build it yourself in Xcode and run it on your own simulator or devices. This README walks you through it from zero. **The fastest way to try it is the Simulator (≈10 minutes, no Apple Developer account needed)** — jump to [Quick start](#quick-start-simulator).

---

## Features

| Area | What it does |
|---|---|
| **Library** | Reads your Real-Debrid torrents, groups them into movies & shows (season-pack expansion, cross-torrent show merge, dedup), and enriches each with TMDB posters, metadata, and episode data. Cache-first — opens instantly, refreshes in the background, only new content hits TMDB. |
| **Playback** | On-device **VLCKit 4 (Metal)** player that plays what AVPlayer can't — MKV, x265/HEVC, DTS/TrueHD, ASS subtitles. Resume from where you left off, swipe/click to seek, version picker, retry / try-another-version. |
| **Subtitles** | On-demand Hebrew & English subtitles via OpenSubtitles, cached locally so the daily quota isn't re-spent. Remembers your last-used audio + subtitle track **by language** and re-applies it automatically. |
| **Browse / Discover** | Lazy, segmented browse — genres, decades, trending, top-rated, recommendations, plus a personalized **For You** rail seeded from what you've watched. |
| **Profiles** | Netflix-style **Who's Watching** — multiple profiles on one shared Real-Debrid account, each with its own avatar, Continue Watching, and My List. |
| **Sync** | **iCloud (CloudKit)** cross-device sync of watch progress — start on the Apple TV, finish on your iPhone. Local-only fallback when no iCloud account is present. |
| **Ratings & trailers** | IMDb / Rotten Tomatoes / Metacritic ratings (OMDb) on detail screens, plus in-app trailers. |
| **Downloads** | Save titles for offline-style playback. |

**Platforms:** **SeretTV** (Apple TV / tvOS — focus sidebar, Siri-remote transport, in-player episode strip) and **SeretMobile** (universal iPhone + iPad — adaptive tab bar / split view, touch-gesture player).

---

## Before you start

You'll need:

| | What | Notes |
|---|---|---|
| 🖥️ | A **Mac** running **macOS 14+** | Required to build with Xcode. |
| 🛠️ | **Xcode 16 or newer** | Free from the [Mac App Store](https://apps.apple.com/app/xcode/id497799835). Open it once after installing so it finishes setup. |
| 📦 | **XcodeGen** | `brew install xcodegen`. (The `.xcodeproj` is generated from `project.yml`, not committed.) If you don't have Homebrew, get it at [brew.sh](https://brew.sh). |
| 🎬 | A **premium [Real-Debrid](https://real-debrid.com)** account | This is what actually streams your content. A free RD account won't stream. |
| 🔑 | A free **TMDB** API key | Required for posters/metadata — see below. (OMDb + OpenSubtitles keys are optional.) |
| 💾 | **~1.5 GB** free disk | ~500 MB of it is the vendored VLCKit framework. |
| 📺 | *(optional)* an **Apple TV / iPhone / iPad on tvOS/iOS 18+** | Only if you want to run on real hardware instead of the Simulator. Requires an Apple ID for signing — see [Run on a real device](#run-on-a-real-apple-tv--iphone--ipad). |

---

## Step 1 — Get your API keys

Seret talks to a few external services. **None of these keys ship with the repo — you supply your own.** Only TMDB is required; the rest just light up extra features.

| Service | Required? | How to get it |
|---|---|---|
| **Real-Debrid** | **Required** to stream | Just a premium **account** — no developer key. You sign in *inside the app*. Tip: grab a personal API token now from **[real-debrid.com/apitoken](https://real-debrid.com/apitoken)** — pasting it is the most reliable way to sign in (especially on Apple TV). |
| **TMDB** (`TMDB_API_KEY`) | **Required** | Make a free account at [themoviedb.org](https://www.themoviedb.org/signup) → **Settings → API** ([direct link](https://www.themoviedb.org/settings/api)) → request a key (choose "Developer", fill in anything reasonable). Copy the **API Key (v3 auth)** — a 32-char hex string. |
| **OMDb** (`OMDB_API_KEY`) | Optional — IMDb/RT/Metacritic ratings | Free key at [omdbapi.com/apikey.aspx](https://www.omdbapi.com/apikey.aspx) (pick "FREE, 1,000/day"). They email you a key; click the activation link in that email. Leave blank = ratings off. |
| **OpenSubtitles** (`OPENSUBTITLES_API_KEY`) | Optional — subtitle download | Register a consumer at [opensubtitles.com/consumers](https://www.opensubtitles.com/en/consumers) for an API key, **and** sign in with your OpenSubtitles account inside the app's Settings. Leave blank = subtitles off. |

You can start with just the **TMDB key + a Real-Debrid account** and add the others later.

---

## Quick start (Simulator)

The Simulator path needs **no Apple Developer account and no code-signing** — it's the fastest way to see Seret running.

```bash
# 1. Clone
git clone https://github.com/MotionPeak/Seret.git
cd Seret

# 2. Create your secrets file from the template, then fill in your key(s)
cp Secrets.example.xcconfig Secrets.xcconfig
open -e Secrets.xcconfig        # or edit in any text editor
#   set at least:
#     TMDB_API_KEY = your_tmdb_v3_key      (required)
#     OMDB_API_KEY = your_omdb_key         (optional)
#     OPENSUBTITLES_API_KEY = your_key     (optional)

# 3. Download the VLCKit framework (~500 MB, one-time; verifies a SHA-256)
./Scripts/fetch-frameworks.sh

# 4. Generate the Xcode project (re-run after any project.yml or framework change)
xcodegen generate

# 5. Open it
open Seret.xcodeproj
```

Then in Xcode:

1. Pick a **scheme** (top-left, next to the run button): **SeretTV** or **SeretMobile**.
2. Pick a **Simulator destination** — e.g. *Apple TV 4K* for SeretTV, or *iPhone 16 / iPad Pro* for SeretMobile.
3. Press **▶ Run** (`⌘R`).
4. On first launch, **sign in to Real-Debrid** — tap **"Use a Real-Debrid token instead"** and paste the token from [real-debrid.com/apitoken](https://real-debrid.com/apitoken). (The device-code option works too, but the token is more reliable — see [Troubleshooting](#troubleshooting).)

That's it — your Real-Debrid library should load. The Simulator ignores the app's signing/iCloud settings, so nothing else needs changing. (Cross-device iCloud sync just won't run there; everything else does.)

> **Note on video in the Simulator:** real playback works in recent simulators, but hardware video decoding is best on a real device. If something won't play in the Simulator, try it on actual hardware.

---

## Run on a real Apple TV / iPhone / iPad

The project ships with the original author's signing identity, so to put it on **your own hardware** you must point it at **your** Apple ID and remove the author's iCloud container. A **free Apple ID works** (no paid Developer Program needed) — apps signed with a free account just expire after 7 days and need a re-run from Xcode to refresh.

**1. Add your Apple ID to Xcode** — Xcode → Settings → Accounts → **+** → Apple ID.

**2. Point the project at your team and your bundle IDs.** Edit `project.yml` and change these to your own (then re-run `xcodegen generate`):

```yaml
# top of the file
options:
  bundleIdPrefix: com.yourname.seret          # was com.solomons.seret

# SeretTV target settings
PRODUCT_BUNDLE_IDENTIFIER: com.yourname.seret.tv      # was com.solomons.seret.tv
DEVELOPMENT_TEAM: YOURTEAMID                           # was ML9HDN3QZS  (see below)

# SeretMobile target settings
PRODUCT_BUNDLE_IDENTIFIER: com.yourname.seret.mobile  # was com.solomons.seret.mobile
DEVELOPMENT_TEAM: YOURTEAMID
```

Find **YOURTEAMID** in Xcode → Settings → Accounts → (your Apple ID) → your team → it's the 10-character ID, or look at *Manage Certificates*. (Alternatively, leave `DEVELOPMENT_TEAM` blank, open the project, and set the Team in each target's **Signing & Capabilities** tab from the dropdown.)

**3. Deal with iCloud (required to build with your own team).** The app is configured for the author's CloudKit container `iCloud.com.solomons.seret`, which **you can't sign**. Pick one:

- **Simplest (recommended) — turn iCloud off.** Cross-device watch sync is disabled; everything else works (progress is saved locally). Replace the contents of **both** `Apps/SeretTV/SeretTV.entitlements` and `Apps/SeretMobile/SeretMobile.entitlements` with an empty entitlements file:
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0"><dict/></plist>
  ```
  *(Free Apple IDs can't use CloudKit at all, so this is the only option for them.)*
- **Keep iCloud sync (paid Apple Developer Program only).** In both `.entitlements` files change `iCloud.com.solomons.seret` to your own container, e.g. `iCloud.com.yourname.seret`, then enable **iCloud → CloudKit** for both targets in Xcode's Signing & Capabilities (this creates the container in your account). For a release/TestFlight build you must also deploy the CloudKit schema to Production in the [CloudKit console](https://icloud.developer.apple.com).

**4. Generate, build, run.**
```bash
xcodegen generate
open Seret.xcodeproj
```
Select your **device** (not a Simulator) as the destination and press **▶ Run**.

**5. Trust the app on the device** (first run only). On the Apple TV / iPhone go to **Settings → General → VPN & Device Management** → tap your developer profile → **Trust**.

---

## Signing in to Real-Debrid

On first launch you have two options:

- **Paste an API token** *(recommended)* — tap **"Use a Real-Debrid token instead"**, paste the token from [real-debrid.com/apitoken](https://real-debrid.com/apitoken). Most reliable, and the right choice on a real Apple TV.
- **Device code** — a code appears on screen; enter it at [real-debrid.com/device](https://real-debrid.com/device). Works, but RD rate-limits this endpoint hard — don't spam it (see Troubleshooting).

---

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

---

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

**The rule:** networking, parsing, and all RD / TMDB / OpenSubtitles / OMDb logic live in `DebridCore`. View-models and seams live in `Shared/DebridUI`. The VLCKit engine lives in `Shared/SeretPlayer`. Only the actual screens are per-platform.

| Module | Kind | Responsibility |
|---|---|---|
| `Packages/DebridCore` | Swift package (no deps, no UI) | The brain: networking, RD auth + resources, recognition, library grouping, TMDB/OMDb enrichment, subtitles, SwiftData persistence + CloudKit, playback coordination |
| `Shared/DebridUI` | Shared source | View-models (`AppSession`, `LibraryStore`, `DetailStore`, `PlayerModel`, `SettingsModel`…), provider seams, design tokens |
| `Shared/SeretPlayer` | Shared source | `VLCKitVideoPlayerEngine` + `VLCVideoView` (VLCKit is platform-specific, kept out of the brain) |
| `Apps/SeretTV` | tvOS app | Focus-driven SwiftUI screens |
| `Apps/SeretMobile` | iOS / iPadOS app | Adaptive touch SwiftUI screens |

### Repo layout

```
Packages/DebridCore/        ← THE BRAIN (all logic + Swift Testing suites)
Shared/DebridUI/            ← shared view-models, seams, design tokens
Shared/SeretPlayer/         ← shared VLCKit engine + video view
Apps/SeretTV/               ← tvOS app + tests
Apps/SeretMobile/           ← iPhone / iPad app + tests
Scripts/                    ← fetch-frameworks.sh, asset/icon generators
project.yml                 ← XcodeGen project definition (generates Seret.xcodeproj)
Secrets.example.xcconfig    ← committed template (copy to gitignored Secrets.xcconfig)
Frameworks/                 ← VLCKit.xcframework lands here (gitignored, fetched by the script)
```

> **Never commit your keys.** They live in `Secrets.xcconfig`, which is **gitignored**; only the blank `Secrets.example.xcconfig` template is tracked. Seret never logs RD tokens or unrestricted URLs.

---

## Troubleshooting

- **"Signing for SeretTV requires a development team."** You're building for a real device without setting your team — follow [Run on a real device](#run-on-a-real-apple-tv--iphone--ipad). (The Simulator doesn't need this.)
- **Build fails on the iCloud / CloudKit capability, or "container … is not a member of this team".** That's the author's `iCloud.com.solomons.seret` container. Remove iCloud (empty the two `.entitlements` files) or switch to your own container — see step 3 above.
- **Real-Debrid sign-in says "busy, wait a minute" / returns 403.** RD hard-throttles the device-code endpoint, and a real Apple TV can get a *persistent* 403. **Fix: use "Use a Real-Debrid token instead"** and paste a personal token from [real-debrid.com/apitoken](https://real-debrid.com/apitoken). Don't keep retrying device-code — it extends the cooldown.
- **`VLCLibrary.h modified since module file`.** Re-run `./Scripts/fetch-frameworks.sh`, then in Xcode do **Product → Clean Build Folder** (`⇧⌘K`) and rebuild. Mandatory after any framework change.
- **`xcodebuild` / Xcode reports "found no destinations".** Your installed Simulator runtime is older than the SDK. Install the matching runtime in **Xcode → Settings → Components** (e.g. the iOS/tvOS 18 runtime).
- **Project won't open, or targets are missing.** Run `xcodegen generate` — the `.xcodeproj` is generated from `project.yml` and is not committed.
- **`fetch-frameworks.sh` fails a checksum / download.** Re-run it (it retries); make sure you have ~500 MB free and a working connection. It pins a specific VLCKit build and verifies its SHA-256.
- **App on a real device stops launching after about a week.** Free Apple IDs sign apps for 7 days. Just re-run from Xcode to refresh, or join the paid Developer Program for a year.
- **The scrub bar / controls are cut off at the edges of your TV.** That's your TV's overscan — set its picture/aspect mode to **"Just Scan" / "Screen Fit" / "1:1"**.

---

## Roadmap

1. **Stage 1 — off Plex** *(done):* the `DebridCore` brain + the tvOS and iPhone/iPad apps — browse · organize · play, with profiles and CloudKit Continue-Watching sync.
2. **Stage 2 — off DMM** *(in progress):* in-app search → Instant RD Add, so you never leave the app to add content. (Lives on the `feat/stage2-search-add` branch.)
3. **Stage 3:** richer organization, an AVPlayer fast-path for hardware-decodable files, and broader sync.

## License

Personal project, shared as-is. Not affiliated with Real-Debrid, TMDB, OpenSubtitles, or OMDb. You are responsible for your own use of those services and of any content you stream.
