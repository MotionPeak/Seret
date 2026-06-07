# tvOS player — swipe-up scrub controls + in-player episode switcher

**Date:** 2026-06-08
**Branch:** `feat/stage2-search-add`
**Status:** Approved (owner chose: player fetches episode meta; build now)

## Problem
While watching, there's no quick way to reveal the scrub bar with an upward swipe, and for shows no way to jump to another episode of the season without leaving the player.

## Goal
- Swipe **up** reveals the scrub bar (movies and shows).
- For a show episode, swipe up also reveals a **side-scrolling episode strip** of the current season (still + "S·E · Title"), focusable; selecting one switches playback to that episode in-place.

## Design

### Gesture (ScrubPad)
Add a `.verticalUp` direction alongside the existing `.horizontal` (scrub) and `.verticalDown` (settings). A pull-up past the threshold fires `onPullUp()` once per gesture. While the episode panel is open, `ScrubPad.isInteractive = false` (like the settings panel) so swipes navigate the strip.

### PlayerModel (Shared/DebridUI — additive, back-compat)
- New optional init param `details: MediaDetailsProviding? = nil` (passed by `AppSession.makePlayer`). Existing callers/tests unaffected (defaulted).
- `public var isEpisode: Bool { episode != nil }` — movies vs shows.
- `public struct PlayerEpisode: Identifiable` { `episode: Episode`, `name: String?`, `stillPath: String?` }.
- `public private(set) var seasonEpisodes: [PlayerEpisode] = []`.
- `public func loadSeasonEpisodes() async` — once, shows only: take the current season's playable episodes from `item.seasons`, fetch TMDB names/stills via `details.seasonEpisodes(tvID: item.tmdbID, season:)`, merge.
- `public func play(_ ep: Episode)` — no-op if already playing it; records current progress, then `switchTo(ep, resumeAt: nil)`.
- Refactor `advanceToNextEpisode()` to call a shared `switchTo(_ ep:, resumeAt:)` (same body it already has). Chosen episodes start from the beginning (resume-on-switch is a deferred follow-up — needs an async watch lookup; out of scope here).
- `public var currentEpisode: Episode?` (or season/number) so the strip can highlight the playing one.

### tvOS UI
- `AppSession.makePlayer` passes `details: detailsProvider` into `PlayerModel`.
- `PlayerView`: add `@State showEpisodes`. `ScrubPad(onPullUp:)` → `model.revealScrubBar()`; if `model.isEpisode` → `showEpisodes = true` + `Task { await model.loadSeasonEpisodes() }`. `ScrubPad.isInteractive = !showSettings && !showEpisodes`. `onExitCommand` closes the episode panel first.
- New `EpisodesPanel` (bottom): a horizontal `LazyHStack` of focusable episode cards (16:9 still + "S·E · name", gold ring on the currently-playing one). Select → `model.play(ep); showEpisodes = false`. Empty/loading → a spinner row.

## Non-goals
- Resume-on-switch (chosen episode starts from 0). Follow-up.
- Mobile player UI (the PlayerModel additions are shared and harmless; the swipe-up strip UI is tvOS-only here).

## Verification
- `swift test` (DebridUI PlayerModel suite stays green — additive change).
- `xcodebuild build` 0 warnings.
- Owner verifies on the Apple TV: swipe up shows scrub (movie) and scrub + episode strip (show); selecting an episode switches playback. (Sim can't verify real playback/gestures.)
