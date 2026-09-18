import Testing
import Foundation
@testable import SeretServer
@testable import DebridCore

/// A browser that takes a moment to change pages, because one that changed instantly would hide
/// the whole hazard: the page being replaced is still the page a read sees.
private final class BrowsingTransport: CDPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var href: String
    private var previous: String
    private var settling = 0
    private let redirects: [String: String]
    private let latency: Int
    private var navigations: [String] = []

    init(openAt: String, redirects: [String: String] = [:], latency: Int = 1) {
        self.href = openAt
        self.previous = openAt
        self.redirects = redirects
        self.latency = latency
    }

    var visited: [String] { lock.withLock { navigations } }

    func send(method: String, params: [String: any Sendable]) async throws -> [String: any Sendable] {
        if method == "Page.navigate" {
            let url = (params["url"] as? String) ?? ""
            lock.withLock {
                navigations.append(url)
                previous = href
                href = redirects[url] ?? url
                settling = latency
            }
            return [:]
        }
        guard method == "Runtime.evaluate" else { return [:] }
        let showing = lock.withLock { () -> String in
            if settling > 0 { settling -= 1; return previous }
            return href
        }
        return ["result": ["value": ["href": showing, "ready": "complete"] as [String: any Sendable]]
                    as [String: any Sendable]]
    }
}

@Suite struct ChromeFilmResolverTests {
    private let tmdb = "https://letterboxd.com/tmdb/73/"
    private let film = "https://letterboxd.com/film/american-history-x/"

    private func resolver(_ transport: BrowsingTransport,
                          map: LetterboxdFilmMap = LetterboxdFilmMap()) -> ChromeFilmResolver {
        ChromeFilmResolver(chrome: ChromeSession(transport: transport), map: map,
                           timeout: .seconds(1), poll: .milliseconds(1))
    }

    @Test func followsTheRedirectToTheFilm() async throws {
        let browser = BrowsingTransport(openAt: "https://letterboxd.com/", redirects: [tmdb: film])
        #expect(try await resolver(browser).slug(forTMDB: 73) == "american-history-x")
    }

    /// The browser is normally sitting on the last film it wrote to. Reading before the new page
    /// has arrived would answer with that one - a wrong slug, written to a real diary.
    @Test func doesNotAnswerWithThePageThatWasAlreadyOpen() async throws {
        let browser = BrowsingTransport(openAt: "https://letterboxd.com/film/fight-club/",
                                        redirects: [tmdb: film])
        #expect(try await resolver(browser).slug(forTMDB: 73) == "american-history-x")
    }

    /// An id Letterboxd does not know bounces to the home page rather than 404ing.
    @Test func anIdLetterboxdDoesNotKnowIsFilmNotFound() async {
        let browser = BrowsingTransport(openAt: "https://letterboxd.com/film/fight-club/",
                                        redirects: ["https://letterboxd.com/tmdb/99999999/":
                                                        "https://letterboxd.com/"])
        await #expect(throws: LetterboxdError.filmNotFound) {
            _ = try await self.resolver(browser).slug(forTMDB: 99999999)
        }
    }

    @Test func aSecondLookupNeverTouchesTheBrowser() async throws {
        let browser = BrowsingTransport(openAt: "https://letterboxd.com/", redirects: [tmdb: film])
        let map = LetterboxdFilmMap(seed: [73: "american-history-x"])
        #expect(try await resolver(browser, map: map).slug(forTMDB: 73) == "american-history-x")
        #expect(browser.visited.isEmpty)
    }

    @Test func onlyALetterboxdFilmPageCarriesASlug() {
        #expect(ChromeFilmResolver.slug(inHref: film) == "american-history-x")
        #expect(ChromeFilmResolver.slug(inHref: "https://letterboxd.com/film/speed/reviews/") == "speed")
        #expect(ChromeFilmResolver.slug(inHref: "https://letterboxd.com/") == nil)
        #expect(ChromeFilmResolver.slug(inHref: "about:blank") == nil)
        #expect(ChromeFilmResolver.slug(inHref: "https://example.com/film/speed/") == nil)
    }
}
