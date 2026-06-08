import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct OpenSubtitlesDownloadTests {
        init() { MockURLProtocol.handler = nil }

        /// A provider with an isolated, unique on-disk cache dir so tests don't share cached files.
        private func makeProvider() -> (OpenSubtitlesProvider, URL) {
            let dir = FileManager.default.temporaryDirectory.appending(path: "ostest-\(UUID().uuidString)")
            let p = OpenSubtitlesProvider(apiKey: "K",
                                          credentials: .init(username: "u", password: "p"),
                                          http: HTTPClient(session: .mock), cacheDirectory: dir)
            return (p, dir)
        }
        private func provider() -> OpenSubtitlesProvider { makeProvider().0 }
        private func result(_ id: Int) -> SubtitleResult {
            SubtitleResult(fileID: id, language: "he")
        }
        private static func resp(_ req: URLRequest, _ status: Int, _ body: String) -> (HTTPURLResponse, Data) {
            (HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }

        @Test func downloadWritesTempFileWithBytes() async throws {
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/login")    { return Self.resp(req, 200, #"{"token":"T1"}"#) }
                if url.contains("/download") { return Self.resp(req, 200, #"{"link":"https://cdn.example/x.srt","file_name":"x.srt","remaining":10}"#) }
                if url.contains("cdn.example/x.srt") { return Self.resp(req, 200, "SUBTITLE-CONTENT") }
                return Self.resp(req, 200, "{}")
            }
            let url = try await provider().download(result(1))
            #expect(url.isFileURL)
            #expect(try String(contentsOf: url, encoding: .utf8) == "SUBTITLE-CONTENT")
        }

        @Test func tempFileNameIsPathSafeAndKeepsExtension() async throws {
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/login")    { return Self.resp(req, 200, #"{"token":"T1"}"#) }
                if url.contains("/download") { return Self.resp(req, 200, #"{"link":"https://cdn.example/s.vtt","file_name":"../../../etc/evil.vtt","remaining":7}"#) }
                if url.contains("cdn.example/s.vtt") { return Self.resp(req, 200, "X") }
                return Self.resp(req, 200, "{}")
            }
            let (p, dir) = makeProvider()
            let url = try await p.download(result(1))
            #expect(url.pathExtension == "vtt")                          // safe extension preserved
            #expect(!url.lastPathComponent.contains("etc"))             // hostile name did NOT leak into the path
            #expect(!url.lastPathComponent.contains(".."))
            #expect(url.path.hasPrefix(dir.path))                        // stayed in the cache dir
        }

        @Test func tokenIsCachedAcrossDownloads() async throws {
            let p = provider()
            MockURLProtocol.handler = { req in   // 1st download: login succeeds, token cached
                let url = req.url!.absoluteString
                if url.contains("/login")    { return Self.resp(req, 200, #"{"token":"T1"}"#) }
                if url.contains("/download") { return Self.resp(req, 200, #"{"link":"https://cdn.example/a.srt","remaining":10}"#) }
                if url.contains("cdn.example/a.srt") { return Self.resp(req, 200, "A") }
                return Self.resp(req, 200, "{}")
            }
            _ = try await p.download(result(1))
            // 2nd download: /login now 500s. If the token weren't cached, re-login would fail the call.
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/login")    { return Self.resp(req, 500, "{}") }
                if url.contains("/download") { return Self.resp(req, 200, #"{"link":"https://cdn.example/b.srt","remaining":9}"#) }
                if url.contains("cdn.example/b.srt") { return Self.resp(req, 200, "B") }
                return Self.resp(req, 200, "{}")
            }
            let url = try await p.download(result(2))
            #expect(try String(contentsOf: url, encoding: .utf8) == "B")   // succeeded ⇒ cached token, no re-login
        }

        @Test func reusesCachedFileWithoutReDownloading() async throws {
            let (p, _) = makeProvider()
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/login")    { return Self.resp(req, 200, #"{"token":"T1"}"#) }
                if url.contains("/download") { return Self.resp(req, 200, #"{"link":"https://cdn.example/c.srt","file_name":"c.srt","remaining":10}"#) }
                if url.contains("cdn.example/c.srt") { return Self.resp(req, 200, "CACHED") }
                return Self.resp(req, 200, "{}")
            }
            let first = try await p.download(result(42))
            #expect(try String(contentsOf: first, encoding: .utf8) == "CACHED")

            // Make EVERY network call fail. A cache hit must serve the file without touching the
            // network (so no `POST /download`, no daily-quota spend) and return the same file.
            MockURLProtocol.handler = { req in Self.resp(req, 500, "{}") }
            let second = try await p.download(result(42))
            #expect(second.lastPathComponent == first.lastPathComponent)   // same cached file (symlink-safe)
            #expect(try String(contentsOf: second, encoding: .utf8) == "CACHED")
        }
    }
}
