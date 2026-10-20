import Foundation
import Testing
@testable import DebridCore

@Suite struct IndexStoreTests {
    private func store(perFile: Int = 64, total: Int = 1024) -> (IndexStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("IndexStoreTests-\(UUID().uuidString)")
        return (IndexStore(directory: dir, chunkSize: 4, perFileLimit: perFile, totalLimit: total), dir)
    }
    private func chunk(_ n: UInt8) -> Data { Data(repeating: n, count: 4) }

    /// A close writes up to 56 MiB of resume region, and the store used to be held for all of
    /// it: the NEXT film's open asked the store what it had on disk and waited behind the whole
    /// write. Now an open waits one chunk at most.
    @Test func anOpenDoesNotWaitBehindAnotherFilesWrite() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("IndexStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let chunkSize = 1 << 20
        let index = IndexStore(directory: dir, chunkSize: chunkSize, perFileLimit: 256 << 20,
                               totalLimit: 1 << 30)
        let chunks = (0..<120).map { ($0, Data(repeating: UInt8($0 & 0xFF), count: chunkSize)) }
        let folder = dir.appendingPathComponent(IndexStore.folderName("a#1"))
        let save = Task { await index.saveResume(fileKey: "a#1", totalSize: 1 << 30, chunks: chunks) }
        for _ in 0..<2000 where !FileManager.default.fileExists(
            atPath: folder.appendingPathComponent("0.chunk").path) {
            try await Task.sleep(for: .milliseconds(1))
        }
        _ = await index.open(fileKey: "b#1")
        let lastWritten = FileManager.default.fileExists(atPath: folder.appendingPathComponent("119.chunk").path)
        #expect(!lastWritten, "the open waited for the whole of another file's write")
        await save.value
        #expect(await index.open(fileKey: "a#1")?.chunks.count == 120)
    }

    @Test func anUnknownFileHasNoEntry() async {
        let (index, _) = store()
        #expect(await index.open(fileKey: "t#1") == nil)
    }

    @Test func headChunksSurviveToTheNextOpen() async {
        let (index, _) = store()
        await index.saveHead(fileKey: "t#1", totalSize: 400, chunks: [(0, chunk(1)), (99, chunk(2))])
        let entry = await index.open(fileKey: "t#1")
        #expect(entry == IndexEntry(totalSize: 400, chunks: [0, 99]))
        #expect(await index.loadChunk(fileKey: "t#1", index: 99) == chunk(2))
    }

    @Test func aNewResumeRegionReplacesTheOldOneButKeepsTheHead() async {
        let (index, _) = store()
        await index.saveHead(fileKey: "t#1", totalSize: 400, chunks: [(0, chunk(1))])
        await index.saveResume(fileKey: "t#1", totalSize: 400, chunks: [(50, chunk(5)), (51, chunk(5))])
        await index.saveResume(fileKey: "t#1", totalSize: 400, chunks: [(70, chunk(7))])
        #expect(await index.open(fileKey: "t#1")?.chunks == [0, 70])
        #expect(await index.loadChunk(fileKey: "t#1", index: 50) == nil)     // its file is gone too
    }

    @Test func aFileIsCappedAtItsLimitHeadFirst() async {
        let (index, _) = store(perFile: 12)                                   // 3 chunks of 4 bytes
        await index.saveHead(fileKey: "t#1", totalSize: 400, chunks: [(0, chunk(1)), (1, chunk(1))])
        await index.saveResume(fileKey: "t#1", totalSize: 400,
                               chunks: [(50, chunk(5)), (51, chunk(5)), (52, chunk(5))])
        #expect(await index.open(fileKey: "t#1")?.chunks == [0, 1, 50])
    }

    @Test func overTheTotalTheLeastRecentlyOpenedFileGoes() async {
        let (index, _) = store(perFile: 64, total: 16)                        // room for 4 chunks
        await index.saveHead(fileKey: "a", totalSize: 400, chunks: [(0, chunk(1)), (1, chunk(1))])
        await index.saveHead(fileKey: "b", totalSize: 400, chunks: [(0, chunk(2)), (1, chunk(2))])
        _ = await index.open(fileKey: "a")                                   // a is now the newer
        await index.saveHead(fileKey: "c", totalSize: 400, chunks: [(0, chunk(3)), (1, chunk(3))])
        #expect(await index.open(fileKey: "b") == nil)
        #expect(await index.open(fileKey: "a") != nil)
        #expect(await index.open(fileKey: "c") != nil)
    }

    @Test func discardForgetsTheFile() async {
        let (index, _) = store()
        await index.saveHead(fileKey: "t#1", totalSize: 400, chunks: [(0, chunk(1))])
        await index.discard(fileKey: "t#1")
        #expect(await index.open(fileKey: "t#1") == nil)
    }

    @Test func aSizeChangeReplacesTheEntry() async {
        // A different size means a different file under the same key: old chunks must not be served.
        let (index, _) = store()
        await index.saveHead(fileKey: "t#1", totalSize: 400, chunks: [(0, chunk(1))])
        await index.saveHead(fileKey: "t#1", totalSize: 800, chunks: [(1, chunk(2))])
        #expect(await index.open(fileKey: "t#1") == IndexEntry(totalSize: 800, chunks: [1]))
    }
}
