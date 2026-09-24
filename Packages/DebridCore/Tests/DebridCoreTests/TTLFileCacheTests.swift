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

    /// A cache that keeps a stale fallback forever grows with every title ever opened, and every
    /// write rewrites the whole file. Entries past `keepFor` go when the file is next written.
    @Test func entriesPastKeepForAreDroppedOnTheNextWrite() async {
        let dir = FileManager.default.temporaryDirectory.appending(path: "ttl-keep-\(UUID().uuidString)")
        let clock = MutableClock()
        let cache = TTLFileCache<String>(directory: dir, fileName: "c.json", ttl: 60,
                                         keepFor: 30 * 24 * 60 * 60, now: { clock.now })
        await cache.store("old", key: "a")
        clock.advance(31 * 24 * 60 * 60)
        #expect(await cache.stored("a") == "old")          // still there until something is written
        await cache.store("new", key: "b")
        #expect(await cache.stored("a") == nil)
        let reopened = TTLFileCache<String>(directory: dir, fileName: "c.json", ttl: 60, now: { clock.now })
        #expect(await reopened.stored("a") == nil)
        #expect(await reopened.stored("b") == "new")
    }

    @Test func updateReadsDecidesAndWritesInOneStep() async {
        let dir = FileManager.default.temporaryDirectory.appending(path: "ttl-update-\(UUID().uuidString)")
        let cache = TTLFileCache<Int>(directory: dir, fileName: "c.json", ttl: 60)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 { group.addTask { await cache.update("n") { ($0 ?? 0) + 1 } } }
        }
        #expect(await cache.stored("n") == 50)
        #expect(await cache.update("n") { _ in nil } == 50)        // nil leaves it as it is
    }
}

final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000_000)
    var now: Date { lock.lock(); defer { lock.unlock() }; return current }
    func advance(_ seconds: TimeInterval) { lock.lock(); current += seconds; lock.unlock() }
}
