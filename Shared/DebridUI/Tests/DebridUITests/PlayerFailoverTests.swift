import Foundation
import Testing
@testable import DebridUI
import DebridCore

/// With both accounts signed in a title can have versions on Real-Debrid AND TorBox. When the
/// current version's provider is down (2026-10-24: RD's file servers answered 503 to every fetch
/// while its API worked), the player moves to the other provider's version by itself — once.
@MainActor
@Suite struct PlayerFailoverTests {

    private final class Calls: @unchecked Sendable {
        var links: [String] = []
    }

    nonisolated private static let rd = "rd://one"
    nonisolated private static let rd2 = "rd://two"
    nonisolated private static let tb = "torbox://tb:7/0"
    nonisolated private static let outage = HTTPError.status(code: 503, body: "")

    private func model(_ engine: FakeVideoPlayerEngine, links: [String], resumeAt: Double? = nil,
                       proxy: FakeStreamProxy? = nil, calls: Calls = Calls(),
                       loadTimeout: Double = 30,
                       unrestrict: @escaping @Sendable (String) throws -> URL = { _ in
                           URL(string: "https://cdn/x.mkv")!
                       }) -> PlayerModel {
        let sources = links.map { Fixture.movieSource($0) }
        return PlayerModel(request: Fixture.request(resumeAt: resumeAt, sources: sources), engine: engine,
                           unrestrict: { link in
                               calls.links.append(link)
                               return try unrestrict(link)
                           },
                           recordProgress: { _, _, _, _, _ in }, subtitles: nil, streamProxy: proxy,
                           loadTimeout: loadTimeout,
                           unrestrictAttemptTimeout: 10, unrestrictRetryDelays: [0.01, 0.01],
                           unrestrictBudget: 15)
    }

    /// RD down for this link: 503 for it, a playable URL for anything else.
    nonisolated private static func rdDown(_ link: String) throws -> URL {
        if DebridProvider.of(link: link) == .realDebrid { throw outage }
        return URL(string: "https://cdn/tb.mkv")!
    }

    private func playTo(_ position: Double, duration: Double = 6000, _ model: PlayerModel,
                        _ engine: FakeVideoPlayerEngine) async {
        engine.emit(.state(.playing))
        engine.emit(.time(.init(position: position - 1, duration: duration)))
        engine.emit(.time(.init(position: position, duration: duration)))
        await model.waitForIdleForTesting()
    }

    /// Wait for something a timer decides — the watchdog, the notice — without betting on a sleep.
    private func eventually(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }
    }

    // MARK: - The unrestrict failing for now

    @Test func transientUnrestrictFailureFailsOverToOtherProvider() async {
        let engine = FakeVideoPlayerEngine(), calls = Calls()
        let m = model(engine, links: [Self.rd, Self.tb], calls: calls, unrestrict: Self.rdDown)
        m.start(); await m.waitForIdleForTesting()

        #expect(!m.phase.isFailed, "the outage was shown as \(m.phase)")
        #expect(m.currentSource.restrictedLink == Self.tb)
        #expect(engine.loadCount == 1)
        #expect(engine.loadedURL == URL(string: "https://cdn/tb.mkv"))
        #expect(calls.links.last == Self.tb)
        #expect(m.failoverNotice == "Real-Debrid isn't responding — playing from TorBox")
        await m.teardown()
    }

    @Test func failoverKeepsResumePosition() async {
        let engine = FakeVideoPlayerEngine()
        let m = model(engine, links: [Self.rd, Self.tb], resumeAt: 600, unrestrict: Self.rdDown)
        m.start(); await m.waitForIdleForTesting()

        #expect(m.currentSource.restrictedLink == Self.tb)
        #expect(engine.seeks.last == 600, "the TorBox load seeked to \(engine.seeks)")
        await m.teardown()
    }

    @Test func noOtherProviderShowsError() async {
        let engine = FakeVideoPlayerEngine()
        let m = model(engine, links: [Self.rd, Self.rd2], unrestrict: Self.rdDown)
        m.start(); await m.waitForIdleForTesting()

        #expect(m.phase == .failed(PlayerModel.unreachableMessage(.realDebrid)))
        #expect(m.phase == .failed("Real-Debrid isn't responding right now. Check your connection, then try again."))
        #expect(m.currentSource.restrictedLink == Self.rd, "an RD outage moved to another RD version")
        #expect(engine.loadCount == 0)
        #expect(m.failoverNotice == nil)
        await m.teardown()
    }

    @Test func failoverHappensOncePerLoad() async {
        let engine = FakeVideoPlayerEngine(), calls = Calls()
        let m = model(engine, links: [Self.rd, Self.tb], calls: calls, unrestrict: { _ in throw Self.outage })
        m.start(); await m.waitForIdleForTesting()

        #expect(m.phase == .failed("TorBox isn't responding right now. Check your connection, then try again."))
        #expect(m.currentSource.restrictedLink == Self.tb)
        // The attempt and two retries on each provider — and no going back.
        #expect(calls.links == [Self.rd, Self.rd, Self.rd, Self.tb, Self.tb, Self.tb])
        #expect(engine.loadCount == 0)
        #expect(m.failoverNotice == nil, "a notice about playing from TorBox over its error")
        await m.teardown()
    }

    /// The viewer's Retry is a fresh attempt, with its own failover.
    @Test func retryEarnsItsOwnFailover() async {
        let engine = FakeVideoPlayerEngine(), calls = Calls()
        let m = model(engine, links: [Self.rd, Self.tb], calls: calls, unrestrict: { _ in throw Self.outage })
        m.start(); await m.waitForIdleForTesting()
        #expect(m.phase.isFailed)

        m.retry(); await m.waitForIdleForTesting()

        #expect(calls.links.suffix(6) == [Self.tb, Self.tb, Self.tb, Self.rd, Self.rd, Self.rd])
        #expect(m.phase == .failed(PlayerModel.unreachableMessage(.realDebrid)))
        await m.teardown()
    }

    @Test func copyNamesTorBox() async {
        let engine = FakeVideoPlayerEngine()
        let m = model(engine, links: [Self.tb], unrestrict: { _ in
            throw HTTPError.status(code: 403, body: "{\"error\":\"DOWNLOAD_NOT_CACHED\"}")
        })
        m.start(); await m.waitForIdleForTesting()

        #expect(m.phase == .failed("The TorBox link could not be opened."))
        await m.teardown()
    }

    /// RD's own "no" is RD's answer, not an outage: nothing to fail over from.
    @Test func aRefusedUnrestrictDoesNotFailOver() async {
        let engine = FakeVideoPlayerEngine()
        let m = model(engine, links: [Self.rd, Self.tb], unrestrict: { _ in
            throw HTTPError.status(code: 403, body: "{\"error\":\"hoster_unavailable\"}")
        })
        m.start(); await m.waitForIdleForTesting()

        #expect(m.phase == .failed("The Real-Debrid link could not be opened."))
        #expect(m.currentSource.restrictedLink == Self.rd)
        await m.teardown()
    }

    // MARK: - The stream failing for now

    /// Mid-film: the outage gets its reopen on the same provider first, then the other provider —
    /// at the playhead.
    @Test func anOutageMidFilmFailsOverAtThePlayhead() async {
        let engine = FakeVideoPlayerEngine(), proxy = FakeStreamProxy()
        let m = model(engine, links: [Self.rd, Self.tb], proxy: proxy)
        m.start(); await m.waitForIdleForTesting()
        await playTo(3000, m, engine)
        await proxy.outageWith(.upstreamStatus(503))
        engine.emit(.state(.ended)); await m.waitForIdleForTesting()
        #expect(engine.loadCount == 2)                         // the same-provider reopen
        #expect(m.currentSource.restrictedLink == Self.rd)
        await playTo(3010, m, engine)

        engine.emit(.state(.ended)); await m.waitForIdleForTesting()

        #expect(!m.phase.isFailed, "the outage was shown as \(m.phase)")
        #expect(m.currentSource.restrictedLink == Self.tb)
        #expect(engine.loadCount == 3)
        #expect(engine.seeks.last == 3010)
        #expect(m.failoverNotice == "Real-Debrid isn't responding — playing from TorBox")
        await m.teardown()
    }

    /// A cold open that fails twice while the provider is down — the 2026-10-24 outage exactly.
    @Test func aColdOpenDuringAnOutageFailsOver() async {
        let engine = FakeVideoPlayerEngine(), proxy = FakeStreamProxy()
        let m = model(engine, links: [Self.rd, Self.tb], proxy: proxy)
        m.start(); await m.waitForIdleForTesting()
        await proxy.outageWith(.upstreamStatus(503))
        engine.emit(.state(.failed("Playback failed."))); await m.waitForIdleForTesting()
        #expect(engine.loadCount == 2)                         // the silent reopen

        engine.emit(.state(.failed("Playback failed."))); await m.waitForIdleForTesting()

        #expect(!m.phase.isFailed, "the outage was shown as \(m.phase)")
        #expect(m.currentSource.restrictedLink == Self.tb)
        #expect(engine.loadCount == 3)
        await m.teardown()
    }

    @Test func theWatchdogFailsOverWhenTheProviderIsDown() async {
        let engine = FakeVideoPlayerEngine(), proxy = FakeStreamProxy()
        let m = model(engine, links: [Self.rd, Self.tb], proxy: proxy, loadTimeout: 0.05)
        m.start(); await m.waitForIdleForTesting()
        await proxy.outageWith(.upstreamStatus(503))

        await eventually { engine.loadCount == 2 }
        await m.waitForIdleForTesting()

        #expect(m.currentSource.restrictedLink == Self.tb)
        #expect(engine.loadCount == 2)
        await m.teardown()
    }

    @Test func theWatchdogNamesTheProvider() async {
        let engine = FakeVideoPlayerEngine()
        let m = model(engine, links: [Self.tb], loadTimeout: 0.05)
        m.start(); await m.waitForIdleForTesting()

        await eventually { m.phase.isFailed }
        await m.waitForIdleForTesting()

        #expect(m.phase == .failed("This stream didn't start. The TorBox link may have expired."))
        await m.teardown()
    }

    @Test func aRefusalNamesTheProvider() async {
        let engine = FakeVideoPlayerEngine(), proxy = FakeStreamProxy()
        let m = model(engine, links: [Self.tb, Self.rd], proxy: proxy)
        m.start(); await m.waitForIdleForTesting()
        await playTo(3000, m, engine)
        await proxy.failWith(.upstreamStatus(404))

        engine.emit(.state(.ended)); await m.waitForIdleForTesting()

        #expect(m.phase == .failed("TorBox no longer has this file."))
        #expect(m.currentSource.restrictedLink == Self.tb, "a refusal is not an outage")
        await m.teardown()
    }

    // MARK: - Review fixes (round 1)

    /// The realistic mid-film chain: RD drops (the cache saw it fail for now), the same-provider
    /// reopen at the playhead fails to open, and the other provider's version opens at the
    /// ORIGINAL playhead.
    @Test func aMidFilmReopenThatFailsToOpenFailsOverAtTheOriginalPlayhead() async {
        let engine = FakeVideoPlayerEngine(), proxy = FakeStreamProxy()
        let m = model(engine, links: [Self.rd, Self.tb], proxy: proxy)
        m.start(); await m.waitForIdleForTesting()
        await playTo(3000, m, engine)
        await proxy.outageWith(.upstreamStatus(503))
        engine.emit(.state(.failed("Playback failed."))); await m.waitForIdleForTesting()
        #expect(engine.loadCount == 2)                         // the silent reopen, at 3000
        #expect(m.currentSource.restrictedLink == Self.rd)

        engine.emit(.state(.failed("Playback failed."))); await m.waitForIdleForTesting()

        #expect(!m.phase.isFailed, "the outage was shown as \(m.phase)")
        #expect(m.currentSource.restrictedLink == Self.tb)
        #expect(engine.loadCount == 3)
        #expect(engine.seeks.last == 3000, "the TorBox load seeked to \(engine.seeks)")
        await m.teardown()
    }

    /// …and the same when the drop reaches the player as an end of file (a closed connection).
    @Test func aMidFilmEndWhoseReopenEndsUnstartedFailsOverAtTheOriginalPlayhead() async {
        let engine = FakeVideoPlayerEngine(), proxy = FakeStreamProxy()
        let m = model(engine, links: [Self.rd, Self.tb], proxy: proxy)
        m.start(); await m.waitForIdleForTesting()
        await playTo(3000, m, engine)
        await proxy.outageWith(.upstreamStatus(503))
        engine.emit(.state(.ended)); await m.waitForIdleForTesting()
        #expect(engine.loadCount == 2)                         // finish()'s reopen, at 3000

        engine.emit(.state(.ended)); await m.waitForIdleForTesting()

        #expect(!m.phase.isFailed, "the outage was shown as \(m.phase)")
        #expect(m.currentSource.restrictedLink == Self.tb)
        #expect(engine.loadCount == 3)
        #expect(engine.seeks.last == 3000, "the TorBox load seeked to \(engine.seeks)")
        await m.teardown()
    }

    /// A failure that may yet fail over is not published while the cache is asked: on tvOS a
    /// `.failed` that is pulled back a moment later still moves focus to Retry.
    @Test func aFailureThatMayFailOverIsNotPublishedFirst() async {
        let engine = FakeVideoPlayerEngine(), proxy = FakeStreamProxy()
        let m = model(engine, links: [Self.rd, Self.tb], proxy: proxy)
        m.start(); await m.waitForIdleForTesting()
        await proxy.outageWith(.upstreamStatus(503))
        engine.emit(.state(.failed("Playback failed."))); await m.waitForIdleForTesting()
        #expect(engine.loadCount == 2)                         // the silent reopen

        m.handle(state: .failed("Playback failed."))           // synchronously, as the event loop does
        #expect(!m.phase.isFailed, "published \(m.phase) before the cache answered")
        #expect(m.isBuffering)
        await m.waitForIdleForTesting()

        #expect(m.currentSource.restrictedLink == Self.tb)
        #expect(!m.phase.isFailed)
        await m.teardown()
    }

    /// When the cache's answer is not an outage, the held failure is still shown — reworded.
    @Test func aHeldFailureIsShownWhenTheCacheSaysRefused() async {
        let engine = FakeVideoPlayerEngine(), proxy = FakeStreamProxy()
        let m = model(engine, links: [Self.rd, Self.tb], proxy: proxy)
        m.start(); await m.waitForIdleForTesting()
        engine.emit(.state(.failed("Playback failed."))); await m.waitForIdleForTesting()
        #expect(engine.loadCount == 2)                         // the silent reopen
        await proxy.failWith(.upstreamStatus(404))

        engine.emit(.state(.failed("Playback failed."))); await m.waitForIdleForTesting()

        #expect(m.phase == .failed("Real-Debrid no longer has this file."))
        #expect(m.currentSource.restrictedLink == Self.rd)
        #expect(!m.isBuffering)
        await m.teardown()
    }

    /// The first frame arriving while the watchdog asks the cache why: the stream started, and
    /// must not be marked failed when the answer comes back "nothing wrong".
    @Test func aFrameDuringTheWatchdogsQuestionIsNotAFailure() async {
        let engine = FakeVideoPlayerEngine(), proxy = FakeStreamProxy()
        let m = model(engine, links: [Self.rd, Self.tb], proxy: proxy, loadTimeout: 0.05)
        let release = await proxy.holdFailureAnswers()
        m.start(); await m.waitForIdleForTesting()
        let watchdog = m.loadWatchdog
        var asked = false
        let deadline = Date().addingTimeInterval(5)
        while !asked, Date() < deadline {
            asked = await proxy.failureQueries > 0
            if !asked { try? await Task.sleep(for: .milliseconds(5)) }
        }
        #expect(asked, "the watchdog never asked the cache")

        await playTo(10, m, engine)                            // the first frame, mid-question
        release.finish()
        await watchdog?.value

        #expect(!m.phase.isFailed, "a stream that started was marked \(m.phase)")
        await m.teardown()
    }

    /// The failed reopen's watchdog must not fail the other provider's version while that one is
    /// still resolving its link.
    @Test func theFailedLoadsWatchdogDoesNotFailTheFailover() async {
        let engine = FakeVideoPlayerEngine(), proxy = FakeStreamProxy()
        let held = LinkGate()
        let m = PlayerModel(request: Fixture.request(sources: [Fixture.movieSource(Self.rd),
                                                               Fixture.movieSource(Self.tb)]),
                            engine: engine,
                            unrestrict: { link in
                                if DebridProvider.of(link: link) == .torBox { await held.wait() }
                                return URL(string: "https://cdn/x.mkv")!
                            },
                            recordProgress: { _, _, _, _, _ in }, subtitles: nil, streamProxy: proxy,
                            loadTimeout: 0.3)
        m.start(); await m.waitForIdleForTesting()
        await proxy.outageWith(.upstreamStatus(503))
        engine.emit(.state(.failed("Playback failed."))); await m.waitForIdleForTesting()
        engine.emit(.state(.failed("Playback failed.")))       // → the TorBox load, held in unrestrict
        await m.waitForIdleWhileLoadIsHeldForTesting()
        #expect(m.currentSource.restrictedLink == Self.tb)

        try? await Task.sleep(for: .milliseconds(700))         // past the old load's watchdog

        #expect(!m.phase.isFailed, "the old watchdog failed the TorBox load: \(m.phase)")
        await held.open()
        await m.waitForIdleForTesting()
        #expect(engine.loadCount == 3)
        await m.teardown()
    }

    // MARK: - The notice

    @Test func theNoticeLeavesSoonAfterTheFirstFrame() async {
        let engine = FakeVideoPlayerEngine()
        let m = model(engine, links: [Self.rd, Self.tb], unrestrict: Self.rdDown)
        m.failoverNoticeSeconds = 0.5
        m.start(); await m.waitForIdleForTesting()
        #expect(m.failoverNotice != nil)

        await playTo(10, m, engine)
        #expect(m.failoverNotice != nil, "gone on the first frame, before anyone could read it")
        await eventually { m.failoverNotice == nil }

        #expect(m.failoverNotice == nil)
        await m.teardown()
    }
}

/// Holds a TorBox unrestrict until the test opens it.
private actor LinkGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
