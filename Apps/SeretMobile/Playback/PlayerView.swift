import DebridCore
import DebridUI
import SwiftUI

/// The touch player: full-screen VLCKit video with the Balanced gesture set —
/// single tap toggles the controls, double-tapping the left/right half seeks ∓10s,
/// dragging the scrubber seeks. Reuses the shared `PlayerModel` + `VLCKitVideoPlayerEngine`.
struct PlayerView: View {
    @State private var model: PlayerModel
    @State private var engine: VLCKitVideoPlayerEngine
    @State private var showSettings = false
    @State private var dragOffset: CGFloat = 0          // interactive pull-down-to-dismiss
    let backdropURL: URL?
    /// Leave the player. An explicit closure (the presenter sets its item to nil) rather than
    /// @Environment(\.dismiss), which is unreliable from a fullScreenCover nested inside another.
    let onExit: () -> Void

    init(model: PlayerModel, engine: VLCKitVideoPlayerEngine, backdropURL: URL?, onExit: @escaping () -> Void) {
        _model = State(initialValue: model)
        _engine = State(initialValue: engine)
        self.backdropURL = backdropURL
        self.onExit = onExit
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VLCVideoView(videoView: engine.videoView).ignoresSafeArea()

            switch model.phase {
            case .preparing:
                LoadingOverlay(caption: "Preparing…", title: model.label, backdropURL: backdropURL)
            case .buffering where model.position == 0:
                LoadingOverlay(caption: "Buffering…", title: model.label, backdropURL: backdropURL)
            case .failed(let reason):
                ErrorOverlay(reason: reason, canTryAnother: model.canTryAnotherVersion, backdropURL: backdropURL,
                             onRetry: { model.retry() }, onTryAnother: { model.tryAnotherVersion() },
                             onBack: { onExit() })
            default:
                gestureLayer                                  // base: tap = toggle, double-tap = ∓10s
                if model.controlsVisible {
                    scrim.allowsHitTesting(false)             // legibility only — never blocks the gestures
                    transport                                 // floating controls (only buttons capture taps)
                }
            }

            if let fb = model.skipFeedback {                  // ride above controls; never eat a tap
                skipIndicator(fb)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.skipFeedback)
        // Pull down to exit: the whole player follows the finger and shrinks slightly, like other
        // fullscreen players. Released past the threshold it dismisses (in pullToDismiss).
        .scaleEffect(1 - min(max(dragOffset, 0), 240) / 1600)
        .offset(y: max(0, dragOffset))
        .overlay(alignment: .bottom) {
            if model.upNextVisible, let next = model.nextEpisode { upNextBar(next) }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $showSettings) { PlayerSettingsSheet(model: model) }
        .animation(.easeInOut(duration: 0.2), value: model.controlsVisible)
        .animation(.easeInOut(duration: 0.25), value: model.upNextVisible)
        .onAppear { model.start() }
        .task(id: model.currentEpisode?.season) {
            if model.isEpisode { await model.loadSeasonEpisodes() }
        }
        .onChange(of: model.shouldDismiss) { _, done in if done { onExit() } }
        .onDisappear { Task { await model.teardown() } }
    }

    // MARK: - Gestures (Balanced)

    private var gestureLayer: some View {
        HStack(spacing: 0) {
            tapZone(skip: -10)
            tapZone(skip: 10)
        }
        .ignoresSafeArea()
        .simultaneousGesture(pullToDismiss)   // vertical pull-down on the video area exits the movie
    }

    /// Pull the player down to exit, like other fullscreen video apps. Vertical-down drags only, so
    /// it never fights the horizontal scrubber (which sits on top and wins at its own location).
    /// Release past the threshold dismisses; otherwise it springs back.
    private var pullToDismiss: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                if value.translation.height > 0, value.translation.height > abs(value.translation.width) {
                    dragOffset = value.translation.height        // follow the finger 1:1
                }
            }
            .onEnded { value in
                if value.translation.height > 140 { onExit() }
                else { withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { dragOffset = 0 } }
            }
    }

    private func tapZone(skip seconds: Double) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { model.skip(seconds); model.showControls() }
            .onTapGesture(count: 1) { model.toggleControls() }
    }

    // MARK: - Transport

    private var scrim: some View {
        LinearGradient(colors: [.black.opacity(0.55), .clear, .black.opacity(0.65)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    /// YouTube-style seek badge on the half you double-tapped, showing the burst's accumulated jump
    /// (10s → 20s → 30s → 1:10…). It stays put and the number rolls in place as you keep tapping,
    /// rather than re-popping each tap.
    private func skipIndicator(_ fb: PlayerModel.SkipFeedback) -> some View {
        let forward = fb.seconds > 0
        return HStack(spacing: 8) {
            Image(systemName: forward ? "goforward" : "gobackward").font(.system(size: 26, weight: .semibold))
            Text(fb.label)
                .font(.system(size: 20, weight: .bold)).monospacedDigit()
                .contentTransition(.numericText(value: abs(fb.seconds)))   // digits roll, not pop
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22).padding(.vertical, 16)
        .background(.black.opacity(0.55), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: forward ? .trailing : .leading)
        .padding(forward ? .trailing : .leading, 56)
    }

    /// Netflix-style "Up Next" bar near content-end: a countdown that auto-advances, Play Now to
    /// skip the wait, and Dismiss to keep watching (e.g. the credits).
    private func upNextBar(_ next: Episode) -> some View {
        HStack(spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Up Next").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                Text("S\(next.season)\u{00B7}E\(next.number)  \u{00B7}  Playing in \(model.upNextSecondsRemaining)s")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
            }
            Spacer(minLength: Theme.Space.md)
            Button("Dismiss") { model.dismissUpNext() }
                .font(.subheadline).foregroundStyle(.white.opacity(0.85))
            Button { model.playNextNow() } label: {
                Label("Play Now", systemImage: "play.fill")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Theme.Palette.gold, in: Capsule())
                    .foregroundStyle(.black)
                    .contentShape(Capsule())
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12)))
        .padding(.horizontal, 24)
        .padding(.bottom, 92)        // sit above the scrub bar when controls are up
    }

    /// Three independently-anchored layers so expanding the episode strip only grows the bottom
    /// cluster upward — it never yanks the centered play controls or the top bar around (the old
    /// single-VStack shared its Spacers with the strip, which made the whole thing jump).
    private var transport: some View {
        ZStack {
            VStack(spacing: 0) { topBar; Spacer(minLength: 0) }              // top bar pinned to top
            centerControls                                                  // stays dead-center
            VStack(spacing: 0) { Spacer(minLength: 0); scrubber; EpisodePeekStrip(model: model) }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .foregroundStyle(.white)
    }

    private var topBar: some View {
        HStack {
            Button { onExit() } label: {
                Image(systemName: "chevron.down").font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)            // generous hit target — taps can't fall
                    .contentShape(Rectangle())               // through to the gesture layer below
            }
            Spacer()
            Text(model.label).font(.headline).lineLimit(1)
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3").font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
    }

    private var centerControls: some View {
        HStack(spacing: 48) {
            Button { model.skip(-10); model.showControls() } label: {
                Image(systemName: "gobackward.10").font(.system(size: 34))
            }
            Button { model.togglePlayPause() } label: {
                Image(systemName: model.phase == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 50))
            }
            Button { model.skip(10); model.showControls() } label: {
                Image(systemName: "goforward.10").font(.system(size: 34))
            }
        }
    }

    private var scrubber: some View {
        let shown = model.isScrubbing ? model.scrubTarget : model.position
        let frac = model.duration > 0 ? min(1, max(0, shown / model.duration)) : 0
        return VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25)).frame(height: 4)
                    Capsule().fill(Theme.Palette.gold).frame(width: geo.size.width * frac, height: 4)
                        .goldGlow(6, opacity: 0.7)
                    Circle().fill(.white)
                        .frame(width: model.isScrubbing ? 20 : 14, height: model.isScrubbing ? 20 : 14)
                        .offset(x: min(geo.size.width - 14, max(-2, geo.size.width * frac - 7)))
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(scrubGesture(width: geo.size.width))
            }
            .frame(height: 28)
            HStack {
                Text(Timecode.format(shown)).font(.caption.monospacedDigit())
                Spacer()
                Text("-" + Timecode.format(max(0, model.duration - shown))).font(.caption.monospacedDigit())
            }
        }
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !model.isScrubbing { model.beginScrub() }
                guard model.duration > 0, width > 0 else { return }
                let target = Double(max(0, min(1, value.location.x / width))) * model.duration
                model.updateScrub(by: target - model.scrubTarget)   // delta API → absolute target
            }
            .onEnded { _ in model.commitScrub() }
    }
}
