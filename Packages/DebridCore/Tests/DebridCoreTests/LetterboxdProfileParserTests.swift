import Testing
import Foundation
@testable import DebridCore

@Suite struct LetterboxdProfileParserTests {
    func fixture(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func readsSlugNameYearAndRating() throws {
        let page = try LetterboxdProfileParser.parse(fixture("letterboxd-films-page"))
        #expect(page.entries.count == 4)
        #expect(page.entries[0] == LetterboxdEntry(slug: "speed", name: "Speed (1994)", year: 1994, rating: 6))
    }

    /// A constructed edge case, not a real Letterboxd title: the release year is the LAST
    /// parenthesised group, and a four-digit number earlier in the name must not win.
    @Test func aYearInsideTheTitleDoesNotBeatTheTrailingReleaseYear() throws {
        let page = try LetterboxdProfileParser.parse(fixture("letterboxd-films-page"))
        let constructed = page.entries[3]
        #expect(constructed.name == "The Class of (1984) (1982)")
        #expect(constructed.year == 1982)
        #expect(constructed.rating == 7)
    }

    @Test func anUnratedFilmParsesWithANilRatingRatherThanBeingDropped() throws {
        let page = try LetterboxdProfileParser.parse(fixture("letterboxd-films-page"))
        let lion = page.entries[1]
        #expect(lion.slug == "the-lion-king-2019")
        #expect(lion.year == 2019)
        #expect(lion.rating == nil)
    }

    @Test func aTitleContainingPunctuationTakesTheTrailingYear() throws {
        let page = try LetterboxdProfileParser.parse(fixture("letterboxd-films-page"))
        let amIOK = page.entries[2]
        #expect(amIOK.slug == "am-i-ok")
        #expect(amIOK.name == "Am I OK? (2022)")
        #expect(amIOK.year == 2022)
        #expect(amIOK.rating == 10)
    }

    @Test func findsTheNextPagePath() throws {
        let page = try LetterboxdProfileParser.parse(fixture("letterboxd-films-page"))
        #expect(page.nextPath == "/thebigshin/films/by/date/page/2/")
    }

    @Test func aLastPageHasNoNextPath() throws {
        let page = try LetterboxdProfileParser.parse(fixture("letterboxd-films-lastpage"))
        #expect(page.entries.count == 3)
        #expect(page.nextPath == nil)
    }

    @Test func aPageWithNoGridItemsIsAStructureChangeNotAnEmptyAccount() {
        #expect(throws: LetterboxdError.structureChanged) {
            try LetterboxdProfileParser.parse("<html><body><p>nothing here</p></body></html>")
        }
    }
}
