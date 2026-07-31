import Testing
import Foundation
import DebridCore
@testable import DebridUI

// MARK: - Fixtures (file scope: the suite is @MainActor, its members can't seed nonisolated defaults)

private func castMember(_ id: Int, _ name: String) -> TMDBCastMember {
    TMDBCastMember(id: id, name: name, character: "Someone", profilePath: "/p.jpg", order: 0)
}
private func similarResult(_ id: Int, _ title: String) -> TMDBSearchResult {
    TMDBSearchResult(id: id, title: title, name: nil, releaseDate: "2021-01-01",
                     firstAirDate: nil, posterPath: "/s.jpg", overview: "o", voteAverage: 7.0)
}

/// The rich-title-page fields on `DetailStore`: TMDB cast/director/creators/similar (free with the
/// details call), the Trakt community score (a FALLBACK when OMDb has nothing), and the watch
/// history rollup. Every extra rides on providers obtained by downcast — nothing new is injected.
@MainActor
@Suite struct DetailStoreRichTests {
    private func movie() -> MediaItem {
        MediaItem(id: "movie:tmdb:99", kind: .movie, title: "M", year: 2020,
                  sources: [], seasons: [], tmdbID: 99)
    }
    private func show() -> MediaItem {
        MediaItem(id: "show:tmdb:1399", kind: .show, title: "S", year: 2011,
                  sources: [], seasons: [], tmdbID: 1399)
    }

    /// Details provider whose payloads the test picks. Defaults carry the rich fields.
    struct RichDetails: MediaDetailsProviding {
        var movie = TMDBMovieDetails(
            id: 99, title: "M", releaseDate: "2020-01-01", overview: "o", posterPath: nil,
            backdropPath: nil, runtime: 100, genres: [], voteAverage: 7.0,
            originalLanguage: "en", imdbID: "tt123",
            cast: [castMember(1, "Timothée Chalamet")],
            director: "Denis Villeneuve",
            similar: [similarResult(42, "Arrival")])
        var tv = TMDBTVDetails(
            id: 1399, name: "S", firstAirDate: "2011-01-01", overview: "o", posterPath: nil,
            backdropPath: nil, numberOfSeasons: 1, genres: [], voteAverage: 8.0,
            originalLanguage: "en", imdbID: "tt777",
            cast: [castMember(2, "Peter Dinklage")],
            creators: ["David Benioff", "D. B. Weiss"],
            similar: [similarResult(77, "Rome")])

        func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails { movie }
        func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails { tv }
        func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] { [] }
    }

    /// A watch backend that ALSO supplies the community score and the history rollup — exactly the
    /// shape of the real `TraktWatchProvider`, so the store's downcasts pick both up.
    final class FakeRichWatch: WatchProgressProviding, CommunityRatingProviding,
                               WatchSummaryProviding, @unchecked Sendable {
        var community: Double?
        var summary: WatchSummary?
        var since: Date?
        private(set) var communityCalls = 0

        init(community: Double? = nil, summary: WatchSummary? = nil, since: Date? = nil) {
            self.community = community; self.summary = summary; self.since = since
        }

        func progress(forContentKey key: String, profileID: String) async throws -> WatchState? { nil }
        func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                    durationSeconds: Double, finished: Bool, profileID: String) async throws {}
        func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] { [] }
        func deleteProgress(forContentKeys keys: [String]) async throws {}

        func communityRating(imdbID: String, kind: MediaKind) async -> Double? {
            communityCalls += 1
            return community
        }
        func watchSummary(forContentKey key: String) async -> WatchSummary? { summary }
        func historySince(forContentKey key: String) async -> Date? { since }
    }

    struct StubRatings: RatingsProviding {
        let value: OMDbRatings
        func ratings(imdbID: String) async throws -> OMDbRatings { value }
    }

    // MARK: - TMDB rich fields

    @Test func loadPopulatesCastDirectorSimilarForAMovie() async {
        let store = DetailStore(item: movie(), details: RichDetails(), watch: nil)
        await store.load()
        #expect(store.cast.first?.name == "Timothée Chalamet")
        #expect(store.director == "Denis Villeneuve")
        #expect(store.similar.first?.id == 42)
    }

    @Test func loadPopulatesCastCreatorsSimilarForAShow() async {
        let store = DetailStore(item: show(), details: RichDetails(), watch: nil)
        await store.load()
        #expect(store.cast.first?.name == "Peter Dinklage")
        #expect(store.creators == ["David Benioff", "D. B. Weiss"])
        #expect(store.similar.first?.id == 77)
    }

    // MARK: - Community score

    /// The production case: no OMDb key configured (`ratings == nil`). The Trakt score must STILL
    /// load — it exists precisely to fill that gap.
    @Test func communityScoreLoadsEvenWhenOMDbIsUnconfigured() async {
        let watch = FakeRichWatch(community: 7.7)
        let store = DetailStore(item: movie(), details: RichDetails(), watch: watch, ratings: nil)
        await store.load()
        #expect(store.communityScore == 7.7)
        #expect(watch.communityCalls == 1)
    }

    /// A fallback, not an always-on fetch: with real OMDb chips there is nothing to fill in.
    @Test func communityScoreIsNotFetchedWhenOMDbAlreadyHasRatings() async {
        let watch = FakeRichWatch(community: 7.7)
        let omdb = StubRatings(value: OMDbRatings(imdb: 8.7, rottenTomatoes: 88, metacritic: 73))
        let store = DetailStore(item: movie(), details: RichDetails(), watch: watch, ratings: omdb)
        await store.load()
        #expect(store.ratings?.hasAny == true)
        #expect(watch.communityCalls == 0)
        #expect(store.communityScore == nil)
    }

    /// OMDb answered but with nothing usable → the community score still fills the gap.
    @Test func communityScoreFillsInWhenOMDbHasNoScores() async {
        let watch = FakeRichWatch(community: 6.4)
        let omdb = StubRatings(value: OMDbRatings(imdb: nil, rottenTomatoes: nil, metacritic: nil))
        let store = DetailStore(item: movie(), details: RichDetails(), watch: watch, ratings: omdb)
        await store.load()
        #expect(store.communityScore == 6.4)
        #expect(watch.communityCalls == 1)
    }

    // MARK: - Watch history rollup

    @Test func watchSummaryAndHistorySinceLoad() async {
        let watch = FakeRichWatch(summary: WatchSummary(plays: 3, lastWatchedAt: Date(timeIntervalSince1970: 100)),
                                  since: Date(timeIntervalSince1970: 50))
        let store = DetailStore(item: movie(), details: RichDetails(), watch: watch)
        await store.load()
        await store.loadWatchSummary()
        #expect(store.watchSummary?.plays == 3)
        #expect(store.historySince != nil)
    }

    // MARK: - Degradation

    @Test func richFieldsDegradeSilentlyWithoutProviders() async {
        let store = DetailStore(item: movie(), details: RichDetails(), watch: nil, ratings: nil)
        await store.load()
        await store.loadWatchSummary()
        #expect(store.richState == .loaded)
        #expect(store.communityScore == nil)
        #expect(store.watchSummary == nil)
        #expect(store.historySince == nil)
        #expect(store.ratingsState == .idle)
    }
}
