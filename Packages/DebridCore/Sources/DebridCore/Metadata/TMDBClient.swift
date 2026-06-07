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

    /// Movies currently in theatrical release ("Recently Released" discovery row).
    public func nowPlayingMovies() async throws -> [TMDBSearchResult] {
        let response: TMDBSearchResponse = try await get("movie/now_playing", [])
        return response.results
    }

    /// Most-popular movies in a TMDB genre (e.g. 27 = Horror), ≥100 votes — for the per-genre
    /// "Most Popular" rows.
    public func discoverMovies(genreID: Int) async throws -> [TMDBSearchResult] {
        let response: TMDBSearchResponse = try await get("discover/movie", [
            URLQueryItem(name: "with_genres", value: String(genreID)),
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "vote_count.gte", value: "100"),
        ])
        return response.results
    }

    /// Newly-released movies in a genre within a date window ("YYYY-MM-DD"), newest first —
    /// for the per-genre "New Releases" rows. Low vote gate (new titles have few votes).
    public func discoverMovies(genreID: Int, releaseFrom: String, releaseTo: String) async throws -> [TMDBSearchResult] {
        let response: TMDBSearchResponse = try await get("discover/movie", [
            URLQueryItem(name: "with_genres", value: String(genreID)),
            URLQueryItem(name: "primary_release_date.gte", value: releaseFrom),
            URLQueryItem(name: "primary_release_date.lte", value: releaseTo),
            URLQueryItem(name: "sort_by", value: "primary_release_date.desc"),
            URLQueryItem(name: "vote_count.gte", value: "10"),
        ])
        return response.results
    }

    /// Newly-aired shows in a TV genre within a first-air-date window — per-genre TV "New Releases".
    public func discoverTV(genreID: Int, firstAirFrom: String, firstAirTo: String) async throws -> [TMDBSearchResult] {
        let response: TMDBSearchResponse = try await get("discover/tv", [
            URLQueryItem(name: "with_genres", value: String(genreID)),
            URLQueryItem(name: "first_air_date.gte", value: firstAirFrom),
            URLQueryItem(name: "first_air_date.lte", value: firstAirTo),
            URLQueryItem(name: "sort_by", value: "first_air_date.desc"),
            URLQueryItem(name: "vote_count.gte", value: "5"),
        ])
        return response.results
    }

    /// Popular movies / shows (the "Popular" browse row).
    public func popularMovies() async throws -> [TMDBSearchResult] {
        let response: TMDBSearchResponse = try await get("movie/popular", [])
        return response.results
    }
    public func popularTV() async throws -> [TMDBSearchResult] {
        let response: TMDBSearchResponse = try await get("tv/popular", [])
        return response.results
    }

    /// Popular shows in a TMDB TV genre (TV genre ids differ from movie ids).
    public func discoverTV(genreID: Int) async throws -> [TMDBSearchResult] {
        let response: TMDBSearchResponse = try await get("discover/tv", [
            URLQueryItem(name: "with_genres", value: String(genreID)),
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "vote_count.gte", value: "100"),
        ])
        return response.results
    }

    /// Movies released within a date window ("YYYY-MM-DD"), newest first — the home-release
    /// window for the "New Releases" row (titles likely to have real cached files).
    public func discoverMovies(releaseFrom: String, releaseTo: String) async throws -> [TMDBSearchResult] {
        let response: TMDBSearchResponse = try await get("discover/movie", [
            URLQueryItem(name: "primary_release_date.gte", value: releaseFrom),
            URLQueryItem(name: "primary_release_date.lte", value: releaseTo),
            URLQueryItem(name: "sort_by", value: "primary_release_date.desc"),
            URLQueryItem(name: "vote_count.gte", value: "50"),
        ])
        return response.results
    }

    /// Trailers/teasers for a title (`/movie|tv/{id}/videos`).
    public func movieVideos(id: Int) async throws -> [TMDBVideo] {
        let response: TMDBVideosResponse = try await get("movie/\(id)/videos", [])
        return response.results
    }
    public func tvVideos(id: Int) async throws -> [TMDBVideo] {
        let response: TMDBVideosResponse = try await get("tv/\(id)/videos", [])
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
