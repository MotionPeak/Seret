import Testing
@testable import DebridCore

/// Size fit must sit ABOVE source tier in the ordering.
///
/// It cannot merely break ties: `REMUX` is the top source tier and is 60–90 GB by construction,
/// so a tie-breaking size term is consulted only after the bloat has already won. That is why the
/// default 4K pick was always an 80 GB remux.
struct SizeAwareRankingTests {
    private func gb(_ n: Double) -> Int { Int(n * 1_000_000_000) }

    private func stream(_ hash: String, res: String, source: String, size: Int,
                        season: Int? = nil, episode: Int? = nil) -> CachedStream {
        CachedStream(infoHash: hash, fileIdx: nil, rawTitle: hash,
                     parsed: ParsedRelease(title: "t", season: season, episode: episode,
                                           resolution: res, source: source),
                     languages: ["en"], sizeBytes: size, sourceName: nil)
    }

    /// The headline case: a right-sized WEB-DL beats a bloated REMUX of the same resolution.
    @Test func aRightSizedWebDLBeatsABloatedRemux() {
        let remux = stream("remux", res: "2160p", source: "REMUX", size: gb(80))
        let webdl = stream("webdl", res: "2160p", source: "WEB-DL", size: gb(24))
        #expect([remux, webdl].rankedFor(originalLanguage: "en").first?.infoHash == "webdl")
    }

    /// Quality is not sacrificed: inside one band, source tier still decides. A right-sized REMUX
    /// is the best of both and must win.
    @Test func insideTheBandSourceTierStillDecides() {
        let remux = stream("remux", res: "2160p", source: "REMUX", size: gb(30))
        let webdl = stream("webdl", res: "2160p", source: "WEB-DL", size: gb(24))
        #expect([webdl, remux].rankedFor(originalLanguage: "en").first?.infoHash == "remux")
    }

    /// Resolution still dominates size — a right-sized 1080p must not beat a right-sized 2160p.
    @Test func resolutionStillOutranksSizeFit() {
        let uhd = stream("uhd", res: "2160p", source: "WEB-DL", size: gb(25))
        let hd = stream("hd", res: "1080p", source: "WEB-DL", size: gb(10))
        #expect([hd, uhd].rankedFor(originalLanguage: "en").first?.infoHash == "uhd")
    }

    /// When everything on offer is oversized they tie on fit, and the old quality ordering still
    /// picks one. Nothing becomes unplayable — the policy removes a default, not a capability.
    @Test func whenEverythingIsBloatedTheBestQualityStillWins() {
        let remux = stream("remux", res: "2160p", source: "REMUX", size: gb(85))
        let bluray = stream("bluray", res: "2160p", source: "BluRay", size: gb(75))
        #expect([bluray, remux].rankedFor(originalLanguage: "en").first?.infoHash == "remux")
    }

    /// Within one fit band, bigger is still better — it means a higher bitrate at the same size
    /// class. The old preference survives, just scoped to sensible files.
    @Test func withinABandBiggerStillWins() {
        let small = stream("small", res: "2160p", source: "WEB-DL", size: gb(15))
        let large = stream("large", res: "2160p", source: "WEB-DL", size: gb(30))
        #expect([small, large].rankedFor(originalLanguage: "en").first?.infoHash == "large")
    }

    /// Original-language audio still dominates everything, including fit.
    @Test func audioTierStillDominates() {
        let bloatedOriginal = stream("orig", res: "2160p", source: "REMUX", size: gb(85))
        let rightSizedDub = stream("dub", res: "2160p", source: "WEB-DL", size: gb(24))
        let ranked = [rightSizedDub, bloatedOriginal].rankedFor(originalLanguage: "en")
        // "dub" carries only `en` too, so both are tier 0 here — assert the ordering holds when
        // the foreign one genuinely lacks the original track.
        _ = ranked
        let foreign = CachedStream(infoHash: "foreign", fileIdx: nil, rawTitle: "foreign",
                                   parsed: ParsedRelease(title: "t", resolution: "2160p",
                                                         source: "WEB-DL"),
                                   languages: ["ru"], sizeBytes: gb(24), sourceName: nil)
        #expect([foreign, bloatedOriginal].rankedFor(originalLanguage: "en").first?.infoHash == "orig")
    }

    /// An episode is judged against episode bands: a 25 GB "episode" is bloat even though the
    /// same byte count is an ideal film.
    @Test func anEpisodeIsJudgedAgainstEpisodeBands() {
        let bloated = stream("big", res: "2160p", source: "REMUX", size: gb(25), season: 1, episode: 1)
        let sane = stream("sane", res: "2160p", source: "WEB-DL", size: gb(5), season: 1, episode: 1)
        #expect([bloated, sane].rankedFor(originalLanguage: "en").first?.infoHash == "sane")
    }

    /// A season pack must not be demoted for being large — without an episode count there is
    /// nothing to compare it against, and penalising it would rank every pack last.
    @Test func aSeasonPackIsNotDemotedForBeingLarge() {
        let pack = stream("pack", res: "2160p", source: "REMUX", size: gb(200), season: 1)
        let other = stream("other", res: "2160p", source: "WEB-DL", size: gb(60), season: 1)
        #expect([other, pack].rankedFor(originalLanguage: "en").first?.infoHash == "pack")
    }
}

/// The same policy must apply to titles already in the library, or the Versions list keeps
/// recommending the bloat the search flow now avoids.
struct OwnedSourceSizeRankingTests {
    private func gb(_ n: Double) -> Int { Int(n * 1_000_000_000) }

    private func source(_ id: String, res: String, source: String, size: Int?) -> MediaSource {
        MediaSource(torrentID: id, fileID: nil, restrictedLink: "rd://\(id)",
                    parsed: ParsedRelease(title: "t", resolution: res, source: source),
                    sizeBytes: size)
    }

    @Test func aRightSizedOwnedVersionOutranksABloatedOne() {
        let remux = source("remux", res: "2160p", source: "REMUX", size: gb(80))
        let webdl = source("webdl", res: "2160p", source: "WEB-DL", size: gb(24))
        #expect([remux, webdl].best?.torrentID == "webdl")
    }

    @Test func insideTheBandSourceTierStillDecides() {
        let remux = source("remux", res: "2160p", source: "REMUX", size: gb(30))
        let webdl = source("webdl", res: "2160p", source: "WEB-DL", size: gb(24))
        #expect([webdl, remux].best?.torrentID == "remux")
    }

    /// Old cached snapshots carry no size. Those must stay orderable and deterministic rather
    /// than all collapsing to one bucket in an arbitrary order.
    @Test func sourcesWithNoRecordedSizeStillOrderDeterministically() {
        let a = source("a", res: "2160p", source: "WEB-DL", size: nil)
        let b = source("b", res: "1080p", source: "WEB-DL", size: nil)
        #expect([b, a].bestFirst().map(\.torrentID) == ["a", "b"])
    }
}
