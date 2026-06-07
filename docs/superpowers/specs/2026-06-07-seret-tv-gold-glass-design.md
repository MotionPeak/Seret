# Seret TV — Gold Glass skin, Home tab, focus hero + spinner fix

**Date:** 2026-06-07
**Branch:** `feat/stage2-search-add` (already contains the full mobile Gold Glass kit + the tvOS Browse screen; 91 commits ahead of `feat/mobile-redesign`, 0 behind — no branch juggling)
**Status:** Approved design, ready for planning

## Problem

1. **Movies/TV tabs spin forever.** `BrowseScreen` shows a default browse feed (`DiscoverStore`: trending / new / popular genre rails) when the search box is empty, but **nothing ever calls `browse.load()`**. The store stays at `.idle` and the screen shows `ProgressView()` indefinitely. `LibraryShell` loads the library store but not the two browse stores.
2. **tvOS looks nothing like the mobile app.** The iPhone/iPad app has a "Gold Glass" design system (gold `#EBC11D` accents, near-black canvas, `SeretMark` logo, `Wordmark` סֶרֶט/SERET lockup, animated splash). tvOS is unthemed native styling. A tvOS port was committed once (`9580271`) then **reverted** (`00beba9`) — never run on a sim, never touched Browse — so today's tvOS has none of it.
3. **No featured/hero presentation on tvOS.** Browsing is a flat grid of posters with no cinematic focus feedback.

## Goal

Bring tvOS up to the mobile app's visual language and fix the loading bug:
- Stop the infinite spinner; show a real failure/retry path.
- Port the Gold Glass skin to tvOS (logo, wordmark, animated splash, gold accents app-wide).
- Add a **Home** tab (hero + Continue Watching + Recently Added) driven by the already-wired shared `HomeStore`.
- Add a **focus-reactive full-bleed top hero** on Movies/TV that crossfades to the focused title.

Non-goals: unifying the mobile + tvOS design tokens into one shared module (flagged for later); real RD-stream playback verification (stays owner-pending, as always); iPhone/iPad changes.

## Architecture

### Existing seams we build on (no new wiring needed)
- `DiscoverStore` (`Shared/DebridUI/.../Search/DiscoverStore.swift`) — `load()` already deterministic via injectable `now:`; `state` ∈ `{idle, loading, loaded, failed}`.
- `HomeStore` (`Shared/DebridUI/.../Home/HomeStore.swift`) — exposes `featured`, `continueWatching: [HomeItem]`, `recentlyAdded: [MediaItem]`; rebuilt by `rebuild(movies:shows:)`.
- `AppSession` already exposes `moviesBrowse`, `showsBrowse`, and `home`, and already calls `home.rebuild(...)` after library load (`AppSession.swift:168,174`). tvOS simply surfaces these.

### New / changed tvOS files (all under `Apps/SeretTV/`)
- `DesignSystem/Theme.swift` — tvOS-local Gold Glass palette + `CanvasBackground` (mirror of mobile palette; resurrect from `9580271`).
- `DesignSystem/Brand.swift` — `SeretMark` (gold play-triangle) + `Wordmark` (סֶרֶט / SERET).
- `DesignSystem/Modifiers.swift` — `.goldGlow()` and any glass helpers used by the skin.
- `Brand/SplashView.swift` — animated launch splash (mark bloom → wordmark rise → gold progress).
- `Home/HomeScreen.swift` — new first tab: hero + Continue Watching rail + Recently Added rail.
- `Browse/HeroBanner.swift` — full-bleed focus-reactive backdrop hero for Browse.
- Edits: `Shell/RootView.swift` (show splash before shell), `Shell/LibraryShell.swift` (add Home tab; gold tab tint), `Browse/BrowseScreen.swift` (call `browse.load()`; host the hero; report focus; real failure/retry), plus accent edits to `Detail/`, `Playback/`, `Settings`, `Auth/SignInView.swift` reconciled against current code.

### Design-token strategy
tvOS gets its **own** `Theme.swift` mirroring the mobile palette values exactly. Rationale: the reverted commit proved this builds; tvOS needs focus-scaled sizing distinct from touch; and promoting tokens into `Shared/DebridUI` would mean restructuring the stable mobile DesignSystem (higher risk, no user-visible payoff now). Unify-later is recorded as a follow-up.

## Components

### A. Spinner fix + failure path
`BrowseScreen.rows` gains `.task(id: browse-identity) { await browse.load() }`. `.failed` already renders "Couldn't load." — add a **Retry** button that re-triggers `load()` (the store already guards `state == .idle || .failed`). Keep the 350ms search debounce untouched.

### B. Gold Glass skin
Resurrect `Theme`/`Brand`/`CanvasBackground`/splash from `9580271`. Apply accents: tab-bar `.tint(gold)`, `CanvasBackground` behind each screen, gold segment pills, gold watched-checks / episode-progress / player scrubber / overlays, gold wordmark on sign-in. Reconcile every accent edit against current (post-revert) code — not a blind cherry-pick.

### C. Home tab
`HomeScreen` reads `session.home`. Layout (top→bottom): featured **hero** (backdrop + title + gold Play/Resume → `PlaybackRequest`/Detail), **Continue Watching** rail (landscape cards + `GoldProgressBar`), **Recently Added** rail (poster cards). Rebuild on appear. Tab order: **Home · Movies · TV · My Library · Settings**.

### D. Focus-reactive hero on Browse
Full-bleed backdrop hero pinned above the genre rails. Mechanism: each `BrowseTile` publishes its `SearchHit` when it gains focus (tvOS `@FocusState`/focus-change → a `@State featuredHit` on `BrowseScreen`); the hero crossfades (`Theme.Motion.hero`) to the focused title's backdrop + title + gold Play treatment + סֶרֶט styling. Rails scroll beneath. Feeds from both idle-browse and search-results. Default featured = first row's first hit until the user moves focus.

## Data flow
Remote focus → `BrowseTile.onFocusChange` → `featuredHit` → `HeroBanner` crossfade. Independently, `BrowseScreen.task` → `DiscoverStore.load()` → genre rails. `AppSession` library load → `home.rebuild` → `HomeScreen` reads rebuilt rows.

## Error handling
- Browse load failure → `.failed` → "Couldn't load — Retry".
- Missing backdrop → hero falls back to poster art, then to `surface1` canvas (never a blank/broken frame).
- Empty Home (no watch history) → hide hero/rails gracefully; don't show an empty hero.

## Testing & verification
- **Unit:** `DiscoverStore` load-trigger reaches `.loaded`; failure → `.failed`; retry path re-enters `load()`. Any `HomeStore` glue stays covered by existing suites. Run `swift test` for DebridCore + DebridUI (host-free), expect green, 0 warnings.
- **Build:** `xcodebuild build` for SeretTV — 0 errors, 0 warnings.
- **tvOS sim:** launch and screenshot — splash, Home, Movies hero crossfading on focus, populated (non-spinning) feed. (pty caveat: long agent runs can exhaust the tvOS-sim pty pool → restart Claude.app; a fresh session is fine.)
- Real RD-stream playback remains **owner-pending** (sim can't verify actual video), consistent with prior player DoDs.

## Risks
- The reverted accent edits target pre-91-commit code; each must be reconciled, not cherry-picked blind.
- tvOS focus-driven hero is new territory — focus reporting from inside nested `ScrollView`/`LazyHStack` may need a `PreferenceKey` rather than `@FocusState` if bindings don't propagate cleanly. Spike the focus mechanism first.
- Adding a Home tab shifts tab order; verify deep-links/navigation destinations still resolve.
