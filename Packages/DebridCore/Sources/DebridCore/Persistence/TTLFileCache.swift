import Foundation

/// Persistent, TTL'd cache of one `Value` per string key, backed by a single JSON file.
///
/// Two rules live here and are worth stating, because both were learned the expensive way:
///
/// - `cached` returns an entry only while it is fresh; `stored` returns it whatever its age. That
///   split is what lets a caller fall back to a stale answer when the network fails, instead of
///   showing nothing.
/// - Every read degrades to "empty" rather than throwing. A cache that cannot be read costs a
///   re-fetch; one that refuses to load costs the feature.
public actor TTLFileCache<Value: Codable & Sendable> {
    struct Entry: Codable, Sendable {
        let value: Value
        let fetchedAt: Date
    }

    private let directory: URL
    private let fileName: String
    private let ttl: TimeInterval
    private let keepFor: TimeInterval?
    private let now: @Sendable () -> Date
    /// nil until first used. The file is read then, on this actor, rather than in `init` — which
    /// ran on whoever built the cache, the main actor at sign-in.
    private var loaded: [String: Entry]?

    private var fileURL: URL { directory.appending(path: fileName) }

    /// - Parameters:
    ///   - fileName: names the cache within the directory, so two caches can share one.
    ///   - ttl: how long an entry stays fresh.
    ///   - keepFor: how long an entry is kept at all, as the stale fallback. Past it, the entry
    ///     goes when the file is next written. nil keeps entries for good.
    ///   - now: injectable clock for testing.
    public init(directory: URL,
                fileName: String,
                ttl: TimeInterval,
                keepFor: TimeInterval? = nil,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.fileName = fileName
        self.ttl = ttl
        self.keepFor = keepFor
        self.now = now
    }

    /// Reads the file on first use; afterwards the dictionary in memory is the truth.
    private func entries() -> [String: Entry] {
        if let loaded { return loaded }
        let decoded = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
        loaded = decoded
        return decoded
    }

    /// Fresh entry only (within the TTL), else nil.
    public func cached(_ key: String) -> Value? {
        guard let entry = entries()[key], now().timeIntervalSince(entry.fetchedAt) < ttl else {
            return nil
        }
        return entry.value
    }

    /// Any stored entry regardless of age — the offline/stale fallback.
    public func stored(_ key: String) -> Value? { entries()[key]?.value }

    public func store(_ value: Value, key: String) {
        var all = entries()
        loaded = nil                        // one reference, so the edit below is in place
        all[key] = Entry(value: value, fetchedAt: now())
        if let keepFor {
            let current = now()
            all = all.filter { current.timeIntervalSince($0.value.fetchedAt) < keepFor }
        }
        loaded = all
        persist(all)
    }

    /// Read, decide and write in one step, with no suspension in between — so two callers that
    /// each fold something into the same entry cannot both start from the old one. `transform`
    /// gets the stored value whatever its age and returns the new one, or nil to leave the entry as
    /// it is. Returns what is stored afterwards.
    @discardableResult
    public func update(_ key: String, _ transform: (Value?) -> Value?) -> Value? {
        let current = entries()[key]?.value
        guard let updated = transform(current) else { return current }
        store(updated, key: key)
        return updated
    }

    private func persist(_ all: [String: Entry]) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
