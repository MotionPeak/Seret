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
                         onShowSettings: { showSettings = true },
                         onPullUp: {
                             model.revealScrubBar()           // swipe up always reveals the scrub bar
                             if model.isEpisode {             // …and the episode strip for a show
                                 showEpisodes = true
                                 Task { await model.loadSeasonEpisodes() }
                             }
                         })
                // Thin scrub bar: appears on click + during scrub, sticky 5s, fades in/out.
                // Forced visible while buffering (a seek/rebuffer), so the user gets the loading hint.
                MinimalScrubBar(model: model, buffering: model.isBuffering)
                    .opacity((model.scrubBarVisible || model.isBuffering) ? 1 : 0)
                    .animation(.easeInOut(duration: 0.25), value: model.scrubBarVisible)
                    .animation(.easeInOut(duration: 0.25), value: model.isBuffering)
                    .allowsHitTesting(false)
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

/// Swipe-up episode strip (shows): the current season's episodes as focusable still cards.
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
                                    Button { model.play(ep.episode); onClose() } label: { card(ep) }
                                        .buttonStyle(.card)
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
            .background(.black.opacity(0.85))
            .padding(.bottom, 96)        // clear the thin scrub bar below
        }
    }

    private func card(_ ep: PlayerModel.PlayerEpisode) -> some View {
        let isCurrent = ep.episode.season == model.currentEpisode?.season
            && ep.episode.number == model.currentEpisode?.number
        return VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: TMDBClient.imageURL(path: ep.stillPath, size: "w300")) {
                $0.resizable().aspectRatio(contentMode: .fill)
            } placeholder: { Rectangle().fill(.gray.opacity(0.25)) }
                .frame(width: 300, height: 300 * 9 / 16).clipped()
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 6).stroke(Theme.Palette.gold, lineWidth: 4)
                    }
                }
            Text("\(ep.episode.number) · \(ep.name ?? "Episode \(ep.episode.number)")")
                .font(.callout.weight(.semibold)).lineLimit(1).frame(width: 300, alignment: .leading)
        }
    }
}

/// Thin bottom scrubber shown only while scrubbing — current time, mini bar, remaining.
private struct MinimalScrubBar: View {
    @Bindable var model: PlayerModel
    let buffering: Bool

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
            .padding(.bottom, 56)
        }
        .transition(.opacity)
    }
}
