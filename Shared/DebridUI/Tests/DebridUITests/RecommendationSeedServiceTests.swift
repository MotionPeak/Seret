import Testing
import Foundation
import DebridCore
@testable import DebridUI

@MainActor
struct RecommendationSeedServiceTests {
    private func item(_ id: Int, key: String) -> MediaItem {
        MediaItem(id: key, kind: .movie, title: "T\(id)", year: 2020, sources: [], seasons: [],
                  tmdbID: id, overview: nil)
    }

    final class FakeWatch: WatchProgressProviding, @unchecked Sendable {
        var states: [WatchState] = []
        func progress(forContentKey key: String, profileID: String) async throws -> WatchState? { nil }
        func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                    durationSeconds: Double, finished: Bool, profileID: String) async throws {}
        func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] { states }
        func deleteProgress(forContentKeys keys: [String]) async throws {}
    }

    private func watched(_ contentKey: String) -> WatchState {
        WatchState(contentKey: contentKey, sourceKey: "s", positionSeconds: 10,
                   durationSeconds: 100, finished: false, updatedAt: Date(timeIntervalSince1970: 1))
    }

    @Test func watchedSeedsComeFirstThenLibrary() async {
        let lib = LibraryStore(library: NoopLibrary())
        lib.setForTest(movies: [item(1, key: "movie:tmdb:1"), item(2, key: "movie:tmdb:2")], shows: [])
        let watch = FakeWatch()
        watch.states = [watched("movie:tmdb:2")]
        let svc = RecommendationSeedService(watch: watch, library: lib, profileID: { "p1" })
        let seeds = await svc.seeds(kind: .movie, limit: 10)
        #expect(seeds.first == RecommendationSeed(tmdbID: 2, title: "T2", watched: true))
        #expect(seeds.contains(RecommendationSeed(tmdbID: 1, title: "T1", watched: false)))
        #expect(seeds.count == 2)   // no dup of tmdb 2
    }

    @Test func respectsLimit() async {
        let lib = LibraryStore(library: NoopLibrary())
        lib.setForTest(movies: (1...5).map { item($0, key: "movie:tmdb:\($0)") }, shows: [])
        let svc = RecommendationSeedService(watch: FakeWatch(), library: lib, profileID: { "p1" })
        #expect(await svc.seeds(kind: .movie, limit: 3).count == 3)
    }
}

private struct NoopLibrary: LibraryProviding {
    func loadCached() -> [MediaItem]? { nil }
    func refresh() async throws -> [MediaItem] { [] }
    func remove(_ item: MediaItem) async throws {}
    func removeVersion(_ item: MediaItem, source: MediaSource) async throws {}
}
