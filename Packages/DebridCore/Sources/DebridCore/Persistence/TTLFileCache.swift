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
    private let now: @Sendable () -> Date
    private var memory: [String: Entry]

    private var fileURL: URL { directory.appending(path: fileName) }

    /// - Parameters:
    ///   - fileName: names the cache within the directory, so two caches can share one.
    ///   - ttl: how long an entry stays fresh.
    ///   - now: injectable clock for testing.
    public init(directory: URL,
                fileName: String,
                ttl: TimeInterval,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.fileName = fileName
        self.ttl = ttl
        self.now = now
        let url = directory.appending(path: fileName)
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            self.memory = decoded
        } else {
            self.memory = [:]
        }
    }

    /// Fresh entry only (within the TTL), else nil.
    public func cached(_ key: String) -> Value? {
        guard let entry = memory[key], now().timeIntervalSince(entry.fetchedAt) < ttl else {
            return nil
        }
        return entry.value
    }

    /// Any stored entry regardless of age — the offline/stale fallback.
    public func stored(_ key: String) -> Value? { memory[key]?.value }

    public func store(_ value: Value, key: String) {
        memory[key] = Entry(value: value, fetchedAt: now())
        persist()
    }

    /// Read, decide and write in one step, with no suspension in between — so two callers that
    /// each fold something into the same entry cannot both start from the old one. `transform`
    /// gets the stored value whatever its age and returns the new one, or nil to leave the entry as
    /// it is. Returns what is stored afterwards.
    @discardableResult
    public func update(_ key: String, _ transform: (Value?) -> Value?) -> Value? {
        guard let updated = transform(memory[key]?.value) else { return memory[key]?.value }
        store(updated, key: key)
        return updated
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
