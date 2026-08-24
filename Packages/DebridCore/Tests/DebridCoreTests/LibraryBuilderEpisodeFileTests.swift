import Testing
@testable import DebridCore

/// Which FILE inside a torrent an episode ends up pointing at.
///
/// The bug this pins: a torrent whose *name* states one episode was resolved with
/// `primaryVideoFile()` — the largest video file in the torrent. That is right when the torrent
/// really holds one episode, and wrong when it holds several, which is common: pack adds are
/// routinely named after their first episode. The result was an episode row that plays a
/// different episode while recording progress under the clicked episode's key.
struct LibraryBuilderEpisodeFileTests {
    let builder = LibraryBuilder()

    /// Named `S01E01`, actually holds three episodes, and E02 is the largest file.
    /// E01 must point at E01's file — not at the biggest one.
    @Test func aTorrentNamedForOneEpisodeButHoldingSeveralUsesTheNamedEpisodesFile() {
        let info = TorrentInfo(
            id: "T", filename: "Some.Show.S01E01.1080p.WEB-DL.x265-NTb", hash: "h",
            bytes: 9000, progress: 100, status: "downloaded",
            files: [
                TorrentFile(id: 1, path: "/Show/Some.Show.S01E01.1080p.mkv", bytes: 2000, selected: 1),
                TorrentFile(id: 2, path: "/Show/Some.Show.S01E02.1080p.mkv", bytes: 5000, selected: 1),
                TorrentFile(id: 3, path: "/Show/Some.Show.S01E03.1080p.mkv", bytes: 2000, selected: 1),
            ],
            links: ["https://rd/E01", "https://rd/E02", "https://rd/E03"])

        let lib = builder.group([info])
        let episodes = lib[0].seasons[0].episodes

        let e1 = episodes.first { $0.number == 1 }
        #expect(e1?.source.restrictedLink == "https://rd/E01")
        #expect(e1?.source.fileID == 1)
    }

    /// The ordinary case must not regress: one episode, one video file, plus junk. The video
    /// file wins even though it is not the only selected file.
    @Test func aGenuineSingleEpisodeTorrentStillResolves() {
        let info = TorrentInfo(
            id: "T", filename: "Some.Show.S01E04.1080p.WEB-DL", hash: "h",
            bytes: 2000, progress: 100, status: "downloaded",
            files: [
                TorrentFile(id: 1, path: "/Show/Some.Show.S01E04.1080p.mkv", bytes: 2000, selected: 1),
                TorrentFile(id: 2, path: "/Show/readme.nfo", bytes: 5, selected: 1),
            ],
            links: ["https://rd/E04", "https://rd/nfo"])

        let lib = builder.group([info])
        let e4 = lib[0].seasons[0].episodes.first { $0.number == 4 }
        #expect(e4?.source.restrictedLink == "https://rd/E04")
    }

    /// Owned sources must record the FILE's size, not the torrent's. Without it, size-aware
    /// ranking is inert for the library and the Versions list keeps recommending the bloat the
    /// search flow now avoids. A pack's per-file sizes differ from its total.
    @Test func everyEpisodeRecordsItsOwnFileSize() {
        let info = TorrentInfo(
            id: "T", filename: "Some.Show.S01.2160p.WEB-DL", hash: "h",
            bytes: 9000, progress: 100, status: "downloaded",
            files: [
                TorrentFile(id: 1, path: "/Show/Some.Show.S01E01.2160p.mkv", bytes: 4000, selected: 1),
                TorrentFile(id: 2, path: "/Show/Some.Show.S01E02.2160p.mkv", bytes: 5000, selected: 1),
            ],
            links: ["https://rd/E01", "https://rd/E02"])

        let episodes = builder.group([info])[0].seasons[0].episodes
        #expect(episodes.first { $0.number == 1 }?.source.sizeBytes == 4000)
        #expect(episodes.first { $0.number == 2 }?.source.sizeBytes == 5000)
    }

    /// A movie's source records its file size too.
    @Test func aMovieRecordsItsFileSize() {
        let info = TorrentInfo(
            id: "M", filename: "Some.Film.2024.2160p.WEB-DL.x265", hash: "h",
            bytes: 3000, progress: 100, status: "downloaded",
            files: [TorrentFile(id: 1, path: "/Film/film.mkv", bytes: 2400, selected: 1)],
            links: ["https://rd/M"])

        #expect(builder.group([info])[0].sources.first?.sizeBytes == 2400)
    }

    /// A torrent named for an episode whose file is named differently (no parseable episode in
    /// the path) must still resolve — fall back to the largest video file rather than dropping
    /// the episode from the library entirely.
    @Test func fallsBackToTheLargestVideoWhenNoFileNamesTheEpisode() {
        let info = TorrentInfo(
            id: "T", filename: "Some.Show.S01E05.1080p.WEB-DL", hash: "h",
            bytes: 2000, progress: 100, status: "downloaded",
            files: [
                TorrentFile(id: 1, path: "/Show/sample.mkv", bytes: 50, selected: 1),
                TorrentFile(id: 2, path: "/Show/video.mkv", bytes: 2000, selected: 1),
            ],
            links: ["https://rd/sample", "https://rd/video"])

        let lib = builder.group([info])
        let e5 = lib[0].seasons[0].episodes.first { $0.number == 5 }
        #expect(e5?.source.restrictedLink == "https://rd/video")
    }
}
