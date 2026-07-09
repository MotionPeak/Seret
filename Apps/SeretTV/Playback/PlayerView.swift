import SwiftUI
import DebridUI
import DebridCore

/// Which player control currently owns focus. `.stage` is the invisible full-screen surface the
/// player rests on while watching; the rest are the on-screen transport buttons that appear with the
/// scrub bar. Only ONE set is focusable at a time (see `controlsMode`) so directional input never
/// races between "skip" and "move focus to a button".
enum PlayerFocus: Hashable { case stage, back, playPause, forward, episodes }

struct PlayerView: View {
    @State private var model: PlayerModel
    @State private var engine: VLCKitVideoPlayerEngine
    @State private var showSettings = false
    @State private var showEpisodes = false
    /// false → the invisible stage owns focus (watching: side-clicks skip, up reveals controls);
    /// true → the on-screen transport buttons own focus (navigate + click to skip / play / episodes).
    @State private var controlsMode = false
    @FocusState private var focus: PlayerFocus?
    @Environment(\.dismiss) private var dismiss
    let backdropURL: URL?

    init(model: PlayerModel, engine: VLCKitVideoPlayerEngine, backdropURL: URL?) {
        _model = State(initialValue: model)
        _engine = State(initialValue: engine)
        self.backdropURL = backdropURL
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()                      // black backing for the open transition
            VLCVideoView(videoView: engine.videoView).ignoresSafeArea()

            // Full-screen loading until the first frame is actually on screen — it never hides over
            // a still-black picture. After that, a seek/rebuffer keeps the video up and surfaces only
            // a small inline hint under the scrub bar instead of dimming the whole screen.
            if case .failed(let reason) = model.phase {
                ErrorOverlay(reason: reason, canTryAnother: model.canTryAnotherVersion, backdropURL: backdropURL,
                             onRetry: { model.retry() }, onTryAnother: { model.tryAnotherVersion() },
                             onBack: { dismiss() })
            } else if !model.hasRenderedFrame {
                LoadingOverlay(caption: model.phase == .preparing ? "Preparing…" : "Buffering…",
                               title: model.label, backdropURL: backdropURL)
            } else {
                // The invisible focus stage owns the remote while watching. `.onMoveCommand` is the
                // RELIABLE directional channel on real hardware: it's the focus engine's own signal,
                // unlike raw `.leftArrow`/`.rightArrow` UIPresses, which the focus engine swallows
                // before they ever reach a UIView on 2nd-gen Siri remotes (why side-clicks did nothing).
                //   • left / right  → skip ∓10s (a burst / swipe repeats → the badge accumulates)
                //   • up            → reveal the scrub bar + hand focus to the transport buttons
                //   • down          → episodes (a show, bar up) or the settings panel
                //   • click(.select)→ play / pause
                Color.clear
                    .contentShape(Rectangle())
                    .focusable(!showSettings && !showEpisodes && !controlsMode)
                    .focused($focus, equals: .stage)
                    .onMoveCommand { direction in
                        switch direction {
                        case .left:  model.skip(-10); model.revealScrubBar()
                        case .right: model.skip(10);  model.revealScrubBar()
                        case .up:    enterControls()
                        case .down:  openSettingsOrEpisodes()
                        default: break
                        }
                    }
                    .onTapGesture { model.togglePlayPause() }   // clickpad center press
                    .ignoresSafeArea()

                // One bottom-anchored column: transport buttons + thin scrub bar on top, the episode
                // strip beneath. Stacking them means the bar AUTOMATICALLY rides up as the strip grows.
                PlayerBottomBar(model: model, showEpisodes: $showEpisodes, controlsMode: controlsMode,
                                focus: $focus,
                                onSkip: { model.skip($0); model.revealScrubBar() },
                                onTogglePlay: { model.togglePlayPause() },
                                onEpisodes: { openEpisodes() })
            }

            if showSettings {
                SettingsPanel(model: model, onClose: { showSettings = false })
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let fb = model.skipFeedback {          // ride above everything; never eat remote input
                skipIndicator(fb)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    .allowsHitTesting(false)
            }

            if model.upNextVisible, let next = model.nextEpisode {
                UpNextBar(model: model, next: next)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .defaultFocus($focus, .stage)
        .animation(.easeInOut(duration: 0.25), value: showSettings)
        .animation(.easeInOut(duration: 0.25), value: showEpisodes)
        .animation(.easeInOut(duration: 0.2), value: controlsMode)
        .animation(.easeInOut(duration: 0.25), value: model.upNextVisible)
        .animation(.easeOut(duration: 0.18), value: model.skipFeedback)
        .onPlayPauseCommand { model.togglePlayPause() }
        .onExitCommand {
            if model.upNextVisible { model.dismissUpNext() }   // Menu keeps watching (credits)
            else if showSettings { showSettings = false }
            else if showEpisodes { showEpisodes = false }
            else if controlsMode { exitControls() }            // Menu backs out of the transport
            else { dismiss() }
        }
        .onAppear {
            model.start()
            model.revealScrubBar()           // show the bar right away on open (sticky 5s)
        }
        .task(id: model.currentEpisode?.season) {
            if model.isEpisode { await model.loadSeasonEpisodes() }   // so the peek has thumbnails
        }
        // A closing panel hands focus back to the invisible stage so the remote keeps working.
        .onChange(of: showSettings) { _, open in if !open { exitControls() } }
        .onChange(of: showEpisodes) { _, open in if !open { exitControls() } }
        .onChange(of: model.shouldDismiss) { _, dismissNow in if dismissNow { dismiss() } }
        .onDisappear { Task { await model.teardown() } }
    }

    // MARK: - Control-focus transitions

    /// Reveal the scrub bar and move focus onto the transport buttons (Play highlighted). Entered by a
    /// d-pad UP; left/right then navigates the buttons, Menu backs out. Kept as a discrete mode so a
    /// left/right SKIP burst on the stage never accidentally slides focus onto a button mid-accumulate.
    private func enterControls() {
        model.revealScrubBar()
        controlsMode = true
        DispatchQueue.main.async { focus = .playPause }   // one tick so the buttons exist to receive it
    }

    private func exitControls() {
        controlsMode = false
        DispatchQueue.main.async { focus = .stage }
    }

    /// Down from the stage: collapse the episode strip if it's open, else open the settings panel.
    private func openSettingsOrEpisodes() {
        if showEpisodes { showEpisodes = false }
        else { showSettings = true }
    }

    /// The Episodes transport button (shows only): lift the full selectable strip.
    private func openEpisodes() {
        guard model.isEpisode, !model.seasonEpisodes.isEmpty else { return }
        showEpisodes = true
        Task { await model.loadSeasonEpisodes() }
    }

    /// The accumulating ±seconds badge on the side you skipped toward (10s → 20s → 1:10…). Sized for
    /// the 10-foot UI; the number rolls in place via `.numericText`. Driven by the shared
    /// `PlayerModel.skipFeedback` — the same state the iPad badge uses.
    private func skipIndicator(_ fb: PlayerModel.SkipFeedback) -> some View {
        let forward = fb.seconds > 0
        return HStack(spacing: 12) {
            Image(systemName: forward ? "goforward" : "gobackward")
                .font(.system(size: 44, weight: .semibold))
            Text(fb.label)
                .font(.system(size: 34, weight: .bold)).monospacedDigit()
                .contentTransition(.numericText(value: abs(fb.seconds)))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 36).padding(.vertical, 26)
        .background(.black.opacity(0.55), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: forward ? .trailing : .leading)
        .padding(forward ? .trailing : .leading, 120)
    }
}

/// A focusable circular transport button (skip / play-pause / episodes). Manual focus styling —
/// reading `focus.wrappedValue` — because a plain tvOS Button gives icon buttons almost no focus
/// affordance at 10 feet.
private struct TransportButton: View {
    let system: String
    var focus: FocusState<PlayerFocus?>.Binding
    let tag: PlayerFocus
    let action: () -> Void

    private var isFocused: Bool { focus.wrappedValue == tag }

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 34, weight: .semibold))
                .frame(width: 84, height: 84)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(.white.opacity(isFocused ? 0.30 : 0.14), in: Circle())
        .overlay(Circle().strokeBorder(.white.opacity(isFocused ? 0.9 : 0.15),
                                       lineWidth: isFocused ? 3 : 1))
        .scaleEffect(isFocused ? 1.12 : 1.0)
        .focused(focus, equals: tag)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

/// Netflix-style "Up Next" bar near content-end. Seeds focus to "Play Now" so the remote acts on
/// it; the countdown auto-advances, and Menu (handled by the player) or Dismiss keeps watching.
private struct UpNextBar: View {
    @Bindable var model: PlayerModel
    let next: Episode
    @FocusState private var playNowFocused: Bool

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 28) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Up Next").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                    Text("S\(next.season)\u{00B7}E\(next.number)  \u{00B7}  Playing in \(model.upNextSecondsRemaining)s")
                        .font(.title3.weight(.semibold))
                }
                Spacer()
                Button("Dismiss") { model.dismissUpNext() }
                Button { model.playNextNow() } label: {
                    Label("Play Now", systemImage: "play.fill")
                }
                .focused($playNowFocused)
            }
            .padding(36)
            .background(RoundedRectangle(cornerRadius: 20).fill(.black.opacity(0.85))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.10))))
            .padding(.horizontal, 80)
            .padding(.bottom, 60)
        }
        .onAppear { playNowFocused = true }
    }
}

/// The bottom-anchored player cluster: transport buttons + scrub bar on TOP, episode strip BENEATH.
/// Because they're stacked in one bottom-pinned column, the bar automatically rides up as the strip
/// grows — it can never overlap the bar or float to the middle of the screen.
private struct PlayerBottomBar: View {
    @Bindable var model: PlayerModel
    @Binding var showEpisodes: Bool
    let controlsMode: Bool
    var focus: FocusState<PlayerFocus?>.Binding
    let onSkip: (Double) -> Void
    let onTogglePlay: () -> Void
    let onEpisodes: () -> Void

    // The bar is up while watching-controls are engaged, mid-buffer, or the strip is open.
    private var barShown: Bool { model.scrubBarVisible || model.isBuffering || showEpisodes || controlsMode }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            if controlsMode {
                HStack(spacing: 44) {
                    TransportButton(system: "gobackward.10", focus: focus, tag: .back) { onSkip(-10) }
                    TransportButton(system: model.phase == .playing ? "pause.fill" : "play.fill",
                                    focus: focus, tag: .playPause) { onTogglePlay() }
                    TransportButton(system: "goforward.10", focus: focus, tag: .forward) { onSkip(10) }
                    if model.isEpisode && !model.seasonEpisodes.isEmpty {
                        TransportButton(system: "rectangle.stack", focus: focus, tag: .episodes) { onEpisodes() }
                    }
                }
                .transition(.opacity.combined(with: .offset(y: 12)))
            }
            if barShown {
                ScrubBarRow(model: model, buffering: model.isBuffering)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            if model.isEpisode && !model.seasonEpisodes.isEmpty {
                if showEpisodes {
                    EpisodeStripExpanded(model: model, onPlay: { showEpisodes = false })
                        .transition(.opacity)
                } else if barShown {
                    EpisodePeek()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
        // A clean side margin (the bar now genuinely respects this — see ScrubBarRow). Also keeps the
        // bar + timecodes inside the tvOS title-safe area.
        .padding(.horizontal, 90)
        // Collapsed (just the bar / a movie) the bar would sit in the TV's overscan and clip; lift it
        // clear. Expanded, the tall strip already rides the bar well up, so keep it tight to the cards.
        .padding(.bottom, showEpisodes ? 48 : 76)
        // A soft bottom scrim so the bar + episode stills/labels stay readable over bright scenes.
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                .frame(height: showEpisodes ? 360 : 240)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .opacity(barShown ? 1 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.25), value: barShown)
        .animation(.easeInOut(duration: 0.3), value: showEpisodes)
    }
}

/// The thin scrub bar's content (no bottom anchoring of its own — `PlayerBottomBar` stacks it).
private struct ScrubBarRow: View {
    @Bindable var model: PlayerModel
    let buffering: Bool

    var body: some View {
        let shown = model.isScrubbing ? model.scrubTarget : model.position
        let frac = model.duration > 0 ? min(1, max(0, shown / model.duration)) : 0
        VStack(spacing: 8) {
            ZStack(alignment: .leading) {
                // A plain Capsule (NOT the GeometryReader) sets the bar's width, so it respects the
                // cluster's horizontal padding. The GeometryReader is nested INSIDE and reads this
                // already-padded width. Previously the GeometryReader was the outer view and stretched
                // the bar edge-to-edge, ignoring the padding (why bumping the inset never moved it).
                Capsule().fill(.white.opacity(0.25)).frame(height: 6)
                GeometryReader { geo in
                    let headX = min(geo.size.width, max(0, geo.size.width * frac))
                    Capsule().fill(.white).frame(width: headX, height: 6)
                        .frame(maxHeight: .infinity, alignment: .center)
                    Circle().fill(.white).frame(width: 16, height: 16)
                        .position(x: min(geo.size.width - 8, max(8, headX)), y: geo.size.height / 2)
                }
            }
            .frame(height: 22)
            HStack {
                Text(Timecode.format(shown)).font(.body.monospacedDigit().weight(.semibold))
                Spacer()
                Text("-" + Timecode.format(max(0, model.duration - shown)))
                    .font(.body.monospacedDigit()).foregroundStyle(.secondary)
            }
            if buffering {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("Loading…").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

/// Resting hint: a chevron + "Episodes" sitting just under the scrub bar. Press UP (opens the
/// transport) then the Episodes button, or open the full strip from there.
private struct EpisodePeek: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.compact.up")
            Text("Episodes").font(.callout.weight(.semibold))
        }
        .foregroundStyle(.white.opacity(0.6))
        .frame(maxWidth: .infinity)
    }
}

/// Open state: the season's episodes as focusable still cards. Selecting a downloaded one switches
/// playback in place; not-downloaded ones are dimmed + a ⬇︎ glyph. Seeds focus to the current one.
private struct EpisodeStripExpanded: View {
    @Bindable var model: PlayerModel
    let onPlay: () -> Void
    @FocusState private var focused: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 22) {
                    ForEach(model.seasonEpisodes) { ep in
                        Button { if let owned = ep.owned { model.play(owned); onPlay() } } label: { card(ep) }
                            .buttonStyle(.card)
                            .disabled(!ep.isPlayable)
                            .id(ep.id)
                            .focused($focused, equals: ep.id)
                    }
                }
                .padding(.vertical, 10)            // just enough room for the focus lift
            }
            // Snug to the cards (stills only now, no name labels) so the strip sits TIGHT under the
            // scrub bar — a horizontal ScrollView is greedy vertically and would otherwise fill it.
            .frame(height: 140)
            .onAppear {
                guard let cur = model.currentEpisode else { return }
                let id = "\(cur.season)x\(cur.number)"
                focused = id
                proxy.scrollTo(id, anchor: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card(_ ep: PlayerModel.PlayerEpisode) -> some View {
        let isCurrent = ep.season == model.currentEpisode?.season && ep.number == model.currentEpisode?.number
        return VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: TMDBClient.imageURL(path: ep.stillPath, size: "w300")) {
                $0.resizable().aspectRatio(contentMode: .fill)
            } placeholder: { Rectangle().fill(.white.opacity(0.08)) }
                .frame(width: 200, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topLeading) {
                    Text("\(ep.number)")
                        .font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(6)
                }
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.Palette.gold, lineWidth: 4)
                    } else if !ep.isPlayable {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.45))
                            .overlay {
                                Image(systemName: "arrow.down.circle").font(.title2)
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                    }
                }
        }
        .opacity(ep.isPlayable ? 1 : 0.7)
    }
}
