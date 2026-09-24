import Foundation

/// The stream cache's RAM: fixed-size chunks of the file, keyed by index.
///
/// It keeps HISTORY as well as read-ahead — the point of the whole cache: libvlc's own prefetch
/// discards what it has played whenever read-ahead needs the room, which is why every rewind went
/// back to Real-Debrid.
///
/// Over budget, the chunk FARTHEST from where libvlc is reading goes first, in either direction;
/// the read-ahead window in front of the reader and partial chunks are never evicted. In forward
/// play that is simply the oldest history. After a rewind it is what matters: least-recently-used
/// eviction was measured throwing out the history just ahead of the new playhead — which libvlc
/// read again seconds later, from RD — while keeping bytes far away that nobody would need.
struct ChunkCache: Sendable {
    let chunkSize: Int
    var budget: Int
    private(set) var totalSize: Int64?
    private(set) var byteCount = 0

    private struct Chunk: Sendable {
        var data: Data
        var read: Bool
    }
    private var chunks: [Int: Chunk] = [:]

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
    /// has not arrived. Marks the chunk read (for `unreadBytes`, a diagnostic).
    mutating func read(at offset: Int64, max: Int) -> Data? {
        let index = chunkIndex(of: offset)
        guard max > 0, var chunk = chunks[index] else { return nil }
        let within = Int(offset - chunkStart(index))
        guard chunk.data.count > within else { return nil }
        let out = chunk.data.subdata(in: within..<min(chunk.data.count, within + max))
        if !chunk.read {
            chunk.read = true
            chunks[index] = chunk
        }
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
            var chunk = chunks[index] ?? Chunk(data: Data(), read: false)
            guard chunk.data.count == within else { return (accepted, true) }
            let room = expectedLength(of: index) - within
            guard room > 0 else { return (accepted, true) }
            let take = min(room, remaining.count)
            chunk.data.append(contentsOf: remaining.prefix(take))
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
        chunks[index] = Chunk(data: Data(data), read: false)
        byteCount += data.count
    }

    /// The bytes of a complete chunk, for persistence; nil when absent or still filling.
    func completeData(_ index: Int) -> Data? {
        isComplete(index) ? chunks[index]?.data : nil
    }

    /// Evict until within budget: complete chunks outside every `protecting` range, farthest from
    /// `anchor` (where libvlc read last) first. The ranges are each reader's read-ahead — libvlc
    /// reads with more than one connection at once, so there can be several. If everything left is
    /// protected the cache stays over budget, and the session suspends read-ahead instead.
    mutating func evictToBudget(anchor: Int64, protecting: [Range<Int64>]) {
        guard byteCount > budget else { return }
        for index in evictable(anchor: anchor, protecting: protecting) {
            guard byteCount > budget else { return }
            remove(index)
        }
    }

    /// Memory warning: keep only the protected ranges and chunks still filling.
    mutating func dropOutsideWindow(anchor: Int64, protecting: [Range<Int64>]) {
        for index in evictable(anchor: anchor, protecting: protecting) { remove(index) }
    }

    /// Complete chunks outside every protected range, farthest from `anchor` first.
    private func evictable(anchor: Int64, protecting: [Range<Int64>]) -> [Int] {
        chunks.keys
            .filter { index in isComplete(index) && !protecting.contains { overlaps(index, $0) } }
            .sorted { distance($0, from: anchor) > distance($1, from: anchor) }
    }

    private func overlaps(_ index: Int, _ window: Range<Int64>) -> Bool {
        let start = chunkStart(index)
        return start < window.upperBound && start + Int64(chunkSize) > window.lowerBound
    }

    private func distance(_ index: Int, from anchor: Int64) -> Int64 {
        let start = chunkStart(index), end = start + Int64(chunkSize)
        if anchor < start { return start - anchor }
        if anchor >= end { return anchor - end + 1 }
        return 0
    }

    private mutating func remove(_ index: Int) {
        if let chunk = chunks.removeValue(forKey: index) { byteCount -= chunk.data.count }
    }
}
