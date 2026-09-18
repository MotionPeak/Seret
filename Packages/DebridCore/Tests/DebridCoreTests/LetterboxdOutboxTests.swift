import Testing
import Foundation
@testable import DebridCore

@Suite struct LetterboxdOutboxTests {
    @Test func onlyAMovieKeyWithATMDBIdYieldsAnId() {
        #expect(LetterboxdContentKey.tmdbID(fromMovieKey: "movie:tmdb:335984") == 335984)
        // An episode is not a film, and Letterboxd has no television at all.
        #expect(LetterboxdContentKey.tmdbID(fromMovieKey: "show:tmdb:1396:s1e2") == nil)
        #expect(LetterboxdContentKey.tmdbID(fromMovieKey: "movie:tmdb:1:s1e2") == nil)
        // A library item TMDB enrichment never matched keeps its parsed-title id.
        #expect(LetterboxdContentKey.tmdbID(fromMovieKey: "movie:speed:1994") == nil)
        #expect(LetterboxdContentKey.tmdbID(fromMovieKey: "") == nil)
    }

    @Test func aQueuedWriteIsDueImmediately() async throws {
        let outbox = InMemoryLetterboxdOutbox()
        try await outbox.enqueue(LetterboxdWrite(tmdbID: 550, rating: 8))
        #expect(try await outbox.due(at: Date()).count == 1)
    }

    @Test func completingRemovesIt() async throws {
        let outbox = InMemoryLetterboxdOutbox()
        let write = LetterboxdWrite(tmdbID: 550, rating: 8)
        try await outbox.enqueue(write)
        try await outbox.complete(write.id)
        #expect(try await outbox.all().isEmpty)
    }

    @Test func failingBumpsAttemptsAndPushesItIntoTheFuture() async throws {
        let outbox = InMemoryLetterboxdOutbox()
        let write = LetterboxdWrite(tmdbID: 550, rating: 8)
        try await outbox.enqueue(write)
        let now = Date()
        try await outbox.fail(write.id, error: "boom", at: now)

        // #require, not `!`: if the write were dropped this must fail, not crash the whole run.
        let stored = try #require(await outbox.all().first)
        #expect(stored.attempts == 1)
        #expect(stored.lastError == "boom")
        #expect(stored.notBefore > now)
        // Still queued — a failure must never drop the write.
        #expect(try await outbox.due(at: now).isEmpty)
        #expect(try await outbox.due(at: now.addingTimeInterval(60)).count == 1)
    }

    @Test func backoffGrowsAndIsCapped() {
        #expect(LetterboxdBackoff.delay(forAttempt: 1) == 30)
        #expect(LetterboxdBackoff.delay(forAttempt: 2) == 60)
        #expect(LetterboxdBackoff.delay(forAttempt: 3) == 120)
        #expect(LetterboxdBackoff.delay(forAttempt: 99) == 6 * 3600)
    }

    @Test func aWriteSurvivesACodableRoundTrip() throws {
        let write = LetterboxdWrite(tmdbID: 550, rating: 8, watchedAt: Date(timeIntervalSince1970: 1_000_000))
        let data = try JSONEncoder().encode(write)
        #expect(try JSONDecoder().decode(LetterboxdWrite.self, from: data) == write)
    }

    @Test func aClearedRatingIsStillAWriteWorthQueueing() async throws {
        let outbox = InMemoryLetterboxdOutbox()
        try await outbox.enqueue(LetterboxdWrite(tmdbID: 550, rating: nil))
        let queued = try await outbox.due(at: Date())
        #expect(queued.count == 1)
        #expect(queued[0].rating == nil)
    }
}
