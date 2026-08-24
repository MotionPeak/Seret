import Testing
import Foundation
@testable import DebridCore

/// Every owned copy of an episode must survive into the library.
///
/// The bug this pins: `ShowAccumulator.add` was first-writer-wins, so owning three copies of
/// S01E05 kept whichever torrent iterated first and silently discarded the rest — not the best
/// one, and not a stable choice across refreshes. A movie has always carried `sources` (plural);
/// an episode had exactly one, which also made "Try another version" permanently unavailable
/// mid-playback, so a bad stream in the middle of a season was a dead end.
struct EpisodeAlternatesTests {
    let builder = LibraryBuilder()
    private func gb(_ n: Double) -> Int { Int(n * 1_000_000_000) }

    private func episodeTorrent(_ id: String, name: String, size: Int) -> TorrentInfo {
        TorrentInfo(id: id, filename: name, hash: "h", bytes: size, progress: 100,
                    status: "downloaded",
                    files: [TorrentFile(id: 1, path: "/\(id)/\(name).mkv", bytes: size, selected: 1)],
                    links: ["https://rd/\(id)"])
    }

    @Test func everyOwnedCopyOfAnEpisodeIsKept() {
        let lib = builder.group([
            episodeTorrent("a", name: "Some.Show.S01E05.1080p.WEB-DL.x265", size: gb(2)),
            episodeTorrent("b", name: "Some.Show.S01E05.2160p.WEB-DL.x265", size: gb(5)),
            episodeTorrent("c", name: "Some.Show.S01E05.720p.HDTV.x264", size: gb(1)),
        ])
        let e5 = lib[0].seasons[0].episodes.first { $0.number == 5 }
        #expect(e5?.sources.count == 3)
    }

    /// The primary must be the BEST copy under the ranker, not whichever torrent came first.
    /// Here the 2160p copy is added second.
    @Test func thePrimarySourceIsTheBestOneNotTheFirstSeen() {
        let lib = builder.group([
            episodeTorrent("a", name: "Some.Show.S01E05.720p.HDTV.x264", size: gb(1)),
            episodeTorrent("b", name: "Some.Show.S01E05.2160p.WEB-DL.x265", size: gb(5)),
        ])
        let e5 = lib[0].seasons[0].episodes.first { $0.number == 5 }
        #expect(e5?.source.torrentID == "b")
        #expect(e5?.source.parsed.resolution == "2160p")
    }

    /// Ordering must be deterministic across refreshes — input order must not change the result.
    @Test func orderingIsIndependentOfInputOrder() {
        let a = episodeTorrent("a", name: "Some.Show.S01E05.720p.HDTV.x264", size: gb(1))
        let b = episodeTorrent("b", name: "Some.Show.S01E05.2160p.WEB-DL.x265", size: gb(5))
        let c = episodeTorrent("c", name: "Some.Show.S01E05.1080p.WEB-DL.x265", size: gb(2))

        let forward = builder.group([a, b, c])[0].seasons[0].episodes[0].sources.map(\.torrentID)
        let backward = builder.group([c, b, a])[0].seasons[0].episodes[0].sources.map(\.torrentID)
        #expect(forward == backward)
        #expect(forward.first == "b")
    }

    /// The identical file arriving twice (same torrent + file) is one copy, not two.
    @Test func theSameFileIsNotCountedTwice() {
        let t = episodeTorrent("a", name: "Some.Show.S01E05.1080p.WEB-DL.x265", size: gb(2))
        let e5 = builder.group([t, t])[0].seasons[0].episodes.first { $0.number == 5 }
        #expect(e5?.sources.count == 1)
    }

    /// `sources` is `source` plus the alternates, and is never empty.
    @Test func sourcesIsAlwaysNonEmptyAndLedByThePrimary() {
        let lib = builder.group([
            episodeTorrent("a", name: "Some.Show.S01E05.1080p.WEB-DL.x265", size: gb(2)),
            episodeTorrent("b", name: "Some.Show.S01E05.2160p.WEB-DL.x265", size: gb(5)),
        ])
        let e5 = lib[0].seasons[0].episodes.first { $0.number == 5 }!
        #expect(e5.sources.first == e5.source)
        #expect(e5.sources.count == e5.alternates.count + 1)
        #expect(!e5.sources.isEmpty)
    }

    /// An episode with one copy has no alternates — the common case must stay simple.
    @Test func aSingleCopyHasNoAlternates() {
        let lib = builder.group([episodeTorrent("a", name: "Some.Show.S01E05.1080p.WEB-DL", size: gb(2))])
        let e5 = lib[0].seasons[0].episodes.first { $0.number == 5 }
        #expect(e5?.alternates.isEmpty == true)
        #expect(e5?.sources.count == 1)
    }

    /// A snapshot written before alternates existed must still decode — it is the cached library,
    /// and failing would blank the whole thing until the next refresh.
    @Test func anOldSnapshotWithoutAlternatesStillDecodes() throws {
        let json = #"""
        {"season":1,"number":5,
         "source":{"torrentID":"a","restrictedLink":"rd://a",
                   "parsed":{"title":"Some Show","season":1,"episode":5}}}
        """#
        let episode = try JSONDecoder().decode(Episode.self, from: Data(json.utf8))
        #expect(episode.number == 5)
        #expect(episode.alternates.isEmpty)
        #expect(episode.sources.count == 1)
        #expect(episode.source.torrentID == "a")
    }

    /// Round-tripping keeps the alternates.
    @Test func alternatesSurviveACodableRoundTrip() throws {
        let lib = builder.group([
            episodeTorrent("a", name: "Some.Show.S01E05.1080p.WEB-DL.x265", size: gb(2)),
            episodeTorrent("b", name: "Some.Show.S01E05.2160p.WEB-DL.x265", size: gb(5)),
        ])
        let e5 = lib[0].seasons[0].episodes.first { $0.number == 5 }!
        let data = try JSONEncoder().encode(e5)
        let back = try JSONDecoder().decode(Episode.self, from: data)
        #expect(back.sources.map(\.torrentID) == e5.sources.map(\.torrentID))
    }
}
