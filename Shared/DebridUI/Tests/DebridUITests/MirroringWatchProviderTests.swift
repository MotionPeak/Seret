import Testing
import Foundation
import DebridCore
@testable import DebridUI

@Suite struct MirroringWatchProviderTests {

    /// Records every call so a test can assert what reached which side. Declares BOTH composed
    /// protocols — satisfying every parent protocol does not imply conformance to a protocol that
    /// merely inherits them; Swift wants it said out loud.
    actor FakeSide: LocalWatchBacking, TraktWatchBacking {
        var reads = 0, writes = 0, deletes = 0, ratingWrites = 0
        var lastRecordedKey: String?
        var throwOnWrite = false
        private var states: [String: WatchState] = [:]
        private var ratings: [String: Int] = [:]

        func counts() -> (reads: Int, writes: Int, deletes: Int, ratingWrites: Int) {
            (reads, writes, deletes, ratingWrites)
        }
        func recordedKey() -> String? { lastRecordedKey }
        func setThrowOnWrite(_ v: Bool) { throwOnWrite = v }

        func progress(forContentKey key: String, profileID: String) async throws -> WatchState? {
            reads += 1; return states[key]
        }
        func progress(forContentKeys keys: [String],
                      profileID: String) async throws -> [String: WatchState] {
            reads += 1
            return states.filter { keys.contains($0.key) }
        }
        func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                    durationSeconds: Double, finished: Bool, profileID: String) async throws {
            if throwOnWrite { throw URLError(.timedOut) }
            writes += 1; lastRecordedKey = contentKey
            states[contentKey] = WatchState(contentKey: contentKey, sourceKey: sourceKey,
                                            positionSeconds: positionSeconds,
                                            durationSeconds: durationSeconds,
                                            finished: finished, updatedAt: Date())
        }
        func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] {
            reads += 1; return Array(states.values.prefix(limit))
        }
        func deleteProgress(forContentKeys keys: [String]) async throws { deletes += 1 }
        func watchSummary(forContentKey key: String) async -> WatchSummary? {
            WatchSummary(plays: 7, lastWatchedAt: nil)
        }
        func historySince(forContentKey key: String) async -> Date? { nil }
        func rating(forContentKey key: String) async -> Int? { ratings[key] }
        func setRating(_ value: Int?, forContentKey key: String) async {
            ratingWrites += 1; ratings[key] = value
        }
        func resumeFraction(forContentKey key: String) async -> Double? { 0.5 }
        func communityRating(imdbID: String, kind: MediaKind) async -> Double? { 8.3 }
    }

    private func make(mirror: Bool = true) -> (MirroringWatchProvider, FakeSide, FakeSide) {
        let local = FakeSide(), trakt = FakeSide()
        return (MirroringWatchProvider(local: local, trakt: trakt, shouldMirror: { mirror }),
                local, trakt)
    }

    /// Poll briefly for a detached mirror task to land, instead of a fixed sleep.
    private func eventually(_ condition: @Sendable () async -> Bool) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("condition never became true")
    }

    /// The whole point: a dead or slow Trakt can never affect a read.
    @Test func readsNeverTouchTrakt() async throws {
        let (m, local, trakt) = make()
        _ = try await m.progress(forContentKey: "movie:tmdb:7", profileID: "p1")
        _ = try await m.progress(forContentKeys: ["a", "b"], profileID: "p1")
        _ = try await m.recentlyWatched(limit: 5, profileID: "p1")
        #expect(await local.counts().reads == 3)
        #expect(await trakt.counts().reads == 0)
    }

    @Test func writesReachBothSides() async throws {
        let (m, local, trakt) = make()
        try await m.record(contentKey: "movie:tmdb:7", sourceKey: "T1#1", positionSeconds: 10,
                           durationSeconds: 600, finished: false, profileID: "p1")
        #expect(await local.counts().writes == 1)
        try await eventually { await trakt.counts().writes == 1 }
        #expect(await trakt.recordedKey() == "movie:tmdb:7")
    }

    /// A failing mirror must never surface — playback cannot be broken by Trakt being down.
    @Test func aFailingTraktMirrorDoesNotFailTheWrite() async throws {
        let (m, local, trakt) = make()
        await trakt.setThrowOnWrite(true)
        try await m.record(contentKey: "movie:tmdb:7", sourceKey: "T1#1", positionSeconds: 10,
                           durationSeconds: 600, finished: false, profileID: "p1")
        #expect(await local.counts().writes == 1)
    }

    /// A local failure is real and must propagate — that is the source of truth failing.
    @Test func aFailingLocalWriteDoesPropagate() async throws {
        let (m, local, _) = make()
        await local.setThrowOnWrite(true)
        await #expect(throws: (any Error).self) {
            try await m.record(contentKey: "movie:tmdb:7", sourceKey: "T1#1", positionSeconds: 10,
                               durationSeconds: 600, finished: false, profileID: "p1")
        }
    }

    /// Several profiles, one Trakt account: only the profile that linked Trakt mirrors, so a kid's
    /// viewing never lands in the owner's history.
    @Test func anUnlinkedProfileDoesNotMirror() async throws {
        let (m, local, trakt) = make(mirror: false)
        try await m.record(contentKey: "movie:tmdb:7", sourceKey: "T1#1", positionSeconds: 10,
                           durationSeconds: 600, finished: false, profileID: "kid")
        #expect(await local.counts().writes == 1)
        try await Task.sleep(for: .milliseconds(50))
        #expect(await trakt.counts().writes == 0)
    }

    @Test func summaryAndResumeComeFromLocal() async throws {
        let (m, _, trakt) = make()
        #expect(await m.watchSummary(forContentKey: "movie:tmdb:7")?.plays == 7)
        #expect(await m.resumeFraction(forContentKey: "movie:tmdb:7") == 0.5)
        #expect(await trakt.counts().reads == 0)
    }

    /// The community score is the one thing local cannot answer, so it routes to Trakt.
    @Test func communityRatingRoutesToTrakt() async throws {
        let (m, _, _) = make()
        #expect(await m.communityRating(imdbID: "tt123", kind: .movie) == 8.3)
    }

    @Test func communityRatingIsNilWithNoTrakt() async throws {
        let m = MirroringWatchProvider(local: FakeSide(), trakt: nil, shouldMirror: { true })
        #expect(await m.communityRating(imdbID: "tt123", kind: .movie) == nil)
    }

    /// Your own rating is local truth, mirrored outward.
    @Test func ratingWritesLocallyAndMirrors() async throws {
        let (m, local, trakt) = make()
        await m.setRating(9, forContentKey: "movie:tmdb:7")
        #expect(await m.rating(forContentKey: "movie:tmdb:7") == 9)
        #expect(await local.counts().ratingWrites == 1)
        try await eventually { await trakt.counts().ratingWrites == 1 }
    }
}
