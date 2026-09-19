import Testing
import Foundation
import SwiftData
import DebridCore
@testable import DebridUI

/// Records what reached the server, for the hold tests below.
private actor CapturingRelay: LetterboxdRelaying {
    private(set) var count = 0
    func send(_ write: LetterboxdWrite) async throws { count += 1 }
}

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

        /// The fallback cutoff, for callers with no player to tell them where the dialogue ends —
        /// a manual mark, the web server. `WatchThreshold` owns the number; this asserts the
        /// provider actually asks it rather than keeping a fraction of its own.
        @Test func passingTheWatchedThresholdMarksItFinished() async throws {
            let p = try provider()
            try await p.record(contentKey: "movie:tmdb:7", sourceKey: "T1#1",
                               positionSeconds: 551, durationSeconds: 600,
                               finished: false, profileID: "p1")
            #expect(try await p.progress(forContentKey: "movie:tmdb:7", profileID: "p1")?.finished == false)

            try await p.record(contentKey: "movie:tmdb:7", sourceKey: "T1#1",
                               positionSeconds: 553, durationSeconds: 600,
                               finished: false, profileID: "p1")
            #expect(try await p.progress(forContentKey: "movie:tmdb:7", profileID: "p1")?.finished == true)
        }

        /// A long-press on a Continue Watching tile is a manual mark, not a film reaching its
        /// credits — its position is nowhere near the end. The diary entry goes out at once.
        @Test func markingAPartlyWatchedTitleWatchedIsNotHeldForARating() async throws {
            let relay = CapturingRelay()
            let push = LetterboxdPushCoordinator(outbox: InMemoryLetterboxdOutbox(), relay: relay,
                                                 loggedElsewhere: { _ in false },
                                                 isEnabled: { true }, ratingHold: 60)
            let c = try ModelContainer(for: WatchProgress.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let p = LocalWatchProvider(store: LocalWatchStore(modelContainer: c),
                                       profileID: { "p1" }, push: push)
            // A third of the way in, as a rail tile would be.
            try await p.record(contentKey: "movie:tmdb:73", sourceKey: "T1#1",
                               positionSeconds: 2000, durationSeconds: 6000,
                               finished: false, profileID: "p1")

            await p.setWatched(true, contentKey: "movie:tmdb:73", sourceKey: "T1#1",
                               profileID: "p1")
            await push.waitForPendingSend()

            #expect(await relay.count == 1)
        }

        /// ...while a film that actually played to its credits IS held, so the viewer can rate it.
        @Test func aFilmPlayedToItsCreditsIsHeldForARating() async throws {
            let relay = CapturingRelay()
            let push = LetterboxdPushCoordinator(outbox: InMemoryLetterboxdOutbox(), relay: relay,
                                                 loggedElsewhere: { _ in false },
                                                 isEnabled: { true }, ratingHold: 60)
            let c = try ModelContainer(for: WatchProgress.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let p = LocalWatchProvider(store: LocalWatchStore(modelContainer: c),
                                       profileID: { "p1" }, push: push)

            try await p.record(contentKey: "movie:tmdb:73", sourceKey: "T1#1",
                               positionSeconds: 5700, durationSeconds: 6000,
                               finished: true, profileID: "p1")
            await push.waitForPendingSend()

            #expect(await relay.count == 0)
        }

        /// The regression this whole change exists to prevent: four fifths of the way in is not
        /// the end of a film, and filing a diary entry there logged Good Will Hunting twenty-five
        /// minutes before it finished.
        @Test func fourFifthsOfTheWayInIsNoLongerWatched() async throws {
            let p = try provider()
            try await p.record(contentKey: "movie:tmdb:7", sourceKey: "T1#1",
                               positionSeconds: 0.81 * 7560, durationSeconds: 7560,
                               finished: false, profileID: "p1")
            #expect(try await p.progress(forContentKey: "movie:tmdb:7", profileID: "p1")?.finished == false)
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

        /// The resume point is now read in SECONDS. It used to be a fraction, because Trakt stored
        /// a percentage; with Trakt gone the player asks for the position directly.
        @Test func theSavedPositionIsWhatPlaybackResumesFrom() async throws {
            let p = try provider()
            try await p.record(contentKey: "movie:tmdb:7", sourceKey: "T1#1",
                               positionSeconds: 150, durationSeconds: 600,
                               finished: false, profileID: "p1")
            let state = try await p.progress(forContentKey: "movie:tmdb:7", profileID: "p1")
            #expect(state?.positionSeconds == 150)
            #expect(state?.finished == false)
        }

        /// A finished title has no resume point — Play, not Resume.
        @Test func finishedTitlesAreMarkedSoThereIsNothingToResume() async throws {
            let p = try provider()
            try await p.record(contentKey: "movie:tmdb:7", sourceKey: "T1#1",
                               positionSeconds: 600, durationSeconds: 600,
                               finished: true, profileID: "p1")
            let state = try await p.progress(forContentKey: "movie:tmdb:7", profileID: "p1")
            #expect(state?.finished == true)
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
