import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct TorBoxClientAddTests {
        init() { MockURLProtocol.handler = nil }

        typealias Recorder = TorBoxClientTests.Recorder

        struct StubKey: AccessTokenProviding {
            func validAccessToken() async throws -> String { "KEY123" }
        }

        private func client() -> TorBoxClient {
            TorBoxClient(http: HTTPClient(session: .mock), tokens: StubKey())
        }

        private static let hash = "ABCDEF0123456789ABCDEF0123456789ABCDEF01"
        private let noSleep: @Sendable (Duration) async throws -> Void = { _ in }

        private static func query(_ r: URLRequest) -> [String: String] {
            let items = URLComponents(url: r.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        }

        private static func form(_ data: Data) -> [String: String] {
            var result: [String: String] = [:]
            for pair in String(decoding: data, as: UTF8.self).split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard kv.count == 2 else { continue }
                result[String(kv[0]).removingPercentEncoding ?? ""] = String(kv[1]).removingPercentEncoding ?? ""
            }
            return result
        }

        private static func torrentJSON(_ id: Int, hash: String = hash, ready: Bool = true) -> String {
            """
            {"id":\(id),"hash":"\(hash)","name":"Movie\(id)","size":1000,"created_at":"2024-03-01T12:00:00Z",
             "download_state":"\(ready ? "cached" : "downloading")","download_finished":\(ready),"download_present":\(ready),
             "progress":\(ready ? 1 : 0.3),"download_speed":0,"seeds":0,
             "files":[{"id":3,"name":"Movie\(id)/Movie\(id).mkv","short_name":"Movie\(id).mkv","size":900,
                       "mimetype":"video/x-matroska","zipped":false}]}
            """
        }

        private static func ok(_ data: String) -> String {
            #"{"success":true,"error":null,"detail":"ok","data":\#(data)}"#
        }

        private static func respond(_ r: URLRequest, status: Int = 200, json: String) -> (HTTPURLResponse, Data) {
            (HTTPURLResponse(url: r.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }

        /// A fake account: `existing` is what `mylist` already holds; `infoAfterCreate` is what the
        /// polled `mylist?id=` answers; `create` answers `createtorrent`.
        private func install(rec: Recorder, existing: [String] = [], infoAfterCreate: String? = nil,
                             createStatus: Int = 200, create: String? = nil) {
            MockURLProtocol.handler = { r in
                rec.record(r)
                let path = r.url?.path ?? ""
                let q = Self.query(r)
                switch path {
                case "/v1/api/torrents/mylist":
                    if q["id"] != nil {
                        return Self.respond(r, json: Self.ok(infoAfterCreate ?? "null"))
                    }
                    let offset = Int(q["offset"] ?? "0") ?? 0
                    return Self.respond(r, json: Self.ok(offset == 0 ? "[\(existing.joined(separator: ","))]" : "[]"))
                case "/v1/api/torrents/createtorrent":
                    return Self.respond(r, status: createStatus,
                                        json: create ?? Self.ok(#"{"torrent_id":7,"hash":"x","auth_id":"00000000-0000-0000-0000-000000000000","queued_id":null}"#))
                case "/v1/api/torrents/controltorrent":
                    return Self.respond(r, json: #"{"success":true,"error":null,"detail":"done","data":null}"#)
                default:
                    return Self.respond(r, status: 404, json: #"{"success":false,"error":"NOPE","detail":"","data":null}"#)
                }
            }
        }

        private func creates(_ rec: Recorder) -> [Int] {
            rec.requests.indices.filter { rec.requests[$0].url?.path == "/v1/api/torrents/createtorrent" }
        }

        // MARK: add

        @Test func addReusesExistingReadyTorrent() async throws {
            let rec = Recorder()
            install(rec: rec, existing: [Self.torrentJSON(5, hash: Self.hash.lowercased())],
                    infoAfterCreate: Self.torrentJSON(5, hash: Self.hash.lowercased()))
            let info = try await client().add(magnetHash: Self.hash)   // upper-case vs lower-case on the account
            #expect(info.id == "tb:5")
            #expect(creates(rec).isEmpty)
        }

        @Test func addCreatesWithOnlyIfCached() async throws {
            let rec = Recorder()
            install(rec: rec, infoAfterCreate: Self.torrentJSON(7))
            let info = try await client().add(magnetHash: Self.hash, maxPollAttempts: 3,
                                              pollInterval: .zero, sleep: noSleep)
            #expect(info.id == "tb:7")
            #expect(info.status == "downloaded")
            let index = try #require(creates(rec).first)
            let req = rec.requests[index]
            #expect(req.httpMethod == "POST")
            #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer KEY123")
            #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
            let form = Self.form(rec.bodies[index])
            #expect(form["magnet"] == "magnet:?xt=urn:btih:\(Self.hash.lowercased())")
            #expect(form["seed"] == "3")
            #expect(form["allow_zip"] == "false")
            #expect(form["add_only_if_cached"] == "true")
        }

        @Test func addPollsUntilDownloaded() async throws {
            let rec = Recorder()
            let polls = Counter()
            MockURLProtocol.handler = { r in
                rec.record(r)
                switch r.url?.path ?? "" {
                case "/v1/api/torrents/createtorrent":
                    return Self.respond(r, json: Self.ok(#"{"torrent_id":7}"#))
                case "/v1/api/torrents/mylist" where Self.query(r)["id"] != nil:
                    let n = polls.next()
                    return Self.respond(r, json: Self.ok(Self.torrentJSON(7, ready: n >= 3)))
                default:
                    return Self.respond(r, json: Self.ok("[]"))
                }
            }
            let info = try await client().add(magnetHash: Self.hash, maxPollAttempts: 5,
                                              pollInterval: .zero, sleep: noSleep)
            #expect(info.status == "downloaded")
            #expect(polls.value == 3)
        }

        @Test func addNotCachedThrowsNotInstant() async throws {
            let rec = Recorder()
            install(rec: rec, createStatus: 400,
                    create: #"{"success":false,"error":"DOWNLOAD_NOT_CACHED","detail":"not cached","data":null}"#)
            await #expect(throws: RDAddError.notInstant(torrentID: "")) {
                _ = try await client().add(magnetHash: Self.hash, maxPollAttempts: 3,
                                           pollInterval: .zero, sleep: noSleep)
            }
        }

        @Test func addBozoTorrentFails() async throws {
            let rec = Recorder()
            install(rec: rec, createStatus: 400,
                    create: #"{"success":false,"error":"BOZO_TORRENT","detail":"bad","data":null}"#)
            await #expect(throws: RDAddError.failed(status: "BOZO_TORRENT", torrentID: "")) {
                _ = try await client().add(magnetHash: Self.hash, maxPollAttempts: 3,
                                           pollInterval: .zero, sleep: noSleep)
            }
        }

        @Test func addOtherAPIErrorsPassThrough() async throws {
            let rec = Recorder()
            install(rec: rec, createStatus: 403,
                    create: #"{"success":false,"error":"PLAN_RESTRICTED_FEATURE","detail":"upgrade","data":null}"#)
            do {
                _ = try await client().add(magnetHash: Self.hash, maxPollAttempts: 3,
                                           pollInterval: .zero, sleep: noSleep)
                Issue.record("expected a throw")
            } catch let error as TorBoxError {
                #expect(error.isPlanRestricted)
            }
        }

        @Test func addTimeoutDeletesAndThrows() async throws {
            let rec = Recorder()
            install(rec: rec, infoAfterCreate: Self.torrentJSON(7, ready: false))
            await #expect(throws: RDAddError.notInstant(torrentID: "tb:7")) {
                _ = try await client().add(magnetHash: Self.hash, maxPollAttempts: 3,
                                           pollInterval: .zero, sleep: noSleep)
            }
            let deleteIndex = try #require(rec.requests.indices.first {
                rec.requests[$0].url?.path == "/v1/api/torrents/controltorrent"
            })
            let body = try #require(JSONSerialization.jsonObject(with: rec.bodies[deleteIndex]) as? [String: Any])
            #expect(body["torrent_id"] as? Int == 7)
            #expect(body["operation"] as? String == "delete")
        }

        @Test func addTerminalErrorStatusDeletesAndFails() async throws {
            let rec = Recorder()
            let errored = Self.torrentJSON(7, ready: false)
                .replacingOccurrences(of: "\"downloading\"", with: "\"error\"")
            install(rec: rec, infoAfterCreate: errored)
            await #expect(throws: RDAddError.failed(status: "error", torrentID: "tb:7")) {
                _ = try await client().add(magnetHash: Self.hash, maxPollAttempts: 3,
                                           pollInterval: .zero, sleep: noSleep)
            }
            #expect(rec.requests.contains { $0.url?.path == "/v1/api/torrents/controltorrent" })
        }

        // MARK: addForDownload

        @Test func addForDownloadOmitsOnlyIfCached() async throws {
            let rec = Recorder()
            install(rec: rec, infoAfterCreate: Self.torrentJSON(7, ready: false))
            let info = try await client().addForDownload(magnetHash: Self.hash)
            #expect(info.id == "tb:7")
            #expect(info.status == "downloading")
            let index = try #require(creates(rec).first)
            let form = Self.form(rec.bodies[index])
            #expect(form["add_only_if_cached"] == nil)
            #expect(form["seed"] == "3")
            #expect(form["allow_zip"] == "false")
            #expect(form["magnet"] == "magnet:?xt=urn:btih:\(Self.hash.lowercased())")
        }

        @Test func addForDownloadReturnsAnExistingTorrentWithoutCreating() async throws {
            let rec = Recorder()
            let existing = Self.torrentJSON(5, hash: Self.hash.lowercased(), ready: false)
            install(rec: rec, existing: [existing], infoAfterCreate: existing)
            let info = try await client().addForDownload(magnetHash: Self.hash)
            #expect(info.id == "tb:5")
            #expect(creates(rec).isEmpty)
        }

        // MARK: checkCached

        @Test func checkCachedChunksAt100() async throws {
            let rec = Recorder()
            MockURLProtocol.handler = { r in
                rec.record(r)
                let index = rec.requests.count - 1
                let sent = (try? JSONSerialization.jsonObject(with: rec.bodies[index]) as? [String: [String]])?["hashes"] ?? []
                // Answer only the even-numbered hashes; keys come back upper-case sometimes.
                let cached = sent.filter { (Int($0.dropFirst()) ?? 1) % 2 == 0 }
                let object = cached.map { "\"\($0.uppercased())\":{\"name\":\"n\",\"size\":1}" }.joined(separator: ",")
                return Self.respond(r, json: Self.ok("{\(object)}"))
            }
            let hashes = (0..<150).map { "h\($0)" }
            let cached = try await client().checkCached(hashes: hashes)
            #expect(rec.requests.count == 2)
            let sizes = try rec.bodies.map { body -> Int in
                let sent = try #require(JSONSerialization.jsonObject(with: body) as? [String: [String]])
                return try #require(sent["hashes"]).count
            }
            #expect(sizes == [100, 50])
            let req = rec.requests[0]
            #expect(req.httpMethod == "POST")
            #expect(req.url?.path == "/v1/api/torrents/checkcached")
            #expect(Self.query(req)["format"] == "object")
            #expect(Self.query(req)["list_files"] == "false")
            #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer KEY123")
            #expect(cached.count == 75)
            #expect(cached.contains("h0") && cached.contains("h148"))
            #expect(!cached.contains("h1"))
        }

        @Test func checkCachedNullDataIsEmpty() async throws {
            MockURLProtocol.handler = { r in
                Self.respond(r, json: #"{"success":true,"error":null,"detail":"none","data":null}"#)
            }
            let cached = try await client().checkCached(hashes: ["abc"])
            #expect(cached.isEmpty)
        }

        @Test func checkCachedWithNoHashesMakesNoRequest() async throws {
            let rec = Recorder()
            MockURLProtocol.handler = { r in rec.record(r); return Self.respond(r, json: Self.ok("null")) }
            let cached = try await client().checkCached(hashes: [])
            #expect(cached.isEmpty)
            #expect(rec.requests.isEmpty)
        }

        /// Thread-safe poll counter for the mock handler.
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var n = 0
            var value: Int { lock.lock(); defer { lock.unlock() }; return n }
            func next() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
        }
    }
}
