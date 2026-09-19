import Foundation

/// A durable queue of pending Letterboxd writes.
///
/// Local watch state is the truth; this is the mirror's to-do list. A failed write is never
/// dropped and never alters local state — it waits.
public protocol LetterboxdOutbox: Sendable {
    func enqueue(_ write: LetterboxdWrite) async throws
    func due(at now: Date) async throws -> [LetterboxdWrite]
    func complete(_ id: UUID) async throws
    func fail(_ id: UUID, error: String, at now: Date) async throws
    /// Put a rating on a queued write and reschedule it.
    ///
    /// A diary entry is queued the moment the credits roll but held for a couple of minutes, so
    /// the viewer can rate the film while it is still in front of them. Rating it amends the
    /// entry in place and releases it; dismissing releases it as it stands. Doing this as
    /// complete-then-re-enqueue instead would let a drain running in between send the unrated
    /// original — and then the rating would have nowhere to go.
    ///
    /// Silently does nothing when the write has already been sent. By then there is nothing to
    /// amend, and the alternative is an error every caller would have to ignore.
    func amend(_ id: UUID, rating: Int?, notBefore: Date) async throws
    func all() async throws -> [LetterboxdWrite]
}

public actor InMemoryLetterboxdOutbox: LetterboxdOutbox {
    private var writes: [LetterboxdWrite]

    public init(_ seed: [LetterboxdWrite] = []) { self.writes = seed }

    public func enqueue(_ write: LetterboxdWrite) async throws { writes.append(write) }

    public func due(at now: Date) async throws -> [LetterboxdWrite] {
        writes.filter { $0.notBefore <= now }
    }

    public func complete(_ id: UUID) async throws { writes.removeAll { $0.id == id } }

    public func fail(_ id: UUID, error: String, at now: Date) async throws {
        guard let index = writes.firstIndex(where: { $0.id == id }) else { return }
        writes[index].attempts += 1
        writes[index].lastError = error
        writes[index].notBefore = now.addingTimeInterval(
            LetterboxdBackoff.delay(forAttempt: writes[index].attempts))
    }

    public func amend(_ id: UUID, rating: Int?, notBefore: Date) async throws {
        guard let index = writes.firstIndex(where: { $0.id == id }) else { return }
        writes[index].rating = rating
        writes[index].notBefore = notBefore
    }

    public func all() async throws -> [LetterboxdWrite] { writes }
}
