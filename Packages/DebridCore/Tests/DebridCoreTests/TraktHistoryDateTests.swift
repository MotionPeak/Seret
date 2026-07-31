import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct TraktHistoryDateTests {
        init() { MockURLProtocol.handler = nil }

        // Single-page history: page-count 1 → the one row's watched_at is the answer.
        @Test func singlePageReturnsOldestRow() async throws {
            MockURLProtocol.handler = { request in
                let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: ["X-Pagination-Page-Count": "1"])!
                return (response, Data(#"[{"id":1,"watched_at":"2019-04-14T20:00:00.000Z"}]"#.utf8))
            }
            let client = TraktClient(clientID: "c", clientSecret: "s",
                                     http: HTTPClient(session: .mock),
                                     token: { "tok" })
            let date = try await client.firstHistoryDate(type: "movies", traktID: 99)
            let comps = Calendar(identifier: .gregorian)
                .dateComponents(in: TimeZone(identifier: "UTC")!, from: try #require(date))
            #expect(comps.year == 2019 && comps.month == 4 && comps.day == 14)
        }

        // Multi-page: must fetch the LAST page (oldest, since history is newest-first).
        @Test func multiPageFetchesLastPage() async throws {
            var pagesRequested: [String] = []
            MockURLProtocol.handler = { request in
                let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "page" })?.value ?? "?"
                pagesRequested.append(page)
                let body = page == "1"
                    ? #"[{"id":9,"watched_at":"2024-01-01T00:00:00Z"}]"#      // newest (page 1)
                    : #"[{"id":1,"watched_at":"2016-06-05T09:30:00Z"}]"#      // oldest (last page)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: ["X-Pagination-Page-Count": "5"])!
                return (response, Data(body.utf8))
            }
            let client = TraktClient(clientID: "c", clientSecret: "s",
                                     http: HTTPClient(session: .mock),
                                     token: { "tok" })
            let date = try await client.firstHistoryDate(type: "movies", traktID: 7)
            #expect(pagesRequested == ["1", "5"])
            let comps = Calendar(identifier: .gregorian)
                .dateComponents(in: TimeZone(identifier: "UTC")!, from: try #require(date))
            #expect(comps.year == 2016)   // the last page's row, not page 1's
        }

        // A timestamp WITHOUT fractional seconds must still parse (this is a real Trakt
        // variation; a .withFractionalSeconds-only formatter silently returns nil).
        @Test func parsesNonFractionalTimestamp() async throws {
            MockURLProtocol.handler = { request in
                let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: ["X-Pagination-Page-Count": "1"])!
                return (response, Data(#"[{"id":1,"watched_at":"2020-12-31T23:59:59Z"}]"#.utf8))
            }
            let client = TraktClient(clientID: "c", clientSecret: "s",
                                     http: HTTPClient(session: .mock),
                                     token: { "tok" })
            let date = try await client.firstHistoryDate(type: "movies", traktID: 1)
            #expect(date != nil)
        }

        // No history rows at all → nil, not a crash.
        @Test func emptyHistoryReturnsNil() async throws {
            MockURLProtocol.handler = { request in
                let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: ["X-Pagination-Page-Count": "1"])!
                return (response, Data("[]".utf8))
            }
            let client = TraktClient(clientID: "c", clientSecret: "s",
                                     http: HTTPClient(session: .mock),
                                     token: { "tok" })
            let date = try await client.firstHistoryDate(type: "movies", traktID: 1)
            #expect(date == nil)
        }

        // Trakt omits the pagination header → we cannot know whether this row is the
        // oldest, so we must decline. Reporting page 1's row would present the NEWEST
        // watch as the oldest — a confidently wrong "in your history since <date>".
        @Test func missingPaginationHeaderReturnsNilRatherThanTheNewestDate() async throws {
            MockURLProtocol.handler = { request in
                // No X-Pagination-Page-Count at all.
                let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: nil)!
                return (response, Data(#"[{"id":9,"watched_at":"2024-01-01T00:00:00Z"}]"#.utf8))
            }
            let client = TraktClient(clientID: "c", clientSecret: "s",
                                     http: HTTPClient(session: .mock),
                                     token: { "tok" })
            let date = try await client.firstHistoryDate(type: "movies", traktID: 7)
            #expect(date == nil)   // must NOT report 2024 as "in your history since"
        }

        // Same reasoning for a header we can't parse as a number.
        @Test func unparseablePaginationHeaderReturnsNil() async throws {
            MockURLProtocol.handler = { request in
                let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: ["X-Pagination-Page-Count": "abc"])!
                return (response, Data(#"[{"id":9,"watched_at":"2024-01-01T00:00:00Z"}]"#.utf8))
            }
            let client = TraktClient(clientID: "c", clientSecret: "s",
                                     http: HTTPClient(session: .mock),
                                     token: { "tok" })
            let date = try await client.firstHistoryDate(type: "movies", traktID: 7)
            #expect(date == nil)
        }

        // A timestamp in no recognized format → nil, not a garbage date.
        @Test func unparseableWatchedAtReturnsNil() async throws {
            MockURLProtocol.handler = { request in
                let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: ["X-Pagination-Page-Count": "1"])!
                return (response, Data(#"[{"id":1,"watched_at":"not-a-date"}]"#.utf8))
            }
            let client = TraktClient(clientID: "c", clientSecret: "s",
                                     http: HTTPClient(session: .mock),
                                     token: { "tok" })
            let date = try await client.firstHistoryDate(type: "movies", traktID: 1)
            #expect(date == nil)
        }
    }
}
