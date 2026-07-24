import Testing
import Foundation
@testable import DebridUI
import DebridCore

@MainActor
@Suite struct PlayerSubtitleQueryTests {

    @Test func anEpisodeSearchesWithItsSeasonAndEpisodeNumbers() async {
        let engine = FakeVideoPlayerEngine()
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "he")]
        let model = PlayerModel(request: Fixture.showRequest(playingEpisode: 2), engine: engine,
                                unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                                recordProgress: { _, _, _, _ in }, subtitles: subs)
        model.start()
        await model.waitForIdleForTesting()

        await model.requestSubtitle(language: "he")

        let query = subs.searchedQueries.last
        #expect(query?.season == 1)
        #expect(query?.episode == 2)
        #expect(query?.title == "The Show")
    }

    @Test func aMovieSearchesWithNoEpisodeNumbers() async {
        let engine = FakeVideoPlayerEngine()
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "he")]
        let model = PlayerModel(request: Fixture.request(), engine: engine,
                                unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                                recordProgress: { _, _, _, _ in }, subtitles: subs)
        model.start()
        await model.waitForIdleForTesting()

        await model.requestSubtitle(language: "he")

        let query = subs.searchedQueries.last
        #expect(query?.season == nil)
        #expect(query?.episode == nil)
    }
}
