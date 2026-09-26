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

    /// A track tagged in ISO 639-2 must compare equal to TMDB's ISO 639-1, or the dub guard reads
    /// the film's own language as foreign and the version silently loses its Hebrew boost.
    @Test(arguments: [
        ("per", "fa"), ("fas", "fa"), ("tam", "ta"), ("tel", "te"), ("ind", "id"), ("in", "id"),
        ("may", "ms"), ("msa", "ms"), ("cat", "ca"), ("bul", "bg"), ("srp", "sr"), ("hrv", "hr"),
        ("slo", "sk"), ("slk", "sk"), ("slv", "sl"), ("est", "et"), ("lav", "lv"), ("lit", "lt"),
        ("ice", "is"), ("isl", "is"), ("tgl", "tl"), ("fil", "tl"), ("ben", "bn"), ("urd", "ur"),
        ("nb", "no"), ("mal", "ml"), ("mar", "mr"), ("kan", "kn"), ("pan", "pa"), ("afr", "af"),
    ])
    func moreIsoCodesNormalise(_ tag: String, _ expected: String) {
        #expect(LanguageCode.normalize(tag) == expected)
    }

    /// TMDB calls Cantonese `cn`, which is no ISO code at all; files tag it `chi`, `zho` or `yue`.
    @Test func cantoneseIsTheSameLanguageHoweverItIsTagged() {
        #expect(LanguageCode.sameLanguage("cn", LanguageCode.normalize("chi")!))
        #expect(LanguageCode.sameLanguage("cn", LanguageCode.normalize("yue")!))
        #expect(!LanguageCode.sameLanguage("cn", "ja"))
        #expect(LanguageCode.sameLanguage("en", "en"))
    }

    @Test func aCantoneseFilmsOwnAudioIsNotADub() {
        let evidence = SubtitleEvidence(hebrew: .builtIn, audioLanguages: ["zh"])
        #expect(hebrewBoostTier(evidence, parsed: ParsedRelease(title: "T"), originalLanguage: "cn")
                == HebrewSubtitles.builtIn.rawValue)
    }
}
