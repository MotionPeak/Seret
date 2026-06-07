import Testing
@testable import DebridCore

@Suite struct CachedStreamRankingTests {
    func stream(_ hash: String, res: String, langs: [String], size: Int) -> CachedStream {
        CachedStream(infoHash: hash, fileIdx: nil, rawTitle: "t",
                     parsed: ParsedRelease(title: "t", resolution: res),
                     languages: langs, sizeBytes: size, sourceName: nil)
    }

    @Test func originalLanguageOutranksHigherQuality() {
        let dub4k = stream("a", res: "2160p", langs: ["en"], size: 100)
        let orig1080 = stream("b", res: "1080p", langs: ["fr"], size: 50)
        let ranked = [dub4k, orig1080].rankedFor(originalLanguage: "fr")
        #expect(ranked.first?.infoHash == "b")
    }

    @Test func qualityBreaksTiesAmongOriginalLanguage() {
        let orig4k = stream("a", res: "2160p", langs: ["fr"], size: 10)
        let orig1080 = stream("b", res: "1080p", langs: ["fr"], size: 10)
        let ranked = [orig1080, orig4k].rankedFor(originalLanguage: "fr")
        #expect(ranked.first?.infoHash == "a")
    }

    @Test func sizeBreaksQualityTies() {
        let big = stream("a", res: "2160p", langs: ["fr"], size: 200)
        let small = stream("b", res: "2160p", langs: ["fr"], size: 100)
        let ranked = [small, big].rankedFor(originalLanguage: "fr")
        #expect(ranked.first?.infoHash == "a")
    }

    @Test func bestMatchFlagsFallbackWhenNoOriginalLanguage() {
        let dub = stream("a", res: "2160p", langs: ["en"], size: 100)
        let match = [dub].bestMatch(originalLanguage: "fr")
        #expect(match?.stream.infoHash == "a")
        #expect(match?.isFallback == true)
    }

    @Test func bestMatchNotFallbackWhenOriginalPresent() {
        let orig = stream("a", res: "1080p", langs: ["fr"], size: 100)
        let match = [orig].bestMatch(originalLanguage: "fr")
        #expect(match?.isFallback == false)
    }

    @Test func nilOriginalLanguageRanksByQualityOnly() {
        let hi = stream("a", res: "2160p", langs: ["en"], size: 1)
        let lo = stream("b", res: "720p", langs: ["fr"], size: 1)
        let ranked = [lo, hi].rankedFor(originalLanguage: nil)
        #expect(ranked.first?.infoHash == "a")
        #expect([hi].bestMatch(originalLanguage: nil)?.isFallback == false)
    }

    @Test func cleanUntaggedBeatsForeignDub() {
        // The Split case: a clean (untagged) English REMUX must outrank a bigger German dual-audio
        // dub for an English-original film — absence of a language tag ≠ a foreign dub.
        let cleanUntagged = stream("clean", res: "2160p", langs: [], size: 53)
        let germanDual = stream("ger", res: "2160p", langs: ["en", "de"], size: 58)  // bigger
        let ranked = [germanDual, cleanUntagged].rankedFor(originalLanguage: "en")
        #expect(ranked.first?.infoHash == "clean")
        let match = [germanDual, cleanUntagged].bestMatch(originalLanguage: "en")
        #expect(match?.stream.infoHash == "clean")
        #expect(match?.isFallback == false)   // clean untagged isn't flagged as a dub
    }

    @Test func foreignOnlyDubIsFlaggedFallback() {
        let italianOnly = stream("ita", res: "2160p", langs: ["it"], size: 50)
        let match = [italianOnly].bestMatch(originalLanguage: "en")
        #expect(match?.isFallback == true)   // no English at all → genuine fallback
    }

    @Test func qualityDominatesWithinSameAudioTier() {
        // A 720p English tag must NOT outrank a 2160p clean release just because it's tagged.
        let tagged720 = stream("a", res: "720p", langs: ["en"], size: 1)   // tier 0 (explicit en)
        let untagged4k = stream("b", res: "2160p", langs: [], size: 50)    // tier 0 (untagged Latin)
        let ranked = [tagged720, untagged4k].rankedFor(originalLanguage: "en")
        #expect(ranked.first?.infoHash == "b")
    }

    @Test func foreignScriptUntaggedTitleIsDemoted() {
        // A 68GB untagged Cyrillic "Сплит" REMUX is a Russian release — must lose to clean English.
        let cyrillic = CachedStream(infoHash: "ru", fileIdx: nil, rawTitle: "Сплит.2016.UHD.Remux.2160p",
                                    parsed: ParsedRelease(title: "Сплит", resolution: "2160p"),
                                    languages: [], sizeBytes: 68_000_000_000, sourceName: nil)
        let cleanEn = stream("en", res: "1080p", langs: ["en"], size: 10)
        let ranked = [cyrillic, cleanEn].rankedFor(originalLanguage: "en")
        #expect(ranked.first?.infoHash == "en")
        #expect([cyrillic].bestMatch(originalLanguage: "en")?.isFallback == true)
    }

    @Test func bestMatchNilWhenEmpty() {
        #expect([CachedStream]().bestMatch(originalLanguage: "en") == nil)
    }

    // MARK: - Season packs

    func packStream(_ hash: String, season: Int, res: String, langs: [String] = ["en"]) -> CachedStream {
        CachedStream(infoHash: hash, fileIdx: nil, rawTitle: "t",
                     parsed: ParsedRelease(title: "t", season: season, episode: nil, resolution: res),
                     languages: langs, sizeBytes: 1, sourceName: nil)
    }
    func epStream(_ hash: String, season: Int, episode: Int, res: String, langs: [String] = ["en"]) -> CachedStream {
        CachedStream(infoHash: hash, fileIdx: nil, rawTitle: "t",
                     parsed: ParsedRelease(title: "t", season: season, episode: episode, resolution: res),
                     languages: langs, sizeBytes: 1, sourceName: nil)
    }

    @Test func seasonPacksKeepsOnlyWholeSeasonReleasesForThatSeason() {
        let pack1 = packStream("p1", season: 1, res: "2160p")            // S01 pack ✓
        let ep    = epStream("e1", season: 1, episode: 1, res: "2160p")  // single episode ✗
        let pack2 = packStream("p2", season: 2, res: "1080p")            // wrong season ✗
        // Complete-series pack: no parsed season → excluded (would pull every season).
        let complete = CachedStream(infoHash: "c", fileIdx: nil, rawTitle: "t",
                                    parsed: ParsedRelease(title: "t", resolution: "2160p"),
                                    languages: ["en"], sizeBytes: 1, sourceName: nil)
        let packs = [pack1, ep, pack2, complete].seasonPacks(forSeason: 1)
        #expect(packs.map(\.infoHash) == ["p1"])
    }

    @Test func bestSeasonPackRanksByLanguageThenQuality() {
        let dub4k = packStream("a", season: 1, res: "2160p", langs: ["en"])
        let orig1080 = packStream("b", season: 1, res: "1080p", langs: ["fr"])
        let match = [dub4k, orig1080].bestSeasonPack(forSeason: 1, originalLanguage: "fr")
        #expect(match?.stream.infoHash == "b")          // original language wins over higher quality
        #expect(match?.isFallback == false)
    }

    @Test func bestSeasonPackNilWhenNoPackForSeason() {
        let ep = epStream("e", season: 1, episode: 1, res: "2160p")
        #expect([ep].bestSeasonPack(forSeason: 1, originalLanguage: "en") == nil)
    }
}
