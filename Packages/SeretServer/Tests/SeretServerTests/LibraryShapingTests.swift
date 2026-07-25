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
}
