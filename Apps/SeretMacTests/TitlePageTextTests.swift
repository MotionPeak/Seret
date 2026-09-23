import DebridCore
import DebridUI
import Testing
@testable import Seret

@Suite struct TitlePageTextTests {
    @Test func aFilmsMetaLineReadsYearRuntimeGenres() {
        let line = TitlePageText.metaLine(year: 2024, runtimeMinutes: 166,
                                          genres: ["Science Fiction", "Adventure"], seasonCount: nil)
        #expect(line == "2024 · 2h 46m · Science Fiction · Adventure")
    }

    @Test func underAnHourIsMinutesOnly() {
        let line = TitlePageText.metaLine(year: nil, runtimeMinutes: 48, genres: [], seasonCount: nil)
        #expect(line == "48m")
    }

    @Test func onlyThreeGenres() {
        let line = TitlePageText.metaLine(year: nil, runtimeMinutes: nil,
                                          genres: ["A", "B", "C", "D"], seasonCount: nil)
        #expect(line == "A · B · C")
    }

    @Test func oneSeasonIsSingular() {
        #expect(TitlePageText.metaLine(year: nil, runtimeMinutes: nil, genres: [], seasonCount: 1) == "1 Season")
        #expect(TitlePageText.metaLine(year: nil, runtimeMinutes: nil, genres: [], seasonCount: 3) == "3 Seasons")
    }

    @Test func missingPartsAreSkipped() {
        let line = TitlePageText.metaLine(year: 2024, runtimeMinutes: nil, genres: [], seasonCount: nil)
        #expect(line == "2024")
    }

    @Test func filmButtonTitles() {
        #expect(TitlePageText.primaryTitle(episode: nil, resumeAt: nil) == "Play")
        #expect(TitlePageText.primaryTitle(episode: nil, resumeAt: 3753) == "Resume · 1:02:33")
    }

    @Test func showButtonTitles() {
        #expect(TitlePageText.primaryTitle(episode: (season: 1, number: 3), resumeAt: nil) == "Play S1·E3")
        #expect(TitlePageText.primaryTitle(episode: (season: 1, number: 3), resumeAt: 100) == "Resume S1·E3")
    }

    @Test func heroHeightIsClamped() {
        #expect(TitlePageLayout.heroHeight(width: 500) == 380)
        #expect(abs(TitlePageLayout.heroHeight(width: 1440) - 532.8) < 0.001)
        #expect(TitlePageLayout.heroHeight(width: 4000) == 620)
    }

    @Test func episodeColumnsFollowTheWidth() {
        #expect(TitlePageLayout.episodeColumns(width: 899) == 2)
        #expect(TitlePageLayout.episodeColumns(width: 900) == 3)
        #expect(TitlePageLayout.episodeColumns(width: 559) == 1)
    }

    @Test func aTitleYouDoNotOwnSaysSo() {
        #expect(TitlePageText.unavailableTitle(isOwned: false) == "Not in Your Library")
    }

    @Test func anOwnedTitleWithNothingPlayableIsNotAvailable() {
        #expect(TitlePageText.unavailableTitle(isOwned: true) == "Not Available")
    }

    // MARK: - Credit line

    @Test func creditLineForAFilm() {
        #expect(TitlePageText.creditLine(kind: .movie, names: ["Denis Villeneuve"]) == "Dir. Denis Villeneuve")
    }

    @Test func creditLineForAShow() {
        #expect(TitlePageText.creditLine(kind: .show, names: ["Vince Gilligan"]) == "Created by Vince Gilligan")
    }

    @Test func multipleCreditsAreCommaJoined() {
        #expect(TitlePageText.creditLine(kind: .show, names: ["A", "B"]) == "Created by A, B")
    }

    @Test func noCreditsNoLine() {
        #expect(TitlePageText.creditLine(kind: .movie, names: []) == nil)
    }

    // MARK: - Franchise line

    @Test func franchiseLineReadsFilmNOfM() {
        // `count` is `parts.count` — a "2 of 2" franchise needs two parts, not just a position.
        func part(_ id: Int, _ title: String, _ date: String) -> TMDBSearchResult {
            TMDBSearchResult(id: id, title: title, name: nil, releaseDate: date, firstAirDate: nil,
                             posterPath: nil, overview: nil, voteAverage: nil)
        }
        let twoPart = Franchise(name: "Dune Collection",
                                parts: [part(1, "Dune", "2021-01-01"), part(2, "Dune: Part Two", "2024-01-01")],
                                position: 2)
        #expect(TitlePageText.franchiseLine(twoPart) == "Film 2 of 2 \u{00B7} Dune Collection")
    }

    // MARK: - Ratings formatting

    @Test func ratingsFormat() {
        #expect(TitlePageText.imdb(8.5) == "8.5")
        #expect(TitlePageText.rottenTomatoes(92) == "92%")
        #expect(TitlePageText.letterboxd(4.4) == "4.4")
        #expect(TitlePageText.letterboxd(4.0) == "4.0")
    }

    @Test func metacriticBandsAt61And40() {
        #expect(TitlePageText.metacriticBand(79) == .good)
        #expect(TitlePageText.metacriticBand(61) == .good)
        #expect(TitlePageText.metacriticBand(60) == .mixed)
        #expect(TitlePageText.metacriticBand(40) == .mixed)
        #expect(TitlePageText.metacriticBand(39) == .bad)
    }

    // MARK: - Acquire title

    @Test func acquireTitles() {
        #expect(TitlePageText.acquireTitle(episode: nil, finding: false) == "Play")
        #expect(TitlePageText.acquireTitle(episode: (season: 1, number: 1), finding: false) == "Play S1\u{00B7}E1")
        #expect(TitlePageText.acquireTitle(episode: nil, finding: true) == "Finding a version\u{2026}")
        #expect(TitlePageText.acquireTitle(episode: (season: 1, number: 1), finding: true) == "Finding a version\u{2026}")
    }

    // MARK: - History lines

    @Test func historyReadsPlaysAndLastDate() {
        let last = Date(timeIntervalSince1970: 1_722_600_000)
        let since = Date(timeIntervalSince1970: 1_705_000_000)
        let lines = TitlePageText.historyLines(summary: WatchSummary(plays: 2, lastWatchedAt: last), since: since)
        #expect(lines == [
            "Watched 2 times \u{00B7} last on \(last.formatted(date: .abbreviated, time: .omitted))",
            "In your history since \(since.formatted(date: .abbreviated, time: .omitted))",
        ])
    }

    @Test func oneTimeIsSingular() {
        let lines = TitlePageText.historyLines(summary: WatchSummary(plays: 1, lastWatchedAt: nil), since: nil)
        #expect(lines == ["Watched 1 time"])
    }

    @Test func noHistoryNoLines() {
        #expect(TitlePageText.historyLines(summary: nil, since: nil) == [])
        #expect(TitlePageText.historyLines(summary: WatchSummary(plays: 0, lastWatchedAt: nil), since: nil) == [])
    }
}
