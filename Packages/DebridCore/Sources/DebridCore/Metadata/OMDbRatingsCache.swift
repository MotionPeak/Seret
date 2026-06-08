import Foundation

/// Persistent, TTL'd cache of OMDb ratings keyed by IMDb id, backed by one JSON file. Keeps us
/// well under OMDb's 1,000/day free quota: a given title costs ~1 fetch per TTL window. Reads
/// degrade silently (missing / unreadable file → empty), mirroring `LibrarySnapshotStore`.
public actor OMDbRatingsCache {
    struct Entry: Codable, Sendable {
        let ratings: OMDbRatings
        let fetchedAt: Date
    }

    private let directory: URL
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date
    private var memory: [String: Entry]

    private var fileURL: URL { directory.appending(path: "omdb-ratings.json") }

    /// - Parameters:
    ///   - ttl: how long an entry stays "fresh" (default 7 days).
    ///   - now: injectable clock for testing.
    public init(directory: URL,
                ttl: TimeInterval = 7 * 24 * 60 * 60,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.ttl = ttl
        self.now = now
        let url = directory.appending(path: "omdb-ratings.json")
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            self.memory = decoded
        } else {
            self.memory = [:]
        }
    }

    /// Fresh entry only (within TTL), else nil.
    public func cached(imdbID: String) -> OMDbRatings? {
        guard let entry = memory[imdbID], now().timeIntervalSince(entry.fetchedAt) < ttl else {
            return nil
        }
        return entry.ratings
    }

    /// Any stored entry regardless of age — the offline/stale fallback.
    public func stored(imdbID: String) -> OMDbRatings? { memory[imdbID]?.ratings }

    public func store(_ ratings: OMDbRatings, imdbID: String) {
        memory[imdbID] = Entry(ratings: ratings, fetchedAt: now())
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
