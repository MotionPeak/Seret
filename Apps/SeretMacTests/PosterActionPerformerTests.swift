import DebridCore
import DebridUI
import Foundation
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

    /// The franchise rail's current-film tile still offers Open from its right-click menu (the
    /// hover row is empty, but the menu is not) — clicking it must not push a second copy of the
    /// page already on top.
    @Test func openingTheTitleYouAreOnDoesNothing() {
        let defaults = UserDefaults(suiteName: "seret.tests.\(UUID().uuidString)")!
        let shell = ShellModel(defaults: defaults)
        let item = MediaItem(id: "movie:tmdb:693134", kind: .movie, title: "Dune: Part Two",
                             year: 2024, sources: [], seasons: [])
        shell.open(.title(item))
        #expect(shell.history(for: .home).path.count == 1)

        let performer = PosterActionPerformer(session: nil, shell: shell, library: nil, marks: nil, watchlist: nil)
        performer.perform(.open, on: .library(item))
        #expect(shell.history(for: .home).path.count == 1)

        // A DIFFERENT title still opens normally.
        let other = MediaItem(id: "movie:tmdb:438631", kind: .movie, title: "Dune",
                              year: 2021, sources: [], seasons: [])
        performer.perform(.open, on: .library(other))
        #expect(shell.history(for: .home).path.count == 2)
    }
}
