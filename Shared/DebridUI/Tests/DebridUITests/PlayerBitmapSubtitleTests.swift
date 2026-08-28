import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// A Blu-ray rip's subtitles are `bdpg` — PGS — which is not text but a sequence of pre-rendered
/// images, and the automatic pick took the first track matching the language with no regard for
/// that. On a REMUX the bitmap tracks are listed first, so the app reliably chose one.
///
/// The cost is not cosmetic. A bitmap track ignores every font and size preference the app offers,
/// `SubtitleRetimer` cannot correct it, and each cue is an image to decode and composite — the
/// first thing to suffer when the pipeline is loaded, which is what "the line appears and is gone
/// 0.1s later, in bursts" looks like. Verified against the real account: every subtitle track in
/// the library REMUX the harness picked is `bdpg`.
@MainActor
@Suite struct PlayerBitmapSubtitleTests {

    private func track(_ id: String, _ codec: String, _ lang: String?) -> MediaTrack {
        MediaTrack(id: id, kind: .subtitle, name: id, language: lang, codec: codec)
    }

    private func model(_ engine: FakeVideoPlayerEngine,
                       prefs: FakeTrackPreferences,
                       subs: FakeSubtitleProvider = FakeSubtitleProvider()) -> PlayerModel {
        PlayerModel(request: Fixture.request(sources: [Fixture.movieSource()]), engine: engine,
                    unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                    recordProgress: { _, _, _, _ in }, subtitles: subs,
                    trackPreferences: prefs, subtitleFallbackDelay: 0.1)
    }

    @Test func aTextTrackIsChosenOverTheBitmapOneListedBeforeIt() async {
        let engine = FakeVideoPlayerEngine()
        engine.subtitleTracks = [track("spu/5", "bdpg", "en"),      // listed first, as on a REMUX
                                 track("spu/6", "subt", "en")]
        let m = model(engine, prefs: FakeTrackPreferences(subtitle: .language("en")))
        m.start()
        engine.emit(.tracksChanged)          // VLCKit announces the track set asynchronously
        await m.waitForIdleForTesting()

        #expect(m.selectedSubtitleID == "spu/6")
    }

    @Test func aBitmapTrackIsStillShownWhenItIsAllTheFileHas() async {
        let engine = FakeVideoPlayerEngine()
        engine.subtitleTracks = [track("spu/5", "bdpg", "en")]
        let m = model(engine, prefs: FakeTrackPreferences(subtitle: .language("en")))
        m.start()
        engine.emit(.tracksChanged)          // VLCKit announces the track set asynchronously
        await m.waitForIdleForTesting()

        // Something on screen beats nothing while the replacement is fetched.
        #expect(m.selectedSubtitleID == "spu/5")
    }

    @Test func aTextSubtitleIsFetchedWhenEveryTrackInTheLanguageIsABitmap() async {
        let engine = FakeVideoPlayerEngine()
        engine.subtitleTracks = [track("spu/5", "bdpg", "en")]
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "en", release: "X", fps: 23.976)]
        let m = model(engine, prefs: FakeTrackPreferences(subtitle: .language("en")), subs: subs)
        m.start()
        engine.emit(.tracksChanged)          // VLCKit announces the track set asynchronously
        await m.waitForIdleForTesting()
        try? await Task.sleep(for: .seconds(0.4))
        await m.waitForIdleForTesting()

        // A bitmap-only language is unserved: the fetched text track honours the font settings and
        // is the only kind the retimer can correct.
        #expect(subs.downloadedResults.count == 1)
    }

    @Test func anEmbeddedTextTrackStillCancelsTheFetch() async {
        let engine = FakeVideoPlayerEngine()
        engine.subtitleTracks = [track("spu/5", "bdpg", "en"), track("spu/6", "subt", "en")]
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "en")]
        let m = model(engine, prefs: FakeTrackPreferences(subtitle: .language("en")), subs: subs)
        m.start()
        engine.emit(.tracksChanged)          // VLCKit announces the track set asynchronously
        await m.waitForIdleForTesting()
        try? await Task.sleep(for: .seconds(0.4))
        await m.waitForIdleForTesting()

        // The file already serves this language as text — spending a capped download would be waste.
        #expect(subs.downloadedResults.isEmpty)
    }

    @Test func aBitmapTrackInAnotherLanguageDoesNotTriggerAFetch() async {
        let engine = FakeVideoPlayerEngine()
        engine.subtitleTracks = [track("spu/5", "subt", "en"), track("spu/6", "bdpg", "fr")]
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "en")]
        let m = model(engine, prefs: FakeTrackPreferences(subtitle: .language("en")), subs: subs)
        m.start()
        engine.emit(.tracksChanged)          // VLCKit announces the track set asynchronously
        await m.waitForIdleForTesting()
        try? await Task.sleep(for: .seconds(0.4))
        await m.waitForIdleForTesting()

        #expect(subs.downloadedResults.isEmpty)
        #expect(m.selectedSubtitleID == "spu/5")
    }
}
