import DebridCore

/// "Mark watched / unwatched" for any title a poster stands for — a film you own, a film you
/// don't, or a whole show. `title` is a library item or `MediaItem.placeholder(for:)`; both carry
/// the canonical `movie:tmdb:…` / `show:tmdb:…` id every store keys writes by.
///
/// Lifted out of tvOS `BrowseTile.toggleWatched` / `LibraryTitleActions.markShow` (and the copy
/// `feat/mobile-parity` made a second time on the iPhone's `BrowseTile`) so the Mac gets one
/// tested answer instead of a third copy. tvOS and the iPhone keep their own call sites for now —
/// switching them over is a follow-up.
@MainActor
public struct TitleWatchToggle {
    private let watch: WatchProgressProviding?
    private let showMarker: ShowWatchMarker?
    private let library: LibraryStore?
    private let profileID: String?

    public init(watch: WatchProgressProviding?, showMarker: ShowWatchMarker?,
                library: LibraryStore?, profileID: String?) {
        self.watch = watch
        self.showMarker = showMarker
        self.library = library
        self.profileID = profileID
    }

    /// Returns false when nothing was written — no profile has resolved yet, or the seam the
    /// write needed (a watch store for an unowned film, a show marker for a show) is absent.
    @discardableResult
    public func set(_ watched: Bool, title: MediaItem) async -> Bool {
        guard let profileID else { return false }

        switch title.kind {
        case .movie:
            if let owned = library?.movies.first(where: { $0.id == title.id }) {
                await library?.setWatched(watched, for: owned)
                return true
            }
            guard let watch else { return false }
            await watch.setWatched(watched, contentKey: title.id, sourceKey: "", profileID: profileID)
            return true

        case .show:
            guard let showMarker else { return false }
            await showMarker.mark(watched, show: title, profileID: profileID)
            await library?.reloadWatchStates()
            return true
        }
    }
}
