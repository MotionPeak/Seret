import Testing
import Foundation
import DebridCore
@testable import DebridUI

/// Mutable "now" for cooldown tests. Single-task test usage only.
private final class MutableClock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_000)
}

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
        func watchedMovies() async throws -> [TraktWatchedMovie] {
            watchedMoviesCallCount += 1
            if failReads { throw HTTPError.status(code: 429, body: "rate limited") }
            return watchedMoviesResult
        }
        func watchedShows() async throws -> [TraktWatchedShow] { watchedShowsResult }
        var ratedShowsResult: [TraktRatingItem] = []
        private(set) var ratedMoviesCallCount = 0
        func setRatedMovies(_ v: [TraktRatingItem]) { ratedMoviesResult = v }
        func ratedMovies() async throws -> [TraktRatingItem] {
            ratedMoviesCallCount += 1
            return ratedMoviesResult
        }
        func ratedEpisodes() async throws -> [TraktRatingItem] { ratedEpisodesResult }
        func ratedShows() async throws -> [TraktRatingItem] { ratedShowsResult }
        func setRatedShows(_ v: [TraktRatingItem]) { ratedShowsResult = v }
        func addToHistory(_ refs: [TraktMediaRef]) async throws { history.append(contentsOf: refs) }
        func removeFromHistory(_ refs: [TraktMediaRef]) async throws { removedHistory.append(contentsOf: refs) }
        func scrobble(_ a: ScrobbleAction, ref: TraktMediaRef, progress: Double) async throws {}

        func setPlaybackMovies(_ v: [TraktPlaybackItem]) { playbackMoviesResult = v }
        func setWatchedMovies(_ v: [TraktWatchedMovie]) { watchedMoviesResult = v }
        func setWatchedShows(_ v: [TraktWatchedShow]) { watchedShowsResult = v }

        struct FakeError: Error {}

        var communityRatingResult: TraktCommunityRating?
        var communityRatingFails = false
        private(set) var communityRatingCallCount = 0
        func setCommunityRating(_ v: TraktCommunityRating?) { communityRatingResult = v }
        func setCommunityRatingFails(_ v: Bool) { communityRatingFails = v }
        func communityRating(imdbID: String, kind: MediaKind) async throws -> TraktCommunityRating? {
            communityRatingCallCount += 1
            if communityRatingFails { throw FakeError() }
            return communityRatingResult
        }

        /// Makes every cache-filling read throw, so a test can watch what the provider does when
        /// Trakt is refusing it (a 429, an expired token, a dead network).
        var failReads = false
        private(set) var watchedMoviesCallCount = 0
        func setFailReads(_ v: Bool) { failReads = v }

        var firstHistoryDateResult: Date?
        private(set) var historyCalls: [(type: String, traktID: Int)] = []
        func setFirstHistoryDate(_ v: Date?) { firstHistoryDateResult = v }
        func firstHistoryDate(type: String, traktID: Int) async throws -> Date? {
            historyCalls.append((type, traktID))
            return firstHistoryDateResult
        }
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

    /// Trakt sends `paused_at` both with and without fractional seconds — this slice proved the
    /// shape varies PER ENDPOINT, so neither can be assumed. A fractional-only parse turns a plain
    /// timestamp into `.distantPast`, which sorts that title to the BACK of `order` and drops it off
    /// Continue Watching entirely once the rail's `prefix(limit)` bites. Hence a position assertion,
    /// not just a parse assertion.
    @Test func plainPausedAtStillSortsNewestFirstOnTheRail() async throws {
        let api = FakeTraktAPI()
        await api.setPlaybackMovies([
            playbackMovie(tmdb: 111, progress: 20, at: "2026-07-20T10:00:00.000Z"),  // older, fractional
            playbackMovie(tmdb: 222, progress: 30, at: "2026-07-24T10:00:00Z"),      // NEWER, plain
        ])
        let provider = TraktWatchProvider(api: api)
        try await provider.refresh()

        let rows = try await provider.recentlyWatched(limit: 10, profileID: "")
        #expect(rows.map(\.contentKey) == ["movie:tmdb:222", "movie:tmdb:111"])
        // And it survives a rail that only shows one card.
        let topOnly = try await provider.recentlyWatched(limit: 1, profileID: "")
        #expect(topOnly.map(\.contentKey) == ["movie:tmdb:222"])
    }

    /// Rate-limit storm guard. A failed fill leaves the cache empty on purpose (so a later read can
    /// retry rather than caching an empty answer) — but `progress(forContentKeys:)` loops per key,
    /// so with no cooldown ONE library repaint fires a full 7-endpoint fan-out PER TITLE. That turns
    /// a single transient 429 into hundreds of calls, which guarantees more 429s. One failing round
    /// must cost one fan-out, not one per row.
    @Test func aFailedFillDoesNotRefetchOncePerTitle() async throws {
        let api = FakeTraktAPI()
        await api.setFailReads(true)
        let provider = TraktWatchProvider(api: api)

        let keys = (1...12).map { "movie:tmdb:\($0)" }
        _ = try? await provider.progress(forContentKeys: keys, profileID: "")

        #expect(await api.watchedMoviesCallCount == 1)
    }

    /// The cooldown must not become a lockout: once it lapses, a read fetches again (Trakt recovers,
    /// the user shouldn't have to relaunch).
    @Test func theCooldownExpiresAndReadsResume() async throws {
        let api = FakeTraktAPI()
        await api.setFailReads(true)
        let clock = MutableClock()
        let provider = TraktWatchProvider(api: api, retryCooldown: 60, now: { clock.date })

        _ = try? await provider.progress(forContentKey: "movie:tmdb:1", profileID: "")
        _ = try? await provider.progress(forContentKey: "movie:tmdb:2", profileID: "")
        #expect(await api.watchedMoviesCallCount == 1)          // second read suppressed

        clock.date += 61
        await api.setFailReads(false)
        await api.setWatchedMovies([.init(plays: 1, movie: .init(ids: .init(tmdb: 3, trakt: 1)))])
        let state = try await provider.progress(forContentKey: "movie:tmdb:3", profileID: "")
        #expect(await api.watchedMoviesCallCount == 2)          // cooldown lapsed → fetched again
        #expect(state?.finished == true)                        // and the data actually landed
    }

    /// Settings ▸ Sync Now is an explicit user action: it must bypass the cooldown, or "wait a
    /// minute and retry" would be a lie for up to a minute.
    @Test func syncNowBypassesTheCooldown() async throws {
        let api = FakeTraktAPI()
        await api.setFailReads(true)
        let provider = TraktWatchProvider(api: api)

        _ = try? await provider.progress(forContentKey: "movie:tmdb:1", profileID: "")
        #expect(await api.watchedMoviesCallCount == 1)
        await api.setFailReads(false)
        try await provider.forceRefresh()
        #expect(await api.watchedMoviesCallCount == 2)
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
    /// Regression: the sign-in refresh is fire-and-forget, so a screen opened before it lands used
    /// to read an empty cache, show "no rating", and never re-read — a rating looked like it hadn't
    /// persisted across a relaunch. Reads must lazily warm the cache themselves.
    @Test func readsWarmTheCacheWithoutAnExplicitRefresh() async throws {
        let api = FakeTraktAPI()
        await api.setRatedMovies([
            .init(rating: 9, type: "movie",
                  movie: .init(ids: .init(tmdb: 1417, trakt: 1)), show: nil, episode: nil)
        ])
        await api.setPlaybackMovies([playbackMovie(tmdb: 27205, progress: 50, at: "2026-07-24T10:00:00.000Z")])
        let provider = TraktWatchProvider(api: api)
        // NOTE: no refresh() call — exactly what a Detail screen opened right after launch does.
        #expect(await provider.rating(forContentKey: "movie:tmdb:1417") == 9)
        #expect(await provider.fraction(forContentKey: "movie:tmdb:27205") == 0.5)
        #expect(try await provider.recentlyWatched(limit: 5, profileID: "").count == 1)
    }

    @Test func concurrentColdReadsFetchOnlyOnce() async throws {
        let api = FakeTraktAPI()
        await api.setRatedMovies([
            .init(rating: 7, type: "movie",
                  movie: .init(ids: .init(tmdb: 1, trakt: 1)), show: nil, episode: nil)
        ])
        let provider = TraktWatchProvider(api: api)
        async let a = provider.rating(forContentKey: "movie:tmdb:1")
        async let b = provider.rating(forContentKey: "movie:tmdb:1")
        async let c = provider.rating(forContentKey: "movie:tmdb:1")
        #expect(await [a, b, c] == [7, 7, 7])
        #expect(await api.ratedMoviesCallCount == 1)      // coalesced, not three fetches
    }

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
