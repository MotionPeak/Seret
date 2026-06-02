import Testing
@testable import DebridCore

struct MediaItemTests {
    private func source(_ torrentID: String = "T") -> MediaSource {
        MediaSource(torrentID: torrentID, fileID: 1, restrictedLink: "https://rd/x",
                    parsed: ParsedRelease(title: "X"))
    }

    @Test func episodeIDCombinesSeasonAndNumber() {
        let ep = Episode(season: 2, number: 5, source: source())
        #expect(ep.id == "s2e5")
        #expect(ep.season == 2)
        #expect(ep.number == 5)
    }

    @Test func seasonIDIsItsNumber() {
        let season = Season(number: 3, episodes: [])
        #expect(season.id == 3)
    }

    @Test func buildsAMovieItem() {
        let item = MediaItem(id: "movie:x", kind: .movie, title: "X", year: 2024,
                             sources: [source()], seasons: [])
        #expect(item.kind == .movie)
        #expect(item.sources.count == 1)
        #expect(item.seasons.isEmpty)
    }

    @Test func buildsAShowItem() {
        let ep = Episode(season: 1, number: 1, source: source())
        let item = MediaItem(id: "show:x", kind: .show, title: "X", year: nil,
                             sources: [], seasons: [Season(number: 1, episodes: [ep])])
        #expect(item.kind == .show)
        #expect(item.seasons.first?.episodes.first?.id == "s1e1")
    }
}
