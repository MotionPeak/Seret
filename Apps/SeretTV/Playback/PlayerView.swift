import SwiftUI
import DebridCore

struct PlayerView: View {
    @State private var model: PlayerModel
    @State private var engine: VLCKitVideoPlayerEngine
    @State private var showTracks = false
    @Environment(\.dismiss) private var dismiss
    let backdropURL: URL?

    init(model: PlayerModel, engine: VLCKitVideoPlayerEngine, backdropURL: URL?) {
        _model = State(initialValue: model)
        _engine = State(initialValue: engine)
        self.backdropURL = backdropURL
    }

    var body: some View {
        ZStack {
            VLCVideoView(videoView: engine.videoView).ignoresSafeArea()

            switch model.phase {
            case .preparing: LoadingOverlay(caption: "Preparing…", title: model.label, backdropURL: backdropURL)
            case .buffering: LoadingOverlay(caption: "Buffering…", title: model.label, backdropURL: backdropURL)
            case .failed(let reason):
                ErrorOverlay(reason: reason, canTryAnother: model.canTryAnotherVersion, backdropURL: backdropURL,
                             onRetry: { model.retry() }, onTryAnother: { model.tryAnotherVersion() },
                             onBack: { dismiss() })
            case .playing, .paused, .ended:
                if model.controlsVisible { TransportOverlay(model: model) { showTracks = true } }
            }

            if showTracks { TrackMenuPanel(model: model) { showTracks = false } }
        }
        .onPlayPauseCommand { model.togglePlayPause() }
        .onMoveCommand { direction in
            switch direction {
            case .left: model.skip(-10)
            case .right: model.skip(10)
            case .down: showTracks = true
            default: break
            }
        }
        .onExitCommand { if showTracks { showTracks = false } else { dismiss() } }
        .onAppear { model.start() }
        .onChange(of: model.shouldDismiss) { _, dismissNow in if dismissNow { dismiss() } }
        .onDisappear { Task { await model.teardown() } }
    }
}
