import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// State that identifies WHICH FILE the subtitle machinery is talking about has to be discarded
/// when the file changes. All three of these survived a swap and described the previous file.
@MainActor
@Suite struct PlayerSubtitleIdentityTests {

    private func model(_ subs: FakeSubtitleProvider,
                       _ engine: FakeVideoPlayerEngine) -> PlayerModel {
        PlayerModel(request: Fixture.showRequest(episodes: 3, playingEpisode: 1), engine: engine,
                    unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                    recordProgress: { _, _, _, _ in }, subtitles: subs)
    }

    /// The moviehash is two range requests against the playing file, so it is resolved once and
    /// cached. Nothing cleared it when the file changed, so every search after an episode swap or
    /// a "Try another version" sent the PREVIOUS file's hash. A hash match scores +1000 in the
    /// ranker, so the one-tap pill confidently picked a subtitle timed to a different file and it
    /// played out of sync.
    @Test func theMoviehashIsDiscardedWhenTheEpisodeChanges() async {
        let engine = FakeVideoPlayerEngine()
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "he")]
        let m = model(subs, engine)
        m.start()
        await m.waitForIdleForTesting()

        m.currentMoviehash = "deadbeefdeadbeef"
        m.moviehashResolved = true

        m.play(m.item.seasons[0].episodes[1])          // swap to episode 2
        await m.waitForIdleForTesting()

        #expect(m.currentMoviehash == nil)
        #expect(m.moviehashResolved == false)
    }

    /// "Try another version" reloads a DIFFERENT FILE of the same episode, which needs its own
    /// hash just as much.
    @Test func theMoviehashIsDiscardedWhenTheVersionChanges() async {
        let engine = FakeVideoPlayerEngine()
        let subs = FakeSubtitleProvider()
        let m = model(subs, engine)
        m.start()
        await m.waitForIdleForTesting()

        m.currentMoviehash = "deadbeefdeadbeef"
        m.moviehashResolved = true

        m.reload()
        await m.waitForIdleForTesting()

        #expect(m.currentMoviehash == nil)
        #expect(m.moviehashResolved == false)
    }

    /// The browser's result list is the previous file's search. Leaving it up meant opening the
    /// browser after a swap showed results for the episode you just left — and picking one
    /// downloaded a subtitle for the wrong episode.
    @Test func browserResultsAreDiscardedWhenTheFileChanges() async {
        let engine = FakeVideoPlayerEngine()
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 7, language: "he")]
        let m = model(subs, engine)
        m.start()
        await m.waitForIdleForTesting()

        await m.searchSubtitles(language: "he")
        #expect(!m.subtitleSearchResults.isEmpty)
        #expect(m.subtitleSearchState == .loaded)

        m.play(m.item.seasons[0].episodes[1])
        await m.waitForIdleForTesting()

        #expect(m.subtitleSearchResults.isEmpty)
        #expect(m.subtitleSearchState == .idle)
        #expect(m.subtitleSearchLanguage == nil)
    }

    /// A language row records the engine track its downloaded subtitle landed on. libvlc's ids are
    /// POSITIONAL, so that id means nothing once a different media is loaded — but `reload()` left
    /// the row saying `.attached`, so after "Try another version" the panel showed Hebrew subtitles
    /// as on while the new media had no such track at all.
    @Test func attachedLanguageRowsAreResetOnReload() async {
        let engine = FakeVideoPlayerEngine()
        let subs = FakeSubtitleProvider()
        let m = model(subs, engine)
        m.start()
        await m.waitForIdleForTesting()

        m.setRow("he", .attached("spu/3"))
        #expect(m.subtitleRows.first(where: { $0.language == "he" })?.state == .attached("spu/3"))

        m.reload()
        await m.waitForIdleForTesting()

        let he = m.subtitleRows.first(where: { $0.language == "he" })
        #expect(he?.state == .idle)
        #expect(m.selectedSubtitleID == nil)
    }
}
