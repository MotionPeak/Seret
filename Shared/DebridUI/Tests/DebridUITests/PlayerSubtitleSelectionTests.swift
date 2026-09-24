import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// "I choose a subtitle — especially Hebrew — and nothing happens."
///
/// Reproduced in the tvOS simulator against the real account, on a REMUX that carries a Hebrew PGS
/// track. The probe caught the whole thing in two consecutive lines:
///
///     [subs] 1.92s SELECT <slave> (attach of downloaded he) <- FLUSHES SPU
///     [subs] 1.92s SELECT spu/20  (auto preference, was <slave>) <- FLUSHES SPU
///
/// The subtitle arrives, is selected, and is taken away again in the same turn — because VLCKit
/// does not tag a slave track with a language, so matching the preferred language against the
/// track list cannot see the file that was just fetched FOR that language, finds the media's own
/// track instead, and "corrects" the selection to it.
@MainActor
@Suite struct PlayerSubtitleSelectionTests {

    private func track(_ id: String, _ codec: String, _ lang: String?) -> MediaTrack {
        MediaTrack(id: id, kind: .subtitle, name: id, language: lang, codec: codec)
    }

    private func model(_ engine: FakeVideoPlayerEngine,
                       prefs: FakeTrackPreferences,
                       subs: FakeSubtitleProvider) -> PlayerModel {
        PlayerModel(request: Fixture.request(sources: [Fixture.movieSource()]), engine: engine,
                    unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                    recordProgress: { _, _, _, _, _ in }, subtitles: subs,
                    trackPreferences: prefs, subtitleFallbackDelay: 0.05)
    }

    /// The file's own Hebrew is a bitmap, so a text subtitle is fetched — and then the preference
    /// put the bitmap back. This is the reproduced defect, in the shape it was reproduced in.
    @Test func theFetchedSubtitleIsNotTakenBackByThePreference() async {
        let engine = FakeVideoPlayerEngine()
        engine.subtitleTracks = [track("spu/20", "bdpg", "he")]
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "he")]
        let m = model(engine, prefs: FakeTrackPreferences(subtitle: .language("he")), subs: subs)
        m.start()
        engine.emit(.tracksChanged)
        await m.waitForIdleForTesting()
        try? await Task.sleep(for: .seconds(0.3))   // the one-shot fetch fires
        await m.waitForIdleForTesting()

        #expect(subs.downloadedResults.count == 1)
        #expect(m.selectedSubtitleID == "ext/1")
    }

    /// …and it must still be the selection after the next `.tracksChanged`, which arrives for free
    /// (VLCKit keeps parsing) and re-runs the whole preference pass.
    @Test func theFetchedSubtitleSurvivesALaterTrackChange() async {
        let engine = FakeVideoPlayerEngine()
        engine.subtitleTracks = [track("spu/20", "bdpg", "he")]
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "he")]
        let m = model(engine, prefs: FakeTrackPreferences(subtitle: .language("he")), subs: subs)
        m.start()
        engine.emit(.tracksChanged)
        await m.waitForIdleForTesting()
        try? await Task.sleep(for: .seconds(0.3))
        await m.waitForIdleForTesting()

        engine.subtitleTracks.append(track("spu/21", "bdpg", "he"))   // discovery continues
        engine.emit(.tracksChanged)
        await m.waitForIdleForTesting()

        #expect(m.selectedSubtitleID == "ext/1")
    }

    /// Picking a specific release in the search browser is a viewer decision every bit as much as
    /// tapping the language pill. It did not say so, so the automatic pick was still live and
    /// re-decided over it the moment the slave appeared.
    @Test func aBrowserPickIsTreatedAsAViewerDecision() async {
        let engine = FakeVideoPlayerEngine()
        engine.subtitleTracks = [track("spu/20", "bdpg", "he")]
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 9, language: "he", release: "PARTICULAR")]
        let m = model(engine, prefs: FakeTrackPreferences(subtitle: .language("he")), subs: subs)
        m.start()
        engine.emit(.tracksChanged)
        await m.waitForIdleForTesting()

        await m.searchSubtitles(language: "he")
        await m.useSubtitle(m.subtitleSearchResults[0])
        engine.emit(.tracksChanged)
        await m.waitForIdleForTesting()

        #expect(m.subtitlePickedByUser)
        #expect(m.selectedSubtitleID == "ext/1")
    }

    /// libvlc keys a playback slave by URL: adding one it already holds surfaces no new track. The
    /// pending-attach handshake then never completed, and eight seconds later the row timed out
    /// into "not found, try Search" — with a perfectly good Hebrew track in the list, deselected.
    @Test func askingAgainForALanguageAlreadyAttachedSelectsItInsteadOfFailing() async {
        let engine = FakeVideoPlayerEngine()
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "he")]
        let m = model(engine, prefs: FakeTrackPreferences(subtitle: .automatic), subs: subs)
        m.start()
        await m.waitForIdleForTesting()

        await m.requestSubtitle(language: "he")
        await m.waitForIdleForTesting()
        #expect(m.selectedSubtitleID == "ext/1")

        m.selectSubtitleOff()                       // …the viewer turns them off, then changes their mind
        await m.requestSubtitle(language: "he")
        await m.waitForIdleForTesting()

        #expect(m.selectedSubtitleID == "ext/1")
        #expect(m.subtitleRows.first { $0.language == "he" }?.state == .attached("ext/1"))
        #expect(subs.downloadedResults.count == 1)  // the second ask re-used the track, not the quota
    }

    /// The same file chosen twice in the browser — the obvious thing to do when the first pick
    /// looked like it did nothing — must not strand the handshake either.
    @Test func choosingTheSameBrowserResultTwiceStillSelectsIt() async {
        let engine = FakeVideoPlayerEngine()
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 9, language: "he")]
        let m = model(engine, prefs: FakeTrackPreferences(subtitle: .automatic), subs: subs)
        m.start()
        await m.waitForIdleForTesting()

        await m.searchSubtitles(language: "he")
        await m.useSubtitle(m.subtitleSearchResults[0])
        await m.waitForIdleForTesting()
        m.selectSubtitleOff()
        await m.useSubtitle(m.subtitleSearchResults[0])
        await m.waitForIdleForTesting()

        #expect(m.selectedSubtitleID == "ext/1")
    }

    /// A language the file serves as TEXT still wins on its own merits — the fix must not turn
    /// every play into a download.
    @Test func anEmbeddedTextTrackIsStillPreferredOverFetchingOne() async {
        let engine = FakeVideoPlayerEngine()
        engine.subtitleTracks = [track("spu/3", "subt", "he")]
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "he")]
        let m = model(engine, prefs: FakeTrackPreferences(subtitle: .language("he")), subs: subs)
        m.start()
        engine.emit(.tracksChanged)
        await m.waitForIdleForTesting()
        try? await Task.sleep(for: .seconds(0.3))
        await m.waitForIdleForTesting()

        #expect(subs.downloadedResults.isEmpty)
        #expect(m.selectedSubtitleID == "spu/3")
    }
}

/// A downloaded subtitle reaches the picker as "Track 3" with no language — VLCKit tags a slave
/// with neither. The viewer asked for Hebrew; the row that appeared said "Track 3".
@MainActor
@Suite struct PlayerSubtitleLabelTests {

    @Test func aDownloadedSubtitleIsNamedForTheLanguageItWasFetchedFor() async {
        let engine = FakeVideoPlayerEngine()
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "he")]
        let m = PlayerModel(request: Fixture.request(), engine: engine,
                            unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                            recordProgress: { _, _, _, _, _ in }, subtitles: subs)
        m.start()
        await m.waitForIdleForTesting()
        await m.requestSubtitle(language: "he")
        await m.waitForIdleForTesting()

        #expect(m.downloadedLanguageName(forTrackID: "ext/1") == "Hebrew")
        #expect(m.downloadedLanguageName(forTrackID: "spu/2") == nil)   // a muxed track keeps its own
    }

    /// Both spellings a container may use for a code, plus the two things that are not codes.
    @Test func aTrackLanguageCodeIsNamedInEnglish() {
        #expect(PlayerModel.languageName("he") == "Hebrew")
        #expect(PlayerModel.languageName("heb") == "Hebrew")
        #expect(PlayerModel.languageName("en") == "English")
        #expect(PlayerModel.languageName("zzz") == "ZZZ")       // nothing can name it
        // A container that wrote a NAME where a code belongs must not be shouted back.
        #expect(PlayerModel.languageName("Brazilian Portuguese") == "Brazilian Portuguese")
    }
}
