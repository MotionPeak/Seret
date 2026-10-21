import DebridCore
import DebridUI
import SwiftUI

/// A TMDB title's poster that opens its page — the one tile every browse surface uses (Movies,
/// Shows, a genre grid, Search). Owned or not, it is the same page: an un-owned title is a
/// source-less placeholder that `DetailStore` fills in from TMDB.
///
/// Marks: watched dims and ticks, owned gets the quieter ✓, a theatrical-window title not in the
/// library gets the CAM warning chip. The long-press menu marks it (un)watched, puts a film on or
/// off the watchlist, and removes an owned title.
struct HitTile: View {
    let hit: SearchHit
    var width: CGFloat?
    var cam = false
    var showsTitle = false
    /// Runs before the page opens (Search puts its keyboard away).
    var onOpen: () -> Void = {}
    /// Asks the page to confirm removing an owned title.
    var onRemove: (MediaItem) -> Void = { _ in }

    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router
    /// OPTIONAL, deliberately: a non-optional `@Environment` read of an `@Observable` TRAPS when
    /// the object has not crossed a presentation boundary. Absent marks mean "no ticks yet".
    @Environment(TileWatchMarks.self) private var marks: TileWatchMarks?
    @Environment(WatchlistMarks.self) private var watchlist: WatchlistMarks?

    var body: some View {
        let owned = session.libraryStore?.ownedItem(tmdbID: hit.result.id, kind: hit.kind)
        let watched = marks?.isWatched(hit) ?? false
        return Button {
            onOpen()
            router.detail = owned ?? .placeholder(for: hit)
        } label: {
            PosterTile(posterPath: hit.result.posterPath, title: hit.result.displayTitle,
                       width: width,
                       chip: cam && owned == nil && !watched ? "CAM" : nil,
                       chipTint: cam ? Theme.Palette.destructive.opacity(0.85) : nil,
                       watched: watched, owned: owned != nil, showsTitle: showsTitle)
        }
        .pressable()
        .contextMenu {
            Button(watched ? unmarkLabel : markLabel,
                   systemImage: watched ? "checkmark.circle.fill" : "checkmark.circle") {
                toggleWatched(watched)
            }
            // Films only: Letterboxd has no watchlist a show can go on.
            if let film = WatchlistFilm(hit: hit), let watchlist {
                let on = watchlist.contains(tmdbID: film.tmdbID)
                Button(on ? "Remove from Watchlist" : "Add to Watchlist",
                       systemImage: on ? "bookmark.fill" : "bookmark") {
                    Task { await watchlist.toggle(film: film) }
                }
            }
            // Only for a title you actually own — an unowned result has nothing to remove.
            if let owned {
                Button("Remove from Library", systemImage: "trash", role: .destructive) {
                    onRemove(owned)
                }
            }
        }
    }

    private var markLabel: String { hit.kind == .movie ? "Mark Watched" : "Mark Show Watched" }
    private var unmarkLabel: String { hit.kind == .movie ? "Mark Unwatched" : "Mark Show Unwatched" }

    /// The tick flips immediately; the write follows. A show fans out over every episode TMDB
    /// lists, which is why it runs detached rather than blocking the gesture.
    private func toggleWatched(_ watched: Bool) {
        // Not before a profile has resolved (see `LibraryTitleMenu.markShow`) — and before the
        // tick flips, so it never shows a mark that was not written.
        guard let profileID = session.activeProfileID else { return }
        marks?.set(!watched, for: hit)
        Task {
            switch hit.kind {
            case .movie:
                await session.watchStore?.setWatched(!watched, contentKey: hit.contentKey,
                                                     sourceKey: "", profileID: profileID)
            case .show:
                await session.makeShowWatchMarker()?.mark(!watched, show: .placeholder(for: hit),
                                                          profileID: profileID)
            }
        }
    }
}
