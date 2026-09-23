import DebridCore
import DebridUI
import SwiftUI

/// One engine + model per presentation. `@StateObject`'s autoclosure runs once for the view's
/// lifetime; a view-builder closure or a `@State` default would build a libvlc instance per
/// re-render and drop them un-stopped (the VLCMediaPlayer-dealloc-on-VLC's-thread abort — memory:
/// player bugfix batch).
struct PlayerHost: View {
    @StateObject private var session: PlayerSession
    private let request: PlaybackRequest
    private let onExit: () -> Void

    init(request: PlaybackRequest, app: AppSession, onExit: @escaping () -> Void) {
        _session = StateObject(wrappedValue: PlayerSession(request: request, app: app))
        self.request = request
        self.onExit = onExit
    }

    var body: some View {
        if let model = session.model {
            PlayerScreen(model: model, onClose: onExit) {
                VideoSurface(videoView: session.engine.videoView)
            }
        } else {
            PlayerUnavailable(label: request.label, onClose: onExit)
        }
    }
}

@MainActor
final class PlayerSession: ObservableObject {
    let engine: VLCKitVideoPlayerEngine
    let model: PlayerModel?

    init(request: PlaybackRequest, app: AppSession) {
        let engine = VLCKitVideoPlayerEngine(preferences: app.subtitleSettings.preferences)
        self.engine = engine
        self.model = app.makePlayer(for: request, engine: engine, audioProbe: AudioActivityProbe())
        if model == nil { engine.stop() }   // no model will ever tear it down
    }
}

/// Shown only when `makePlayer` returns nil (signed out) — matches the failed-panel look so the
/// player never shows a blank black window with nothing explaining it.
private struct PlayerUnavailable: View {
    let label: String
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Playback isn't available right now.")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Button("Back", action: onClose)
                    .buttonStyle(GlassButtonStyle())
            }
            .padding(28)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
