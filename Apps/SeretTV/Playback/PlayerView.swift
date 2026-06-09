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
                             // Swipe DOWN: when the scrub bar is up on a show → the episodes popup
                             // (sits under the bar); otherwise → the audio/subtitle settings panel.
                             if model.scrubBarVisible && model.isEpisode {
                                 showEpisodes = true
                                 Task { await model.loadSeasonEpisodes() }
                             } else {
                                 showSettings = true
                             }
                         },
                         onPullUp: { model.revealScrubBar() })   // pull up lands on the scrub bar first
                // Thin scrub bar: appears on click + during scrub, sticky 5s, fades in/out.
                // Forced visible while buffering (a seek/rebuffer), so the user gets the loading hint.
                MinimalScrubBar(model: model, buffering: model.isBuffering, bottomInset: scrubInset)
                    .opacity((model.scrubBarVisible || model.isBuffering) ? 1 : 0)
                    .animation(.easeInOut(duration: 0.25), value: model.scrubBarVisible)
                    .animation(.easeInOut(duration: 0.25), value: model.isBuffering)
                    .animation(.easeInOut(duration: 0.25), value: scrubInset)
                    .allowsHitTesting(false)
                // A dimmed sliver of episode stills above the scrub bar — a hint that swiping down
                // opens the full strip. Shows only with the scrub bar, on a show.
                if model.isEpisode && model.scrubBarVisible && !showEpisodes && !showSettings
                    && !model.seasonEpisodes.isEmpty {
                    EpisodePeek(model: model)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.25), value: model.scrubBarVisible)
                }
            }

            if showSettings {
                SettingsPanel(model: model, onClose: { showSettings = false })
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if showEpisodes {
                EpisodesPanel(model: model, onClose: { showEpisodes = false })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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

    /// How far the scrub bar rides up: normal for a movie; lifted on a show so the episode peek
    /// sits beneath it; lifted further while the full strip is open so it has room to grow upward.
    private var scrubInset: CGFloat {
        guard model.isEpisode else { return 56 }
        return showEpisodes ? 268 : 140
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

/// A dimmed, vertically-cropped sliver of the season's stills, shown above the scrub bar as a hint
/// that swiping down opens the full episode strip. Non-interactive (the ScrubPad handles the swipe).
private struct EpisodePeek: View {
    let model: PlayerModel
    var body: some View {
        VStack(spacing: 6) {
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "chevron.compact.down")
                Text("Episodes").font(.callout.weight(.semibold))
            }
            .foregroundStyle(.white.opacity(0.65))
            HStack(spacing: 10) {
                ForEach(model.seasonEpisodes.prefix(14)) { ep in
                    let isCurrent = ep.season == model.currentEpisode?.season
                        && ep.number == model.currentEpisode?.number
                    AsyncImage(url: TMDBClient.imageURL(path: ep.stillPath, size: "w300")) {
                        $0.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: { Rectangle().fill(.white.opacity(0.08)) }
                    .frame(width: 150, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        if isCurrent {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Theme.Palette.gold, lineWidth: 2)
                        }
                    }
                }
            }
            .frame(height: 34, alignment: .top)   // crop to a thin sliver — only the top shows
            .clipped()
            .opacity(0.5)
            .mask(LinearGradient(colors: [.clear, .black, .black, .clear],
                                 startPoint: .leading, endPoint: .trailing))
        }
        .padding(.bottom, 36)                     // sit BENEATH the (raised) scrub bar
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

/// Swipe-down episode strip (shows): the current season's episodes as focusable still cards.
/// Selecting one switches playback to it in-place. Seeds focus to the playing episode and sits
/// just above the thin scrub bar so both are visible.
private struct EpisodesPanel: View {
    @Bindable var model: PlayerModel
    let onClose: () -> Void
    @FocusState private var focused: String?

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                Text("Episodes").font(.title3.weight(.semibold)).foregroundStyle(Theme.Palette.gold)
                    .padding(.horizontal, 60)
                if model.seasonEpisodes.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView().tint(Theme.Palette.gold)
                        Text("Loading episodes…").foregroundStyle(.secondary)
                    }
                    .frame(height: 200).padding(.horizontal, 60)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 28) {
                                ForEach(model.seasonEpisodes) { ep in
                                    Button {
                                        if let owned = ep.owned { model.play(owned); onClose() }
                                    } label: { card(ep) }
                                        .buttonStyle(.card)
                                        .disabled(!ep.isPlayable)        // not downloaded → not selectable
                                        .id(ep.id)
                                        .focused($focused, equals: ep.id)
                                }
                            }
                            .padding(.horizontal, 60).padding(.vertical, 12)
                        }
                        .onAppear {
                            guard let cur = model.currentEpisode else { return }
                            let id = "\(cur.season)x\(cur.number)"
                            focused = id
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
            .padding(.vertical, 22)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.92)],
                               startPoint: .top, endPoint: .bottom)
            )
            .padding(.bottom, 36)        // rise from the bottom, BENEATH the (raised) scrub bar
        }
    }

    private func card(_ ep: PlayerModel.PlayerEpisode) -> some View {
        let isCurrent = ep.season == model.currentEpisode?.season && ep.number == model.currentEpisode?.number
        return VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: TMDBClient.imageURL(path: ep.stillPath, size: "w300")) {
                $0.resizable().aspectRatio(contentMode: .fill)
            } placeholder: { Rectangle().fill(.white.opacity(0.08)) }
                .frame(width: 300, height: 300 * 9 / 16)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.Palette.gold, lineWidth: 4)
                    } else if !ep.isPlayable {
                        // Not downloaded → dim + a small marker so it reads as "not in your library".
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.45))
                            .overlay {
                                Image(systemName: "arrow.down.circle").font(.title2)
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                    }
                }
            Text("\(ep.number) · \(ep.name ?? "Episode \(ep.number)")")
                .font(.callout.weight(.semibold)).lineLimit(1).frame(width: 300, alignment: .leading)
                .foregroundStyle(ep.isPlayable ? .primary : .secondary)
        }
        .opacity(ep.isPlayable ? 1 : 0.7)
    }
}

/// Thin bottom scrubber shown only while scrubbing — current time, mini bar, remaining.
private struct MinimalScrubBar: View {
    @Bindable var model: PlayerModel
    let buffering: Bool
    /// Distance from the bottom edge. Rides UP on a show so the episode peek/strip can sit BENEATH
    /// the bar without ever overlapping it.
    var bottomInset: CGFloat = 56

    var body: some View {
        // Mid-scrub → preview target; otherwise the live playhead.
        let shown = model.isScrubbing ? model.scrubTarget : model.position
        let frac = model.duration > 0 ? min(1, max(0, shown / model.duration)) : 0
        VStack {
            Spacer()
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
                // Inline loading hint under the bar while buffering (a seek/rebuffer) — bar stays up.
                if buffering {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small).tint(.white)
                        Text("Loading…").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 80)
            .padding(.bottom, bottomInset)
        }
        .transition(.opacity)
    }
}
