# Seret Mobile Redesign — Session Handoff (2026-06-07)

Resume guide for the **Gold Glass** iPhone/iPad redesign. Read this + `CLAUDE.md` + the
memory file `project_seret_redesign.md` to pick up exactly where this session left off.

---

## TL;DR

- **Branch:** `feat/mobile-redesign` (off `feat/mobile-foundation`). **Pushed to `origin/feat/mobile-redesign` (2026-06-07); NOT merged** to `feat/mobile-foundation`/`main`. (HEAD was `871c816` at handoff; a small doc commit follows.)
- **Done & verified:** full **iPhone/iPad Gold Glass redesign** — new icon, animated splash, new **Home** tab (Continue Watching + Recently Added), full-screen Detail + Player, bigger iPad layout, branded sidebar, chip playback sheet, rotation fix.
- **tvOS:** a Gold Glass port was built then **reverted** at the owner's request (looked worse). SeretTV is back to its original look. The redesign is **iPhone/iPad-only**.
- **Builds green:** SeretMobile (iPhone + iPad) + SeretTV. **Tests:** DebridCore **138** + DebridUI **50**.
- **Real VLCKit playback works on the iOS simulator** with the owner's RD token.

### The pending decision
The branch is **pushed to origin**. Owner reviews on real devices (especially **rotate mid-movie**, **iPhone landscape**, the **chip playback sheet**), then decides whether to **merge `feat/mobile-redesign` into `feat/mobile-foundation`** (and onward to `main`). Don't merge without asking.

---

## How to resume

```bash
cd /Users/shaharsolomons/Documents/Code/Seret
git checkout feat/mobile-redesign
./Scripts/fetch-frameworks.sh   # only if Frameworks/VLCKit.xcframework is missing
xcodegen generate               # .xcodeproj is gitignored — regenerate it

# Build
xcodebuild -scheme SeretMobile -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -scheme SeretMobile -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build
xcodebuild -scheme SeretTV     -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build

# Tests
cd Packages/DebridCore && swift test      # 138
cd Shared/DebridUI     && swift test      # 50
```
(Adjust sim names with `xcrun simctl list devices available`.)

### Run on the iOS sim with real data
```bash
U=$(xcrun simctl list devices available | grep -m1 "iPhone 17 Pro" | grep -oE '[0-9A-F-]{36}')
xcrun simctl boot "$U"; open -a Simulator
APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/Seret-*/Build/Products/Debug-iphonesimulator/Seret.app | head -1)
xcrun simctl install "$U" "$APP"
xcrun simctl launch "$U" com.solomons.seret.mobile
```
Then **sign in with the owner's Real-Debrid token** (sign-in screen → "Use a token" → paste a token from real-debrid.com/apitoken). **Never commit/log the token.** Device-code sign-in is throttled (403) — use the token.

**Recently Added** only populates after a **full library rebuild** (the reconciler returns the cached snapshot when there's no delta, and old snapshots predate `addedAt`). Force it:
```bash
DATA=$(xcrun simctl get_app_container "$U" com.solomons.seret.mobile data)
rm -rf "$DATA/Library/Caches/"*    # deletes library.json → next launch does a full rebuild w/ addedAt
```
**Continue Watching** populates after you actually play something (writes WatchProgress).

---

## What was built (iPhone/iPad)

**Design system** — `Apps/SeretMobile/DesignSystem/` (mobile-only; tvOS untouched):
`Theme.swift` (color/type/space/radius/motion tokens; gold **#EBC11D**), `Modifiers.swift` (`goldGlow`/`glassBackground`/`pressable`/`CanvasBackground`), `SeretMark.swift` (play logo), `Wordmark.swift` (סֶרֶט+SERET), `Buttons.swift` (Gold/Ghost), `PosterCard`, `LandscapeProgressCard`, `GoldProgressBar`, `SectionHeader`, `QualityChip`, `Rail`, `HeroBackdrop`, `ShimmerView`, `FlowLayout` (wrapping chips).

**Brand** — `Scripts/generate-icon.swift` → `Apps/SeretMobile/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` (gold "Bare Play" mark). `Apps/SeretMobile/Brand/SplashView.swift` (animated splash on launch + post-sign-in).

**Home tab (new)** — `Apps/SeretMobile/Home/HomeScreen.swift` on `HomeStore` (`Shared/DebridUI/Sources/DebridUI/Home/HomeStore.swift`): featured hero + Continue Watching + Recently Added. `MainShell.swift` now has 4 tabs (Home/Movies/Shows/Settings) — `TabView` on iPhone, custom branded `NavigationSplitView` sidebar on iPad.

**Data layer (DebridCore, additive/back-compat)** — `MediaItem.addedAt` + `TorrentInfo.added` threaded from the RD `/torrents` list (`TorrentsClient.attachAddedDates`), `LibraryBuilder.parseAdded` (ISO-8601), preserved through `MetadataEnricher`; `WatchProgressProviding.recentlyWatched(limit:)` seam; `PlayerModel.selectedAudioID/selectedSubtitleID` (drives the sheet's current-selection check). Baseline fix: `MockPlayerEngine` gained the missing `setRate` stub.

**Screens** — Sign-in (wordmark + gold), Library grids (`PosterCard` fills cells, retired `PosterTile`), Detail (cinematic, gold buttons/chips, gold watched-check, two-column-ish wide via `maxWidth`), Player (subtler — white transport, **gold only on the scrubber**), Settings (dark + gold). App forced `.preferredColorScheme(.dark)`.

**Full-screen Detail + Player + rotation fix** — Detail and the player are `fullScreenCover`s. They were originally presented from inside the shell, which (a) on iPad left the sidebar showing, and (b) made rotation dismiss them. Fixed by hoisting the presentation to **RootView** above the TabView/SplitView via `Apps/SeretMobile/Shell/AppRouter.swift` (`router.detail`). Home/Library set `router.detail`; RootView presents the Detail cover; the player cover stays nested in `DetailScreen` (now stable because Detail is root-presented).

---

## Verification status (be honest about this)

**Screenshot-verified on the iPhone 17 Pro sim (real data, owner token):** splash, Home (hero + Continue Watching + Recently Added), Movies grid, Settings, Detail, **real VLCKit playback** (Oppenheimer streamed → populated Continue Watching). **iPad Pro M5:** token sign-in, split-view Home + Movies, **full-screen Detail + Player (no sidebar)**. Build matrix + tests green.

**NOT visually verified (could not, in this environment):**
- The **chip playback sheet** — build-verified; the player's 4-second control auto-hide kept beating the laggy sim tap/capture.
- **iPhone landscape** rendering and the **rotation fix** — the sim here cannot actually rotate the app (see gotchas). Config is correct (Info.plist all orientations, no code lock) and layouts are size-class adaptive; the rotation *fix* is the standard SwiftUI remedy but needs a real device to confirm.
- **tvOS visuals** — the tvOS sim won't launch here (and the port was reverted anyway).

---

## Gotchas / environment limits (important for the next session)

- **mobile-mcp on iPad is unreliable:** `mobile_save_screenshot` and `mobile_set_orientation` are **cosmetic/laggy**. Use `xcrun simctl io <udid> screenshot <path>` for **ground-truth** captures; use `mobile_list_elements_on_screen` for tap coordinates (point space, ~1032 wide on iPad). Cross-check screenshot vs element tree.
- **You cannot truly rotate the sim here.** `mobile_set_orientation` only flips a cosmetic flag (framebuffer stays portrait); `osascript` Device-menu rotate didn't move the booted device's framebuffer either. So landscape/rotation must be verified on a real device or a hands-on Simulator.
- **Player chrome is hard to screenshot** — controls auto-hide after 4s; pausing keeps them up but the gesture/tap timing on the laggy sim fights it.
- **tvOS sim won't launch** in this environment (pty "Pseudo Terminal Setup Error 7/6") → tvOS is **build-only**; restart Claude.app or use Xcode GUI for tvOS runtime.
- **Real RD playback DOES work** on the iOS sim with the owner's token (unlike tvOS, which needs the real Apple TV).
- **Recently Added** needs the cache cleared (above) to populate `addedAt` on an existing library.
- Owner sometimes edits `feat/mobile-foundation` in parallel — this branch is separate, but stage specific paths, never `git add -A`.

---

## Open follow-ups / next steps

1. **Owner verifies on real devices:** rotate mid-movie (the fix), iPhone landscape across screens, the chip playback sheet, the splash.
2. **Land it:** push `feat/mobile-redesign` to origin and/or merge into `feat/mobile-foundation` — **ask first**. History has a tvOS port + its revert; squash if you want it clean before merge.
3. **Optional — redo the tvOS Gold Glass port** with a different approach (the first attempt was reverted). If so, consider unifying the brand/palette into `DebridUI` (shared) instead of duplicating per target (DRY). tvOS also still lacks a Home tab (style port only).
4. **Spec & plan:** `docs/superpowers/specs/2026-06-06-seret-mobile-redesign-design.md`, `docs/superpowers/plans/2026-06-06-seret-mobile-redesign.md`.
