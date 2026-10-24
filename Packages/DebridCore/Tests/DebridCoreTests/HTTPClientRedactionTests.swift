import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import DebridCore

/// A transport failure's description used to be `String(describing: URLError)`, which carries the
/// failing URL — and TorBox's `requestdl` puts the account key in that URL's query. Every such
/// description ends up in a log (the stream proxy's, the server's), so it must never name the URL.
extension MockTests {
    @Suite struct HTTPClientRedactionTests {
        init() { MockURLProtocol.handler = nil }

        struct StubKey: AccessTokenProviding {
            func validAccessToken() async throws -> String { "SECRETKEY" }
        }

        /// A failure shaped like the real one: URLSession puts the failing URL in `userInfo`.
        private static func timeout(for request: URLRequest) -> URLError {
            URLError(.timedOut, userInfo: [
                NSURLErrorFailingURLErrorKey: request.url!,
                NSURLErrorFailingURLStringErrorKey: request.url!.absoluteString,
            ])
        }

        @Test func transportFailureDoesNotNameTheURL() async throws {
            MockURLProtocol.handler = { r in throw Self.timeout(for: r) }
            let url = URL(string: "https://api.torbox.app/v1/api/torrents/requestdl?token=SECRETKEY&file_id=1")!
            do {
                _ = try await HTTPClient(session: .mock).data(url)
                Issue.record("expected a throw")
            } catch {
                let text = String(describing: error) + String(reflecting: error)
                #expect(!text.contains("SECRETKEY"))
                #expect(!text.contains("requestdl"))
                guard case HTTPError.transport(let message) = error else {
                    Issue.record("expected .transport, got \(type(of: error))"); return
                }
                // Still says what went wrong, so a log line is useful.
                #expect(message.contains("\(URLError.Code.timedOut.rawValue)"))
            }
        }

        @Test func transportFailureOnEveryVerbIsRedacted() async throws {
            MockURLProtocol.handler = { r in throw Self.timeout(for: r) }
            let url = URL(string: "https://example.com/x?api_key=SECRETKEY")!
            let client = HTTPClient(session: .mock)
            struct Body: Codable { let a: Int }
            let calls: [() async throws -> Void] = [
                { let _: Body = try await client.get(url) },
                { let _: Body = try await client.post(url, form: [:]) },
                { let _: Body = try await client.post(url, json: Body(a: 1)) },
                { _ = try await client.postFormData(url, form: [:]) },
                { _ = try await client.postJSONData(url, json: Body(a: 1)) },
                { try await client.postJSON(url, json: Body(a: 1)) },
                { try await client.postJSON(url, jsonBody: "{}") },
                { try await client.postForm(url, form: [:]) },
                { try await client.delete(url) },
            ]
            for call in calls {
                do {
                    try await call()
                    Issue.record("expected a throw")
                } catch {
                    #expect(!String(reflecting: error).contains("SECRETKEY"))
                }
            }
        }

        @Test func torBoxUnrestrictTransportFailureDoesNotLeakTheKey() async throws {
            MockURLProtocol.handler = { r in throw Self.timeout(for: r) }
            let client = TorBoxClient(http: HTTPClient(session: .mock), tokens: StubKey())
            do {
                _ = try await client.unrestrict(link: TorBoxMapping.link(torrentID: 7, fileID: 3))
                Issue.record("expected a throw")
            } catch {
                #expect(!String(describing: error).contains("SECRETKEY"))
                #expect(!String(reflecting: error).contains("SECRETKEY"))
            }
        }

        @Test func redactionStripsAnyURL() {
            let text = HTTPClient.redactingURLs(
                "failed for https://api.torbox.app/v1/x?token=SECRETKEY, then http://a.b/c")
            #expect(!text.contains("SECRETKEY"))
            #expect(!text.contains("api.torbox.app"))
            #expect(text.hasPrefix("failed for "))
        }
    }
}
