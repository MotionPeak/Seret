import Foundation
import Testing
@testable import DebridCore

@Suite struct FetchPlannerTests {
    private let mib: Int64 = 1 << 20
    private let planner = FetchPlanner(budget: StreamCacheBudget(ramBytes: 192 << 20,
                                                                 readAheadBytes: 96 << 20))

    private func decide(_ offset: Int64, cached: Bool = false, inIndex: Bool = false,
                        fetches: [FetchSnapshot] = [], lastRead: Int64? = nil,
                        cachedChunks: Set<Int> = []) -> ReadDecision {
        planner.decide(offset: offset, cached: cached, inIndex: inIndex, fetches: fetches,
                       lastRead: lastRead, isChunkCached: { cachedChunks.contains($0) })
    }

    @Test func cachedBytesAreServed() {
        #expect(decide(5 * mib, cached: true) == .serve)
    }

    @Test func theDiskIndexComesBeforeTheNetwork() {
        #expect(decide(5 * mib, inIndex: true) == .loadFromIndex)
    }

    @Test func aFetchAboutToReachTheReadIsWaitedFor() {
        // 3 MiB short of the read on a live connection: cheaper than a ~460ms reconnect.
        let fetches = [FetchSnapshot(id: 7, position: 10 * mib)]
        #expect(decide(13 * mib, fetches: fetches) == .wait(fetch: 7))
    }

    @Test func aFetchTooFarBehindOrAlreadyPastIsNotWaitedFor() {
        let behind = [FetchSnapshot(id: 1, position: 10 * mib)]
        #expect(decide(19 * mib, fetches: behind) != .wait(fetch: 1))   // 9 MiB short: reconnect
        let past = [FetchSnapshot(id: 2, position: 30 * mib)]
        #expect(decide(20 * mib, fetches: past) != .wait(fetch: 2))
    }

    @Test func aForwardMissFetchesFromItsChunkBoundary() {
        #expect(decide(40 * mib + 123, lastRead: 10 * mib)
            == .fetch(start: 40 * mib, lookBehind: nil, cancel: []))
    }

    @Test func aBackwardMissAlsoFetchesBehindIt() {
        #expect(decide(20 * mib + 5, lastRead: 40 * mib)
            == .fetch(start: 20 * mib, lookBehind: 12 * mib, cancel: []))
    }

    @Test func noLookBehindWhenItsStartIsAlreadyCachedOrBeforeTheFile() {
        #expect(decide(20 * mib, lastRead: 40 * mib, cachedChunks: [12])
            == .fetch(start: 20 * mib, lookBehind: nil, cancel: []))
        #expect(decide(3 * mib, lastRead: 40 * mib)
            == .fetch(start: 3 * mib, lookBehind: 0, cancel: []))
        #expect(decide(100, lastRead: 40 * mib)
            == .fetch(start: 0, lookBehind: nil, cancel: []))
    }

    @Test func atCapacityTheFetchesFarthestFromTheReadAreCancelled() {
        // id 2 sits 9 MiB behind the backward read — just outside the 8 MiB wait window.
        let fetches = [FetchSnapshot(id: 1, position: 100 * mib), FetchSnapshot(id: 2, position: 21 * mib)]
        // A forward miss needs one slot: the farthest (id 1) goes.
        #expect(decide(40 * mib, fetches: fetches, lastRead: 10 * mib)
            == .fetch(start: 40 * mib, lookBehind: nil, cancel: [1]))
        // A backward miss needs two: both go.
        #expect(decide(30 * mib, fetches: fetches, lastRead: 100 * mib)
            == .fetch(start: 30 * mib, lookBehind: 22 * mib, cancel: [1, 2]))
    }

    @Test func readAheadSuspendsAtTheCapAndResumesBelowHalf() {
        #expect(!planner.shouldSuspend(position: 95 * mib, lastReadEnd: 0))
        #expect(planner.shouldSuspend(position: 96 * mib, lastReadEnd: 0))
        #expect(!planner.shouldResume(position: 96 * mib, lastReadEnd: 48 * mib))
        #expect(planner.shouldResume(position: 96 * mib, lastReadEnd: 49 * mib))
    }

    /// The 108-second rewind on the iPad (The Shining, 2026-09-22): libvlc's MKV seeker stepped back
    /// one cluster at a time and re-read everything in between — 230 requests over 25 positions,
    /// each a new TLS connection. Replayed against the planner, with a fetch modelled as filling
    /// chunks until it reaches cached data (the playhead fetch stops after 8 chunks).
    @Test func theRecordedKeyframeWalkNeedsFewFetchesAndNoRefetch() {
        let size = Int64(1 << 20)
        let base: Int64 = 7_192_101_749            // where the walk began, as a file offset
        var cached = Set<Int>()
        var fetchStarts: [Int64] = []
        var refetched = false
        var lastRead: Int64?
        func fill(from start: Int64, limit: Int) {
            fetchStarts.append(start)
            var index = Int(start / size)
            var filled = 0
            if cached.contains(index) { refetched = true }
            while filled < limit, !cached.contains(index) {
                cached.insert(index)
                index += 1
                filled += 1
            }
        }
        for relative in Self.recordedWalk {
            let offset = base + relative
            switch decide(offset, cached: cached.contains(Int(offset / size)), lastRead: lastRead,
                          cachedChunks: cached) {
            case .serve:
                break
            case .fetch(let start, let lookBehind, _):
                fill(from: start, limit: 8)
                if let lookBehind { fill(from: lookBehind, limit: .max) }
            default:
                Issue.record("unexpected decision at \(relative)")
            }
            lastRead = offset
        }
        #expect(Self.recordedWalk.count == 230)
        #expect(Set(Self.recordedWalk).count == 25)
        #expect(fetchStarts.count <= 10)           // was 230 connections
        #expect(!refetched)                        // no chunk downloaded twice
    }

    /// Request offsets relative to the first, verbatim from the iPad's vlc.log (lines 58093–65428).
    static let recordedWalk: [Int64] = [
        0, -1661047, 0, -3266070, -1661047, 0, -4766861, -1661047,
        0, -6293661, -4766861, -3266070, -1661047, 0, -7795061, -4766861,
        -3266070, -1661047, 0, -9405194, -7795061, -6293661, -4766861, -3266070,
        -1661047, 0, -10913188, -7795061, -6293661, -4766861, -3266070, -1661047,
        0, -12465977, -9405194, -7795061, -6293661, -4766861, -3266070, -1661047,
        0, -13966951, -9405194, -7795061, -6293661, -4766861, -3266070, -1661047,
        0, -15548064, -13966951, -12465977, -9405194, -7795061, -6293661, -4766861,
        -3266070, -1661047, 0, -17111501, -13966951, -12465977, -9405194, -7795061,
        -6293661, -4766861, -3266070, -1661047, 0, -18695989, -15548064, -13966951,
        -12465977, -9405194, -7795061, -6293661, -4766861, -3266070, -1661047, 0,
        -20304601, -18695989, -15548064, -13966951, -12465977, -9405194, -7795061, -6293661,
        -4766861, -3266070, -1661047, 0, -21806477, -18695989, -15548064, -13966951,
        -12465977, -9405194, -7795061, -6293661, -4766861, -3266070, -1661047, 0,
        -23542936, -20304601, -18695989, -15548064, -13966951, -12465977, -9405194, -7795061,
        -6293661, -4766861, -3266070, -1661047, 0, -25052648, -23542936, -20304601,
        -18695989, -15548064, -13966951, -12465977, -9405194, -7795061, -6293661, -4766861,
        -3266070, -1661047, 0, -26565692, -23542936, -20304601, -18695989, -15548064,
        -13966951, -12465977, -9405194, -7795061, -6293661, -4766861, -3266070, -1661047,
        0, -28295919, -25052648, -23542936, -20304601, -18695989, -15548064, -13966951,
        -12465977, -9405194, -7795061, -6293661, -4766861, -3266070, -1661047, 0,
        -29819546, -28295919, -25052648, -23542936, -20304601, -18695989, -15548064, -13966951,
        -12465977, -9405194, -7795061, -6293661, -4766861, -3266070, -1661047, 0,
        -31320006, -28295919, -25052648, -23542936, -20304601, -18695989, -15548064, -13966951,
        -12465977, -9405194, -7795061, -6293661, -4766861, -3266070, -1661047, 0,
        -32897307, -29819546, -28295919, -25052648, -23542936, -20304601, -18695989, -15548064,
        -13966951, -12465977, -9405194, -7795061, -6293661, -4766861, -3266070, -1661047,
        0, -34477722, -32897307, -29819546, -28295919, -25052648, -23542936, -20304601,
        -18695989, -15548064, -13966951, -12465977, -9405194, -7795061, -6293661, -5251290,
        -6281369, -4766861, -3266070, -1661047, 0, -34477722,
    ]
}
