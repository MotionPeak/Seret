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

    @Test func aWriteCarriesTheRewatchFlag() {
        let first = LetterboxdWrite(tmdbID: 550, rating: 8)
        let again = LetterboxdWrite(tmdbID: 550, rating: 8, rewatch: true)
        #expect(first.rewatch == false)
        #expect(again.rewatch)
    }

    /// Entries queued before the flag existed must still decode — they are first watches.
    @Test func olderEncodedWritesDecodeAsFirstWatches() throws {
        let legacy = #"{"id":"00000000-0000-0000-0000-000000000001","tmdbID":550,"attempts":0}"#
        let decoded = try JSONDecoder().decode(LetterboxdWrite.self, from: Data(legacy.utf8))
        #expect(decoded.rewatch == false)
        #expect(decoded.tmdbID == 550)
    }

    @Test func aClearedRatingIsStillAWriteWorthQueueing() async throws {
        let outbox = InMemoryLetterboxdOutbox()
        try await outbox.enqueue(LetterboxdWrite(tmdbID: 550, rating: nil))
        let queued = try await outbox.due(at: Date())
        #expect(queued.count == 1)
        #expect(queued[0].rating == nil)
    }
}

/// A diary write is held back for a couple of minutes so the viewer can put a rating on it while
/// the credits roll. Held on disk rather than in memory, because the whole point of the outbox is
/// that being killed at the wrong moment cannot lose a diary entry.
@Suite struct LetterboxdOutboxAmendTests {
    @Test func aHeldWriteIsNotDueUntilItsHoldExpires() async throws {
        let outbox = InMemoryLetterboxdOutbox()
        let now = Date()
        try await outbox.enqueue(LetterboxdWrite(tmdbID: 550, watchedAt: now,
                                                 notBefore: now.addingTimeInterval(120)))
        #expect(try await outbox.due(at: now).isEmpty)
        #expect(try await outbox.due(at: now.addingTimeInterval(121)).count == 1)
    }

    @Test func amendingPutsARatingOnAHeldWriteAndReleasesIt() async throws {
        let outbox = InMemoryLetterboxdOutbox()
        let now = Date()
        let write = LetterboxdWrite(tmdbID: 550, watchedAt: now,
                                    notBefore: now.addingTimeInterval(120))
        try await outbox.enqueue(write)

        try await outbox.amend(write.id, rating: 8, notBefore: now)

        let due = try await outbox.due(at: now)
        #expect(due.count == 1)
        #expect(due.first?.rating == 8)
        // Everything else about the write survives — the diary date above all, or the entry lands
        // on the day it was sent rather than the day it was watched.
        #expect(due.first?.watchedAt == now)
        #expect(due.first?.tmdbID == 550)
    }

    /// Dismissing the prompt releases the write as it stands. Clearing a rating the viewer had
    /// already given the film on the title page would be a silent edit of their own data.
    @Test func amendingWithNoRatingLeavesTheWriteUnrated() async throws {
        let outbox = InMemoryLetterboxdOutbox()
        let now = Date()
        let write = LetterboxdWrite(tmdbID: 550, rating: 7, watchedAt: now,
                                    notBefore: now.addingTimeInterval(120))
        try await outbox.enqueue(write)

        try await outbox.amend(write.id, rating: nil, notBefore: now)

        #expect(try await outbox.due(at: now).first?.rating == nil)
    }

    @Test func amendingAWriteThatIsNoLongerQueuedDoesNothing() async throws {
        let outbox = InMemoryLetterboxdOutbox()
        try await outbox.amend(UUID(), rating: 8, notBefore: Date())
        #expect(try await outbox.all().isEmpty)
    }

    @Test func theFileBackedQueueAmendsTheSameWay() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("outbox-amend-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let now = Date()
        let write = LetterboxdWrite(tmdbID: 550, watchedAt: now,
                                    notBefore: now.addingTimeInterval(120))
        try await FileLetterboxdOutbox(fileURL: url).enqueue(write)

        try await FileLetterboxdOutbox(fileURL: url).amend(write.id, rating: 9, notBefore: now)

        // A THIRD instance, so this proves the amendment reached the file and not just memory.
        let due = try await FileLetterboxdOutbox(fileURL: url).due(at: now)
        #expect(due.count == 1)
        #expect(due.first?.rating == 9)
    }
}
