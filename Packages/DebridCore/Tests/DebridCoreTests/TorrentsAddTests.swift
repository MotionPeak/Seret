import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct TorrentsAddTests {
        init() { MockURLProtocol.handler = nil }

        struct StubTokens: AccessTokenProviding {
            func validAccessToken() async throws -> String { "TESTTOKEN" }
        }

        @Test func addMagnetReturnsTorrentID() async throws {
            MockURLProtocol.handler = { request in
                #expect(request.url?.path.hasSuffix("/torrents/addMagnet") == true)
                #expect(request.bodyString().contains("magnet"))
                let response = HTTPURLResponse(url: request.url!, statusCode: 201,
                                               httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"id":"NEWID","uri":"https://rd/t/NEWID"}"#.utf8))
            }
            let client = TorrentsClient(http: HTTPClient(session: .mock), tokens: StubTokens())
            let result = try await client.addMagnet(magnet: "magnet:?xt=urn:btih:abc")
            #expect(result.id == "NEWID")
        }

        @Test func selectFilesPostsAllAndSucceedsOn204() async throws {
            MockURLProtocol.handler = { request in
                #expect(request.url?.path.contains("/torrents/selectFiles/NEWID") == true)
                #expect(request.bodyString().contains("files=all"))
                let response = HTTPURLResponse(url: request.url!, statusCode: 204,
                                               httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
            let client = TorrentsClient(http: HTTPClient(session: .mock), tokens: StubTokens())
            try await client.selectFiles(torrentID: "NEWID", files: "all")
        }

        // Drives add(): addMagnet → info(waiting) → selectFiles → info(downloaded).
        @Test func addInstantCachedReturnsDownloadedInfo() async throws {
            let infoWaiting = #"{"id":"NEWID","filename":"M","hash":"h","bytes":1,"progress":0,"status":"waiting_files_selection","files":[{"id":1,"path":"/M/m.mkv","bytes":1,"selected":0}],"links":[]}"#
            let infoDone = #"{"id":"NEWID","filename":"M","hash":"h","bytes":1,"progress":100,"status":"downloaded","files":[{"id":1,"path":"/M/m.mkv","bytes":1,"selected":1}],"links":["https://rd/d/X"]}"#
            let counter = Counter()
            MockURLProtocol.handler = { request in
                let path = request.url?.path ?? ""
                if path.hasSuffix("/torrents/addMagnet") {
                    let r = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
                    return (r, Data(#"{"id":"NEWID","uri":"u"}"#.utf8))
                }
                if path.contains("/torrents/selectFiles/") {
                    let r = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
                    return (r, Data())
                }
                // /torrents/info/NEWID — first call waiting, subsequent calls downloaded.
                let json = counter.next() == 0 ? infoWaiting : infoDone
                let r = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (r, Data(json.utf8))
            }
            let client = TorrentsClient(http: HTTPClient(session: .mock), tokens: StubTokens())
            let info = try await client.add(magnetHash: "abc", pollInterval: .zero, sleep: { _ in })
            #expect(info.status == "downloaded")
            #expect(info.id == "NEWID")
        }

        @Test func addThrowsNotInstantWhenNeverDownloaded() async throws {
            let infoDownloading = #"{"id":"NEWID","filename":"M","hash":"h","bytes":1,"progress":5,"status":"downloading","files":[{"id":1,"path":"/M/m.mkv","bytes":1,"selected":1}],"links":[]}"#
            MockURLProtocol.handler = { request in
                let path = request.url?.path ?? ""
                if path.hasSuffix("/torrents/addMagnet") {
                    let r = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
                    return (r, Data(#"{"id":"NEWID"}"#.utf8))
                }
                if path.contains("/torrents/selectFiles/") {
                    let r = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
                    return (r, Data())
                }
                let r = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (r, Data(infoDownloading.utf8))
            }
            let client = TorrentsClient(http: HTTPClient(session: .mock), tokens: StubTokens())
            await #expect(throws: RDAddError.self) {
                _ = try await client.add(magnetHash: "abc", maxPollAttempts: 3, pollInterval: .zero, sleep: { _ in })
            }
        }
    }
}

/// Thread-safe call counter for sequencing mock responses.
final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; let v = n; n += 1; return v }
}
