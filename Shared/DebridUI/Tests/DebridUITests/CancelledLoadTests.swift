import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// Leaving a screen while it is still loading is the ordinary way to leave it — a poster tapped on
/// impulse, a back press, a tab switch. Every store here refused to start a load again from the
/// state a cancellation left behind, so the screen stayed on its spinner, or on its half-built page,
/// for the rest of the session. Each test was run against the unfixed store and observed to fail.
@MainActor
@Suite struct CancelledLoadTests {

    private static func result(_ id: Int) -> TMDBSearchResult {
        TMDBSearchResult(id: id, title: "T\(id)", name: nil, releaseDate: "2020-01-01",
                         firstAirDate: nil, posterPath: "/p.jpg", overview: nil, voteAverage: nil)
    }

    // MARK: - Person page

    /// Never returns, so the load is guaranteed to still be in flight when the task is cancelled.
    private struct HangingCredits: PersonCreditsProviding {
        func person(tmdbID: Int) async throws -> TMDBPersonDetails {
            try await Task.sleep(for: .seconds(60))
            throw CancellationError()
        }
    }

    @Test func aCancelledPersonLoadLeavesThePageLoadableAgain() async {
        let store = PersonStore(ref: TMDBPersonRef(id: 1, name: "Denis Villeneuve"),
                                credits: HangingCredits())
        let load = Task { await store.load() }
        try? await Task.sleep(for: .seconds(0.05))
        load.cancel()
        await load.value

        // `load()` refuses to start from `.loading`, so being left there is being left there for
        // good — the person page shows its spinner and never loads again.
        #expect(store.state == .idle)
    }

    // MARK: - Browse

    /// Every rail waits for the gate, so the segment is certain to be mid-load when its asker
    /// goes away.
    private final class GatedDiscover: DiscoverProviding, @unchecked Sendable {
        let gate = BrowseGate()
        private func held(_ id: Int) async throws -> [TMDBSearchResult] {
            await gate.wait()
            return [TMDBSearchResult(id: id, title: "T\(id)", name: nil, releaseDate: "2020-01-01",
                                     firstAirDate: nil, posterPath: "/p.jpg", overview: nil, voteAverage: nil)]
        }
        func nowPlayingMovies() async throws -> [TMDBSearchResult] { [] }
        func trending(_ k: MediaKind, window: TMDBTrendingWindow) async throws -> [TMDBSearchResult] { try await held(1) }
        func topRatedCurated(_ k: MediaKind) async throws -> [TMDBSearchResult] { try await held(2) }
        func newOverall(_ k: MediaKind, from: String, to: String) async throws -> [TMDBSearchResult] { try await held(3) }
        func decade(_ k: MediaKind, from: String, to: String) async throws -> [TMDBSearchResult] { try await held(4) }
        func recommended(_ k: MediaKind, tmdbID: Int) async throws -> [TMDBSearchResult] { try await held(5) }
        func newByGenre(_ k: MediaKind, _ g: Int, from: String, to: String) async throws -> [TMDBSearchResult] { try await held(100 + g) }
        func popularByGenre(_ k: MediaKind, _ g: Int) async throws -> [TMDBSearchResult] { try await held(1_000 + g) }
        func topRatedByGenre(_ k: MediaKind, _ g: Int) async throws -> [TMDBSearchResult] { try await held(10_000 + g) }
    }

    actor BrowseGate {
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var opened = false
        func wait() async {
            guard !opened else { return }
            await withCheckedContinuation { waiters.append($0) }
        }
        func open() {
            opened = true
            for w in waiters { w.resume() }
            waiters = []
        }
    }

    /// Leaving Browse mid-load used to cancel the load itself — it ran in the asking view's task —
    /// and the page then sat on its skeletons, or on whichever rails had finished, for the session.
    /// The store owns the load now: the asker going away does not abandon it, so the segment is
    /// finished, every rail in, when the viewer comes back. (This test used to assert the opposite
    /// repair — a cancelled segment falling back to `.idle` so it could be reloaded — which was a
    /// second load of everything, and raced a re-ask into stranding the segment for good.)
    @Test func aBrowseSegmentLeftMidLoadIsFinishedOnReturn() async {
        let discover = GatedDiscover()
        let store = DiscoverStore(kind: .movie, discover: discover)
        let asker = Task { await store.loadSegment(.popular) }
        try? await Task.sleep(for: .seconds(0.05))
        asker.cancel()                              // the viewer leaves
        await discover.gate.open()                  // the rails come back while they are away
        await store.loadSegment(.popular)           // …and they return
        await asker.value

        #expect(store.segmentState(.popular) == .loaded)
        #expect(store.rowsBySegment[.popular]?.count == DiscoverStore.genres(for: .movie).count)
    }

    /// Rails finish out of order. Filling a late one into its spec slot inserted it ABOVE rails the
    /// viewer was already looking at — the page jumped — and re-running the cross-rail dedup with a
    /// new earliest claimant pulled posters out of a rail that was already showing them. The visible
    /// list must only ever grow at the bottom.
    @Test func railsOnlyEverAppendToTheBottom() {
        let specs = (0..<4).map { i in
            DiscoverStore.RowSpec(id: "r\(i)", title: "Rail \(i)", fetch: { [] })
        }
        let hit = { (id: Int) in SearchHit(result: Self.result(id), kind: .movie) }

        // Rail 2 comes back first…
        let late = DiscoverStore.assemble(specs: specs, completed: [2: [hit(20)]])
        #expect(late.isEmpty, "nothing may appear above a rail that has not finished")

        // …then rail 0. Rail 2 still waits its turn behind rail 1, so nothing on screen moves.
        let then = DiscoverStore.assemble(specs: specs, completed: [0: [hit(10)], 2: [hit(20)]])
        #expect(then.map(\.id) == ["r0"])

        let whenAllIn = DiscoverStore.assemble(
            specs: specs, completed: [0: [hit(10)], 1: [hit(11)], 2: [hit(20)], 3: [hit(30)]])
        #expect(whenAllIn.map(\.id) == ["r0", "r1", "r2", "r3"], "…and the finished page is unchanged")
    }

    /// "Stop at the first rail that has not FINISHED" must not become "stop at the first rail that
    /// is empty" — a genre with no results is a completed rail, and holding the page behind it
    /// would leave a whole segment blank.
    @Test func anEmptyRailDoesNotBlockTheOnesBehindIt() {
        let specs = (0..<3).map { i in
            DiscoverStore.RowSpec(id: "r\(i)", title: "Rail \(i)", fetch: { [] })
        }
        let hit = { (id: Int) in SearchHit(result: Self.result(id), kind: .movie) }

        let rows = DiscoverStore.assemble(specs: specs,
                                          completed: [0: [], 1: [hit(11)], 2: [hit(22)]])

        #expect(rows.map(\.id) == ["r1", "r2"])
    }
}
