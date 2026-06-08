import Testing
import Foundation
import SwiftData
@testable import DebridCore

// Nested under `SwiftDataSuite` (the serialized parent) — per-suite `.serialized` is NOT enough
// once there are two SwiftData suites; they would run concurrently with each other.
extension SwiftDataSuite {
    @Suite struct PlaybackCoordinatorTests {
        private func store() throws -> WatchProgressStore {
            let container = try ModelContainer(
                for: WatchProgress.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            return WatchProgressStore(modelContainer: container)
        }

        @Test func resumeIsZeroWhenNoProgress() async throws {
            let coord = PlaybackCoordinator(store: try store(), profileID: "p1")
            #expect(await coord.resumePosition(contentKey: "movie:tmdb:1") == 0)
        }

        @Test func recordThenResumeReturnsSavedPosition() async throws {
            let s = try store()
            let coord = PlaybackCoordinator(store: s, profileID: "p1")
            await coord.record(contentKey: "movie:tmdb:1", sourceKey: "T#0", position: 73, duration: 100)
            #expect(await coord.resumePosition(contentKey: "movie:tmdb:1") == 73)
            let saved = try await s.progress(forContentKey: "movie:tmdb:1", profileID: "p1")
            #expect(saved?.positionSeconds == 73)
            #expect(saved?.finished == false)
        }

        @Test func recordMarksFinishedPastThreshold() async throws {
            let s = try store()
            let coord = PlaybackCoordinator(store: s, profileID: "p1")
            await coord.record(contentKey: "k", sourceKey: "T#0", position: 96, duration: 100)   // 96% ≥ 95%
            #expect(try await s.progress(forContentKey: "k", profileID: "p1")?.finished == true)
        }

        @Test func recordBelowThresholdIsNotFinished() async throws {
            let s = try store()
            let coord = PlaybackCoordinator(store: s, profileID: "p1")
            await coord.record(contentKey: "k", sourceKey: "T#0", position: 50, duration: 100)
            #expect(try await s.progress(forContentKey: "k", profileID: "p1")?.finished == false)
        }

        @Test func resumeIsZeroWhenFinished() async throws {
            let s = try store()
            let coord = PlaybackCoordinator(store: s, profileID: "p1")
            await coord.record(contentKey: "k", sourceKey: "T#0", position: 99, duration: 100)   // finished
            #expect(await coord.resumePosition(contentKey: "k") == 0)
        }

        @Test func coordinatorRecordsAndResumesUnderItsProfile() async throws {
            let s = try store()
            let p1 = PlaybackCoordinator(store: s, profileID: "p1")
            let p2 = PlaybackCoordinator(store: s, profileID: "p2")
            await p1.record(contentKey: "m", sourceKey: "x", position: 30, duration: 100)
            #expect(await p1.resumePosition(contentKey: "m") == 30)
            #expect(await p2.resumePosition(contentKey: "m") == 0)   // p2 has no progress for "m"
        }
    }
}
