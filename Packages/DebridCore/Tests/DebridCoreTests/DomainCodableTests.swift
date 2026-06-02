import Testing
import Foundation
@testable import DebridCore

@Suite struct DomainCodableTests {
    @Test func movieRoundTrips() throws {
        let item = MediaItem(
            id: "movie:tmdb:693134", kind: .movie, title: "Dune: Part Two", year: 2024,
            sources: [MediaSource(torrentID: "T1", fileID: 1, restrictedLink: "https://rd/x",
                                  parsed: ParsedRelease(title: "Dune Part Two", year: 2024,
                                                        resolution: "2160p", videoCodec: "HEVC"))],
            seasons: [], tmdbID: 693134, posterPath: "/p.jpg", overview: "Paul…")
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(MediaItem.self, from: data)
        #expect(decoded == item)
    }

    @Test func showWithSeasonsRoundTrips() throws {
        let ep = Episode(season: 1, number: 2,
                         source: MediaSource(torrentID: "T2", fileID: nil, restrictedLink: "https://rd/y",
                                             parsed: ParsedRelease(title: "Show", season: 1, episode: 2)))
        let item = MediaItem(id: "show:tmdb:1399", kind: .show, title: "Show", year: 2011,
                             sources: [], seasons: [Season(number: 1, episodes: [ep])],
                             tmdbID: 1399, posterPath: "/s.jpg", overview: "o")
        let decoded = try JSONDecoder().decode(MediaItem.self, from: try JSONEncoder().encode(item))
        #expect(decoded == item)
    }
}
