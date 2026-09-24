import Foundation
import Testing
@testable import DebridUI
import DebridCore

@MainActor
@Suite struct PlayerStreamProxyTests {
    private let local1 = URL(string: "http://127.0.0.1:9/s/1")!
    private let local2 = URL(string: "http://127.0.0.1:9/s/2")!

    private final class Counter: @unchecked Sendable { var value = 0 }

    private func model(_ proxy: FakeStreamProxy, _ engine: FakeVideoPlayerEngine,
                       unrestricts: Counter = Counter()) -> PlayerModel {
        PlayerModel(request: Fixture.request(), engine: engine,
                    unrestrict: { _ in unrestricts.value += 1; return URL(string: "https://cdn/x.mkv")! },
                    recordProgress: { _, _, _, _, _ in }, subtitles: nil, streamProxy: proxy)
    }

    /// Fire-and-forget calls to the proxy land on its actor a moment later: poll the condition.
    private func eventually(_ condition: () async -> Bool) async {
        for _ in 0..<100 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func libvlcIsHandedTheCachesURLNotRDs() async {
        let proxy = FakeStreamProxy(), engine = FakeVideoPlayerEngine()
        let m = model(proxy, engine)
        m.start(); await m.waitForIdleForTesting()
        #expect(engine.loadedURL == local1)
        let opened = await proxy.opened
        #expect(opened.first?.upstream == URL(string: "https://cdn/x.mkv"))
        #expect(opened.first?.fileKey == WatchKey.source(m.currentSource))
    }

    @Test func aRetryClosesTheOldStreamAndOpensANewOne() async {
        let proxy = FakeStreamProxy(), engine = FakeVideoPlayerEngine()
        let m = model(proxy, engine)
        m.start(); await m.waitForIdleForTesting()
        m.retry(); await m.waitForIdleForTesting()
        await eventually { await proxy.closed == [local1] }
        #expect(await proxy.closed == [local1])
        #expect(engine.loadedURL == local2)
    }

    @Test func theFirstFrameMarksPlaybackStartedOnce() async {
        let proxy = FakeStreamProxy(), engine = FakeVideoPlayerEngine()
        let m = model(proxy, engine)
        m.start(); await m.waitForIdleForTesting()
        engine.emit(.state(.playing))
        engine.emit(.time(.init(position: 1, duration: 100)))
        engine.emit(.time(.init(position: 2, duration: 100)))
        engine.emit(.time(.init(position: 3, duration: 100)))
        await m.waitForIdleForTesting()
        await eventually { await !proxy.marked.isEmpty }
        #expect(await proxy.marked == [local1])
    }

    @Test func teardownClosesTheStream() async {
        let proxy = FakeStreamProxy(), engine = FakeVideoPlayerEngine()
        let m = model(proxy, engine)
        m.start(); await m.waitForIdleForTesting()
        await m.teardown()
        #expect(await proxy.closed == [local1])
    }

    /// Found in review: a teardown that lands while the cache is still opening finds no handle to
    /// close, and the handle arrives after it — that session stayed open until sign-out.
    @Test func aStreamStillOpeningAtTeardownIsClosed() async {
        let proxy = FakeStreamProxy(), engine = FakeVideoPlayerEngine()
        let release = await proxy.holdOpens()
        let m = model(proxy, engine)
        m.start()
        await eventually { await !proxy.opened.isEmpty }           // the open is in flight
        await m.teardown()
        release.finish()
        await eventually { await proxy.closed == [local1] }
        #expect(await proxy.closed == [local1])
        #expect(engine.loadedURL == nil)                           // and nothing played it
    }

    /// Found in review: closing the stream writes up to 56 MiB of resume region to flash, and the
    /// final progress write waited behind it — racing the Detail page's reload of "Resume · …".
    @Test func teardownRecordsProgressBeforeTheCacheWritesToDisk() async {
        let proxy = FakeStreamProxy(), engine = FakeVideoPlayerEngine(), records = Counter()
        let m = PlayerModel(request: Fixture.request(), engine: engine,
                            unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                            recordProgress: { _, _, _, _, _ in records.value += 1 },
                            subtitles: nil, streamProxy: proxy)
        m.start(); await m.waitForIdleForTesting()
        let before = records.value
        let release = await proxy.holdCloses()
        let teardown = Task { await m.teardown() }
        await eventually { await !proxy.closed.isEmpty }            // the close is under way
        await eventually { records.value > before }
        #expect(records.value > before)                            // recorded while it writes
        release.finish()
        await teardown.value
    }

    /// Found in review: with the file's index on disk, the first frames play before RD is asked.
    /// When RD then refuses, libvlc sees only a closed connection — an EOF — and the film "ended":
    /// dismissed, or the next episode started, with no Retry. The cache knows it was a refusal.
    @Test func anEndTheCacheSaysRDRefusedIsAFailureNotAnEnd() async {
        let proxy = FakeStreamProxy(), engine = FakeVideoPlayerEngine()
        let m = model(proxy, engine)
        m.start(); await m.waitForIdleForTesting()
        engine.emit(.state(.playing))
        engine.emit(.time(.init(position: 40, duration: 6000))); await m.waitForIdleForTesting()
        await proxy.failWith(.upstreamStatus(404))
        engine.emit(.state(.ended)); await m.waitForIdleForTesting()
        guard case .failed = m.phase else {
            Issue.record("expected a failure with Retry, got \(m.phase)")
            return
        }
        #expect(m.shouldDismiss == false)
    }

    @Test func anEndWithoutARefusalIsStillAnEnd() async {
        let proxy = FakeStreamProxy(), engine = FakeVideoPlayerEngine()
        let m = model(proxy, engine)
        m.start(); await m.waitForIdleForTesting()
        engine.emit(.state(.playing))
        engine.emit(.time(.init(position: 5990, duration: 6000))); await m.waitForIdleForTesting()
        engine.emit(.state(.ended)); await m.waitForIdleForTesting()
        #expect(m.phase == .ended)
        #expect(m.shouldDismiss == true)
    }

    @Test func theCacheCanAskForAFreshLink() async throws {
        let proxy = FakeStreamProxy(), engine = FakeVideoPlayerEngine(), count = Counter()
        let m = model(proxy, engine, unrestricts: count)
        m.start(); await m.waitForIdleForTesting()
        #expect(try await proxy.callRefresh() == URL(string: "https://cdn/x.mkv"))
        #expect(count.value == 2)                      // the load, then the refresh
    }

    @Test func withoutACacheRDsLinkIsPlayedDirectly() async {
        let engine = FakeVideoPlayerEngine()
        let m = PlayerModel(request: Fixture.request(), engine: engine,
                            unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                            recordProgress: { _, _, _, _, _ in }, subtitles: nil)
        m.start(); await m.waitForIdleForTesting()
        #expect(engine.loadedURL == URL(string: "https://cdn/x.mkv"))
    }
}
