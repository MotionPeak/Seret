# In-Player Episode Peek-Strip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline) or superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add a subtle episode peek-strip under the player scrub bar that expands to a selectable episode list, on SeretMobile and SeretTV, reusing the existing `PlayerModel` episode APIs.

**Architecture:** Pure player-UI. `PlayerModel` already vends `isEpisode`, `seasonEpisodes` (TMDB stills + owned flag), `currentEpisode`, `play(_:Episode)`, and the Up-Next countdown — no model changes. New native strip view per app.

**Tech Stack:** SwiftUI, VLCKit player, XcodeGen. View-only (verified by build + on-device).

**Branch:** `feat/player-episode-strip` (off main). Stage only listed paths.

**Spec:** `docs/superpowers/specs/2026-06-10-player-episode-strip-design.md`

> **Verification note:** this env can't launch the iOS/tvOS sim, so each slice is verified by
> `xcodebuild build` (0 errors/warnings) + the OWNER on-device. Gesture *feel* (swipe directions)
> is owner-tunable — sign flips are trivial.

---

## Reused `PlayerModel` API (no changes)
- `var isEpisode: Bool`, `var currentEpisode: Episode?`
- `struct PlayerEpisode { season, number, name:String?, stillPath:String?, owned:Episode?, isPlayable:Bool, id }`
- `private(set) var seasonEpisodes: [PlayerEpisode]`
- `func loadSeasonEpisodes() async`
- `func play(_ ep: Episode)` — in-place switch
- `func showControls()`

---

# SLICE 1 — Mobile

## Task 1: EpisodePeekStrip (mobile)

**Files:**
- Create: `Apps/SeretMobile/Playback/EpisodePeekStrip.swift`

- [ ] **Step 1: Create the view**

Create `Apps/SeretMobile/Playback/EpisodePeekStrip.swift`:

```swift
import DebridCore
import DebridUI
import SwiftUI

/// Episode strip for the touch player. Collapsed = a dimmed, vertically-cropped "peek" of the
/// season's stills under the scrub bar (a hint). Tap or swipe up expands it into a scrollable,
/// selectable card strip; tapping a DOWNLOADED episode switches playback in place. Not-downloaded
/// episodes are shown dimmed with a ⬇︎ glyph and aren't selectable. Hidden for movies.
struct EpisodePeekStrip: View {
    let model: PlayerModel
    @State private var expanded = false

    var body: some View {
        if model.isEpisode && !model.seasonEpisodes.isEmpty {
            Group {
                if expanded { fullStrip } else { peek }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: expanded)
        }
    }

    // MARK: Collapsed peek

    private var peek: some View {
        VStack(spacing: 2) {
            Image(systemName: "chevron.compact.up").font(.caption2).foregroundStyle(.white.opacity(0.45))
            HStack(spacing: 6) {
                ForEach(model.seasonEpisodes) { ep in thumb(ep, height: 54) }
            }
            .frame(height: 26, alignment: .top)     // crop to a sliver: only the top of each still shows
            .clipped()
            .opacity(0.55)
            .mask(LinearGradient(colors: [.clear, .black, .black, .clear],
                                 startPoint: .leading, endPoint: .trailing))
        }
        .contentShape(Rectangle())
        .onTapGesture { expanded = true }
        .highPriorityGesture(DragGesture(minimumDistance: 14).onEnded { v in
            if v.translation.height < -18 { expanded = true }     // swipe up → expand
        })
        .padding(.top, 8)
    }

    // MARK: Expanded selectable strip

    private var fullStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Episodes").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Spacer()
                Button { expanded = false } label: {
                    Image(systemName: "chevron.compact.down").font(.title3).foregroundStyle(.white.opacity(0.7))
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(model.seasonEpisodes) { ep in card(ep) }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.top, 6)
        .highPriorityGesture(DragGesture(minimumDistance: 14).onEnded { v in
            if v.translation.height > 18 { expanded = false }      // swipe down → collapse
        })
    }

    private func card(_ ep: PlayerModel.PlayerEpisode) -> some View {
        Button {
            if let owned = ep.owned { model.play(owned); model.showControls(); expanded = false }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                thumb(ep, height: 92)
                Text("\(ep.number) · \(ep.name ?? "Episode \(ep.number)")")
                    .font(.caption.weight(.semibold)).foregroundStyle(.white)
                    .lineLimit(1).frame(width: 164, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .disabled(!ep.isPlayable)
        .opacity(ep.isPlayable ? 1 : 0.5)
    }

    private func thumb(_ ep: PlayerModel.PlayerEpisode, height: CGFloat) -> some View {
        let isCurrent = ep.season == model.currentEpisode?.season && ep.number == model.currentEpisode?.number
        return AsyncImage(url: TMDBClient.imageURL(path: ep.stillPath, size: "w300")) { img in
            img.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            ZStack { Color.white.opacity(0.08); Image(systemName: "tv").foregroundStyle(.white.opacity(0.25)) }
        }
        .frame(width: height * 16 / 9, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            if isCurrent { RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.Palette.gold, lineWidth: 2) }
        }
        .overlay(alignment: .center) {
            if !ep.isPlayable {
                Image(systemName: "arrow.down.circle.fill").font(.title3).foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}
```

- [ ] **Step 2: It compiles in isolation (built with the app in Task 2).** No standalone build.

## Task 2: Wire into the mobile PlayerView

**Files:**
- Modify: `Apps/SeretMobile/Playback/PlayerView.swift`

- [ ] **Step 1: Replace `nextEpisodeBar` with the peek strip in `transport`**

In `Apps/SeretMobile/Playback/PlayerView.swift`, the `transport` stack ends with `scrubber` then
`nextEpisodeBar`. Replace the `nextEpisodeBar` line:

```swift
            scrubber
            nextEpisodeBar
```
with:
```swift
            scrubber
            EpisodePeekStrip(model: model)
```

Then delete the now-unused `nextEpisodeBar` computed property (the whole `@ViewBuilder private var
nextEpisodeBar: some View { … }` block, lines ~148–164). (The Up-Next bar + the strip cover
episode advancement; the standalone button is redundant.)

- [ ] **Step 2: Load the season's episodes when an episode is playing**

In `PlayerView.body`, add a `.task(id:)` next to the existing `.onAppear { model.start() }` (just
after it):

```swift
        .onAppear { model.start() }
        .task(id: model.currentEpisode?.season) {
            if model.isEpisode { await model.loadSeasonEpisodes() }
        }
```

- [ ] **Step 3: Build SeretMobile**

Run:
```bash
cd /Users/shaharsolomons/Documents/Code/Seret && xcodegen generate && \
xcodebuild -scheme SeretMobile -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:" | head
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Apps/SeretMobile/Playback/EpisodePeekStrip.swift Apps/SeretMobile/Playback/PlayerView.swift
git commit -m "feat(mobile): in-player episode peek-strip (swipe/tap to expand + pick episode)"
```

---

# SLICE 2 — tvOS

## Task 3: Replace the tvOS EpisodesPanel with the peek design

**Files:**
- Modify: `Apps/SeretTV/Playback/PlayerView.swift` (hosts the panel)
- Create/Modify: the tvOS episode strip view (currently `EpisodesPanel` inside `PlayerView.swift`)

> Read `Apps/SeretTV/Playback/PlayerView.swift` first — it already has a `showEpisodes` flag, a
> swipe/press-down trigger, and an `EpisodesPanel` that lists `model.seasonEpisodes` as focusable
> still cards calling `model.play(owned)`. The redesign keeps that wiring; it changes the LOOK to:
> a thin dimmed peek visible WITH the controls, that expands (focus-down) into the card strip.

- [ ] **Step 1: Read the current panel**

Run: `sed -n '1,210p' Apps/SeretTV/Playback/PlayerView.swift` and locate `EpisodesPanel` + the
`showEpisodes` trigger.

- [ ] **Step 2: Add a collapsed peek under the scrub bar (visible with controls)**

When `model.isEpisode` and controls are visible, render a dimmed, vertically-cropped sliver of
`model.seasonEpisodes` stills under the scrub bar (mirror the mobile `peek`: `frame(height: ~30,
alignment: .top).clipped().opacity(0.55)` + horizontal gradient mask + an up-chevron hint). It is
non-focusable (a hint only).

```swift
// In the controls overlay, below the scrub bar:
if model.isEpisode && !model.seasonEpisodes.isEmpty && !showEpisodes {
    EpisodePeek(model: model)        // dimmed sliver; focus-down opens the panel
}
```

- [ ] **Step 3: Keep the existing `EpisodesPanel` as the EXPANDED state**

Trigger it from the peek: a `.onMoveCommand(.down)` (or the existing down trigger) on the controls
sets `showEpisodes = true`, presenting the existing `EpisodesPanel` (already a `LazyHStack` of
focusable still cards that call `model.play(owned)` and a Menu/close to dismiss). Confirm the panel
highlights `currentEpisode` (gold border) and dims not-playable episodes — it already does; leave
that logic intact.

- [ ] **Step 4: Extract the peek view**

Create `Apps/SeretTV/Playback/EpisodePeek.swift` with a focusless dimmed sliver (the collapsed
look), reading `model.seasonEpisodes` + `model.currentEpisode`. Stills via
`TMDBClient.imageURL(path: ep.stillPath, size: "w300")`. (Use the mobile `thumb`/`peek` as the
visual reference, sized up for 10-foot viewing: sliver height ~40, still height ~80.)

- [ ] **Step 5: Build SeretTV**

Run:
```bash
cd /Users/shaharsolomons/Documents/Code/Seret && xcodegen generate && \
xcodebuild -scheme SeretTV -destination 'generic/platform=tvOS Simulator' build 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:" | head
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Apps/SeretTV/Playback/PlayerView.swift Apps/SeretTV/Playback/EpisodePeek.swift
git commit -m "feat(tv): redesign in-player episodes as a subtle peek that expands on focus-down"
```

---

## Task 4: Verification

- [ ] **Step 1:** `swift test --package-path Shared/DebridUI 2>&1 | tail -1` (PlayerModel suite still green — no model changes, but confirm).
- [ ] **Step 2:** Both apps build (Tasks 2 + 3 already proved this).
- [ ] **Step 3: Owner on-device:** open a show episode → see the dimmed peek under the scrub bar →
  tap / swipe-up (mobile) or focus-down (tvOS) → pick a downloaded episode → it switches in place;
  not-downloaded episodes are dimmed; near the end the Up-Next bar still auto-advances. Report if a
  swipe direction feels backwards (trivial sign flip).

## Self-Review Notes
- **Spec coverage:** peek (dimmed/cropped/faded sliver) — Task 1 `peek` / Task 4 tvOS peek; expand
  + select downloaded in-place — `fullStrip`/`card` → `model.play`; not-downloaded dimmed/unselectable
  — `.disabled(!isPlayable)` + ⬇︎ overlay; movies hidden — `if model.isEpisode`; Up Next unchanged —
  untouched. ✓
- **Types:** `PlayerModel.PlayerEpisode` fields (`season/number/name/stillPath/owned/isPlayable/id`),
  `currentEpisode`, `isEpisode`, `seasonEpisodes`, `play(_:)`, `loadSeasonEpisodes()`,
  `showControls()` — all match the Explore-confirmed public API.
- **Watch-outs:** mobile swipe-to-collapse (down) could race the player's pull-to-dismiss
  (`pullToDismiss` only fires on the video area; the strip uses `highPriorityGesture`) — owner
  verifies. tvOS slice intentionally keeps the existing `EpisodesPanel` as the expanded state to
  minimise risk; only the collapsed peek + trigger are new.
