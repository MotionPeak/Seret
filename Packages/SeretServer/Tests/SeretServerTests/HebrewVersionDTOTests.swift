import XCTest
import DebridCore
@testable import SeretServer

final class HebrewVersionDTOTests: XCTestCase {
    private let uhd = MediaSource(torrentID: "A", fileID: 1, restrictedLink: "https://rd.example/A",
                                  parsed: ParsedRelease(title: "Dune", resolution: "2160p"))
    private let hd = MediaSource(torrentID: "B", fileID: 1, restrictedLink: "https://rd.example/B",
                                 parsed: ParsedRelease(title: "Dune", resolution: "1080p"))

    private var item: MediaItem {
        MediaItem(id: "movie:tmdb:1", kind: .movie, title: "Dune", year: 2021,
                  sources: [uhd, hd], seasons: [], tmdbID: 1)
    }

    private var hebrewOnHD: SubtitleEvidenceSet {
        SubtitleEvidenceSet(byVersion: [WatchKey.source(hd): SubtitleEvidence(hebrew: .builtIn)],
                            originalLanguage: "en")
    }

    func testAHebrewVersionIsListedFirstAndBadged() {
        let versions = VersionDTO.list(for: item, subtitles: hebrewOnHD)
        XCTAssertEqual(versions.map(\.index), [1, 0])
        XCTAssertEqual(versions.first?.hebrew, "Hebrew · Built in")
        XCTAssertNil(versions.last?.hebrew)
    }

    func testWithoutEvidenceTheOrderIsUnchanged() {
        let versions = VersionDTO.list(for: item)
        XCTAssertEqual(versions.map(\.index), [0, 1])
        XCTAssertNil(versions.first?.hebrew)
    }

    func testTheLibraryPlaysTheSameCopy() {
        XCTAssertEqual(LibraryItemDTO(item, subtitles: hebrewOnHD).versions.first?.index, 1)
    }

    func testTheOpenSubtitlesKeyIsOptional() throws {
        let bare = try ServerConfig.fromEnvironment(["RD_TOKEN": "t", "TMDB_API_KEY": "k"])
        XCTAssertEqual(bare.openSubtitlesAPIKey, "")
        let keyed = try ServerConfig.fromEnvironment(["RD_TOKEN": "t", "TMDB_API_KEY": "k",
                                                      "OPENSUBTITLES_API_KEY": "os"])
        XCTAssertEqual(keyed.openSubtitlesAPIKey, "os")
    }
}
