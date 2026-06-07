# Trailers — Slice 2 (iOS Playback + Auto-Play) Implementation Plan

> **For agentic workers:** Inline execution. Steps use `- [ ]`. Builds on Slice 1 (the
> `TrailerModel` + `YouTubeKitStreamResolver` foundation, already merged). Stage only the named paths.

**Goal:** On iPhone/iPad, the Trailer button plays the trailer **in-app full-screen** (AVPlayer,
sound), and the detail backdrop **auto-plays a muted trailer** after ~4s (cross-fade, unmute
control, stop on leave), gated by a Settings toggle — with a YouTube deep-link fallback when
extraction fails. Replaces the dead WKWebView embed.

**Architecture:** `TrailerModel` (Slice 1) resolves the stream URL. AVPlayer plays it — a SwiftUI
`VideoPlayer` for full-screen (sound) and a custom muted `AVPlayerLayer` view for the inline
backdrop. No VLCKit (trailers are standard H.264/AAC). Verified playing on the iOS simulator.

**Spec:** `docs/superpowers/specs/2026-06-08-trailer-playback-autoplay-design.md`.
**Branch:** `feat/stage2-search-add`.

---

## File Structure

- Create `Apps/SeretMobile/Playback/TrailerPlayers.swift` — `InlineMutedTrailer` (AVPlayerLayer) +
  `FullScreenTrailer` (VideoPlayer sheet).
- Rewrite `Apps/SeretMobile/Playback/TrailerView.swift` — `TrailerButton` now drives `TrailerModel`
  → full-screen AVPlayer, with a YouTube deep-link fallback. Drop the WKWebView embed.
- Modify `Apps/SeretMobile/Detail/MovieDetail.swift` + `ShowDetail.swift` — auto-play muted trailer
  on the backdrop (4s cross-fade, unmute, teardown on disappear).
- Modify `Apps/SeretMobile/Shell/SettingsView.swift` — "Autoplay trailers" toggle.

---

## Task 1: AVPlayer trailer player components

**Files:** Create `Apps/SeretMobile/Playback/TrailerPlayers.swift`

- [ ] **Step 1: Implement the two players**

```swift
import AVKit
import SwiftUI

/// Inline, muted-by-default, looping trailer for the detail backdrop. No controls; an `AVPlayerLayer`
/// fills the space. `muted` is a binding so a parent unmute button can flip it.
struct InlineMutedTrailer: UIViewRepresentable {
    let url: URL
    @Binding var muted: Bool

    func makeUIView(context: Context) -> PlayerLayerView {
        let v = PlayerLayerView()
        let player = AVQueuePlayer()
        let item = AVPlayerItem(url: url)
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: item)
        player.isMuted = muted
        player.play()
        v.player = player
        return v
    }

    func updateUIView(_ v: PlayerLayerView, context: Context) {
        v.playerLayer.player?.isMuted = muted
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var looper: AVPlayerLooper? }

    /// UIView whose backing layer is an AVPlayerLayer (fills bounds, aspect-fill).
    final class PlayerLayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var player: AVPlayer? {
            get { playerLayer.player }
            set { playerLayer.player = newValue; playerLayer.videoGravity = .resizeAspectFill }
        }
    }
}

/// Full-screen trailer with native controls + sound. Presented as a sheet/cover.
struct FullScreenTrailer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }
        }
        .overlay(alignment: .topLeading) {
            Button("Done") { dismiss() }
                .padding().tint(Theme.Palette.gold)
        }
        .onAppear {
            let p = AVPlayer(url: url)
            p.isMuted = false
            player = p
            p.play()
        }
        .onDisappear { player?.pause() }
        .preferredColorScheme(.dark)
    }
}
```

- [ ] **Step 2: Build the app**

Run: `xcodebuild -scheme SeretMobile -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Apps/SeretMobile/Playback/TrailerPlayers.swift
git commit -m "feat(ios): AVPlayer trailer players (inline muted + fullscreen)"
```

---

## Task 2: Trailer button → in-app playback (+ deep-link fallback)

**Files:** Rewrite `Apps/SeretMobile/Playback/TrailerView.swift`

- [ ] **Step 1: Replace the file**

`TrailerButton` builds a `TrailerModel`, resolves on appear, and:
- ready → show the "Trailer" button → tap presents `FullScreenTrailer`.
- unavailable but has a YouTube key → show the button → tap opens YouTube (deep-link fallback).
- still resolving / no key → render nothing (zero-size host so `.task` runs — the Slice-1 fix lesson).

```swift
import AVKit
import DebridCore
import DebridUI
import SwiftUI

/// A "Trailer" button: resolves the title's trailer to a playable stream on appear and plays it
/// full-screen in-app (AVPlayer). Falls back to opening YouTube if extraction fails. Renders
/// nothing until there's something to offer.
struct TrailerButton: View {
    let tmdbID: Int?
    let kind: MediaKind
    @Environment(AppSession.self) private var session
    @State private var model: TrailerModel?
    @State private var showing = false

    var body: some View {
        Group {
            if let model, canOffer(model) {
                Button { showing = true } label: {
                    Label("Trailer", systemImage: "play.rectangle.fill")
                }
                .buttonStyle(GhostButtonStyle())
                .fullScreenCover(isPresented: $showing) { cover(model) }
            } else {
                Color.clear.frame(width: 0, height: 0)   // real host so .task runs
            }
        }
        .task(id: tmdbID) {
            guard let tmdbID, model == nil else { return }
            let m = session.makeTrailerModel()
            model = m
            await m?.prepare(tmdbID: tmdbID, kind: kind)
        }
    }

    private func canOffer(_ m: TrailerModel) -> Bool {
        m.streamURL != nil || m.youTubeKey != nil   // playable, or at least a deep-link target
    }

    @ViewBuilder private func cover(_ m: TrailerModel) -> some View {
        if let url = m.streamURL {
            FullScreenTrailer(url: url)
        } else {
            // Extraction failed but we have a key → bounce to YouTube and dismiss.
            Color.black.ignoresSafeArea()
                .onAppear {
                    if let key = m.youTubeKey,
                       let url = URL(string: "https://www.youtube.com/watch?v=\(key)") {
                        UIApplication.shared.open(url)
                    }
                    showing = false
                }
        }
    }
}
```

- [ ] **Step 2: Build + run on the sim; VERIFY a trailer plays**

Build, install, launch, open a detail (e.g. Sherlock), tap **Trailer** → confirm the AVPlayer
shows the trailer **playing** (this is the real proof the whole approach works). Screenshot it.

- [ ] **Step 3: Commit**

```bash
git add Apps/SeretMobile/Playback/TrailerView.swift
git commit -m "feat(ios): Trailer button plays in-app via AVPlayer (YouTube deep-link fallback)"
```

---

## Task 3: Muted auto-play on the detail backdrop

**Files:** Modify `Apps/SeretMobile/Detail/MovieDetail.swift`, `ShowDetail.swift`

Add a shared `AutoplayBackdrop` view used by both: it owns a `TrailerModel`, after ~4s (if
`autoplayAllowed`) cross-fades the backdrop image into `InlineMutedTrailer`, shows an unmute
speaker button, and tears down on disappear. Replaces the `DetailBackdrop(...)` background in each.

- [ ] **Step 1: Add `AutoplayBackdrop`** (new view in `Apps/SeretMobile/Detail/AutoplayBackdrop.swift`):

```swift
import DebridCore
import DebridUI
import SwiftUI

/// The detail hero background: the TMDB backdrop, which after ~4s cross-fades to a muted, looping
/// trailer (when autoplay is on and a stream resolves). An unmute button toggles sound. Everything
/// tears down on disappear.
struct AutoplayBackdrop: View {
    let tmdbID: Int?
    let kind: MediaKind
    let backdropPath: String?
    let posterFallback: String?

    @Environment(AppSession.self) private var session
    @State private var model: TrailerModel?
    @State private var showVideo = false
    @State private var muted = true

    var body: some View {
        ZStack {
            DetailBackdrop(path: backdropPath, posterFallback: posterFallback)
            if showVideo, let url = model?.streamURL {
                InlineMutedTrailer(url: url, muted: $muted)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .overlay(alignment: .topTrailing) { muteButton }
            }
        }
        .task(id: tmdbID) {
            guard let tmdbID, model == nil else { return }
            let m = session.makeTrailerModel(); model = m
            await m?.prepare(tmdbID: tmdbID, kind: kind)
            guard let m, m.autoplayAllowed else { return }
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { withAnimation(.easeInOut(duration: 0.6)) { showVideo = true } }
        }
        .onDisappear { showVideo = false }
    }

    private var muteButton: some View {
        Button { muted.toggle() } label: {
            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .padding(10).background(.black.opacity(0.5), in: Circle()).foregroundStyle(.white)
        }
        .padding(.top, 60).padding(.trailing, Theme.Space.lg)
    }
}
```

- [ ] **Step 2: Use it in MovieDetail/ShowDetail**

In each, replace `.background(DetailBackdrop(path: store.backdropPath, posterFallback: item.posterPath))`
with:
```swift
        .background(AutoplayBackdrop(tmdbID: item.tmdbID, kind: <.movie | .show>,
                                    backdropPath: store.backdropPath, posterFallback: item.posterPath))
```
(`.movie` in MovieDetail, `.show` in ShowDetail.)

- [ ] **Step 3: Build + verify on sim** — open a detail, wait ~4s → backdrop fades to a muted
  trailer; tap the speaker → sound. Leave the screen → it stops. Screenshot.

- [ ] **Step 4: Commit**

```bash
git add Apps/SeretMobile/Detail/AutoplayBackdrop.swift Apps/SeretMobile/Detail/MovieDetail.swift Apps/SeretMobile/Detail/ShowDetail.swift
git commit -m "feat(ios): muted auto-play trailer on the detail backdrop (4s cross-fade + unmute)"
```

---

## Task 4: Settings toggle

**Files:** Modify `Apps/SeretMobile/Shell/SettingsView.swift`

- [ ] **Step 1: Add a section** binding to `session.trailerSettings.autoplayTrailers`:

```swift
            Section {
                Toggle("Autoplay trailers", isOn: Binding(
                    get: { session.trailerSettings.autoplayTrailers },
                    set: { session.trailerSettings.autoplayTrailers = $0 }))
                .tint(Theme.Palette.gold)
            } header: {
                Text("Trailers").foregroundStyle(Theme.Palette.gold)
            } footer: {
                Text("Play a muted trailer on a title's page automatically.")
                    .font(.footnote).foregroundStyle(Theme.Palette.textSecondary)
            }
            .listRowBackground(Theme.Palette.surface1)
```
(Place it among the existing `Form` sections.)

- [ ] **Step 2: Build + verify** the toggle appears and, when off, the backdrop no longer auto-plays.

- [ ] **Step 3: Commit**

```bash
git add Apps/SeretMobile/Shell/SettingsView.swift
git commit -m "feat(ios): Settings toggle for autoplay trailers"
```

---

## Self-Review Notes

- **Spec coverage (iOS):** in-app full-screen AVPlayer playback (Task 2) · muted auto-play backdrop
  + 4s cross-fade + unmute + teardown (Task 3) · Settings toggle (Task 4) · deep-link fallback
  (Task 2) · the empty-Group `.task` lesson reused (Task 2). tvOS = Slice 3.
- **Verification is on-sim** (AVPlayer plays the extracted URL — unlike the embed), the whole point.
- **Type consistency:** `TrailerModel.streamURL/youTubeKey/autoplayAllowed/prepare`,
  `session.makeTrailerModel()`, `session.trailerSettings.autoplayTrailers`, `InlineMutedTrailer`,
  `FullScreenTrailer`, `AutoplayBackdrop` — consistent.
