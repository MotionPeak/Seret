# Reliable Trailer Playback + Muted Auto-Play — Design

**Date:** 2026-06-08
**Branch:** `feat/stage2-search-add`
**Apps:** SeretTV (tvOS) + SeretMobile (iOS/iPadOS)

## Problem

Trailers don't play. The current implementation embeds YouTube's player (iOS: WKWebView
`/embed/`; tvOS: deep-link to the YouTube app). On real devices the embed now fails for
**every** video with **Error 152 ("video unavailable")** — YouTube has systemically clamped
down on embedded playback from unrecognized origins. Two bugs were fixed along the way (the
Trailer button never appeared due to an empty-`Group` `.task`; a 153 config error from loading
`/embed/` as a top-level document), but the embed mechanism itself is a dead end. We also want
an Apple-TV-style **muted auto-play** trailer on the detail page, which needs playback that
actually works.

## Goal

Play trailers reliably **in-app** on both platforms, and add a **muted, looping auto-play**
trailer on the movie/show detail backdrop — by **not embedding YouTube's player** at all.

## Decisions (locked in brainstorming)

- **Approach: native playback via stream extraction.** Resolve the trailer's YouTube key to a
  **direct stream URL** and play it with **AVPlayer**. No YouTube embed.
- **Scope:** reliable playback **and** auto-play, built together.
- **Auto-play UX:** muted backdrop, **~4s** delay, cross-fade, unmute control, Trailer button =
  full-screen + sound, stop on leave/scroll, a Settings toggle (default on).
- **Both apps.**
- **Fallback:** extraction fails → no auto-play + deep-link to YouTube.

## How playback works

> Resolve **YouTube key → direct stream URL** via YouTube's **InnerTube player API**
> (`POST https://youtubei.googleapis.com/youtubei/v1/player`) using a **mobile client context**.
> Mobile clients return a ready-to-play **HLS manifest** (`streamingData.hlsManifestUrl`) and/or
> progressive MP4 `formats` whose URLs need **no signature deciphering** — so a ~100-line
> `URLSession` + JSON resolver suffices. **No third-party dependency** (keeps `DebridCore`'s
> no-deps rule), and no YouTube SPM library to rot.

Then play the resolved URL with **`AVPlayer`** (not VLCKit). Trailers are standard H.264/AAC —
the one place AVPlayer is correct (VLCKit exists precisely because AVPlayer *can't* play RD's
MKV/x265). AVPlayer gives mute, loop, native HLS, and an inline `AVPlayerLayer` for the backdrop
for free. **VLCKit remains the engine for actual RD playback** — unchanged.

### ⚠️ Make-or-break spike (gates the UI slices)

Confirm InnerTube returns a playable stream URL for trailers, **before** building UI. Two checks:
1. **`curl`** the InnerTube player API with a mobile client context for a known trailer id;
   confirm a `hlsManifestUrl` or progressive URL comes back.
2. **AVPlayer on the simulator** can play an HLS/MP4 URL (unlike the YouTube embed) — so a real
   trailer can be **verified playing on the sim**.
If InnerTube doesn't pan out (blocked / no URL), fall back to deep-link-only and rethink.

## Architecture

### DebridCore (brain; pure, no deps, TDD)

- **`TrailerStream`** model: the resolved playable stream (`url: URL`, `isHLS: Bool`).
- **`TrailerStreamResolving`** seam: `func streamURL(youTubeKey: String) async throws -> TrailerStream?`.
- **`YouTubeStreamResolver`** (conforms): POSTs to InnerTube with a mobile client context +
  `videoId`, parses `streamingData` — **prefers `hlsManifestUrl`**, else best progressive
  `formats` entry (highest resolution with a direct `url`). Returns nil on no playable stream.
  Pure networking; unit-tested against mocked InnerTube JSON.
- The existing **`TrailerProviding`** (TMDB `/videos` → YouTube key) is unchanged; this is the
  second hop (key → stream URL).

### DebridUI (shared view-model)

- **`TrailerModel`** (`@MainActor @Observable`): one model both apps reuse. State machine:
  `idle → resolving → ready(TrailerStream) → failed`. Owns: the YouTube-key resolve + stream
  resolve, the **autoplay-enabled** setting read, mute state, and the **~4s auto-play delay**.
  Exposes: `prepare(tmdbID:kind:)`, `autoPlayURL` (muted backdrop, after delay, if enabled),
  `fullScreenURL` (unmuted, on demand), `markFailed`/fallback signal.
- **Autoplay setting**: a small persisted preference (`autoplayTrailers`, default true),
  mirroring `SubtitleSettingsModel`; survives sign-out.

### Apps (thin, per-platform)

- **Inline muted player** (`AVPlayerLayer` in a `UIViewRepresentable`/`UIViewControllerRepresentable`):
  loops, muted, with an **unmute speaker** overlay; sits in the detail hero, cross-fading in over
  the backdrop after the delay. Torn down on disappear / scroll-off.
- **Full-screen trailer player** (AVPlayer): from the Trailer button or tapping the inline video —
  unmuted, from start. iOS presents a sheet/cover; tvOS pushes/presents focus-aware.
- **Trailer button**: now plays in-app. **Fallback**: if resolve fails, opens YouTube
  (iOS `https://youtube.com/watch?v=KEY` / `youtube://`; tvOS the existing `youtube://` deep link).
- Replaces: iOS WKWebView `TrailerView`/`YouTubeEmbed`; tvOS deep-link-only `TrailerButton`
  (deep link kept as fallback).

## Auto-play behavior (detail page)

1. Detail opens → `TrailerModel.prepare(...)` resolves key → stream URL in the background.
2. If `autoplayTrailers` is on and the stream is ready, after **~4s** the backdrop image
   **cross-fades** to the trailer playing **muted + looping** inline.
3. **Speaker button** unmutes in place. Tapping the video (or the Trailer button) → **full-screen,
   unmuted, from start**.
4. Leaving the detail or scrolling the hero off-screen **stops + tears down** the player.
5. **Settings → Autoplay trailers** toggles the behavior (default on).

## Error handling

- Key not found (no TMDB trailer) → no button, no auto-play (unchanged from today).
- Stream extraction fails / InnerTube blocked → no auto-play; Trailer button **deep-links to
  YouTube**. Never shows a broken embed.
- Network/transport errors are swallowed into the fallback path.

## Testing

- **DebridCore:** `YouTubeStreamResolver` parse tests (mocked InnerTube JSON: HLS-present,
  progressive-only, none → nil) under `MockTests`. Plus the **live spike** (curl).
- **DebridUI:** `TrailerModel` state tests with fakes (resolve→ready, mute/unmute,
  fail→fallback, autoplay-off suppresses auto-play, the delay gates auto-play).
- **Apps:** build clean (0 warnings). **Verify a real trailer plays on the iPhone sim**
  (AVPlayer can play the extracted URL). On-device confirm of the muted-backdrop cross-fade feel
  (owner-pending, like other UX DoD).

## Delivery slices

1. **Brain + spike** — `TrailerStream`, `TrailerStreamResolving`, `YouTubeStreamResolver` (TDD),
   and the InnerTube spike proving a playable URL.
2. **iOS** — AVPlayer trailer: full-screen tap-to-play + muted auto-play backdrop + unmute +
   Settings toggle + YouTube fallback. Verify on the sim.
3. **tvOS** — same, focus-aware; Trailer button plays in-app, deep-link kept as fallback.

## Out of scope (YAGNI)

- Caching/pre-resolving trailers across the grid.
- Picture-in-Picture for trailers.
- Quality selection (just take HLS, or the best progressive).
- Trailers for episodes (title-level only, as today).
