import Testing
import Foundation
@testable import DebridCore

private func credit(_ id: Int, _ title: String, popularity: Double,
                    character: String? = nil, job: String? = nil,
                    poster: String? = "/p.jpg", date: String = "2020-01-01",
                    kind: MediaKind = .movie) -> TMDBPersonCredit {
    TMDBPersonCredit(
        result: TMDBSearchResult(id: id, title: title, name: nil, releaseDate: date,
                                 firstAirDate: nil, posterPath: poster, overview: nil,
                                 voteAverage: nil),
        kind: kind, character: character, job: job, popularity: popularity)
}

/// Turning TMDB's raw combined credits into a filmography worth looking at. Pure — no network,
/// no SwiftData, so this suite stays a plain top-level struct.
@Suite struct PersonFilmographyTests {

    @Test func ranksByPopularityDescending() {
        let out = [credit(1, "Quiet", popularity: 3),
                   credit(2, "Famous", popularity: 90),
                   credit(3, "Middling", popularity: 40)].actingFilmography()
        #expect(out.map(\.result.displayTitle) == ["Famous", "Middling", "Quiet"])
    }

    @Test func dropsSelfAppearances() {
        let out = [credit(1, "Talk Show", popularity: 99, character: "Self"),
                   credit(2, "Chat", popularity: 98, character: "Self - Guest"),
                   credit(3, "Doc", popularity: 97, character: "Himself"),
                   credit(4, "Real Film", popularity: 1, character: "Paul")].actingFilmography()
        #expect(out.map(\.result.displayTitle) == ["Real Film"])
    }

    @Test func dropsCreditsWithNoPoster() {
        let out = [credit(1, "Ghost", popularity: 99, character: "X", poster: nil),
                   credit(2, "Real", popularity: 1, character: "Y")].actingFilmography()
        #expect(out.map(\.result.displayTitle) == ["Real"])
    }

    @Test func dedupesTheSameTitleCreditedTwice() {
        let out = [credit(7, "Twice", popularity: 50, character: "Young Paul"),
                   credit(7, "Twice", popularity: 50, character: "Old Paul")].actingFilmography()
        #expect(out.count == 1)
    }

    @Test func aMovieAndAShowSharingAnIDAreDifferentTitles() {
        let out = [credit(7, "Film", popularity: 50, character: "A", kind: .movie),
                   credit(7, "Series", popularity: 40, character: "B", kind: .show)]
            .actingFilmography()
        #expect(out.count == 2)
    }

    @Test func breaksPopularityTiesByDateThenTitleSoTheOrderIsTotal() {
        let out = [credit(1, "Beta", popularity: 5, character: "X", date: "2020-01-01"),
                   credit(2, "Alpha", popularity: 5, character: "X", date: "2020-01-01"),
                   credit(3, "Newer", popularity: 5, character: "X", date: "2024-01-01")]
            .actingFilmography()
        #expect(out.map(\.result.displayTitle) == ["Newer", "Alpha", "Beta"])
    }

    @Test func directingKeepsOnlyDirectorCredits() {
        let out = [credit(1, "Directed", popularity: 10, job: "Director"),
                   credit(2, "Produced", popularity: 99, job: "Producer"),
                   credit(3, "Wrote", popularity: 98, job: "Screenplay")].directingFilmography()
        #expect(out.map(\.result.displayTitle) == ["Directed"])
    }

    @Test func emptyInEmptyOut() {
        #expect([TMDBPersonCredit]().actingFilmography().isEmpty)
        #expect([TMDBPersonCredit]().directingFilmography().isEmpty)
    }
}
