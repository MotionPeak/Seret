# Session Handoff — Trailers + Player Fixes (2026-06-08)

**Branch:** `feat/stage2-search-add` — all work committed & **pushed** (origin @ `d7712fe`).
**Verified on:** iPhone 17 Pro sim (signed in with the RD token). tvOS = builds clean, on-device verify owner-pending (the tvOS sim isn't drivable in this dev env).

---

## What shipped this session

### Trailers — reliable playback + auto-play (iOS + tvOS) ✅
The original problem: YouTube embeds failed with **Error 152/153** on real devices (YouTube's
systemic anti-embed clampdown). Re-architected end to end.

- **Spec:** `docs/superpowers/specs/2026-06-08-trailer-playback-autoplay-design.md`
- **Plans:** `docs/superpowers/plans/2026-06-08-trailers-slice1-extraction.md`, `…-slice2-ios-ui.md`
- **Approach:** stop embedding YouTube; **extract a direct stream URL** with **YouTubeKit**
  (new SPM dep in `Shared/DebridUI`) → play with **AVPlayer** (right tool for standard-codec
  trailers; VLCKit stays for RD media). The hand-rolled InnerTube spike failed (po-token wall);
  YouTubeKit cleared it (proven live: resolves a 360p progressive MP4).
- **Slice 1 (DebridUI foundation):** `TrailerStreamResolving` seam + `YouTubeKitStreamResolver`,
  `TrailerSettingsModel` (persisted `autoplayTrailers`), `TrailerModel` (key→stream, deep-link
  fallback), `AppSession.makeTrailerModel()`. **DebridUI 132 tests green, 0 warnings.**
- **Detail UI (both apps):** a **contained hero banner** — TMDB backdrop → muted auto-play
  trailer (~4s, delay overlaps extraction), fading into the solid canvas; title/Play/overview
  below (always legible). **iOS:** inline 🔇/🔊 **unmute** + ⤢ expand; **tap** the hero → full-screen
  with sound. **tvOS:** **swipe up** on the action row → full-screen with sound; muted hero keeps
  playing underneath; Menu returns with focus on Play. The redundant **Trailer button removed**
  from both Detail screens (kept on the Add screen, which has no auto-play). Extraction-fail →
  deep-link to YouTube.
- **Verified on the iPhone sim:** Streetwise + Family Guy — hero plays, margins correct, unmute
  toggles inline sound, tap/expand opens full-screen.

### Bug fixes
- **Hero width overflow (iOS):** the aspect-fill backdrop dictated the hero width (~16:9 of its
  height > screen) so content was clipped off the left edge. Fixed with a fixed-size `Color.clear`
  base + clipped overlays. (`ced28b7`, `f65e05b`, `3a0a2b4`)
- **tvOS settings panel oversize (#3 below):** Audio/Subtitles/Speed columns now scroll inside a
  640pt-capped box, so many subtitles no longer push the tab bar off-screen. (`d7712fe`)

> The owner committed tvOS player/focus/design work in parallel on the same branch this session
> (e.g. `ab992b1`, `9acc728`, `048fd2d`, `71f722a`, `404ffdb`, `e1ff968`).

### Caveats (baked into the trailer design)
- **YouTubeKit is a maintained dependency** — it will break when YouTube changes its internals;
  the fix is a version bump (a maintenance treadmill, accepted).
- **Trailers play at 360p** — the only muxed progressive format YouTube serves now.

---

## Open bugs (from tonight's testing) — see `memory/project_seret_playback_bugs.md`

| # | Bug | Status | Notes |
|---|-----|--------|-------|
| 1 | **Audio cuts every few seconds** playing **Warfare (2025)** | OPEN | Almost certainly the **TrueHD/DTS-HD** track problem = punch-list **M3**: VLCKit-4's audio/subtitle track API is **stubbed** (`[]`/no-op) in `VLCKitVideoPlayerEngine`, so it can't pick a decodable audio track. Re-downloading another version won't help if it's the same audio format. **Real work; needs the actual stream on a device.** |
| 2 | **App crashed & exited** during open Warfare → download new version → delete from library | OPEN | **Need the crash log** to diagnose — capture it on repro. May tie to the download/delete flow or the track sheet. |
| 3 | **tvOS settings panel grew tall, hid the tab bar** with many subtitles | **FIXED** `d7712fe` | Columns scroll inside a height cap. On-device verify pending. *(If actually hit on the iOS sheet, re-check — that one has detents+scroll.)* |
| 4 | **Scrub bar shows the wrong position** when seeking to a random point (iPhone + iPad) | OPEN | Likely `PlayerModel.position` not re-syncing after a `.seek` (or scrub-preview state not clearing). Check `PlayerView` scrub gestures + position on seek. **Quick once the player's running.** |

---

## What's left for the app — TOMORROW

**Fix the open player bugs (highest priority — they hit real playback):**
1. **Scrub bar wrong-position (#4)** — quickest; chase the seek→position sync with the player running.
2. **Warfare audio cutting (#1 / punch-list M3)** — implement the VLCKit-4 object-based audio/subtitle
   **track API** in `VLCKitVideoPlayerEngine` (currently stubbed), so the player enumerates and
   selects a decodable audio track (default TrueHD-only remuxes to a supported track). Needs a device.
3. **Crash (#2)** — get the crash log, then root-cause.

**Trailers — finish the loop:**
- **On-device verify** the tvOS trailer interaction (swipe-up → full-screen, focus-return) — couldn't
  drive the tvOS sim here.
- Optional: if you want **swipe-down** (not Menu) to exit the full-screen tvOS trailer, say so.

**Bigger remaining (from the roadmap / CLAUDE.md):**
- **Home tab** — Continue Watching + Recently Added (iOS Home exists; round out tvOS / parity).
- **Stage 2 (Search → instant RD Add)** — Slice A (brain) is done & green; finish the DebridUI +
  apps UI slices (the Add screen scaffolding exists).
- **Track prefs (TODO)** — persist audio/subtitle choice **by language** across sessions
  (`memory/project_seret_track_prefs.md`).
- **Merges:** `feat/mobile-foundation` → `main` (real-playback owner-pending), then land this
  `feat/stage2-search-add` line.

---

*Everything above is committed & pushed on `feat/stage2-search-add` (@ `d7712fe`). Nothing in flight.*
