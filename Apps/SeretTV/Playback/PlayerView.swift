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

            switch model.phase {
            case .preparing: LoadingOverlay(caption: "Preparing…", title: model.label, backdropURL: backdropURL)
            case .buffering: LoadingOverlay(caption: "Buffering…", title: model.label, backdropURL: backdropURL)
            case .failed(let reason):
                ErrorOverlay(reason: reason, canTryAnother: model.canTryAnotherVersion, backdropURL: backdropURL,
                             onRetry: { model.retry() }, onTryAnother: { model.tryAnotherVersion() },
                             onBack: { dismiss() })
            case .playing, .paused, .ended:
                // Clean by default. The focusable ScrubPad covers the screen invisibly to receive
                // remote gestures: horizontal swipe → scrub, swipe down → show settings, click → play/pause.
                ScrubPad(model: model, onShowSettings: { showSettings = true })
                // Minimal scrub bar surfaces only while scrubbing (no chrome otherwise).
                if model.isScrubbing { MinimalScrubBar(model: model) }
            }

            if showSettings {
                SettingsPanel(model: model, onClose: { showSettings = false })
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showSettings)
        .onPlayPauseCommand {
            if model.isScrubbing { model.commitScrub() } else { model.togglePlayPause() }
        }
        .onExitCommand {
            if showSettings { showSettings = false }
            else if model.isScrubbing { model.cancelScrub() }
            else { dismiss() }
        }
        .onAppear { model.start() }
        .onChange(of: model.shouldDismiss) { _, dismissNow in if dismissNow { dismiss() } }
        .onDisappear { Task { await model.teardown() } }
    }
}

/// Thin bottom scrubber shown only while scrubbing — current time, mini bar, remaining.
private struct MinimalScrubBar: View {
    @Bindable var model: PlayerModel

    var body: some View {
        let shown = model.scrubTarget
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
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 56)
        }
        .transition(.opacity)
    }
}
