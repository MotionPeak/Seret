#if DEBUG
import DebridCore
import DebridUI
import SwiftUI

/// `-uiPreview posters` / `postersloading` — the fixture films (plus a row of TMDB-hit tiles) in
/// `PosterTile`s, so tilt, glare, the gold rim, badges, quick actions and the loading skeletons can
/// all be screenshot-verified without signing in.
struct PosterGalleryPreview: View {
    var isLoading: Bool = false

    /// Inception carries the watchlist ribbon in this gallery.
    private var onWatchlistID: String { Fixture.films[3].id }
    /// Dune: Part Two is the forced-hover card — tilted, glared, rimmed, quick actions shown.
    private var forcedID: String { Fixture.films[1].id }

    var body: some View {
        ZStack {
            CanvasBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    PosterGrid(items: Fixture.films, isLoading: isLoading) { item in
                        libraryTile(for: item)
                    }
                    if !isLoading {
                        hitRow
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
        }
        .frame(minWidth: 1100, minHeight: 700)
    }

    private func libraryTile(for item: MediaItem) -> some View {
        let watched = Fixture.watch[WatchKey.content(forMovie: item)]
        let onWatchlist = item.id == onWatchlistID
        let model = PosterTileModel.library(item)
        return PosterTile(
            model: model,
            state: PosterTileState(badge: WatchBadge(watched), decor: PosterDecor(onWatchlist: onWatchlist)),
            actions: .make(kind: .movie, owned: true, watched: watched?.finished ?? false, onWatchlist: onWatchlist),
            perform: { _, _ in },
            forcedPointer: item.id == forcedID ? UnitPoint(x: 0.85, y: 0.15) : nil)
    }

    /// Owned, CAM and watched+dimmed — one of each, over TMDB-hit-shaped models (the shape Browse
    /// and Search build from) rather than library items.
    private var hitRow: some View {
        let dune = Fixture.films[0]
        let cam = Fixture.films[6]
        let godfather = Fixture.films[2]

        let ownedTile = PosterTileModel(id: "movie-hit:\(dune.tmdbID!)", title: dune.title,
            caption: dune.year.map(String.init) ?? "", posterURL: TMDBClient.imageURL(path: dune.posterPath, size: "w342"),
            kind: .movie, owned: dune, hit: nil, page: dune, watchlistFilm: WatchlistFilm(item: dune), isCAM: false)

        let camTile = PosterTileModel(id: "movie-hit:cam", title: cam.title,
            caption: cam.year.map(String.init) ?? "", posterURL: TMDBClient.imageURL(path: cam.posterPath, size: "w342"),
            kind: .movie, owned: nil, hit: nil, page: cam, watchlistFilm: nil, isCAM: true)

        let watchedTile = PosterTileModel(id: "movie-hit:watched", title: godfather.title,
            caption: godfather.year.map(String.init) ?? "", posterURL: TMDBClient.imageURL(path: godfather.posterPath, size: "w342"),
            kind: .movie, owned: godfather, hit: nil, page: godfather, watchlistFilm: WatchlistFilm(item: godfather), isCAM: false)

        return HStack(alignment: .top, spacing: PosterGridLayout.spacing) {
            PosterTile(model: ownedTile, state: PosterTileState(badge: .none, decor: PosterDecor(owned: true)),
                      actions: .make(kind: .movie, owned: true, watched: false, onWatchlist: false), perform: { _, _ in })
            PosterTile(model: camTile, state: PosterTileState(badge: .none, decor: PosterDecor(cam: true)),
                      actions: .make(kind: .movie, owned: false, watched: false, onWatchlist: false), perform: { _, _ in })
            PosterTile(model: watchedTile,
                      state: PosterTileState(badge: .watched, decor: PosterDecor(dimsWatched: true)),
                      actions: .make(kind: .movie, owned: true, watched: true, onWatchlist: false), perform: { _, _ in })
        }
        .padding(.top, 8)
    }
}
#endif
