import Testing
import Foundation
import DebridCore
@testable import DebridUI

@Suite struct TraktMigrationTests {
    actor CaptureAPI: TraktWatchAPI {
        private(set) var history: [TraktMediaRef] = []
        private(set) var scrobbles: [(ref: TraktMediaRef, progress: Double)] = []
        func playbackMovies() async throws -> [TraktPlaybackItem] { [] }
        func playbackEpisodes() async throws -> [TraktPlaybackItem] { [] }
        func watchedMovies() async throws -> [TraktWatchedMovie] { [] }
        func watchedShows() async throws -> [TraktWatchedShow] { [] }
        func ratedMovies() async throws -> [TraktRatingItem] { [] }
        func ratedEpisodes() async throws -> [TraktRatingItem] { [] }
        func ratedShows() async throws -> [TraktRatingItem] { [] }
        func addToHistory(_ refs: [TraktMediaRef]) async throws { history.append(contentsOf: refs) }
        func removeFromHistory(_ refs: [TraktMediaRef]) async throws {}
        func scrobble(_ a: ScrobbleAction, ref: TraktMediaRef, progress: Double) async throws {
            scrobbles.append((ref, progress))
        }
    }

    private func state(_ key: String, position: Double, duration: Double,
                       finished: Bool) -> WatchState {
        WatchState(contentKey: key, sourceKey: "s", positionSeconds: position,
                   durationSeconds: duration, finished: finished, updatedAt: Date())
    }

    @Test func mapsFinishedAndInProgressRows() {
        let rows = TraktMigration.rows(from: [
            state("movie:tmdb:1", position: 100, duration: 100, finished: true),
            state("show:tmdb:2:s1e3", position: 40, duration: 100, finished: false)
        ])
        #expect(rows.count == 2)
        #expect(rows[0] == .init(ref: .movie(tmdb: 1), fraction: 1, finished: true))
        #expect(rows[1] == .init(ref: .episode(showTmdb: 2, season: 1, number: 3),
                                 fraction: 0.4, finished: false))
    }

    @Test func skipsUnenrichedAndEmptyRows() {
        let rows = TraktMigration.rows(from: [
            state("movie:dune:2024", position: 50, duration: 100, finished: false),  // no tmdb id
            state("movie:tmdb:3", position: 0, duration: 100, finished: false)       // nothing watched
        ])
        #expect(rows.isEmpty)
    }

    @Test func pushesHistoryInOneBatchAndScrobblesTheRest() async throws {
        let api = CaptureAPI()
        try await TraktMigration.push([
            .init(ref: .movie(tmdb: 1), fraction: 1.0, finished: true),
            .init(ref: .movie(tmdb: 2), fraction: 0.4, finished: false),
            .init(ref: .movie(tmdb: 3), fraction: 1.0, finished: true)
        ], to: api)
        #expect(await api.history == [.movie(tmdb: 1), .movie(tmdb: 3)])   // one batched call
        let scrobbles = await api.scrobbles
        #expect(scrobbles.count == 1)
        #expect(scrobbles[0].ref == .movie(tmdb: 2))
        #expect(scrobbles[0].progress == 40)
    }

    @Test func nothingToMigrateIsANoOp() async throws {
        let api = CaptureAPI()
        try await TraktMigration.push([], to: api)
        #expect(await api.history.isEmpty)
        #expect(await api.scrobbles.isEmpty)
    }
}
