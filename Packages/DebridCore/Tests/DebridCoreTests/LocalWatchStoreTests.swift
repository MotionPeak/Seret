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
    }
}
