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
}
