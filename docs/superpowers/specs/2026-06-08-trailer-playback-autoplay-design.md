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

## Spike result (2026-06-08)

The make-or-break question — can we resolve a YouTube key to a playable stream URL? — was tested.

- **Hand-rolled InnerTube player API: FAILED.** Every easy client is now closed: ANDROID/IOS →
  `Precondition check failed` (they require a **proof-of-origin / BotGuard token** now);
  `TVHTML5_SIMPLY_EMBEDDED_PLAYER` → `"YouTube is no longer supported in this application or
  device."`. A no-dependency, by-hand extractor is **not viable**.
- **YouTubeKit (SPM, alexeichhorn) v0.4.8: PASSED.** It parses the player JS and solves the
  cipher locally (bundling the JS), clearing the po-token wall. Resolved playable streams for two
  test videos, returning a **direct `googlevideo.com/videoplayback` URL** for **itag 18 (360p
  progressive MP4, muxed audio+video)** — which AVPlayer plays natively.

**Consequences:**
1. Extraction is done by **YouTubeKit**, a maintained third-party SPM dependency. It will break
   when YouTube changes; the fix is a **version bump** (a maintenance treadmill, accepted). It
   **cannot live in `DebridCore`** (no-deps rule) — it lives in **`DebridUI`**.
2. YouTube serves only **one muxed progressive format now: 360p (itag 18)**. Trailers play at
   **360p** (fine for a muted backdrop; acceptable for a trailer). Higher-res would require
   stitching separate adaptive video+audio streams — out of scope (YAGNI for trailers).

## How playback works

Resolve **YouTube key → direct stream URL** with **YouTubeKit** (`YouTube(videoID:).streams` →
the progressive itag-18 muxed MP4 URL), then play that URL with **`AVPlayer`** (not VLCKit).
Trailers are standard H.264/AAC — the one place AVPlayer is correct (VLCKit exists precisely
because AVPlayer *can't* play RD's MKV/x265). AVPlayer gives mute, loop, and an inline
`AVPlayerLayer` for the backdrop for free. **VLCKit remains the engine for actual RD playback** —
unchanged.

### Remaining UI-slice gate

The extraction is proven; before/while building UI, confirm **AVPlayer plays the extracted URL on
the iPhone simulator** (it can play an MP4 URL, unlike the YouTube embed) — so a real trailer is
**verified playing on the sim**, not just on device.

## Architecture

### DebridCore (brain) — unchanged

The existing **`TrailerProviding`** (TMDB `/videos` → YouTube key) stays. **No trailer-stream
code lands in `DebridCore`** — it keeps its no-deps rule. (The key→URL hop needs YouTubeKit, which
lives in DebridUI.)

### DebridUI (shared) — extraction + view-model

- **YouTubeKit dependency** added to the `DebridUI` SwiftPM package (the presentation layer, which
  may take deps — unlike the pure brain).
- **`TrailerStreamResolving`** seam: `func streamURL(youTubeKey: String) async -> URL?` (nil on
  failure → caller falls back to deep-link). Keeps `TrailerModel` testable without YouTubeKit.
- **`YouTubeKitStreamResolver`** (conforms): `YouTube(videoID:).streams` → the best **progressive**
  (muxed) stream's `url` (itag 18 today). Returns nil if extraction throws / no progressive stream.
  Thin wrapper; the parsing/cipher work is YouTubeKit's.
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

- **DebridUI:** `YouTubeKitStreamResolver` is a thin wrapper — covered by the **live spike**
  (proven) + a build/integration check that it returns a URL for a known id. `TrailerModel` state
  tests with a **fake `TrailerStreamResolving`** (resolve→ready, mute/unmute, fail→fallback,
  autoplay-off suppresses auto-play, the delay gates auto-play) — no YouTubeKit in unit tests.
- **DebridCore:** unchanged (no new code).
- **Apps:** build clean (0 warnings). **Verify a real trailer plays on the iPhone sim** (AVPlayer
  plays the extracted MP4 URL). On-device confirm of the muted-backdrop cross-fade feel
  (owner-pending, like other UX DoD).

## Delivery slices

1. **DebridUI extraction** — add YouTubeKit to the `DebridUI` package; `TrailerStreamResolving`
   seam + `YouTubeKitStreamResolver`; wire it into `AppSession`. Verify it resolves a URL.
2. **iOS** — AVPlayer trailer: full-screen tap-to-play + muted auto-play backdrop + unmute +
   Settings toggle + YouTube fallback; `TrailerModel`. Verify a trailer plays on the sim.
3. **tvOS** — same, focus-aware; Trailer button plays in-app, deep-link kept as fallback.

## Out of scope (YAGNI)

- Caching/pre-resolving trailers across the grid.
- Picture-in-Picture for trailers.
- Quality selection (just take HLS, or the best progressive).
- Trailers for episodes (title-level only, as today).
