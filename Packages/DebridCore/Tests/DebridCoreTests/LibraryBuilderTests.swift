import Testing
@testable import DebridCore

struct LibraryBuilderTests {
    let builder = LibraryBuilder()

    /// One torrent with a single selected video file named `path`.
    private func torrent(_ id: String, name: String, file path: String) -> TorrentInfo {
        TorrentInfo(id: id, filename: name, hash: "h", bytes: 1000, progress: 100, status: "downloaded",
                    files: [TorrentFile(id: 1, path: path, bytes: 1000, selected: 1)],
                    links: ["https://rd/\(id)"])
    }

    @Test func groupsAMovie() {
        let lib = builder.group([
            torrent("A", name: "Dune.Part.Two.2024.2160p.BluRay.x265-WiKi.mkv", file: "/Dune/movie.mkv"),
        ])
        #expect(lib.count == 1)
        #expect(lib[0].kind == .movie)
        #expect(lib[0].title == "Dune Part Two")
        #expect(lib[0].year == 2024)
        #expect(lib[0].sources.first?.restrictedLink == "https://rd/A")
    }

    @Test func groupsSingleEpisodesOfTheSameShowAcrossTorrents() {
        let lib = builder.group([
            torrent("E1", name: "Shogun.S01E01.1080p.WEB-DL.x265-NTb.mkv", file: "/Shogun/e01.mkv"),
            torrent("E2", name: "Shogun.S01E02.1080p.WEB-DL.x265-NTb.mkv", file: "/Shogun/e02.mkv"),
        ])
        #expect(lib.count == 1)
        let show = lib[0]
        #expect(show.kind == .show)
        #expect(show.title == "Shogun")
        #expect(show.seasons.count == 1)
        #expect(show.seasons[0].number == 1)
        #expect(show.seasons[0].episodes.map(\.number) == [1, 2])
    }

    @Test func separatesMoviesAndShows() {
        let lib = builder.group([
            torrent("M", name: "The.Batman.2022.1080p.BluRay.x264-GRP.mkv", file: "/b/movie.mkv"),
            torrent("E1", name: "Severance.S02E01.1080p.x265-NTb.mkv", file: "/s/e01.mkv"),
        ])
        #expect(lib.contains { $0.kind == .movie && $0.title == "The Batman" })
        #expect(lib.contains { $0.kind == .show && $0.title == "Severance" })
        #expect(lib.count == 2)
    }

    @Test func dedupesRepeatedEpisode() {
        let lib = builder.group([
            torrent("E1", name: "Shogun.S01E01.1080p.x265-A.mkv", file: "/a/e01.mkv"),
            torrent("E1b", name: "Shogun.S01E01.2160p.x265-B.mkv", file: "/b/e01.mkv"),
        ])
        #expect(lib.count == 1)
        #expect(lib[0].seasons[0].episodes.count == 1)
    }

    /// One torrent with several selected video files (a season pack).
    private func pack(_ id: String, name: String, files: [String]) -> TorrentInfo {
        let tfiles = files.enumerated().map { i, path in
            TorrentFile(id: i + 1, path: path, bytes: 1000, selected: 1)
        }
        let links = files.indices.map { "https://rd/\(id)/\($0)" }
        return TorrentInfo(id: id, filename: name, hash: "h", bytes: 3000, progress: 100,
                           status: "downloaded", files: tfiles, links: links)
    }

    @Test func expandsASeasonPackIntoEpisodes() {
        let lib = builder.group([
            pack("P", name: "Fallout.S01.2160p.WEB-DL.HEVC-FLUX", files: [
                "/Fallout.S01/Fallout.S01E01.mkv",
                "/Fallout.S01/Fallout.S01E02.mkv",
                "/Fallout.S01/Fallout.S01E03.mkv",
            ]),
        ])
        #expect(lib.count == 1)
        let show = lib[0]
        #expect(show.kind == .show)
        #expect(show.title == "Fallout")
        #expect(show.seasons.count == 1)
        #expect(show.seasons[0].episodes.map(\.number) == [1, 2, 3])
        #expect(show.seasons[0].episodes[0].source.restrictedLink == "https://rd/P/0")
        #expect(show.seasons[0].episodes[1].source.restrictedLink == "https://rd/P/1")
    }

    @Test func mergesAPackAndASingleEpisodeIntoOneShow() {
        let lib = builder.group([
            pack("P", name: "Fallout.S01.2160p.WEB-DL.HEVC-FLUX", files: [
                "/Fallout.S01/Fallout.S01E01.mkv",
                "/Fallout.S01/Fallout.S01E02.mkv",
            ]),
            torrent("X", name: "Fallout.S01E03.2160p.WEB-DL.HEVC-NTb.mkv", file: "/x/e03.mkv"),
        ])
        #expect(lib.count == 1)
        #expect(lib[0].seasons[0].episodes.map(\.number) == [1, 2, 3])
    }

    @Test func skipsNonVideoFilesInAPack() {
        let lib = builder.group([
            pack("P", name: "Fallout.S01.WEB-DL", files: [
                "/Fallout.S01/Fallout.S01E01.mkv",
                "/Fallout.S01/readme.txt",
                "/Fallout.S01/Fallout.S01E02.mkv",
            ]),
        ])
        #expect(lib[0].seasons[0].episodes.map(\.number) == [1, 2])
    }
}
