import Foundation

/// A durable queue of pending Letterboxd writes.
///
/// The queue lives on the device that played the film, and nowhere else: the server writes or says
/// precisely why it could not, so it needs no queue of its own. One queue, one owner, one retry
/// clock — and a write made away from home waits here until the Synology is reachable.
///
/// Every failure degrades to "empty" rather than throwing. A queue that refuses to load because its
/// file is corrupt would block every write behind it forever, which is worse than losing it.
public actor FileLetterboxdOutbox: LetterboxdOutbox {
    private let fileURL: URL?
    private var writes: [LetterboxdWrite]

    public init(fileURL: URL?) {
        self.fileURL = fileURL
        self.writes = Self.load(fileURL)
    }

    /// Located through `WritableStorage`, which proves the directory by creating it — tvOS has no
    /// `Application Support` and assuming otherwise has failed silently on a real device before.
    public static func defaultURL() -> URL? {
        WritableStorage.file(named: "letterboxd-outbox.json")
    }

    private static func load(_ url: URL?) -> [LetterboxdWrite] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([LetterboxdWrite].self, from: data)) ?? []
    }

    private func persist() {
        guard let fileURL, let data = try? JSONEncoder().encode(writes) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    public func enqueue(_ write: LetterboxdWrite) async throws {
        writes.append(write)
        persist()
    }

    public func due(at now: Date) async throws -> [LetterboxdWrite] {
        writes.filter { $0.notBefore <= now }
    }

    public func complete(_ id: UUID) async throws {
        writes.removeAll { $0.id == id }
        persist()
    }

    public func fail(_ id: UUID, error: String, at now: Date) async throws {
        guard let index = writes.firstIndex(where: { $0.id == id }) else { return }
        writes[index].attempts += 1
        writes[index].lastError = error
        writes[index].notBefore = now.addingTimeInterval(
            LetterboxdBackoff.delay(forAttempt: writes[index].attempts))
        persist()
    }

    public func amend(_ id: UUID, rating: Int?, notBefore: Date) async throws {
        guard let index = writes.firstIndex(where: { $0.id == id }) else { return }
        writes[index].rating = rating
        writes[index].notBefore = notBefore
        persist()
    }

    public func all() async throws -> [LetterboxdWrite] { writes }
}
