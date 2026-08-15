import Testing
import Foundation
import DebridCore
@testable import DebridUI

private actor CountingWatch: WatchProgressProviding {
    private var rows: [String: WatchState]
    private(set) var batchCalls = 0
    init(_ finished: [String]) {
        rows = Dictionary(uniqueKeysWithValues: finished.map {
            ($0, WatchState(contentKey: $0, sourceKey: "", positionSeconds: 0,
                            durationSeconds: 0, finished: true,
                            updatedAt: Date(timeIntervalSince1970: 0)))
        })
    }
    func progress(forContentKey key: String, profileID: String) async throws -> WatchState? { rows[key] }
    func progress(forContentKeys keys: [String], profileID: String) async throws -> [String: WatchState] {
        batchCalls += 1
        return rows.filter { keys.contains($0.key) }
    }
    func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                durationSeconds: Double, finished: Bool, profileID: String) async throws {}
    func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] { [] }
    func deleteProgress(forContentKeys keys: [String]) async throws {}
    func calls() -> Int { batchCalls }
}

@MainActor
@Suite struct TileWatchMarksTests {
    private func hit(_ id: Int, _ kind: MediaKind) -> SearchHit {
        SearchHit(result: TMDBSearchResult(id: id, title: "T\(id)", name: "T\(id)",
                                           releaseDate: "2012-01-01", firstAirDate: nil,
                                           posterPath: nil, overview: nil, voteAverage: nil),
                  kind: kind)
    }

    @Test func readsAWholeGridInOneCall() async {
        let watch = CountingWatch(["movie:tmdb:2"])
        let marks = TileWatchMarks(watch: { watch }, profileID: { "" })
        await marks.load([hit(1, .movie), hit(2, .movie), hit(3, .movie)])
        #expect(marks.isWatched(hit(2, .movie)))
        #expect(!marks.isWatched(hit(1, .movie)))
        #expect(await watch.calls() == 1)
    }

    @Test func doesNotRefetchKeysItAlreadyKnows() async {
        let watch = CountingWatch(["movie:tmdb:2"])
        let marks = TileWatchMarks(watch: { watch }, profileID: { "" })
        await marks.load([hit(1, .movie), hit(2, .movie)])
        await marks.load([hit(1, .movie), hit(2, .movie)])
        #expect(await watch.calls() == 1)
    }

    @Test func fetchesOnlyTheNewKeysWhenTheGridGrows() async {
        let watch = CountingWatch([])
        let marks = TileWatchMarks(watch: { watch }, profileID: { "" })
        await marks.load([hit(1, .movie)])
        await marks.load([hit(1, .movie), hit(2, .movie)])
        #expect(await watch.calls() == 2)
    }

    @Test func moviesAndShowsAreDifferentTitles() async {
        let watch = CountingWatch(["show:tmdb:5"])
        let marks = TileWatchMarks(watch: { watch }, profileID: { "" })
        await marks.load([hit(5, .movie), hit(5, .show)])
        #expect(marks.isWatched(hit(5, .show)))
        #expect(!marks.isWatched(hit(5, .movie)))
    }

    @Test func setUpdatesImmediatelyWithoutARead() async {
        let watch = CountingWatch([])
        let marks = TileWatchMarks(watch: { watch }, profileID: { "" })
        await marks.load([hit(1, .movie)])
        marks.set(true, for: hit(1, .movie))
        #expect(marks.isWatched(hit(1, .movie)))
        marks.set(false, for: hit(1, .movie))
        #expect(!marks.isWatched(hit(1, .movie)))
    }

    @Test func withoutABackendNothingIsWatched() async {
        let marks = TileWatchMarks(watch: { nil }, profileID: { "" })
        await marks.load([hit(1, .movie)])
        #expect(!marks.isWatched(hit(1, .movie)))
    }

    /// The shell builds this object when it first appears — which is BEFORE sign-in has produced a
    /// watch store. Capturing the store by value therefore captured `nil` for the whole session and
    /// no browse or search poster ever showed a watched tick. It has to resolve the store on each
    /// read instead.
    @Test func aStoreThatArrivesAfterSignInIsStillUsed() async {
        let watch = CountingWatch(["movie:tmdb:1"])
        var live: (any WatchProgressProviding)?          // nil at launch, as it really is
        let marks = TileWatchMarks(watch: { live }, profileID: { "" })
        let tile = hit(1, .movie)

        await marks.load([tile])                         // signed out — nothing to read
        #expect(marks.isWatched(tile) == false)

        live = watch                                     // sign-in completes
        await marks.load([tile])

        #expect(marks.isWatched(tile) == true)
    }
}
