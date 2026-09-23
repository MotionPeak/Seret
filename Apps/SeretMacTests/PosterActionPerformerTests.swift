import DebridCore
import DebridUI
import Testing
@testable import Seret

@MainActor
@Suite struct PosterActionPerformerTests {
    /// Before any profile resolves nothing is written, so the tick flipped optimistically on the
    /// poster must be taken back — otherwise it shows ✓ until the next marks load erases it.
    @Test func aMarkThatCouldNotBeWrittenIsTakenBack() async {
        let hit = SearchHit(result: TMDBSearchResult(id: 693134, title: "Dune: Part Two", name: nil,
                                                     releaseDate: "2024-02-27", firstAirDate: nil,
                                                     posterPath: nil, overview: nil, voteAverage: 8),
                            kind: .movie)
        let marks = TileWatchMarks(watch: { nil }, profileID: { "" })
        let performer = PosterActionPerformer(session: nil, shell: nil, library: nil, marks: marks, watchlist: nil)

        performer.perform(.markWatched(true), on: .hit(hit, library: nil, isCAM: false))
        #expect(marks.isWatched(hit))                 // optimistic

        for _ in 0..<1000 where marks.isWatched(hit) { await Task.yield() }
        #expect(!marks.isWatched(hit))
    }
}
