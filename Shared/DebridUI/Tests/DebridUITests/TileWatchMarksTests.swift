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
    /// Somewhere else — a title page, the library grid — marked it unwatched.
    func unfinish(_ key: String) { rows[key] = nil }
}

/// Answers from a snapshot taken when the read STARTS, and holds the answer until released — a
/// read in flight while the viewer long-presses a poster.
private actor GatedWatch: WatchProgressProviding {
    private var waiter: CheckedContinuation<Void, Never>?
    private(set) var started = false
    func progress(forContentKey key: String, profileID: String) async throws -> WatchState? { nil }
    func progress(forContentKeys keys: [String], profileID: String) async throws -> [String: WatchState] {
        started = true
        await withCheckedContinuation { waiter = $0 }
        return [:]                                       // what it read: nothing finished
    }
    func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                durationSeconds: Double, finished: Bool, profileID: String) async throws {}
    func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] { [] }
    func deleteProgress(forContentKeys keys: [String]) async throws {}
    func release() { waiter?.resume(); waiter = nil }
    func hasStarted() -> Bool { started }
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

    /// A finished answer was never read again — "it cannot become unfinished on its own" — but a
    /// mark made ANYWHERE else (the title page, the library grid, Continue Watching) does exactly
    /// that, and the poster kept its tick, dimmed, until the app was relaunched. Every load reads
    /// the grid again; it is one batched local read.
    @Test func aTitleUnmarkedElsewhereLosesItsTick() async {
        let watch = CountingWatch(["movie:tmdb:1"])
        let marks = TileWatchMarks(watch: { watch }, profileID: { "" })
        await marks.load([hit(1, .movie)])
        #expect(marks.isWatched(hit(1, .movie)))
        await watch.unfinish("movie:tmdb:1")
        await marks.load([hit(1, .movie)])
        #expect(!marks.isWatched(hit(1, .movie)))
    }

    /// …but a read that began before a long-press mark answers a question asked before it, and must
    /// not undo the tick the viewer just placed.
    @Test func aReadAlreadyInFlightDoesNotUndoAMarkJustMade() async {
        let watch = GatedWatch()
        let marks = TileWatchMarks(watch: { watch }, profileID: { "" })
        let load = Task { await marks.load([hit(1, .movie)]) }
        while !(await watch.hasStarted()) { await Task.yield() }
        marks.set(true, for: hit(1, .movie))
        await watch.release()
        await load.value
        #expect(marks.isWatched(hit(1, .movie)))
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

    /// A grid that had already looked at a title never looked again, so watching something and
    /// coming back to Browse or Find showed no tick until the app was relaunched.
    @Test func aTitleWatchedThisSessionGrowsItsTick() async {
        let watch = MutableWatch()
        let marks = TileWatchMarks(watch: { watch }, profileID: { "p1" })
        let subject = hit(42, .movie)

        await marks.load([subject])
        #expect(marks.isWatched(subject) == false)

        await watch.markFinished(subject.contentKey)      // …as the player would, mid-session
        await marks.load([subject])

        #expect(marks.isWatched(subject) == true)
    }

    /// What a grid appearance costs: ONE batched read, however many posters it holds. (Finished
    /// titles used to be skipped to save even that, which is what kept a tick on a title marked
    /// unwatched elsewhere — see `aTitleUnmarkedElsewhereLosesItsTick`.)
    @Test func eachLoadIsOneBatchedReadForTheWholeGrid() async {
        let watch = MutableWatch()
        let grid = (1...30).map { hit($0, .movie) }
        await watch.markFinished(grid[4].contentKey)
        let marks = TileWatchMarks(watch: { watch }, profileID: { "p1" })

        await marks.load(grid)
        await marks.load(grid)

        #expect(marks.isWatched(grid[4]) == true)
        #expect(await watch.batchReads == 2)
    }
}

/// A watch double whose answers can change between reads, like the real store's do.
private actor MutableWatch: WatchProgressProviding {
    private var finished: Set<String> = []
    private(set) var batchReads = 0

    func markFinished(_ key: String) { finished.insert(key) }

    func progress(forContentKey key: String, profileID: String) async throws -> WatchState? {
        finished.contains(key) ? Self.state(key) : nil
    }
    func progress(forContentKeys keys: [String], profileID: String) async throws -> [String: WatchState] {
        batchReads += 1
        var out: [String: WatchState] = [:]
        for key in keys where finished.contains(key) { out[key] = Self.state(key) }
        return out
    }
    func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                durationSeconds: Double, finished: Bool, profileID: String) async throws {}
    func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] { [] }
    func deleteProgress(forContentKeys keys: [String]) async throws {}

    private static func state(_ key: String) -> WatchState {
        WatchState(contentKey: key, sourceKey: "s", positionSeconds: 100, durationSeconds: 100,
                   finished: true, updatedAt: Date(timeIntervalSince1970: 1))
    }
}
