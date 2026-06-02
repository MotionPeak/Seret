import Testing
import Foundation
@testable import DebridCore

@Suite struct SubtitleQueryTests {
    private func source(_ t: String) -> MediaSource {
        MediaSource(torrentID: "T", fileID: 1, restrictedLink: "https://rd/x", parsed: ParsedRelease(title: t))
    }

    @Test func movieQueryUsesTmdbTitleYear() {
        let item = MediaItem(id: "movie:tmdb:5", kind: .movie, title: "Dune", year: 2024,
                             sources: [source("Dune")], seasons: [], tmdbID: 5)
        let q = SubtitleQuery.movie(item)
        #expect(q.tmdbID == 5)
        #expect(q.title == "Dune")
        #expect(q.year == 2024)
        #expect(q.season == nil)
        #expect(q.episode == nil)
    }

    @Test func episodeQueryUsesShowTmdbAndEpisodeNumbers() {
        let ep = Episode(season: 2, number: 7, source: source("Show S02E07"))
        let show = MediaItem(id: "show:tmdb:9", kind: .show, title: "Show", year: 2011,
                             sources: [], seasons: [Season(number: 2, episodes: [ep])], tmdbID: 9)
        let q = SubtitleQuery.episode(show: show, episode: ep)
        #expect(q.tmdbID == 9)
        #expect(q.title == "Show")
        #expect(q.season == 2)
        #expect(q.episode == 7)
    }
}
