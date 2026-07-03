import Testing
import Foundation
@testable import DebridUI

/// Counts resolver calls and lets tests gate/fail them.
private actor ResolveLog {
    private(set) var calls: [String] = []
    var failNextCall = false
    struct Failed: Error {}

    func record(_ link: String) throws -> URL {
        calls.append(link)
        if failNextCall { failNextCall = false; throw Failed() }
        return URL(string: "https://cdn/\(link.hashValue)/\(calls.count).mkv")!
    }
    func setFailNextCall() { failNextCall = true }
}

/// Mutable "now" for TTL tests. Single-task test usage only.
private final class TestClock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 0)
}

@Suite struct PlayableLinkCacheTests {
    private func makeCache(ttl: TimeInterval = 480, clock: TestClock = TestClock())
        -> (PlayableLinkCache, ResolveLog) {
        let log = ResolveLog()
        let cache = PlayableLinkCache(ttl: ttl, now: { clock.date },
                                      resolve: { link in try await log.record(link) })
        return (cache, log)
    }

    /// Poll until the background prefetch settles (its watcher task runs detached).
    private func waitForCalls(_ log: ResolveLog, count: Int) async {
        for _ in 0..<200 {
            if await log.calls.count >= count { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)   // let finishPrefetch land
    }

    @Test func consumeAfterPrefetchResolvesExactlyOnce() async throws {
        let (cache, log) = makeCache()
        await cache.prefetch("rd://a")
        await waitForCalls(log, count: 1)
        let url = try await cache.consume("rd://a")
        #expect(url.absoluteString.hasPrefix("https://cdn/"))
        #expect(await log.calls == ["rd://a"])           // the prefetch was the only resolve
    }

    @Test func consumeIsOneShot() async throws {
        let (cache, log) = makeCache()
        await cache.prefetch("rd://a")
        await waitForCalls(log, count: 1)
        _ = try await cache.consume("rd://a")
        _ = try await cache.consume("rd://a")            // entry was consumed → resolves fresh
        #expect(await log.calls.count == 2)
    }

    @Test func consumeWithoutPrefetchResolvesDirectly() async throws {
        let (cache, log) = makeCache()
        _ = try await cache.consume("rd://a")
        #expect(await log.calls == ["rd://a"])
    }

    @Test func duplicatePrefetchIsANoOp() async throws {
        let (cache, log) = makeCache()
        await cache.prefetch("rd://a")
        await cache.prefetch("rd://a")
        await waitForCalls(log, count: 1)
        await cache.prefetch("rd://a")                    // fresh entry exists → still a no-op
        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(await log.calls.count == 1)
    }

    @Test func expiredEntryReResolves() async throws {
        let clock = TestClock()
        let (cache, log) = makeCache(ttl: 480, clock: clock)
        await cache.prefetch("rd://a")
        await waitForCalls(log, count: 1)
        clock.date = Date(timeIntervalSince1970: 481)     // past the TTL
        _ = try await cache.consume("rd://a")
        #expect(await log.calls.count == 2)               // stale entry dropped → fresh resolve
    }

    @Test func consumeAwaitsAnInFlightPrefetchWithoutASecondResolve() async throws {
        let log = ResolveLog()
        let gate = AsyncStream<Void>.makeStream()
        let cache = PlayableLinkCache(resolve: { link in
            var iterator = gate.stream.makeAsyncIterator()
            _ = await iterator.next()                     // hold until the test opens the gate
            return try await log.record(link)
        })
        await cache.prefetch("rd://a")
        async let consumed = cache.consume("rd://a")      // arrives while the prefetch is in flight
        try? await Task.sleep(nanoseconds: 30_000_000)
        gate.continuation.yield()
        gate.continuation.finish()
        let url = try await consumed
        #expect(url.absoluteString.hasPrefix("https://cdn/"))
        #expect(await log.calls == ["rd://a"])            // shared the single in-flight resolve
    }

    @Test func failedPrefetchRecoversWithAFreshResolveOnConsume() async throws {
        let (cache, log) = makeCache()
        await log.setFailNextCall()
        await cache.prefetch("rd://a")
        await waitForCalls(log, count: 1)                 // failed prefetch settles, drops silently
        let url = try await cache.consume("rd://a")       // fresh resolve succeeds
        #expect(url.absoluteString.hasPrefix("https://cdn/"))
        #expect(await log.calls.count == 2)
    }
}
