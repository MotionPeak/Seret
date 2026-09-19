import Testing
import Foundation
@testable import DebridCore

/// Fixtures are real captured film pages, trimmed to the `ld+json` block under test: one rated
/// title and one that genuinely has no ratings yet (an unreleased film, which Letterboxd serves
/// as a 200 with the `aggregateRating` key simply absent).
@Suite struct LetterboxdRatingParserTests {
    func fixture(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func readsTheWeightedAverageAndCountFromARealFilmPage() throws {
        let rating = LetterboxdRatingParser.rating(fromFilmPage: try fixture("letterboxd-film-rated"))
        #expect(rating?.score == 4.38)
        #expect(rating?.count == 3_654_485)
    }

    /// An unreleased film answers 200 with no `aggregateRating`. That is an answer — "no score" —
    /// not a failure, and the caller caches it as such rather than re-fetching the page forever.
    @Test func aFilmWithNoRatingsYetParsesAsNil() throws {
        #expect(LetterboxdRatingParser.rating(fromFilmPage: try fixture("letterboxd-film-unrated")) == nil)
    }

    @Test func aPageWithNoJSONLDAtAllIsNil() {
        #expect(LetterboxdRatingParser.rating(fromFilmPage: "<html><body>nothing here</body></html>") == nil)
    }

    /// The block is wrapped in a CDATA comment, so decoding the script's raw contents fails. If
    /// Letterboxd ever drops the wrapper the parser must still cope.
    @Test func parsesTheSameJSONWithoutTheCDATAWrapper() {
        let page = """
        <script type="application/ld+json">
        {"@type":"Movie","aggregateRating":{"bestRating":5,"@type":"AggregateRating",\
        "ratingValue":3.5,"ratingCount":12,"worstRating":0.5}}
        </script>
        """
        #expect(LetterboxdRatingParser.rating(fromFilmPage: page) == LetterboxdFilmRating(score: 3.5, count: 12))
    }

    /// A score outside Letterboxd's own 0.5–5 scale means the page shape changed under us. Showing
    /// it would render a nonsense figure in a chip labelled out of five; nothing is the safer read.
    @Test func aScoreOutsideTheFiveStarScaleIsRejected() {
        let page = """
        <script type="application/ld+json">
        {"aggregateRating":{"ratingValue":8.7,"ratingCount":12}}
        </script>
        """
        #expect(LetterboxdRatingParser.rating(fromFilmPage: page) == nil)
    }
}
