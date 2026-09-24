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

    @Test func unreadChunksAreNeverEvicted() {
        // Read-ahead is what libvlc is about to ask for; throwing it away would re-fetch it.
        var cache = ChunkCache(chunkSize: 4, budget: 4)
        _ = cache.append(bytes(0..<12), at: 0)
        cache.evictToBudget()
        #expect(cache.byteCount == 12)
        #expect(cache.unreadBytes == 12)
    }

    @Test func historyIsEvictedLeastRecentlyUsedFirst() {
        var cache = ChunkCache(chunkSize: 4, budget: 12)
        _ = cache.append(bytes(0..<16), at: 0)       // 4 chunks, 16 bytes, over budget
        _ = cache.read(at: 0, max: 4)                // chunk 0 read first…
        _ = cache.read(at: 4, max: 4)                // …then chunk 1
        cache.evictToBudget()
        #expect(!cache.contains(0))                  // the older history went
        #expect(cache.contains(1) && cache.contains(2) && cache.contains(3))
        #expect(cache.byteCount == 12)
    }

    @Test func aRewindReadRefreshesItsChunk() {
        var cache = ChunkCache(chunkSize: 4, budget: 12)
        _ = cache.append(bytes(0..<16), at: 0)
        _ = cache.read(at: 0, max: 4)
        _ = cache.read(at: 4, max: 4)
        _ = cache.read(at: 0, max: 4)                // chunk 0 read again: now the most recent
        cache.evictToBudget()
        #expect(cache.contains(0) && !cache.contains(1))
    }

    @Test func droppingHistoryKeepsReadAheadAndPartialChunks() {
        var cache = ChunkCache(chunkSize: 4, budget: 100)
        _ = cache.append(bytes(0..<10), at: 0)
        _ = cache.read(at: 0, max: 4)
        _ = cache.read(at: 8, max: 2)                // chunk 2 is read but still partial
        cache.dropHistory()
        #expect(!cache.contains(0))
        #expect(cache.contains(1) && cache.contains(2))
    }

    @Test func onlyCompleteChunksAreOfferedForPersistence() {
        var cache = ChunkCache(chunkSize: 4, budget: 100)
        _ = cache.append(bytes(0..<6), at: 0)
        #expect(cache.completeData(0) == bytes(0..<4))
        #expect(cache.completeData(1) == nil)
    }
}
