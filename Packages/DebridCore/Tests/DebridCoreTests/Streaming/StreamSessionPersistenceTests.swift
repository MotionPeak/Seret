import Foundation
import Testing
@testable import DebridCore

extension StreamingNetworkTests {
    @Suite struct StreamSessionPersistenceTests {
        static let mib: Int64 = 1 << 20
        let budget = StreamCacheBudget(ramBytes: 24 << 20, readAheadBytes: 8 << 20)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StreamSessionPersistenceTests-\(UUID().uuidString)")

        init() { RangeFileURLProtocol.reset(.init(fileSize: 64 << 20)) }

        func index() -> IndexStore {
            IndexStore(directory: dir, chunkSize: budget.chunkSize,
                       perFileLimit: budget.indexBytesPerFile, totalLimit: budget.indexBytesTotal)
        }

        func session(_ index: IndexStore) -> StreamSession {
            StreamSession(id: UUID(), fileKey: "t#1", upstream: URL(string: "https://rd.test/f.mkv")!,
                          refreshUpstream: { URL(string: "https://rd.test/f.mkv")! },
                          budget: budget, index: index,
                          makeConfiguration: { RangeFileURLProtocol.configuration }, log: { _ in })
        }

        func read(_ s: StreamSession, _ offset: Int64, _ count: Int) async throws -> Data {
            var out = Data()
            while out.count < count {
                out.append(try await s.read(offset: offset + Int64(out.count), max: count - out.count))
            }
            return out
        }

        @Test func whatWasReadBeforeTheFirstFrameIsThereNextTime() async throws {
            let store = index()
            let first = session(store)
            _ = try await first.head()
            _ = try await read(first, 0, 2 << 20)                    // header + index region
            await first.markPlaybackStarted()
            // Watch far from the start before leaving, so the resume region kept at close (48 MiB
            // behind the last read) cannot also cover the header — only the head save can.
            _ = try await read(first, 55 * Self.mib, 1 << 20)
            await first.close()

            RangeFileURLProtocol.reset(.init(fileSize: 64 << 20))
            let second = session(store)
            #expect(try await second.head().total == 64 << 20)        // size from disk
            #expect(try await read(second, 0, 2 << 20) == RangeFileURLProtocol.bytes(0..<(2 << 20)))
            #expect(RangeFileURLProtocol.requests.isEmpty)            // not one connection to RD
            await second.close()
        }

        /// Found in review: with the index on disk, the head and first frames come from disk before
        /// RD is ever asked. When RD then refuses (the file is gone, RD is down), all libvlc sees
        /// is a closed connection — an EOF — and the film "ended" with no Retry. The session must
        /// remember WHY, for the player to ask.
        @Test func aRefusalAfterAHeadFromDiskIsRemembered() async throws {
            let store = index()
            let first = session(store)
            _ = try await read(first, 0, 1 << 20)
            await first.markPlaybackStarted()
            await first.close()

            RangeFileURLProtocol.reset(.init(fileSize: 64 << 20, statusByPath: ["/f.mkv": 404]))
            let second = session(store)
            #expect(try await second.head().total == 64 << 20)        // from disk: RD not asked
            #expect(await second.upstreamFailure == nil)
            await #expect(throws: StreamError.upstreamStatus(404)) {
                try await self.read(second, 40 * Self.mib, 4096)
            }
            #expect(await second.upstreamFailure == .upstreamStatus(404))
            await second.close()
        }

        @Test func whereTheViewerStoppedIsThereNextTime() async throws {
            let store = index()
            let first = session(store)
            _ = try await read(first, 0, 4096)
            await first.markPlaybackStarted()
            _ = try await read(first, 30 * Self.mib, 2 << 20)        // watching around 30 MiB
            await first.close()

            RangeFileURLProtocol.reset(.init(fileSize: 64 << 20))
            let second = session(store)
            let at = 30 * Self.mib + 100
            #expect(try await read(second, at, 4096) == RangeFileURLProtocol.bytes(at..<(at + 4096)))
            #expect(RangeFileURLProtocol.requests.isEmpty)
            await second.close()
        }

        @Test func aDifferentSizeFromRDDiscardsTheStoredIndex() async throws {
            let store = index()
            let first = session(store)
            _ = try await read(first, 0, 1 << 20)
            await first.markPlaybackStarted()
            await first.close()

            RangeFileURLProtocol.reset(.init(fileSize: 32 << 20))     // RD now reports another size
            let second = session(store)
            _ = try await read(second, 20 * Self.mib, 4096)           // a miss: RD answers 32 MiB
            await second.close()
            #expect(await store.open(fileKey: "t#1")?.totalSize != 64 << 20)
        }

        @Test func trimmingMemoryForgetsHistoryButNotReadAhead() async throws {
            let s = session(index())
            _ = try await read(s, 0, 2 << 20)
            await s.trimMemory()
            let before = await s.upstreamRequestCount
            _ = try await read(s, 0, 4096)                            // history is gone: RD again
            #expect(await s.upstreamRequestCount > before)
            await s.close()
        }
    }
}
