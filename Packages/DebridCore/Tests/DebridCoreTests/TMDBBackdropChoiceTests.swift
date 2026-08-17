import Testing
import Foundation
@testable import DebridCore

/// A TMDB backdrop carries `iso_639_1` when the artwork has text burned into it — a language-
/// specific title treatment. TMDB's default `backdrop_path` is frequently one of those, which is
/// why the Home hero rendered "Backrooms" twice: once as huge ghosted art inside the image, and
/// again as the label the app draws on top.
///
/// A backdrop with no language is the textless plate, and that is what a hero wants.
private extension TMDBMovieDetails {
    static func fixture(backdropPath: String?, images: TMDBImageSet?) -> TMDBMovieDetails {
        TMDBMovieDetails(id: 1, title: "Fixture", releaseDate: nil, overview: nil,
                         posterPath: nil, backdropPath: backdropPath, runtime: nil,
                         genres: [], voteAverage: nil, images: images)
    }
}

struct TMDBBackdropChoiceTests {

    private func image(_ path: String, lang: String?, vote: Double = 0, width: Int = 1920)
    -> TMDBImageRef {
        TMDBImageRef(filePath: path, languageCode: lang, voteAverage: vote, width: width)
    }

    @Test func aTextlessBackdropIsPreferredOverATitledOne() {
        let set = TMDBImageSet(backdrops: [
            image("/titled.jpg", lang: "en", vote: 9.0),      // higher rated, but has text
            image("/clean.jpg", lang: nil, vote: 3.0),
        ])
        #expect(set.textlessBackdropPath == "/clean.jpg")
    }

    @Test func theBestRatedTextlessBackdropWins() {
        let set = TMDBImageSet(backdrops: [
            image("/ok.jpg", lang: nil, vote: 2.0),
            image("/best.jpg", lang: nil, vote: 7.5),
            image("/meh.jpg", lang: nil, vote: 5.0),
        ])
        #expect(set.textlessBackdropPath == "/best.jpg")
    }

    /// Equal votes are common (TMDB starts everything at 0), so width decides — a hero is shown
    /// full-bleed on a 4K panel and the widest plate is the one that holds up.
    @Test func equalVotesFallBackToTheWidestPlate() {
        let set = TMDBImageSet(backdrops: [
            image("/small.jpg", lang: nil, vote: 0, width: 1280),
            image("/huge.jpg", lang: nil, vote: 0, width: 3840),
            image("/mid.jpg", lang: nil, vote: 0, width: 1920),
        ])
        #expect(set.textlessBackdropPath == "/huge.jpg")
    }

    @Test func noTextlessBackdropReportsNothing() {
        let set = TMDBImageSet(backdrops: [
            image("/a.jpg", lang: "en"),
            image("/b.jpg", lang: "he"),
        ])
        #expect(set.textlessBackdropPath == nil)
    }

    @Test func anEmptySetReportsNothing() {
        #expect(TMDBImageSet(backdrops: []).textlessBackdropPath == nil)
    }

    /// The whole point: a title whose images we could not fetch, or which has only titled art,
    /// must still get its backdrop. Preferring textless may never mean showing nothing.
    @Test func detailsFallBackToTheDefaultBackdropWhenThereIsNoTextlessOne() {
        let withoutImages = TMDBMovieDetails.fixture(backdropPath: "/default.jpg", images: nil)
        #expect(withoutImages.preferredBackdropPath == "/default.jpg")

        let titledOnly = TMDBMovieDetails.fixture(
            backdropPath: "/default.jpg",
            images: TMDBImageSet(backdrops: [image("/titled.jpg", lang: "en", vote: 9)]))
        #expect(titledOnly.preferredBackdropPath == "/default.jpg")
    }

    @Test func detailsPreferTheTextlessBackdropWhenThereIsOne() {
        let details = TMDBMovieDetails.fixture(
            backdropPath: "/default.jpg",
            images: TMDBImageSet(backdrops: [
                image("/titled.jpg", lang: "en", vote: 9),
                image("/clean.jpg", lang: nil, vote: 1),
            ]))
        #expect(details.preferredBackdropPath == "/clean.jpg")
    }

    /// Decoding guard: TMDB nests the block under `images` and omits `iso_639_1` as JSON null.
    @Test func imagesDecodeFromTheShapeTMDBActuallyReturns() throws {
        let json = """
        {"backdrops":[
          {"file_path":"/clean.jpg","iso_639_1":null,"vote_average":5.4,"width":3840,"height":2160},
          {"file_path":"/titled.jpg","iso_639_1":"en","vote_average":8.1,"width":1920,"height":1080}
        ]}
        """.data(using: .utf8)!
        let set = try JSONDecoder().decode(TMDBImageSet.self, from: json)
        #expect(set.backdrops.count == 2)
        #expect(set.textlessBackdropPath == "/clean.jpg")
    }
}
