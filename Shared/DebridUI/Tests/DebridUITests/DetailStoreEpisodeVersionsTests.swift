import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// The Detail page must hand the player an episode's FULL set of owned copies.
///
/// `EpisodeRowInfo.ownedEpisode` rebuilt an `Episode` from just its source, so even with the
/// library keeping every copy, the play request built here would carry a single-source episode and
/// the player would again have nothing to fall back to. The row also needs the copies in order to
/// offer a Versions picker at all.
/// `episodes(forSeason:)` reads only what is already in the item, so the provider is never called.
private final class NoDetails: MediaDetailsProviding {
    struct Unused: Error {}
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails { throw Unused() }
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails { throw Unused() }
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] { [] }
}

@MainActor
@Suite struct DetailStoreEpisodeVersionsTests {

    private func source(_ id: String, res: String = "1080p") -> MediaSource {
        MediaSource(torrentID: id, fileID: nil, restrictedLink: "rd://\(id)",
                    parsed: ParsedRelease(title: "The Show", season: 1, episode: 1,
                                          resolution: res),
                    sizeBytes: 2_000_000_000)
    }

    private func store(episode: Episode) -> DetailStore {
        let item = MediaItem(id: "s1", kind: .show, title: "The Show", year: 2023,
                             sources: [], seasons: [Season(number: 1, episodes: [episode])],
                             tmdbID: 1399)
        return DetailStore(item: item, details: NoDetails(), watch: nil)
    }

    @Test func aRowCarriesEveryOwnedCopyOfItsEpisode() {
        let ep = Episode(season: 1, number: 1, source: source("a"),
                         alternates: [source("b", res: "2160p")])
        let rows = store(episode: ep).episodes(forSeason: 1)

        #expect(rows.first?.ownedEpisode?.sources.count == 2)
        #expect(rows.first?.ownedEpisode?.alternates.map(\.torrentID) == ["b"])
    }

    /// The play request the row builds must carry them through to the player.
    @Test func thePlayRequestCarriesTheAlternates() {
        let ep = Episode(season: 1, number: 1, source: source("a"), alternates: [source("b")])
        let s = store(episode: ep)
        let row = s.episodes(forSeason: 1).first!

        let request = s.playRequest(source: row.ownedSource!, episode: row.ownedEpisode!,
                                    label: "The Show — S1·E1")
        #expect(request.episode?.sources.count == 2)
    }

    /// A single-copy episode reports no alternates, so the UI can hide the picker.
    @Test func aSingleCopyEpisodeHasNoAlternates() {
        let ep = Episode(season: 1, number: 1, source: source("a"))
        let rows = store(episode: ep).episodes(forSeason: 1)

        #expect(rows.first?.ownedEpisode?.alternates.isEmpty == true)
        #expect(rows.first?.hasAlternateVersions == false)
    }

    /// The row exposes whether a picker is worth offering at all.
    @Test func aMultiCopyEpisodeAdvertisesItsVersions() {
        let ep = Episode(season: 1, number: 1, source: source("a"), alternates: [source("b")])
        let rows = store(episode: ep).episodes(forSeason: 1)

        #expect(rows.first?.hasAlternateVersions == true)
    }
}
