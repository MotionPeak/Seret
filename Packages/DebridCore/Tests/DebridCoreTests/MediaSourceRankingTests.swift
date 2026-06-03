import Testing
import DebridCore

@Suite struct MediaSourceRankingTests {
    private func src(_ id: String, _ res: String?, _ source: String? = nil, _ codec: String? = nil) -> MediaSource {
        MediaSource(torrentID: id, fileID: nil, restrictedLink: "l",
                    parsed: ParsedRelease(title: "t", resolution: res, source: source, videoCodec: codec))
    }

    @Test func ordersByResolutionThenSourceThenCodec() {
        let s2160 = src("a", "2160p", "REMUX", "HEVC")   // 40702
        let s1080blu = src("c", "1080p", "BluRay", "x265") // 30602
        let s1080web = src("b", "1080p", "WEB-DL", "x264") // 30501
        let s720 = src("d", "720p")                        // 20000
        #expect([s720, s1080web, s2160, s1080blu].bestFirst().map(\.torrentID) == ["a", "c", "b", "d"])
    }

    @Test func bestPicksHighest() {
        #expect([src("a", "1080p"), src("b", "2160p")].best?.torrentID == "b")
    }

    @Test func tieBreaksByTorrentIDForStableOrder() {
        let x = src("z", "1080p", "WEB-DL", "x264")
        let y = src("a", "1080p", "WEB-DL", "x264")
        #expect([x, y].bestFirst().map(\.torrentID) == ["a", "z"])
    }

    @Test func unknownFieldsRankLowest() {
        #expect([src("b", nil), src("a", "1080p")].bestFirst().map(\.torrentID) == ["a", "b"])
    }

    @Test func emptyHasNoBest() {
        #expect([MediaSource]().best == nil)
    }

    @Test func tieBreaksByFileIDWhenRankAndTorrentMatch() {
        let a = MediaSource(torrentID: "t", fileID: 1, restrictedLink: "l",
                            parsed: ParsedRelease(title: "x", resolution: "1080p"))
        let b = MediaSource(torrentID: "t", fileID: 2, restrictedLink: "l",
                            parsed: ParsedRelease(title: "x", resolution: "1080p"))
        #expect([b, a].bestFirst().map(\.fileID) == [1, 2])
    }
}
