import Foundation
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import DebridCore

/// Real-Debrid failing for a while — Wi-Fi dropping, RD busy — must cost the viewer a wait, never
/// the film. The policies here have the standard one's shape at a fraction of its pace.
extension StreamingNetworkTests {
    @Suite struct StreamSessionRecoveryTests {
        static let mib: Int64 = 1 << 20
        /// A cache miss far from the start, so nothing but a fetch from RD can answer it.
        static let at = 40 * mib
        static let quick = StreamRetryPolicy(firstDelay: .milliseconds(5), maxDelay: .milliseconds(40),
                                             budget: .seconds(5), wholeFileAnswers: 3)
        /// A first pause long enough that a read is certainly waiting in it.
        static let slow = StreamRetryPolicy(firstDelay: .seconds(30), maxDelay: .seconds(30),
                                            budget: .seconds(120), wholeFileAnswers: 3)
        let budget = StreamCacheBudget(ramBytes: 24 << 20, readAheadBytes: 8 << 20)

        init() { RangeFileURLProtocol.reset(.init(fileSize: 64 << 20)) }

        func makeSession(budget: StreamCacheBudget? = nil,
                         retry: StreamRetryPolicy = Self.quick) -> StreamSession {
            let budget = budget ?? self.budget
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("StreamSessionRecoveryTests-\(UUID().uuidString)")
            return StreamSession(
                id: UUID(), fileKey: "t#1", upstream: URL(string: "https://rd.test/f.mkv")!,
                refreshUpstream: { URL(string: "https://rd.test/f.mkv")! }, budget: budget,
                index: IndexStore(directory: dir, chunkSize: budget.chunkSize,
                                  perFileLimit: budget.indexBytesPerFile,
                                  totalLimit: budget.indexBytesTotal),
                makeConfiguration: { RangeFileURLProtocol.configuration }, retry: retry, log: { _ in })
        }

        /// Read `count` bytes from `offset` the way the server does: in a loop.
        func read(_ s: StreamSession, _ offset: Int64 = at, _ count: Int = 4096) async throws -> Data {
            var out = Data()
            while out.count < count {
                out.append(try await s.read(offset: offset + Int64(out.count), max: count - out.count))
            }
            return out
        }

        static func bytes(_ offset: Int64 = at, _ count: Int64 = 4096) -> Data {
            RangeFileURLProtocol.bytes(offset..<(offset + count))
        }

        /// Until the session reports a failure (polls; gives up after a second).
        func untilFailing(_ s: StreamSession) async throws {
            for _ in 0..<200 {
                if await s.upstreamFailure != nil { return }
                try await Task.sleep(for: .milliseconds(5))
            }
        }

        /// The owner's report. Wi-Fi drops for a few seconds mid-film and every fetch fails the
        /// instant it starts (-1009): the four starts a read had went by in milliseconds, the
        /// session latched "RD kept failing" for good, and once the read-ahead ran out the film
        /// died with "Real-Debrid stopped sending this file" — the network long since back.
        @Test func aNetworkDropIsWaitedOutNotLatched() async throws {
            RangeFileURLProtocol.reset(.init(
                fileSize: 64 << 20, faults: Array(repeating: .transport(.notConnectedToInternet), count: 6)))
            let s = makeSession()
            let clock = ContinuousClock()
            let started = clock.now
            #expect(try await read(s) == Self.bytes())
            #expect(RangeFileURLProtocol.requests.count == 7)
            // Asked again after growing pauses — 5, 10, 20, then 40ms — not in a burst.
            #expect(started.duration(to: clock.now) >= .milliseconds(155))
            #expect(await s.upstreamFailure == nil)
            await s.close()
        }

        /// RD busy (429), a server fault (5xx), a timeout (408): "not now", not "no". The first
        /// one used to be latched as the session's refusal.
        @Test func RDBusyOrFaultyIsAskedAgain() async throws {
            RangeFileURLProtocol.reset(.init(fileSize: 64 << 20, faults: [
                .status(503), .status(429), .status(500), .status(502), .status(504), .status(408)]))
            let s = makeSession()
            #expect(try await read(s) == Self.bytes())
            #expect(RangeFileURLProtocol.requests.count == 7)
            #expect(await s.upstreamFailure == nil)
            await s.close()
        }

        /// The same at open, before the size is known: the film still opens.
        @Test func theHeadRidesOutAFailingRDToo() async throws {
            RangeFileURLProtocol.reset(.init(fileSize: 64 << 20, faults: [
                .status(503), .transport(.timedOut), .status(429)]))
            let s = makeSession()
            #expect(try await s.head().total == 64 << 20)
            #expect(try await read(s, 0) == Self.bytes(0))
            #expect(RangeFileURLProtocol.requests.count == 4)
            #expect(await s.upstreamFailure == nil)
            await s.close()
        }

        /// RD down for longer than a read will wait: that read gives up and the session says why —
        /// the player asks when libvlc reports the end. But nothing is latched: the next read,
        /// once the network is back, plays on.
        @Test func aReadThatOutwaitsItsBudgetFailsAloneAndTheNextOneRecovers() async throws {
            var short = Self.quick
            short.budget = .milliseconds(300)
            RangeFileURLProtocol.reset(.init(
                fileSize: 64 << 20, faults: Array(repeating: .transport(.notConnectedToInternet), count: 10_000)))
            let s = makeSession(retry: short)
            let error = await #expect(throws: StreamError.self) { try await self.read(s) }
            guard case .transport = error else {
                Issue.record("a transport failure, not \(String(describing: error))")
                return
            }
            #expect(await s.upstreamFailure == error)

            RangeFileURLProtocol.reset(.init(fileSize: 64 << 20))           // the network is back
            #expect(try await read(s) == Self.bytes())
            #expect(await s.upstreamFailure == nil)
            await s.close()
        }

        /// A whole file answered to a range is not the bytes that were asked for — but it may be
        /// one bad server, so RD is asked again, and the next one answers properly.
        @Test func aWholeFileAnsweredToARangeIsAskedAgain() async throws {
            RangeFileURLProtocol.reset(.init(fileSize: 64 << 20, faults: [.wholeFile, .wholeFile]))
            let s = makeSession()
            #expect(try await read(s) == Self.bytes())
            #expect(RangeFileURLProtocol.requests.map(\.start) == [Self.at, Self.at, Self.at])
            #expect(await s.upstreamFailure == nil)
            await s.close()
        }

        /// …but RD ignoring the range every time will not pass: the session stops asking, for
        /// good, and says why.
        @Test func aRangeRDKeepsIgnoringIsRefusedForGood() async throws {
            RangeFileURLProtocol.reset(.init(fileSize: 64 << 20,
                                             faults: Array(repeating: .wholeFile, count: 100)))
            let s = makeSession()
            let error = await #expect(throws: StreamError.self) { try await self.read(s) }
            #expect(RangeFileURLProtocol.requests.count == Self.quick.wholeFileAnswers)
            #expect(await s.upstreamFailure == error)
            await #expect(throws: StreamError.self) { try await self.read(s, 20 * Self.mib) }
            #expect(RangeFileURLProtocol.requests.count == Self.quick.wholeFileAnswers)   // not asked again
            await s.close()
        }

        /// "No" stays no. A refusal no link refresh can fix (451: the file is blocked) fails at
        /// once and for good — asking again for a minute would not change the answer.
        @Test func aRefusalTheRefreshCannotFixIsNotRetried() async throws {
            RangeFileURLProtocol.reset(.init(fileSize: 64 << 20, statusByPath: ["/f.mkv": 451]))
            let s = makeSession(retry: .standard)
            await #expect(throws: StreamError.upstreamStatus(451)) { try await s.head() }
            #expect(RangeFileURLProtocol.requests.count == 1)
            #expect(await s.upstreamFailure == .upstreamStatus(451))
            await s.close()
        }

        /// Cancelled by another reader's planning is no failure of RD's. Two readers needing more
        /// fetches than the budget allows cancel each other's; each restart used to count toward
        /// the four starts a read had, and the read then latched "RD kept failing". Here RD takes
        /// 20ms to answer, so no fetch answers before the other reader cancels it.
        @Test func fetchesCancelledByAnotherReaderNeverFailARead() async throws {
            var oneFetch = budget
            oneFetch.maxFetches = 1
            var patient = Self.quick
            patient.maxDelay = .milliseconds(160)
            RangeFileURLProtocol.reset(.init(fileSize: 64 << 20, delayByStart: [0: 0.02, Self.at: 0.02]))
            let s = makeSession(budget: oneFetch, retry: patient)
            async let near = read(s, 0)
            async let far = read(s)
            #expect(try await near == Self.bytes(0))
            #expect(try await far == Self.bytes())
            #expect(await s.upstreamFailure == nil)
            await s.close()
        }

        /// While RD is failing, the session says so — before any read has given up. libvlc can
        /// report the end on its own, and the player must not take an outage for the film's end
        /// (it would record it finished and move on). Closing then ends the waiting read at once.
        @Test func closingEndsAReadWaitingOutABackoffAtOnce() async throws {
            RangeFileURLProtocol.reset(.init(fileSize: 64 << 20,
                                             faults: [.transport(.notConnectedToInternet)]))
            let s = makeSession(retry: Self.slow)
            let reader = Task { try await self.read(s) }
            try await untilFailing(s)
            guard case .transport = await s.upstreamFailure else {
                Issue.record("the failure RD is in is reported")
                reader.cancel()
                return
            }
            let clock = ContinuousClock()
            let closing = clock.now
            await s.close()
            await #expect(throws: StreamError.closed) { try await reader.value }
            #expect(closing.duration(to: clock.now) < .seconds(5))
            #expect(RangeFileURLProtocol.requests.count == 1)                 // nothing more asked
        }

        /// libvlc hanging up (the connection's task is cancelled) ends a read waiting out a backoff
        /// at once, too.
        @Test func aReadCancelledInABackoffStopsAtOnce() async throws {
            RangeFileURLProtocol.reset(.init(fileSize: 64 << 20,
                                             faults: [.transport(.notConnectedToInternet)]))
            let s = makeSession(retry: Self.slow)
            let reader = Task { try await self.read(s) }
            try await untilFailing(s)
            #expect(await s.upstreamFailure != nil)
            let clock = ContinuousClock()
            let cancelling = clock.now
            reader.cancel()
            await #expect(throws: CancellationError.self) { try await reader.value }
            #expect(cancelling.duration(to: clock.now) < .seconds(5))
            #expect(RangeFileURLProtocol.requests.count == 1)
            await s.close()
        }
    }
}
