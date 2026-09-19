import Testing
import Foundation
@testable import DebridCore

@Suite struct FileLetterboxdOutboxTests {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("outbox-\(UUID().uuidString).json")
    }

    @Test func aQueuedWriteSurvivesANewInstance() async throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        try await FileLetterboxdOutbox(fileURL: url)
            .enqueue(LetterboxdWrite(tmdbID: 73, rating: 9, watchedAt: Date()))

        let reopened = try await FileLetterboxdOutbox(fileURL: url).all()
        #expect(reopened.count == 1)
        #expect(reopened.first?.tmdbID == 73)
    }

    /// Two writes, one completed: the survivor is what makes this test mean something. Asserting
    /// only that the queue is empty would pass just as well against a store that never wrote
    /// anything down — which is exactly the bug it is meant to catch.
    @Test func completingRemovesOnlyThatOneFromDisk() async throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let outbox = FileLetterboxdOutbox(fileURL: url)
        let done = LetterboxdWrite(tmdbID: 73, rating: nil)
        let waiting = LetterboxdWrite(tmdbID: 550, rating: nil)
        try await outbox.enqueue(done)
        try await outbox.enqueue(waiting)
        try await outbox.complete(done.id)

        let reopened = try await FileLetterboxdOutbox(fileURL: url).all()
        #expect(reopened.map(\.tmdbID) == [550])
    }

    /// A failure is not a loss. The write stays, its attempt count rises, and it is not due again
    /// until the backoff has passed — otherwise a dead browser session becomes a retry storm.
    @Test func aFailedWriteWaitsAndIsStillThere() async throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let outbox = FileLetterboxdOutbox(fileURL: url)
        let write = LetterboxdWrite(tmdbID: 73, rating: nil)
        try await outbox.enqueue(write)

        let now = Date()
        try await outbox.fail(write.id, error: "browser signed out", at: now)

        let stored = try #require(try await outbox.all().first)
        #expect(stored.attempts == 1)
        #expect(stored.lastError == "browser signed out")
        #expect(try await outbox.due(at: now).isEmpty)
        #expect(try await outbox.due(
            at: now.addingTimeInterval(LetterboxdBackoff.delay(forAttempt: 1) + 1)).count == 1)
    }

    /// An unreadable or absent file is an empty queue, not a crash: a queue that refuses to load
    /// would block every write behind it forever.
    @Test func anUnreadableFileIsAnEmptyQueue() async throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)
        #expect(try await FileLetterboxdOutbox(fileURL: url).all().isEmpty)
    }

    /// No writable location at all must not take the app down with it.
    @Test func noFileAtAllStillBehavesLikeAQueue() async throws {
        let outbox = FileLetterboxdOutbox(fileURL: nil)
        try await outbox.enqueue(LetterboxdWrite(tmdbID: 73, rating: nil))
        #expect(try await outbox.all().count == 1)
    }
}
