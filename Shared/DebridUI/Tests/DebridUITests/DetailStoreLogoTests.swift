import Testing
import Foundation
import DebridCore
@testable import DebridUI

// MARK: - Fixtures

private enum LogoFakeError: Error { case boom }

private func movieHit(_ id: Int) -> SearchHit {
    SearchHit(result: TMDBSearchResult(id: id, title: "Dune: Part Two", name: nil,
                                       releaseDate: "2024-02-27", firstAirDate: nil,
                                       posterPath: nil, overview: nil, voteAverage: nil),
              kind: .movie)
}

private func showHit(_ id: Int) -> SearchHit {
    SearchHit(result: TMDBSearchResult(id: id, title: nil, name: "Breaking Bad",
                                       releaseDate: nil, firstAirDate: "2008-01-20",
                                       posterPath: nil, overview: nil, voteAverage: nil),
              kind: .show)
}

/// Details provider whose logo payload the test picks. `.failing` throws on both calls, to prove
/// a failed load leaves `logoPath` untouched rather than reaching for a partial answer.
private struct LogoDetails: MediaDetailsProviding {
    var logoPath: String?
    var failing = false

    private var images: TMDBImageSet {
        TMDBImageSet(backdrops: [], logos: logoPath.map {
            [TMDBImageRef(filePath: $0, languageCode: "en", voteAverage: 5, width: 500)]
        } ?? [])
    }

    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails {
        if failing { throw LogoFakeError.boom }
        return TMDBMovieDetails(id: tmdbID, title: "Dune: Part Two", releaseDate: "2024-02-27",
                                overview: "o", posterPath: nil, backdropPath: nil, runtime: 166,
                                genres: [], voteAverage: 8.2, images: images)
    }

    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails {
        if failing { throw LogoFakeError.boom }
        return TMDBTVDetails(id: tmdbID, name: "Breaking Bad", firstAirDate: "2008-01-20",
                             overview: "o", posterPath: nil, backdropPath: nil,
                             numberOfSeasons: 5, genres: [], voteAverage: 8.9, images: images)
    }

    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] { [] }
}

private actor NoWatch: WatchProgressProviding {
    func progress(forContentKey key: String, profileID: String) async throws -> WatchState? { nil }
    func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                durationSeconds: Double, finished: Bool, profileID: String) async throws {}
    func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] { [] }
    func deleteProgress(forContentKeys keys: [String]) async throws {}
}

/// The title page's own artwork arrives on the same details call `backdropPath` already rides —
/// no new request, no new cache.
@MainActor
@Suite struct DetailStoreLogoTests {
    @Test func aFilmsLogoArrivesWithItsDetails() async {
        let item = MediaItem.placeholder(for: movieHit(693134))
        let store = DetailStore(item: item, details: LogoDetails(logoPath: "/dune-logo.png"),
                                watch: NoWatch())

        await store.load()

        #expect(store.logoPath == "/dune-logo.png")
        #expect(store.richState == .loaded)
    }

    @Test func aShowsLogoArrivesToo() async {
        let item = MediaItem.placeholder(for: showHit(1396))
        let store = DetailStore(item: item, details: LogoDetails(logoPath: "/bb-logo.png"),
                                watch: NoWatch())

        await store.load()

        #expect(store.logoPath == "/bb-logo.png")
        #expect(store.richState == .loaded)
    }

    @Test func aFailedLoadLeavesNoLogo() async {
        let item = MediaItem.placeholder(for: movieHit(693134))
        let store = DetailStore(item: item, details: LogoDetails(failing: true), watch: NoWatch())

        await store.load()

        #expect(store.logoPath == nil)
        #expect(store.richState == .failed)
    }
}
