import Testing
@testable import DebridCore

/// A season pack added through RD is routinely NAMED after the first episode it contains, because
/// that is what the indexer titled it. `ingestTV` branched on the torrent NAME: seeing an episode
/// number there, it added that one episode and returned — so every other episode in the torrent was
/// never looked at, and a pack the viewer added showed exactly one episode.
///
/// The existing code already knew the name can lie; it used the lie only to pick the right FILE,
/// not to notice that the torrent holds a whole season.
struct PackNamedForOneEpisodeTests {
    private let builder = LibraryBuilder()

    private func file(_ id: Int, _ path: String, bytes: Int = 1_000_000_000) -> TorrentFile {
        TorrentFile(id: id, path: path, bytes: bytes, selected: 1)
    }

    private func torrent(_ name: String, _ files: [TorrentFile]) -> TorrentInfo {
        TorrentInfo(id: "T1", filename: name, hash: "h", bytes: 1, progress: 100,
                    status: "downloaded", files: files,
                    links: files.map { "https://rd/\($0.id)" }, added: "2024-01-01T00:00:00Z")
    }

    private func episodes(_ items: [MediaItem]) -> [Int] {
        (items.first?.seasons.first?.episodes ?? []).map(\.number).sorted()
    }

    @Test func aPackNamedForItsFirstEpisodeStillYieldsEveryEpisode() {
        let info = torrent("Some.Show.S01E01.1080p.WEB-DL.x264-GRP", [
            file(1, "/Some.Show.S01/Some.Show.S01E01.1080p.WEB-DL.x264-GRP.mkv"),
            file(2, "/Some.Show.S01/Some.Show.S01E02.1080p.WEB-DL.x264-GRP.mkv"),
            file(3, "/Some.Show.S01/Some.Show.S01E03.1080p.WEB-DL.x264-GRP.mkv"),
        ])
        let items = builder.group([info])
        #expect(items.count == 1)
        #expect(episodes(items) == [1, 2, 3])
    }

    /// …and each episode must point at its OWN file, not all at the named one.
    @Test func eachExpandedEpisodePointsAtItsOwnFile() {
        let info = torrent("Some.Show.S02E05.1080p.WEB-DL", [
            file(1, "/Some.Show.S02E05.mkv"),
            file(2, "/Some.Show.S02E06.mkv"),
        ])
        let eps = builder.group([info]).first?.seasons.first?.episodes ?? []
        #expect(eps.first(where: { $0.number == 5 })?.source.fileID == 1)
        #expect(eps.first(where: { $0.number == 6 })?.source.fileID == 2)
    }

    /// The guard that matters most: a genuine single-episode torrent must NOT change. Its extra
    /// files (a sample, an .nfo, a featurette naming the same episode) name no other episode, so
    /// there is nothing to expand and the largest real file still wins.
    @Test func aGenuineSingleEpisodeTorrentIsUnchanged() {
        let info = torrent("Some.Show.S01E04.1080p.WEB-DL", [
            file(1, "/Sample/Some.Show.S01E04.sample.mkv", bytes: 40_000_000),
            file(2, "/Some.Show.S01E04.1080p.WEB-DL.mkv", bytes: 2_000_000_000),
        ])
        let eps = builder.group([info]).first?.seasons.first?.episodes ?? []
        #expect(eps.map(\.number) == [4])
        #expect(eps.first?.source.fileID == 2)
    }

    /// A torrent whose name states an episode but whose files name none at all still falls back to
    /// the largest video, so an oddly-named single episode is not dropped.
    @Test func aTorrentWhoseFilesNameNoEpisodeStillFallsBackToTheLargest() {
        let info = torrent("Some.Show.S01E07.1080p.WEB-DL", [
            file(1, "/video.mkv", bytes: 2_000_000_000),
        ])
        let eps = builder.group([info]).first?.seasons.first?.episodes ?? []
        #expect(eps.map(\.number) == [7])
        #expect(eps.first?.source.fileID == 1)
    }

    /// A pack spanning two seasons that is named for one episode must place each file in the
    /// season its own name states.
    @Test func anExpandedPackRespectsEachFilesOwnSeason() {
        let info = torrent("Some.Show.S01E01.1080p.WEB-DL", [
            file(1, "/Some.Show.S01E01.mkv"),
            file(2, "/Some.Show.S02E01.mkv"),
        ])
        let item = builder.group([info]).first
        #expect(item?.seasons.map(\.number).sorted() == [1, 2])
    }

    /// Files inside a pack are often named far more sparsely than the pack itself. Expanding using
    /// only the file's own parse stripped the resolution, source and codec that were stated on the
    /// torrent — which is what the ranker and the Versions list read.
    @Test func anExpandedEpisodeKeepsTheQualityStatedOnTheTorrent() {
        let info = torrent("Some.Show.S01E01.2160p.BluRay.REMUX.x265-GRP", [
            file(1, "/S01E01.mkv"),
            file(2, "/S01E02.mkv"),
        ])
        let eps = builder.group([info]).first?.seasons.first?.episodes ?? []
        #expect(eps.count == 2)
        for ep in eps {
            #expect(ep.source.parsed.resolution == "2160p")
            #expect(ep.source.parsed.source == "REMUX")
            #expect(ep.source.parsed.videoCodec == "x265")
        }
    }

    /// …but a file that states its OWN quality keeps it — the torrent is only a fallback.
    @Test func aFileStatingItsOwnQualityIsNotOverriddenByTheTorrent() {
        let info = torrent("Some.Show.S01E01.2160p.BluRay.REMUX", [
            file(1, "/Some.Show.S01E01.1080p.WEB-DL.mkv"),
            file(2, "/Some.Show.S01E02.1080p.WEB-DL.mkv"),
        ])
        let eps = builder.group([info]).first?.seasons.first?.episodes ?? []
        #expect(eps.allSatisfy { $0.source.parsed.resolution == "1080p" })
        #expect(eps.allSatisfy { $0.source.parsed.source == "WEB-DL" })
    }
}
