import SwiftUI
import DebridUI
import DebridCore

/// Owns the one engine + model for a playback presentation, and builds them exactly once.
///
/// Every play site used to construct `VLCKitVideoPlayerEngine` inline in the `fullScreenCover` /
/// `navigationDestination` content closure. Those are view builders: SwiftUI re-invokes them
/// whenever the presenting screen re-evaluates, and this app's screens re-evaluate constantly
/// (`@Observable` stores, a playhead that ticks). Every one of those passes built a whole libvlc
/// instance and a `PlayerModel`, and SwiftUI kept the first and dropped the rest — un-`stop()`ped,
/// so a discarded player's `dealloc` could run on VLC's own mainloop thread. That is the abort
/// (`vlc_player_Lock` → `__assert_rtn`) behind most of this app's crash reports.
///
/// `@StateObject`'s initial value is an autoclosure SwiftUI evaluates exactly once for the lifetime
/// of the view, which is precisely the guarantee that was missing. Nothing here changes what is on
/// screen.
struct PlayerHost: View {
    @StateObject private var session: PlayerSession
    private let backdropURL: URL?
    /// Passed explicitly rather than read from the environment: a non-optional `@Environment`
    /// Observable read traps when the object does not cross the presentation boundary.
    private let pushSignal: LetterboxdPushSignal

    init(request: PlaybackRequest, app: AppSession, backdropSize: String) {
        _session = StateObject(wrappedValue: PlayerSession(request: request, app: app))
        backdropURL = TMDBClient.imageURL(path: request.item.backdropPath, size: backdropSize)
        pushSignal = app.letterboxdPushSignal
    }

    var body: some View {
        if let model = session.model {
            PlayerView(model: model, engine: session.engine, backdropURL: backdropURL,
                       pushSignal: pushSignal)
        } else {
            PlaybackUnavailableView()
        }
    }
}

/// Shown only if a player can't be built while signed in (e.g. the SwiftData container failed).
/// Gives the viewer a way back instead of a soft-locked blank screen.
///
/// Three of the four play sites used to fall back to a bare `Text` inside a `fullScreenCover`, with
/// no Back button and no Menu handling — which on tvOS is exactly the soft-lock this view exists to
/// prevent. One fallback now, for all of them.
private struct PlaybackUnavailableView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 54))
            Text("Unable to start playback.").font(.seretTitle2)
            Button("Back") { dismiss() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand { dismiss() }
    }
}

/// The engine + model pair, built together so the model always holds the engine the view renders.
@MainActor
final class PlayerSession: ObservableObject {
    let engine: VLCKitVideoPlayerEngine
    let model: PlayerModel?

    init(request: PlaybackRequest, app: AppSession) {
        let engine = VLCKitVideoPlayerEngine(preferences: app.subtitleSettings.preferences)
        self.engine = engine
        self.model = app.makePlayer(for: request, engine: engine, audioProbe: AudioActivityProbe())
    }
}
