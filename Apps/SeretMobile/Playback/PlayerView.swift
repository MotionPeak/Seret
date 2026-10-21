import AVKit
import DebridCore
import DebridUI
import SwiftUI

/// The touch player: full-screen VLCKit video with the Balanced gesture set —
/// single tap toggles the controls, double-tapping the left/right half seeks ∓10s,
/// dragging the scrubber seeks. Reuses the shared `PlayerModel` + `VLCKitVideoPlayerEngine`.
struct PlayerView: View {
    @State private var model: PlayerModel
    @State private var engine: VLCKitVideoPlayerEngine
    /// The settings panel, and which of its sections it opens on (Subtitles / Audio / Speed pills).
    @State private var settingsFocus: PlayerSettingsSection?
    /// What is holding the transport up right now. Counted, not one flag: the episode strip, the
    /// panel and the route picker each hold and release on their own, and one releasing must not
    /// let the controls fade under another that is still open.
    @State private var holds: Set<ControlHold> = []
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize
    @State private var dragOffset: CGFloat = 0          // interactive pull-down-to-dismiss
    @State private var showsMidPlaySpinner = false      // see `midPlaySpinner`
    @Environment(\.scenePhase) private var scenePhase
    let backdropURL: URL?
    let pushSignal: LetterboxdPushSignal?
    let filmRating: FinishedFilmRating?
    /// Leave the player. An explicit closure (the presenter sets its item to nil) rather than
    /// @Environment(\.dismiss), which is unreliable from a fullScreenCover nested inside another.
    let onExit: () -> Void

    init(model: PlayerModel, engine: VLCKitVideoPlayerEngine, backdropURL: URL?,
         pushSignal: LetterboxdPushSignal? = nil, filmRating: FinishedFilmRating? = nil,
         settingsFocus: PlayerSettingsSection? = nil,
         onExit: @escaping () -> Void) {
        _model = State(initialValue: model)
        // A harness can open on the panel; the app never passes one.
        _settingsFocus = State(initialValue: settingsFocus)
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
                cornerClose
            // A cold open, as on tvOS — not "the playhead is at 0". While a resume travels,
            // `position` already holds the place being resumed, so a resumed play (and a Retry,
            // and a swap to a part-watched episode) lost its overlay: controls over a black screen
            // with live skip zones, whose double-tap cancelled the pending resume.
            case .buffering where model.isColdOpen:
                loadingOverlay("Buffering…")
                cornerClose
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
            midPlaySpinner
        }
        .animation(.easeOut(duration: 0.18), value: model.skipFeedback)
        .animation(.easeOut(duration: 0.2), value: showsMidPlaySpinner)
        .task(id: model.isBuffering) {
            guard model.isBuffering else { showsMidPlaySpinner = false; return }
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled { showsMidPlaySpinner = true }
        }
        // Pull down to exit: the whole player follows the finger and shrinks slightly, like other
        // fullscreen players. Released past the threshold it dismisses (in pullToDismiss).
        .scaleEffect(1 - min(max(dragOffset, 0), 240) / 1600)
        .offset(y: max(0, dragOffset))
        // Up Next sits above the bottom cluster — except on a landscape phone with the controls
        // up, where there is no room between the cluster and the centre circles: it moves under
        // the title instead (measured with -uiPreview upnext in both orientations).
        .overlay(alignment: .bottom) {
            if model.upNextVisible, !upNextOnTop, let next = model.nextEpisode {
                upNextCard(next)
                    .padding(.horizontal, 24)
                    // Above the scrub bar, the pills and the episode strip's peek with controls up.
                    .padding(.bottom, model.controlsVisible ? 190 : 28)
            }
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
        // The panel. On iPhone a sheet presented from HERE, the root: hung off the transport, any
        // reload that took the transport down (a silent reopen, Up Next advancing, a failure) took
        // the panel with it and left `settingsFocus` set. On iPad a popover on the tapped pill —
        // see `controlPills` for how that one is kept honest.
        .sheet(item: compactPanel) { focus in PlayerSettingsSheet(model: model, focus: focus) }
        // Held open while the panel is up, so the controls behind it never fade mid-choice.
        .onChange(of: settingsFocus, initial: true) { _, focus in setHold(.panel, focus != nil) }
        .onChange(of: holds) { _, now in model.holdControls(!now.isEmpty) }
        // A rotation or a split-view resize that changes which presentation the panel uses: close
        // it (which releases its hold) rather than leave the state pointing at the wrong one.
        .onChange(of: panelIsPopover) { _, _ in settingsFocus = nil }
        .animation(.easeInOut(duration: 0.2), value: model.controlsVisible)
        .animation(.easeInOut(duration: 0.25), value: model.upNextVisible)
        .animation(.easeInOut(duration: 0.2), value: model.autoSyncBanner)
        .onAppear { model.start(); OrientationGate.setPlayerActive(true) }
        .task(id: model.currentEpisode?.season) {
            if model.isEpisode { await model.loadSeasonEpisodes() }
        }
        .onChange(of: model.shouldDismiss) { _, done in if done { onExit() } }
        // Locked, switched away, a call: pause and keep the place.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            // The route list is gone once the app is; its "did end" may never arrive.
            setHold(.routePicker, false)
            Task { await model.appDidLeaveForeground() }
        }
        .onDisappear {
            // Closing the player ends every hold, whatever was open at the time.
            settingsFocus = nil
            holds.removeAll()
            model.holdControls(false)
            OrientationGate.setPlayerActive(false)
            Task { await model.teardown() }
        }
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

    /// A visible way out while the load overlay is up — it replaces the transport (and its close
    /// circle), and a link that never opens left only the undiscoverable pull-down for up to 30
    /// seconds. In the transport's own corner, so the exit never moves between loading and playing.
    private var cornerClose: some View {
        VStack {
            HStack {
                Spacer()
                GlassCircleButton(systemImage: "chevron.down", label: "Close Player", action: onExit)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func setHold(_ hold: ControlHold, _ on: Bool) {
        if on { holds.insert(hold) } else { holds.remove(hold) }
    }

    /// The panel is an iPad popover only when BOTH size classes are regular. Width alone is also
    /// regular on a Plus / Pro Max iPhone in landscape, where a 440pt-tall popover does not fit a
    /// ~430pt screen; there, as on every iPhone, the panel is the root sheet.
    private var panelIsPopover: Bool { hSize == .regular && vSize == .regular }

    /// A landscape phone with the controls up: no room between the bottom cluster and the centre
    /// circles, so Up Next joins the top bar's row (beside the title) — under it would sit in the
    /// slot the AutoSync / Letterboxd bars use.
    private var upNextOnTop: Bool { vSize == .compact && model.controlsVisible }

    /// `settingsFocus` as the iPhone sheet sees it — nothing on iPad, where the popover owns it.
    private var compactPanel: Binding<PlayerSettingsSection?> {
        Binding(get: { panelIsPopover ? nil : settingsFocus },
                set: { settingsFocus = $0 })
    }

    /// `settingsFocus` as one pill's iPad popover sees it.
    private func popoverBinding(_ section: PlayerSettingsSection) -> Binding<Bool> {
        Binding(get: { panelIsPopover && settingsFocus == section },
                set: { if !$0, settingsFocus == section { settingsFocus = nil } })
    }

    /// A small spinner over a picture that has stopped moving mid-film — libvlc's own buffering
    /// and the stall watch both raise `isBuffering`, and nothing on this player showed it once the
    /// first frame was up: the picture froze, the button still said pause. Held back a beat so a
    /// skip the stream cache answers at once never flashes it.
    ///
    /// …and over an episode swap. That is not a cold open — the viewer is watching, so the screen
    /// is not the full overlay's to take — but nothing is moving either, and asking for a rendered
    /// frame (which the swap's reload clears) left it showing nothing at all: the next episode
    /// looked like a dead tap. Everything that is not a cold open gets the spinner — except while
    /// `.preparing`, which shows the "Preparing…" overlay with a spinner of its own.
    @ViewBuilder private var midPlaySpinner: some View {
        if !model.isColdOpen && model.isBuffering && showsMidPlaySpinner && model.phase != .preparing {
            ProgressView().controlSize(.large).tint(Theme.Palette.focus)
                .padding(18).background(.black.opacity(0.35), in: Circle())
                .allowsHitTesting(false)
                .transition(.opacity)
        }
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
        .background(.black.opacity(0.25), in: Capsule())
        .seretGlass(in: Capsule(), interactive: false)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: forward ? .trailing : .leading)
        .padding(forward ? .trailing : .leading, 56)
        // A portrait phone with the controls up: below the centre circles, which span the width
        // there and sat under the badge. Landscape and iPad have room beside the circles, and
        // below them is the scrub bar — so the badge stays on the circles' row.
        .offset(y: model.controlsVisible && hSize == .compact && vSize == .regular ? 92 : 0)
    }

    /// Netflix-style "Up Next" bar near content-end: a countdown that auto-advances, Play Now to
    /// skip the wait, and Dismiss to keep watching (e.g. the credits).
    private func upNextCard(_ next: Episode) -> some View {
        HStack(spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Up Next").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                Text("S\(next.season)\u{00B7}E\(next.number)  \u{00B7}  Playing in \(model.upNextSecondsRemaining)s")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(2)
            }
            Spacer(minLength: Theme.Space.md)
            Button("Dismiss") { model.dismissUpNext() }
                .font(.subheadline).foregroundStyle(.white.opacity(0.85))
            Button { model.playNextNow() } label: {
                Label("Play Now", systemImage: "play.fill")
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Theme.Palette.focus, in: Capsule())
                    .foregroundStyle(Theme.Palette.onFocus)
                    .contentShape(Capsule())
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .seretGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false)
    }

    /// Three independently-anchored layers so expanding the episode strip only grows the bottom
    /// cluster upward — it never yanks the centered play controls or the top bar around (the old
    /// single-VStack shared its Spacers with the strip, which made the whole thing jump).
    ///
    /// The look is g6: title and year top-left, glass ⏪ ⏯ ⏩ in the middle, a thin white scrub bar
    /// between the times, and a row of glass pills — Subtitles, Audio, Speed, AirPlay — under it.
    private var transport: some View {
        ZStack {
            VStack(spacing: 0) { topBar; Spacer(minLength: 0) }              // top bar pinned to top
            centerControls                                                  // stays dead-center
            VStack(spacing: 14) {
                Spacer(minLength: 0)
                scrubber
                controlPills
                EpisodePeekStrip(model: model, onHold: { setHold(.strip, $0) })
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .foregroundStyle(.white)
    }

    private var topBar: some View {
        let lines = model.titleLines
        return HStack(alignment: .top, spacing: Theme.Space.lg) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lines.title)
                    .font(.system(size: 26, weight: .bold))
                    .lineLimit(1).minimumScaleFactor(0.7)
                if !lines.subtitle.isEmpty {
                    Text(lines.subtitle)
                        .font(.system(size: 15, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
            }
            .shadow(color: .black.opacity(0.45), radius: 8)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.Space.md)
            // A landscape phone: Up Next rides in this row (see `upNextOnTop`).
            if upNextOnTop, model.upNextVisible, let next = model.nextEpisode {
                upNextCard(next)
                    .frame(maxWidth: 440)
                    .layoutPriority(1)
                    .transition(.opacity)
            }
            GlassCircleButton(systemImage: "chevron.down", label: "Close Player", action: onExit)
        }
    }

    private var centerControls: some View {
        GlassGroup(spacing: 10) {
            HStack(spacing: 36) {
                GlassCircleButton(systemImage: "gobackward.10", label: "Back 10 Seconds", size: 62) {
                    model.skip(-10); model.showControls()
                }
                GlassCircleButton(systemImage: model.phase == .playing ? "pause.fill" : "play.fill",
                                  label: model.phase == .playing ? "Pause" : "Play", size: 80) {
                    model.togglePlayPause()
                }
                // Dead to touch while a skip burst runs: the burst reveals the controls on its first
                // skip, and the next taps on the right half landed here and paused the film. ⏪/⏩
                // stay live — a tap on them during the burst is another skip, which is what was meant.
                .allowsHitTesting(model.skipFeedback == nil)
                GlassCircleButton(systemImage: "goforward.10", label: "Forward 10 Seconds", size: 62) {
                    model.skip(10); model.showControls()
                }
            }
        }
    }

    private var scrubber: some View {
        let shown = model.isScrubbing ? model.scrubTarget : model.position
        let frac = model.duration > 0 ? min(1, max(0, shown / model.duration)) : 0
        let remaining = max(0, model.duration - shown)
        return HStack(spacing: 14) {
            Text(Timecode.format(shown))
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .accessibilityHidden(true)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.track).frame(height: 4)
                    Capsule().fill(Theme.Palette.focus).frame(width: geo.size.width * frac, height: 4)
                    Circle().fill(.white)
                        .frame(width: model.isScrubbing ? 22 : 16, height: model.isScrubbing ? 22 : 16)
                        .shadow(color: .black.opacity(0.3), radius: 3)
                        .offset(x: min(geo.size.width - 16, max(-2, geo.size.width * frac - 8)))
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(scrubGesture(width: geo.size.width))
            }
            .frame(height: 32)
            // One adjustable control for VoiceOver: swipe up / down moves ten seconds, the value
            // reads where the film is. It was a bare drag area before (audit).
            .accessibilityElement()
            .accessibilityLabel("Playback Position")
            .accessibilityValue("\(Timecode.format(shown)) of \(Timecode.format(model.duration))")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: model.skip(10); model.showControls()
                case .decrement: model.skip(-10); model.showControls()
                @unknown default: break
                }
            }
            Text("-" + Timecode.format(remaining))
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .accessibilityHidden(true)
        }
    }

    /// Subtitles · Audio · Speed · AirPlay. The first three open the playback panel on their own
    /// section — a sheet on iPhone (from the root), a popover on the tapped pill on iPad. Speed is
    /// the panel too, not a menu: a menu's open/closed state is invisible to us, so it could not
    /// hold the controls, and the auto-hide took the transport down under it. Icons alone on a
    /// portrait iPhone, where the words do not fit.
    private var controlPills: some View {
        let titles = !(hSize == .compact && vSize == .regular)
        return GlassGroup(spacing: 8) {
            HStack(spacing: 12) {
                panelPill(.subtitles, title: "Subtitles", systemImage: "captions.bubble",
                          accessibility: "Subtitles", titles: titles)
                panelPill(.audio, title: "Audio", systemImage: "speaker.wave.2",
                          accessibility: "Audio and Volume", titles: titles)
                panelPill(.speed, title: Self.speedLabel(model.playbackSpeed), systemImage: nil,
                          accessibility: "Playback Speed", titles: true)
                    .accessibilityValue(Self.speedLabel(model.playbackSpeed))
                // Sound only: VLCKit draws the picture itself, so AirPlay cannot take the video —
                // what this does is send the SOUND to AirPods, a HomePod or an AirPlay speaker.
                // The picker shows the audio-route glyph, and says so to VoiceOver.
                AirPlayAudioPicker(onPresenting: { setHold(.routePicker, $0) })
                    .frame(width: 46, height: 46)
                    .padding(.horizontal, 4)
                    .seretGlass(in: Capsule())
                    .accessibilityLabel("Sound Output")
                    .accessibilityHint("Plays the sound on AirPods, a HomePod or an AirPlay speaker. The picture stays here.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // An iPad popover lives on its pill: when the transport goes (a reload, a failure) the
        // popover goes with it, and the state must not outlive it.
        // The route picker lives here too, and its list's "did end" is not guaranteed once its
        // view is gone.
        .onDisappear {
            if panelIsPopover { settingsFocus = nil }
            setHold(.routePicker, false)
        }
    }

    private func panelPill(_ section: PlayerSettingsSection, title: String, systemImage: String?,
                           accessibility: String, titles: Bool) -> some View {
        Button { settingsFocus = section } label: {
            PlayerPillLabel(title: title, systemImage: systemImage, showsTitle: titles)
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel(accessibility)
        .popover(isPresented: popoverBinding(section), arrowEdge: .bottom) {
            PlayerSettingsSheet(model: model, focus: section)
                .frame(minWidth: 380, idealWidth: 440, minHeight: 440, idealHeight: 620)
        }
    }

    static func speedLabel(_ speed: Double) -> String {
        speed == 1 ? "1×" : String(format: "%g×", speed)
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
                    .foregroundStyle(Theme.Palette.focus)
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
                            .foregroundStyle(shown >= value ? Theme.Palette.focus
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
                .foregroundStyle(Theme.Palette.focus)
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
                            Capsule().fill(Theme.Palette.focus)
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
        .overlay(Capsule().strokeBorder(Theme.Palette.hairline))
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
        case .measuring: Theme.Palette.textPrimary
        case .synced:    .green
        case .failed:    .orange
        }
    }
}

/// A pill's face in the player: glass capsule, white icon and title (g6).
struct PlayerPillLabel: View {
    let title: String
    let systemImage: String?
    var showsTitle = true

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 16, weight: .semibold))
            }
            if showsTitle || systemImage == nil {
                Text(title).font(.system(size: 16, weight: .semibold)).monospacedDigit()
            }
        }
        .foregroundStyle(.white)
        .lineLimit(1)
        .fixedSize()
        .frame(minWidth: 22, minHeight: 22)
        .padding(.vertical, 12).padding(.horizontal, showsTitle ? 20 : 14)
        .contentShape(Capsule())
        .seretGlass(in: Capsule())
    }
}

/// The system route picker, white on clear, preferring audio routes — see where it is used.
/// `onPresenting` reports the route list opening and closing, so the transport holds under it.
struct AirPlayAudioPicker: UIViewRepresentable {
    var onPresenting: (Bool) -> Void = { _ in }

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.tintColor = .white
        view.activeTintColor = .white
        view.backgroundColor = .clear
        view.delegate = context.coordinator
        // Its own label says "AirPlay", which promises the picture; this only moves the sound.
        view.accessibilityLabel = "Sound Output"
        view.accessibilityHint = "Plays the sound on AirPods, a HomePod or an AirPlay speaker. The picture stays here."
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        context.coordinator.onPresenting = onPresenting
        // VoiceOver reads the picker's inner button, which calls itself "AirPlay" whatever the
        // view's own label says — and AirPlay promises the picture, when this only moves the sound.
        for case let button as UIButton in uiView.subviews {
            button.accessibilityLabel = "Sound Output"
            button.accessibilityHint = "Plays the sound on AirPods, a HomePod or an AirPlay speaker. The picture stays here."
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPresenting: onPresenting) }

    /// Main-actor isolated: the delegate callbacks change SwiftUI state (the player's holds).
    @MainActor
    final class Coordinator: NSObject, AVRoutePickerViewDelegate {
        var onPresenting: (Bool) -> Void
        init(onPresenting: @escaping (Bool) -> Void) { self.onPresenting = onPresenting }

        // AVKit calls these on the main thread but its protocol is not main-actor isolated, so
        // they are nonisolated and step onto the main actor they are already on.
        nonisolated func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            MainActor.assumeIsolated { onPresenting(true) }
        }
        nonisolated func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            MainActor.assumeIsolated { onPresenting(false) }
        }
    }
}

/// Why the transport is being held up — see `PlayerView.holds`.
enum ControlHold: Hashable {
    case panel, strip, routePicker
}
