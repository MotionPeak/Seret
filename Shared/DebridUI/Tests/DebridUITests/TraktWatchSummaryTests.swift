import Testing
import Foundation
import DebridCore
@testable import DebridUI

/// The Detail page's richer history rollup: play counts, last-watched, first-watched, and the
/// Trakt community score — all optional capabilities the provider exposes via downcast.
@Suite struct TraktWatchSummaryTests {
    private typealias FakeTraktAPI = TraktWatchProviderTests.FakeTraktAPI

    /// `TraktWatchedShow` has no public memberwise init (only the synthesized `Decodable`),
    /// so shows are built the way the real code gets them: by decoding a Trakt payload.
    private func watchedShows(_ json: String) throws -> [TraktWatchedShow] {
        try JSONDecoder().decode([TraktWatchedShow].self, from: Data(json.utf8))
    }

    @Test func retainsPlaysAndLastWatchedForMovie() async throws {
        let api = FakeTraktAPI()
        // NOTE: a NON-fractional timestamp — Trakt sends both shapes.
        await api.setWatchedMovies([
            .init(plays: 3, lastWatchedAt: "2023-05-01T00:00:00Z",
                  movie: .init(ids: .init(tmdb: 27205, trakt: 481)))
        ])
        let provider = TraktWatchProvider(api: api)
        try await provider.refresh()

        let summary = await provider.watchSummary(forContentKey: "movie:tmdb:27205")
        #expect(summary?.plays == 3)
        #expect(summary?.lastWatchedAt != nil)
        let expected = ISO8601DateFormatter().date(from: "2023-05-01T00:00:00Z")
        #expect(summary?.lastWatchedAt == expected)
    }

    @Test func retainsSummedPlaysAndLastWatchedForShow() async throws {
        let api = FakeTraktAPI()
        await api.setWatchedShows(try watchedShows("""
        [{"show": {"ids": {"tmdb": 1399, "trakt": 1390}},
          "last_watched_at": "2024-01-02T03:04:05.000Z",
          "seasons": [{"number": 1, "episodes": [{"number": 1, "plays": 2},
                                                 {"number": 2, "plays": 1}]}]}]
        """))
        let provider = TraktWatchProvider(api: api)
        try await provider.refresh()

        let summary = await provider.watchSummary(forContentKey: "show:tmdb:1399")
        #expect(summary?.plays == 3)                    // summed across episodes
        #expect(summary?.lastWatchedAt != nil)
        // The per-episode watched set must keep working exactly as before.
        let ep = try await provider.progress(forContentKey: "show:tmdb:1399:s1e2", profileID: "")
        #expect(ep?.finished == true)
    }

    @Test func communityRatingIsMemoizedPerIMDbID() async throws {
        let api = FakeTraktAPI()
        await api.setCommunityRating(TraktCommunityRating(rating: 8.1, votes: 5))
        let provider = TraktWatchProvider(api: api)

        let first = await provider.communityRating(imdbID: "tt0816692", kind: .movie)
        let second = await provider.communityRating(imdbID: "tt0816692", kind: .movie)
        #expect(first == 8.1)
        #expect(second == 8.1)
        #expect(await api.communityRatingCallCount == 1)   // in-session memo, one network hop
    }

    @Test func historySinceUsesTheRetainedTraktID() async throws {
        let api = FakeTraktAPI()
        let firstWatch = Date(timeIntervalSince1970: 1_500_000_000)
        await api.setFirstHistoryDate(firstWatch)
        await api.setWatchedMovies([
            .init(plays: 1, lastWatchedAt: "2023-05-01T00:00:00Z",
                  movie: .init(ids: .init(tmdb: 27205, trakt: 481)))
        ])
        let provider = TraktWatchProvider(api: api)
        try await provider.refresh()

        #expect(await provider.historySince(forContentKey: "movie:tmdb:27205") == firstWatch)
        let calls = await api.historyCalls
        #expect(calls.count == 1)
        #expect(calls.first?.type == "movies")
        #expect(calls.first?.traktID == 481)              // the id retained during refresh
    }

    @Test func unknownContentKeyYieldsNilSummary() async throws {
        let api = FakeTraktAPI()
        let provider = TraktWatchProvider(api: api)
        try await provider.refresh()
        #expect(await provider.watchSummary(forContentKey: "movie:tmdb:999999") == nil)
        #expect(await provider.historySince(forContentKey: "movie:tmdb:999999") == nil)
        #expect(await api.historyCalls.isEmpty)           // no id retained → no network hop
    }
}
