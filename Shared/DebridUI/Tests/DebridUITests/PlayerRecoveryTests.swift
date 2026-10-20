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
}
