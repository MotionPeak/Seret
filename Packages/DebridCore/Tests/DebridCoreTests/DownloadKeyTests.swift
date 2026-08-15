import Testing
import Foundation
@testable import DebridCore

@Suite struct DownloadKeyTests {
    @Test func movieKeyMatchesTheWatchKeyScheme() {
        #expect(DownloadKey.movie(tmdbID: 693134) == "movie:tmdb:693134")
    }

    @Test func episodeKeyMatchesTheWatchKeyScheme() {
        #expect(DownloadKey.episode(showTmdbID: 1399, season: 1, number: 2) == "show:tmdb:1399:s1e2")
    }

    /// The whole reason the season form is `season:3` and not `s3`: a season download must never
    /// be mistakable for an EPISODE key. Detail looks up watch state and download state with the
    /// same string, so if these two shapes collided a whole-season download would read as a
    /// watched episode.
    @Test func aSeasonKeyIsNotShapedLikeAnEpisodeKey() {
        #expect(DownloadKey.season(showTmdbID: 1399, season: 3) == "show:tmdb:1399:season:3")
        #expect(DownloadKey.season(showTmdbID: 1399, season: 3)
                != DownloadKey.episode(showTmdbID: 1399, season: 3, number: 1))
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
