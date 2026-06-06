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

    @Test func bestMatchNilWhenEmpty() {
        #expect([CachedStream]().bestMatch(originalLanguage: "en") == nil)
    }
}
