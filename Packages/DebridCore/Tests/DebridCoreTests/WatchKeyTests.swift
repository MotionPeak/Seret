import Testing
import Foundation
@testable import DebridCore

@Suite struct WatchKeyTests {
    private func movie() -> MediaItem {
        MediaItem(id: "movie:tmdb:693134", kind: .movie, title: "Dune", year: 2024,
                  sources: [MediaSource(torrentID: "T1", fileID: 3, restrictedLink: "https://rd/x",
                                        parsed: ParsedRelease(title: "Dune"))],
                  seasons: [], tmdbID: 693134)
    }
    private func show() -> MediaItem {
        let ep = Episode(season: 1, number: 2,
                         source: MediaSource(torrentID: "T2", fileID: nil, restrictedLink: "https://rd/y",
                                             parsed: ParsedRelease(title: "Show", season: 1, episode: 2)))
        return MediaItem(id: "show:tmdb:1399", kind: .show, title: "Show", year: 2011,
                         sources: [], seasons: [Season(number: 1, episodes: [ep])], tmdbID: 1399)
    }

    @Test func movieContentKeyIsTheItemID() {
        #expect(WatchKey.content(forMovie: movie()) == "movie:tmdb:693134")
    }

    @Test func episodeContentKeyPrependsShowID() {
        let ep = show().seasons[0].episodes[0]
        #expect(WatchKey.content(forShow: show(), episode: ep) == "show:tmdb:1399:s1e2")
    }

    @Test func sourceKeyEncodesTorrentAndFile() {
        #expect(WatchKey.source(movie().sources[0]) == "T1#3")
        let noFile = MediaSource(torrentID: "T2", fileID: nil, restrictedLink: "x", parsed: ParsedRelease(title: "y"))
        #expect(WatchKey.source(noFile) == "T2#-")
    }

}
