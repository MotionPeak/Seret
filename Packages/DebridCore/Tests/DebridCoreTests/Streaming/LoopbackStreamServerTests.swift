#if canImport(Network)
import Foundation
import Testing
@testable import DebridCore

extension StreamingNetworkTests {
    @Suite struct LoopbackStreamServerTests {
        let budget = StreamCacheBudget(ramBytes: 24 << 20, readAheadBytes: 8 << 20)

        init() { RangeFileURLProtocol.reset(.init(fileSize: 64 << 20)) }

        /// A server with one session behind a known id, and a plain URLSession client (real
        /// loopback HTTP — the client is NOT mocked; only the session's upstream is).
        func serve() async throws -> (URL, LoopbackStreamServer, StreamSession) {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let id = UUID()
            let session = StreamSession(
                id: id, fileKey: "t#1", upstream: URL(string: "https://rd.test/f.mkv")!,
                refreshUpstream: { URL(string: "https://rd.test/f.mkv")! }, budget: budget,
                index: IndexStore(directory: dir, chunkSize: budget.chunkSize,
                                  perFileLimit: budget.indexBytesPerFile, totalLimit: budget.indexBytesTotal),
                makeConfiguration: { RangeFileURLProtocol.configuration }, log: { _ in })
            let server = LoopbackStreamServer(session: { $0 == id ? session : nil }, log: { _ in })
            let port = try await server.start()
            return (URL(string: "http://127.0.0.1:\(port)/s/\(id.uuidString)")!, server, session)
        }

        func get(_ url: URL, range: String?, method: String = "GET") async throws -> (Data, HTTPURLResponse) {
            var request = URLRequest(url: url)
            request.httpMethod = method
            if let range { request.setValue(range, forHTTPHeaderField: "Range") }
            let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
            return (data, response as! HTTPURLResponse)
        }

        @Test func aRangeIsServedByteForByte() async throws {
            let (url, server, session) = try await serve()
            let (data, response) = try await get(url, range: "bytes=1048576-3145727")
            #expect(response.statusCode == 206)
            #expect(response.value(forHTTPHeaderField: "Content-Range") == "bytes 1048576-3145727/67108864")
            #expect(data == RangeFileURLProtocol.bytes(1_048_576..<3_145_728))
            await session.close(); server.stop()
        }

        @Test func headAnswersWithoutABody() async throws {
            let (url, server, session) = try await serve()
            let (data, response) = try await get(url, range: "bytes=0-99", method: "HEAD")
            #expect(response.statusCode == 206)
            #expect(response.value(forHTTPHeaderField: "Content-Length") == "100")
            #expect(data.isEmpty)
            await session.close(); server.stop()
        }

        @Test func anUnknownSessionIs404() async throws {
            let (url, server, session) = try await serve()
            let other = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
            #expect(try await get(other, range: nil).1.statusCode == 404)
            await session.close(); server.stop()
        }

        @Test func pastTheEndIs416() async throws {
            let (url, server, session) = try await serve()
            #expect(try await get(url, range: "bytes=99999999999-").1.statusCode == 416)
            await session.close(); server.stop()
        }

        @Test func RDsRefusalReachesLibvlc() async throws {
            RangeFileURLProtocol.reset(.init(statusByPath: ["/f.mkv": 404]))
            let (url, server, session) = try await serve()
            #expect(try await get(url, range: "bytes=0-").1.statusCode == 404)
            await session.close(); server.stop()
        }

        @Test func aClientThatHangsUpMidBodyDoesNotBreakTheNext() async throws {
            let (url, server, session) = try await serve()
            var request = URLRequest(url: url)
            request.setValue("bytes=0-", forHTTPHeaderField: "Range")
            let (bytes, _) = try await URLSession(configuration: .ephemeral).bytes(for: request)
            var seen = 0
            for try await _ in bytes { seen += 1; if seen > 100_000 { break } }   // hang up early
            let (data, response) = try await get(url, range: "bytes=5000000-5000999")
            #expect(response.statusCode == 206)
            #expect(data == RangeFileURLProtocol.bytes(5_000_000..<5_001_000))
            await session.close(); server.stop()
        }
    }
}
#endif
