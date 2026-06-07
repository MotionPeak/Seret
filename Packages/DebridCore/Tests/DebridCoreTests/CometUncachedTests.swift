import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct CometUncachedTests {
        init() { MockURLProtocol.handler = nil }

        struct StubTokens: AccessTokenProviding {
            func validAccessToken() async throws -> String { "TESTTOKEN" }
        }

        /// Decodes the `cachedOnly` value from the base64 config segment of a Comet URL.
        private static func cachedOnlyFlag(in url: URL) -> Bool? {
            guard let seg = url.pathComponents.first(where: { $0 != "/" && !$0.isEmpty }),
                  let data = Data(base64Encoded: seg),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return json["cachedOnly"] as? Bool
        }

        private func source() -> CometStreamSource {
            CometStreamSource(http: HTTPClient(session: .mock), tokens: StubTokens())
        }
        private func query() -> StreamQuery {
            StreamQuery(imdbID: "tt0133093", kind: .movie, originalLanguage: "en")
        }

        @Test func includeUncachedSendsCachedOnlyFalse() async throws {
            let box = FlagBox()
            MockURLProtocol.handler = { req in
                box.flag = Self.cachedOnlyFlag(in: req.url!)
                return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                        Data(#"{"streams":[]}"#.utf8))
            }
            _ = try await source().streams(for: query(), includeUncached: true)
            #expect(box.flag == false)
        }

        @Test func defaultStaysCachedOnly() async throws {
            let box = FlagBox()
            MockURLProtocol.handler = { req in
                box.flag = Self.cachedOnlyFlag(in: req.url!)
                return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                        Data(#"{"streams":[]}"#.utf8))
            }
            _ = try await source().streams(for: query())
            #expect(box.flag == true)
        }
    }
}

private final class FlagBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _flag: Bool?
    var flag: Bool? {
        get { lock.lock(); defer { lock.unlock() }; return _flag }
        set { lock.lock(); _flag = newValue; lock.unlock() }
    }
}
