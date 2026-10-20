#if DEBUG
import DebridCore
import DebridUI
import SwiftUI

/// DEBUG-only harness for the movie title page — the real `MovieDetail` over fixed details and
/// watch state, no session or network beyond TMDB's image CDN. No iPad simulator is signed in, so
/// this is how the iPad layout (art + info on the left, sections in a readable column) gets
/// screenshot-checked.
///
///     xcrun simctl launch <udid> com.solomons.seret.mobile -uiPreview moviedetail
///
/// Not compiled into release builds.
struct DetailUIPreview: View {
    @State private var session = AppSession(realDebrid: RealDebridSession(store: InMemoryTokenStore()))
    @State private var scrolled = false
    @State private var store: DetailStore = {
        let source = { (id: String, res: String, src: String, audio: String) in
            MediaSource(torrentID: id, fileID: 1, restrictedLink: "rd://\(id)",
                        parsed: ParsedRelease(title: "Dune", year: 2021, resolution: res, source: src,
                                              videoCodec: "HEVC", audioCodec: audio),
                        sizeBytes: 58_400_000_000)
        }
        let movie = MediaItem(id: "movie:tmdb:438631", kind: .movie, title: "Dune", year: 2021,
                              sources: [source("a", "2160p", "BluRay", "Atmos"),
                                        source("b", "1080p", "WEB-DL", "DDP5.1")],
                              seasons: [], tmdbID: 438631,
                              backdropPath: Details.backdrop,
                              overview: Details.overview)
        return DetailStore(item: movie, details: Details(), watch: Watch(), profileID: "preview")
    }()

    var body: some View {
        NavigationStack {
            MovieDetail(store: store, heroScrolled: $scrolled, onPlay: { request in
                print("[preview] play \(request.label) fromStart=\(request.fromStart)")
            })
            .navigationBarTitleDisplayMode(.inline)
            .titlePageBar()
        }
        .environment(session)
        .environment(session.makeTileWatchMarks())
        .task { await store.load() }
        .preferredColorScheme(.dark)
    }

    private struct Details: MediaDetailsProviding {
        static let backdrop = "/jYEW5xZkZk2WTrdbMGAPFuBqbDc.jpg"
        static let overview = "Paul Atreides, a brilliant and gifted young man born into a great destiny beyond "
            + "his understanding, must travel to the most dangerous planet in the universe to ensure the "
            + "future of his family and his people."

        func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails {
            TMDBMovieDetails(id: tmdbID, title: "Dune", releaseDate: "2021-09-15", overview: Self.overview,
                             posterPath: nil, backdropPath: Self.backdrop, runtime: 155,
                             genres: [TMDBGenre(id: 878, name: "Science Fiction"),
                                      TMDBGenre(id: 12, name: "Adventure")],
                             voteAverage: 7.8, originalLanguage: "en", imdbID: "tt1160419",
                             directors: [TMDBPersonRef(id: 137427, name: "Denis Villeneuve")])
        }
        func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails { throw CancellationError() }
        func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] { [] }
    }

    /// Part-way through, so Play reads "Resume · 58:31".
    private struct Watch: WatchProgressProviding {
        func progress(forContentKey key: String, profileID: String) async throws -> WatchState? {
            WatchState(contentKey: key, sourceKey: "a#1", positionSeconds: 3511,
                       durationSeconds: 9300, finished: false, updatedAt: Date())
        }
        func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                    durationSeconds: Double, finished: Bool, profileID: String) async throws {}
        func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] { [] }
        func deleteProgress(forContentKeys keys: [String]) async throws {}
    }
}
#endif
