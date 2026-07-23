import Testing
import Foundation
@testable import DebridCore

@Suite struct TraktMappingTests {
    private func movie(tmdb: Int?) -> MediaItem {
        MediaItem(id: tmdb.map { "movie:tmdb:\($0)" } ?? "movie:dune:2024", kind: .movie,
                  title: "Dune", year: 2024, sources: [], seasons: [], tmdbID: tmdb)
    }
    private func show(tmdb: Int?) -> MediaItem {
        let ep = Episode(season: 2, number: 5,
                         source: MediaSource(torrentID: "T", fileID: nil, restrictedLink: "x",
                                             parsed: ParsedRelease(title: "S", season: 2, episode: 5)))
        return MediaItem(id: tmdb.map { "show:tmdb:\($0)" } ?? "show:got", kind: .show,
                         title: "GoT", year: 2011, sources: [],
                         seasons: [Season(number: 2, episodes: [ep])], tmdbID: tmdb)
    }

    @Test func movieRefUsesTmdbID() throws {
        let ref = try #require(TraktMapping.ref(forMovie: movie(tmdb: 27205)))
        #expect(ref == .movie(tmdb: 27205))
    }

    @Test func episodeRefUsesShowTmdbAndNumbers() throws {
        let s = show(tmdb: 1399)
        let ref = try #require(TraktMapping.ref(forShow: s, episode: s.seasons[0].episodes[0]))
        #expect(ref == .episode(showTmdb: 1399, season: 2, number: 5))
    }

    @Test func unenrichedItemReturnsNil() throws {
        #expect(TraktMapping.ref(forMovie: movie(tmdb: nil)) == nil)
    }

    @Test func contentKeysMatchEnricherScheme() {
        #expect(TraktMapping.movieContentKey(tmdb: 27205) == "movie:tmdb:27205")
        #expect(TraktMapping.episodeContentKey(showTmdb: 1399, season: 2, number: 5) == "show:tmdb:1399:s2e5")
    }

    @Test func refFromContentKeyRoundTrips() throws {
        #expect(TraktMapping.ref(forContentKey: "movie:tmdb:27205") == .movie(tmdb: 27205))
        #expect(TraktMapping.ref(forContentKey: "show:tmdb:1399:s2e5") == .episode(showTmdb: 1399, season: 2, number: 5))
        #expect(TraktMapping.ref(forContentKey: "movie:dune:2024") == nil)  // unenriched → no tmdb
    }
}
