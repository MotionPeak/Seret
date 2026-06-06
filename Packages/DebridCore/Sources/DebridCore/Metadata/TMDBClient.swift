import Foundation

/// Looks up movies/shows on TMDB (v3 API, `api_key` query param). The key is injected;
/// tests mock the transport, so no real key is needed to test.
public struct TMDBClient: Sendable {
    public static let base = URL(string: "https://api.themoviedb.org/3")!
    public static let imageBase = "https://image.tmdb.org/t/p/"

    private let apiKey: String
    private let http: HTTPClient

    public init(apiKey: String, http: HTTPClient = HTTPClient()) {
        self.apiKey = apiKey
        self.http = http
    }

    public func searchMovie(query: String, year: Int? = nil) async throws -> [TMDBSearchResult] {
        var items = [URLQueryItem(name: "query", value: query)]
        if let year { items.append(.init(name: "year", value: String(year))) }
        let response: TMDBSearchResponse = try await get("search/movie", items)
        return response.results
    }

    public func searchTV(query: String, firstAirYear: Int? = nil) async throws -> [TMDBSearchResult] {
        var items = [URLQueryItem(name: "query", value: query)]
        if let firstAirYear { items.append(.init(name: "first_air_date_year", value: String(firstAirYear))) }
        let response: TMDBSearchResponse = try await get("search/tv", items)
        return response.results
    }

    public func movieDetails(id: Int) async throws -> TMDBMovieDetails {
        try await get("movie/\(id)", [])
    }

    public func tvDetails(id: Int) async throws -> TMDBTVDetails {
        try await get("tv/\(id)", [URLQueryItem(name: "append_to_response", value: "external_ids")])
    }

    public func tvSeasonDetails(tvID: Int, season: Int) async throws -> TMDBSeasonDetails {
        try await get("tv/\(tvID)/season/\(season)", [])
    }

    /// Builds a TMDB image URL from a `poster_path`/`backdrop_path` (e.g. "/abc.jpg").
    /// Returns nil when `path` is nil. `size` is a TMDB size token like "w500" or "original".
    public static func imageURL(path: String?, size: String = "w500") -> URL? {
        guard let path else { return nil }
        return URL(string: imageBase + size + path)
    }

    private func get<T: Decodable>(_ path: String, _ items: [URLQueryItem]) async throws -> T {
        var comps = URLComponents(url: Self.base.appending(path: path), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "api_key", value: apiKey)] + items
        return try await http.get(comps.url!)
    }
}
