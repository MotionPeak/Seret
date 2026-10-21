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
    @Suite struct LetterboxdTasteReaderTests {
        init() { MockURLProtocol.handler = nil }

        func fixture(_ name: String) throws -> Data {
            let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
            return try Data(contentsOf: url)
        }

        func reader() -> LetterboxdTasteReader {
            LetterboxdTasteReader(http: HTTPClient(session: .mock), pageDelay: .zero)
        }

        /// Serves `body` for every request and returns a log of the URLs asked for.
        @discardableResult
        fileprivate func serve(_ body: Data, status: Int = 200) -> PathLog {
            let log = PathLog()
            MockURLProtocol.handler = { request in
                log.record(request.url!.absoluteString)
                return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, body)
            }
            return log
        }

        @Test func similarFilmsDropsTheFilmItself() async throws {
            serve(try fixture("letterboxd-similar.html"))
            let films = try await reader().similarFilms(to: "the-lives-of-others")
            #expect(films.first?.slug == "the-spy-who-came-in-from-the-cold")
            #expect(!films.contains { $0.slug == "the-lives-of-others" })
        }

        @Test func similarFilmsRequestsTheSimilarPage() async throws {
            let log = serve(try fixture("letterboxd-similar.html"))
            _ = try await reader().similarFilms(to: "the-lives-of-others")
            #expect(log.all == ["https://letterboxd.com/film/the-lives-of-others/similar/"])
        }

        @Test func filmPageReturnsDirectorAndGenres() async throws {
            let log = serve(try fixture("letterboxd-film-page.html"))
            let facts = try await reader().filmPage("the-lives-of-others")
            #expect(facts.directorSlugs == ["florian-henckel-von-donnersmarck"])
            #expect(facts.genres == ["Drama", "Thriller"])
            #expect(log.all == ["https://letterboxd.com/film/the-lives-of-others/"])
        }

        @Test func filmsByDirectorReadsTheDirectorPage() async throws {
            let log = serve(try fixture("letterboxd-director.html"))
            let films = try await reader().films(byDirector: "florian-henckel-von-donnersmarck")
            #expect(log.all == ["https://letterboxd.com/director/florian-henckel-von-donnersmarck/"])
            #expect(Set(films.map(\.slug)).isSuperset(of: ["the-lives-of-others", "the-tourist", "never-look-away"]))
        }

        /// A Letterboxd that is refusing us (429) must not be hit back-to-back by the rest of a crawl.
        @Test func aFailureIsPacedLikeASuccess() async {
            serve(Data(), status: 429)
            let r = LetterboxdTasteReader(http: HTTPClient(session: .mock), pageDelay: .milliseconds(300))
            let clock = ContinuousClock()
            let start = clock.now
            await #expect(throws: LetterboxdError.profileUnavailable) { _ = try await r.similarFilms(to: "x") }
            #expect(clock.now - start >= .milliseconds(300))
        }

        @Test func aServerErrorIsProfileUnavailable() async {
            serve(Data(), status: 503)
            let r = reader()
            await #expect(throws: LetterboxdError.profileUnavailable) { _ = try await r.similarFilms(to: "x") }
            await #expect(throws: LetterboxdError.profileUnavailable) { _ = try await r.filmPage("x") }
            await #expect(throws: LetterboxdError.profileUnavailable) { _ = try await r.films(byDirector: "x") }
        }
    }
}
