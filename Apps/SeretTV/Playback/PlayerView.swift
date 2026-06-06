import SwiftUI
import DebridUI

struct PlayerView: View {
    @State private var model: PlayerModel
    @State private var engine: VLCKitVideoPlayerEngine
    @State private var showSettings = false
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

            // Show the full LoadingOverlay ONLY for the initial load (no frames yet). After that —
            // including a seek-triggered rebuffer — keep the player chrome up and surface a small
            // spinner inline under the scrub bar instead of dimming the whole screen.
            let rebuffering = model.phase == .buffering && model.position > 0
            switch model.phase {
            case .preparing:
                LoadingOverlay(caption: "Preparing…", title: model.label, backdropURL: backdropURL)
            case .buffering where !rebuffering:
                LoadingOverlay(caption: "Buffering…", title: model.label, backdropURL: backdropURL)
            case .failed(let reason):
                ErrorOverlay(reason: reason, canTryAnother: model.canTryAnotherVersion, backdropURL: backdropURL,
                             onRetry: { model.retry() }, onTryAnother: { model.tryAnotherVersion() },
                             onBack: { dismiss() })
            case .playing, .paused, .ended, .buffering:
                // Clean by default. The focusable ScrubPad covers the screen invisibly to receive
                // remote gestures: horizontal swipe → scrub, swipe down → show settings, click →
                // play/pause. While the settings panel is open it goes inert so swipes navigate the
                // panel instead of starting a scrub.
                ScrubPad(model: model, isInteractive: !showSettings,
                         onShowSettings: { showSettings = true })
                // Thin scrub bar: appears on click + during scrub, sticky 5s, fades in/out.
                // Forced visible while a seek is rebuffering, so the user gets the loading hint.
                MinimalScrubBar(model: model, rebuffering: rebuffering)
                    .opacity((model.scrubBarVisible || rebuffering) ? 1 : 0)
                    .animation(.easeInOut(duration: 0.25), value: model.scrubBarVisible)
                    .animation(.easeInOut(duration: 0.25), value: rebuffering)
                    .allowsHitTesting(false)
            }

            if showSettings {
                SettingsPanel(model: model, onClose: { showSettings = false })
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showSettings)
        .onPlayPauseCommand {
            if model.isScrubbing { model.commitScrub() } else { model.togglePlayPause() }
        }
        .onExitCommand {
            if showSettings { showSettings = false }
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

/// Thin bottom scrubber shown only while scrubbing — current time, mini bar, remaining.
private struct MinimalScrubBar: View {
    @Bindable var model: PlayerModel
    let rebuffering: Bool

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
                        Capsule().fill(.white.opacity(0.22)).frame(height: 6)
                        Capsule().fill(Theme.Palette.gold).frame(width: headX, height: 6)
                            .shadow(color: Theme.Palette.goldGlow, radius: 6)
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
                // Inline loading hint under the bar when a seek is rebuffering — the bar stays up.
                if rebuffering {
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
