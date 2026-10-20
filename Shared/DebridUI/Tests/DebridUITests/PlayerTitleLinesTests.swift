import Testing
import Foundation
import DebridCore
@testable import DebridUI

struct PlayerTitleLinesTests {
    private let source = MediaSource(torrentID: "t", fileID: nil, restrictedLink: "rd://x",
                                     parsed: ParsedRelease(title: "x"))

    @Test func filmLeadsWithLabelAndShowsYearAndRuntime() {
        let lines = PlayerTitleLines.make(label: "Dune: Part Two", itemTitle: "Dune: Part Two",
                                          kind: .movie, year: 2024, episode: nil, episodeName: nil,
                                          duration: 7_680)
        #expect(lines == PlayerTitleLines(title: "Dune: Part Two", subtitle: "2024 · 2 hr 8 min"))
    }

    @Test func episodeLeadsWithItsNameAndCarriesTheShow() {
        let ep = Episode(season: 1, number: 3, source: source)
        let lines = PlayerTitleLines.make(label: "Severance — S1·E3", itemTitle: "Severance",
                                          kind: .show, year: 2022, episode: ep,
                                          episodeName: "In Perpetuity", duration: 3_120)
        #expect(lines == PlayerTitleLines(title: "In Perpetuity",
                                          subtitle: "Severance · S1 \u{2022} E3 · 52 min"))
    }

    @Test func unnamedEpisodeFallsBackToItsNumberAndNeverShowsAYear() {
        let ep = Episode(season: 2, number: 7, source: source)
        let lines = PlayerTitleLines.make(label: "Severance — S2·E7", itemTitle: "Severance",
                                          kind: .show, year: 2022, episode: ep,
                                          episodeName: "  ", duration: 0)
        #expect(lines == PlayerTitleLines(title: "Episode 7", subtitle: "Severance · S2 \u{2022} E7"))
    }

    /// An Add-flow play of an episode carries no series context: the label is all there is, and a
    /// show's first-air year would be wrong under it.
    @Test func showWithoutEpisodeContextUsesTheLabelAndNoYear() {
        let lines = PlayerTitleLines.make(label: "Severance — S1·E3", itemTitle: "Severance",
                                          kind: .show, year: 2022, episode: nil, episodeName: nil,
                                          duration: 3_000)
        #expect(lines == PlayerTitleLines(title: "Severance — S1·E3", subtitle: "50 min"))
    }

    /// The model's own lookup: the name comes from the loaded season list, matched on season AND
    /// number — a same-numbered episode of another season must not lend its name.
    @MainActor
    @Test func modelTakesTheNameOfTheMatchingSeasonAndNumber() {
        let model = PlayerModel(request: Fixture.showRequest(episodes: 3, playingEpisode: 2),
                                engine: FakeVideoPlayerEngine(),
                                unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                                recordProgress: { _, _, _, _, _ in }, subtitles: nil)
        #expect(model.titleLines.title == "Episode 2")            // nothing loaded yet

        model.seasonEpisodes = [
            .init(season: 2, number: 2, name: "Another Season's Second", stillPath: nil, owned: nil),
            .init(season: 1, number: 1, name: "Pilot", stillPath: nil, owned: nil),
            .init(season: 1, number: 2, name: "  The Second\n", stillPath: nil, owned: nil),
            .init(season: 1, number: 3, name: "Third", stillPath: nil, owned: nil),
        ]
        #expect(model.titleLines == PlayerTitleLines(title: "The Second",
                                                     subtitle: "The Show · S1 \u{2022} E2"))

        // A name that is only whitespace and newlines falls back to the number.
        model.seasonEpisodes = [.init(season: 1, number: 2, name: " \n\t", stillPath: nil, owned: nil)]
        #expect(model.titleLines.title == "Episode 2")
    }

    @Test func runtimeFormats() {
        #expect(PlayerTitleLines.runtimeText(59) == nil)
        #expect(PlayerTitleLines.runtimeText(60) == "1 min")
        #expect(PlayerTitleLines.runtimeText(7_200) == "2 hr")
        #expect(PlayerTitleLines.runtimeText(5_820) == "1 hr 37 min")
    }
}
