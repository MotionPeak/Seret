import Testing
@testable import DebridCore

/// Size sits ABOVE source tier in the ordering.
///
/// It cannot merely break ties: `REMUX` is the top source tier and is 60–90 GB by construction,
/// so a tie-breaking size term is consulted only after the bloat has already won. That is why the
/// default 4K pick was always an 80 GB remux. Since 2026-10-23 the owner's rule goes further: the
/// LIGHTEST real version of the best resolution wins (see `PlayPolicy`).
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

    /// Inside one band the lighter real version wins: it starts and skips faster.
    @Test func insideTheBandTheLighterVersionWins() {
        let remux = stream("remux", res: "2160p", source: "REMUX", size: gb(30))
        let webdl = stream("webdl", res: "2160p", source: "WEB-DL", size: gb(24))
        #expect([remux, webdl].rankedFor(originalLanguage: "en").first?.infoHash == "webdl")
    }

    /// Resolution still dominates size — a right-sized 1080p must not beat a right-sized 2160p.
    @Test func resolutionStillOutranksSizeFit() {
        let uhd = stream("uhd", res: "2160p", source: "WEB-DL", size: gb(25))
        let hd = stream("hd", res: "1080p", source: "WEB-DL", size: gb(10))
        #expect([hd, uhd].rankedFor(originalLanguage: "en").first?.infoHash == "uhd")
    }

    /// When everything on offer is oversized the lighter one still wins. Nothing becomes
    /// unplayable — the policy removes a default, not a capability.
    @Test func whenEverythingIsBloatedTheLighterStillWins() {
        let remux = stream("remux", res: "2160p", source: "REMUX", size: gb(85))
        let bluray = stream("bluray", res: "2160p", source: "BluRay", size: gb(75))
        #expect([remux, bluray].rankedFor(originalLanguage: "en").first?.infoHash == "bluray")
    }

    /// Within one band the lighter file wins — the owner's "lowest bitrate above the floor".
    @Test func withinABandTheLighterWins() {
        let small = stream("small", res: "2160p", source: "WEB-DL", size: gb(15))
        let large = stream("large", res: "2160p", source: "WEB-DL", size: gb(30))
        #expect([large, small].rankedFor(originalLanguage: "en").first?.infoHash == "small")
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

    @Test func insideTheBandTheLighterOwnedVersionWins() {
        let remux = source("remux", res: "2160p", source: "REMUX", size: gb(30))
        let webdl = source("webdl", res: "2160p", source: "WEB-DL", size: gb(24))
        #expect([remux, webdl].best?.torrentID == "webdl")
    }

    /// Old cached snapshots carry no size. Those must stay orderable and deterministic rather
    /// than all collapsing to one bucket in an arbitrary order.
    @Test func sourcesWithNoRecordedSizeStillOrderDeterministically() {
        let a = source("a", res: "2160p", source: "WEB-DL", size: nil)
        let b = source("b", res: "1080p", source: "WEB-DL", size: nil)
        #expect([b, a].bestFirst().map(\.torrentID) == ["a", "b"])
    }
}
