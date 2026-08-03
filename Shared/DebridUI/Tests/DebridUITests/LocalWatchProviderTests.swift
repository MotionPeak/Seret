import Testing
import Foundation
import SwiftData
import DebridCore
@testable import DebridUI

extension SwiftDataSuite {
    @Suite struct LocalWatchProviderTests {
        private func provider(profile: String = "p1") throws -> LocalWatchProvider {
            let c = try ModelContainer(for: WatchProgress.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            return LocalWatchProvider(store: LocalWatchStore(modelContainer: c),
                                      profileID: { profile })
        }

        @Test func recordThenReadThroughTheSeam() async throws {
            let p = try provider()
            try await p.record(contentKey: "movie:tmdb:7", sourceKey: "T1#1",
                               positionSeconds: 120, durationSeconds: 600,
                               finished: false, profileID: "p1")
            let state = try await p.progress(forContentKey: "movie:tmdb:7", profileID: "p1")
            #expect(state?.positionSeconds == 120)
        }

        /// The 80% rule: Trakt owned this cutoff, so going local means owning it again. Matching
        /// Trakt's number keeps local and the mirror agreeing about what counts as watched.
        @Test func passingEightyPercentMarksItFinished() async throws {
            let p = try provider()
            try await p.record(contentKey: "movie:tmdb:7", sourceKey: "T1#1",
                               positionSeconds: 479, durationSeconds: 600,
                               finished: false, profileID: "p1")
            #expect(try await p.progress(forContentKey: "movie:tmdb:7", profileID: "p1")?.finished == false)

            try await p.record(contentKey: "movie:tmdb:7", sourceKey: "T1#1",
                               positionSeconds: 481, durationSeconds: 600,
                               finished: false, profileID: "p1")
            #expect(try await p.progress(forContentKey: "movie:tmdb:7", profileID: "p1")?.finished == true)
        }

        /// A manual Mark Watched arrives with position 0 and duration 0 — the fraction is undefined
        /// and must not be computed, or every manual mark would divide by zero. This is exactly
        /// what the seam's `setWatched` default funnels into, without needing to build a
        /// `MediaSource` (which requires a whole `ParsedRelease`) just to reach it.
        @Test func manualMarkWatchedCarriesNoPosition() async throws {
            let p = try provider()
            try await p.record(contentKey: "movie:tmdb:7", sourceKey: "T1#1",
                               positionSeconds: 0, durationSeconds: 0,
                               finished: true, profileID: "p1")
            let state = try await p.progress(forContentKey: "movie:tmdb:7", profileID: "p1")
            #expect(state?.finished == true)
            #expect(state?.positionSeconds == 0)
        }

        /// The mirror image: a zero duration must not be treated as "reached the end".
        @Test func zeroDurationNeverMarksFinishedOnItsOwn() async throws {
            let p = try provider()
            try await p.record(contentKey: "movie:tmdb:7", sourceKey: "T1#1",
                               positionSeconds: 0, durationSeconds: 0,
                               finished: false, profileID: "p1")
            #expect(try await p.progress(forContentKey: "movie:tmdb:7", profileID: "p1")?.finished == false)
        }

        @Test func summaryReportsPlaysAfterAFinish() async throws {
            let p = try provider()
            try await p.record(contentKey: "movie:tmdb:7", sourceKey: "T1#1",
                               positionSeconds: 600, durationSeconds: 600,
                               finished: true, profileID: "p1")
            #expect(await p.watchSummary(forContentKey: "movie:tmdb:7")?.plays == 1)
        }

        @Test func ratingRoundTripsThroughTheCapability() async throws {
            let p = try provider()
            await p.setRating(9, forContentKey: "movie:tmdb:7")
            #expect(await p.rating(forContentKey: "movie:tmdb:7") == 9)
        }

        @Test func resumeFractionIsPositionOverDuration() async throws {
            let p = try provider()
            try await p.record(contentKey: "movie:tmdb:7", sourceKey: "T1#1",
                               positionSeconds: 150, durationSeconds: 600,
                               finished: false, profileID: "p1")
            #expect(await p.resumeFraction(forContentKey: "movie:tmdb:7") == 0.25)
        }

        /// A finished title has no resume point — Play, not Resume.
        @Test func finishedTitlesHaveNoResumeFraction() async throws {
            let p = try provider()
            try await p.record(contentKey: "movie:tmdb:7", sourceKey: "T1#1",
                               positionSeconds: 600, durationSeconds: 600,
                               finished: true, profileID: "p1")
            #expect(await p.resumeFraction(forContentKey: "movie:tmdb:7") == nil)
        }

        @Test func recentlyWatchedComesBackNewestFirst() async throws {
            let p = try provider()
            try await p.record(contentKey: "movie:tmdb:1", sourceKey: "T1#1", positionSeconds: 10,
                               durationSeconds: 600, finished: false, profileID: "p1")
            try await p.record(contentKey: "movie:tmdb:2", sourceKey: "T2#1", positionSeconds: 20,
                               durationSeconds: 600, finished: false, profileID: "p1")
            let recent = try await p.recentlyWatched(limit: 10, profileID: "p1")
            #expect(recent.first?.contentKey == "movie:tmdb:2")
        }
    }
}
