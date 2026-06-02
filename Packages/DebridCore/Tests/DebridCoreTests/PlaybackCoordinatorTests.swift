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
            let coord = PlaybackCoordinator(store: try store())
            #expect(await coord.resumePosition(contentKey: "movie:tmdb:1") == 0)
        }

        @Test func recordThenResumeReturnsSavedPosition() async throws {
            let s = try store()
            let coord = PlaybackCoordinator(store: s)
            await coord.record(contentKey: "movie:tmdb:1", sourceKey: "T#0", position: 73, duration: 100)
            #expect(await coord.resumePosition(contentKey: "movie:tmdb:1") == 73)
            let saved = try await s.progress(forContentKey: "movie:tmdb:1")
            #expect(saved?.positionSeconds == 73)
            #expect(saved?.finished == false)
        }

        @Test func recordMarksFinishedPastThreshold() async throws {
            let s = try store()
            let coord = PlaybackCoordinator(store: s)
            await coord.record(contentKey: "k", sourceKey: "T#0", position: 96, duration: 100)   // 96% ≥ 95%
            #expect(try await s.progress(forContentKey: "k")?.finished == true)
        }

        @Test func recordBelowThresholdIsNotFinished() async throws {
            let s = try store()
            let coord = PlaybackCoordinator(store: s)
            await coord.record(contentKey: "k", sourceKey: "T#0", position: 50, duration: 100)
            #expect(try await s.progress(forContentKey: "k")?.finished == false)
        }

        @Test func resumeIsZeroWhenFinished() async throws {
            let s = try store()
            let coord = PlaybackCoordinator(store: s)
            await coord.record(contentKey: "k", sourceKey: "T#0", position: 99, duration: 100)   // finished
            #expect(await coord.resumePosition(contentKey: "k") == 0)
        }
    }
}
