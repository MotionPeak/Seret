# In-Player Episode Peek-Strip + Selector — Design

**Date:** 2026-06-10
**Branch:** `feat/player-episode-strip` (off `main`)
**Status:** Approved
**Targets:** SeretMobile (iPhone/iPad) **and** SeretTV (redesign existing panel)

## Goal

While watching a **show episode**, let the viewer glance at and jump between episodes without
leaving the player — via a subtle "peek" strip under the scrub bar that expands on demand into a
selectable episode list. Keep the existing Netflix-style "Up Next" auto-advance.

## What already exists (reused, not rebuilt)

`Shared/DebridUI/.../Playback/PlayerModel.swift` already provides everything the brain needs — **no
model changes are required**:
- `isEpisode: Bool`, `currentEpisode: Episode?`
- `seasonEpisodes: [PlayerEpisode]` (`season`, `number`, `name`, `stillPath`, `owned`, `isPlayable`)
- `loadSeasonEpisodes() async` — fetches the whole current season from TMDB (stills + names), each
  tagged with its owned/playable episode
- `play(_ ep: Episode)` — switches playback **in-place** (records current progress, reloads the new
  source; same engine + event loop, no teardown)
- `nextEpisode` / `hasNextEpisode` / `playNext()` and the **Up Next** countdown
  (`upNextVisible`, `upNextSecondsRemaining`, `dismissUpNext()`, `playNextNow()`), which auto-shows
  near content end (last subtitle cue, else `duration − 45s`).

The mobile player already renders an Up Next bar + a "Next Episode" transport button. The **new**
work is the episode **peek-strip + expand + select**, plus replacing tvOS's full `EpisodesPanel`
with the same subtler design.

## Behavior

### Collapsed — the "peek"
- Shown only when **`isEpisode`** is true **and** the transport controls/scrub bar are visible.
- A single horizontal row of the season's episode stills, rendered as a **hint**: vertically
  **cropped to a thin sliver** (only the top ~28–36 pt shows), **dimmed** (low opacity), and
  **edge-faded** (a horizontal gradient mask) so it occupies minimal space and never competes with
  the video. Sits **just below the scrub bar**.
- The currently-playing episode carries a subtle gold accent.
- Hidden entirely for movies, and when controls are hidden.

### Expanded — interact
- **Mobile:** a **swipe-down gesture scoped to the peek band** lifts it into a full strip. (A
  downward drag that starts on the video area still dismisses the player, as today — no clash.)
- **tvOS:** moving focus **down** onto the peek expands it (focus-driven), same as the panel works
  today; **Menu** collapses it.
- Expanded = a horizontally-scrollable `LazyHStack` of 16:9 episode cards (still · `number · name`).
  - The current episode is highlighted (gold border).
  - **Downloaded** (`isPlayable`) episodes are tappable/selectable → `model.play(ep.owned!)` switches
    in-place; the strip collapses.
  - **Not-downloaded** episodes render **dimmed with a ⬇︎ glyph and are NOT selectable** (a later
    iteration may start a download on tap — out of scope here).
- Collapse: swipe up / tap the dimmed backdrop (mobile); Menu (tvOS).

### Up Next (unchanged behavior, light polish)
The existing near-end Up Next bar stays: countdown auto-advances to the next **owned** episode;
**Play Now** advances immediately; **Dismiss / back / Menu** keeps watching. We only ensure it
layers cleanly above the new peek strip (the peek hides while Up Next is visible).

## Architecture

One brain, native views per platform (mirrors the existing per-app player split):
- **`Shared` (DebridUI):** no changes expected. `loadSeasonEpisodes()` is already called by tvOS;
  mobile will call it when the player loads an episode.
- **Mobile:** new `Apps/SeretMobile/Playback/EpisodePeekStrip.swift` — owns the collapsed/expanded
  state + the swipe-to-expand gesture + the card grid; reads `model.seasonEpisodes` /
  `currentEpisode`, calls `model.play(_:)`. Wired into `PlayerView`/`PlayerOverlays` beneath the
  scrub bar, gated on `model.isEpisode` + controls-visible. `PlayerView` triggers
  `await model.loadSeasonEpisodes()` on load when `isEpisode`.
- **tvOS:** rework `Apps/SeretTV/Playback/` `EpisodesPanel` into the peek→expand model (a thin
  focusable peek with controls; focus-down expands; cards reuse the same still/owned/current logic).

## Files

**Mobile**
- Create: `Apps/SeretMobile/Playback/EpisodePeekStrip.swift`
- Modify: `Apps/SeretMobile/Playback/PlayerView.swift` (mount the strip, load episodes), and/or
  `PlayerOverlays.swift` if the scrub/controls overlay lives there.

**tvOS**
- Modify: `Apps/SeretTV/Playback/PlayerView.swift` (+ the `EpisodesPanel` it hosts) to the peek
  design. Possibly extract `Apps/SeretTV/Playback/EpisodePeekStrip.swift`.

**Shared**
- Expected: none. If a tiny convenience is needed (e.g. "is Up Next visible" already exists), reuse.

## Slices (for the plan)

1. **Mobile** — `EpisodePeekStrip` (peek + expand + select) wired into the mobile player; load
   season episodes on play; gesture scoped so it doesn't fight pull-to-dismiss. Build SeretMobile.
2. **tvOS** — replace `EpisodesPanel` with the matching peek→expand strip. Build SeretTV.

## Testing

The episode/selection/Up-Next *logic* already lives in `PlayerModel` and is unit-tested
(`PlayerModelTests`). The new code is SwiftUI views (no host-free test surface), verified by
`xcodebuild build` (0 errors/warnings) + the owner's on-device check: open a show episode → see the
peek under the scrub bar → swipe/press down → pick another episode → it switches in place; near the
end the Up Next bar still auto-advances.

## Out of scope

- Tap-to-download a not-yet-downloaded episode from the strip (dimmed/unselectable for now).
- Cross-season browsing inside the player (peek shows the **current** season; matches today's tvOS).
- Changing the Up Next timing/logic (reused as-is).
