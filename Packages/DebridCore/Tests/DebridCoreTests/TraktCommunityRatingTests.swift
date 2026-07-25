import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct TraktCommunityRatingTests {
        init() { MockURLProtocol.handler = nil }

        @Test func movieRatingHitsPublicEndpointWithApiKeyOnly() async throws {
            var capturedURL: URL?
            var capturedAuth: String?
            MockURLProtocol.handler = { request in
                capturedURL = request.url
                capturedAuth = request.value(forHTTPHeaderField: "Authorization")
                let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                               httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"rating":8.4,"votes":42000}"#.utf8))
            }
            // A token closure IS provided here, so if the implementation ever used authedHeaders()
            // instead of baseHeaders, an Authorization header would appear and this test would catch it.
            let client = TraktClient(clientID: "cid", clientSecret: "sec",
                                     http: HTTPClient(session: .mock), token: { "tok" })
            let r = try await client.communityRating(imdbID: "tt0133093", kind: .movie)
            #expect(r?.rating == 8.4)
            #expect(capturedURL?.path == "/movies/tt0133093/ratings")
            #expect(capturedAuth == nil)          // public endpoint: no Bearer token
        }

        @Test func showRatingUsesShowsPath() async throws {
            var capturedURL: URL?
            MockURLProtocol.handler = { request in
                capturedURL = request.url
                let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                               httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"rating":9.0,"votes":10}"#.utf8))
            }
            let client = TraktClient(clientID: "cid", clientSecret: "sec",
                                     http: HTTPClient(session: .mock))
            _ = try await client.communityRating(imdbID: "tt0944947", kind: .show)
            #expect(capturedURL?.path == "/shows/tt0944947/ratings")
        }
    }
}
