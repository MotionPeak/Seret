import Testing
@testable import DebridCore

/// A version list is drawn Instant first, Download last. The ranking interleaves the two — it
/// judges quality, size and Hebrew, never whether Real-Debrid already has the file — so a release
/// that plays at once could sit under several that must download first.
@Suite struct VersionGroupTests {
    private let gb = 1_000_000_000

    private func stream(_ hash: String, cached: Bool, _ gbSize: Int = 20,
                        season: Int? = nil) -> CachedStream {
        CachedStream(infoHash: hash, fileIdx: nil, rawTitle: hash,
                     parsed: ParsedRelease(title: "T", season: season, resolution: "2160p"),
                     languages: [], sizeBytes: gbSize * gb, sourceName: nil, isCached: cached)
    }

    @Test func everyInstantVersionComesBeforeEveryDownload() {
        let list = [stream("d1", cached: false), stream("i1", cached: true),
                    stream("d2", cached: false), stream("i2", cached: true)]
        let groups = list.groupedByAvailability(episodesInSeason: nil)
        #expect(groups.map(\.availability) == [.instant, .download])
        #expect(groups[0].rest.map(\.infoHash) == ["i1", "i2"])
        #expect(groups[1].rest.map(\.infoHash) == ["d1", "d2"])
    }

    @Test func theRankingHoldsInsideEachGroup() {
        // The list arrives ranked. Re-sorting inside a group (by size, say) would stop the best
        // instant release being the first row.
        let list = [stream("i-best", cached: true, 30), stream("d-best", cached: false, 25),
                    stream("i-next", cached: true, 14), stream("i-last", cached: true, 33)]
        let instant = list.groupedByAvailability(episodesInSeason: nil)[0]
        #expect(instant.rest.map(\.infoHash) == ["i-best", "i-next", "i-last"])
    }

    @Test func eachGroupSplitsOffItsOwnOversizedReleases() {
        // An oversized download must not climb into the instant block just for being big.
        let list = [stream("i-ok", cached: true, 20), stream("d-huge", cached: false, 80),
                    stream("i-huge", cached: true, 75), stream("d-ok", cached: false, 15)]
        let groups = list.groupedByAvailability(episodesInSeason: nil)
        #expect(groups[0].larger.map(\.infoHash) == ["i-huge"])
        #expect(groups[0].rest.map(\.infoHash) == ["i-ok"])
        #expect(groups[1].larger.map(\.infoHash) == ["d-huge"])
        #expect(groups[1].rest.map(\.infoHash) == ["d-ok"])
    }

    @Test func aBlockWithNothingInItIsLeftOut() {
        // An empty block would draw a heading over no rows.
        let instantOnly = [stream("i1", cached: true), stream("i2", cached: true, 80)]
        #expect(instantOnly.groupedByAvailability(episodesInSeason: nil).map(\.availability) == [.instant])
        let downloadOnly = [stream("d1", cached: false)]
        #expect(downloadOnly.groupedByAvailability(episodesInSeason: nil).map(\.availability) == [.download])
        #expect([CachedStream]().groupedByAvailability(episodesInSeason: nil).isEmpty)
    }

    @Test func aSeasonPackIsJudgedPerEpisodeInsideItsGroup() {
        // 100GB over 10 episodes is 10GB each, over the 2160p episode band; over 30 it is not.
        let pack = [stream("pack", cached: true, 100, season: 1)]
        #expect(pack.groupedByAvailability(episodesInSeason: 10)[0].larger.map(\.infoHash) == ["pack"])
        #expect(pack.groupedByAvailability(episodesInSeason: 30)[0].larger.isEmpty)
    }
}
