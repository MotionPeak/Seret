import Testing
import Foundation
@testable import DebridCore

/// The title page's own artwork: TMDB's `images.logos` block, on the same details payload
/// `preferredBackdropPath` already reads. A logo *is* the title, so it must be the English
/// treatment (or untagged) — never another language's alphabet standing in for the title.
private extension TMDBMovieDetails {
    static func fixture(images: TMDBImageSet?) -> TMDBMovieDetails {
        TMDBMovieDetails(id: 1, title: "Fixture", releaseDate: nil, overview: nil,
                         posterPath: nil, backdropPath: nil, runtime: nil,
                         genres: [], voteAverage: nil, images: images)
    }
}

struct TMDBLogoChoiceTests {

    private func logo(_ path: String, lang: String?, vote: Double = 0, width: Int = 500)
    -> TMDBImageRef {
        TMDBImageRef(filePath: path, languageCode: lang, voteAverage: vote, width: width)
    }

    @Test func englishBeatsUntagged() {
        let set = TMDBImageSet(backdrops: [], logos: [
            logo("/untagged.png", lang: nil, vote: 9.0),
            logo("/english.png", lang: "en", vote: 1.0),
        ])
        #expect(set.bestLogoPath == "/english.png")
    }

    @Test func untaggedWhenThereIsNoEnglish() {
        let set = TMDBImageSet(backdrops: [], logos: [
            logo("/untagged.png", lang: nil, vote: 4.0),
        ])
        #expect(set.bestLogoPath == "/untagged.png")
    }

    @Test func anotherLanguageNeverWins() {
        let set = TMDBImageSet(backdrops: [], logos: [
            logo("/korean.png", lang: "ko", vote: 10.0),
        ])
        #expect(set.bestLogoPath == nil)
    }

    @Test func ratedThenWidest() {
        let byRating = TMDBImageSet(backdrops: [], logos: [
            logo("/low.png", lang: "en", vote: 2.0, width: 2000),
            logo("/high.png", lang: "en", vote: 7.0, width: 500),
        ])
        #expect(byRating.bestLogoPath == "/high.png")

        let byWidth = TMDBImageSet(backdrops: [], logos: [
            logo("/narrow.png", lang: "en", vote: 5.0, width: 500),
            logo("/wide.png", lang: "en", vote: 5.0, width: 2000),
        ])
        #expect(byWidth.bestLogoPath == "/wide.png")
    }

    @Test func svgIsSkipped() {
        let svgLoses = TMDBImageSet(backdrops: [], logos: [
            logo("/vector.svg", lang: "en", vote: 10.0),
            logo("/raster.png", lang: "en", vote: 1.0),
        ])
        #expect(svgLoses.bestLogoPath == "/raster.png")

        let onlySVG = TMDBImageSet(backdrops: [], logos: [
            logo("/vector.svg", lang: "en", vote: 10.0),
        ])
        #expect(onlySVG.bestLogoPath == nil)
    }

    @Test func noLogosIsNil() {
        #expect(TMDBImageSet(backdrops: []).bestLogoPath == nil)
    }

    @Test func decodesLogosFromADetailsPayload() throws {
        let json = """
        {"backdrops":[],"logos":[
          {"file_path":"/en.png","iso_639_1":"en","vote_average":8.0,"width":500},
          {"file_path":"/ko.png","iso_639_1":"ko","vote_average":9.0,"width":500}
        ]}
        """.data(using: .utf8)!
        let set = try JSONDecoder().decode(TMDBImageSet.self, from: json)
        #expect(set.logos.count == 2)
        #expect(set.bestLogoPath == "/en.png")

        let details = TMDBMovieDetails.fixture(images: set)
        #expect(details.logoPath == "/en.png")
    }

    @Test func aPayloadWithoutLogosStillDecodes() throws {
        let backdropsOnly = """
        {"backdrops":[{"file_path":"/b.jpg","iso_639_1":null,"vote_average":1,"width":1920}]}
        """.data(using: .utf8)!
        let set1 = try JSONDecoder().decode(TMDBImageSet.self, from: backdropsOnly)
        #expect(set1.logos.isEmpty)
        #expect(set1.bestLogoPath == nil)

        let noImagesAtAll = TMDBMovieDetails.fixture(images: nil)
        #expect(noImagesAtAll.logoPath == nil)
    }
}
