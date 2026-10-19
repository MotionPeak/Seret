import Testing
import Foundation
@testable import DebridUI
import DebridCore

@Suite struct PreviewSubjectTests {
    private static func ep(_ s: Int, _ n: Int) -> Episode {
        Episode(season: s, number: n, source: MediaSource(torrentID: "t\(s)\(n)", fileID: nil,
                                                          restrictedLink: "rd://\(s)\(n)",
                                                          parsed: ParsedRelease(title: "S")))
    }
    private static let movie = MediaItem(id: "movie:tmdb:7", kind: .movie, title: "Heat", year: 1995,
                                         sources: [], seasons: [], tmdbID: 7,
                                         posterPath: "/p.jpg", backdropPath: "/b.jpg",
                                         overview: "A heist.")
    private static let show = MediaItem(id: "show:tmdb:1", kind: .show, title: "The Show", year: 2020,
                                        sources: [], seasons: [Season(number: 1, episodes: [ep(1, 3)])],
                                        tmdbID: 1, posterPath: "/sp.jpg", backdropPath: "/sb.jpg",
                                        overview: "  ")

    private static func home(_ item: MediaItem, fraction: Double, episode: Episode?,
                             subtitle: String = "S1 · E3", upNext: Bool = false) -> HomeItem {
        HomeItem(item: item, fraction: fraction, subtitle: subtitle, episode: episode, source: nil,
                 contentKey: "k", resumeAt: nil, isUpNext: upNext)
    }

    @Test func movieItemCopiesItsFieldsAndHasNoEpisodeLine() {
        let s = PreviewSubject(item: Self.movie)
        #expect(s.id == "movie:tmdb:7")
        #expect(s.kind == .movie)
        #expect(s.tmdbID == 7)
        #expect(s.title == "Heat")
        #expect(s.year == 1995)
        #expect(s.overview == "A heist.")
        #expect(s.backdropPath == "/b.jpg")
        #expect(s.posterPath == "/p.jpg")
        #expect(s.episodeLine == nil)
        #expect(s.fraction == nil)
        #expect(s.remainingMinutes == nil)
    }

    @Test func blankOverviewBecomesNil() {
        #expect(PreviewSubject(item: Self.show).overview == nil)
    }

    @Test func homeEpisodeGetsASeasonEpisodeLine() {
        let s = PreviewSubject(home: Self.home(Self.show, fraction: 0.5, episode: Self.ep(1, 3)))
        #expect(s.episodeLine == "Season 1 · Episode 3")
        #expect(s.fraction == 0.5)
        #expect(s.title == "The Show")
    }

    @Test func upNextEpisodeLineIsPrefixed() {
        let s = PreviewSubject(home: Self.home(Self.show, fraction: 0, episode: Self.ep(2, 1),
                                               subtitle: "S2 · E1", upNext: true))
        #expect(s.episodeLine == "Next · Season 2 · Episode 1")
    }

    @Test func twoEpisodesOfOneShowHaveDistinctIDs() {
        let a = PreviewSubject(home: Self.home(Self.show, fraction: 0.1, episode: Self.ep(1, 3)))
        let b = PreviewSubject(home: Self.home(Self.show, fraction: 0.1, episode: Self.ep(2, 1),
                                               subtitle: "S2 · E1"))
        #expect(a.id != b.id)
    }

    @Test func movieHomeItemHasNoEpisodeLine() {
        let s = PreviewSubject(home: Self.home(Self.movie, fraction: 0.4, episode: nil, subtitle: ""))
        #expect(s.episodeLine == nil)
    }

    @Test func remainingMinutesNeedsFractionAndRuntime() {
        let h = Self.home(Self.movie, fraction: 0.25, episode: nil, subtitle: "")
        #expect(PreviewSubject(home: h, runtimeMinutes: 120).remainingMinutes == 90)
        #expect(PreviewSubject(home: h).remainingMinutes == nil)
        #expect(PreviewSubject(item: Self.movie).remainingMinutes == nil)
    }

    @Test func anUnstartedEntryHasNoRemainingMinutes() {
        let unstarted = Self.home(Self.show, fraction: 0, episode: Self.ep(2, 1),
                                  subtitle: "S2 · E1", upNext: true)
        #expect(PreviewSubject(home: unstarted, runtimeMinutes: 52).remainingMinutes == nil)
        let negative = Self.home(Self.movie, fraction: -0.2, episode: nil, subtitle: "")
        #expect(PreviewSubject(home: negative, runtimeMinutes: 52).remainingMinutes == nil)
        let started = Self.home(Self.movie, fraction: 0.5, episode: nil, subtitle: "")
        #expect(PreviewSubject(home: started, runtimeMinutes: 52).remainingMinutes == 26)
    }

    @Test func searchHitParsesYearAndKeepsKindAndIDs() {
        let result = TMDBSearchResult(id: 99, title: "Dune", name: nil, releaseDate: "2024-05-01",
                                      firstAirDate: nil, posterPath: "/d.jpg", overview: "Sand.",
                                      voteAverage: 8)
        let hit = SearchHit(result: result, kind: .movie)
        let s = PreviewSubject(hit: hit)
        #expect(s.id == hit.id)
        #expect(s.id != Self.movie.id)
        #expect(s.kind == .movie)
        #expect(s.tmdbID == 99)
        #expect(s.title == "Dune")
        #expect(s.year == 2024)
        #expect(s.overview == "Sand.")
        #expect(s.posterPath == "/d.jpg")
        #expect(s.backdropPath == nil)
    }

    @Test func malformedOrEmptyDatesYieldNoYear() {
        func year(_ date: String?) -> Int? {
            let r = TMDBSearchResult(id: 1, title: "T", name: nil, releaseDate: date, firstAirDate: nil,
                                     posterPath: nil, overview: "", voteAverage: nil)
            return PreviewSubject(hit: SearchHit(result: r, kind: .movie)).year
        }
        #expect(year("20") == nil)
        #expect(year("") == nil)
        #expect(year(nil) == nil)
        #expect(year("abcd-01-01") == nil)
        #expect(year("+123-01-01") == nil)
        #expect(year("-123") == nil)
        #expect(year("1999") == 1999)
    }

    @Test func showHitUsesTheAirDateAndName() {
        let r = TMDBSearchResult(id: 5, title: nil, name: "Severance", releaseDate: nil,
                                 firstAirDate: "2022-02-18", posterPath: nil, overview: "",
                                 voteAverage: nil)
        let s = PreviewSubject(hit: SearchHit(result: r, kind: .show))
        #expect(s.title == "Severance")
        #expect(s.year == 2022)
        #expect(s.overview == nil)
        #expect(s.kind == .show)
    }
}
