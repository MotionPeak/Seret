import Testing
@testable import DebridCore

@Suite struct LanguageCodeTests {
    @Test(arguments: ["he", "heb", "HEB", "iw", "he-IL", "Hebrew", "hebrew"])
    func everySpellingOfHebrewIsHe(_ tag: String) {
        #expect(LanguageCode.normalize(tag) == "he")
    }

    @Test func threeLetterCodesBecomeTwo() {
        #expect(LanguageCode.normalize("eng") == "en")
        #expect(LanguageCode.normalize("fre") == "fr")
        #expect(LanguageCode.normalize("ger") == "de")
        #expect(LanguageCode.normalize("pt-BR") == "pt")
    }

    @Test(arguments: ["und", "zxx", "mul", "", "  "])
    func undeterminedTagsSayNothing(_ tag: String) {
        #expect(LanguageCode.normalize(tag) == nil)
    }

    @Test func nilSaysNothing() {
        #expect(LanguageCode.normalize(nil) == nil)
    }

    @Test func anUnknownTagPassesThroughLowercased() {
        #expect(LanguageCode.normalize("QAA") == "qaa")
    }

    @Test func aTrackNameCanDeclareHebrew() {
        #expect(LanguageCode.fromName("Hebrew") == "he")
        #expect(LanguageCode.fromName("Hebrew (Forced)") == "he")
        #expect(LanguageCode.fromName("עברית") == "he")
        #expect(LanguageCode.fromName("Heb SDH") == "he")
    }

    @Test func aNameOnlyCountsAsWholeWords() {
        #expect(LanguageCode.fromName("Hebrewtown commentary") == nil)
        #expect(LanguageCode.fromName("Track 3") == nil)
        #expect(LanguageCode.fromName(nil) == nil)
    }
}
