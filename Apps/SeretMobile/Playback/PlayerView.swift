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
    let pushSignal: LetterboxdPushSignal?
    let filmRating: FinishedFilmRating?
    /// Leave the player. An explicit closure (the presenter sets its item to nil) rather than
    /// @Environment(\.dismiss), which is unreliable from a fullScreenCover nested inside another.
    let onExit: () -> Void

    init(model: PlayerModel, engine: VLCKitVideoPlayerEngine, backdropURL: URL?,
         pushSignal: LetterboxdPushSignal? = nil, filmRating: FinishedFilmRating? = nil,
         onExit: @escaping () -> Void) {
        _model = State(initialValue: model)
        _engine = State(initialValue: engine)
        self.backdropURL = backdropURL
        self.pushSignal = pushSignal
        self.filmRating = filmRating
        self.onExit = onExit
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoSurface(videoView: engine.videoView).ignoresSafeArea()

            switch model.phase {
            case .preparing:
                loadingOverlay("Preparing…")
            case .buffering where model.position == 0:
                loadingOverlay("Buffering…")
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
        // A sync runs for minutes while the film keeps playing, so it reports from up here rather
        // than from the sheet that started it. Below the transport's own top row when the controls
        // are up, at the top of the picture when they are not.
        .overlay(alignment: .top) {
            if let banner = model.autoSyncBanner {
                AutoSyncBar(banner: banner)
                    .padding(.top, model.controlsVisible ? 74 : 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // Below the sync banner's slot, so the two can never sit on top of each other.
        .letterboxdDiaryBar(signal: pushSignal, contentKey: model.contentKey) { state in
            switch state {
            case .logged:
                LetterboxdLoggedBar()
                    .padding(.top, model.controlsVisible ? 74 : 14)
            case .askingRating(let tmdbID, let current):
                LetterboxdRatingBar(current: current) { value in
                    Task { await filmRating?.rate(value, contentKey: model.contentKey,
                                                  tmdbID: tmdbID) }
                } onDismiss: {
                    Task { await filmRating?.dismiss(tmdbID: tmdbID) }
                }
                .padding(.top, model.controlsVisible ? 74 : 14)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $showSettings) { PlayerSettingsSheet(model: model) }
        .animation(.easeInOut(duration: 0.2), value: model.controlsVisible)
        .animation(.easeInOut(duration: 0.25), value: model.upNextVisible)
        .animation(.easeInOut(duration: 0.2), value: model.autoSyncBanner)
        .onAppear { model.start(); OrientationGate.setPlayerActive(true) }
        .task(id: model.currentEpisode?.season) {
            if model.isEpisode { await model.loadSeasonEpisodes() }
        }
        .onChange(of: model.shouldDismiss) { _, done in if done { onExit() } }
        .onDisappear { OrientationGate.setPlayerActive(false); Task { await model.teardown() } }
    }

    // MARK: - Gestures (Balanced)

    /// The load overlay REPLACES the gesture layer, so while it is up both of the player's ways out
    /// — the back chevron and the pull-down — are off screen. A stream slow to start, or a dead link
    /// (which takes the 30s watchdog to declare), therefore trapped the viewer on a spinner. Keeping
    /// the pull-down alive here is why Menu always works on the tvOS side, and it changes nothing on
    /// screen until the viewer actually drags.
    private func loadingOverlay(_ caption: String) -> some View {
        LoadingOverlay(caption: caption, title: model.label, backdropURL: backdropURL)
            .contentShape(Rectangle())
            .gesture(pullToDismiss)
    }

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
                if isDownward(value.translation) {
                    dragOffset = value.translation.height        // follow the finger 1:1
                }
            }
            .onEnded { value in
                // The SAME dominance test the drag used. Without it a long, mostly-horizontal swipe
                // that drifted 140pt down exited the film — the player never moved on the way (the
                // drag test rejected it), so it vanished with no warning at all.
                if isDownward(value.translation), value.translation.height > 140 { onExit() }
                else { withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { dragOffset = 0 } }
            }
    }

    /// A deliberate downward pull, not a horizontal swipe that happened to drift.
    private func isDownward(_ t: CGSize) -> Bool { t.height > 0 && t.height > abs(t.width) }

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

/// The strip across the top while a subtitle sync runs, and for a few seconds after it ends.
///
/// It exists because the measurement takes minutes — reading the film's audio means downloading it
/// — so the sheet closes, the film keeps playing, and the work reports from here. Nothing in it is
/// tappable, so it can never swallow a tap meant for the gesture layer underneath.
///
/// The track sits UNDER the text rather than beside it, and the text wraps rather than truncating.
/// Both were measured, not guessed: side by side on the widest iPhone made, the text and the track
/// fought for the width and "Syncing subtitles · about 3 min left" broke across two lines with a
/// gap beside it — and truncating instead would have cut the one message that tells the viewer what
/// to do when a sync fails.
/// "Logged to Letterboxd", for three seconds, when an entry actually lands.
///
/// Nothing appears for a failed write: it is not actionable while a film is playing, and the
/// Letterboxd settings card carries it.
/// The post-credits prompt: ten taps, and a way out.
///
/// Same slot as the logged confirmation, because it is the same bar at an earlier moment — the
/// entry is already queued, and this is what it is waiting for.
struct LetterboxdRatingBar: View {
    let current: Int?
    let onRate: (Int?) -> Void
    let onDismiss: () -> Void

    private var shown: Int { current ?? 0 }

    var body: some View {
        VStack(spacing: 8) {
            // No Spacer: one would make the row — and so the whole bar — fill the width, which
            // over a film in landscape is a band across the picture rather than a prompt.
            HStack(spacing: 10) {
                Text(shown > 0 ? "RATE IT · \(shown)/10" : "RATE IT?")
                    .font(.system(size: 11, weight: .bold)).kerning(1.2)
                    .foregroundStyle(SeretPalette.gold)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Log it without a rating")
            }

            HStack(spacing: 2) {
                ForEach(1...10, id: \.self) { value in
                    Button {
                        // Tapping the current rating again clears it, exactly as the title page
                        // row behaves — otherwise there is no way to undo a mis-tap here.
                        onRate(current == value ? nil : value)
                    } label: {
                        Image(systemName: shown >= value ? "star.fill" : "star")
                            .font(.system(size: 15))
                            .foregroundStyle(shown >= value ? SeretPalette.gold
                                                            : .white.opacity(0.45))
                            // A 15pt glyph is not a tap target; ten of them side by side is a
                            // row of near-misses without this.
                            .frame(width: 30, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rate \(value) out of 10")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12)))
    }
}

struct LetterboxdLoggedBar: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(SeretPalette.gold)
            Text("Logged to Letterboxd")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.black.opacity(0.62), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
    }
}

struct AutoSyncBar: View {
    let banner: PlayerModel.AutoSyncBanner

    var body: some View {
        HStack(alignment: banner.fraction == nil ? .center : .top, spacing: 9) {
            Image(systemName: glyph)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .padding(.top, banner.fraction == nil ? 0 : 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(banner.text)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let fraction = banner.fraction {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.22))
                            // A floor, so the bar reads as started rather than as broken while the
                            // first seconds of audio are still arriving.
                            Capsule().fill(Theme.Palette.goldGradient)
                                .frame(width: max(5, geo.size.width * fraction))
                        }
                    }
                    .frame(height: 4)
                    .animation(.easeOut(duration: 0.9), value: fraction)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.black.opacity(0.74), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.Palette.gold.opacity(0.22)))
        .padding(.horizontal, 20)
        .allowsHitTesting(false)
    }

    private var glyph: String {
        switch banner.mood {
        case .measuring: "waveform"
        case .synced:    "checkmark.circle.fill"
        case .failed:    "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch banner.mood {
        case .measuring: Theme.Palette.gold
        case .synced:    .green
        case .failed:    .orange
        }
    }
}
