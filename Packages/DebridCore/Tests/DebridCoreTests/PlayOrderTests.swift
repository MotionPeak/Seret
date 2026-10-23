import Testing
import DebridCore

/// The owner's rules for the version Play opens (2026-10-23):
/// - English (and Hebrew) films: the REAL 2160p version with the lowest bitrate, else 1080p —
///   never an upscale, an interpolation or a file too thin to be genuine. Hebrew subtitles do not
///   count.
/// - Foreign films: the version whose Hebrew lines up best, then the same picture rules.
@Suite struct PlayOrderTests {
    private static let gb = 1_000_000_000

    private func film(_ id: String, _ res: String, gb: Double?, source: String = "WEB-DL",
                      audio: String? = "EAC3", upscaled: Bool = false) -> MediaSource {
        var parsed = ParsedRelease(title: "t", year: 2020, resolution: res, source: source,
                                   videoCodec: "HEVC", audioCodec: audio)
        parsed.isUpscaled = upscaled
        return MediaSource(torrentID: id, fileID: nil, restrictedLink: "l", parsed: parsed,
                           sizeBytes: gb.map { Int($0 * Double(Self.gb)) })
    }

    private func evidence(_ language: String?, hebrew: [MediaSource: HebrewSubtitles] = [:]) -> SubtitleEvidenceSet {
        var versions: [String: SubtitleEvidence] = [:]
        for (source, level) in hebrew { versions[WatchKey.source(source)] = SubtitleEvidence(hebrew: level) }
        return SubtitleEvidenceSet(byVersion: versions, originalLanguage: language)
    }

    // MARK: - Policy

    @Test func theFilmsLanguageDecidesThePolicy() {
        #expect(PlayPolicy(originalLanguage: "en") == .understood)
        #expect(PlayPolicy(originalLanguage: "he") == .understood)
        #expect(PlayPolicy(originalLanguage: "ko") == .foreign)
        #expect(PlayPolicy(originalLanguage: "fr") == .foreign)
        #expect(PlayPolicy(originalLanguage: nil) == .unknownLanguage)
        #expect(PlayPolicy(originalLanguage: "") == .unknownLanguage)
    }

    // MARK: - English films

    @Test func englishTakesTheLowestBitrateReal2160p() {
        let remux = film("remux", "2160p", gb: 62, source: "REMUX", audio: "DTS-HD")
        let web = film("web", "2160p", gb: 16)
        let encode = film("encode", "2160p", gb: 11, source: "BluRay")
        let hd = film("hd", "1080p", gb: 8)
        let order = [remux, hd, web, encode].bestFirst(subtitles: evidence("en"))
        #expect(order.map(\.torrentID) == ["encode", "web", "remux", "hd"])
    }

    @Test func englishFallsBackTo1080pWhenNo2160pIsReal() {
        let thin = film("thin", "2160p", gb: 3)                 // 4 Mbps over a typical 100 min: not a real 4K
        let ai = film("ai", "2160p", gb: 20, upscaled: true)
        let hd = film("hd", "1080p", gb: 6)
        let order = [thin, ai, hd].bestFirst(subtitles: evidence("en"))
        #expect(order.first?.torrentID == "hd")
    }

    @Test func englishIgnoresHebrewSubtitles() {
        let uhd = film("uhd", "2160p", gb: 15)
        let hebrew = film("hebrew", "1080p", gb: 6)
        let order = [uhd, hebrew].bestFirst(subtitles: evidence("en", hebrew: [hebrew: .builtIn]))
        #expect(order.first?.torrentID == "uhd")
    }

    @Test func aThin1080pIsNotPickedOverARealOne() {
        let thin = film("thin", "1080p", gb: 1)                 // 1.3 Mbps over 100 min
        let real = film("real", "1080p", gb: 5)
        #expect([thin, real].bestFirst(subtitles: evidence("en")).first?.torrentID == "real")
    }

    /// The bitrate is judged over a typical 100-minute film, never the title's own runtime, so
    /// every screen (Home's Resume included) picks the same file.
    @Test func thinnessIsJudgedOverATypicalLength() {
        let thin = film("thin", "2160p", gb: 4)                 // 5.3 Mbps over 100 min
        let hd = film("hd", "1080p", gb: 6)
        let real = film("real", "2160p", gb: 9)
        #expect([thin, hd].bestFirst(subtitles: evidence("en")).first?.torrentID == "hd")
        #expect([thin, hd, real].bestFirst(subtitles: evidence("en")).first?.torrentID == "real")
    }

    /// From the owner's library: a 1.7 GB 1080p encode is real 1080p, and must beat a 720p file.
    @Test func aSmall1080pEncodeIsStillReal1080p() {
        let small = film("small", "1080p", gb: 1.7)
        let sd = film("sd", "720p", gb: 9.1)
        #expect([sd, small].bestFirst(subtitles: evidence("en")).first?.torrentID == "small")
    }

    @Test func anUnknownSizeRanksAfterKnownOnesAtItsResolution() {
        let unknown = film("unknown", "2160p", gb: nil)
        let known = film("known", "2160p", gb: 20)
        #expect([unknown, known].bestFirst(subtitles: evidence("en"))
            .map(\.torrentID) == ["known", "unknown"])
    }

    @Test func playableAudioStillComesFirst() {
        let silent = film("silent", "2160p", gb: 14, audio: "TrueHD")
        let sound = film("sound", "2160p", gb: 30)
        #expect([silent, sound].bestFirst(subtitles: evidence("en")).first?.torrentID == "sound")
    }

    @Test func theatreCopiesAreNeverTheRealPicture() {
        let cam = film("cam", "2160p", gb: 15, source: "CAM")
        let hd = film("hd", "1080p", gb: 6)
        #expect([cam, hd].bestFirst(subtitles: evidence("en")).first?.torrentID == "hd")
    }

    // MARK: - Foreign films

    @Test func foreignPutsTheBestAlignedHebrewFirst() {
        let uhd = film("uhd", "2160p", gb: 15)
        let matched = film("matched", "1080p", gb: 6)
        let inFile = film("inFile", "1080p", gb: 9)
        let order = [uhd, matched, inFile].bestFirst(
            subtitles: evidence("ko", hebrew: [matched: .matched, inFile: .builtIn]))
        #expect(order.map(\.torrentID) == ["inFile", "matched", "uhd"])
    }

    @Test func foreignAppliesThePictureRulesAmongEqualHebrew() {
        let remux = film("remux", "2160p", gb: 60, source: "REMUX")
        let web = film("web", "2160p", gb: 14)
        let hd = film("hd", "1080p", gb: 6)
        let order = [remux, hd, web].bestFirst(
            subtitles: evidence("ja", hebrew: [remux: .matched, web: .matched, hd: .matched]))
        #expect(order.map(\.torrentID) == ["web", "remux", "hd"])
    }

    @Test func anUpscaleNeverWinsOnItsHebrew() {
        let fake = film("fake", "2160p", gb: 20, upscaled: true)
        let real = film("real", "1080p", gb: 6)
        let order = [fake, real].bestFirst(subtitles: evidence("fr", hebrew: [fake: .builtIn]))
        #expect(order.first?.torrentID == "real")
    }

    /// A Hebrew-language film needs no subtitles: it is ranked like an English one.
    @Test func aHebrewFilmIsRankedLikeAnEnglishOne() {
        let uhd = film("uhd", "2160p", gb: 15)
        let subs = film("subs", "1080p", gb: 6)
        #expect([uhd, subs].bestFirst(subtitles: evidence("he", hebrew: [subs: .builtIn])).first?.torrentID == "uhd")
    }

    // MARK: - Search results (not yet added)

    private func stream(_ hash: String, _ res: String, gb: Double?, langs: [String] = [],
                        name: String? = nil, season: Int? = nil) -> CachedStream {
        let raw = name ?? "Film.2020.\(res).WEB-DL.x265-\(hash)"
        var parsed = FilenameParser().parse(raw)
        if let season { parsed.season = season }
        return CachedStream(infoHash: hash, fileIdx: nil, rawTitle: raw, parsed: parsed, languages: langs,
                            sizeBytes: gb.map { Int($0 * Double(Self.gb)) }, sourceName: nil, isCached: true)
    }

    @Test func searchResultsFollowTheSameRules() {
        let remux = stream("remux", "2160p", gb: 58)
        let web = stream("web", "2160p", gb: 15)
        let upscale = stream("upscale", "2160p", gb: 12, name: "Film.2020.2160p.AI.Upscale.x265-GRP")
        let hd = stream("hd", "1080p", gb: 7)
        let order = [remux, hd, upscale, web].rankedFor(originalLanguage: "en")
        #expect(order.map(\.infoHash) == ["web", "remux", "hd", "upscale"])
    }

    @Test func searchResultsKeepTheOriginalAudioFirst() {
        let dub = stream("dub", "2160p", gb: 14, langs: ["it"])
        let original = stream("orig", "1080p", gb: 6, langs: ["en"])
        #expect([dub, original].rankedFor(originalLanguage: "en").first?.infoHash == "orig")
    }

    @Test func aSeasonPackIsJudgedPerEpisode() {
        // 10 episodes: 30 GB is 3 GB an episode, lighter than a 4 GB single episode.
        let pack = stream("pack", "2160p", gb: 30, name: "Show.S01.2160p.WEB-DL.x265-GRP")
        let single = stream("single", "2160p", gb: 4, name: "Show.S01E01.2160p.WEB-DL.x265-GRP")
        #expect([single, pack].rankedFor(originalLanguage: "en", episodesInSeason: 10)
            .first?.infoHash == "pack")
    }
}

/// Release names that say the picture is not what its resolution claims.
@Suite struct UpscaleTagTests {
    private func upscaled(_ name: String) -> Bool { FilenameParser().parse(name).isUpscaled }

    @Test func aiUpscalesAreFlagged() {
        #expect(upscaled("Heat.1995.2160p.AI.Upscale.x265-GRP"))
        #expect(upscaled("Heat.1995.2160p.UPSCALED.HEVC.mkv"))
        #expect(upscaled("Heat 1995 2160p Upscaled SDR x265"))
        #expect(upscaled("Heat.1995.2160p.AI-Upscale.HDR.x265"))
        #expect(upscaled("Heat.1995.2160p.AI.Enhanced.x265"))
        #expect(upscaled("Heat.1995.2160p.Topaz.x265"))
        #expect(upscaled("Heat.AI.Upscale.2160p.x265"))                 // no year: the whole name
    }

    @Test func interpolatedFilmsAreFlagged() {
        #expect(upscaled("Heat.1995.2160p.60fps.HEVC.mkv"))
        #expect(upscaled("Heat.1995.1080p.60FPS.x264"))
        #expect(upscaled("Heat.1995.2160p.RIFE.x265"))
        #expect(upscaled("Heat.1995.1080p.Interpolated.x264"))
        #expect(upscaled("Heat.1995.2160p.Fake.HDR.x265"))
    }

    @Test func ordinaryReleasesAreNot() {
        #expect(!upscaled("Heat.1995.2160p.UHD.BluRay.REMUX.HDR.HEVC.DTS-HD.MA.5.1-FGT"))
        #expect(!upscaled("Heat.1995.Remastered.1080p.BluRay.x264-SPARKS"))
        #expect(!upscaled("A.I.Artificial.Intelligence.2001.1080p.BluRay.x264"))
        #expect(!upscaled("AI.2024.1080p.WEB-DL.x264"))              // a film called "AI"
        #expect(!upscaled("Ai.No.Kusabi.1992.1080p.x264"))
        #expect(!upscaled("Upscale.Living.2019.1080p.WEB.x264"))      // the title, before the year
        #expect(!upscaled("Waltz.with.Bashir.2008.1080p.BluRay.AI.HebSubs"))   // AI-translated subtitles
        #expect(!upscaled("Gemini.Man.2019.2160p.HFR.120fps.x265"))   // genuine high frame rate
        #expect(!upscaled("The.Hobbit.2012.1080p.HFR.48fps.x264"))
    }

    /// 50 or 60 frames a second is real broadcast television; on a film it is interpolation.
    @Test func highFrameRateTelevisionIsNot() {
        #expect(!upscaled("Match.of.the.Day.S61E10.1080p.50fps.HDTV.x264"))
        #expect(!upscaled("Show.S01E01.2160p.60fps.WEB-DL.x265"))
    }

    @Test func theFlagSurvivesFillingInFromThePack() {
        let pack = FilenameParser().parse("Show.S01.2160p.AI.Upscale.x265-GRP")
        let file = FilenameParser().parse("Show.S01E03.mkv")
        #expect(file.completed(from: pack).isUpscaled)
    }
}
