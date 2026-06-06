# Seret Mobile — Design Overhaul (iPhone + iPad)

**Date:** 2026-06-06
**Branch base:** `feat/mobile-foundation`
**Status:** Approved direction; ready for implementation plan.

## 1. Goal

A complete visual overhaul of the Seret iPhone/iPad app: stylish, modern, **dark with gold (#EBC11D) accents on black** — no purple, no "AI-slop" gradients. Add a new **Home** tab (Continue Watching + Recently Added), a new **app icon** and **animated splash**, polished motion throughout, and full **landscape** support on both devices. Build natively in SwiftUI; verify in the iOS simulator (mobile-mcp) on iPhone **and** iPad, both orientations, before calling it done.

**Out of scope (non-goals):** tvOS visuals (untouched), playback engine / auth / scraping logic, Search/Add (Stage 2), custom bundled fonts. No new features beyond the Home tab.

## 2. Design language — "Gold Glass"

True-black canvas with a faint top gold glow, frosted-blur chrome, soft depth. **Gold is reserved for interactive/active elements** (primary buttons, active tab, progress, focus, selection) — never decorative.

### Color tokens
| Token | Value | Use |
|---|---|---|
| `gold` | `#EBC11D` | primary accent |
| `goldLight` | `#F6D24A` | gradient top / highlight |
| `goldBright` | `#FDE98A` | logo gradient top, glints |
| `goldDeep` | `#C8930A` | gradient bottom / pressed |
| `goldGlow` | `#EBC11D` @ 40% | shadow/glow color |
| `canvas` | `#08080A` | app background |
| `trueBlack` | `#000000` | player background |
| `surface1` | `#141416` | cards, sheets |
| `surface2` | `#1C1C1F` | rows, inputs |
| `hairline` | white @ 9% | borders/dividers |
| `chipFill` | white @ 12% | quality chips (matches tvOS token) |
| `textPrimary` | `#F5F5F7` | titles/body |
| `textSecondary` | `#8A8A90` | meta/subtitles |
| `textTertiary` | `#5A5A60` | inactive |
| `accentCheck` | `gold` | "watched/finished" check (was green → now on-brand gold) |

### Typography (SF Pro + system Hebrew; Dynamic Type aware)
- **Display** (logo/SERET): heavy, tracked +6.
- **Title XL** (screen titles): 30 / heavy / tracking -0.4.
- **Title** (detail/section title): 22 / bold.
- **Headline**: 17 / semibold.
- **Body**: 15 / regular, `textSecondary` for overviews, line-spacing ~1.4.
- **Label** (uppercase section headers, e.g. CONTINUE WATCHING): 12 / semibold / tracking +1.5 / gold or dim.
- **Caption/time**: 12 monospaced-digit.

### Spacing / radius / materials / motion
- Spacing scale (base 4): 4, 8, 12, 16, 20, 24, 32. Screen margin 16 (compact) / 24 (regular).
- Radius: card/poster 12, chip 8, pill/button 22, sheet 28.
- Materials: `.ultraThinMaterial` + a black tint overlay for bars (keeps them dark). Glow = gold shadow on active elements.
- **Motion tokens:** `quick = .spring(response:0.3, damping:0.85)`, `standard = .spring(response:0.45, damping:0.82)`, `hero = .spring(response:0.6, damping:0.8)`, `fade = .easeInOut(0.25)`, press-scale 0.96. **All motion respects Reduce Motion** (fall back to fades/none).

## 3. Brand

### App icon
The **Bare Play** mark: a soft-edged (rounded-corner) gold play triangle with a gradient (`goldBright → goldDeep`) and a soft glow, on a black tile carrying a subtle top gold glow. Rendered crisp at 1024×1024 + full iconset. Produced as a vector so it matches the in-app `SeretMark`.

### Wordmark lockup
**סֶרֶט** (Hebrew, with nikud) as the hero — gold, soft glow — with **SERET** (Latin, tracked +6, `textSecondary`/gold-dim) beneath. Used on the Splash and Sign-in.

### Splash / loading animation
Black bg; radial gold glow blooms. Sequence (~1.6–2.0s; honors Reduce Motion → fade-only):
1. `t=0` — `SeretMark` scales 0.6→1.0 (quick spring), glow opacity 0→1.
2. `t≈0.35s` — **סֶרֶט** fades + rises (y +8→0).
3. `t≈0.55s` — **SERET** (Latin) fades in beneath.
4. Thin gold progress bar fills along the load (indeterminate shimmer if load outlasts it).
5. On (load complete AND min-duration elapsed) → cross-fade/scale out into Home.

**Triggers:** shown at cold launch over auth resolution, and immediately after a fresh sign-in while the first library load runs.

## 4. Architecture — centralized design system

New `Apps/SeretMobile/DesignSystem/` (mobile-only; **tvOS untouched**, shared `DebridUI/Theme/Tokens.swift` left as-is). One source of truth + reusable components, so future polish is a one-file change and new screens compose cleanly.

- **`Theme`** — static enum exposing Color / Type / Space / Radius / Motion tokens above, plus `Color` extensions and view modifiers (`.goldGlow()`, `.glassBar()`, `.pressable()`).
- **Components:** `SeretMark` (animatable play logo via `Canvas`/`Shape`), `Wordmark` (סֶרֶט + SERET), `GoldButton` & `GhostButton` (`ButtonStyle`), `PosterCard`, `LandscapeProgressCard` (continue-watching), `Rail` (generic horizontal section), `SectionHeader` (label + optional See-all), `QualityChip`, `HeroBackdrop` (image + gradient + subtle parallax), `GlassBar`, `ProgressBar` (gold), `ShimmerView` (loading), `PressableCard` modifier.

## 5. Responsive & orientation

**Support all orientations on iPhone + iPad** (Info.plist already lists Portrait + Landscape L/R; verify no code orientation lock; add iPad upside-down). Every screen adapts to size class **and** orientation:
- **MainShell:** `horizontalSizeClass == .regular` (iPad, iPhone Max landscape) → `NavigationSplitView` sidebar (Home/Movies/Shows/Settings); `.compact` → `TabView`. Extend to 4 destinations incl. Home.
- **Library grids:** `LazyVGrid` `GridItem(.adaptive(minimum:))` → ~3 cols (compact portrait) up to 5–7 (regular/landscape). Tune min widths per size class.
- **Home:** hero uses full width, caps height in landscape; rails are horizontal scrollers (naturally fine); larger hero + more visible items in regular width.
- **Detail:** compact portrait → stacked (backdrop hero top, content below). Regular width / landscape → **two-column** (backdrop/poster + actions left; scrollable meta/overview/versions/episodes right) via `ViewThatFits`/size-class branch.
- **Player:** full-bleed in any orientation (letterboxed in portrait, fills in landscape); transport + gestures respect safe areas.
- **Splash / Sign-in:** centered, anchors gracefully in both orientations.
- Respect safe areas, Dynamic Type, Reduce Motion throughout.

## 6. Screens

- **Splash** — §3 animation; cross-fades to Home.
- **Sign-in** — Gold Glass; Wordmark lockup; `GoldButton` "Sign in with Real-Debrid" (device-code) + ghost "Use a token" fallback (existing flows, restyled).
- **Home (new tab)** — featured `HeroBackdrop` (most-recent Continue item, Resume + List), **Continue Watching** rail (`LandscapeProgressCard` w/ gold progress), **Recently Added** rail (`PosterCard`). Empty/loading/failed states via `ShimmerView` and graceful copy.
- **Movies / Shows** — adopted grid (direction B), recomposed from `PosterCard` + `SectionHeader`.
- **Detail (movie/show)** — cinematic `HeroBackdrop`, gold Resume/Play + ghost secondary, `QualityChip`s, overview, Versions; shows add season picker + episode list (TMDB titles/synopsis, gold watched-check). Two-column in wide layouts.
- **Player (subtler)** — content-first. **No** big gold button. Center transport = white SF Symbols (play/pause ~44pt, ±10s skips ~30pt), optional faint press backing only. **Gold only on the thin scrubber progress + small knob.** Top scrim: back + title + tracks/subtitles (white, small). Bottom: slim gold progress + white monospaced times. Auto-hide controls; subtle dim scrim. Restyle existing `PlayerView`/overlays/`PlayerSettingsSheet`.
- **Settings** — dark grouped form, gold accents, RD account + OpenSubtitles + version.

## 7. Data work (Home only)

**Continue Watching — no brain change.** Expose `recentlyWatched(limit:)` on the `WatchProgressProviding` seam (`DebridUI`) + Live impl → delegates to existing `WatchProgressStore.recentlyWatched(limit:)`. Resolver maps `WatchState.contentKey` → `MediaItem`: movie `contentKey == item.id`; episode `contentKey == "\(show.id):\(episode.id)"` → match show by id prefix. New `HomeStore` (`@MainActor @Observable`, DebridUI) composes `LibraryStore` + watch progress into `continueWatching` (item + progress fraction + resume label + `PlaybackRequest`) and `recentlyAdded`.

**Recently Added — 5 additive, backward-compatible DebridCore changes** (optional fields → old caches & tvOS unaffected):
1. `RealDebrid/RealDebridResourceModels.swift` — add `added: String?` to `TorrentInfo`.
2. `RealDebrid/TorrentsClient.swift` — in `allTorrentInfos()`, carry `Torrent.added` (from `/torrents` list) onto each `TorrentInfo` by id match (`/torrents/info/{id}` omits it).
3. `Library/MediaItem.swift` — add `addedAt: Date?` (init `= nil` default; Codable optional decodes missing key → nil).
4. `Library/LibraryBuilder.swift` — parse ISO-8601 `added` → `Date`; for shows use the newest episode's added (so new episodes surface).
5. `Library/MetadataEnricher.swift` — preserve `addedAt` when rebuilding with TMDB data.

Home "Recently Added" = `(movies + shows).filter{ addedAt != nil }.sorted(by: addedAt desc).prefix(N)`. Fallback when all nil (pre-migration cache): hide rail until next `refresh()`. Add DebridCore tests for date parse + carry-through + old-snapshot decode.

## 8. Animations catalog
Poster/card press-scale (0.96, quick); rail item appearance; screen push/pop and tab-switch transitions; hero parallax on scroll; gold progress fill; shimmer loaders; controls fade in player; the splash sequence; selection/active-tab glow. All via shared motion tokens; all Reduce-Motion safe.

## 9. Verification / done bar
- `SeretMobile` builds for iPhone + iPad sims (target 0 errors / 0 warnings); `SeretTV` still builds (no regression); DebridCore + DebridUI tests green incl. new ones.
- mobile-mcp on **iPhone sim and iPad sim**: launch → splash → sign in → Home → Movies → Shows → Detail → Player → Settings; `mobile_save_screenshot` (high-res) each; rotate to **landscape** and re-shoot key screens; confirm no clipping, tappable buttons, safe areas, no overlap/weirdness.
- Deliver before/after screenshots to the owner.
- ⚠️ Owner-pending (same caveat as existing player): rails fully populate only with a signed-in RD library; if no token on the sim, verify layout + empty/loading/failed states and as much as possible with the owner's token.

## 10. Implementation notes
- Work on a **dedicated branch** off `feat/mobile-foundation` (e.g. `feat/mobile-redesign`) — owner commits to `feat/mobile-foundation` in parallel; stage specific paths, never `git add -A`. Commit locally; **ask before pushing**.
- Theme/components are additive and mobile-scoped; the only shared-package edits are the 6 small additive DebridCore/DebridUI data changes in §7, all optional/back-compat.
- No tvOS view or token changes.

## 11. Risks
- **No RD token on sim** → can't see populated rails; mitigate by verifying all non-data states + using owner's token when available.
- **MediaItem Codable migration** → covered by optional field + an old-snapshot decode test.
- **Parallel-commit collisions** on the shared branch → dedicated branch + path-scoped staging.
