import Testing
import Foundation
@testable import DebridCore

/// The TTL and stale-fallback rules these pin used to live inside `OMDbRatingsCache`. They are
/// tested here once, on the generic, so the two caches built on it cannot drift apart.
struct TTLFileCacheTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }

    private func cache(_ dir: URL, ttl: TimeInterval = 100, at t: TimeInterval = 1_000_000)
    -> TTLFileCache<String> {
        TTLFileCache(directory: dir, fileName: "test-cache.json", ttl: ttl,
                     now: { Date(timeIntervalSince1970: t) })
    }

    @Test func freshEntryIsReturned() async {
        let c = cache(tempDir())
        await c.store("hello", key: "k")
        #expect(await c.cached("k") == "hello")
    }

    /// Stored at T by one instance; a second whose clock is past the TTL reads it back off disk and
    /// sees it as expired. Also exercises persistence and the injected clock.
    @Test func expiredEntryIsNotReturnedByCached() async {
        let dir = tempDir()
        await cache(dir, at: 1_000_000).store("hello", key: "k")
        #expect(await cache(dir, at: 1_000_200).cached("k") == nil)
    }

    @Test func storedReturnsAnExpiredEntryAsTheStaleFallback() async {
        let dir = tempDir()
        await cache(dir, at: 1_000_000).store("hello", key: "k")
        #expect(await cache(dir, at: 1_000_200).stored("k") == "hello")
    }

    @Test func missingEntryIsNil() async {
        let c = cache(tempDir())
        #expect(await c.cached("nope") == nil)
        #expect(await c.stored("nope") == nil)
    }

    @Test func persistsAcrossInstances() async {
        let dir = tempDir()
        await cache(dir, ttl: 10_000).store("hello", key: "k")
        #expect(await cache(dir, ttl: 10_000).cached("k") == "hello")
    }

    /// Two caches in one directory must not read each other's entries.
    @Test func differentFileNamesAreDifferentCaches() async {
        let dir = tempDir()
        await cache(dir).store("hello", key: "k")
        let other = TTLFileCache<String>(directory: dir, fileName: "other.json", ttl: 100,
                                         now: { Date(timeIntervalSince1970: 1_000_000) })
        #expect(await other.cached("k") == nil)
    }

    /// An unreadable or absent file costs a re-fetch, never a crash or a thrown error.
    @Test func anUnreadableFileDegradesToEmpty() async throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appending(path: "test-cache.json"))
        #expect(await cache(dir).cached("k") == nil)
    }
}
