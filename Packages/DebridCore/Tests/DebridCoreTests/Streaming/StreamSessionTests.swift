import Foundation
import Testing
@testable import DebridCore

extension StreamingNetworkTests {
    @Suite struct StreamSessionTests {
        static let mib: Int64 = 1 << 20
        let budget = StreamCacheBudget(ramBytes: 24 << 20, readAheadBytes: 8 << 20)

        init() { RangeFileURLProtocol.reset(.init(fileSize: 64 << 20)) }

        func makeSession(upstream: String = "https://rd.test/f.mkv",
                         index: IndexStore? = nil, fileKey: String = "t#1",
                         refresh: @escaping @Sendable () async throws -> URL = {
                             URL(string: "https://rd.test/fresh.mkv")!
                         }) -> StreamSession {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("StreamSessionTests-\(UUID().uuidString)")
            return StreamSession(
                id: UUID(), fileKey: fileKey, upstream: URL(string: upstream)!,
                refreshUpstream: refresh, budget: budget,
                index: index ?? IndexStore(directory: dir, chunkSize: budget.chunkSize,
                                           perFileLimit: budget.indexBytesPerFile,
                                           totalLimit: budget.indexBytesTotal),
                makeConfiguration: { RangeFileURLProtocol.configuration }, log: { _ in })
        }

        /// Read `count` bytes from `offset` the way the server does: in a loop.
        func read(_ s: StreamSession, _ offset: Int64, _ count: Int) async throws -> Data {
            var out = Data()
            while out.count < count {
                out.append(try await s.read(offset: offset + Int64(out.count), max: count - out.count))
            }
            return out
        }

        @Test func headLearnsTheSizeFromRD() async throws {
            let s = makeSession()
            let head = try await s.head()
            #expect(head.total == 64 << 20)
            #expect(head.contentType == "application/force-download")
            await s.close()
        }

        @Test func sequentialReadsAreExactAndUseOneConnection() async throws {
            let s = makeSession()
            _ = try await s.head()
            #expect(try await read(s, 0, 3 << 20) == RangeFileURLProtocol.bytes(0..<(3 << 20)))
            #expect(await s.upstreamRequestCount == 1)
            await s.close()
        }

        @Test func aRewindIsServedFromRAM() async throws {
            let s = makeSession()
            _ = try await read(s, 0, 3 << 20)
            let before = await s.upstreamRequestCount
            #expect(try await read(s, Self.mib, 1 << 20)
                == RangeFileURLProtocol.bytes(Self.mib..<(2 * Self.mib)))
            #expect(await s.upstreamRequestCount == before)          // no reconnect
            await s.close()
        }

        @Test func aFarJumpFetchesFromItsChunk() async throws {
            let s = makeSession()
            _ = try await read(s, 0, 1 << 20)
            let at = 40 * Self.mib + 123
            #expect(try await read(s, at, 4096) == RangeFileURLProtocol.bytes(at..<(at + 4096)))
            #expect(RangeFileURLProtocol.requests.map(\.start).contains(40 * Self.mib))
            await s.close()
        }

        @Test func aBackwardMissAlsoFetchesBehindIt() async throws {
            let s = makeSession()
            _ = try await read(s, 40 * Self.mib, 1 << 20)
            _ = try await read(s, 20 * Self.mib, 4096)
            let starts = RangeFileURLProtocol.requests.map(\.start)
            #expect(starts.contains(20 * Self.mib))
            #expect(starts.contains(12 * Self.mib))                  // 8 MiB look-behind
            await s.close()
        }

        @Test func readAheadSuspendsAtItsCap() async throws {
            let s = makeSession()
            _ = try await read(s, 0, 4096)
            for _ in 0..<200 {                                       // poll a condition, never a bare sleep
                if await s.suspendedFetchCount > 0 { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(await s.suspendedFetchCount == 1)
            await s.close()
        }

        /// libvlc opens a file with two connections at once — the header at the start, the keyframe
        /// index at the end. One global "last read" made each reader's fetch look far ahead of the
        /// OTHER reader, so it paused, was resumed by its own reader, and paused again on every
        /// piece: ~290 pause/resume pairs in one cold open, measured in the tvOS simulator.
        @Test func twoReadersDoNotThrashEachOthersFetches() async throws {
            let s = makeSession()
            _ = try await s.head()
            for k in 0..<16 {                                        // start of file, then near the end
                _ = try await read(s, Int64(k) * 4096, 4096)
                _ = try await read(s, 60 * Self.mib + Int64(k) * 65536, 65536)
            }
            #expect(await s.suspendCount <= 2)                        // each fetch pauses once, at its cap
            await s.close()
        }

        @Test func anExpiredLinkIsRefreshedOnce() async throws {
            RangeFileURLProtocol.reset(.init(fileSize: 64 << 20, statusByPath: ["/expired.mkv": 403]))
            let s = makeSession(upstream: "https://rd.test/expired.mkv")
            #expect(try await s.head().total == 64 << 20)
            #expect(RangeFileURLProtocol.requests.map(\.path) == ["/expired.mkv", "/fresh.mkv"])
            await s.close()
        }

        /// Found in review: the refresh is an RD unrestrict the viewer can outlast. Closing the
        /// player during it used to leave a fresh fetch nobody read or paused — the whole file,
        /// tens of GB, downloading in the background.
        @Test func aRefreshThatFinishesAfterCloseStartsNoFetch() async throws {
            RangeFileURLProtocol.reset(.init(fileSize: 64 << 20, statusByPath: ["/expired.mkv": 403]))
            let (entered, enter) = AsyncStream.makeStream(of: Void.self)
            let (gate, release) = AsyncStream.makeStream(of: Void.self)
            let s = makeSession(upstream: "https://rd.test/expired.mkv", refresh: {
                enter.yield()
                for await _ in gate { break }
                return URL(string: "https://rd.test/fresh.mkv")!
            })
            let reader = Task { try? await s.head() }
            for await _ in entered { break }                         // the refresh is in flight
            await s.close()
            release.yield()
            _ = await reader.value
            try await Task.sleep(for: .milliseconds(300))
            #expect(RangeFileURLProtocol.requests.map(\.path) == ["/expired.mkv"])
        }

        /// An expired link is refused on EVERY fetch, and fetches start in twos — a read and its
        /// look-behind, or two of libvlc's readers. The second refusal found the first one's
        /// refresh already begun, was denied a refresh of its own, and failed its read with 403
        /// for good: the film died at the end of its read-ahead, though the refresh succeeded.
        @Test func twoFetchesRefusedAtOnceBothWaitForTheOneRefresh() async throws {
            RangeFileURLProtocol.reset(.init(fileSize: 64 << 20, statusByPath: ["/expired.mkv": 403]))
            let refreshes = Calls()
            let (entered, enter) = AsyncStream.makeStream(of: Void.self)
            let (gate, release) = AsyncStream.makeStream(of: Void.self)
            let s = makeSession(upstream: "https://rd.test/expired.mkv", refresh: {
                refreshes.record()
                enter.yield()
                for await _ in gate { break }
                return URL(string: "https://rd.test/fresh.mkv")!
            })
            let far = 40 * Self.mib
            let nearRead = Task { try await self.read(s, 0, 4096) }
            let farRead = Task { try await self.read(s, far, 4096) }
            for await _ in entered { break }                         // the first refusal is refreshing…
            for _ in 0..<200 where RangeFileURLProtocol.requests.count < 2 {
                try await Task.sleep(for: .milliseconds(5))
            }
            #expect(RangeFileURLProtocol.requests.map(\.path) == ["/expired.mkv", "/expired.mkv"])
            // …and the second is refused meanwhile. Nothing to observe while it waits, so give a
            // refusal that would fail its read the time to do so before the refresh ends.
            try await Task.sleep(for: .milliseconds(200))
            release.yield()
            #expect(try await nearRead.value == RangeFileURLProtocol.bytes(0..<4096))
            #expect(try await farRead.value == RangeFileURLProtocol.bytes(far..<(far + 4096)))
            #expect(refreshes.count == 1)
            #expect(await s.upstreamFailure == nil)
            await s.close()
        }

        /// The same race the other way round: a fetch started on the old link is refused only
        /// after the refresh has finished. That link is already replaced, so the fetch moves to
        /// the fresh one — it is not the fresh link being refused too.
        @Test func aFetchOnTheOldLinkRefusedAfterTheRefreshMovesToTheFreshOne() async throws {
            let far = 40 * Self.mib
            RangeFileURLProtocol.reset(.init(fileSize: 64 << 20, statusByPath: ["/expired.mkv": 403],
                                             delayByStart: [far: 0.3]))   // its refusal comes late
            let (entered, enter) = AsyncStream.makeStream(of: Void.self)
            let (gate, release) = AsyncStream.makeStream(of: Void.self)
            let s = makeSession(upstream: "https://rd.test/expired.mkv", refresh: {
                enter.yield()
                for await _ in gate { break }
                return URL(string: "https://rd.test/fresh.mkv")!
            })
            let nearRead = Task { try await self.read(s, 0, 4096) }
            for await _ in entered { break }                         // refreshing after the first refusal…
            let farRead = Task { try await self.read(s, far, 4096) } // …as a fetch starts on the old link
            for _ in 0..<200 where RangeFileURLProtocol.requests.count < 2 {
                try await Task.sleep(for: .milliseconds(5))
            }
            #expect(RangeFileURLProtocol.requests.map(\.path) == ["/expired.mkv", "/expired.mkv"])
            release.yield()                                          // the refresh ends first
            #expect(try await nearRead.value == RangeFileURLProtocol.bytes(0..<4096))
            #expect(try await farRead.value == RangeFileURLProtocol.bytes(far..<(far + 4096)))
            #expect(await s.upstreamFailure == nil)
            await s.close()
        }

        @Test func aRefusalThatSurvivesTheRefreshReachesTheCaller() async {
            RangeFileURLProtocol.reset(.init(statusByPath: ["/gone.mkv": 404, "/fresh.mkv": 404]))
            let s = makeSession(upstream: "https://rd.test/gone.mkv")
            await #expect(throws: StreamError.upstreamStatus(404)) { try await s.head() }
            await s.close()
        }

        @Test func readingAtTheEndIsEndOfFile() async throws {
            let s = makeSession()
            _ = try await s.head()
            await #expect(throws: StreamError.endOfFile) { try await s.read(offset: 64 << 20, max: 10) }
            await s.close()
        }

        @Test func aConnectionThatEndsEarlyIsPickedUpByANewFetch() async throws {
            RangeFileURLProtocol.reset(.init(fileSize: 64 << 20, maxBytesPerRequest: 1 << 20))
            let s = makeSession()
            #expect(try await read(s, 0, 3 << 20) == RangeFileURLProtocol.bytes(0..<(3 << 20)))
            #expect(await s.upstreamRequestCount >= 3)
            await s.close()
        }

        /// Measured in the tvOS simulator (Goodfellas): a paused fetch that RD dropped left its chunk
        /// half filled. The next fetch started at the chunk's boundary, ran straight into those
        /// bytes, stopped as "already cached" — and the read started it again: 12 fetches from one
        /// offset, ~200ms apart. A new fetch must continue from the first byte the chunk lacks.
        @Test func aConnectionThatEndsMidChunkIsContinuedNotRestarted() async throws {
            RangeFileURLProtocol.reset(.init(fileSize: 64 << 20, maxBytesPerRequest: 1_572_864)) // 1.5 MiB
            let s = makeSession()
            #expect(try await read(s, 0, 3 << 20) == RangeFileURLProtocol.bytes(0..<(3 << 20)))
            let starts = RangeFileURLProtocol.requests.map(\.start)
            #expect(starts == [0, 1_572_864])                        // continued at the missing byte
            await s.close()
        }

        @Test func aClosedSessionRefusesReads() async throws {
            let s = makeSession()
            _ = try await s.head()
            await s.close()
            await #expect(throws: StreamError.closed) { try await s.read(offset: 0, max: 10) }
        }
    }
}

/// How many times a closure ran, from any thread.
private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func record() { lock.lock(); n += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return n }
}
