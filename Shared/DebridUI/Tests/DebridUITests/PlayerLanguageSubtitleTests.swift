import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// The subtitles a film opens with follow the language it is spoken in (owner, 2026-10-23): a
/// foreign film opens with Hebrew, one in English or Hebrew opens with nothing forced on, and the
/// viewer's own pick for a title always wins.
@MainActor
@Suite struct PlayerLanguageSubtitleTests {
    private func request(language: String?) -> PlaybackRequest {
        let base = Fixture.request()
        return PlaybackRequest(item: base.item, source: base.source, resumeAt: nil, label: base.label,
                               contentKey: base.contentKey, originalLanguage: language)
    }

    private func model(_ request: PlaybackRequest, _ engine: FakeVideoPlayerEngine,
                       prefs: FakeTrackPreferences, subtitles: SubtitleProvider? = nil,
                       lookup: (@Sendable (String) async -> String?)? = nil) -> PlayerModel {
        PlayerModel(request: request, engine: engine, unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                    recordProgress: { _, _, _, _, _ in }, subtitles: subtitles,
                    trackPreferences: prefs, lookupTitleLanguage: lookup, subtitleFallbackDelay: 0.02)
    }

    private let audio = [MediaTrack(id: "audio/0", kind: .audio, name: "Korean", language: "ko")]
    private let embedded = [MediaTrack(id: "spu/0", kind: .subtitle, name: "English", language: "en"),
                            MediaTrack(id: "spu/1", kind: .subtitle, name: "Hebrew", language: "he")]

    private func discover(_ engine: FakeVideoPlayerEngine, _ model: PlayerModel,
                          subtitles: [MediaTrack]) async {
        engine.audioTracks = audio
        engine.subtitleTracks = subtitles
        engine.emit(.tracksChanged)
        await model.waitForIdleForTesting()
    }

    @Test func aForeignFilmOpensWithItsBuiltInHebrew() async {
        let engine = FakeVideoPlayerEngine()
        let m = model(request(language: "ko"), engine, prefs: FakeTrackPreferences())
        m.start(); await m.waitForIdleForTesting()
        await discover(engine, m, subtitles: embedded)
        #expect(engine.selectedSubtitleID == .some("spu/1"))
    }

    @Test func aForeignFilmFetchesHebrewWhenTheFileHasNone() async {
        let engine = FakeVideoPlayerEngine()
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "he")]
        let m = model(request(language: "ja"), engine, prefs: FakeTrackPreferences(), subtitles: subs)
        m.start(); await m.waitForIdleForTesting()
        await discover(engine, m, subtitles: [])
        await m.waitForSubtitleFallbackForTesting()
        #expect(subs.searchedLanguages.contains(["he"]))
    }

    /// Picking Hebrew once used to make it the default for every title — English films included.
    @Test func anEnglishFilmIgnoresAStickyHebrewDefault() async {
        let engine = FakeVideoPlayerEngine()
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "he")]
        let m = model(request(language: "en"), engine, prefs: FakeTrackPreferences(subtitle: .language("he")),
                      subtitles: subs)
        m.start(); await m.waitForIdleForTesting()
        await discover(engine, m, subtitles: embedded)
        await m.waitForSubtitleFallbackForTesting()
        #expect(engine.selectedSubtitleID != .some("spu/1"))
        #expect(m.selectedSubtitleID == nil)
        #expect(subs.searchedLanguages.isEmpty)
    }

    @Test func aHebrewFilmOpensWithoutSubtitles() async {
        let engine = FakeVideoPlayerEngine()
        let m = model(request(language: "he"), engine, prefs: FakeTrackPreferences(subtitle: .language("he")))
        m.start(); await m.waitForIdleForTesting()
        await discover(engine, m, subtitles: embedded)
        #expect(m.selectedSubtitleID == nil)
    }

    @Test func theViewersOwnPickForTheTitleWins() async {
        let engine = FakeVideoPlayerEngine()
        let prefs = FakeTrackPreferences()
        let base = request(language: "ko")
        prefs.record(subtitle: .off, forTitle: base.item.id)
        let m = model(base, engine, prefs: prefs)
        m.start(); await m.waitForIdleForTesting()
        await discover(engine, m, subtitles: embedded)
        #expect(engine.selectedSubtitleID == .some(nil))
    }

    /// Home's Resume and Up Next do not know the language; the player looks it up.
    @Test func theLanguageIsLookedUpWhenTheRequestHasNone() async {
        let engine = FakeVideoPlayerEngine()
        let m = model(request(language: nil), engine, prefs: FakeTrackPreferences(),
                      lookup: { _ in "fr" })
        m.start(); await m.waitForIdleForTesting()
        await m.waitForTitleLanguageForTesting()
        await discover(engine, m, subtitles: embedded)
        #expect(engine.selectedSubtitleID == .some("spu/1"))
    }

    /// The lookup lands long before the stream does. It must not start the download timer then:
    /// with no tracks known, the timer would read the file's own Hebrew as missing and spend the
    /// OpenSubtitles quota on a copy that then outranks it.
    @Test func aLookedUpLanguageWaitsForTheFilesTracks() async {
        let engine = FakeVideoPlayerEngine()
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "he")]
        let m = model(request(language: nil), engine, prefs: FakeTrackPreferences(), subtitles: subs,
                      lookup: { _ in "ko" })
        m.start(); await m.waitForIdleForTesting()
        await m.waitForTitleLanguageForTesting()
        await m.waitForSubtitleFallbackForTesting()
        #expect(subs.searchedLanguages.isEmpty)
        await discover(engine, m, subtitles: embedded)
        await m.waitForSubtitleFallbackForTesting()
        #expect(engine.selectedSubtitleID == .some("spu/1"))
        #expect(subs.searchedLanguages.isEmpty)
    }

    /// Tracks can arrive before the lookup answers. The library-wide Hebrew must not be switched
    /// on in that gap for a film the lookup then says is English.
    @Test func noSubtitleIsChosenWhileTheLanguageIsStillBeingLookedUp() async {
        let engine = FakeVideoPlayerEngine()
        let (gate, open) = AsyncStream<Void>.makeStream()
        let m = model(request(language: nil), engine, prefs: FakeTrackPreferences(subtitle: .language("he")),
                      lookup: { _ in
                          for await _ in gate { break }
                          return "en"
                      })
        m.start(); await m.waitForIdleForTesting()
        await discover(engine, m, subtitles: embedded)
        #expect(m.selectedSubtitleID == nil)
        open.yield(); open.finish()
        await m.waitForTitleLanguageForTesting()
        #expect(m.selectedSubtitleID == nil)
        #expect(engine.selectedSubtitleID != .some("spu/1"))
    }

    /// …and a foreign answer arriving after the tracks still turns Hebrew on.
    @Test func aLateForeignAnswerStillTurnsHebrewOn() async {
        let engine = FakeVideoPlayerEngine()
        let (gate, open) = AsyncStream<Void>.makeStream()
        let m = model(request(language: nil), engine, prefs: FakeTrackPreferences(),
                      lookup: { _ in
                          for await _ in gate { break }
                          return "ja"
                      })
        m.start(); await m.waitForIdleForTesting()
        await discover(engine, m, subtitles: embedded)
        open.yield(); open.finish()
        await m.waitForTitleLanguageForTesting()
        #expect(engine.selectedSubtitleID == .some("spu/1"))
    }

    /// A file with no subtitles at all reports audio only; a late foreign answer must still arm
    /// the Hebrew download.
    @Test func aLateForeignAnswerFetchesHebrewForAFileWithNone() async {
        let engine = FakeVideoPlayerEngine()
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "he")]
        let (gate, open) = AsyncStream<Void>.makeStream()
        let m = model(request(language: nil), engine, prefs: FakeTrackPreferences(), subtitles: subs,
                      lookup: { _ in
                          for await _ in gate { break }
                          return "ja"
                      })
        m.start(); await m.waitForIdleForTesting()
        await discover(engine, m, subtitles: [])
        open.yield(); open.finish()
        await m.waitForTitleLanguageForTesting()
        await m.waitForSubtitleFallbackForTesting()
        #expect(subs.searchedLanguages.contains(["he"]))
    }

    @Test func withNoLanguageTheLibraryDefaultStillApplies() async {
        let engine = FakeVideoPlayerEngine()
        let m = model(request(language: nil), engine, prefs: FakeTrackPreferences(subtitle: .language("he")))
        m.start(); await m.waitForIdleForTesting()
        await discover(engine, m, subtitles: embedded)
        #expect(engine.selectedSubtitleID == .some("spu/1"))
    }
}
