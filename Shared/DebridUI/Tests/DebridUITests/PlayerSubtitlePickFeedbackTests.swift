import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// Pressing a subtitle in the search browser did nothing, on the real Apple TV, every time.
///
/// The device's own `vlc.log` settled what: across five plays over two days there is not one
/// `add subtitle` line. No subtitle has ever been downloaded on that device — while the simulator
/// downloads one within two seconds of every play. Whatever stops it (no OpenSubtitles account in
/// that Keychain, an exhausted daily cap, a refused login), `useSubtitle` collapsed all of it into
/// `subtitleSearchState = .failed` and the browser closed itself immediately afterwards on both
/// platforms — so every one of those causes looked identical, and identical to being ignored.
///
/// A pick that cannot be honoured has to say so, in the viewer's words, without closing the list
/// they were choosing from.
@MainActor
@Suite struct PlayerSubtitlePickFeedbackTests {

    private func model(_ subs: FakeSubtitleProvider?) -> PlayerModel {
        PlayerModel(request: Fixture.request(), engine: FakeVideoPlayerEngine(),
                    unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                    recordProgress: { _, _, _, _ in }, subtitles: subs)
    }

    private func ranked() -> SubtitleMatch.Ranked {
        SubtitleMatch.rank([SubtitleResult(fileID: 1, language: "he")],
                           against: "Dune", videoFPS: nil)[0]
    }

    /// The case the device is almost certainly in: no account, so the provider was never built.
    /// It returned on its own `guard` without a word.
    @Test func aPickWithNoAccountSaysSoInsteadOfReturningSilently() async {
        let m = model(nil)
        m.start()
        await m.waitForIdleForTesting()

        let applied = await m.useSubtitle(ranked())

        #expect(applied == false)
        #expect(m.subtitlePickFailure == .noAccount)
        // The viewer has to be told where to go, not just that it failed.
        #expect(m.subtitlePickFailure?.message.contains("OpenSubtitles") == true)
    }

    @Test func aPickBlockedByTheDailyCapSaysSo() async {
        let subs = FakeSubtitleProvider()
        subs.downloadError = SubtitleError.dailyCapReached(resetTime: nil)
        let m = model(subs)
        m.start()
        await m.waitForIdleForTesting()

        let applied = await m.useSubtitle(ranked())

        #expect(applied == false)
        #expect(m.subtitlePickFailure == .capReached(nil))
        #expect(m.subtitlePickFailure?.message.contains("limit") == true)
    }

    /// An account that is configured but refused — a changed password, a revoked key.
    @Test func aRefusedLoginIsNotReportedAsADeadButton() async {
        let subs = FakeSubtitleProvider()
        subs.downloadError = SubtitleError.notAuthenticated
        let m = model(subs)
        m.start()
        await m.waitForIdleForTesting()

        let applied = await m.useSubtitle(ranked())

        #expect(applied == false)
        #expect(m.subtitlePickFailure == .noAccount)
    }

    @Test func anyOtherFailureStillSaysSomething() async {
        let subs = FakeSubtitleProvider()
        subs.downloadError = URLError(.timedOut)
        let m = model(subs)
        m.start()
        await m.waitForIdleForTesting()

        let applied = await m.useSubtitle(ranked())

        #expect(applied == false)
        #expect(m.subtitlePickFailure == .failed)
        #expect(m.subtitlePickFailure?.message.isEmpty == false)
    }

    /// …and a pick that works reports success, so the browser knows it may close.
    @Test func aPickThatWorksReportsSuccessAndClearsAnEarlierFailure() async {
        let subs = FakeSubtitleProvider()
        subs.downloadError = URLError(.timedOut)
        let m = model(subs)
        m.start()
        await m.waitForIdleForTesting()
        _ = await m.useSubtitle(ranked())
        #expect(m.subtitlePickFailure != nil)

        subs.downloadError = nil
        let applied = await m.useSubtitle(ranked())

        #expect(applied)
        #expect(m.subtitlePickFailure == nil)
        #expect(m.selectedSubtitleID == "ext/1")
    }

    /// The list the viewer is standing in has to survive a failed pick — otherwise keeping the
    /// browser open buys them a reason and nothing to act on. (It did not: the first version of
    /// this fix marked the SEARCH failed, which is what the browser draws its list from.)
    @Test func aFailedPickLeavesTheResultsOnScreenToRetryFrom() async {
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "he"),
                              SubtitleResult(fileID: 2, language: "he")]
        let m = model(subs)
        m.start()
        await m.waitForIdleForTesting()
        await m.searchSubtitles(language: "he")
        #expect(m.subtitleSearchResults.count == 2)

        subs.downloadError = SubtitleError.notAuthenticated
        _ = await m.useSubtitle(m.subtitleSearchResults[0])

        #expect(m.subtitleSearchState == .loaded)        // the SEARCH did not fail; one download did
        #expect(m.subtitleSearchResults.count == 2)
    }

    /// Starting a new search is the viewer moving on; the stale complaint must not outlive it.
    @Test func aNewSearchClearsTheFailure() async {
        let subs = FakeSubtitleProvider()
        subs.downloadError = URLError(.timedOut)
        subs.searchResults = [SubtitleResult(fileID: 2, language: "en")]
        let m = model(subs)
        m.start()
        await m.waitForIdleForTesting()
        _ = await m.useSubtitle(ranked())
        #expect(m.subtitlePickFailure != nil)

        await m.searchSubtitles(language: "en")

        #expect(m.subtitlePickFailure == nil)
    }

    /// A download that succeeds but whose track never appears is the same silence by another route.
    @Test func anAttachThatNeverLandsIsReportedToo() async {
        let engine = FakeVideoPlayerEngine()
        engine.deferSlaveAttach = true          // VLCKit accepts the slave and never surfaces it
        let subs = FakeSubtitleProvider()
        let m = PlayerModel(request: Fixture.request(), engine: engine,
                            unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                            recordProgress: { _, _, _, _ in }, subtitles: subs)
        m.start()
        await m.waitForIdleForTesting()
        _ = await m.useSubtitle(ranked())
        #expect(m.subtitlePickFailure == nil)     // nothing has gone wrong yet — it is still pending

        m.failPendingSubtitleAttachForTesting()
        await m.waitForIdleForTesting()

        #expect(m.subtitlePickFailure == .failed)
    }
}
