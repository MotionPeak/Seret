import Testing
import Foundation
@testable import DebridCore

private final class PathLog: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []

    func record(_ path: String) {
        lock.lock(); defer { lock.unlock() }
        paths.append(path)
    }

    var all: [String] {
        lock.lock(); defer { lock.unlock() }
        return paths
    }
}

extension MockTests {
    @Suite struct LetterboxdProfileReaderTests {
        init() { MockURLProtocol.handler = nil }

        /// Minimal markup in the shape `LetterboxdProfileParser` contracts for.
        func page(_ entries: [(String, Int?)], next: String?) -> String {
            let items = entries.map { slug, rating in
                let ratingSpan = rating.map { "<span class=\"rating rated-\($0)\">x</span>" } ?? ""
                return "<li class=\"griditem\"><div data-item-slug=\"\(slug)\" data-item-name=\"\(slug) (2000)\"></div><p class=\"poster-viewingdata\">\(ratingSpan)</p></li>"
            }.joined()
            let pagination = next.map { "<a class=\"next\" href=\"\($0)\">Older</a>" } ?? ""
            return "<html><body><ul>\(items)</ul>\(pagination)</body></html>"
        }

        @Test func stitchesEveryPageTogether() async throws {
            let p1 = page([("speed", 6), ("nope", 5)], next: "/thebigshin/films/by/date/page/2/")
            let p2 = page([("heat", 9)], next: nil)
            MockURLProtocol.handler = { request in
                let body = request.url!.path.contains("page/2") ? p2 : p1
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                        Data(body.utf8))
            }
            let reader = LetterboxdProfileReader(http: HTTPClient(session: .mock),
                                                 username: "thebigshin", pageDelay: .zero)
            let films = try await reader.films()
            #expect(films.map(\.slug) == ["speed", "nope", "heat"])
            #expect(films.map(\.rating) == [6, 5, 9])
        }

        @Test func aMissingProfileIsProfileUnavailable() async {
            MockURLProtocol.handler = { request in
                (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
            }
            let reader = LetterboxdProfileReader(http: HTTPClient(session: .mock),
                                                 username: "nobody", pageDelay: .zero)
            await #expect(throws: LetterboxdError.profileUnavailable) { _ = try await reader.films() }
        }

        @Test func thePageLimitStopsARunawayCrawl() async throws {
            // Every page claims there is another one.
            let body = page([("speed", 6)], next: "/thebigshin/films/by/date/page/9/")
            let log = PathLog()
            MockURLProtocol.handler = { request in
                log.record(request.url!.path)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                        Data(body.utf8))
            }
            let reader = LetterboxdProfileReader(http: HTTPClient(session: .mock),
                                                 username: "thebigshin", pageDelay: .zero, pageLimit: 3)
            _ = try await reader.films()
            #expect(log.all.count == 3)
        }

        @Test func theWatchlistUsesItsOwnPath() async throws {
            let log = PathLog()
            let body = page([("the-irishman-2019", nil)], next: nil)
            MockURLProtocol.handler = { request in
                log.record(request.url!.path)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                        Data(body.utf8))
            }
            let reader = LetterboxdProfileReader(http: HTTPClient(session: .mock),
                                                 username: "thebigshin", pageDelay: .zero)
            _ = try await reader.watchlist()
            // URL.path drops the trailing slash.
            #expect(log.all == ["/thebigshin/watchlist"])
        }

        @Test func theFilmsCrawlStartsAtTheDateOrderedGrid() async throws {
            let log = PathLog()
            let body = page([("speed", 6)], next: nil)
            MockURLProtocol.handler = { request in
                log.record(request.url!.path)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                        Data(body.utf8))
            }
            let reader = LetterboxdProfileReader(http: HTTPClient(session: .mock),
                                                 username: "thebigshin", pageDelay: .zero)
            _ = try await reader.films()
            #expect(log.all == ["/thebigshin/films/by/date"])
        }
    }
}
