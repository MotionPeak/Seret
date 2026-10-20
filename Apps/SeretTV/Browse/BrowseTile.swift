import DebridCore
import DebridUI
import SwiftUI

/// Where a browse/search poster goes: the title's page, or the full-screen Search. ONE value type
/// so a tile is ONE stable `NavigationLink` — see BrowseTile.
enum BrowseDestination: Hashable {
    case detail(MediaItem)
    case search(MediaKind)
    /// An actor or director — their photo and the work of theirs you can watch.
    case person(TMDBPersonRef)
    /// One genre's full grid — a genre row's "See All" on Movies/Shows.
    case genre(MediaKind, DiscoverStore.Genre)
    /// Straight to the full-screen versions list, skipping the page.
    case versions(SearchHit)
    /// The versions list for ONE episode of a show. A separate case rather than optional payload
    /// on `versions`, so an episode row's link carries one unambiguous value.
    case episodeVersions(SearchHit, season: Int, number: Int)
    /// Straight into playback, skipping the page — what a Continue Watching card means.
    ///
    /// A destination CASE rather than pushing a bare `PlaybackRequest`, because a link must offer
    /// one value type: Home has to choose between resuming and (when the file no longer resolves)
    /// opening the page, and choosing between two differently-typed links would swap the identity
    /// of a focused view, which is how this app has lost focus before.
    case play(PlaybackRequest)
}

/// A focusable browse poster — a `PosterTile` (the Plex rail tile) carrying what a TMDB title
/// needs on top: the watched ✓ and dim, the "in library" ✓, a CAM chip for a film still in
/// cinemas, and the press-and-hold menu (watched, watchlist, remove). Owned or not, it opens the
/// SAME page — an un-owned title is a source-less placeholder that `DetailStore` fills in from TMDB
/// exactly as it fills in a library item. Shared by Movies/Shows, Search, the genre grid, a
/// person's credits and "More Like This"; the grids wrap it in `CaptionedPoster` for its title.
///
/// ⚠️ The link must be ONE stable view whose VALUE varies — not an owned/not-owned branch of two
/// links. The background library load flips `ownedItem` while the user browses; a branch swap
/// destroys the focused tile, tvOS silently drops focus back to the first stable element (the
/// Search pill), and the next click opened the search keyboard instead of the title. `PosterTile`
/// is built once as a link and only its value and marks change.
struct BrowseTile: View {
    let hit: SearchHit
    var cam: Bool = false
    /// Focus landed on this tile — a browse page drives its preview header from it.
    var onFocus: () -> Void = {}
    @Environment(AppSession.self) private var session
    /// OPTIONAL, deliberately. A non-optional `@Environment` read of an `@Observable` TRAPS when
    /// the object is not in the environment, and it does not reliably cross a presentation
    /// boundary — which is the `EnvironmentValues.subscript.getter → assertionFailure` SIGTRAP in
    /// this app's crash reports. Absent marks must mean "no ticks yet", never a dead process.
    @Environment(TileWatchMarks.self) private var marks: TileWatchMarks?
    /// Optional for the same reason as `marks` above.
    @Environment(WatchlistMarks.self) private var watchlist: WatchlistMarks?
    /// Set by the shell; a no-op anywhere else. See `requestLibraryRemoval`.
    @Environment(\.requestLibraryRemoval) private var requestRemoval

    var body: some View {
        let owned = session.libraryStore?.ownedItem(tmdbID: hit.result.id, kind: hit.kind)
        let watched = marks?.isWatched(hit) ?? false
        // Watched beats owned beats CAM — the tile shows one mark at a time, as it always has.
        return PosterTile(posterPath: hit.result.posterPath, title: hit.result.displayTitle,
                          chip: cam && owned == nil && !watched ? "CAM" : nil,
                          // A warning, not a label: a cinema recording is worth avoiding.
                          chipTint: Theme.Palette.destructive.opacity(0.85),
                          watched: watched, owned: owned != nil, onFocus: onFocus,
                          value: BrowseDestination.detail(owned ?? .placeholder(for: hit)))
            // Press and hold to say you have seen it. `PosterCard` in the library grid already
            // proves this works on a `.card` NavigationLink with the Siri remote.
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

                // Only for a title you actually own — a Find result you have not added has
                // nothing to remove. Find could mark watched but never remove, which is half of
                // "the option isn't there in all screens".
                if let owned {
                    Button("Remove from Library", systemImage: "trash", role: .destructive) {
                        requestRemoval(owned)
                    }
                }
            }
    }

    private var markLabel: String { hit.kind == .movie ? "Mark Watched" : "Mark Show Watched" }
    private var unmarkLabel: String { hit.kind == .movie ? "Mark Unwatched" : "Mark Show Unwatched" }

    /// The tick flips immediately; the write follows. A movie is one row. A show fans out over
    /// every episode TMDB lists, which is why it runs detached rather than blocking the gesture.
    private func toggleWatched(_ watched: Bool) {
        marks?.set(!watched, for: hit)
        let profileID = session.activeProfileID ?? ""
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
