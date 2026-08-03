import Testing
import Foundation
import SwiftData
@testable import DebridCore

extension SwiftDataSuite {
    @Suite struct LocalWatchStoreTests {
        private func store() throws -> LocalWatchStore {
            let c = try ModelContainer(for: WatchProgress.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            return LocalWatchStore(modelContainer: c)
        }

        @Test func writingThenReadingRoundTrips() async throws {
            let s = try store()
            try await s.write(contentKey: "movie:tmdb:7", sourceKey: "T1#3",
                              positionSeconds: 120, durationSeconds: 600,
                              finished: false, profileID: "p1",
                              at: Date(timeIntervalSince1970: 10))
            let state = try await s.state(forContentKey: "movie:tmdb:7", profileID: "p1")
            #expect(state?.positionSeconds == 120)
            #expect(state?.durationSeconds == 600)
            #expect(state?.sourceKey == "T1#3")
            #expect(state?.finished == false)
        }

        @Test func unknownKeyReadsAsNil() async throws {
            #expect(try await store().state(forContentKey: "movie:tmdb:7", profileID: "p1") == nil)
        }

        /// Profiles are isolated: one viewer's progress is invisible to another.
        @Test func profilesAreIndependent() async throws {
            let s = try store()
            try await s.write(contentKey: "movie:tmdb:7", sourceKey: "T1#3",
                              positionSeconds: 120, durationSeconds: 600,
                              finished: false, profileID: "p1",
                              at: Date(timeIntervalSince1970: 10))
            #expect(try await s.state(forContentKey: "movie:tmdb:7", profileID: "p2") == nil)
        }

        @Test func batchedReadReturnsOnlyKnownKeys() async throws {
            let s = try store()
            try await s.write(contentKey: "show:tmdb:1:s1e1", sourceKey: "T1#1",
                              positionSeconds: 60, durationSeconds: 600, finished: false,
                              profileID: "p1", at: Date(timeIntervalSince1970: 10))
            try await s.write(contentKey: "show:tmdb:1:s1e2", sourceKey: "T1#2",
                              positionSeconds: 30, durationSeconds: 600, finished: true,
                              profileID: "p1", at: Date(timeIntervalSince1970: 20))

            let got = try await s.states(forContentKeys: ["show:tmdb:1:s1e1", "show:tmdb:1:s1e2",
                                                          "show:tmdb:1:s1e3"], profileID: "p1")
            #expect(got.count == 2)
            #expect(got["show:tmdb:1:s1e1"]?.positionSeconds == 60)
            #expect(got["show:tmdb:1:s1e2"]?.finished == true)
            #expect(got["show:tmdb:1:s1e3"] == nil)
        }

        @Test func batchedReadIsProfileScoped() async throws {
            let s = try store()
            try await s.write(contentKey: "show:tmdb:1:s1e1", sourceKey: "T1#1",
                              positionSeconds: 60, durationSeconds: 600, finished: false,
                              profileID: "p1", at: Date(timeIntervalSince1970: 10))
            #expect(try await s.states(forContentKeys: ["show:tmdb:1:s1e1"], profileID: "p2").isEmpty)
        }

        /// CloudKit merges two devices' rows for one title. The newest wins, and the next write
        /// collapses the losers rather than letting them accumulate forever.
        @Test func duplicateRowsResolveToNewestAndCollapse() async throws {
            let c = try ModelContainer(for: WatchProgress.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let ctx = ModelContext(c)
            ctx.insert(WatchProgress(contentKey: "movie:tmdb:7", profileID: "p1", sourceKey: "OLD",
                                     positionSeconds: 10, durationSeconds: 600,
                                     updatedAt: Date(timeIntervalSince1970: 10)))
            ctx.insert(WatchProgress(contentKey: "movie:tmdb:7", profileID: "p1", sourceKey: "NEW",
                                     positionSeconds: 500, durationSeconds: 600,
                                     updatedAt: Date(timeIntervalSince1970: 99)))
            try ctx.save()

            let s = LocalWatchStore(modelContainer: c)
            #expect(try await s.count() == 2)
            // Read: the newer row wins.
            #expect(try await s.state(forContentKey: "movie:tmdb:7", profileID: "p1")?.sourceKey == "NEW")
            // Write: the duplicates collapse to one.
            try await s.write(contentKey: "movie:tmdb:7", sourceKey: "T9#1", positionSeconds: 520,
                              durationSeconds: 600, finished: false, profileID: "p1",
                              at: Date(timeIntervalSince1970: 120))
            #expect(try await s.count() == 1)
            #expect(try await s.state(forContentKey: "movie:tmdb:7", profileID: "p1")?.sourceKey == "T9#1")
        }

        /// Collapsing keeps the surviving row's history — a merge must not reset the play count.
        @Test func collapsingPreservesPlayCount() async throws {
            let c = try ModelContainer(for: WatchProgress.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let ctx = ModelContext(c)
            ctx.insert(WatchProgress(contentKey: "movie:tmdb:7", profileID: "p1", sourceKey: "NEW",
                                     finished: true, plays: 3,
                                     updatedAt: Date(timeIntervalSince1970: 99)))
            ctx.insert(WatchProgress(contentKey: "movie:tmdb:7", profileID: "p1", sourceKey: "OLD",
                                     finished: true, plays: 1,
                                     updatedAt: Date(timeIntervalSince1970: 10)))
            try ctx.save()

            let s = LocalWatchStore(modelContainer: c)
            try await s.write(contentKey: "movie:tmdb:7", sourceKey: "T9#1", positionSeconds: 5,
                              durationSeconds: 600, finished: false, profileID: "p1",
                              at: Date(timeIntervalSince1970: 120))
            #expect(try await s.rollup(forContentKey: "movie:tmdb:7", profileID: "p1")?.plays == 3)
        }

        @Test func ratingRoundTripsAndClears() async throws {
            let s = try store()
            try await s.setRating(9, contentKey: "movie:tmdb:7", profileID: "p1",
                                  at: Date(timeIntervalSince1970: 10))
            #expect(try await s.rating(forContentKey: "movie:tmdb:7", profileID: "p1") == 9)
            try await s.setRating(nil, contentKey: "movie:tmdb:7", profileID: "p1",
                                  at: Date(timeIntervalSince1970: 20))
            #expect(try await s.rating(forContentKey: "movie:tmdb:7", profileID: "p1") == nil)
        }

        /// Rating a title you have never played creates the row — you can rate before you finish.
        @Test func ratingAnUnwatchedTitleCreatesTheRow() async throws {
            let s = try store()
            try await s.setRating(7, contentKey: "movie:tmdb:7", profileID: "p1",
                                  at: Date(timeIntervalSince1970: 10))
            #expect(try await s.count() == 1)
            #expect(try await s.state(forContentKey: "movie:tmdb:7", profileID: "p1")?.finished == false)
        }

        /// A rating must survive later position writes — separate facts about the same row.
        @Test func ratingSurvivesAPositionWrite() async throws {
            let s = try store()
            try await s.setRating(8, contentKey: "movie:tmdb:7", profileID: "p1",
                                  at: Date(timeIntervalSince1970: 10))
            try await s.write(contentKey: "movie:tmdb:7", sourceKey: "T1#1", positionSeconds: 30,
                              durationSeconds: 600, finished: false, profileID: "p1",
                              at: Date(timeIntervalSince1970: 20))
            #expect(try await s.rating(forContentKey: "movie:tmdb:7", profileID: "p1") == 8)
        }
    }
}
