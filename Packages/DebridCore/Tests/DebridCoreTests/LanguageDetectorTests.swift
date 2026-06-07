import Testing
@testable import DebridCore

@Suite struct LanguageDetectorTests {
    let detector = LanguageDetector()

    @Test func detectsFlagEmoji() {
        #expect(detector.detect(in: "🇺🇸/🇫🇷") == ["en", "fr"])
    }

    @Test func mapsGBToEnglishAndJPToJapanese() {
        #expect(detector.detect(in: "audio 🇬🇧 🇯🇵") == ["en", "ja"])
    }

    @Test func detectsLanguageWords() {
        #expect(detector.detect(in: "Multi: English, French, Hindi") == ["en", "fr", "hi"])
    }

    @Test func dedupesAndPreservesFirstSeenOrder() {
        #expect(detector.detect(in: "🇫🇷 French 🇫🇷") == ["fr"])
    }

    @Test func ignoresUnknownTokens() {
        #expect(detector.detect(in: "no languages here 1080p x265").isEmpty)
    }

    @Test func detectsSceneAbbreviations() {
        // Dual-audio dub names use abbreviations, not full words.
        #expect(detector.detect(in: "Split.2016.Ger.Eng.Dubbed.DTS.2160p.Remux") == ["de", "en"])
        #expect(detector.detect(in: "Split.(2016).UHD.2160p.ITA.DTS.ENG.AC3") == ["it", "en"])
    }

    @Test func cleanEnglishRemuxHasNoLanguageTag() {
        // The clean LEGi0N English REMUX carries no language token → empty (treated as original).
        #expect(detector.detect(in: "Split.2016.REMUX.UHD.BluRay.2160p.HEVC.DTS-HD.MA.5.1-LEGi0N").isEmpty)
    }
}
