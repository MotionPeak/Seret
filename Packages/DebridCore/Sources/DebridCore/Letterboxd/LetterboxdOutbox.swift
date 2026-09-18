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

    public func all() async throws -> [LetterboxdWrite] { writes }
}
