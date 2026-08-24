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

        /// Continue Watching: started but unfinished, newest first.
        @Test func recentReturnsUnfinishedNewestFirst() async throws {
            let s = try store()
            try await s.write(contentKey: "movie:tmdb:1", sourceKey: "T1#1", positionSeconds: 10,
                              durationSeconds: 600, finished: false, profileID: "p1",
                              at: Date(timeIntervalSince1970: 10))
            try await s.write(contentKey: "movie:tmdb:2", sourceKey: "T2#1", positionSeconds: 20,
                              durationSeconds: 600, finished: false, profileID: "p1",
                              at: Date(timeIntervalSince1970: 50))
            // finished — must not appear
            try await s.write(contentKey: "movie:tmdb:3", sourceKey: "T3#1", positionSeconds: 590,
                              durationSeconds: 600, finished: true, profileID: "p1",
                              at: Date(timeIntervalSince1970: 60))
            // never started — must not appear
            try await s.setRating(9, contentKey: "movie:tmdb:4", profileID: "p1",
                                  at: Date(timeIntervalSince1970: 70))

            let recent = try await s.recent(limit: 10, profileID: "p1")
            #expect(recent.map(\.contentKey) == ["movie:tmdb:2", "movie:tmdb:1"])
        }

        @Test func recentHonoursTheLimitAndTheProfile() async throws {
            let s = try store()
            for i in 1...5 {
                try await s.write(contentKey: "movie:tmdb:\(i)", sourceKey: "T\(i)#1",
                                  positionSeconds: 10, durationSeconds: 600, finished: false,
                                  profileID: "p1", at: Date(timeIntervalSince1970: TimeInterval(i)))
            }
            #expect(try await s.recent(limit: 2, profileID: "p1").count == 2)
            #expect(try await s.recent(limit: 10, profileID: "p2").isEmpty)
        }

        /// The title left the shared library — its progress goes for every profile.
        @Test func deleteRemovesKeysAcrossProfiles() async throws {
            let s = try store()
            try await s.write(contentKey: "movie:tmdb:1", sourceKey: "T1#1", positionSeconds: 10,
                              durationSeconds: 600, finished: false, profileID: "p1",
                              at: Date(timeIntervalSince1970: 10))
            try await s.write(contentKey: "movie:tmdb:1", sourceKey: "T1#1", positionSeconds: 10,
                              durationSeconds: 600, finished: false, profileID: "p2",
                              at: Date(timeIntervalSince1970: 10))
            try await s.write(contentKey: "movie:tmdb:2", sourceKey: "T2#1", positionSeconds: 10,
                              durationSeconds: 600, finished: false, profileID: "p1",
                              at: Date(timeIntervalSince1970: 10))

            try await s.delete(contentKeys: ["movie:tmdb:1"])
            #expect(try await s.count() == 1)
            #expect(try await s.state(forContentKey: "movie:tmdb:2", profileID: "p1") != nil)
        }

        /// CloudKit cannot enforce one row per (title, profile), so two devices each insert one.
        /// Writers collapse the extras — but `rating`, `plays` and `lastWatchedAt` accumulate
        /// INDEPENDENTLY of position, so discarding the loser wholesale throws away a score the
        /// user typed and undercounts their plays.
        @Test func collapsingDuplicateRowsKeepsTheRatingAndPlayCount() async throws {
            let s = try store()
            // Device A: watched it twice and rated it 9.
            try await s.seedRow(contentKey: "movie:tmdb:7", profileID: "p1", sourceKey: "T1#1",
                                positionSeconds: 0, durationSeconds: 6000, finished: true,
                                plays: 2, rating: 9,
                                updatedAt: Date(timeIntervalSince1970: 10),
                                lastWatchedAt: Date(timeIntervalSince1970: 10))
            // Device B, syncing later: a fresh row with no rating and no play history.
            try await s.seedRow(contentKey: "movie:tmdb:7", profileID: "p1", sourceKey: "T1#1",
                                positionSeconds: 300, durationSeconds: 6000, finished: false,
                                plays: 0, rating: nil,
                                updatedAt: Date(timeIntervalSince1970: 20),
                                lastWatchedAt: nil)

            // Any write collapses them. The newer row wins on position; the rating and plays must
            // survive from the older one rather than being deleted with it.
            try await s.write(contentKey: "movie:tmdb:7", sourceKey: "T1#1",
                              positionSeconds: 400, durationSeconds: 6000, finished: false,
                              profileID: "p1", at: Date(timeIntervalSince1970: 30))

            #expect(try await s.count() == 1)
            #expect(try await s.rating(forContentKey: "movie:tmdb:7", profileID: "p1") == 9)
            let rollup = try await s.rollup(forContentKey: "movie:tmdb:7", profileID: "p1")
            #expect(rollup?.plays == 2)
            #expect(rollup?.lastWatchedAt == Date(timeIntervalSince1970: 10))
            #expect(try await s.state(forContentKey: "movie:tmdb:7", profileID: "p1")?.positionSeconds == 400)
        }

        /// `setRating` collapses duplicates too, and the newest row can easily be the one with no
        /// position (a rating written on a device that never played the file). Deleting the other
        /// takes the resume point with it.
        @Test func ratingATitleDoesNotDiscardTheResumePointOnADuplicateRow() async throws {
            let s = try store()
            try await s.seedRow(contentKey: "movie:tmdb:7", profileID: "p1", sourceKey: "T1#1",
                                positionSeconds: 900, durationSeconds: 6000, finished: false,
                                plays: 1, rating: nil,
                                updatedAt: Date(timeIntervalSince1970: 10),
                                lastWatchedAt: nil)
            try await s.seedRow(contentKey: "movie:tmdb:7", profileID: "p1", sourceKey: "",
                                positionSeconds: 0, durationSeconds: 0, finished: false,
                                plays: 0, rating: nil,
                                updatedAt: Date(timeIntervalSince1970: 20),
                                lastWatchedAt: nil)

            try await s.setRating(8, contentKey: "movie:tmdb:7", profileID: "p1",
                                  at: Date(timeIntervalSince1970: 30))

            #expect(try await s.count() == 1)
            #expect(try await s.rating(forContentKey: "movie:tmdb:7", profileID: "p1") == 8)
            let state = try await s.state(forContentKey: "movie:tmdb:7", profileID: "p1")
            #expect(state?.positionSeconds == 900)
            #expect(state?.durationSeconds == 6000)
        }

        /// Adopting a row written before the profile resolved resolves a collision by deleting one
        /// side outright — so whichever side happened to be older loses its score and play count
        /// even though nothing else recorded them.
        @Test func adoptingUnprofiledProgressKeepsBothRowsRatingAndPlays() async throws {
            let s = try store()
            // Recorded before the profile resolved: the actual playback, and a play.
            try await s.seedRow(contentKey: "movie:tmdb:7", profileID: "", sourceKey: "T1#1",
                                positionSeconds: 1200, durationSeconds: 6000, finished: true,
                                plays: 1, rating: nil,
                                updatedAt: Date(timeIntervalSince1970: 30),
                                lastWatchedAt: Date(timeIntervalSince1970: 30))
            // Recorded after it resolved: the user's score, written earlier in wall-clock terms.
            try await s.seedRow(contentKey: "movie:tmdb:7", profileID: "p1", sourceKey: "",
                                positionSeconds: 0, durationSeconds: 0, finished: false,
                                plays: 0, rating: 10,
                                updatedAt: Date(timeIntervalSince1970: 20),
                                lastWatchedAt: nil)

            try await s.adoptUnprofiledProgress(into: "p1")

            #expect(try await s.count() == 1)
            #expect(try await s.rating(forContentKey: "movie:tmdb:7", profileID: "p1") == 10)
            let rollup = try await s.rollup(forContentKey: "movie:tmdb:7", profileID: "p1")
            #expect(rollup?.plays == 1)
            #expect(try await s.state(forContentKey: "movie:tmdb:7", profileID: "p1")?.positionSeconds == 1200)
        }
    }
}
