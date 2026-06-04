import SwiftUI
import DebridCore

/// Which transport control currently holds focus. Drives the highlight + which view
/// receives the remote's left/right (the scrubber skips ±10s; the button opens the panel).
enum PlayerControl: Hashable { case scrubber, subtitles }

struct PlayerView: View {
    @State private var model: PlayerModel
    @State private var engine: VLCKitVideoPlayerEngine
    @State private var showTracks = false
    @FocusState private var focus: PlayerControl?
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
                if model.controlsVisible {
                    TransportOverlay(model: model, focus: $focus) { showTracks = true }
                }
            }

            if showTracks { TrackMenuPanel(model: model) }
        }
        .onPlayPauseCommand { model.togglePlayPause() }
        .onExitCommand { if showTracks { showTracks = false } else { dismiss() } }
        .onAppear { model.start() }
        // Land focus on the scrubber when controls appear / the panel closes, so the remote works
        // and Menu (onExitCommand above) fires from within the player.
        .onChange(of: model.phase) { _, p in
            if case .playing = p, focus == nil { focus = .scrubber }
        }
        .onChange(of: showTracks) { _, open in if !open { focus = .scrubber } }
        .onChange(of: model.shouldDismiss) { _, dismissNow in if dismissNow { dismiss() } }
        .onDisappear { Task { await model.teardown() } }
    }
}
