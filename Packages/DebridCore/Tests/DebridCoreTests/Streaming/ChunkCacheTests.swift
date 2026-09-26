import Foundation
import Testing
@testable import DebridCore

@Suite struct ChunkCacheTests {
    private func bytes(_ range: Range<Int>) -> Data { Data(range.map { UInt8($0 % 251) }) }

    @Test func appendedBytesAreReadBackWithinOneChunk() {
        var cache = ChunkCache(chunkSize: 4, budget: 100)
        let result = cache.append(bytes(0..<10), at: 0)
        #expect(result.accepted == 10 && !result.hitCached)
        #expect(cache.isComplete(0) && cache.isComplete(1) && !cache.isComplete(2))
        // A read never crosses a chunk: the server loops.
        #expect(cache.read(at: 5, max: 10) == bytes(5..<8))
        #expect(cache.read(at: 9, max: 10) == bytes(9..<10))
        #expect(cache.read(at: 10, max: 10) == nil)                  // not arrived yet
    }

    @Test func theLastChunkIsShorterOnceTheSizeIsKnown() {
        var cache = ChunkCache(chunkSize: 4, budget: 100)
        cache.setTotalSize(10)
        _ = cache.append(bytes(0..<10), at: 0)
        #expect(cache.expectedLength(of: 2) == 2)
        #expect(cache.isComplete(2))
    }

    @Test func aFetchStopsWhereCachedDataBegins() {
        // Two fetches converging on the same bytes: the second must not download them again.
        var cache = ChunkCache(chunkSize: 4, budget: 100)
        cache.insert(bytes(4..<8), index: 1)
        let result = cache.append(bytes(0..<8), at: 0)
        #expect(result.accepted == 4)
        #expect(result.hitCached)
    }

    @Test func theReadAheadWindowIsNeverEvicted() {
        // What libvlc is about to ask for; throwing it away would only fetch it again.
        var cache = ChunkCache(chunkSize: 4, budget: 4)
        _ = cache.append(bytes(0..<12), at: 0)
        cache.evictToBudget(anchor: 0, protecting: [0..<12])
        #expect(cache.byteCount == 12)
    }

    @Test func inForwardPlayTheOldestHistoryGoesFirst() {
        // Reading at 12: history 0–11 behind it; the farthest behind is the oldest.
        var cache = ChunkCache(chunkSize: 4, budget: 12)
        _ = cache.append(bytes(0..<16), at: 0)
        cache.evictToBudget(anchor: 12, protecting: [12..<16])
        #expect(!cache.contains(0))
        #expect(cache.contains(1) && cache.contains(2) && cache.contains(3))
        #expect(cache.byteCount == 12)
    }

    /// Measured in the tvOS simulator: after a rewind, least-recently-used eviction threw out the
    /// history just AHEAD of the new playhead — libvlc read it again seconds later and it had to be
    /// fetched from RD. Distance from the reader keeps it, and loses the far side instead.
    @Test func afterARewindTheFarSideGoesNotTheNextMinute() {
        var cache = ChunkCache(chunkSize: 4, budget: 16)
        _ = cache.append(bytes(0..<24), at: 0)         // chunks 0…5
        for offset in stride(from: Int64(0), to: 24, by: 4) { _ = cache.read(at: offset, max: 4) }
        cache.evictToBudget(anchor: 4, protecting: [4..<8])  // rewound to 4
        #expect(cache.contains(0) && cache.contains(1) && cache.contains(2) && cache.contains(3))
        #expect(!cache.contains(4) && !cache.contains(5))
    }

    @Test func everyReadersWindowIsProtected() {
        // Two libvlc connections reading at once: neither one's read-ahead may be evicted for the other.
        var cache = ChunkCache(chunkSize: 4, budget: 8)
        _ = cache.append(bytes(0..<24), at: 0)         // chunks 0…5
        cache.evictToBudget(anchor: 0, protecting: [0..<4, 20..<24])
        #expect(cache.contains(0) && cache.contains(5))
        #expect(cache.byteCount == 8)
    }

    @Test func aMemoryWarningKeepsOnlyTheWindowAndPartialChunks() {
        var cache = ChunkCache(chunkSize: 4, budget: 100)
        _ = cache.append(bytes(0..<18), at: 0)         // chunks 0…3 complete, 4 partial
        cache.dropOutsideWindow(anchor: 8, protecting: [8..<12])
        #expect(!cache.contains(0) && !cache.contains(1) && !cache.contains(3))
        #expect(cache.contains(2) && cache.contains(4))
    }

    @Test func onlyCompleteChunksAreOfferedForPersistence() {
        var cache = ChunkCache(chunkSize: 4, budget: 100)
        _ = cache.append(bytes(0..<6), at: 0)
        #expect(cache.completeData(0) == bytes(0..<4))
        #expect(cache.completeData(1) == nil)
    }
}
