import Testing
import Foundation
@testable import DebridCore

@Suite struct LetterboxdTasteParsersTests {
    func fixture(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func similarPageListsTheFilmsInLetterboxdOrder() throws {
        let films = LetterboxdFilmListParser.parse(try fixture("letterboxd-similar.html"))
        #expect(films.first?.slug == "the-lives-of-others")          // the page lists the film itself first
        #expect(Array(films.dropFirst().prefix(3)).map(\.slug) ==
                ["the-spy-who-came-in-from-the-cold", "a-most-wanted-man", "bridge-of-spies"])
        #expect(films.count >= 60)
        #expect(films.first?.year == 2006)
    }

    @Test func similarPageIsDeduplicatedBySlugAndUnrated() throws {
        let films = LetterboxdFilmListParser.parse(try fixture("letterboxd-similar.html"))
        #expect(Set(films.map(\.slug)).count == films.count)
        #expect(films.allSatisfy { $0.rating == nil })
        #expect(films.first?.name == "The Lives of Others (2006)")
    }

    @Test func directorPageListsTheDirectorsFilms() throws {
        let films = LetterboxdFilmListParser.parse(try fixture("letterboxd-director.html"))
        #expect(Set(films.map(\.slug)).isSuperset(of: ["the-lives-of-others", "the-tourist", "never-look-away"]))
        #expect(films.first(where: { $0.slug == "the-tourist" })?.year == 2010)
    }

    @Test func aPageWithoutFilmsIsEmptyNotAnError() {
        #expect(LetterboxdFilmListParser.parse("<html></html>").isEmpty)
    }

    @Test func namesAreEntityDecodedAndAttributeOrderDoesNotMatter() {
        let html = #"<div data-item-slug="honey-dont" data-item-name="Honey Don&#039;t! (2025)"></div>"#
        let films = LetterboxdFilmListParser.parse(html)
        #expect(films.map(\.name) == ["Honey Don't! (2025)"])
        #expect(films.first?.year == 2025)
    }

    @Test func filmPageNamesItsDirectorAndGenres() throws {
        let html = try fixture("letterboxd-film-page.html")
        #expect(LetterboxdFilmPageParser.directorSlugs(fromFilmPage: html) == ["florian-henckel-von-donnersmarck"])
        #expect(LetterboxdFilmPageParser.genres(fromFilmPage: html) == ["Drama", "Thriller"])
    }

    @Test func aPageWithoutDirectorsOrGenresIsEmpty() {
        #expect(LetterboxdFilmPageParser.directorSlugs(fromFilmPage: "<html></html>").isEmpty)
        #expect(LetterboxdFilmPageParser.genres(fromFilmPage: "<html></html>").isEmpty)
    }
}
