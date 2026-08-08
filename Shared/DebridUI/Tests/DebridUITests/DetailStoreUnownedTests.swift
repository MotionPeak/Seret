import Testing
import Foundation
import DebridCore
@testable import DebridUI

private enum FakeError: Error { case boom }

private final class UnownedDetails: MediaDetailsProviding {
    let seasons: [Int: [TMDBEpisodeDetails]]
    init(seasons: [Int: [TMDBEpisodeDetails]] = [:]) { self.seasons = seasons }
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails { throw FakeError.boom }
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails {
        TMDBTVDetails(id: tmdbID, name: "Game of Thrones", firstAirDate: "2011-04-17",
                      overview: "o", posterPath: "/p.jpg", backdropPath: "/b.jpg",
                      numberOfSeasons: 2, genres: [], voteAverage: 8.4)
    }
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] {
        seasons[season] ?? []
    }
}

private actor RecordingWatch: WatchProgressProviding {
    private(set) var rows: [String: WatchState] = [:]
    func progress(forContentKey key: String, profileID: String) async throws -> WatchState? { rows[key] }
    func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                durationSeconds: Double, finished: Bool, profileID: String) async throws {
        rows[contentKey] = WatchState(contentKey: contentKey, sourceKey: sourceKey,
                                      positionSeconds: positionSeconds,
                                      durationSeconds: durationSeconds, finished: finished,
                                      updatedAt: Date(timeIntervalSince1970: 0))
    }
    func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] { [] }
    func deleteProgress(forContentKeys keys: [String]) async throws {}
    func sourceKey(for key: String) -> String? { rows[key]?.sourceKey }
}

private func episodeMeta(_ n: Int) -> TMDBEpisodeDetails {
    TMDBEpisodeDetails(episodeNumber: n, name: "Episode \(n)", overview: nil,
                       stillPath: nil, runtime: 55, airDate: nil)
}

private func movieHit(_ id: Int) -> SearchHit {
    SearchHit(result: TMDBSearchResult(id: id, title: "The Hunger Games", name: nil,
                                       releaseDate: "2012-03-12", firstAirDate: nil,
                                       posterPath: nil, overview: nil, voteAverage: nil),
              kind: .movie)
}

private func showHit(_ id: Int) -> SearchHit {
    SearchHit(result: TMDBSearchResult(id: id, title: nil, name: "Game of Thrones",
                                       releaseDate: nil, firstAirDate: "2011-04-17",
                                       posterPath: nil, overview: nil, voteAverage: nil),
              kind: .show)
}

@MainActor
@Suite struct DetailStoreUnownedTests {
    @Test func marksAMovieWatchedWithNoSource() async {
        let item = MediaItem.placeholder(for: movieHit(70160))
        let watch = RecordingWatch()
        let store = DetailStore(item: item, details: UnownedDetails(), watch: watch)

        await store.setWatched(true, contentKey: item.id, source: nil)

        #expect(store.watchState(forKey: item.id)?.finished == true)
        #expect(await watch.sourceKey(for: item.id) == "")
    }

    @Test func anUnownedShowStillGetsEpisodeCheckmarks() async {
        let item = MediaItem.placeholder(for: showHit(1399))
        let watch = RecordingWatch()
        // Seed episode 2 of season 1 as already watched, keyed the un-owned way.
        try? await watch.record(contentKey: "show:tmdb:1399:s1e2", sourceKey: "",
                                positionSeconds: 0, durationSeconds: 0, finished: true,
                                profileID: "")
        let details = UnownedDetails(seasons: [1: [episodeMeta(1), episodeMeta(2), episodeMeta(3)]])
        let store = DetailStore(item: item, details: details, watch: watch)

        await store.load()

        #expect(store.episodes(forSeason: 1).count == 3)
        #expect(store.watchState(forKey: "show:tmdb:1399:s1e2")?.finished == true)
        #expect(store.watchState(forKey: "show:tmdb:1399:s1e1") == nil)
    }

    @Test func reloadWatchSeesEpisodeProgressRecordedSinceTheScreenOpened() async {
        // The season read de-duplicates by key set so the initial load queries once. This proves it
        // cannot also swallow the re-read the player triggers on dismiss — which would leave the
        // episode you just finished unticked until the screen was reopened.
        let item = MediaItem.placeholder(for: showHit(1399))
        let watch = RecordingWatch()
        let details = UnownedDetails(seasons: [1: [episodeMeta(1), episodeMeta(2)]])
        let store = DetailStore(item: item, details: details, watch: watch)
        await store.load()
        #expect(store.watchState(forKey: "show:tmdb:1399:s1e1") == nil)

        try? await watch.record(contentKey: "show:tmdb:1399:s1e1", sourceKey: "",
                                positionSeconds: 0, durationSeconds: 0, finished: true, profileID: "")
        await store.reloadWatch()

        #expect(store.watchState(forKey: "show:tmdb:1399:s1e1")?.finished == true)
    }

    @Test func nextEpisodeTargetIsTheFirstUnwatchedOfAnUnownedShow() async {
        let item = MediaItem.placeholder(for: showHit(1399))
        let watch = RecordingWatch()
        try? await watch.record(contentKey: "show:tmdb:1399:s1e1", sourceKey: "",
                                positionSeconds: 0, durationSeconds: 0, finished: true, profileID: "")
        let details = UnownedDetails(seasons: [1: [episodeMeta(1), episodeMeta(2)]])
        let store = DetailStore(item: item, details: details, watch: watch)

        await store.load()
        let target = store.nextEpisodeTarget()

        #expect(target?.season == 1)
        #expect(target?.number == 2)      // e1 is finished
    }

    @Test func nextEpisodeTargetFallsBackToTheFirstEpisode() async {
        let item = MediaItem.placeholder(for: showHit(1399))
        let details = UnownedDetails(seasons: [1: [episodeMeta(1), episodeMeta(2)]])
        let store = DetailStore(item: item, details: details, watch: RecordingWatch())

        await store.load()

        #expect(store.nextEpisodeTarget()?.number == 1)
    }
}
