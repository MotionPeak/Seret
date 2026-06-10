import SwiftUI
import DebridUI
import DebridCore

struct PlayerView: View {
    @State private var model: PlayerModel
    @State private var engine: VLCKitVideoPlayerEngine
    @State private var showSettings = false
    @State private var showEpisodes = false
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
                // Clean by default. The focusable ScrubPad covers the screen invisibly to receive
                // remote gestures: horizontal swipe → scrub, swipe down → show settings, click →
                // play/pause. While the settings panel is open it goes inert so swipes navigate the
                // panel instead of starting a scrub.
                ScrubPad(model: model, isInteractive: !showSettings && !showEpisodes,
                         onShowSettings: {
                             // Swipe DOWN: collapse the episode strip if it's open, else open settings.
                             if showEpisodes { showEpisodes = false }
                             else { showSettings = true }
                         },
                         onPullUp: {
                             // Swipe UP: first reveals the scrub bar; a SECOND swipe up (bar already
                             // showing, on a show) lifts the episode strip — up-then-up, no direction
                             // change, which reads more naturally than up-then-down.
                             if model.scrubBarVisible && model.isEpisode && !model.seasonEpisodes.isEmpty {
                                 showEpisodes = true
                                 Task { await model.loadSeasonEpisodes() }
                             } else {
                                 model.revealScrubBar()
                             }
                         })
                // One bottom-anchored column: the thin scrub bar on top, the episode strip beneath
                // it (a dimmed peek, or — on swipe-down — the full selectable strip). Stacking them
                // means the bar AUTOMATICALLY rides up as the strip grows: it can never overlap the
                // bar or float to the middle.
                PlayerBottomBar(model: model, showEpisodes: $showEpisodes)
            }

            if showSettings {
                SettingsPanel(model: model, onClose: { showSettings = false })
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if model.upNextVisible, let next = model.nextEpisode {
                UpNextBar(model: model, next: next)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showSettings)
        .animation(.easeInOut(duration: 0.25), value: showEpisodes)
        .animation(.easeInOut(duration: 0.25), value: model.upNextVisible)
        .onPlayPauseCommand {
            if model.isScrubbing { model.commitScrub() } else { model.togglePlayPause() }
        }
        .onExitCommand {
            if model.upNextVisible { model.dismissUpNext() }   // Menu keeps watching (credits)
            else if showSettings { showSettings = false }
            else if showEpisodes { showEpisodes = false }
            else if model.isScrubbing { model.cancelScrub() }
            else { dismiss() }
        }
        .onAppear {
            model.start()
            model.revealScrubBar()           // show the bar right away on open (sticky 5s)
        }
        .task(id: model.currentEpisode?.season) {
            if model.isEpisode { await model.loadSeasonEpisodes() }   // so the peek has thumbnails
        }
        .onChange(of: model.shouldDismiss) { _, dismissNow in if dismissNow { dismiss() } }
        .onDisappear { Task { await model.teardown() } }
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

/// The bottom-anchored player cluster: scrub bar on TOP, episode strip BENEATH it. Because they're
/// stacked in one bottom-pinned column, the bar automatically rides up as the strip grows — it can
/// never overlap the bar or float to the middle of the screen.
private struct PlayerBottomBar: View {
    @Bindable var model: PlayerModel
    @Binding var showEpisodes: Bool

    private var barShown: Bool { model.scrubBarVisible || model.isBuffering || showEpisodes }

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
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
                    EpisodePeek(model: model)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
        // 140pt horizontal so the bar ENDS + timecodes clear heavy TV overscan (80 and 100 both still
        // clipped on the owner's set — ~7% inset each side covers up to a 7.5% overscan crop).
        .padding(.horizontal, 140)
        // Collapsed (just the bar / a movie) the bar would sit in the TV's overscan and clip; lift it
        // clear. Expanded, the tall strip already rides the bar well up, so keep it tight to the cards.
        .padding(.bottom, showEpisodes ? 48 : 76)
        // A soft bottom scrim so the bar + episode stills/labels stay readable over bright scenes.
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                .frame(height: showEpisodes ? 360 : 210)
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
            GeometryReader { geo in
                let headX = geo.size.width * frac
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25)).frame(height: 6)
                    Capsule().fill(.white).frame(width: headX, height: 6)
                    Circle().fill(.white).frame(width: 16, height: 16)
                        .offset(x: min(geo.size.width - 16, max(0, headX - 8)))
                }
                .frame(maxHeight: .infinity, alignment: .center)
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

/// Resting hint: a dimmed, vertically-cropped, edge-faded sliver of the season's stills, sitting
/// just under the scrub bar. Swipe down (handled by the ScrubPad) opens the full strip.
private struct EpisodePeek: View {
    let model: PlayerModel
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.compact.up")
                Text("Episodes").font(.callout.weight(.semibold))
            }
            .foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 10) {
                ForEach(model.seasonEpisodes.prefix(14)) { ep in
                    let isCur = ep.season == model.currentEpisode?.season && ep.number == model.currentEpisode?.number
                    AsyncImage(url: TMDBClient.imageURL(path: ep.stillPath, size: "w300")) {
                        $0.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: { Rectangle().fill(.white.opacity(0.08)) }
                    .frame(width: 150, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        if isCur {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Theme.Palette.gold, lineWidth: 2)
                        }
                    }
                }
            }
            .frame(height: 30, alignment: .top)        // crop to a thin sliver — only the top shows
            .clipped()
            .opacity(0.5)
            .mask(LinearGradient(colors: [.clear, .black, .black, .clear],
                                 startPoint: .leading, endPoint: .trailing))
        }
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
                        .font(.title3.weight(.heavy)).monospacedDigit().foregroundStyle(.white)
                        .padding(.horizontal, 11).padding(.vertical, 4)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(8)
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
