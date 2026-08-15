import SwiftUI
import DebridUI
import DebridCore

/// Owns the one engine + model for a playback presentation, and builds them exactly once.
///
/// Every play site used to construct `VLCKitVideoPlayerEngine` inline in the `fullScreenCover`
/// content closure. Those are view builders: SwiftUI re-invokes them whenever the presenting screen
/// re-evaluates, and this app's screens re-evaluate constantly (`@Observable` stores, a playhead
/// that ticks). Every one of those passes built a whole libvlc instance and a `PlayerModel`, and
/// SwiftUI kept the first and dropped the rest — un-`stop()`ped, so a discarded player's `dealloc`
/// could run on VLC's own mainloop thread. That is the abort (`vlc_player_Lock` → `__assert_rtn`)
/// behind most of this app's crash reports.
///
/// `@StateObject`'s initial value is an autoclosure SwiftUI evaluates exactly once for the lifetime
/// of the view, which is precisely the guarantee that was missing. Nothing here changes what is on
/// screen.
struct PlayerHost: View {
    @StateObject private var session: PlayerSession
    private let request: PlaybackRequest
    private let backdropURL: URL?
    private let onExit: () -> Void

    init(request: PlaybackRequest, app: AppSession, onExit: @escaping () -> Void) {
        _session = StateObject(wrappedValue: PlayerSession(request: request, app: app))
        self.request = request
        self.onExit = onExit
        backdropURL = TMDBClient.imageURL(path: request.item.backdropPath, size: "w1280")
    }

    var body: some View {
        if let model = session.model {
            PlayerView(model: model, engine: session.engine, backdropURL: backdropURL, onExit: onExit)
        } else {
            PlayerPlaceholder(request: request)
        }
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
        self.model = app.makePlayer(for: request, engine: engine)
    }
}
