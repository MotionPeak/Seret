import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct TraktClientSyncTests {
        init() { MockURLProtocol.handler = nil }

        @Test func playbackMoviesDecodes() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            [{"progress":35.5,"paused_at":"2026-07-24T10:00:00.000Z","id":1,"type":"movie",
              "movie":{"ids":{"tmdb":27205}}}]
            """#)
            let client = TraktClient(clientID: "c", clientSecret: "s",
                                     http: HTTPClient(session: .mock), token: { "AT" })
            let items = try await client.playbackMovies()
            #expect(items.first?.movie?.ids.tmdb == 27205)
        }

        @Test func addHistorySendsItems() async throws {
            let box = RequestBox()
            MockURLProtocol.handler = { req in
                box.request = req
                return (HTTPURLResponse(url: req.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!,
                        Data(#"{"added":{"movies":1}}"#.utf8))
            }
            let client = TraktClient(clientID: "c", clientSecret: "s",
                                     http: HTTPClient(session: .mock), token: { "AT" })
            try await client.addToHistory([.movie(tmdb: 27205)])
            // Decode the real structure — a substring check passes even when the entry is wrongly
            // wrapped as {"movies":[{"movie":{…}}]}, which Trakt accepts but silently ignores.
            let sent = box.request?.httpBodyStreamData() ?? Data()
            let obj = try JSONSerialization.jsonObject(with: sent) as! [String: Any]
            let movies = obj["movies"] as! [[String: Any]]
            #expect(movies[0]["movie"] == nil)
            #expect((movies[0]["ids"] as! [String: Any])["tmdb"] as! Int == 27205)
        }

        @Test func rateSendsRating() async throws {
            let box = RequestBox()
            MockURLProtocol.handler = { req in
                box.request = req
                return (HTTPURLResponse(url: req.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!,
                        Data(#"{"added":{"movies":1}}"#.utf8))
            }
            let client = TraktClient(clientID: "c", clientSecret: "s",
                                     http: HTTPClient(session: .mock), token: { "AT" })
            try await client.rate(.movie(tmdb: 27205), rating: 8)
            let sent = box.request?.httpBodyStreamData() ?? Data()
            let obj = try JSONSerialization.jsonObject(with: sent) as! [String: Any]
            let movies = obj["movies"] as! [[String: Any]]
            #expect(movies[0]["rating"] as! Int == 8)
            #expect((movies[0]["ids"] as! [String: Any])["tmdb"] as! Int == 27205)
        }
    }
}
