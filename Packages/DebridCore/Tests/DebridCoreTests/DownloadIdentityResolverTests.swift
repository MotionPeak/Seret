import Testing
import Foundation
@testable import DebridCore

@Suite struct DownloadIdentityResolverTests {
    /// Counts calls so the caching tests can prove TMDB is hit exactly once.
    private final class CountingSearch: DownloadTitleSearching, @unchecked Sendable {
        var movieHits: [TMDBSearchResult]
        var tvHits: [TMDBSearchResult]
        var movieCalls = 0
        var tvCalls = 0

        init(movieHits: [TMDBSearchResult] = [], tvHits: [TMDBSearchResult] = []) {
            self.movieHits = movieHits; self.tvHits = tvHits
        }

        func searchMovie(query: String, year: Int?) async throws -> [TMDBSearchResult] {
            movieCalls += 1
            return movieHits
        }

        func searchTV(query: String, firstAirYear: Int?) async throws -> [TMDBSearchResult] {
            tvCalls += 1
            return tvHits
        }
    }

    private func result(_ id: Int, title: String? = nil, name: String? = nil,
                        poster: String? = "/p.jpg") -> TMDBSearchResult {
        TMDBSearchResult(id: id, title: title, name: name, releaseDate: nil,
                         firstAirDate: nil, posterPath: poster, overview: nil, voteAverage: nil)
    }

    @Test func resolvesAMovieToTheMovieContentKey() async {
        let search = CountingSearch(movieHits: [result(693134, title: "Dune: Part Two")])
        let r = TMDBDownloadIdentityResolver(search: search)
        let id = await r.identity(filename: "Dune.Part.Two.2024.2160p.WEB-DL.mkv", infoHash: "h1")
        #expect(id?.contentKey == "movie:tmdb:693134")
        #expect(id?.tmdbID == 693134)
        #expect(id?.kind == .movie)
        #expect(id?.title == "Dune: Part Two")
        #expect(id?.posterPath == "/p.jpg")
    }

    @Test func resolvesAnEpisodeToTheEpisodeContentKey() async {
        let search = CountingSearch(tvHits: [result(1399, name: "Game of Thrones")])
        let r = TMDBDownloadIdentityResolver(search: search)
        let id = await r.identity(filename: "Game.of.Thrones.S01E02.1080p.mkv", infoHash: "h2")
        #expect(id?.contentKey == "show:tmdb:1399:s1e2")
        #expect(id?.kind == .show)
        #expect(id?.title == "Game of Thrones")
    }

    /// A season pack parses with a season but no episode.
    @Test func resolvesASeasonPackToTheSeasonContentKey() async {
        let search = CountingSearch(tvHits: [result(1399, name: "Game of Thrones")])
        let r = TMDBDownloadIdentityResolver(search: search)
        let id = await r.identity(filename: "Game.of.Thrones.S03.1080p.BluRay.x265", infoHash: "h3")
        #expect(id?.contentKey == "show:tmdb:1399:season:3")
        #expect(id?.kind == .show)
    }

    @Test func anUnmatchedTitleResolvesToNil() async {
        let r = TMDBDownloadIdentityResolver(search: CountingSearch())
        #expect(await r.identity(filename: "Some.Obscure.Thing.2019.mkv", infoHash: "h4") == nil)
    }

    /// The poll runs every 5 seconds. Without caching this is a TMDB search every 5 seconds
    /// per torrent, forever.
    @Test func aResolvedIdentityIsCachedByInfoHash() async {
        let search = CountingSearch(movieHits: [result(1, title: "X")])
        let r = TMDBDownloadIdentityResolver(search: search)
        _ = await r.identity(filename: "X.2020.mkv", infoHash: "same")
        _ = await r.identity(filename: "X.2020.mkv", infoHash: "same")
        _ = await r.identity(filename: "X.2020.mkv", infoHash: "same")
        #expect(search.movieCalls == 1)
    }

    /// A miss must be cached too — an unmatchable release name is otherwise the worst case,
    /// re-searching forever and never succeeding.
    @Test func aMissIsAlsoCached() async {
        let search = CountingSearch()
        let r = TMDBDownloadIdentityResolver(search: search)
        #expect(await r.identity(filename: "Nope.2019.mkv", infoHash: "miss") == nil)
        #expect(await r.identity(filename: "Nope.2019.mkv", infoHash: "miss") == nil)
        #expect(search.movieCalls == 1)
    }

    @Test func differentInfoHashesResolveIndependently() async {
        let search = CountingSearch(movieHits: [result(1, title: "X")])
        let r = TMDBDownloadIdentityResolver(search: search)
        _ = await r.identity(filename: "X.2020.mkv", infoHash: "a")
        _ = await r.identity(filename: "X.2020.mkv", infoHash: "b")
        #expect(search.movieCalls == 2)
    }

    /// A show with neither season nor episode is not a downloadable unit — there is no key for it.
    @Test func aShowWithNoSeasonOrEpisodeResolvesToNil() async {
        let search = CountingSearch(tvHits: [result(1399, name: "Game of Thrones")])
        let r = TMDBDownloadIdentityResolver(search: search)
        // No S/E tokens, so this parses as a movie-shaped name and takes the movie path,
        // which has no hits configured.
        #expect(await r.identity(filename: "Game.of.Thrones.1080p.mkv", infoHash: "h5") == nil)
    }
}
