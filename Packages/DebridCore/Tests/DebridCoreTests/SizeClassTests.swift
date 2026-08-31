import Testing
@testable import DebridCore

/// `SizeFit` collapses "too big" and "too small" into the same `.far`, which is right for ranking
/// — both should lose — but useless for showing someone WHICH files are the big ones.
///
/// Nothing is filtered out of a version list today; the oversized releases are simply ranked to the
/// bottom of thirty-odd rows, which reads as missing. Telling oversize from undersize is what lets
/// them be grouped into a section of their own instead.
@Suite struct SizeClassTests {
    private let gb = 1_000_000_000

    @Test func aRemuxWellOverTheBandIsOversized() {
        // The 70–80GB 4K Blu-rays the sizing exists to demote. Band for a 2160p film is 12–35GB.
        #expect(sizeClass(bytes: 80 * gb, resolution: "2160p", shape: .movie) == .over)
        #expect(sizeClass(bytes: 36 * gb, resolution: "2160p", shape: .movie) == .over)
    }

    @Test func aFilmInsideItsBandFits() {
        #expect(sizeClass(bytes: 20 * gb, resolution: "2160p", shape: .movie) == .fits)
        #expect(sizeClass(bytes: 12 * gb, resolution: "2160p", shape: .movie) == .fits)
        #expect(sizeClass(bytes: 35 * gb, resolution: "2160p", shape: .movie) == .fits)
    }

    @Test func aFilmWellUnderItsBandIsUndersized() {
        // Usually a mislabelled or upscaled release — it must not be grouped with the big ones.
        #expect(sizeClass(bytes: 2 * gb, resolution: "2160p", shape: .movie) == .under)
    }

    @Test func anEpisodeIsJudgedAgainstEpisodeBandsNotFilmOnes() {
        // 40GB is a plausible film and an absurd episode. Shahar's Sherlock S01E01 is 39.7GB.
        #expect(sizeClass(bytes: 40 * gb, resolution: "2160p", shape: .episode) == .over)
        #expect(sizeClass(bytes: 3 * gb, resolution: "2160p", shape: .episode) == .fits)
    }

    @Test func aSeasonPackIsJudgedPerEpisode() {
        // 100GB across 10 episodes is 10GB each — over the 2160p episode band's 9GB top.
        #expect(sizeClass(bytes: 100 * gb, resolution: "2160p",
                          shape: .seasonPack(episodes: 10)) == .over)
        #expect(sizeClass(bytes: 40 * gb, resolution: "2160p",
                          shape: .seasonPack(episodes: 10)) == .fits)
    }

    @Test func whatCannotBeJudgedIsNeverCalledOversized() {
        // An unknown size, and a pack with no episode count, have nothing to compare against.
        // Guessing "over" would hide a perfectly ordinary release in the big-files section.
        #expect(sizeClass(bytes: nil, resolution: "2160p", shape: .movie) == .fits)
        #expect(sizeClass(bytes: 0, resolution: "2160p", shape: .movie) == .fits)
        #expect(sizeClass(bytes: 500 * gb, resolution: "2160p",
                          shape: .seasonPack(episodes: nil)) == .fits)
    }

    @Test func anUnknownResolutionUsesTheForgivingBand() {
        #expect(sizeClass(bytes: 10 * gb, resolution: nil, shape: .movie) == .fits)
        #expect(sizeClass(bytes: 60 * gb, resolution: nil, shape: .movie) == .over)
    }
}

/// Splitting a ranked list for display. The ranking itself is untouched — the smaller, sensible
/// release stays the default pick — this only decides which section a row is drawn in.
@Suite struct CachedStreamGroupingTests {
    private let gb = 1_000_000_000

    private func stream(_ hash: String, _ gbSize: Int, _ resolution: String?,
                        episode: Int? = nil, season: Int? = nil) -> CachedStream {
        CachedStream(infoHash: hash, fileIdx: nil, rawTitle: hash,
                     parsed: ParsedRelease(title: "T", season: season, episode: episode,
                                           resolution: resolution),
                     languages: [], sizeBytes: gbSize * gb, sourceName: nil)
    }

    @Test func theOversizedOnesAreSeparatedFromTheRest() {
        let list = [stream("a", 80, "2160p"), stream("b", 20, "2160p"), stream("c", 70, "2160p")]
        let (larger, rest) = list.splitOversized(episodesInSeason: nil)
        #expect(larger.map(\.infoHash) == ["a", "c"])
        #expect(rest.map(\.infoHash) == ["b"])
    }

    @Test func theIncomingRankingIsPreservedInsideEachSection() {
        // The list arrives already ranked; grouping must not reorder within a group, or the best
        // pick would stop being the first row.
        let list = [stream("a", 20, "2160p"), stream("b", 80, "2160p"),
                    stream("c", 15, "2160p"), stream("d", 75, "2160p")]
        let (larger, rest) = list.splitOversized(episodesInSeason: nil)
        #expect(larger.map(\.infoHash) == ["b", "d"])
        #expect(rest.map(\.infoHash) == ["a", "c"])
    }

    @Test func nothingOversizedLeavesAnEmptySection() {
        let list = [stream("a", 20, "2160p"), stream("b", 15, "2160p")]
        let (larger, rest) = list.splitOversized(episodesInSeason: nil)
        #expect(larger.isEmpty)
        #expect(rest.count == 2)
    }

    @Test func everythingOversizedStillShowsEveryRow() {
        // The whole point: nothing is dropped. A title that only exists as huge REMUXes must still
        // list all of them rather than showing an empty screen.
        let list = [stream("a", 80, "2160p"), stream("b", 70, "2160p")]
        let (larger, rest) = list.splitOversized(episodesInSeason: nil)
        #expect(larger.count == 2)
        #expect(rest.isEmpty)
        #expect(larger.count + rest.count == list.count)
    }

    @Test func anEpisodeListUsesEpisodeBands() {
        let list = [stream("big", 40, "2160p", episode: 1), stream("ok", 3, "2160p", episode: 1)]
        let (larger, rest) = list.splitOversized(episodesInSeason: nil)
        #expect(larger.map(\.infoHash) == ["big"])
        #expect(rest.map(\.infoHash) == ["ok"])
    }

    @Test func aSeasonPackUsesTheEpisodeCountItIsGiven() {
        let pack = [stream("pack", 100, "2160p", season: 1)]
        #expect(pack.splitOversized(episodesInSeason: 10).larger.count == 1)   // 10GB/episode
        #expect(pack.splitOversized(episodesInSeason: 30).larger.isEmpty)      // 3.3GB/episode
    }
}
