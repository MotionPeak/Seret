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

    @Test func aHebrewSubtitleTagIsNotHebrewAudio() {
        // Read as audio, an English film "with Hebrew audio" ranked as a foreign dub — the one
        // release a Hebrew-reading household wants first sank to the bottom.
        #expect(detector.detect(in: "Oppenheimer.2023.1080p.BluRay.Heb.Sub-GRP").isEmpty)
    }

    @Test func aHebrewDubIsStillHebrewAudio() {
        #expect(detector.detect(in: "Moana.2016.1080p.Heb.Dub") == ["he"])
    }

    @Test func theAddonsFlagForASubtitledReleaseIsNotAudio() {
        #expect(detector.detect(in: "Oppenheimer.2023.1080p.HebSubs\n👤 12 💾 2.1 GB\n🇮🇱").isEmpty)
    }

    @Test func aFlagWithADubWordStaysAudio() {
        #expect(detector.detect(in: "Moana.2016.Hebrew.Dubbed\n🇮🇱") == ["he"])
    }

    @Test func englishSubtitlesOnAFrenchFilmAreNotEnglishAudio() {
        #expect(detector.detect(in: "Amelie.2001.1080p.BluRay.ENG.SUBS\n🇬🇧").isEmpty)
    }
}
