#if canImport(Network)
import Foundation
import Testing
@testable import DebridCore

extension StreamingNetworkTests {
    @Suite struct StreamProxyTests {
        let budget = StreamCacheBudget(ramBytes: 24 << 20, readAheadBytes: 8 << 20)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        init() { RangeFileURLProtocol.reset(.init(fileSize: 64 << 20)) }

        func proxy() -> StreamProxy {
            StreamProxy(budget: budget, indexDirectory: dir,
                        makeConfiguration: { RangeFileURLProtocol.configuration })
        }

        func get(_ url: URL, _ range: String) async throws -> (Data, Int) {
            var request = URLRequest(url: url)
            request.setValue(range, forHTTPHeaderField: "Range")
            let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
            return (data, (response as! HTTPURLResponse).statusCode)
        }

        @Test func anOpenedStreamIsALoopbackURLThatServesTheFile() async throws {
            let p = proxy()
            let handle = await p.open(upstream: URL(string: "https://rd.test/f.mkv")!, fileKey: "t#1",
                                      refreshUpstream: { URL(string: "https://rd.test/f.mkv")! })
            #expect(handle.url.host == "127.0.0.1")
            #expect(handle.url.lastPathComponent == "f.mkv")         // what the engine logs
            let (data, status) = try await get(handle.url, "bytes=0-65535")
            #expect(status == 206)
            #expect(data == RangeFileURLProtocol.bytes(0..<65536))
            await p.close(handle)
        }

        @Test func aClosedStreamIsGone() async throws {
            let p = proxy()
            let handle = await p.open(upstream: URL(string: "https://rd.test/f.mkv")!, fileKey: "t#1",
                                      refreshUpstream: { URL(string: "https://rd.test/f.mkv")! })
            await p.close(handle)
            #expect(try await get(handle.url, "bytes=0-9").1 == 404)
        }

        @Test func reopeningAFilePlayedBeforeStartsFromDisk() async throws {
            let p = proxy()
            let first = await p.open(upstream: URL(string: "https://rd.test/f.mkv")!, fileKey: "t#1",
                                     refreshUpstream: { URL(string: "https://rd.test/f.mkv")! })
            _ = try await get(first.url, "bytes=0-1048575")
            await p.markPlaybackStarted(first)
            await p.close(first)

            RangeFileURLProtocol.reset(.init(fileSize: 64 << 20))
            let second = await p.open(upstream: URL(string: "https://rd.test/f.mkv")!, fileKey: "t#1",
                                      refreshUpstream: { URL(string: "https://rd.test/f.mkv")! })
            let (data, status) = try await get(second.url, "bytes=0-1048575")
            #expect(status == 206)
            #expect(data == RangeFileURLProtocol.bytes(0..<1_048_576))
            #expect(RangeFileURLProtocol.requests.isEmpty)
            await p.close(second)
        }

        @Test func aDirectHandleIsJustTheURL() {
            let url = URL(string: "https://rd.test/f.mkv")!
            #expect(StreamHandle(direct: url).url == url)
        }
    }
}
#endif
