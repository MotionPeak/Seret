import Foundation
import Testing
@testable import DebridUI
import DebridCore

/// Failures the app can recover from by itself never reach the viewer (QA sweep 2026-10-20).
///
/// - D2: 5 of 26 opens on the Apple TV ended on "Playback failed." — the stream proxy's socket
///   reclaimed while idle. One silent reopen, on a fresh socket and link, comes first.
/// - D6: one failed or hung RD `unrestrict` was the error screen (or 30 s of spinner).
/// - D8: RD failing for now (an outage) said "Real-Debrid stopped sending this file".
@MainActor
@Suite struct PlayerRecoveryTests {

    private final class Box<T>: @unchecked Sendable {
        var value: T
        init(_ value: T) { self.value = value }
    }

    private func model(_ engine: FakeVideoPlayerEngine, proxy: FakeStreamProxy? = nil,
                       unrestricts: Box<Int> = Box(0),
                       unrestrict: ((Int) async throws -> URL)? = nil,
                       attemptTimeout: Double = 10, retryDelays: [Double] = [0.01, 0.01],
                       budget: Double = 15) -> PlayerModel {
        PlayerModel(request: Fixture.request(), engine: engine,
                    unrestrict: { _ in
                        unrestricts.value += 1
                        if let unrestrict { return try await unrestrict(unrestricts.value) }
                        return URL(string: "https://cdn/x.mkv")!
                    },
                    recordProgress: { _, _, _, _, _ in }, subtitles: nil, streamProxy: proxy,
                    unrestrictAttemptTimeout: attemptTimeout, unrestrictRetryDelays: retryDelays,
                    unrestrictBudget: budget)
    }

    private func playTo(_ position: Double, duration: Double = 6000, _ model: PlayerModel,
                        _ engine: FakeVideoPlayerEngine) async {
        engine.emit(.state(.playing))
        engine.emit(.time(.init(position: position - 1, duration: duration)))
        engine.emit(.time(.init(position: position, duration: duration)))
        await model.waitForIdleForTesting()
    }

    // MARK: - D2: one silent reopen

    @Test func aFailedOpenReopensOnceOnAFreshSocketAndLink() async {
        let engine = FakeVideoPlayerEngine(), proxy = FakeStreamProxy(), unrestricts = Box(0)
        let m = model(engine, proxy: proxy, unrestricts: unrestricts)
        m.start(); await m.waitForIdleForTesting()

        engine.emit(.state(.failed("Playback failed."))); await m.waitForIdleForTesting()

        #expect(!m.phase.isFailed, "the first failed open reached the viewer")
        #expect(engine.loadCount == 2)
        #expect(unrestricts.value == 2)                    // a fresh link…
        #expect(await proxy.opened.count == 2)             // …through a fresh stream session
        #expect(m.isColdOpen)                              // still the loading screen, no error

        engine.emit(.state(.failed("Playback failed."))); await m.waitForIdleForTesting()
        #expect(m.phase == .failed("Playback failed."))    // the second one is shown
        #expect(engine.loadCount == 2)
        await m.teardown()
    }

    /// The `.ended` libvlc sends after its error belongs to the dying media, not the reopen.
    @Test func theEndThatFollowsTheErrorDoesNotSpendTheReopensFailure() async {
        let engine = FakeVideoPlayerEngine()
        let m = model(engine)
        m.start(); await m.waitForIdleForTesting()
        engine.emit(.state(.failed("Playback failed.")))
        engine.emit(.state(.ended))
        await m.waitForIdleForTesting()
        #expect(!m.phase.isFailed)
        #expect(engine.loadCount == 2)
        await m.teardown()
    }

    @Test func aStreamRDRefusedIsNotReopened() async {
        let engine = FakeVideoPlayerEngine(), proxy = FakeStreamProxy()
        let m = model(engine, proxy: proxy)
        m.start(); await m.waitForIdleForTesting()
        await proxy.failWith(.upstreamStatus(404))
        engine.emit(.state(.failed("Playback failed."))); await m.waitForIdleForTesting()
        #expect(m.phase == .failed("Real-Debrid no longer has this file."))
        #expect(engine.loadCount == 1)
        await m.teardown()
    }

    @Test func aMidFilmFailureReopensAtThePlayhead() async {
        let engine = FakeVideoPlayerEngine()
        let m = model(engine)
        m.start(); await m.waitForIdleForTesting()
        await playTo(1200, m, engine)

        engine.emit(.state(.failed("Playback failed."))); await m.waitForIdleForTesting()

        #expect(!m.phase.isFailed)
        #expect(engine.loadCount == 2)
        #expect(engine.seeks.last == 1200)
        await m.teardown()
    }

    /// Played again after the reopen, a later failure somewhere else is a new one…
    @Test func aReopenThatPlaysEarnsTheNextFailureItsOwnReopen() async {
        let engine = FakeVideoPlayerEngine()
        let m = model(engine)
        m.start(); await m.waitForIdleForTesting()
        await playTo(1200, m, engine)
        engine.emit(.state(.failed("Playback failed."))); await m.waitForIdleForTesting()
        await playTo(2400, m, engine)

        engine.emit(.state(.failed("Playback failed."))); await m.waitForIdleForTesting()

        #expect(!m.phase.isFailed)
        #expect(engine.loadCount == 3)
        await m.teardown()
    }

    /// …but failing again where it failed before is the file, not the network: shown.
    @Test func failingAgainAtTheSamePlaceIsShown() async {
        let engine = FakeVideoPlayerEngine()
        let m = model(engine)
        m.start(); await m.waitForIdleForTesting()
        await playTo(1200, m, engine)
        engine.emit(.state(.failed("Playback failed."))); await m.waitForIdleForTesting()
        await playTo(1210, m, engine)

        engine.emit(.state(.failed("Playback failed."))); await m.waitForIdleForTesting()

        #expect(m.phase == .failed("Playback failed."))
        #expect(engine.loadCount == 2)
        await m.teardown()
    }

    /// The review's loop (D2): libvlc reports `.playing` before any frame, and that re-armed the
    /// silent reopen — so an open that "played" and failed reopened forever, an RD unrestrict and
    /// a libvlc open each time, until RD throttled the account.
    @Test func anOpenThatOnlyReportsPlayingCannotReopenForever() async {
        let engine = FakeVideoPlayerEngine(), unrestricts = Box(0)
        let m = model(engine, unrestricts: unrestricts)
        m.start(); await m.waitForIdleForTesting()

        for _ in 0..<5 {
            engine.emit(.state(.playing))
            engine.emit(.state(.failed("Playback failed.")))
            await m.waitForIdleForTesting()
        }

        #expect(engine.loadCount <= 2, "reopened \(engine.loadCount - 1) times")
        #expect(unrestricts.value <= 2)
        #expect(m.phase == .failed("Playback failed."))
        await m.teardown()
    }

    /// The same mid-film: the reopen sits at the place it reopened at until its playhead settles,
    /// and failing there again is failing at the same place.
    @Test func aMidFilmReopenThatOnlyReportsPlayingCannotReopenForever() async {
        let engine = FakeVideoPlayerEngine()
        let m = model(engine)
        m.start(); await m.waitForIdleForTesting()
        await playTo(1200, m, engine)

        engine.emit(.state(.failed("Playback failed."))); await m.waitForIdleForTesting()
        for _ in 0..<5 {
            engine.emit(.state(.playing))
            engine.emit(.state(.failed("Playback failed.")))
            await m.waitForIdleForTesting()
        }

        #expect(engine.loadCount == 2)
        #expect(m.phase.isFailed)
        await m.teardown()
    }

    /// Whatever asks — failures at new places each time — no more than two automatic reopens a
    /// minute. The viewer's Retry starts the count afresh.
    @Test func automaticReopensAreCappedAndRetryResetsTheCap() async {
        let engine = FakeVideoPlayerEngine()
        let m = model(engine)
        m.start(); await m.waitForIdleForTesting()

        await playTo(1200, m, engine)
        engine.emit(.state(.failed("Playback failed."))); await m.waitForIdleForTesting()
        await playTo(2400, m, engine)
        engine.emit(.state(.failed("Playback failed."))); await m.waitForIdleForTesting()
        #expect(engine.loadCount == 3)
        await playTo(3600, m, engine)
        engine.emit(.state(.failed("Playback failed."))); await m.waitForIdleForTesting()
        #expect(engine.loadCount == 3, "a third automatic reopen within a minute")
        #expect(m.phase.isFailed)

        m.retry(); await m.waitForIdleForTesting()
        #expect(engine.loadCount == 4)
        await playTo(4800, m, engine)
        engine.emit(.state(.failed("Playback failed."))); await m.waitForIdleForTesting()
        #expect(!m.phase.isFailed)
        #expect(engine.loadCount == 5)
        await m.teardown()
    }

    /// A reopen that fails while RD is down says that RD is down — not "Playback failed."
    @Test func aReopenThatFailsDuringAnOutageIsWordedAsOne() async {
        let engine = FakeVideoPlayerEngine(), proxy = FakeStreamProxy()
        let m = model(engine, proxy: proxy)
        m.start(); await m.waitForIdleForTesting()
        await proxy.outageWith(.transport("The network connection was lost."))
        engine.emit(.state(.failed("Playback failed."))); await m.waitForIdleForTesting()
        #expect(engine.loadCount == 2)

        engine.emit(.state(.failed("Playback failed."))); await m.waitForIdleForTesting()

        #expect(m.phase == .failed(PlayerModel.unreachableMessage))
        await m.teardown()
    }

    /// …and so does one that ends before its first frame.
    @Test func aReopenThatEndsUnstartedDuringAnOutageIsWordedAsOne() async {
        let engine = FakeVideoPlayerEngine(), proxy = FakeStreamProxy()
        let m = model(engine, proxy: proxy)
        m.start(); await m.waitForIdleForTesting()
        await proxy.outageWith(.transport("The network connection was lost."))
        engine.emit(.state(.ended)); await m.waitForIdleForTesting()
        #expect(engine.loadCount == 2)

        engine.emit(.state(.ended)); await m.waitForIdleForTesting()

        #expect(m.phase == .failed(PlayerModel.unreachableMessage))
        await m.teardown()
    }

    // MARK: - D6: unrestrict, with a deadline and retries

    @Test func anUnrestrictThatFailsForNowIsAskedAgain() async {
        let engine = FakeVideoPlayerEngine(), unrestricts = Box(0)
        let m = model(engine, unrestricts: unrestricts, unrestrict: { call in
            if call == 1 { throw URLError(.networkConnectionLost) }      // -1005 after a wake
            return URL(string: "https://cdn/x.mkv")!
        })
        m.start(); await m.waitForIdleForTesting()
        #expect(unrestricts.value == 2)
        #expect(engine.loadCount == 1)
        #expect(!m.phase.isFailed)
        await m.teardown()
    }

    @Test func RDsOwnNoIsNotRetried() async {
        let engine = FakeVideoPlayerEngine(), unrestricts = Box(0)
        let m = model(engine, unrestricts: unrestricts, unrestrict: { _ in
            throw HTTPError.status(code: 403, body: "{\"error\":\"hoster_unavailable\"}")
        })
        m.start(); await m.waitForIdleForTesting()
        #expect(unrestricts.value == 1)
        #expect(m.phase == .failed("The Real-Debrid link could not be opened."))
        await m.teardown()
    }

    @Test func anUnrestrictThatHangsIsAbandonedAndAskedAgain() async {
        let engine = FakeVideoPlayerEngine(), unrestricts = Box(0), release = Box(false)
        let m = model(engine, unrestricts: unrestricts, unrestrict: { call in
            if call == 1 {
                // Hung, and deaf to cancellation — as an await on another task's value is.
                while !release.value { try? await Task.sleep(for: .milliseconds(10)) }
            }
            return URL(string: "https://cdn/x.mkv")!
        }, attemptTimeout: 0.2)
        m.start(); await m.waitForIdleForTesting()
        #expect(unrestricts.value == 2)
        #expect(engine.loadCount == 1)
        #expect(!m.phase.isFailed)
        release.value = true
        await m.teardown()
    }

    @Test func anRDThatStaysUnreachableSaysSoPlainly() async {
        let engine = FakeVideoPlayerEngine(), unrestricts = Box(0)
        let m = model(engine, unrestricts: unrestricts, unrestrict: { _ in
            throw URLError(.notConnectedToInternet)
        })
        m.start(); await m.waitForIdleForTesting()
        #expect(unrestricts.value == 3)                    // the attempt and two retries
        #expect(m.phase == .failed(PlayerModel.unreachableMessage))
        #expect(engine.loadCount == 0)
        await m.teardown()
    }

    // MARK: - D8: an outage is not the end, and not a refusal

    @Test func anEndDuringAnRDOutageReopensAtThePlayhead() async {
        let engine = FakeVideoPlayerEngine(), proxy = FakeStreamProxy()
        let m = model(engine, proxy: proxy)
        m.start(); await m.waitForIdleForTesting()
        await playTo(3000, m, engine)
        await proxy.outageWith(.transport("The network connection was lost."))

        engine.emit(.state(.ended)); await m.waitForIdleForTesting()

        #expect(!m.phase.isFailed, "an outage was shown as \(m.phase)")
        #expect(engine.loadCount == 2)
        #expect(engine.seeks.last == 3000)
        #expect(m.shouldDismiss == false)
        await m.teardown()
    }

    /// In the credits too: an outage taken for the film's end would be recorded as watched.
    @Test func anOutageInTheCreditsIsStillNotTheEnd() async {
        let engine = FakeVideoPlayerEngine(), proxy = FakeStreamProxy()
        let m = model(engine, proxy: proxy)
        m.start(); await m.waitForIdleForTesting()
        await playTo(5990, m, engine)
        await proxy.outageWith(.transport("The network connection was lost."))

        engine.emit(.state(.ended)); await m.waitForIdleForTesting()

        #expect(m.shouldDismiss == false)
        #expect(engine.loadCount == 2)
        await m.teardown()
    }

    /// The reopen fails the same way at the same place: now the viewer is told — in words that
    /// say what to do, not that the file is gone.
    @Test func anOutageThatOutlastsTheReopenIsWordedAsOne() async {
        let engine = FakeVideoPlayerEngine(), proxy = FakeStreamProxy()
        let m = model(engine, proxy: proxy)
        m.start(); await m.waitForIdleForTesting()
        await playTo(3000, m, engine)
        await proxy.outageWith(.transport("The network connection was lost."))
        engine.emit(.state(.ended)); await m.waitForIdleForTesting()
        await playTo(3001, m, engine)

        engine.emit(.state(.ended)); await m.waitForIdleForTesting()

        #expect(m.phase == .failed(PlayerModel.unreachableMessage))
        await m.teardown()
    }

    /// A refusal is still final, and still says so.
    @Test func anEndRDRefusedIsStillARefusal() async {
        let engine = FakeVideoPlayerEngine(), proxy = FakeStreamProxy()
        let m = model(engine, proxy: proxy)
        m.start(); await m.waitForIdleForTesting()
        await playTo(3000, m, engine)
        await proxy.failWith(.upstreamStatus(403))
        engine.emit(.state(.ended)); await m.waitForIdleForTesting()
        #expect(m.phase == .failed("Real-Debrid stopped sending this file (HTTP 403)."))
        #expect(engine.loadCount == 1)
        await m.teardown()
    }
}

/// Leaving the player (D14): teardown runs from `.onDisappear`, after the dismiss animation, and
/// the film played on — picture, sound and progress — through the whole pop.
@MainActor
@Suite struct PlayerClosingTests {
    @Test func closingSilencesAtOnceAndFreezesThePlace() async {
        let engine = FakeVideoPlayerEngine()
        var saved: [Double] = []
        let m = PlayerModel(request: Fixture.request(), engine: engine,
                            unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                            recordProgress: { _, _, position, _, _ in saved.append(position) },
                            subtitles: nil)
        m.start(); await m.waitForIdleForTesting()
        m.setVolume(150)
        engine.emit(.state(.playing))
        engine.emit(.time(.init(position: 600, duration: 6000)))
        engine.emit(.time(.init(position: 601, duration: 6000)))
        await m.waitForIdleForTesting()

        m.beginClosing()
        #expect(engine.volumesSet.last == 0)
        #expect(engine.pauseCount == 1)

        // The dismiss animation: the engine keeps talking until teardown.
        engine.emit(.time(.init(position: 602, duration: 6000)))
        engine.emit(.tracksChanged)
        await m.waitForIdleForTesting()
        #expect(m.position == 601, "the place moved on after Menu: \(m.position)")
        #expect(engine.volumesSet.last == 0, "a track refresh turned the sound back on")

        await m.teardown()
        #expect(saved.last == 601)
    }
}

/// The engine prepares for the file (on tvOS: the display mode) before it is loaded (D1).
@MainActor
@Suite struct PlayerPrepareTests {
    @Test func theEngineIsPreparedBeforeTheFileIsLoaded() async {
        let engine = FakeVideoPlayerEngine()
        let m = PlayerModel(request: Fixture.request(), engine: engine,
                            unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                            recordProgress: { _, _, _, _, _ in }, subtitles: nil)
        m.start(); await m.waitForIdleForTesting()
        #expect(engine.transport == ["prepare", "play"])
        #expect(engine.loadCount == 1)
        await m.teardown()
    }

    /// Leaving while the TV is still switching mode loads nothing into a player being torn down.
    @Test func leavingDuringThePrepareLoadsNothing() async {
        let engine = FakeVideoPlayerEngine()
        let (gate, release) = AsyncStream.makeStream(of: Void.self)
        engine.prepareGate = gate
        let m = PlayerModel(request: Fixture.request(), engine: engine,
                            unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                            recordProgress: { _, _, _, _, _ in }, subtitles: nil)
        m.start(); await m.waitForIdleWhileLoadIsHeldForTesting()
        for _ in 0..<200 where engine.transport.isEmpty { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(engine.transport == ["prepare"])
        await m.teardown()
        release.finish()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(engine.loadCount == 0)
    }
}

@MainActor
@Suite struct PlayerRecoveryWatchdogTests {
    /// The failed load's 30 s watchdog was still armed while the silent reopen resolved its link:
    /// firing then, it put "This stream didn't start" up over a reopen that was about to play.
    @Test func theFailedLoadsWatchdogDoesNotFireDuringTheReopen() async throws {
        let engine = FakeVideoPlayerEngine()
        let (gate, release) = AsyncStream.makeStream(of: Void.self)
        var calls = 0
        let m = PlayerModel(request: Fixture.request(), engine: engine,
                            unrestrict: { _ in
                                calls += 1
                                if calls == 2 { for await _ in gate {} }   // the reopen's link is slow
                                return URL(string: "https://cdn/x.mkv")!
                            },
                            recordProgress: { _, _, _, _, _ in }, subtitles: nil,
                            loadTimeout: 0.3)
        m.start(); await m.waitForIdleForTesting()
        try await Task.sleep(for: .milliseconds(150))
        engine.emit(.state(.failed("Playback failed.")))
        await m.waitForIdleWhileLoadIsHeldForTesting()
        try await Task.sleep(for: .milliseconds(300))           // past the first load's deadline
        #expect(!m.phase.isFailed, "the old watchdog fired over the reopen: \(m.phase)")
        release.finish()
        await m.waitForIdleForTesting()
        await m.teardown()
    }
}
