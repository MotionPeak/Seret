import Testing
import Foundation
@testable import DebridCore

/// Picking the file for a *specific* episode out of a season pack.
///
/// The bug this pins: playback resolved a pack's file with `primaryVideoFile()` — "the largest
/// selected video file" — so clicking E3 played whichever episode happened to be biggest, while
/// recording progress under E3's watch key.
struct EpisodeFileSelectionTests {

    /// A pack whose largest file is NOT the requested episode. `primaryVideoFile()` would return
    /// E01 here (the double-length opener); the episode-aware lookup must return E03.
    @Test func picksTheRequestedEpisodeNotTheLargestFile() {
        let info = TorrentInfo(
            id: "PACK", filename: "Some.Show.S01.1080p.WEB-DL", hash: "beef", bytes: 9000,
            progress: 100, status: "downloaded",
            files: [
                TorrentFile(id: 1, path: "/Show.S01/Some.Show.S01E01.1080p.mkv", bytes: 5000, selected: 1),
                TorrentFile(id: 2, path: "/Show.S01/Some.Show.S01E02.1080p.mkv", bytes: 2000, selected: 1),
                TorrentFile(id: 3, path: "/Show.S01/Some.Show.S01E03.1080p.mkv", bytes: 2000, selected: 1),
            ],
            links: ["https://rd/E01", "https://rd/E02", "https://rd/E03"])

        #expect(info.primaryVideoFile()?.file.id == 1)   // the trap, still true

        let picked = info.videoFile(forSeason: 1, episode: 3)
        #expect(picked?.file.id == 3)
        #expect(picked?.link == "https://rd/E03")
    }

    /// A pack spanning two seasons must not confuse S01E03 with S02E03.
    @Test func disambiguatesBySeason() {
        let info = TorrentInfo(
            id: "PACK", filename: "Some.Show.S01-S02.1080p", hash: "beef", bytes: 4000,
            progress: 100, status: "downloaded",
            files: [
                TorrentFile(id: 1, path: "/Show/Some.Show.S01E03.1080p.mkv", bytes: 1000, selected: 1),
                TorrentFile(id: 2, path: "/Show/Some.Show.S02E03.1080p.mkv", bytes: 1000, selected: 1),
            ],
            links: ["https://rd/S01E03", "https://rd/S02E03"])

        #expect(info.videoFile(forSeason: 2, episode: 3)?.link == "https://rd/S02E03")
        #expect(info.videoFile(forSeason: 1, episode: 3)?.link == "https://rd/S01E03")
    }

    /// A caller with no season in hand (the torrent name never stated one) matches on episode
    /// number alone, rather than finding nothing.
    @Test func nilSeasonMatchesOnEpisodeAlone() {
        let info = TorrentInfo(
            id: "PACK", filename: "Some.Show.Complete", hash: "beef", bytes: 2000,
            progress: 100, status: "downloaded",
            files: [
                TorrentFile(id: 1, path: "/Show/Some.Show.S01E01.1080p.mkv", bytes: 1000, selected: 1),
                TorrentFile(id: 2, path: "/Show/Some.Show.S01E02.1080p.mkv", bytes: 1000, selected: 1),
            ],
            links: ["https://rd/E01", "https://rd/E02"])

        #expect(info.videoFile(forSeason: nil, episode: 2)?.link == "https://rd/E02")
    }

    /// `1x03` is the other episode form the parser recognises; the lookup must handle it too.
    @Test func matchesTheNxMEpisodeForm() {
        let info = TorrentInfo(
            id: "PACK", filename: "Some.Show.Season.1", hash: "beef", bytes: 2000,
            progress: 100, status: "downloaded",
            files: [
                TorrentFile(id: 1, path: "/Show/Some Show 1x02 720p.mkv", bytes: 1000, selected: 1),
                TorrentFile(id: 2, path: "/Show/Some Show 1x03 720p.mkv", bytes: 1000, selected: 1),
            ],
            links: ["https://rd/E02", "https://rd/E03"])

        #expect(info.videoFile(forSeason: 1, episode: 3)?.link == "https://rd/E03")
    }

    /// Nothing matching the request must yield nil — never a consolation file. Playing "some
    /// episode" is the defect being fixed.
    @Test func returnsNilWhenTheEpisodeIsNotInTheTorrent() {
        let info = TorrentInfo(
            id: "PACK", filename: "Some.Show.S01", hash: "beef", bytes: 2000,
            progress: 100, status: "downloaded",
            files: [
                TorrentFile(id: 1, path: "/Show/Some.Show.S01E01.mkv", bytes: 1000, selected: 1),
            ],
            links: ["https://rd/E01"])

        #expect(info.videoFile(forSeason: 1, episode: 9) == nil)
    }

    /// Unselected files have no link and must never be offered; junk files are skipped even when
    /// their name parses to the right episode.
    @Test func ignoresUnselectedAndNonVideoFiles() {
        let info = TorrentInfo(
            id: "PACK", filename: "Some.Show.S01", hash: "beef", bytes: 3000,
            progress: 100, status: "downloaded",
            files: [
                TorrentFile(id: 1, path: "/Show/Some.Show.S01E01.srt", bytes: 5, selected: 1),
                TorrentFile(id: 2, path: "/Show/Some.Show.S01E01.mkv", bytes: 2000, selected: 1),
                TorrentFile(id: 3, path: "/Show/Some.Show.S01E02.mkv", bytes: 900, selected: 0),
            ],
            links: ["https://rd/E01-sub", "https://rd/E01"])

        #expect(info.videoFile(forSeason: 1, episode: 1)?.file.id == 2)
        #expect(info.videoFile(forSeason: 1, episode: 2) == nil)   // not selected → no link
    }

    /// A pack can carry more than one file naming the same episode: a sample clip, a
    /// behind-the-scenes featurette, a "proper" re-encode. `videoFileIDs()` selects every video
    /// file, so all of them get links — and taking the FIRST match meant whichever RD happened to
    /// list first won. A 40 MB sample listed under "Sample/" beat the real 2 GB episode, so the
    /// episode played for thirty seconds and stopped.
    @Test func picksTheLargestFileForTheEpisodeNotTheFirstListed() {
        let info = TorrentInfo(
            id: "PACK", filename: "Some.Show.S01.1080p.WEB-DL", hash: "beef", bytes: 9000,
            progress: 100, status: "downloaded",
            files: [
                TorrentFile(id: 1, path: "/Show.S01/Sample/Show.S01E03.sample.mkv",
                            bytes: 40_000_000, selected: 1),
                TorrentFile(id: 2, path: "/Show.S01/Show.S01E03.1080p.WEB-DL.mkv",
                            bytes: 2_000_000_000, selected: 1),
            ],
            links: ["https://rd/sample", "https://rd/real"])

        let picked = info.videoFile(forSeason: 1, episode: 3)
        #expect(picked?.file.id == 2)
        #expect(picked?.link == "https://rd/real")
    }

    /// Two genuinely different files for one episode still resolve deterministically — the bigger
    /// one, which is the higher bitrate.
    @Test func theLargestMatchWinsRegardlessOfListOrder() {
        func pack(_ files: [TorrentFile], _ links: [String]) -> TorrentInfo {
            TorrentInfo(id: "P", filename: "Show.S02", hash: "h", bytes: 1, progress: 100,
                        status: "downloaded", files: files, links: links)
        }
        let small = TorrentFile(id: 1, path: "/Show.S02E05.720p.mkv", bytes: 500, selected: 1)
        let big = TorrentFile(id: 2, path: "/Show.S02E05.1080p.mkv", bytes: 5_000, selected: 1)
        #expect(pack([small, big], ["a", "b"]).videoFile(forSeason: 2, episode: 5)?.file.id == 2)
        #expect(pack([big, small], ["b", "a"]).videoFile(forSeason: 2, episode: 5)?.file.id == 2)
    }
}
