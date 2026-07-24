import SwiftUI
import DebridUI
import DebridCore

/// What still takes SwiftUI focus inside the player. At rest NOTHING does — `PlayerInputSurface`
/// owns the remote and is deliberately non-focusable, which is what lets touch-scrub and
/// directional clicks coexist. Only the lifted episode strip is a focusable surface.
enum PlayerFocus: Hashable { case episodes }

struct PlayerView: View {
    @State private var model: PlayerModel
    @State private var engine: VLCKitVideoPlayerEngine
    @State private var showSettings = false
    @State private var showEpisodes = false
    /// The playhead when the current scrub gesture started — scrub displacement is relative to it.
    @State private var scrubOrigin: Double = 0
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

            // The interaction layer is ALWAYS mounted. It used to be the `else` branch of the
            // loading check, so while "Buffering…" showed there was no input surface, no bar and
            // no Back affordance at all — and `.defaultFocus(.stage)` pointed at a view that did
            // not exist. Swapping the focused view's identity mid-playback is also the exact
            // anti-pattern that cost this app its Browse-tile focus (see CLAUDE.md).
            PlayerInputSurface(
                isActive: !showSettings && !showEpisodes && !model.upNextVisible,
                onTouchDown: { model.revealScrubBar() },
                onTouchUp: {},
                onScrubBegan: { model.beginScrub() },
                onScrubMoved: { displacement in
                    let target = scrubOrigin + ScrubGain.seconds(forDisplacement: displacement,
                                                                 duration: model.duration)
                    model.updateScrub(by: target - model.scrubTarget)
                },
                onScrubEnded: { model.commitScrub() },
                onScrubCancelled: { model.cancelScrub() },
                onSkip: { delta in
                    if model.isScrubbing { model.updateScrub(by: delta) }
                    else { model.skip(delta); model.revealScrubBar() }
                },
                onSelect: { model.togglePlayPause(); model.revealScrubBar() },
                onUp: { model.revealScrubBar() },
                onDown: { openSettingsOrEpisodes() },
                onScanBegan: { direction in model.beginScan(direction: direction) },
                onScanEnded: { model.endScan() }
            )
            .ignoresSafeArea()
            .onChange(of: model.isScrubbing) { _, scrubbing in
                if scrubbing { scrubOrigin = model.position }
            }

            // One bottom-anchored column: thin scrub bar on top, the episode strip beneath.
            // Stacking them means the bar AUTOMATICALLY rides up as the strip grows.
            PlayerBottomBar(model: model, showEpisodes: $showEpisodes,
                            focus: $focus,
                            onEpisodes: { openEpisodes() })

            // Loading is now an OVERLAY above a live interaction layer, never a replacement for it.
            // And it is gated on a COLD open: an episode auto-advance also reloads (clearing
            // hasRenderedFrame), but the viewer is already watching, so taking the screen over is
            // wrong — the bar's inline spinner covers that case.
            if case .failed(let reason) = model.phase {
                ErrorOverlay(reason: reason, canTryAnother: model.canTryAnotherVersion, backdropURL: backdropURL,
                             onRetry: { model.retry() }, onTryAnother: { model.tryAnotherVersion() },
                             onBack: { dismiss() })
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if model.isColdOpen {
                LoadingOverlay(caption: model.phase == .preparing ? "Preparing…" : "Buffering…",
                               title: model.label, backdropURL: backdropURL)
                    .transition(.opacity)
                    .allowsHitTesting(false)      // the input surface underneath stays live
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

            // Last, so it sits above the skip badge and the Up Next bar — they used to render
            // over the panel.
            if showSettings {
                SettingsPanel(model: model, onClose: { showSettings = false })
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Theme.Anim.pageFade, value: showSettings)
        .animation(Theme.Anim.pageFade, value: showEpisodes)
        .animation(Theme.Anim.pageFade, value: model.upNextVisible)
        .animation(Theme.Anim.pageFade, value: model.isColdOpen)
        // The error overlay is gated on `phase`; without animating that value it would pop in
        // rather than fade. Only the ErrorOverlay enters/leaves on a phase change, so this can't
        // animate anything else in the stack.
        .animation(Theme.Anim.pageFade, value: model.phase)
        .animation(Theme.Anim.focus, value: model.skipFeedback)
        .onPlayPauseCommand { model.togglePlayPause() }
        .onExitCommand {
            if model.isScrubbing { model.cancelScrub() }       // Menu abandons a scrub
            else if model.upNextVisible { model.dismissUpNext() }
            else if showSettings { showSettings = false }
            else if showEpisodes { showEpisodes = false }
            else { dismiss() }
        }
        .onAppear {
            model.start()
            model.revealScrubBar()           // show the bar right away on open (sticky 5s)
        }
        .task(id: model.currentEpisode?.season) {
            if model.isEpisode { await model.loadSeasonEpisodes() }   // so the peek has thumbnails
        }
        // A closing panel hands the remote back to the input surface (which re-enables itself via
        // `isActive`) and re-reveals the bar so there is something on screen to act on.
        .onChange(of: showSettings) { _, open in if !open { model.revealScrubBar() } }
        .onChange(of: showEpisodes) { _, open in if !open { model.revealScrubBar() } }
        .onChange(of: model.shouldDismiss) { _, dismissNow in if dismissNow { dismiss() } }
        .onDisappear { Task { await model.teardown() } }
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
    var focus: FocusState<PlayerFocus?>.Binding
    let onEpisodes: () -> Void

    // The bar is up while the viewer is interacting, mid-buffer, or the strip is open.
    private var barShown: Bool { model.scrubBarVisible || model.isBuffering || showEpisodes }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            if barShown {
                ScrubBar(model: model, buffering: model.isBuffering)
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
        // A clean side margin (the bar genuinely respects this — see ScrubBar). Also keeps the
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
        .animation(Theme.Anim.pageFade, value: barShown)
        .animation(Theme.Anim.pageFade, value: showEpisodes)
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
            RemoteImage(url: TMDBClient.imageURL(path: ep.stillPath, size: "w300"),
                        contentMode: .fill) { Rectangle().fill(.white.opacity(0.08)) }
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
