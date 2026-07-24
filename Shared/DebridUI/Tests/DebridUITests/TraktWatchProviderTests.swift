import Testing
import Foundation
import DebridCore
@testable import DebridUI

@Suite struct TraktWatchProviderTests {
    /// Fake of the API seam the provider depends on (not the concrete TraktClient).
    actor FakeTraktAPI: TraktWatchAPI {
        var playbackMoviesResult: [TraktPlaybackItem] = []
        var playbackEpisodesResult: [TraktPlaybackItem] = []
        var watchedMoviesResult: [TraktWatchedMovie] = []
        var watchedShowsResult: [TraktWatchedShow] = []
        var ratedMoviesResult: [TraktRatingItem] = []
        var ratedEpisodesResult: [TraktRatingItem] = []
        private(set) var history: [TraktMediaRef] = []
        private(set) var removedHistory: [TraktMediaRef] = []

        func playbackMovies() async throws -> [TraktPlaybackItem] { playbackMoviesResult }
        func playbackEpisodes() async throws -> [TraktPlaybackItem] { playbackEpisodesResult }
        func watchedMovies() async throws -> [TraktWatchedMovie] { watchedMoviesResult }
        func watchedShows() async throws -> [TraktWatchedShow] { watchedShowsResult }
        var ratedShowsResult: [TraktRatingItem] = []
        func ratedMovies() async throws -> [TraktRatingItem] { ratedMoviesResult }
        func ratedEpisodes() async throws -> [TraktRatingItem] { ratedEpisodesResult }
        func ratedShows() async throws -> [TraktRatingItem] { ratedShowsResult }
        func setRatedShows(_ v: [TraktRatingItem]) { ratedShowsResult = v }
        func addToHistory(_ refs: [TraktMediaRef]) async throws { history.append(contentsOf: refs) }
        func removeFromHistory(_ refs: [TraktMediaRef]) async throws { removedHistory.append(contentsOf: refs) }
        func scrobble(_ a: ScrobbleAction, ref: TraktMediaRef, progress: Double) async throws {}

        func setPlaybackMovies(_ v: [TraktPlaybackItem]) { playbackMoviesResult = v }
        func setWatchedMovies(_ v: [TraktWatchedMovie]) { watchedMoviesResult = v }
    }

    private func playbackMovie(tmdb: Int, progress: Double, at: String) -> TraktPlaybackItem {
        .init(progress: progress, pausedAt: at, type: "movie",
              movie: .init(ids: .init(tmdb: tmdb, trakt: 1)), show: nil, episode: nil)
    }

    private func source() -> MediaSource {
        MediaSource(torrentID: "t1", fileID: nil, restrictedLink: "rd://x",
                    parsed: ParsedRelease(title: "Dune"))
    }

    @Test func recentlyWatchedMapsPlaybackToWatchState() async throws {
        let api = FakeTraktAPI()
        await api.setPlaybackMovies([playbackMovie(tmdb: 27205, progress: 40, at: "2026-07-24T10:00:00.000Z")])
        let provider = TraktWatchProvider(api: api)
        try await provider.refresh()
        let rows = try await provider.recentlyWatched(limit: 10, profileID: "")
        #expect(rows.first?.contentKey == "movie:tmdb:27205")
        #expect(rows.first?.finished == false)
    }

    @Test func fractionExposedForResume() async throws {
        let api = FakeTraktAPI()
        await api.setPlaybackMovies([playbackMovie(tmdb: 27205, progress: 50, at: "2026-07-24T10:00:00.000Z")])
        let provider = TraktWatchProvider(api: api)
        try await provider.refresh()
        #expect(await provider.fraction(forContentKey: "movie:tmdb:27205") == 0.5)
    }

    @Test func watchedMovieReportsFinished() async throws {
        let api = FakeTraktAPI()
        await api.setWatchedMovies([.init(plays: 1, movie: .init(ids: .init(tmdb: 27205, trakt: 1)))])
        let provider = TraktWatchProvider(api: api)
        try await provider.refresh()
        let state = try await provider.progress(forContentKey: "movie:tmdb:27205", profileID: "")
        #expect(state?.finished == true)
    }

    // DetailStore/LibraryStore mark watched by calling `record(...finished:)` directly (their own
    // `setWatched` helper). These assert the provider routes that to Trakt history.
    @Test func showLevelRatingIsCachedUnderTheSeriesKey() async throws {
        let api = FakeTraktAPI()
        await api.setRatedShows([
            .init(rating: 10, type: "show", movie: nil,
                  show: .init(ids: .init(tmdb: 1399, trakt: 1)), episode: nil)
        ])
        let provider = TraktWatchProvider(api: api)
        try await provider.refresh()
        #expect(await provider.rating(forContentKey: "show:tmdb:1399") == 10)
    }

    @Test func recordFinishedAddsToHistory() async throws {
        let api = FakeTraktAPI()
        let provider = TraktWatchProvider(api: api)
        try await provider.record(contentKey: "movie:tmdb:27205", sourceKey: WatchKey.source(source()),
                                  positionSeconds: 0, durationSeconds: 0, finished: true, profileID: "")
        #expect(await api.history == [.movie(tmdb: 27205)])
    }

    @Test func recordUnfinishedRemovesFromHistory() async throws {
        let api = FakeTraktAPI()
        let provider = TraktWatchProvider(api: api)
        try await provider.record(contentKey: "movie:tmdb:27205", sourceKey: WatchKey.source(source()),
                                  positionSeconds: 0, durationSeconds: 0, finished: false, profileID: "")
        #expect(await api.removedHistory == [.movie(tmdb: 27205)])
    }
}
