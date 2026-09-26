import Testing
import Foundation
import DebridCore
@testable import DebridUI

/// What a tracked download is FOR — the single place a film, an episode, a season pack and a
/// Versions pick all assemble the same key + title tvOS used to build separately in three places.
@MainActor
@Suite struct DownloadTargetTests {
    private func movie(tmdbID: Int? = 693134) -> MediaItem {
        MediaItem(id: "movie:tmdb:\(tmdbID ?? 0)", kind: .movie, title: "Dune: Part Two", year: 2024,
                  sources: [], seasons: [], tmdbID: tmdbID, posterPath: "/dune.jpg")
    }
    private func show(tmdbID: Int? = 1396) -> MediaItem {
        MediaItem(id: "show:tmdb:\(tmdbID ?? 0)", kind: .show, title: "Breaking Bad", year: 2008,
                  sources: [], seasons: [], tmdbID: tmdbID, posterPath: "/bb.jpg")
    }

    @Test func aFilmFilesUnderItsMovieKey() {
        let target = DownloadTarget.movie(movie())
        #expect(target?.contentKey == "movie:tmdb:693134")
        #expect(target?.title == "Dune: Part Two")
        #expect(target?.kind == .movie)
        #expect(target?.posterPath == "/dune.jpg")
    }

    @Test func anEpisodeFilesUnderItsEpisodeKeyWithTheTVTitle() {
        let target = DownloadTarget.episode(of: show(), season: 1, number: 3)
        #expect(target?.contentKey == "show:tmdb:1396:s1e3")
        #expect(target?.title == "Breaking Bad S1E3")
        #expect(target?.kind == .show)
    }

    @Test func aSeasonFilesUnderTheSeasonKey() {
        let target = DownloadTarget.season(of: show(), 2)
        #expect(target?.contentKey == "show:tmdb:1396:season:2")
        #expect(target?.title == "Breaking Bad Season 2")
        #expect(target?.kind == .show)
    }

    @Test func noTMDBIDNoTarget() {
        #expect(DownloadTarget.movie(movie(tmdbID: nil)) == nil)
        #expect(DownloadTarget.episode(of: show(tmdbID: nil), season: 1, number: 1) == nil)
        #expect(DownloadTarget.season(of: show(tmdbID: nil), 1) == nil)
    }

    @Test func aVersionPickUsesTheResolvedTitle() {
        let movieTarget = DownloadTarget.version(tmdbID: 693134, kind: .movie, title: "Dune: Part Two",
                                                 posterPath: "/dune.jpg", target: .movie)
        #expect(movieTarget.contentKey == "movie:tmdb:693134")
        #expect(movieTarget.title == "Dune: Part Two")

        let episodeTarget = DownloadTarget.version(tmdbID: 1396, kind: .show, title: "Breaking Bad",
                                                    posterPath: nil,
                                                    target: .episode(season: 1, number: 3))
        #expect(episodeTarget.contentKey == "show:tmdb:1396:s1e3")
        #expect(episodeTarget.title == "Breaking Bad")
    }

    @Test func theMagnetTargetCarriesTheSameKey() {
        let target = DownloadTarget.movie(movie())!
        #expect(target.magnet.contentKey == target.contentKey)
        #expect(target.magnet.tmdbID == target.tmdbID)
        #expect(target.magnet.title == target.title)
        #expect(target.magnet.kind == target.kind)
        #expect(target.magnet.posterPath == target.posterPath)
    }
}
