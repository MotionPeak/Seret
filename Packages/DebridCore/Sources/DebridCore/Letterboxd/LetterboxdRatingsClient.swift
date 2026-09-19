import Foundation

/// Fetches Letterboxd's community score for a TMDB title.
///
/// Two requests at worst — resolve the TMDB id to a slug, then read the film page — and usually
/// one, because `LetterboxdFilmResolver` keeps its slug map across launches. Reads only; the
/// public film page needs no account, which is why this works from the apps while every WRITE has
/// to go through the browser the server drives.
public struct LetterboxdRatingsClient: Sendable {
    private let http: HTTPClient
    private let resolver: any LetterboxdFilmResolving
    private let baseURL: URL

    public init(http: HTTPClient = HTTPClient(),
                resolver: any LetterboxdFilmResolving,
                baseURL: URL = URL(string: "https://letterboxd.com")!) {
        self.http = http
        self.resolver = resolver
        self.baseURL = baseURL
    }

    /// Returns nil when the film exists but carries no score yet.
    ///
    /// Throws `LetterboxdError.filmNotFound` when Letterboxd has no film for the id at all — every
    /// TV show, since Letterboxd indexes films only. Keeping that apart from "no score" matters:
    /// one is a permanent fact about the title, the other is a transient state of the page.
    public func rating(forTMDB id: Int) async throws -> LetterboxdFilmRating? {
        let slug = try await resolver.slug(forTMDB: id)
        let url = baseURL.appendingPathComponent("film/\(slug)", isDirectory: true)

        let data: Data
        do {
            data = try await http.data(url)
        } catch {
            // A refusal or a dead network says nothing about the film. Surfacing it as "no score"
            // would let the caller cache it and suppress a real rating for the whole TTL.
            throw LetterboxdError.transient("fetching film/\(slug): \(error)")
        }

        return LetterboxdRatingParser.rating(fromFilmPage: String(decoding: data, as: UTF8.self))
    }
}
