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

        /// Measured on the Apple TV: after the player closed, 163 MB stayed resident. libvlc stops
        /// reading once its own buffer is full, which leaves the server mid-send on a full socket —
        /// and the session can close before libvlc hangs up. That send never completed, and its
        /// task held the closed session, RAM cache and all, for the rest of the app's life (found
        /// in the simulator: the leaked task's frame was `serve`, suspended in `send`).
        @Test func closingASessionEndsASendTheClientStoppedReading() async throws {
            let p = proxy()
            let handle = await p.open(upstream: URL(string: "https://rd.test/f.mkv")!, fileKey: "t#1",
                                      refreshUpstream: { URL(string: "https://rd.test/f.mkv")! })
            weak var session = await p.session(try #require(handle.sessionID))
            #expect(session != nil)

            // A client that asks for the whole file, reads a little, then stops reading — and,
            // like libvlc at stop, has not hung up yet when the player closes the session.
            var input: InputStream?, output: OutputStream?
            Stream.getStreamsToHost(withName: "127.0.0.1", port: try #require(handle.url.port),
                                    inputStream: &input, outputStream: &output)
            let (i, o) = (try #require(input), try #require(output))
            i.open(); o.open()
            defer { i.close(); o.close() }
            let request = Array("GET \(handle.url.path) HTTP/1.1\r\nHost: 127.0.0.1\r\nRange: bytes=0-\r\n\r\n".utf8)
            #expect(o.write(request, maxLength: request.count) == request.count)
            var buffer = [UInt8](repeating: 0, count: 65536)
            #expect(i.read(&buffer, maxLength: buffer.count) > 0)
            try await Task.sleep(for: .milliseconds(500))            // the server fills the socket and blocks

            await p.close(handle)
            for _ in 0..<100 where session != nil { try await Task.sleep(for: .milliseconds(20)) }
            #expect(session == nil)
        }

        @Test func aDirectHandleIsJustTheURL() {
            let url = URL(string: "https://rd.test/f.mkv")!
            #expect(StreamHandle(direct: url).url == url)
        }
    }
}
#endif
