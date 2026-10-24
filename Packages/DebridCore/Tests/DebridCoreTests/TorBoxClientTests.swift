import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct TorBoxClientTests {
        init() { MockURLProtocol.handler = nil }

        struct StubKey: AccessTokenProviding {
            func validAccessToken() async throws -> String { "KEY123" }
        }

        private func client() -> TorBoxClient {
            TorBoxClient(http: HTTPClient(session: .mock), tokens: StubKey())
        }

        /// Counts requests thread-safely; the mock handler runs off the test's task.
        final class Recorder: @unchecked Sendable {
            private let lock = NSLock()
            private var _requests: [URLRequest] = []
            private var _bodies: [Data] = []
            var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return _requests }
            var bodies: [Data] { lock.lock(); defer { lock.unlock() }; return _bodies }
            func record(_ r: URLRequest) {
                lock.lock(); defer { lock.unlock() }
                _requests.append(r)
                _bodies.append(Self.body(of: r))
            }
            private static func body(of r: URLRequest) -> Data {
                if let b = r.httpBody { return b }
                guard let stream = r.httpBodyStream else { return Data() }
                stream.open(); defer { stream.close() }
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let n = stream.read(&buffer, maxLength: buffer.count)
                    if n <= 0 { break }
                    data.append(buffer, count: n)
                }
                return data
            }
        }

        private static func query(_ r: URLRequest) -> [String: String] {
            let items = URLComponents(url: r.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        }

        private static func torrentJSON(_ id: Int, name: String = "Movie") -> String {
            """
            {"id":\(id),"hash":"h\(id)","name":"\(name)\(id)","size":1000,"created_at":"2024-03-0\(id % 9 + 1)T12:00:00Z",
             "download_state":"cached","download_finished":true,"download_present":true,"progress":1,
             "download_speed":0,"seeds":0,
             "files":[{"id":3,"name":"\(name)\(id)/\(name)\(id).mkv","short_name":"\(name)\(id).mkv","size":900,
                       "mimetype":"video/x-matroska","zipped":false}]}
            """
        }

        private static func ok(_ data: String) -> String {
            #"{"success":true,"error":null,"detail":"ok","data":\#(data)}"#
        }

        private static func respond(_ r: URLRequest, status: Int = 200, json: String,
                                    headers: [String: String]? = nil) -> (HTTPURLResponse, Data) {
            (HTTPURLResponse(url: r.url!, statusCode: status, httpVersion: nil, headerFields: headers)!,
             Data(json.utf8))
        }

        @Test func listSendsBearerAndBypassCache() async throws {
            let rec = Recorder()
            MockURLProtocol.handler = { r in
                rec.record(r)
                return Self.respond(r, json: Self.ok("[\(Self.torrentJSON(1)),\(Self.torrentJSON(2))]"))
            }
            let torrents = try await client().torrents(page: 1, limit: 50)
            #expect(torrents.map(\.id) == ["tb:1", "tb:2"])
            let req = try #require(rec.requests.first)
            #expect(req.url?.path == "/v1/api/torrents/mylist")
            let q = Self.query(req)
            #expect(q["bypass_cache"] == "true")
            #expect(q["offset"] == "0")
            #expect(q["limit"] == "50")
            #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer KEY123")
            #expect(req.httpMethod == "GET")
        }

        @Test func secondPageUsesOffset() async throws {
            let rec = Recorder()
            MockURLProtocol.handler = { r in rec.record(r); return Self.respond(r, json: Self.ok("[]")) }
            _ = try await client().torrents(page: 3, limit: 50)
            #expect(Self.query(try #require(rec.requests.first))["offset"] == "100")
        }

        @Test func allTorrentsPagesUntilShortPage() async throws {
            let rec = Recorder()
            MockURLProtocol.handler = { r in
                rec.record(r)
                let offset = Int(Self.query(r)["offset"] ?? "") ?? -1
                let page: String
                switch offset {
                case 0: page = "[\(Self.torrentJSON(1)),\(Self.torrentJSON(2))]"
                case 2: page = "[\(Self.torrentJSON(3))]"
                default: page = "[]"
                }
                return Self.respond(r, json: Self.ok(page))
            }
            let all = try await client().allTorrents(pageSize: 2)
            #expect(all.map(\.id) == ["tb:1", "tb:2", "tb:3"])
            #expect(rec.requests.count == 2)
        }

        @Test func allTorrentsDefaultPageSizeIs1000() async throws {
            let rec = Recorder()
            MockURLProtocol.handler = { r in rec.record(r); return Self.respond(r, json: Self.ok("[]")) }
            _ = try await client().allTorrents()
            #expect(Self.query(try #require(rec.requests.first))["limit"] == "1000")
        }

        @Test func infoDecodesSingleObject() async throws {
            let rec = Recorder()
            MockURLProtocol.handler = { r in rec.record(r); return Self.respond(r, json: Self.ok(Self.torrentJSON(7))) }
            let info = try await client().info(id: "tb:7")
            #expect(info.id == "tb:7")
            #expect(info.links == ["torbox://tb:7/3"])
            let q = Self.query(try #require(rec.requests.first))
            #expect(q["id"] == "7")
            #expect(q["bypass_cache"] == "true")
        }

        @Test func infoAlsoDecodesAnArray() async throws {
            MockURLProtocol.handler = { r in Self.respond(r, json: Self.ok("[\(Self.torrentJSON(7))]")) }
            let info = try await client().info(id: "tb:7")
            #expect(info.id == "tb:7")
        }

        @Test func infoForARealDebridIDIsABadID() async throws {
            MockURLProtocol.handler = { r in Self.respond(r, json: Self.ok("null")) }
            do {
                _ = try await client().info(id: "ABC")
                Issue.record("expected BAD_ID")
            } catch let TorBoxError.api(code, _, _) {
                #expect(code == "BAD_ID")
            }
        }

        @Test func allTorrentInfosMakesOneListCall() async throws {
            let rec = Recorder()
            MockURLProtocol.handler = { r in
                rec.record(r)
                return Self.respond(r, json: Self.ok("[\(Self.torrentJSON(1)),\(Self.torrentJSON(2)),\(Self.torrentJSON(3)),\(Self.torrentJSON(4))]"))
            }
            let list = [1, 2, 3].map { id in
                Torrent(id: "tb:\(id)", filename: "x", hash: "h", bytes: 1, host: "torbox", progress: 100,
                        status: "downloaded", added: "", links: [])
            }
            let infos = try await client().allTorrentInfos(from: list)
            #expect(rec.requests.count == 1)
            #expect(infos.map(\.id) == ["tb:1", "tb:2", "tb:3"])
            #expect(infos[0].added == "2024-03-02T12:00:00Z")
            #expect(infos[0].links == ["torbox://tb:1/3"])
        }

        @Test func allTorrentInfosForAnEmptyListMakesNoRequest() async throws {
            let rec = Recorder()
            MockURLProtocol.handler = { r in rec.record(r); return Self.respond(r, json: Self.ok("[]")) }
            let infos = try await client().allTorrentInfos(from: [])
            #expect(infos.isEmpty)
            #expect(rec.requests.isEmpty)
        }

        @Test func unrestrictCallsRequestdlWithIDs() async throws {
            let rec = Recorder()
            MockURLProtocol.handler = { r in
                rec.record(r)
                return Self.respond(r, json: Self.ok(#""https://cdn.torbox.example/stream/abc""#))
            }
            let link = try await client().unrestrict(link: "torbox://tb:7/3")
            #expect(link.download == "https://cdn.torbox.example/stream/abc")
            let req = try #require(rec.requests.first)
            #expect(req.url?.path == "/v1/api/torrents/requestdl")
            let q = Self.query(req)
            #expect(q["torrent_id"] == "7")
            #expect(q["file_id"] == "3")
            #expect(q["token"] == "KEY123")
        }

        @Test func unrestrictRejectsANonTorBoxLink() async throws {
            MockURLProtocol.handler = { r in Self.respond(r, json: Self.ok(#""x""#)) }
            do {
                _ = try await client().unrestrict(link: "https://real-debrid.com/d/X")
                Issue.record("expected BAD_LINK")
            } catch let TorBoxError.api(code, _, status) {
                #expect(code == "BAD_LINK")
                #expect(status == 400)
            }
        }

        @Test func playableURLUnrestrictsThePrimaryVideoFile() async throws {
            let rec = Recorder()
            MockURLProtocol.handler = { r in
                rec.record(r)
                return Self.respond(r, json: Self.ok(#""https://cdn.torbox.example/stream/p""#))
            }
            let info = TorBoxMapping.info(try {
                let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase
                return try d.decode(TorBoxTorrent.self, from: Data(Self.torrentJSON(7).utf8))
            }())
            let link = try await client().playableURL(for: info)
            #expect(link?.download == "https://cdn.torbox.example/stream/p")
            #expect(Self.query(try #require(rec.requests.first))["file_id"] == "3")
        }

        @Test func deleteSendsControlTorrent() async throws {
            let rec = Recorder()
            MockURLProtocol.handler = { r in
                rec.record(r)
                return Self.respond(r, json: #"{"success":true,"error":null,"detail":"done","data":null}"#)
            }
            try await client().deleteTorrent(id: "tb:7")
            let req = try #require(rec.requests.first)
            #expect(req.httpMethod == "POST")
            #expect(req.url?.path == "/v1/api/torrents/controltorrent")
            #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer KEY123")
            let bodyData = try #require(rec.bodies.first)
            let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            #expect(body["torrent_id"] as? Int == 7)
            #expect(body["operation"] as? String == "delete")
        }

        @Test func userReadsMe() async throws {
            let rec = Recorder()
            MockURLProtocol.handler = { r in
                rec.record(r)
                return Self.respond(r, json: Self.ok(#"{"id":1,"plan":2,"email":"a@b.c","premium_expires_at":"2027-01-01T00:00:00Z"}"#))
            }
            let user = try await client().user()
            #expect(user.plan == 2)
            #expect(user.planName == "Pro")
            let req = try #require(rec.requests.first)
            #expect(req.url?.path == "/v1/api/user/me")
            #expect(Self.query(req)["settings"] == "false")
        }

        @Test func planRestrictedMapsToTorBoxError() async throws {
            MockURLProtocol.handler = { r in
                Self.respond(r, status: 403, json: #"{"success":false,"error":"PLAN_RESTRICTED_FEATURE","detail":"upgrade","data":null}"#)
            }
            do {
                _ = try await client().allTorrents()
                Issue.record("expected a throw")
            } catch let error as TorBoxError {
                #expect(error.isPlanRestricted)
                #expect(!error.isAuthRejection)
                #expect(error == .api(code: "PLAN_RESTRICTED_FEATURE", detail: "upgrade", status: 403))
            }
        }

        @Test func badTokenIsAuthRejection() async throws {
            MockURLProtocol.handler = { r in
                Self.respond(r, status: 403, json: #"{"success":false,"error":"BAD_TOKEN","detail":"bad","data":null}"#)
            }
            do {
                _ = try await client().user()
                Issue.record("expected a throw")
            } catch let error as TorBoxError {
                #expect(error.isAuthRejection)
            }
        }

        @Test func rateLimitedThrowsWithoutRetry() async throws {
            let rec = Recorder()
            MockURLProtocol.handler = { r in
                rec.record(r)
                return Self.respond(r, status: 429, json: #"{"success":false,"error":"RATE_LIMITED","detail":"slow down","data":null}"#,
                                    headers: ["Retry-After": "300"])
            }
            do {
                _ = try await client().allTorrents()
                Issue.record("expected a throw")
            } catch let error as TorBoxError {
                // retryAfter is expected nil until HTTPError carries response headers.
                guard case .rateLimited = error else { Issue.record("got \(error)"); return }
            }
            #expect(rec.requests.count == 1)
        }

        @Test func successFalseWith200Throws() async throws {
            MockURLProtocol.handler = { r in
                Self.respond(r, json: #"{"success":false,"error":"DATABASE_ERROR","detail":"oops","data":null}"#)
            }
            do {
                _ = try await client().allTorrents()
                Issue.record("expected a throw")
            } catch let error as TorBoxError {
                #expect(error == .api(code: "DATABASE_ERROR", detail: "oops", status: 200))
            }
        }

        @Test func nonEnvelopeErrorBodyStillThrowsAPIError() async throws {
            MockURLProtocol.handler = { r in Self.respond(r, status: 502, json: "<html>bad gateway</html>") }
            do {
                _ = try await client().allTorrents()
                Issue.record("expected a throw")
            } catch let error as TorBoxError {
                guard case .api(_, _, let status) = error else { Issue.record("got \(error)"); return }
                #expect(status == 502)
            }
        }
    }
}
