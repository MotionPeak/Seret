import Testing
import Foundation
@testable import DebridCore

@Suite struct DownloadKeyTests {
    @Test func movieKeyMatchesTheWatchKeyScheme() {
        #expect(DownloadKey.movie(tmdbID: 693134) == "movie:tmdb:693134")
        #expect(DownloadKey.movie(tmdbID: 693134) == TraktMapping.movieContentKey(tmdb: 693134))
    }

    @Test func episodeKeyMatchesTheWatchKeyScheme() {
        #expect(DownloadKey.episode(showTmdbID: 1399, season: 1, number: 2) == "show:tmdb:1399:s1e2")
        #expect(DownloadKey.episode(showTmdbID: 1399, season: 1, number: 2)
                == TraktMapping.episodeContentKey(showTmdb: 1399, season: 1, number: 2))
    }

    /// An episode download key must round-trip through Trakt, because Detail looks up watch state
    /// and download state with the same string.
    @Test func episodeKeyRoundTripsThroughTraktMapping() {
        let key = DownloadKey.episode(showTmdbID: 1399, season: 1, number: 2)
        #expect(TraktMapping.ref(forContentKey: key) == .episode(showTmdb: 1399, season: 1, number: 2))
    }

    /// The whole reason the season form is `season:3` and not `s3`: it must never be parsed as a
    /// Trakt ref. If this fails, a season download would be reported to Trakt as a watched episode.
    @Test func seasonKeyIsNeverParsedAsATraktRef() {
        let key = DownloadKey.season(showTmdbID: 1399, season: 3)
        #expect(key == "show:tmdb:1399:season:3")
        #expect(TraktMapping.ref(forContentKey: key) == nil)
    }

    @Test func seasonKeysAreDistinctPerSeasonAndShow() {
        #expect(DownloadKey.season(showTmdbID: 1399, season: 1)
                != DownloadKey.season(showTmdbID: 1399, season: 2))
        #expect(DownloadKey.season(showTmdbID: 1399, season: 1)
                != DownloadKey.season(showTmdbID: 1400, season: 1))
    }

    /// Two episodes of one show must not collide — the defect this whole key scheme exists to fix.
    @Test func twoEpisodesOfOneShowHaveDistinctKeys() {
        #expect(DownloadKey.episode(showTmdbID: 1399, season: 1, number: 1)
                != DownloadKey.episode(showTmdbID: 1399, season: 1, number: 2))
    }
}
