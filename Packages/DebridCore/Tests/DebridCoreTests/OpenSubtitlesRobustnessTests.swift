import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct OpenSubtitlesRobustnessTests {
        init() { MockURLProtocol.handler = nil }

        private func provider() -> OpenSubtitlesProvider {
            // Each provider gets an isolated cache dir so a successful download in one test can't be
            // served from cache (and skip the network) in another that reuses the same file id.
            OpenSubtitlesProvider(apiKey: "K",
                                  credentials: .init(username: "u", password: "p"),
                                  http: HTTPClient(session: .mock),
                                  cacheDirectory: FileManager.default.temporaryDirectory
                                      .appending(path: "ostest-\(UUID().uuidString)"))
        }
        private func result(_ id: Int) -> SubtitleResult { SubtitleResult(fileID: id, language: "he") }
        private static func resp(_ req: URLRequest, _ status: Int, _ body: String) -> (HTTPURLResponse, Data) {
            (HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }

        /// `remaining: 0` alongside a link means "here is your file, and that was your last one
        /// today" — OpenSubtitles charges the quota for the POST and answers 200 with the link;
        /// being genuinely out of downloads is a 406, which `dailyCapWhenForbidden` covers. So the
        /// link must be USED. Throwing it away spent a download and delivered nothing, which made
        /// the last subtitle of every day fail for no reason.
        @Test func theFinalDownloadOfTheDayIsStillDelivered() async throws {
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/login")    { return Self.resp(req, 200, #"{"token":"T1"}"#) }
                if url.contains("/download") { return Self.resp(req, 200, #"{"link":"https://cdn/x.srt","remaining":0,"reset_time_utc":"2026-06-03T00:00:00Z"}"#) }
                if url.contains("cdn")       { return Self.resp(req, 200, "1\n00:00:01,000 --> 00:00:02,000\nhi\n") }
                return Self.resp(req, 200, "{}")
            }
            let url = try await provider().download(result(1))
            #expect(FileManager.default.fileExists(atPath: url.path))
        }

        /// …but a capped response with nothing usable in it is still a cap.
        @Test func dailyCapWhenRemainingZeroAndNoLink() async throws {
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/login")    { return Self.resp(req, 200, #"{"token":"T1"}"#) }
                if url.contains("/download") { return Self.resp(req, 200, #"{"link":"","remaining":0,"reset_time_utc":"2026-06-03T00:00:00Z"}"#) }
                return Self.resp(req, 200, "{}")
            }
            do {
                _ = try await provider().download(result(1))
                Issue.record("expected dailyCapReached to be thrown")
            } catch {
                guard case let SubtitleError.dailyCapReached(reset) = error else {
                    Issue.record("expected .dailyCapReached, got \(error)"); return
                }
                #expect(reset != nil)   // reset_time_utc ("2026-06-03T00:00:00Z") was parsed + threaded through
            }
        }

        @Test func dailyCapWhenForbidden() async throws {
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/login")    { return Self.resp(req, 200, #"{"token":"T1"}"#) }
                if url.contains("/download") { return Self.resp(req, 403, "{}") }
                return Self.resp(req, 200, "{}")
            }
            do {
                _ = try await provider().download(result(1))
                Issue.record("expected dailyCapReached to be thrown")
            } catch {
                guard case SubtitleError.dailyCapReached = error else {
                    Issue.record("expected .dailyCapReached, got \(error)"); return
                }
            }
        }

        @Test func recoversFromExpiredTokenViaRelogin() async throws {
            let p = provider()
            // prime: cache token T1 with a successful download
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/login")    { return Self.resp(req, 200, #"{"token":"T1"}"#) }
                if url.contains("/download") { return Self.resp(req, 200, #"{"link":"https://cdn/a.srt","remaining":9}"#) }
                if url.contains("cdn/a.srt") { return Self.resp(req, 200, "A") }
                return Self.resp(req, 200, "{}")
            }
            _ = try await p.download(result(1))
            // T1 is now stale: a download bearing T1 → 401; re-login yields T2; T2 → 200.
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                let auth = req.value(forHTTPHeaderField: "Authorization") ?? ""
                if url.contains("/login")    { return Self.resp(req, 200, #"{"token":"T2"}"#) }
                if url.contains("/download") {
                    return auth.contains("T2")
                        ? Self.resp(req, 200, #"{"link":"https://cdn/c.srt","remaining":5}"#)
                        : Self.resp(req, 401, "{}")
                }
                if url.contains("cdn/c.srt") { return Self.resp(req, 200, "C") }
                return Self.resp(req, 200, "{}")
            }
            let url = try await p.download(result(2))
            #expect(try String(contentsOf: url, encoding: .utf8) == "C")   // 401 → re-login → success
        }

        // Item 1 test
        @Test func loginFailureSurfacesNotAuthenticated() async throws {
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/login") { return Self.resp(req, 401, "{}") }
                return Self.resp(req, 200, "{}")
            }
            do {
                _ = try await provider().download(result(1))
                Issue.record("expected notAuthenticated to be thrown")
            } catch {
                guard case SubtitleError.notAuthenticated = error else {
                    Issue.record("expected .notAuthenticated, got \(error)"); return
                }
            }
        }

        // Item 2: malformed download link → .invalidResponse
        @Test func malformedDownloadLinkThrowsInvalidResponse() async throws {
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/login")    { return Self.resp(req, 200, #"{"token":"T1"}"#) }
                if url.contains("/download") { return Self.resp(req, 200, #"{"link":"","remaining":10}"#) }
                return Self.resp(req, 200, "{}")
            }
            do {
                _ = try await provider().download(result(1))
                Issue.record("expected invalidResponse to be thrown")
            } catch {
                guard case SubtitleError.invalidResponse = error else {
                    Issue.record("expected .invalidResponse, got \(error)"); return
                }
            }
        }

        // Item 3: 406 also maps to the daily cap
        @Test func dailyCapWhenNotAcceptable() async throws {
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/login")    { return Self.resp(req, 200, #"{"token":"T1"}"#) }
                if url.contains("/download") { return Self.resp(req, 406, "{}") }
                return Self.resp(req, 200, "{}")
            }
            do {
                _ = try await provider().download(result(1))
                Issue.record("expected dailyCapReached to be thrown")
            } catch {
                guard case SubtitleError.dailyCapReached = error else {
                    Issue.record("expected .dailyCapReached, got \(error)"); return
                }
            }
        }
    }
}
