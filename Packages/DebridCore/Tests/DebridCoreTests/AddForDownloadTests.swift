import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct AddForDownloadTests {
        init() { MockURLProtocol.handler = nil }

        struct StubTokens: AccessTokenProviding {
            func validAccessToken() async throws -> String { "T" }
        }
        private func client() -> TorrentsClient {
            TorrentsClient(http: HTTPClient(session: .mock), tokens: StubTokens())
        }
        private static func resp(_ req: URLRequest, _ status: Int, _ json: String) -> (HTTPURLResponse, Data) {
            (HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        // A torrent that is downloading (not cached): files listed, status "downloading", progress 12.
        private static func infoJSON(_ status: String, progress: Int) -> String {
            #"{"id":"TID","filename":"x","hash":"h","bytes":1,"progress":\#(progress),"status":"\#(status)","files":[{"id":1,"path":"/movie.mkv","bytes":1,"selected":0}],"links":[]}"#
        }

        @Test func addsSelectsAndReturnsWithoutWaitingForDownloaded() async throws {
            let selected = SelectFlag()
            MockURLProtocol.handler = { req in
                let u = req.url!.absoluteString
                if u.contains("addMagnet") { return Self.resp(req, 201, #"{"id":"TID","uri":"u"}"#) }
                if u.contains("selectFiles") { selected.value = true; return Self.resp(req, 204, "") }
                if u.contains("/torrents/info/") { return Self.resp(req, 200, Self.infoJSON("downloading", progress: 12)) }
                return Self.resp(req, 200, "{}")
            }
            let info = try await client().addForDownload(magnetHash: "abc", pollInterval: .zero, sleep: { _ in })
            #expect(info.id == "TID")
            #expect(info.status == "downloading")   // returned mid-download, NOT awaited to "downloaded"
            #expect(selected.value == true)         // files were selected
        }

        @Test func exhaustsListAttemptsThenSelectsAndReturns() async throws {
            // A slow-to-hash torrent never lists files within the budget and never errors. The
            // loop exits on the attempt cap; we still selectFiles("all") and return (no throw).
            let selected = SelectFlag()
            MockURLProtocol.handler = { req in
                let u = req.url!.absoluteString
                if u.contains("addMagnet") { return Self.resp(req, 201, #"{"id":"TID","uri":"u"}"#) }
                if u.contains("selectFiles") { selected.value = true; return Self.resp(req, 204, "") }
                if u.contains("/torrents/info/") {
                    return Self.resp(req, 200, #"{"id":"TID","filename":"x","hash":"h","bytes":1,"progress":0,"status":"queued","files":[],"links":[]}"#)
                }
                return Self.resp(req, 200, "{}")
            }
            let info = try await client().addForDownload(magnetHash: "abc", maxListAttempts: 2,
                                                         pollInterval: .zero, sleep: { _ in })
            #expect(selected.value == true)      // selectFiles("all") still fired
            #expect(info.status == "queued")     // returned without throwing
        }

        @Test func terminalStatusDuringListingThrows() async throws {
            MockURLProtocol.handler = { req in
                let u = req.url!.absoluteString
                if u.contains("addMagnet") { return Self.resp(req, 201, #"{"id":"TID","uri":"u"}"#) }
                if u.contains("/torrents/info/") {
                    return Self.resp(req, 200, #"{"id":"TID","filename":"x","hash":"h","bytes":1,"progress":0,"status":"dead","files":[],"links":[]}"#)
                }
                return Self.resp(req, 200, "{}")
            }
            await #expect(throws: RDAddError.self) {
                _ = try await client().addForDownload(magnetHash: "abc", pollInterval: .zero, sleep: { _ in })
            }
        }
    }
}

private final class SelectFlag: @unchecked Sendable {
    private let lock = NSLock(); private var _v = false
    var value: Bool { get { lock.lock(); defer { lock.unlock() }; return _v } set { lock.lock(); _v = newValue; lock.unlock() } }
}
