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

        @Test func addMagnetMapsInfringingFileToBlocked() async throws {
            // RD refuses copyright-flagged torrents with HTTP 451 — surface a distinct .blocked.
            MockURLProtocol.handler = { request in
                let response = HTTPURLResponse(url: request.url!, statusCode: 451,
                                               httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"error":"infringing_file","error_code":35}"#.utf8))
            }
            let client = TorrentsClient(http: HTTPClient(session: .mock), tokens: StubTokens())
            await #expect(throws: RDAddError.blocked) {
                try await client.addMagnet(magnet: "magnet:?xt=urn:btih:abc")
            }
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

        @Test func addSelectsOnlyVideoFilesNotJunk() async throws {
            // A torrent with a video file + thumbnail/metadata junk: selectFiles must get the
            // video file id, NOT "all" (selecting junk breaks RD's file↔link pairing).
            let waiting = #"{"id":"NEWID","filename":"M","hash":"h","bytes":1,"progress":0,"status":"waiting_files_selection","files":[{"id":1,"path":"/M/Movie.mp4","bytes":900,"selected":0},{"id":2,"path":"/M/__ia_thumb.jpg","bytes":1,"selected":0},{"id":3,"path":"/M/meta.sqlite","bytes":1,"selected":0}],"links":[]}"#
            let done = #"{"id":"NEWID","filename":"M","hash":"h","bytes":1,"progress":100,"status":"downloaded","files":[{"id":1,"path":"/M/Movie.mp4","bytes":900,"selected":1}],"links":["https://rd/d/X"]}"#
            let box = SelectBox()
            let counter = Counter()
            MockURLProtocol.handler = { request in
                let path = request.url?.path ?? ""
                if path.hasSuffix("/torrents/addMagnet") {
                    return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, Data(#"{"id":"NEWID"}"#.utf8))
                }
                if path.contains("/torrents/selectFiles/") {
                    box.set(request.bodyString())
                    return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
                }
                let json = counter.next() == 0 ? waiting : done
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
            }
            let client = TorrentsClient(http: HTTPClient(session: .mock), tokens: StubTokens())
            _ = try await client.add(magnetHash: "abc", pollInterval: .zero, sleep: { _ in })
            #expect(box.value.contains("files=1"))
            #expect(!box.value.contains("files=all"))
            #expect(!box.value.contains("2"))   // the .jpg id must NOT be selected
        }

        @Test func addDeletesTorrentWhenNotInstant() async throws {
            let downloading = #"{"id":"NEWID","filename":"M","hash":"h","bytes":1,"progress":5,"status":"downloading","files":[{"id":1,"path":"/M/m.mkv","bytes":1,"selected":1}],"links":[]}"#
            let deleted = DeletedBox()
            MockURLProtocol.handler = { request in
                let path = request.url?.path ?? ""
                if path.hasSuffix("/torrents/addMagnet") {
                    return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, Data(#"{"id":"NEWID"}"#.utf8))
                }
                if path.contains("/torrents/selectFiles/") {
                    return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
                }
                if path.contains("/torrents/delete/NEWID") {
                    deleted.mark()
                    return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
                }
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(downloading.utf8))
            }
            let client = TorrentsClient(http: HTTPClient(session: .mock), tokens: StubTokens())
            await #expect(throws: RDAddError.self) {
                _ = try await client.add(magnetHash: "abc", maxPollAttempts: 2, pollInterval: .zero, sleep: { _ in })
            }
            #expect(deleted.wasDeleted)   // junk torrent cleaned up
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

/// Captures the last selectFiles request body.
final class SelectBox: @unchecked Sendable {
    private let lock = NSLock(); private var s = ""
    func set(_ v: String) { lock.lock(); defer { lock.unlock() }; s = v }
    var value: String { lock.lock(); defer { lock.unlock() }; return s }
}

/// Records whether a delete request was made.
final class DeletedBox: @unchecked Sendable {
    private let lock = NSLock(); private var deleted = false
    func mark() { lock.lock(); defer { lock.unlock() }; deleted = true }
    var wasDeleted: Bool { lock.lock(); defer { lock.unlock() }; return deleted }
}
