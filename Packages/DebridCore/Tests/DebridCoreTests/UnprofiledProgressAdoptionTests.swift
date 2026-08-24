import Testing
import Foundation
import SwiftData
@testable import DebridCore

/// Progress recorded before a profile was resolved must not be stranded.
///
/// The chain this pins, all four links verified in the code:
///
/// 1. `AppSession` sets `state = .signedIn` and only THEN kicks off `loadAndResolve()`, so there is
///    a window where `activeProfileID` is nil.
/// 2. `makePlayer` captures `activeProfileID ?? ""` once, at player creation — inside that window
///    it captures the empty string.
/// 3. `LocalWatchStore` filters on `$0.profileID == profileID`, strict equality, so a row written
///    under "" is invisible to every read under a real profile id.
/// 4. `ensureOwnerProfileAndMigrate` — despite the name — only ensures the Profile row exists. It
///    never adopts those watch rows.
///
/// The result is a title whose position was recorded but can never be read again: the page offers
/// "Play" instead of "Resume" and playback starts from zero, permanently, for exactly the titles
/// that were started inside that window. "Sometimes it doesn't show resume and starts from the
/// start."
extension SwiftDataSuite {
    @Suite struct UnprofiledProgressAdoptionTests {
        private func store() throws -> LocalWatchStore {
            let c = try ModelContainer(for: WatchProgress.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            return LocalWatchStore(modelContainer: c)
        }

        /// The defect itself: written unprofiled, unreadable once a profile exists.
        @Test func progressWrittenWithNoProfileIsInvisibleToTheOwner() async throws {
            let s = try store()
            try await s.write(contentKey: "movie:tmdb:7", sourceKey: "T1#3",
                              positionSeconds: 1200, durationSeconds: 7200,
                              finished: false, profileID: "",
                              at: Date(timeIntervalSince1970: 10))
            #expect(try await s.state(forContentKey: "movie:tmdb:7", profileID: "owner") == nil)
        }

        /// Adopting hands those rows to the owner, so the position is readable again.
        @Test func adoptingGivesTheOwnerTheUnprofiledProgress() async throws {
            let s = try store()
            try await s.write(contentKey: "movie:tmdb:7", sourceKey: "T1#3",
                              positionSeconds: 1200, durationSeconds: 7200,
                              finished: false, profileID: "",
                              at: Date(timeIntervalSince1970: 10))

            try await s.adoptUnprofiledProgress(into: "owner")

            let state = try await s.state(forContentKey: "movie:tmdb:7", profileID: "owner")
            #expect(state?.positionSeconds == 1200)
            #expect(state?.resumePosition == 1200)
        }

        /// Adoption must not touch another profile's rows.
        @Test func adoptingLeavesOtherProfilesAlone() async throws {
            let s = try store()
            try await s.write(contentKey: "movie:tmdb:9", sourceKey: "T2#1",
                              positionSeconds: 300, durationSeconds: 7200,
                              finished: false, profileID: "someone-else",
                              at: Date(timeIntervalSince1970: 10))

            try await s.adoptUnprofiledProgress(into: "owner")

            #expect(try await s.state(forContentKey: "movie:tmdb:9", profileID: "owner") == nil)
            #expect(try await s.state(forContentKey: "movie:tmdb:9", profileID: "someone-else") != nil)
        }

        /// The owner may already have a row for the same title — watched once before profiles
        /// resolved and once after. Keep the more recent one rather than creating a duplicate,
        /// which would then be ambiguous to every later read.
        @Test func aConflictKeepsTheNewerRow() async throws {
            let s = try store()
            try await s.write(contentKey: "movie:tmdb:7", sourceKey: "old", positionSeconds: 100,
                              durationSeconds: 7200, finished: false, profileID: "",
                              at: Date(timeIntervalSince1970: 10))
            try await s.write(contentKey: "movie:tmdb:7", sourceKey: "new", positionSeconds: 2000,
                              durationSeconds: 7200, finished: false, profileID: "owner",
                              at: Date(timeIntervalSince1970: 500))

            try await s.adoptUnprofiledProgress(into: "owner")

            let state = try await s.state(forContentKey: "movie:tmdb:7", profileID: "owner")
            #expect(state?.positionSeconds == 2000)
            #expect(state?.sourceKey == "new")
        }

        /// …and the other way round: the unprofiled row is the newer one.
        @Test func aConflictKeepsTheUnprofiledRowWhenItIsNewer() async throws {
            let s = try store()
            try await s.write(contentKey: "movie:tmdb:7", sourceKey: "old", positionSeconds: 100,
                              durationSeconds: 7200, finished: false, profileID: "owner",
                              at: Date(timeIntervalSince1970: 10))
            try await s.write(contentKey: "movie:tmdb:7", sourceKey: "new", positionSeconds: 2000,
                              durationSeconds: 7200, finished: false, profileID: "",
                              at: Date(timeIntervalSince1970: 500))

            try await s.adoptUnprofiledProgress(into: "owner")

            let state = try await s.state(forContentKey: "movie:tmdb:7", profileID: "owner")
            #expect(state?.positionSeconds == 2000)
        }

        /// Running twice must be a no-op the second time — it runs on every launch.
        @Test func adoptingIsIdempotent() async throws {
            let s = try store()
            try await s.write(contentKey: "movie:tmdb:7", sourceKey: "T1#3", positionSeconds: 1200,
                              durationSeconds: 7200, finished: false, profileID: "",
                              at: Date(timeIntervalSince1970: 10))
            try await s.adoptUnprofiledProgress(into: "owner")
            try await s.adoptUnprofiledProgress(into: "owner")
            #expect(try await s.state(forContentKey: "movie:tmdb:7", profileID: "owner")?
                .positionSeconds == 1200)
        }
    }
}
