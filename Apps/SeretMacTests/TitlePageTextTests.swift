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
}
