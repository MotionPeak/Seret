import SwiftUI
import DebridCore

/// A transparent, focusable full-screen catcher shown while the transport is auto-hidden. The first
/// remote move/click brings the controls back without performing a transport action.
private struct WakeLayer: View {
    let onWake: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .focusable()
            .focused($focused)
            .onMoveCommand { _ in onWake() }
            .onTapGesture { onWake() }
            .onAppear { focused = true }
    }
}

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
                if model.controlsVisible {
                    TransportOverlay(model: model) { showTracks = true }
                } else {
                    // Controls auto-hid: an invisible focusable layer catches the first remote
                    // interaction and brings them back (without seeking).
                    WakeLayer { model.showControls() }
                }
            }

            if showTracks { TrackMenuPanel(model: model) }
        }
        .onPlayPauseCommand {
            if model.isScrubbing { model.commitScrub() } else { model.togglePlayPause() }
            model.showControls()
        }
        .onExitCommand {
            if model.isScrubbing { model.cancelScrub() }
            else if showTracks { showTracks = false }
            else { dismiss() }
        }
        .onAppear { model.start() }
        // Focus is driven by the focus engine: the focusable ScrubPad (prefersDefaultFocus) lands
        // focus when the transport appears, and the WakeLayer self-focuses when controls hide.
        .onChange(of: model.shouldDismiss) { _, dismissNow in if dismissNow { dismiss() } }
        .onDisappear { Task { await model.teardown() } }
    }
}
