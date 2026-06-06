# Seret Mobile Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-skin the Seret iPhone/iPad app into a dark "Gold Glass" look (#EBC11D on black), add a new app icon + animated splash, a new Home tab (Continue Watching + Recently Added), polished animations, and first-class landscape — verified in the iOS simulator on iPhone and iPad.

**Architecture:** A mobile-only centralized `DesignSystem/` (tokens + reusable components) is built first; every screen is recomposed from it. Home's data comes from existing `WatchProgressStore.recentlyWatched()` (Continue Watching) plus a small set of additive, backward-compatible DebridCore changes that thread the Real-Debrid `added` date onto `MediaItem` (Recently Added). tvOS and the shared `DebridUI/Theme/Tokens.swift` are untouched.

**Tech Stack:** SwiftUI (iOS 18), XcodeGen, Swift Package Manager (DebridCore, DebridUI), VLCKit (unchanged), swift-testing (`swift test`), mobile-mcp simulator verification.

**Spec:** `docs/superpowers/specs/2026-06-06-seret-mobile-redesign-design.md`
**Branch:** `feat/mobile-redesign` (already created off `feat/mobile-foundation`). Stage specific paths, never `git add -A`. Commit locally; do **not** push without asking.

**Method notes:**
- **Logic/data tasks** (Phase 3) follow strict TDD: failing test → run-fail → implement → run-pass → commit.
- **View tasks** (Phases 1, 2, 4) follow: implement with a SwiftUI `#Preview` → `xcodegen generate` → `xcodebuild` succeeds (0 warnings target) → simulator screenshot via mobile-mcp → commit. Each component gets a `#Preview` so it can be eyeballed in Xcode canvas; full UX verification happens per-screen in Phase 4/6.
- After adding/removing any file under `Apps/SeretMobile`, run `xcodegen generate` (sources are globbed). Package files under `Packages/*` and `Shared/*` are picked up automatically.
- **Reuse, don't reinvent:** screen tasks begin by reading the current file to capture data wiring (stores, navigation values, image-URL helpers) and preserve it.

---

## File Structure

**New — Design System (`Apps/SeretMobile/DesignSystem/`):**
- `Theme.swift` — `Color(hex:)` + `Theme` enum: `Palette`, `Typo`, `Space`, `Radius`, `Motion`.
- `Modifiers.swift` — `.goldGlow()`, `.glassBackground()`, `.pressable()` + `PressableButtonStyle`.
- `SeretMark.swift` — `PlayTriangle: Shape` + `SeretMark: View` (the logo).
- `Wordmark.swift` — `Wordmark: View` (סֶרֶט + SERET lockup).
- `Buttons.swift` — `GoldButtonStyle`, `GhostButtonStyle`.
- `PosterCard.swift`, `LandscapeProgressCard.swift`, `Rail.swift`, `SectionHeader.swift`, `QualityChip.swift`, `GoldProgressBar.swift`, `HeroBackdrop.swift`, `GlassBar.swift`, `ShimmerView.swift`.

**New — Brand:**
- `Apps/SeretMobile/Brand/SplashView.swift` — animated splash.
- `Scripts/generate-icon.swift` — Core Graphics icon generator (reproducible).
- `Apps/SeretMobile/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` — generated output.

**New — Home (`Shared/DebridUI/Sources/DebridUI/Home/`):**
- `HomeStore.swift` — `@MainActor @Observable` composing Continue Watching + Recently Added.
- `Apps/SeretMobile/Home/HomeScreen.swift` — the Home tab view.
- `Shared/DebridUI/Tests/DebridUITests/HomeStoreTests.swift`.

**Modify — Data layer (additive):**
- `Packages/DebridCore/Sources/DebridCore/RealDebrid/RealDebridResourceModels.swift` — `TorrentInfo.added`.
- `Packages/DebridCore/Sources/DebridCore/RealDebrid/TorrentsClient.swift` — carry `added`.
- `Packages/DebridCore/Sources/DebridCore/Library/MediaItem.swift` — `addedAt`.
- `Packages/DebridCore/Sources/DebridCore/Library/LibraryBuilder.swift` — parse date.
- `Packages/DebridCore/Sources/DebridCore/Library/MetadataEnricher.swift` — preserve `addedAt`.
- `Shared/DebridUI/Sources/DebridUI/Detail/WatchProgressProviding.swift` — add `recentlyWatched(limit:)`.
- `Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift` — expose `home` + wire live `recentlyWatched`.

**Modify — Screens (`Apps/SeretMobile/`):**
- `Shell/MainShell.swift` (add Home destination), `Shell/RootView.swift` (splash), `Auth/SignInView.swift`, `Library/*`, `Detail/*`, `Playback/PlayerView.swift` + `PlayerOverlays.swift` + `PlayerSettingsSheet.swift`, `Shell/SettingsView.swift`.
- `Apps/SeretMobile/Info.plist` / `project.yml` — orientations.

---

## Phase 0 — Baseline

### Task 0.1: Confirm green baseline

**Files:** none (verification only).

- [ ] **Step 1: Build the mobile app for the simulator**

Run:
```bash
cd /Users/shaharsolomons/Documents/Code/Seret
xcodegen generate
xcodebuild -scheme SeretMobile -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`. If the destination name fails, list devices with `xcrun simctl list devices available | grep iPhone` and use an available iPhone, recording the name for later tasks.

- [ ] **Step 2: Run package tests**

Run:
```bash
cd Packages/DebridCore && swift test 2>&1 | tail -3
cd ../../Shared/DebridUI && swift test 2>&1 | tail -3
```
Expected: both report all tests passing (DebridCore ~130, DebridUI ~48 per project history).

- [ ] **Step 3: Confirm branch**

Run: `git branch --show-current`
Expected: `feat/mobile-redesign`. No commit (baseline only).

---

## Phase 1 — Design System

### Task 1.1: Theme tokens

**Files:**
- Create: `Apps/SeretMobile/DesignSystem/Theme.swift`

- [ ] **Step 1: Create the theme**

```swift
import SwiftUI

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

/// Single source of truth for the mobile "Gold Glass" look. tvOS is unaffected.
enum Theme {
    enum Palette {
        static let gold        = Color(hex: 0xEBC11D)
        static let goldLight   = Color(hex: 0xF6D24A)
        static let goldBright  = Color(hex: 0xFDE98A)
        static let goldDeep    = Color(hex: 0xC8930A)
        static let goldGlow    = Color(hex: 0xEBC11D, alpha: 0.40)
        static let canvas      = Color(hex: 0x08080A)
        static let trueBlack   = Color.black
        static let surface1    = Color(hex: 0x141416)
        static let surface2    = Color(hex: 0x1C1C1F)
        static let hairline    = Color.white.opacity(0.09)
        static let chipFill    = Color.white.opacity(0.12)
        static let textPrimary   = Color(hex: 0xF5F5F7)
        static let textSecondary = Color(hex: 0x8A8A90)
        static let textTertiary  = Color(hex: 0x5A5A60)

        static let goldGradient = LinearGradient(
            colors: [goldLight, gold, goldDeep],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        static let markGradient = LinearGradient(
            colors: [goldBright, goldDeep],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        /// Faint top glow used as a screen background wash.
        static let canvasGlow = RadialGradient(
            colors: [Color(hex: 0xEBC11D, alpha: 0.14), .clear],
            center: .init(x: 0.8, y: -0.05), startRadius: 0, endRadius: 520)
    }

    enum Typo {
        static func titleXL() -> Font { .system(size: 30, weight: .heavy) }
        static func title()   -> Font { .system(size: 22, weight: .bold) }
        static func headline() -> Font { .system(size: 17, weight: .semibold) }
        static func body()    -> Font { .system(size: 15, weight: .regular) }
        static func label()   -> Font { .system(size: 12, weight: .semibold) }
        static func caption() -> Font { .system(size: 12, weight: .medium).monospacedDigit() }
    }

    enum Space {
        static let xs: CGFloat = 4, sm: CGFloat = 8, md: CGFloat = 12
        static let lg: CGFloat = 16, xl: CGFloat = 20, xxl: CGFloat = 24, xxxl: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 12, chip: CGFloat = 8, pill: CGFloat = 22, sheet: CGFloat = 28
    }

    enum Motion {
        static let quick    = Animation.spring(response: 0.30, dampingFraction: 0.85)
        static let standard = Animation.spring(response: 0.45, dampingFraction: 0.82)
        static let hero     = Animation.spring(response: 0.60, dampingFraction: 0.80)
        static let fade     = Animation.easeInOut(duration: 0.25)
    }
}
```

- [ ] **Step 2: Build**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret && xcodegen generate && xcodebuild -scheme SeretMobile -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Apps/SeretMobile/DesignSystem/Theme.swift project.yml
git commit -m "feat(ds): Gold Glass theme tokens (color/type/space/radius/motion)"
```

### Task 1.2: View modifiers

**Files:**
- Create: `Apps/SeretMobile/DesignSystem/Modifiers.swift`

- [ ] **Step 1: Create modifiers**

```swift
import SwiftUI

extension View {
    /// Soft gold halo for active/interactive elements.
    func goldGlow(_ radius: CGFloat = 16, opacity: Double = 0.45) -> some View {
        shadow(color: Color(hex: 0xEBC11D, alpha: opacity), radius: radius)
    }

    /// Dark frosted bar/sheet background (blur + black tint + hairline top).
    func glassBackground(topHairline: Bool = true) -> some View {
        background(.ultraThinMaterial)
            .background(Theme.Palette.canvas.opacity(0.55))
            .overlay(alignment: .top) {
                if topHairline { Theme.Palette.hairline.frame(height: 0.5) }
            }
    }

    /// Tap feedback: scale down on press.
    func pressable() -> some View { buttonStyle(PressableButtonStyle()) }
}

/// Scales content to 0.96 while pressed. Use on tappable cards/posters.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
    }
}

/// Full-screen Gold Glass canvas wash. Put behind screen content.
struct CanvasBackground: View {
    var body: some View {
        ZStack {
            Theme.Palette.canvas
            Theme.Palette.canvasGlow
        }
        .ignoresSafeArea()
    }
}
```

- [ ] **Step 2: Build** — Run the Task 1.1 Step 2 build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Apps/SeretMobile/DesignSystem/Modifiers.swift
git commit -m "feat(ds): goldGlow / glassBackground / pressable modifiers + CanvasBackground"
```

### Task 1.3: SeretMark (logo)

**Files:**
- Create: `Apps/SeretMobile/DesignSystem/SeretMark.swift`

- [ ] **Step 1: Create the mark**

```swift
import SwiftUI

/// The Seret play triangle with rounded corners (matches the app icon).
struct PlayTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w * 0.32, y: h * 0.24))
        p.addLine(to: CGPoint(x: w * 0.32, y: h * 0.76))
        p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.50))
        p.closeSubpath()
        return p
    }
}

/// Gold play-triangle logo. `glow` adds the halo; size via `.frame`.
struct SeretMark: View {
    var glow: Bool = true
    var body: some View {
        GeometryReader { geo in
            let corner = geo.size.width * 0.14
            PlayTriangle()
                .fill(Theme.Palette.markGradient)
                .overlay(
                    PlayTriangle()
                        .stroke(Theme.Palette.markGradient,
                                style: StrokeStyle(lineWidth: corner, lineJoin: .round))
                )
                .goldGlow(glow ? geo.size.width * 0.22 : 0, opacity: glow ? 0.55 : 0)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview {
    ZStack { CanvasBackground(); SeretMark().frame(width: 120) }
}
```

- [ ] **Step 2: Build** — Task 1.1 Step 2 command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Apps/SeretMobile/DesignSystem/SeretMark.swift
git commit -m "feat(ds): SeretMark play-triangle logo + PlayTriangle shape"
```

### Task 1.4: Wordmark (סֶרֶט + SERET)

**Files:**
- Create: `Apps/SeretMobile/DesignSystem/Wordmark.swift`

- [ ] **Step 1: Create the lockup**

```swift
import SwiftUI

/// Brand lockup: Hebrew nikud hero + Latin subtitle. Used on Splash & Sign-in.
struct Wordmark: View {
    var hebrewSize: CGFloat = 44
    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            Text("סֶרֶט")
                .font(.system(size: hebrewSize, weight: .bold))
                .foregroundStyle(Theme.Palette.gold)
                .environment(\.layoutDirection, .rightToLeft)
                .goldGlow(hebrewSize * 0.5, opacity: 0.5)
            Text("SERET")
                .font(.system(size: hebrewSize * 0.32, weight: .semibold))
                .tracking(hebrewSize * 0.14)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}

#Preview { ZStack { CanvasBackground(); Wordmark() } }
```

- [ ] **Step 2: Build** — Task 1.1 Step 2 command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Apps/SeretMobile/DesignSystem/Wordmark.swift
git commit -m "feat(ds): Wordmark lockup (סֶרֶט + SERET)"
```

### Task 1.5: Button styles

**Files:**
- Create: `Apps/SeretMobile/DesignSystem/Buttons.swift`

- [ ] **Step 1: Create button styles**

```swift
import SwiftUI

/// Primary action: gold gradient pill with glow.
struct GoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typo.headline())
            .foregroundStyle(Color(hex: 0x1A1400))
            .padding(.vertical, 11).padding(.horizontal, Theme.Space.xl)
            .background(Theme.Palette.goldGradient, in: Capsule())
            .goldGlow(14, opacity: configuration.isPressed ? 0.2 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
    }
}

/// Secondary action: hairline-outlined pill on glass.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typo.headline())
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.vertical, 11).padding(.horizontal, Theme.Space.lg)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
    }
}

#Preview {
    ZStack { CanvasBackground()
        VStack(spacing: 16) {
            Button("▶  Resume") {}.buttonStyle(GoldButtonStyle())
            Button("Use a token") {}.buttonStyle(GhostButtonStyle())
        }
    }
}
```

- [ ] **Step 2: Build** — Task 1.1 Step 2 command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Apps/SeretMobile/DesignSystem/Buttons.swift
git commit -m "feat(ds): GoldButtonStyle + GhostButtonStyle"
```

### Task 1.6: Poster cards + progress bar

**Files:**
- Create: `Apps/SeretMobile/DesignSystem/GoldProgressBar.swift`
- Create: `Apps/SeretMobile/DesignSystem/PosterCard.swift`
- Create: `Apps/SeretMobile/DesignSystem/LandscapeProgressCard.swift`

- [ ] **Step 1: Read the current poster tile for the image pattern**

Run: `cat Apps/SeretMobile/Library/PosterTile.swift` — note how it builds the poster `URL` (the TMDB image-URL helper) and its `AsyncImage` usage. The new cards take a ready `URL?` (kept presentation-only); screens compute it with that same helper.

- [ ] **Step 2: Create `GoldProgressBar.swift`**

```swift
import SwiftUI

/// Thin gold progress line on a faint track.
struct GoldProgressBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(Theme.Palette.gold)
                    .frame(width: max(0, min(1, fraction)) * g.size.width)
                    .goldGlow(6, opacity: 0.7)
            }
        }
        .frame(height: 3)
    }
}
```

- [ ] **Step 3: Create `PosterCard.swift`**

```swift
import SwiftUI

/// 2:3 poster + title. Presentation-only; pass a resolved poster URL.
struct PosterCard: View {
    let title: String
    let posterURL: URL?
    var width: CGFloat = 110
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: posterURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    ZStack { Theme.Palette.surface2
                        Image(systemName: "film").foregroundStyle(Theme.Palette.textTertiary) }
                }
            }
            .frame(width: width, height: width * 3 / 2)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Theme.Palette.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
            Text(title).font(Theme.Typo.caption())
                .foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
    }
}
```

- [ ] **Step 4: Create `LandscapeProgressCard.swift`**

```swift
import SwiftUI

/// 16:9 thumbnail + gold progress + title/subtitle. For Continue Watching.
struct LandscapeProgressCard: View {
    let title: String
    let subtitle: String
    let imageURL: URL?
    let fraction: Double
    var width: CGFloat = 168
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: imageURL) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFill() }
                else { Theme.Palette.surface2 }
            }
            .frame(width: width, height: width * 9 / 16)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Theme.Palette.hairline, lineWidth: 1))
            GoldProgressBar(fraction: fraction).frame(width: width)
            Text(title).font(Theme.Typo.caption())
                .foregroundStyle(Theme.Palette.textPrimary).lineLimit(1).frame(width: width, alignment: .leading)
            if !subtitle.isEmpty {
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1).frame(width: width, alignment: .leading)
            }
        }
    }
}
```

- [ ] **Step 5: Build** — `xcodegen generate && xcodebuild -scheme SeretMobile -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3`. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Apps/SeretMobile/DesignSystem/GoldProgressBar.swift Apps/SeretMobile/DesignSystem/PosterCard.swift Apps/SeretMobile/DesignSystem/LandscapeProgressCard.swift
git commit -m "feat(ds): PosterCard, LandscapeProgressCard, GoldProgressBar"
```

### Task 1.7: Section header, chip, rail

**Files:**
- Create: `Apps/SeretMobile/DesignSystem/SectionHeader.swift`
- Create: `Apps/SeretMobile/DesignSystem/QualityChip.swift`
- Create: `Apps/SeretMobile/DesignSystem/Rail.swift`

- [ ] **Step 1: Create `SectionHeader.swift`**

```swift
import SwiftUI

/// Uppercase gold section label with optional trailing action.
struct SectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil
    var body: some View {
        HStack {
            Text(title.uppercased()).font(Theme.Typo.label())
                .tracking(1.5).foregroundStyle(Theme.Palette.gold)
            Spacer()
            if let action {
                Button("See all", action: action)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .padding(.horizontal, Theme.Space.lg)
    }
}
```

- [ ] **Step 2: Create `QualityChip.swift`**

```swift
import SwiftUI

/// Small capsule for metadata (2160p, HDR, TrueHD…).
struct QualityChip: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.vertical, 4).padding(.horizontal, 8)
            .background(Theme.Palette.chipFill,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
    }
}
```

- [ ] **Step 3: Create `Rail.swift`**

```swift
import SwiftUI

/// A titled horizontal scroller. Pass cards (e.g. PosterCard) as content.
struct Rail<Content: View>: View {
    let title: String
    var onSeeAll: (() -> Void)? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SectionHeader(title: title, action: onSeeAll)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Theme.Space.md) { content }
                    .padding(.horizontal, Theme.Space.lg)
            }
        }
    }
}
```

- [ ] **Step 4: Build** — Task 1.6 Step 5 command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Apps/SeretMobile/DesignSystem/SectionHeader.swift Apps/SeretMobile/DesignSystem/QualityChip.swift Apps/SeretMobile/DesignSystem/Rail.swift
git commit -m "feat(ds): SectionHeader, QualityChip, Rail"
```

### Task 1.8: Hero backdrop, shimmer

**Files:**
- Create: `Apps/SeretMobile/DesignSystem/HeroBackdrop.swift`
- Create: `Apps/SeretMobile/DesignSystem/ShimmerView.swift`

- [ ] **Step 1: Create `HeroBackdrop.swift`**

```swift
import SwiftUI

/// Backdrop image fading into the canvas, with an overlay (title/buttons) at bottom-leading.
struct HeroBackdrop<Overlay: View>: View {
    let imageURL: URL?
    var height: CGFloat = 220
    @ViewBuilder var overlay: Overlay
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: imageURL) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFill() }
                else { Theme.Palette.surface1 }
            }
            .frame(height: height).frame(maxWidth: .infinity).clipped()
            LinearGradient(
                stops: [.init(color: .clear, location: 0.0),
                        .init(color: Theme.Palette.canvas.opacity(0.6), location: 0.55),
                        .init(color: Theme.Palette.canvas, location: 1.0)],
                startPoint: .top, endPoint: .bottom)
            .frame(height: height)
            overlay.padding(Theme.Space.lg)
        }
        .frame(height: height)
    }
}
```

- [ ] **Step 2: Create `ShimmerView.swift`**

```swift
import SwiftUI

/// Animated loading placeholder. Use to fill rails/grids while data loads.
struct ShimmerView: View {
    var cornerRadius: CGFloat = Theme.Radius.card
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.Palette.surface2)
            .overlay(
                GeometryReader { g in
                    LinearGradient(colors: [.clear, Color.white.opacity(0.08), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: g.size.width * 0.6)
                        .offset(x: phase * g.size.width)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1.4 }
            }
    }
}
```

- [ ] **Step 3: Build** — Task 1.6 Step 5 command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Apps/SeretMobile/DesignSystem/HeroBackdrop.swift Apps/SeretMobile/DesignSystem/ShimmerView.swift
git commit -m "feat(ds): HeroBackdrop + ShimmerView"
```

---

## Phase 2 — Brand assets

### Task 2.1: App icon

**Files:**
- Create: `Scripts/generate-icon.swift`
- Create: `Apps/SeretMobile/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`
- Modify: `Apps/SeretMobile/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`

- [ ] **Step 1: Create the generator `Scripts/generate-icon.swift`**

```swift
import AppKit
import CoreGraphics

let S = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError() }
let full = CGRect(x: 0, y: 0, width: S, height: S)
// Opaque near-black background (no alpha; iOS masks corners itself).
ctx.setFillColor(CGColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1)); ctx.fill(full)
// Top-center radial gold glow.
let glow = [CGColor(red: 0.92, green: 0.76, blue: 0.11, alpha: 0.30),
            CGColor(red: 0.92, green: 0.76, blue: 0.11, alpha: 0)] as CFArray
if let g = CGGradient(colorsSpace: cs, colors: glow, locations: [0, 1]) {
    let c = CGPoint(x: Double(S) * 0.5, y: Double(S) * 0.62)
    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: Double(S) * 0.6, options: [])
}
// Play triangle (CG origin is bottom-left → flip y).
func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: Double(S) * x, y: Double(S) * (1 - y)) }
let tri = CGMutablePath()
tri.move(to: p(0.37, 0.27)); tri.addLine(to: p(0.37, 0.73)); tri.addLine(to: p(0.72, 0.50)); tri.closeSubpath()
let rounded = tri.copy(strokingWithWidth: Double(S) * 0.085, lineCap: .round, lineJoin: .round, miterLimit: 10)
// Halo + solid base.
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: Double(S) * 0.055,
              color: CGColor(red: 0.92, green: 0.76, blue: 0.11, alpha: 0.7))
ctx.addPath(tri); ctx.addPath(rounded)
ctx.setFillColor(CGColor(red: 0.92, green: 0.76, blue: 0.11, alpha: 1)); ctx.fillPath()
ctx.restoreGState()
// Gradient sheen on top.
ctx.saveGState(); ctx.addPath(tri); ctx.addPath(rounded); ctx.clip()
let gold = [CGColor(red: 0.99, green: 0.91, blue: 0.54, alpha: 1),
            CGColor(red: 0.78, green: 0.58, blue: 0.04, alpha: 1)] as CFArray
if let g = CGGradient(colorsSpace: cs, colors: gold, locations: [0, 1]) {
    ctx.drawLinearGradient(g, start: p(0.37, 0.73), end: p(0.72, 0.30), options: [])
}
ctx.restoreGState()
guard let image = ctx.makeImage() else { fatalError() }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
```

- [ ] **Step 2: Generate the PNG**

Run:
```bash
cd /Users/shaharsolomons/Documents/Code/Seret
swift Scripts/generate-icon.swift Apps/SeretMobile/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
file Apps/SeretMobile/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
```
Expected: `wrote …/icon-1024.png` and `file` reports `PNG image data, 1024 x 1024`.

- [ ] **Step 3: Point the asset catalog at it** — set `Contents.json` to:

```json
{
  "images" : [
    { "filename" : "icon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

- [ ] **Step 4: Build (icon compiles into the app)** — Task 1.6 Step 5 command. Expected: `** BUILD SUCCEEDED **` with no "AppIcon" asset warnings.

- [ ] **Step 5: Commit**

```bash
git add Scripts/generate-icon.swift Apps/SeretMobile/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png Apps/SeretMobile/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json
git commit -m "feat(brand): generated Bare Play app icon (1024) + generator script"
```

### Task 2.2: Splash screen + wiring

**Files:**
- Create: `Apps/SeretMobile/Brand/SplashView.swift`
- Modify: `Apps/SeretMobile/Shell/RootView.swift`

- [ ] **Step 1: Read the current root** — Run: `cat Apps/SeretMobile/Shell/RootView.swift`. Capture the exact `AppSession` auth-state API (the `unknown / signedOut / signedIn` value it switches on, and its property name) so the splash can be triggered on cold launch and on the signedOut→signedIn transition without changing routing.

- [ ] **Step 2: Create `SplashView.swift`**

```swift
import SwiftUI

/// Branded intro: mark scales in, glow blooms, wordmark rises, gold bar fills.
/// Fixed ~1.6s; Home shows its own shimmer until data lands.
struct SplashView: View {
    var onFinished: () -> Void
    @State private var markIn = false
    @State private var wordIn = false
    @State private var latinIn = false
    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.Palette.trueBlack.ignoresSafeArea()
            RadialGradient(colors: [Theme.Palette.goldGlow, .clear],
                           center: .center, startRadius: 0, endRadius: 360)
                .opacity(markIn ? 1 : 0).ignoresSafeArea()
            VStack(spacing: Theme.Space.xxl) {
                SeretMark().frame(width: 96)
                    .scaleEffect(markIn ? 1 : 0.6).opacity(markIn ? 1 : 0)
                VStack(spacing: Theme.Space.sm) {
                    Text("סֶרֶט").font(.system(size: 48, weight: .bold))
                        .foregroundStyle(Theme.Palette.gold)
                        .environment(\.layoutDirection, .rightToLeft)
                        .goldGlow(24, opacity: 0.5)
                        .opacity(wordIn ? 1 : 0).offset(y: wordIn ? 0 : 8)
                    Text("SERET").font(.system(size: 15, weight: .semibold)).tracking(6)
                        .foregroundStyle(Theme.Palette.textSecondary).opacity(latinIn ? 1 : 0)
                }
            }
            VStack { Spacer()
                GoldProgressBar(fraction: progress).frame(width: 120).padding(.bottom, 48) }
        }
        .task { await run() }
    }

    private func run() async {
        if reduceMotion {
            markIn = true; wordIn = true; latinIn = true; progress = 1
            try? await Task.sleep(for: .seconds(0.9)); onFinished(); return
        }
        withAnimation(Theme.Motion.hero) { markIn = true }
        try? await Task.sleep(for: .seconds(0.35)); withAnimation(Theme.Motion.standard) { wordIn = true }
        try? await Task.sleep(for: .seconds(0.20)); withAnimation(Theme.Motion.fade) { latinIn = true }
        withAnimation(.easeInOut(duration: 1.05)) { progress = 1 }
        try? await Task.sleep(for: .seconds(1.05)); onFinished()
    }
}
```

- [ ] **Step 3: Wire into `RootView`** — wrap the existing routed content in a `ZStack` and overlay the splash. Use the auth-state property name confirmed in Step 1 (shown here as `session.phase` with case `.signedIn`; adjust to the real names). Add:

```swift
@State private var showSplash = true
// …
ZStack {
    routedContent            // the existing switch on session state
    if showSplash {
        SplashView { withAnimation(Theme.Motion.fade) { showSplash = false } }
            .transition(.opacity)
            .zIndex(1)
    }
}
.onChange(of: session.phase) { old, new in   // adjust property/case names to the real API
    if case .signedIn = new, case .signedOut = old { showSplash = true }
}
```

- [ ] **Step 4: Build** — Task 1.6 Step 5 command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Verify in simulator (mobile-mcp)** — launch SeretMobile on the iPhone sim; within the first ~1.5s capture `mobile_save_screenshot` (high-res). Confirm: black bg, gold play mark, **סֶרֶט** above **SERET**, gold bar at the bottom; then it cross-fades to the app. No clipping.

- [ ] **Step 6: Commit**

```bash
git add Apps/SeretMobile/Brand/SplashView.swift Apps/SeretMobile/Shell/RootView.swift
git commit -m "feat(brand): animated splash (mark + סֶרֶט/SERET) on launch & post-sign-in"
```

---

## Phase 3 — Data layer for Home (TDD)

> All additive and backward-compatible. tvOS keeps building. Test runner is swift-testing (`import Testing`, `@Test`, `#expect`). Before each task, **read the named file** and adapt the provided code to the real signatures you find.

### Task 3.1: `TorrentInfo.added`

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/RealDebrid/RealDebridResourceModels.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/TorrentInfoAddedTests.swift`

- [ ] **Step 1: Read** `RealDebridResourceModels.swift` — confirm the `TorrentInfo` field list and Codable style.

- [ ] **Step 2: Write the failing test**

```swift
import Testing
import Foundation
@testable import DebridCore

@Suite struct TorrentInfoAddedTests {
    @Test func decodesAddedWhenPresent() throws {
        let json = #"{"id":"abc","filename":"f","hash":"h","bytes":1,"progress":100,"status":"downloaded","files":[],"links":[],"added":"2026-06-01T10:30:00.000Z"}"#
        let info = try JSONDecoder().decode(TorrentInfo.self, from: Data(json.utf8))
        #expect(info.added == "2026-06-01T10:30:00.000Z")
    }
    @Test func addedIsNilWhenMissing() throws {
        let json = #"{"id":"abc","filename":"f","hash":"h","bytes":1,"progress":100,"status":"downloaded","files":[],"links":[]}"#
        let info = try JSONDecoder().decode(TorrentInfo.self, from: Data(json.utf8))
        #expect(info.added == nil)
    }
}
```

- [ ] **Step 3: Run — expect failure**

Run: `cd Packages/DebridCore && swift test 2>&1 | tail -8`
Expected: build/test failure — `value of type 'TorrentInfo' has no member 'added'`.

- [ ] **Step 4: Add the field** — in `TorrentInfo` add `public let added: String?` (place it last; keep CodingKeys/decoder consistent with the struct's existing style — synthesized Codable on an Optional decodes a missing key to `nil`).

- [ ] **Step 5: Run — expect pass**

Run: `cd Packages/DebridCore && swift test 2>&1 | tail -4`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/RealDebrid/RealDebridResourceModels.swift Packages/DebridCore/Tests/DebridCoreTests/TorrentInfoAddedTests.swift
git commit -m "feat(core): TorrentInfo.added (optional, back-compat)"
```

### Task 3.2: Carry `added` onto `TorrentInfo` in the client

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/RealDebrid/TorrentsClient.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/TorrentsClientMergeTests.swift`

- [ ] **Step 1: Read** `TorrentsClient.swift` — find `allTorrentInfos()` and confirm it has both the `[Torrent]` list (which has `added`) and the decoded `[TorrentInfo]` (which now has an `added` that's nil from `/info`). Note the internal memberwise init availability.

- [ ] **Step 2: Write the failing test for a pure merge helper**

```swift
import Testing
import Foundation
@testable import DebridCore

@Suite struct TorrentsClientMergeTests {
    @Test func attachesAddedById() {
        let infos = [TorrentInfo(id: "a", filename: "fa", hash: "h", bytes: 1, progress: 100, status: "downloaded", files: [], links: [], added: nil),
                     TorrentInfo(id: "b", filename: "fb", hash: "h", bytes: 1, progress: 100, status: "downloaded", files: [], links: [], added: nil)]
        let torrents = [Torrent(id: "a", filename: "fa", hash: "h", bytes: 1, host: "x", progress: 100, status: "downloaded", added: "2026-06-01T00:00:00.000Z", links: [], ended: nil)]
        let merged = TorrentsClient.attachAddedDates(infos: infos, torrents: torrents)
        #expect(merged.first(where: { $0.id == "a" })?.added == "2026-06-01T00:00:00.000Z")
        #expect(merged.first(where: { $0.id == "b" })?.added == nil)
    }
}
```
(Adapt the `TorrentInfo`/`Torrent` initializers to the exact field order read in Step 1.)

- [ ] **Step 3: Run — expect failure**

Run: `cd Packages/DebridCore && swift test 2>&1 | tail -8`
Expected: `type 'TorrentsClient' has no member 'attachAddedDates'`.

- [ ] **Step 4: Implement the helper + use it** — add to `TorrentsClient`:

```swift
static func attachAddedDates(infos: [TorrentInfo], torrents: [Torrent]) -> [TorrentInfo] {
    let addedByID = Dictionary(torrents.map { ($0.id, $0.added) }, uniquingKeysWith: { a, _ in a })
    return infos.map { info in
        guard let added = addedByID[info.id] else { return info }
        return TorrentInfo(id: info.id, filename: info.filename, hash: info.hash, bytes: info.bytes,
                           progress: info.progress, status: info.status, files: info.files,
                           links: info.links, added: added)
    }
}
```
Then in `allTorrentInfos()`, return `attachAddedDates(infos: <decoded infos>, torrents: <the torrent list>)`.

- [ ] **Step 5: Run — expect pass** — `cd Packages/DebridCore && swift test 2>&1 | tail -4`. Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/RealDebrid/TorrentsClient.swift Packages/DebridCore/Tests/DebridCoreTests/TorrentsClientMergeTests.swift
git commit -m "feat(core): thread RD added date onto TorrentInfo"
```

### Task 3.3: `MediaItem.addedAt`

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/Library/MediaItem.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/MediaItemAddedAtTests.swift`

- [ ] **Step 1: Read** `MediaItem.swift` — confirm the exact stored properties and the `public init` parameter order.

- [ ] **Step 2: Write the failing test**

```swift
import Testing
import Foundation
@testable import DebridCore

@Suite struct MediaItemAddedAtTests {
    @Test func storesAndRoundTripsAddedAt() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let item = MediaItem(id: "movie:x", kind: .movie, title: "X", year: nil, sources: [], seasons: [], addedAt: date)
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(MediaItem.self, from: data)
        #expect(decoded.addedAt == date)
    }
    @Test func decodesOldSnapshotWithoutAddedAt() throws {
        // Old cached snapshots have no `addedAt` key — must decode to nil, not throw.
        let item = MediaItem(id: "movie:x", kind: .movie, title: "X", year: nil, sources: [], seasons: [])
        var dict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as! [String: Any]
        dict.removeValue(forKey: "addedAt")
        let decoded = try JSONDecoder().decode(MediaItem.self, from: JSONSerialization.data(withJSONObject: dict))
        #expect(decoded.addedAt == nil)
        #expect(decoded.id == "movie:x")
    }
}
```

- [ ] **Step 3: Run — expect failure** — `cd Packages/DebridCore && swift test 2>&1 | tail -8`. Expected: `MediaItem … has no member/parameter 'addedAt'`.

- [ ] **Step 4: Add the field** — add `public let addedAt: Date?` to the struct and `addedAt: Date? = nil` as the **last** parameter of the `public init` (default keeps every existing call site compiling). Synthesized `Codable` on the Optional decodes a missing key to `nil`.

- [ ] **Step 5: Run — expect pass** — `cd Packages/DebridCore && swift test 2>&1 | tail -4`. Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Library/MediaItem.swift Packages/DebridCore/Tests/DebridCoreTests/MediaItemAddedAtTests.swift
git commit -m "feat(core): MediaItem.addedAt (optional, back-compat with old snapshots)"
```

### Task 3.4: Parse the date in `LibraryBuilder`

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/Library/LibraryBuilder.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/LibraryBuilderAddedTests.swift`

- [ ] **Step 1: Read** `LibraryBuilder.swift` — find `group(_:)` and how it constructs `MediaItem`s for movies and shows, and what `TorrentInfo`/file data is in scope per item.

- [ ] **Step 2: Write the failing test for the parse helper**

```swift
import Testing
import Foundation
@testable import DebridCore

@Suite struct LibraryBuilderAddedTests {
    @Test func parsesISO8601WithFractionalSeconds() {
        let d = LibraryBuilder.parseAdded("2026-06-01T10:30:00.000Z")
        #expect(d != nil)
    }
    @Test func parsesISO8601WithoutFractionalSeconds() {
        #expect(LibraryBuilder.parseAdded("2026-06-01T10:30:00Z") != nil)
    }
    @Test func returnsNilForGarbage() {
        #expect(LibraryBuilder.parseAdded("not-a-date") == nil)
        #expect(LibraryBuilder.parseAdded(nil) == nil)
    }
}
```

- [ ] **Step 3: Run — expect failure** — `cd Packages/DebridCore && swift test 2>&1 | tail -8`. Expected: `type 'LibraryBuilder' has no member 'parseAdded'`.

- [ ] **Step 4: Implement the helper + wire it**

```swift
static func parseAdded(_ string: String?) -> Date? {
    guard let string else { return nil }
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = withFraction.date(from: string) { return d }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: string)
}
```
Then in `group(_:)`: for a **movie**, pass `addedAt: Self.parseAdded(info.added)`. For a **show**, compute the newest episode date and pass it: `addedAt: episodeInfos.compactMap { Self.parseAdded($0.added) }.max()` (so new episodes resurface the show in Recently Added). Use the real local variable names from Step 1.

- [ ] **Step 5: Run — expect pass** — `cd Packages/DebridCore && swift test 2>&1 | tail -4`. Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Library/LibraryBuilder.swift Packages/DebridCore/Tests/DebridCoreTests/LibraryBuilderAddedTests.swift
git commit -m "feat(core): LibraryBuilder parses RD added date into MediaItem.addedAt"
```

### Task 3.5: Preserve `addedAt` through `MetadataEnricher`

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/Library/MetadataEnricher.swift`

- [ ] **Step 1: Read** `MetadataEnricher.swift` — find every place it constructs a new `MediaItem` from an input item + TMDB data.

- [ ] **Step 2: Thread the field** — at each `MediaItem(...)` construction inside the enricher, add `addedAt: item.addedAt` (carry the pre-enrichment value through). This is a no-test plumbing change validated by the next step + Task 3.7.

- [ ] **Step 3: Build the package** — `cd Packages/DebridCore && swift build 2>&1 | tail -3` then `swift test 2>&1 | tail -4`. Expected: builds; all existing tests still pass.

- [ ] **Step 4: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Library/MetadataEnricher.swift
git commit -m "fix(core): preserve MediaItem.addedAt through metadata enrichment"
```

### Task 3.6: Expose `recentlyWatched` on the seam + public `WatchState` init

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/Persistence/WatchProgress.swift` (public `WatchState` init if missing)
- Modify: `Shared/DebridUI/Sources/DebridUI/Detail/WatchProgressProviding.swift`
- Modify: `Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift` (Live conformance)
- Modify: any existing fakes conforming to `WatchProgressProviding` (e.g. in `Shared/DebridUI/Tests`)

- [ ] **Step 1: Read** all four — capture `WatchProgressProviding`'s current methods, the Live conformance, the `WatchProgressStore.recentlyWatched(limit:)` signature, and every existing `WatchProgressProviding` conformer (so none break).

- [ ] **Step 2: Ensure `WatchState` has a public init** — if it lacks one, add:

```swift
public init(contentKey: String, sourceKey: String, positionSeconds: Double,
            durationSeconds: Double, finished: Bool, updatedAt: Date) {
    self.contentKey = contentKey; self.sourceKey = sourceKey
    self.positionSeconds = positionSeconds; self.durationSeconds = durationSeconds
    self.finished = finished; self.updatedAt = updatedAt
}
```

- [ ] **Step 3: Add the seam method** — in `WatchProgressProviding` add:

```swift
func recentlyWatched(limit: Int) async throws -> [WatchState]
```

- [ ] **Step 4: Implement in the Live conformer** (in `AppSession.swift` or wherever `LiveWatchProgress` lives) — delegate to the store:

```swift
func recentlyWatched(limit: Int) async throws -> [WatchState] {
    try await store.recentlyWatched(limit: limit)   // `store` = the WatchProgressStore actor
}
```

- [ ] **Step 5: Update existing fakes** — add the method to every other `WatchProgressProviding` conformer found in Step 1 (test fakes): `func recentlyWatched(limit: Int) async throws -> [WatchState] { [] }`.

- [ ] **Step 6: Build + test both packages**

Run:
```bash
cd Packages/DebridCore && swift test 2>&1 | tail -3
cd ../../Shared/DebridUI && swift test 2>&1 | tail -3
```
Expected: both pass (no conformers broken).

- [ ] **Step 7: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Persistence/WatchProgress.swift Shared/DebridUI/Sources/DebridUI/Detail/WatchProgressProviding.swift Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift Shared/DebridUI/Tests
git commit -m "feat(ui): expose recentlyWatched on WatchProgressProviding + public WatchState init"
```

### Task 3.7: `HomeStore` (TDD)

**Files:**
- Create: `Shared/DebridUI/Sources/DebridUI/Home/HomeStore.swift`
- Create: `Shared/DebridUI/Tests/DebridUITests/HomeStoreTests.swift`
- Modify: `Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift` (expose a `home` factory/property)

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import DebridUI
import DebridCore

private struct FakeWatch: WatchProgressProviding {
    var states: [WatchState]
    func recentlyWatched(limit: Int) async throws -> [WatchState] { Array(states.prefix(limit)) }
    // Implement the rest of WatchProgressProviding as no-ops to match the protocol read in Task 3.6.
    func progress(forContentKey key: String) async -> WatchState? { nil }
    func record(contentKey: String, sourceKey: String, positionSeconds: Double, durationSeconds: Double) async {}
}

@Suite struct HomeStoreTests {
    @MainActor @Test func resolvesMovieAndShowProgress() async {
        let movie = MediaItem(id: "movie:dune:2021", kind: .movie, title: "Dune", year: 2021, sources: [], seasons: [])
        let show  = MediaItem(id: "show:bb", kind: .show, title: "Breaking Bad", year: 2008, sources: [], seasons: [])
        let states = [
            WatchState(contentKey: "movie:dune:2021", sourceKey: "t#f", positionSeconds: 30, durationSeconds: 120, finished: false, updatedAt: Date()),
            WatchState(contentKey: "show:bb:s3e4", sourceKey: "t#f", positionSeconds: 600, durationSeconds: 1200, finished: false, updatedAt: Date())
        ]
        let store = HomeStore(watch: FakeWatch(states: states))
        await store.rebuild(movies: [movie], shows: [show])
        #expect(store.continueWatching.count == 2)
        #expect(store.continueWatching[0].item.id == "movie:dune:2021")
        #expect(abs(store.continueWatching[0].fraction - 0.25) < 0.001)
        #expect(store.continueWatching[1].item.id == "show:bb")
        #expect(store.continueWatching[1].subtitle == "S3 · E4")
    }

    @MainActor @Test func recentlyAddedSortsDescAndSkipsNil() async {
        let older = MediaItem(id: "a", kind: .movie, title: "A", year: nil, sources: [], seasons: [], addedAt: Date(timeIntervalSince1970: 1000))
        let newer = MediaItem(id: "b", kind: .movie, title: "B", year: nil, sources: [], seasons: [], addedAt: Date(timeIntervalSince1970: 2000))
        let undated = MediaItem(id: "c", kind: .movie, title: "C", year: nil, sources: [], seasons: [])
        let store = HomeStore(watch: FakeWatch(states: []))
        await store.rebuild(movies: [older, newer, undated], shows: [])
        #expect(store.recentlyAdded.map(\.id) == ["b", "a"])
    }
}
```

- [ ] **Step 2: Run — expect failure** — `cd Shared/DebridUI && swift test 2>&1 | tail -8`. Expected: `cannot find 'HomeStore' in scope`.

- [ ] **Step 3: Implement `HomeStore.swift`**

```swift
import Foundation
import DebridCore

public struct HomeItem: Identifiable, Sendable, Equatable {
    public let item: MediaItem
    public let fraction: Double
    public let subtitle: String
    public var id: String { item.id + "|" + subtitle }
}

@MainActor
@Observable
public final class HomeStore {
    public private(set) var continueWatching: [HomeItem] = []
    public private(set) var recentlyAdded: [MediaItem] = []
    public var featured: HomeItem? { continueWatching.first }

    private let watch: WatchProgressProviding
    public init(watch: WatchProgressProviding) { self.watch = watch }

    /// Recompute both rails from the current library + watch progress.
    public func rebuild(movies: [MediaItem], shows: [MediaItem]) async {
        let states = (try? await watch.recentlyWatched(limit: 20)) ?? []
        continueWatching = states.compactMap { Self.resolve($0, movies: movies, shows: shows) }
        let all = movies + shows
        recentlyAdded = Array(all.filter { $0.addedAt != nil }
            .sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
            .prefix(20))
    }

    static func resolve(_ s: WatchState, movies: [MediaItem], shows: [MediaItem]) -> HomeItem? {
        let fraction = s.durationSeconds > 0 ? min(1, s.positionSeconds / s.durationSeconds) : 0
        if let movie = movies.first(where: { $0.id == s.contentKey }) {
            return HomeItem(item: movie, fraction: fraction, subtitle: "")
        }
        if let show = shows.first(where: { s.contentKey.hasPrefix($0.id + ":") }) {
            let epKey = String(s.contentKey.dropFirst(show.id.count + 1))
            return HomeItem(item: show, fraction: fraction, subtitle: Self.formatEpisodeKey(epKey))
        }
        return nil
    }

    /// "s3e4" → "S3 · E4"; falls back to the raw key if it isn't sXeY.
    static func formatEpisodeKey(_ key: String) -> String {
        let lower = key.lowercased()
        guard let s = lower.firstIndex(of: "s"), let e = lower.firstIndex(of: "e"), s < e else { return key }
        let season = lower[lower.index(after: s)..<e]
        let episode = lower[lower.index(after: e)...]
        guard !season.isEmpty, !episode.isEmpty,
              season.allSatisfy(\.isNumber), episode.allSatisfy(\.isNumber) else { return key }
        return "S\(season) · E\(episode)"
    }
}
```

- [ ] **Step 4: Run — expect pass** — `cd Shared/DebridUI && swift test 2>&1 | tail -4`. Expected: all pass.

- [ ] **Step 5: Expose on `AppSession`** — read `AppSession.swift` for how `LibraryStore`/`DetailStore` are exposed, then add a `home` property built with the live watch provider (mirror the existing pattern):

```swift
public lazy var home = HomeStore(watch: liveWatchProgress)   // use the same live provider as DetailStore
```

- [ ] **Step 6: Build the app** — `cd /Users/shaharsolomons/Documents/Code/Seret && xcodebuild -scheme SeretMobile -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3`. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Shared/DebridUI/Sources/DebridUI/Home/HomeStore.swift Shared/DebridUI/Tests/DebridUITests/HomeStoreTests.swift Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift
git commit -m "feat(ui): HomeStore — Continue Watching + Recently Added composition (TDD)"
```

---

## Phase 4 — Screens

> Each screen task: **read the current file first** to capture data wiring (stores, `NavigationLink(value:)`/`navigationDestination`, the TMDB poster/backdrop URL helper), then recompose with the design system, preserving all wiring. Verify by `xcodegen generate` → build → mobile-mcp screenshot. Use `mobile_save_screenshot` (high-res), never the tiny one. If no RD token is signed in on the sim, verify layout via loading/empty/failed states and structure; note full-data population as owner-pending.

### Task 4.1: HomeScreen

**Files:**
- Create: `Apps/SeretMobile/Home/HomeScreen.swift`

- [ ] **Step 1: Read wiring** — `cat Apps/SeretMobile/Library/LibrarySection.swift Apps/SeretMobile/Library/PosterTile.swift` to capture: how the view gets `AppSession` (e.g. `@Environment`), the `LibraryStore` access, the poster/backdrop **URL helper**, and the `NavigationLink(value: MediaItem)` + `navigationDestination(for: MediaItem.self) { DetailScreen(item: $0) }` pattern.

- [ ] **Step 2: Create `HomeScreen.swift`** — compose Hero + two rails on `session.home`, recomputing when the library changes. Reuse the URL helper and DetailScreen nav from Step 1.

```swift
import SwiftUI
import DebridUI
import DebridCore

struct HomeScreen: View {
    @Environment(AppSession.self) private var session   // match the real injection from Step 1
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Space.xxl) {
                    if let f = session.home.featured {
                        NavigationLink(value: f.item) {
                            HeroBackdrop(imageURL: backdropURL(f.item), height: 230) {
                                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                                    Text(f.subtitle.isEmpty ? "Continue" : "Continue · \(f.subtitle)")
                                        .font(Theme.Typo.label()).tracking(1.5).foregroundStyle(Theme.Palette.gold)
                                    Text(f.item.title).font(Theme.Typo.titleXL()).foregroundStyle(Theme.Palette.textPrimary).lineLimit(2)
                                    Label("Resume", systemImage: "play.fill")
                                        .padding(.top, 2)
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                    if !session.home.continueWatching.isEmpty {
                        Rail(title: "Continue Watching") {
                            ForEach(session.home.continueWatching) { hi in
                                NavigationLink(value: hi.item) {
                                    LandscapeProgressCard(title: hi.item.title, subtitle: hi.subtitle,
                                                          imageURL: backdropURL(hi.item), fraction: hi.fraction)
                                }.pressable()
                            }
                        }
                    }
                    if !session.home.recentlyAdded.isEmpty {
                        Rail(title: "Recently Added") {
                            ForEach(session.home.recentlyAdded) { item in
                                NavigationLink(value: item) {
                                    PosterCard(title: item.title, posterURL: posterURL(item))
                                }.pressable()
                            }
                        }
                    }
                    if session.home.continueWatching.isEmpty && session.home.recentlyAdded.isEmpty {
                        emptyState
                    }
                }
                .padding(.vertical, Theme.Space.lg)
            }
            .background(CanvasBackground())
            .navigationTitle("Home").toolbarTitleDisplayMode(.inlineLarge)
            .navigationDestination(for: MediaItem.self) { DetailScreen(item: $0) }
        }
        .task { await refresh() }
        .onChange(of: session.library.movies) { _, _ in Task { await refresh() } }
        .onChange(of: session.library.shows)  { _, _ in Task { await refresh() } }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.md) {
            SeretMark(glow: false).frame(width: 54).opacity(0.5)
            Text("Nothing here yet").font(Theme.Typo.headline()).foregroundStyle(Theme.Palette.textSecondary)
            Text("Sign in and add titles to see them here.").font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textTertiary)
        }.frame(maxWidth: .infinity).padding(.top, 80)
    }

    private func refresh() async {
        await session.home.rebuild(movies: session.library.movies, shows: session.library.shows)
    }
    // `posterURL`/`backdropURL`: use the exact helper found in Step 1 (TMDBClient image URL).
    private func posterURL(_ i: MediaItem) -> URL? { /* helper from Step 1 */ nil }
    private func backdropURL(_ i: MediaItem) -> URL? { /* helper from Step 1 */ nil }
}
```
Replace the two `// helper from Step 1` stubs with the real TMDB URL calls; do not ship the `nil` stubs.

- [ ] **Step 3: Build** — `xcodegen generate && xcodebuild -scheme SeretMobile -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3`. Expected: `** BUILD SUCCEEDED **` (screenshot happens in 4.2 once it's hosted).

- [ ] **Step 4: Commit**

```bash
git add Apps/SeretMobile/Home/HomeScreen.swift
git commit -m "feat(home): Home screen — featured hero + Continue Watching + Recently Added"
```

### Task 4.2: MainShell — add Home tab

**Files:**
- Modify: `Apps/SeretMobile/Shell/MainShell.swift`

- [ ] **Step 1: Read** `MainShell.swift` — capture the section enum (`.movies/.shows/.settings`), the `TabView` (compact) and `NavigationSplitView` (regular) construction, and how each destination view is built.

- [ ] **Step 2: Add Home** — add a `.home` case (first), map icons (Home `house.fill`, Movies `film.fill`, Shows `tv.fill`, Settings `gearshape.fill`), put `HomeScreen()` as the Home destination in both the `TabView` and the sidebar, and tint selection gold:

```swift
// TabView branch:
TabView(selection: $selection) {
    HomeScreen().tabItem { Label("Home", systemImage: "house.fill") }.tag(Section.home)
    MoviesScreen().tabItem { Label("Movies", systemImage: "film.fill") }.tag(Section.movies)
    ShowsScreen().tabItem { Label("Shows", systemImage: "tv.fill") }.tag(Section.shows)
    SettingsView().tabItem { Label("Settings", systemImage: "gearshape.fill") }.tag(Section.settings)
}
.tint(Theme.Palette.gold)
```
Use the real destination view names from Step 1 (`MoviesScreen`/`ShowsScreen` shown as placeholders for whatever the current Movies/Shows views are). Add `.home` to the sidebar `List` the same way, and set the split view's detail default to Home.

- [ ] **Step 3: Build** — Task 4.1 Step 3 command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Verify (mobile-mcp, iPhone)** — boot iPhone sim, launch SeretMobile, dismiss splash, land on **Home**. `mobile_save_screenshot`. Confirm: 4-tab bar (Home selected, gold), glass tab bar, canvas glow, no clipping; tap each tab and screenshot to confirm they switch. Rotate to landscape (`mobile_set_orientation`/equivalent), screenshot Home — tab bar still correct, content reflows.

- [ ] **Step 5: Commit**

```bash
git add Apps/SeretMobile/Shell/MainShell.swift
git commit -m "feat(shell): Home tab (4 tabs) with gold selection; iPhone TabView + iPad sidebar"
```

### Task 4.3: Sign-in redesign

**Files:**
- Modify: `Apps/SeretMobile/Auth/SignInView.swift`

- [ ] **Step 1: Read** `SignInView.swift` — capture `SignInModel` phases, the device-code action, the token-paste action/field, and `SafariSheet` presentation. Preserve all of it; restyle only.

- [ ] **Step 2: Restyle** — `CanvasBackground()` + centered `Wordmark()`, a tagline, primary `GoldButtonStyle` for "Sign in with Real-Debrid", `GhostButtonStyle` for "Use a token", and the token field on `surface2`. Keep every existing binding/handler. Skeleton:

```swift
ZStack {
    CanvasBackground()
    VStack(spacing: Theme.Space.xl) {
        Spacer()
        Wordmark(hebrewSize: 52)
        Text("Your debrid library, everywhere.")
            .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
        Spacer()
        VStack(spacing: Theme.Space.md) {
            Button(action: model.beginDeviceCode) { Text("Sign in with Real-Debrid").frame(maxWidth: .infinity) }
                .buttonStyle(GoldButtonStyle())
            Button("Use a token instead") { /* existing toggle */ }.buttonStyle(GhostButtonStyle())
        }
        .padding(.horizontal, Theme.Space.xxl).padding(.bottom, Theme.Space.xxl)
    }
    // keep the existing device-code display + token entry + SafariSheet, restyled with surface2/gold.
}
```

- [ ] **Step 3: Build** — Task 4.1 Step 3 command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Verify (mobile-mcp)** — sign out (or fresh install) so the signed-out screen shows; `mobile_save_screenshot` portrait + landscape. Confirm: wordmark + gold button render, no clipping, button tappable (tap shows device-code/token flow).

- [ ] **Step 5: Commit**

```bash
git add Apps/SeretMobile/Auth/SignInView.swift
git commit -m "feat(auth): Gold Glass sign-in with wordmark + gold CTA"
```

### Task 4.4: Library (Movies / Shows) restyle

**Files:**
- Modify: `Apps/SeretMobile/Library/LibraryGrid.swift`, `Apps/SeretMobile/Library/PosterTile.swift`, `Apps/SeretMobile/Library/LibrarySection.swift`

- [ ] **Step 1: Read** all three — capture the `LazyVGrid` columns, `LibraryStore` state handling, and nav.

- [ ] **Step 2: Restyle** — set `CanvasBackground()`; replace tiles with `PosterCard`; use adaptive columns that grow with width:

```swift
private var columns: [GridItem] {
    [GridItem(.adaptive(minimum: 108, maximum: 160), spacing: Theme.Space.md)]
}
// loading → grid of ShimmerView at 2:3; empty/failed → styled message + retry (GhostButtonStyle)
LazyVGrid(columns: columns, spacing: Theme.Space.lg) {
    ForEach(items) { item in
        NavigationLink(value: item) { PosterCard(title: item.title, posterURL: posterURL(item)) }.pressable()
    }
}
.padding(.horizontal, Theme.Space.lg)
```
Keep the existing `navigationDestination(for: MediaItem.self)`. The `.adaptive` columns give ~3 (compact portrait) → 5–7 (regular/landscape) automatically.

- [ ] **Step 3: Build** — Task 4.1 Step 3 command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Verify (mobile-mcp)** — Movies + Shows tabs, `mobile_save_screenshot`. Confirm: poster grid, gold section/title, no clipping; **rotate to landscape** and confirm more columns appear and spacing holds. (Posters need a signed-in library; otherwise verify the loading/empty/failed states.)

- [ ] **Step 5: Commit**

```bash
git add Apps/SeretMobile/Library
git commit -m "feat(library): Gold Glass grids with PosterCard + adaptive columns"
```

### Task 4.5: Detail restyle (movie + show, two-column wide)

**Files:**
- Modify: `Apps/SeretMobile/Detail/DetailScreen.swift`, `Apps/SeretMobile/Detail/MovieDetail.swift`, `Apps/SeretMobile/Detail/ShowDetail.swift`

- [ ] **Step 1: Read** all three — capture `DetailStore`, the Play/Resume actions + `PlaybackRequest`, the player presentation, versions list, season picker/episode list, and image helpers. Preserve all wiring.

- [ ] **Step 2: Restyle (compact, stacked)** — `HeroBackdrop` (backdrop) overlapping into title; `Text(title)` `titleXL`; meta row with `QualityChip`s; primary `GoldButtonStyle` Resume/Play + `GhostButtonStyle` secondary; overview in `textSecondary`; Versions rows on `surface2`; show episode rows with TMDB title/synopsis and a **gold** watched check (`Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Palette.gold)`).

- [ ] **Step 3: Two-column for regular width** — wrap the body so wide layouts use two columns:

```swift
@Environment(\.horizontalSizeClass) private var hSize
// ...
if hSize == .regular {
    HStack(alignment: .top, spacing: Theme.Space.xxl) {
        leftColumn   // backdrop/poster + title + actions, fixed ~360pt width
        ScrollView { rightColumn }   // meta + overview + versions + episodes
    }
} else {
    ScrollView { VStack(alignment: .leading) { hero; title; actions; overview; versions; episodes } }
}
```
Factor the content into `leftColumn`/`rightColumn`/section subviews so both branches reuse them (DRY).

- [ ] **Step 4: Build** — Task 4.1 Step 3 command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Verify (mobile-mcp)** — open a Detail (tap a poster). `mobile_save_screenshot` portrait. Confirm: cinematic hero gradient, gold Resume/Play, chips, overview, versions; for a show, season picker + episode list. **Rotate to landscape** → confirm two-column layout. No clipping; buttons tappable.

- [ ] **Step 6: Commit**

```bash
git add Apps/SeretMobile/Detail
git commit -m "feat(detail): cinematic Gold Glass detail + two-column wide layout"
```

### Task 4.6: Player — subtler restyle

**Files:**
- Modify: `Apps/SeretMobile/Playback/PlayerView.swift`, `Apps/SeretMobile/Playback/PlayerOverlays.swift`, `Apps/SeretMobile/Playback/PlayerSettingsSheet.swift`

- [ ] **Step 1: Read** all three — capture `PlayerModel` bindings: `controlsVisible`, play/pause, the ±10s skip handlers, scrubbing (`beginScrub`/`updateScrub`/`commitScrub` or the slider binding), time/duration, the tracks/subtitles entry, error/loading states. Preserve every handler.

- [ ] **Step 2: Restyle to subtle** — remove the big gold circular button. Center transport = **white SF Symbols**, no gold fill, no heavy glow:

```swift
HStack(spacing: 44) {
    Button(action: model.skipBackward) { Image(systemName: "gobackward.10") }
    Button(action: model.togglePlayPause) { Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 44)) }
    Button(action: model.skipForward) { Image(systemName: "goforward.10") }
}
.font(.system(size: 30, weight: .semibold))
.foregroundStyle(.white)
```
Top scrim: back chevron + title + tracks button (white, small) over a `LinearGradient(.black.opacity(0.5) → .clear)` — not a solid bar. Bottom: a slim **gold** scrubber (tint the `Slider`/progress gold, white monospaced time labels). Use thin black top/bottom gradient scrims instead of glass bars. Keep `controlsVisible` auto-hide + the existing 0.2s fade. Gold appears **only** on the scrubber fill/knob.

```swift
Slider(value: scrubBinding, in: 0...max(model.duration, 0.001))
    .tint(Theme.Palette.gold)
```

- [ ] **Step 3: Restyle overlays + settings sheet** — `PlayerOverlays`: loading = white `ProgressView().tint(.white)` on a subtle dim; error = message + retry/try-another/back as `GhostButtonStyle`. `PlayerSettingsSheet`: `surface1` background, `Theme.Radius.sheet`, gold check on the selected audio/subtitle track, gold tint on the speed control.

- [ ] **Step 4: Build** — Task 4.1 Step 3 command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Verify (mobile-mcp)** — enter the player (needs a signed-in, playable item; if unavailable, verify the loading + error overlays and the transport layout). `mobile_save_screenshot` in **landscape**. Confirm: white transport (no gold button), thin gold scrubber, readable times, tracks button works, controls auto-hide on tap.

- [ ] **Step 6: Commit**

```bash
git add Apps/SeretMobile/Playback
git commit -m "feat(player): subtler transport — white controls, gold only on the scrubber"
```

### Task 4.7: Settings restyle

**Files:**
- Modify: `Apps/SeretMobile/Shell/SettingsView.swift`

- [ ] **Step 1: Read** `SettingsView.swift` — capture the RD account status, OpenSubtitles fields, version, and sign-out action.

- [ ] **Step 2: Restyle** — keep the `Form`/`List` but apply: `.scrollContentBackground(.hidden)` + `CanvasBackground()`, `Theme.Palette.surface1` section backgrounds, gold accents on toggles/links (`.tint(Theme.Palette.gold)`), a small `SeretMark` + version in the footer, sign-out in red (`.foregroundStyle(.red)`).

- [ ] **Step 3: Build** — Task 4.1 Step 3 command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Verify (mobile-mcp)** — Settings tab, `mobile_save_screenshot` portrait + landscape. Confirm dark grouped form, gold accents, readable rows, no clipping.

- [ ] **Step 5: Commit**

```bash
git add Apps/SeretMobile/Shell/SettingsView.swift
git commit -m "feat(settings): Gold Glass settings form"
```

---

## Phase 5 — Responsive & motion polish

### Task 5.1: Orientation config + landscape audit

**Files:**
- Modify: `project.yml` (and regenerate `Apps/SeretMobile/Info.plist` via xcodegen)

- [ ] **Step 1: Read** `project.yml` SeretMobile `info.properties` orientations.

- [ ] **Step 2: Ensure all orientations** — confirm `UISupportedInterfaceOrientations` = Portrait + LandscapeLeft + LandscapeRight, and add `UISupportedInterfaceOrientations~ipad` with all four (incl. `UIInterfaceOrientationPortraitUpsideDown`). Grep for any programmatic orientation lock (`AppDelegate`/`supportedInterfaceOrientations`/`UIDevice` rotation) and remove it if present.

```yaml
UISupportedInterfaceOrientations:
  - UIInterfaceOrientationPortrait
  - UIInterfaceOrientationLandscapeLeft
  - UIInterfaceOrientationLandscapeRight
UISupportedInterfaceOrientations~ipad:
  - UIInterfaceOrientationPortrait
  - UIInterfaceOrientationPortraitUpsideDown
  - UIInterfaceOrientationLandscapeLeft
  - UIInterfaceOrientationLandscapeRight
```

- [ ] **Step 3: Build** — `xcodegen generate && xcodebuild -scheme SeretMobile -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3`. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Landscape audit (mobile-mcp)** — on iPhone sim, rotate to landscape and walk Home → Movies → Detail → Player → Settings, `mobile_save_screenshot` each. Confirm no clipping/overlap, safe-area insets respected, grids gain columns. Fix any screen that breaks (usually a missing `ScrollView` or a fixed width) and re-shoot.

- [ ] **Step 5: Commit**

```bash
git add project.yml Apps/SeretMobile/Info.plist
git commit -m "feat(mobile): first-class landscape on iPhone + iPad"
```

### Task 5.2: Motion polish pass

**Files:** touch the screen files as needed (small, additive).

- [ ] **Step 1: Apply consistent motion** — confirm `.pressable()` on every tappable poster/card; add `.animation(Theme.Motion.standard, value: <state>)` to grid/rail data changes and the Detail two-column switch; ensure tab/selection changes animate; confirm the splash `.transition(.opacity)`. All already-Reduce-Motion-safe (tokens + `accessibilityReduceMotion` guards).

- [ ] **Step 2: Verify Reduce Motion** — enable Reduce Motion in the sim (Settings ▸ Accessibility) and relaunch; confirm the splash shows the fade-only path and nothing janks. `mobile_save_screenshot`.

- [ ] **Step 3: Build + commit**

```bash
xcodebuild -scheme SeretMobile -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3
git add Apps/SeretMobile
git commit -m "polish(motion): consistent springs, pressable cards, reduce-motion safe"
```

---

## Phase 6 — Verification & handoff

### Task 6.1: Build matrix + tests

- [ ] **Step 1: Build mobile for both device families**

```bash
cd /Users/shaharsolomons/Documents/Code/Seret && xcodegen generate
xcodebuild -scheme SeretMobile -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3
xcodebuild -scheme SeretMobile -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' build 2>&1 | tail -3
```
Expected: both `** BUILD SUCCEEDED **`. (Adjust device names to `xcrun simctl list devices available`.)

- [ ] **Step 2: tvOS no-regression build**

```bash
xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **` (proves shared-package changes didn't break tvOS).

- [ ] **Step 3: Package tests**

```bash
cd Packages/DebridCore && swift test 2>&1 | tail -3
cd ../../Shared/DebridUI && swift test 2>&1 | tail -3
```
Expected: all pass, including the new TorrentInfo/MediaItem/LibraryBuilder/HomeStore tests.

### Task 6.2: iPhone walkthrough (mobile-mcp)

- [ ] **Step 1:** Install + launch on the iPhone sim. Sign in (owner's token if available). Walk: Splash → Sign-in → Home → Movies → Shows → Detail (movie) → Detail (show) → Player → Settings.
- [ ] **Step 2:** `mobile_save_screenshot` (high-res) each, **portrait**. Then rotate and re-shoot Home, Movies, Detail, Player **landscape**.
- [ ] **Step 3:** Checklist per screen: gold-on-black correct (no purple), no clipping, no overlap, safe areas respected, every button responds (`mobile_list_elements_on_screen` + tap to confirm), tab bar correct, splash plays once. File any defect as a fix + re-shoot before proceeding.

### Task 6.3: iPad walkthrough (mobile-mcp)

- [ ] **Step 1:** Launch on the iPad sim; confirm `NavigationSplitView` sidebar (Home/Movies/Shows/Settings).
- [ ] **Step 2:** `mobile_save_screenshot` Home, Movies (column count), Detail (two-column), Player, Settings — **portrait and landscape**.
- [ ] **Step 3:** Same checklist as 6.2, plus: sidebar selection tint gold, two-column Detail correct, grids use the width.

### Task 6.4: Deliver + record

- [ ] **Step 1:** Collect the best before/after screenshots; send the after set to the owner (SendUserFile).
- [ ] **Step 2:** Update the `project_seret.md` memory: redesign branch `feat/mobile-redesign`, Gold Glass system, new icon + splash, Home tab + `addedAt` plumbing, landscape; note real-data population (Continue Watching/Recently Added) + on-device verification as owner-pending.
- [ ] **Step 3:** Do **not** push. Tell the owner the branch is ready and ask before pushing to origin.

---

## Self-Review

- **Spec coverage:** Gold Glass tokens → 1.1; modifiers/glass → 1.2; icon → 2.1; splash w/ סֶרֶט+SERET → 2.2; Home (Continue Watching + Recently Added) → 3.1–3.7 + 4.1–4.2; subtler player → 4.6; landscape → 5.1 + 4.x verifications; animations → 1.x + 5.2; per-screen redesign → 4.2–4.7; watched-check green→gold → 4.5; verification on iPhone+iPad both orientations → 6.1–6.3; tvOS untouched/no-regression → 6.1; no-push → 6.4. All spec sections mapped.
- **Placeholder scan:** the only intentional "fill from the real file" markers are the URL-helper lines in 4.1 and the wiring reads — each has an explicit instruction to replace with the real call and not ship the stub. No "TBD/handle edge cases" left.
- **Type consistency:** `Theme.*`, `SeretMark`, `Wordmark`, `GoldButtonStyle`/`GhostButtonStyle`, `PosterCard`, `LandscapeProgressCard`, `GoldProgressBar`, `SectionHeader`, `QualityChip`, `Rail`, `HeroBackdrop`, `ShimmerView`, `HomeStore`/`HomeItem`, `MediaItem.addedAt`, `TorrentInfo.added`, `WatchProgressProviding.recentlyWatched(limit:)` are defined once and reused with consistent names.
