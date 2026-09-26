import DebridCore
import DebridUI

/// Mac glue: what happens when a poster's hover row or context menu is used. Built fresh in each
/// view from whatever the environment has on hand — every dependency is optional, so a poster still
/// renders (its actions simply no-op) before sign-in resolves.
@MainActor
struct PosterActionPerformer {
    let session: AppSession?
    let shell: ShellModel?
    let library: LibraryStore?
    let marks: TileWatchMarks?
    let watchlist: WatchlistMarks?

    func perform(_ action: PosterAction, on model: PosterTileModel) {
        switch action {
        case .open:
            // The franchise rail rings the film you're already reading and turns off its quick
            // actions — but a right-click still offers Open, so this is the one place left that
            // must refuse to push a second copy of the page you're standing on.
            guard shell?.titleOnTop?.id != model.page.id else { return }
            shell?.open(.title(model.page))

        case .play:
            guard let owned = model.owned, let session else { return }
            Task {
                if let request = await QuickPlay.request(for: owned, session: session) {
                    shell?.present(request)
                } else {
                    shell?.couldNotPlay = owned
                }
            }

        case .watchlist:
            guard let film = model.watchlistFilm else { return }
            Task { await watchlist?.toggle(film: film) }   // the shell turns the outcome into a toast

        case .markWatched(let watched), .markShowWatched(let watched):
            // Flip the tick now — the round-trip below is what makes it durable.
            if let hit = model.hit { marks?.set(watched, for: hit) }
            let toggle = TitleWatchToggle(watch: session?.watchStore, showMarker: session?.makeShowWatchMarker(),
                                          library: library, profileID: session?.activeProfileID)
            Task {
                let ok = await toggle.set(watched, title: model.page)
                if ok {
                    shell?.showToast(Self.markedMessage(model: model, watched: watched))
                } else {
                    // Nothing was written, so take back the tick flipped above — or the poster
                    // shows a mark that is gone on the next load.
                    if let hit = model.hit { marks?.set(!watched, for: hit) }
                    shell?.showToast("Couldn\u{2019}t mark \u{201C}\(model.title)\u{201D} \u{2014} your profile hasn\u{2019}t loaded yet",
                                     isFailure: true)
                }
            }

        case .removeFromLibrary:
            shell?.pendingRemoval = model.owned
        }
    }

    private static func markedMessage(model: PosterTileModel, watched: Bool) -> String {
        let verb = watched ? "watched" : "unwatched"
        if model.kind == .show {
            return "Marked every episode of \u{201C}\(model.title)\u{201D} \(verb)"
        }
        return "Marked \u{201C}\(model.title)\u{201D} \(verb)"
    }
}
