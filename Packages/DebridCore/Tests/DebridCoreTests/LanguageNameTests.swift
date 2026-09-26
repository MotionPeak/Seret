import Testing
@testable import DebridCore

@Suite struct LanguageNameTests {
    @Test func namesCommonCodesInEnglish() {
        #expect(LanguageName.english("he") == "Hebrew")
        #expect(LanguageName.english("en") == "English")
        #expect(LanguageName.english("ko") == "Korean")
    }

    @Test func aFullNameWhereACodeBelongsIsNotShouted() {
        #expect(LanguageName.english("english") == "English")
    }

    @Test func tmdbNoLanguageIsLeftOff() {
        #expect(LanguageName.forTitle("xx") == nil)
        #expect(LanguageName.forTitle(nil) == nil)
        #expect(LanguageName.forTitle("") == nil)
    }

    @Test func tmdbsCantoneseCodeIsNamed() {
        #expect(LanguageName.forTitle("cn") == "Cantonese")
    }

    @Test func aTitleLanguageIsNamed() {
        #expect(LanguageName.forTitle("ja") == "Japanese")
    }
}
