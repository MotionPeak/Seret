import Foundation

/// Turns a TMDB id into a Letterboxd slug by asking Letterboxd where `/tmdb/{id}/` goes.
///
/// Exact by construction — no title or year is involved — which is why neither sync direction
/// needs fuzzy matching.
public struct LetterboxdFilmResolver: Sendable {
    private let http: HTTPClient
    private let map: LetterboxdFilmMap
    private let baseURL: URL

    public init(http: HTTPClient,
                map: LetterboxdFilmMap,
                baseURL: URL = URL(string: "https://letterboxd.com")!) {
        self.http = http
        self.map = map
        self.baseURL = baseURL
    }

    public func slug(forTMDB id: Int) async throws -> String {
        if let cached = await map.slug(forTMDB: id) { return cached }

        let url = baseURL.appendingPathComponent("tmdb/\(id)", isDirectory: true)
        let resolved: URL
        do {
            resolved = try await http.resolvedURL(for: url)
        } catch {
            throw LetterboxdError.filmNotFound
        }

        // An id Letterboxd does not know can bounce to the home page rather than 404, so the
        // destination has to actually be a film page before we believe it.
        let parts = resolved.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, parts[0] == "film" else { throw LetterboxdError.filmNotFound }

        let slug = parts[1]
        await map.store(slug, forTMDB: id)
        return slug
    }
}
