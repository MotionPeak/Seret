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

    /// Every rail hangs, so the segment is certain to be mid-load when it is cancelled.
    private struct HangingDiscover: DiscoverProviding {
        private func hang() async throws -> [TMDBSearchResult] {
            try await Task.sleep(for: .seconds(60))
            return []
        }
        func nowPlayingMovies() async throws -> [TMDBSearchResult] { try await hang() }
        func trending(_ k: MediaKind, window: TMDBTrendingWindow) async throws -> [TMDBSearchResult] { try await hang() }
        func topRatedCurated(_ k: MediaKind) async throws -> [TMDBSearchResult] { try await hang() }
        func newOverall(_ k: MediaKind, from: String, to: String) async throws -> [TMDBSearchResult] { try await hang() }
        func decade(_ k: MediaKind, from: String, to: String) async throws -> [TMDBSearchResult] { try await hang() }
        func recommended(_ k: MediaKind, tmdbID: Int) async throws -> [TMDBSearchResult] { try await hang() }
        func newByGenre(_ k: MediaKind, _ g: Int, from: String, to: String) async throws -> [TMDBSearchResult] { try await hang() }
        func popularByGenre(_ k: MediaKind, _ g: Int) async throws -> [TMDBSearchResult] { try await hang() }
        func topRatedByGenre(_ k: MediaKind, _ g: Int) async throws -> [TMDBSearchResult] { try await hang() }
    }

    @Test func aCancelledBrowseSegmentCanBeLoadedAgain() async {
        let store = DiscoverStore(kind: .movie, discover: HangingDiscover())
        let load = Task { await store.loadSegment(.popular) }
        try? await Task.sleep(for: .seconds(0.05))
        load.cancel()
        await load.value

        // `.loaded` (set the moment the first rail lands) and `.loading` both refuse a reload, so
        // leaving Browse mid-load froze the page on whichever rails happened to have finished.
        #expect(store.segmentState(.popular) == .idle)
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
}
