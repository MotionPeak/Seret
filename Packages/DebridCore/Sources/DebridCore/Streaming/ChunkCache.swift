import Foundation

/// The stream cache's RAM: fixed-size chunks of the file, keyed by index.
///
/// A chunk is UNREAD until libvlc takes bytes from it and HISTORY after. Read-ahead lives in unread
/// chunks and is never evicted; history is evicted least-recently-used first when over budget. That
/// split is the point of the whole cache: libvlc's own prefetch keeps only read-ahead and discards
/// history whenever read-ahead needs the room, which is why every rewind went back to Real-Debrid.
struct ChunkCache: Sendable {
    let chunkSize: Int
    var budget: Int
    private(set) var totalSize: Int64?
    private(set) var byteCount = 0

    private struct Chunk: Sendable {
        var data: Data
        var read: Bool
        var lastAccess: UInt64
    }
    private var chunks: [Int: Chunk] = [:]
    private var clock: UInt64 = 0

    init(chunkSize: Int, budget: Int) {
        precondition(chunkSize > 0)
        self.chunkSize = chunkSize
        self.budget = budget
    }

    mutating func setTotalSize(_ size: Int64) { totalSize = size }

    func chunkIndex(of offset: Int64) -> Int { Int(offset / Int64(chunkSize)) }
    func chunkStart(_ index: Int) -> Int64 { Int64(index) * Int64(chunkSize) }

    /// A chunk's full length: `chunkSize`, except the file's last chunk once the size is known.
    func expectedLength(of index: Int) -> Int {
        guard let totalSize else { return chunkSize }
        return Int(max(0, min(Int64(chunkSize), totalSize - chunkStart(index))))
    }

    func contains(_ index: Int) -> Bool { chunks[index] != nil }

    func isComplete(_ index: Int) -> Bool {
        guard let chunk = chunks[index] else { return false }
        return chunk.data.count >= expectedLength(of: index)
    }

    var unreadBytes: Int { chunks.values.reduce(0) { $0 + ($1.read ? 0 : $1.data.count) } }

    /// Up to `max` bytes at `offset`, from its chunk only (the caller loops), or nil when that byte
    /// has not arrived. Marks the chunk read, which makes it history.
    mutating func read(at offset: Int64, max: Int) -> Data? {
        let index = chunkIndex(of: offset)
        guard max > 0, var chunk = chunks[index] else { return nil }
        let within = Int(offset - chunkStart(index))
        guard chunk.data.count > within else { return nil }
        let out = chunk.data.subdata(in: within..<min(chunk.data.count, within + max))
        chunk.read = true
        chunk.lastAccess = tick()
        chunks[index] = chunk
        return out
    }

    /// Append bytes a fetch streamed, starting at `offset`.
    ///
    /// Every fetch enters a chunk at its start, so finding bytes already there means another fetch
    /// (or the disk) got there first: `hitCached` tells the caller to stop this fetch rather than
    /// download them again.
    mutating func append(_ data: Data, at offset: Int64) -> (accepted: Int, hitCached: Bool) {
        var accepted = 0
        var cursor = offset
        var remaining = data[...]
        while !remaining.isEmpty {
            let index = chunkIndex(of: cursor)
            let within = Int(cursor - chunkStart(index))
            var chunk = chunks[index] ?? Chunk(data: Data(), read: false, lastAccess: 0)
            guard chunk.data.count == within else { return (accepted, true) }
            let room = expectedLength(of: index) - within
            guard room > 0 else { return (accepted, true) }
            let take = min(room, remaining.count)
            chunk.data.append(contentsOf: remaining.prefix(take))
            chunk.lastAccess = tick()
            chunks[index] = chunk
            byteCount += take
            accepted += take
            cursor += Int64(take)
            remaining = remaining.dropFirst(take)
        }
        return (accepted, false)
    }

    /// A complete chunk from the disk index.
    mutating func insert(_ data: Data, index: Int) {
        if let old = chunks[index] { byteCount -= old.data.count }
        chunks[index] = Chunk(data: Data(data), read: false, lastAccess: tick())
        byteCount += data.count
    }

    /// The bytes of a complete chunk, for persistence; nil when absent or still filling.
    func completeData(_ index: Int) -> Data? {
        isComplete(index) ? chunks[index]?.data : nil
    }

    /// Evict history, least recently used first, until within budget. Unread and partial chunks
    /// are never evicted — the fetch planner suspends read-ahead instead.
    mutating func evictToBudget() {
        while byteCount > budget {
            guard let victim = chunks
                .filter({ $0.value.read && isComplete($0.key) })
                .min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key
            else { return }
            remove(victim)
        }
    }

    /// Memory warning: keep only what libvlc has not read yet.
    mutating func dropHistory() {
        for index in chunks.filter({ $0.value.read && isComplete($0.key) }).map(\.key) {
            remove(index)
        }
    }

    private mutating func remove(_ index: Int) {
        if let chunk = chunks.removeValue(forKey: index) { byteCount -= chunk.data.count }
    }

    private mutating func tick() -> UInt64 {
        clock += 1
        return clock
    }
}
