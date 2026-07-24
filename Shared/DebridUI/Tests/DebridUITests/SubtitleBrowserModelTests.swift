import Testing
import Foundation
@testable import DebridUI
import DebridCore

@MainActor
@Suite struct SubtitleBrowserModelTests {

    private func playing(_ engine: FakeVideoPlayerEngine,
                         subs: SubtitleProvider? = nil) async -> PlayerModel {
        let model = PlayerModel(request: Fixture.request(), engine: engine,
                                unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                                recordProgress: { _, _, _, _ in }, subtitles: subs)
        model.start()
        await model.waitForIdleForTesting()
        return model
    }

    @Test func embeddedAndDownloadedTracksAreSeparated() async {
        let engine = FakeVideoPlayerEngine()
        engine.subtitleTracks = [
            MediaTrack(id: "spu/0", kind: .subtitle, name: "English SDH", language: "en"),
            MediaTrack(id: "spu/1", kind: .subtitle, name: "Español", language: "es"),
        ]
        let model = await playing(engine)
        engine.emit(.tracksChanged)
        await model.waitForIdleForTesting()

        #expect(model.embeddedTracks.map(\.id) == ["spu/0", "spu/1"])
        #expect(model.downloadedTracks.isEmpty)

        engine.addExternalSubtitle(url: URL(fileURLWithPath: "/tmp/he.srt"))
        engine.emit(.tracksChanged)
        await model.waitForIdleForTesting()

        #expect(model.embeddedTracks.map(\.id) == ["spu/0", "spu/1"])
        #expect(model.downloadedTracks.map(\.id) == ["ext/1"])
    }

    @Test func searchRanksResultsAgainstThePlayingFile() async {
        let engine = FakeVideoPlayerEngine()
        let subs = FakeSubtitleProvider()
        subs.searchResults = [
            SubtitleResult(fileID: 1, language: "he", release: "Dune.720p.BluRay-YTS",
                           downloadCount: 90_000),
            SubtitleResult(fileID: 2, language: "he", release: "Dune.2160p.WEB-DL-FLUX",
                           downloadCount: 100, moviehashMatch: true),
        ]
        let model = await playing(engine, subs: subs)

        await model.searchSubtitles(language: "he")

        #expect(model.subtitleSearchResults.first?.result.fileID == 2)
        #expect(model.subtitleSearchResults.first?.quality == .perfect)
        #expect(model.subtitleSearchState == .loaded)
    }

    @Test func aFailedSearchSurfacesAnErrorRatherThanAnEmptyList() async {
        let engine = FakeVideoPlayerEngine()
        let subs = FakeSubtitleProvider()
        subs.searchError = SubtitleError.notAuthenticated
        let model = await playing(engine, subs: subs)

        await model.searchSubtitles(language: "he")

        #expect(model.subtitleSearchState == .failed)
        #expect(model.subtitleSearchResults.isEmpty)
    }

    @Test func usingAResultDownloadsAndAttachesIt() async {
        let engine = FakeVideoPlayerEngine()
        let subs = FakeSubtitleProvider()
        subs.downloadedURL = URL(fileURLWithPath: "/tmp/dune.he.srt")
        let model = await playing(engine, subs: subs)
        let ranked = SubtitleMatch.rank([SubtitleResult(fileID: 7, language: "he")],
                                        against: "Dune", videoFPS: nil)[0]

        await model.useSubtitle(ranked)

        #expect(engine.addedSubtitles == [URL(fileURLWithPath: "/tmp/dune.he.srt")])
    }
}
