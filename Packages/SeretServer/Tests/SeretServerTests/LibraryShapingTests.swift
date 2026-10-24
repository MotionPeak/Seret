import XCTest
import DebridCore
@testable import SeretServer

final class LibraryShapingTests: XCTestCase {
    private func movie(id: String, tmdb: Int?, title: String, torrent: String,
                       poster: String? = "/p.jpg") -> MediaItem {
        MediaItem(id: id, kind: .movie, title: title, year: 2026,
                  sources: [MediaSource(torrentID: torrent, fileID: 1,
                                        restrictedLink: "https://rd.example/\(torrent)",
                                        parsed: FilenameParser().parse("\(title).2026.1080p.BluRay.mkv"))],
                  seasons: [], tmdbID: tmdb, posterPath: poster, backdropPath: nil, overview: "o")
    }

    func testSameTmdbIDMoviesMergeIntoOneItemWithAllVersions() {
        let items = [movie(id: "movie:tmdb:1", tmdb: 1, title: "A", torrent: "T1"),
                     movie(id: "movie:tmdb:1", tmdb: 1, title: "A", torrent: "T2"),
                     movie(id: "movie:tmdb:1", tmdb: 1, title: "A", torrent: "T3")]
        let merged = ServerLibrary.mergeDuplicates(items)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].sources.count, 3)
        XCTAssertEqual(merged[0].sources.map { $0.torrentID }, ["T1", "T2", "T3"])
    }

    func testDistinctTmdbIDsStaySeparate() {
        let items = [movie(id: "a", tmdb: 1, title: "A", torrent: "T1"),
                     movie(id: "b", tmdb: 2, title: "B", torrent: "T2")]
        XCTAssertEqual(ServerLibrary.mergeDuplicates(items).count, 2)
    }

    func testItemsWithoutTmdbIDAreNeverMerged() {
        let items = [movie(id: "a", tmdb: nil, title: "A", torrent: "T1"),
                     movie(id: "b", tmdb: nil, title: "B", torrent: "T2")]
        XCTAssertEqual(ServerLibrary.mergeDuplicates(items).count, 2)
    }

    func testMergeKeepsFirstNonNilArtwork() {
        let items = [movie(id: "x", tmdb: 5, title: "A", torrent: "T1", poster: nil),
                     movie(id: "x", tmdb: 5, title: "A", torrent: "T2", poster: "/found.jpg")]
        XCTAssertEqual(ServerLibrary.mergeDuplicates(items)[0].posterPath, "/found.jpg")
    }

    func testDTOExposesVersionsAndHidesRestrictedLink() throws {
        let dto = LibraryItemDTO(movie(id: "m", tmdb: 7, title: "A", torrent: "T1"))
        XCTAssertEqual(dto.tmdbID, 7)
        XCTAssertEqual(dto.kind, "movie")
        XCTAssertEqual(dto.versions.count, 1)
        let encoded = String(decoding: try JSONEncoder().encode(dto), as: UTF8.self)
        XCTAssertFalse(encoded.contains("rd.example"), "restricted RD links must never reach the browser")
    }

    // MARK: - A provider that could not answer keeps its titles

    private func rd(_ id: String, tmdb: Int, title: String) -> MediaItem {
        movie(id: id, tmdb: tmdb, title: title, torrent: "R\(tmdb)")
    }
    private func tb(_ id: String, tmdb: Int, title: String) -> MediaItem {
        movie(id: id, tmdb: tmdb, title: title, torrent: "tb:\(tmdb)")
    }

    func testUnavailableProvidersTitlesStayAndTheAnsweringAccountsNewTitlesAppear() {
        let previous = [rd("movie:tmdb:1", tmdb: 1, title: "A"), tb("movie:tmdb:2", tmdb: 2, title: "B")]
        // TorBox did not answer: the fresh build only knows RD, which now also has a new film C.
        let fresh = [rd("movie:tmdb:1", tmdb: 1, title: "A"), rd("movie:tmdb:3", tmdb: 3, title: "C")]
        let result = ServerLibrary.carryOver(previous: previous, fresh: fresh, unavailable: [.torBox])
        XCTAssertEqual(Set(result.map(\.id)), ["movie:tmdb:1", "movie:tmdb:2", "movie:tmdb:3"])
    }

    func testNothingUnavailableMeansTheFreshBuildReplacesThePreviousOne() {
        let previous = [rd("movie:tmdb:1", tmdb: 1, title: "A"), tb("movie:tmdb:2", tmdb: 2, title: "B")]
        let fresh = [rd("movie:tmdb:1", tmdb: 1, title: "A")]
        // A signed-out / deleted account is NOT unavailable: its titles leave.
        XCTAssertEqual(ServerLibrary.carryOver(previous: previous, fresh: fresh, unavailable: []).map(\.id),
                       ["movie:tmdb:1"])
    }

    func testATitleDrawingOnAnUnavailableAccountIsKeptWithAllItsVersions() {
        let both = MediaItem(id: "movie:tmdb:1", kind: .movie, title: "A", year: 2026,
                             sources: rd("x", tmdb: 1, title: "A").sources + tb("x", tmdb: 1, title: "A").sources,
                             seasons: [], tmdbID: 1)
        let fresh = [rd("movie:tmdb:1", tmdb: 1, title: "A")]   // rebuilt from RD alone
        let result = ServerLibrary.carryOver(previous: [both], fresh: fresh, unavailable: [.torBox])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].sources.map(\.torrentID), ["R1", "tb:1"],
                       "rebuilding without the TorBox copy would drop that version until TorBox answers")
    }

    func testAnEpisodeOnAnUnavailableAccountFreezesItsShow() {
        let parsed = FilenameParser().parse("Show.S01E01.1080p.mkv")
        let ep = Episode(season: 1, number: 1, source: MediaSource(
            torrentID: "tb:9", fileID: 1, restrictedLink: "torbox://9/1", parsed: parsed))
        let show = MediaItem(id: "tv:tmdb:5", kind: .show, title: "Show", year: nil, sources: [],
                             seasons: [Season(number: 1, episodes: [ep])], tmdbID: 5)
        let result = ServerLibrary.carryOver(previous: [show], fresh: [], unavailable: [.torBox])
        XCTAssertEqual(result, [show])
    }
}
