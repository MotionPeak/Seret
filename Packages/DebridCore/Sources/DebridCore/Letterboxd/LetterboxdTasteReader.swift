import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // URLSession/URLRequest live here on Linux, not in Foundation
#endif

/// What the film's own page says about it: who directed it and what genres it carries.
public struct LetterboxdFilmFacts: Sendable, Equatable, Codable {
    public let directorSlugs: [String]
    public let genres: [String]

    public init(directorSlugs: [String], genres: [String]) {
        self.directorSlugs = directorSlugs
        self.genres = genres
    }
}

/// Public pages only, one request at a time with a delay after each — the same politeness as
/// `LetterboxdProfileReader`. Any transport or HTTP failure is `LetterboxdError.profileUnavailable`.
public struct LetterboxdTasteReader: LetterboxdTasteReading {
    private let http: HTTPClient
    private let baseURL: URL
    private let pageDelay: Duration

    public init(http: HTTPClient,
                baseURL: URL = URL(string: "https://letterboxd.com")!,
                pageDelay: Duration = .seconds(1)) {
        self.http = http
        self.baseURL = baseURL
        self.pageDelay = pageDelay
    }

    public func similarFilms(to slug: String) async throws -> [LetterboxdEntry] {
        let html = try await page("/film/\(slug)/similar/")
        // The page lists the film itself first; it is not similar to itself.
        return LetterboxdFilmListParser.parse(html).filter { $0.slug != slug }
    }

    public func filmPage(_ slug: String) async throws -> LetterboxdFilmFacts {
        let html = try await page("/film/\(slug)/")
        return LetterboxdFilmFacts(directorSlugs: LetterboxdFilmPageParser.directorSlugs(fromFilmPage: html),
                                   genres: LetterboxdFilmPageParser.genres(fromFilmPage: html))
    }

    public func films(byDirector slug: String) async throws -> [LetterboxdEntry] {
        LetterboxdFilmListParser.parse(try await page("/director/\(slug)/"))
    }

    private func page(_ path: String) async throws -> String {
        // Relative resolution, not appendingPathComponent: `path` already starts with "/".
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw LetterboxdError.profileUnavailable
        }
        let data: Data
        do {
            data = try await http.data(url)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LetterboxdError.profileUnavailable
        }
        if pageDelay > .zero { try await Task.sleep(for: pageDelay) }
        return String(decoding: data, as: UTF8.self)
    }
}
