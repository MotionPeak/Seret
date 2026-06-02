import Foundation

/// A row from a TMDB `/search/movie` or `/search/tv` response.
public struct TMDBSearchResult: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let title: String?          // movies
    public let name: String?           // tv
    public let releaseDate: String?    // movies, "YYYY-MM-DD"
    public let firstAirDate: String?   // tv
    public let posterPath: String?
    public let overview: String?
    public let voteAverage: Double?

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case posterPath = "poster_path"
        case voteAverage = "vote_average"
    }

    /// Movie `title` or TV `name`.
    public var displayTitle: String { title ?? name ?? "" }

    /// Year parsed from the release / first-air date (the leading 4 digits).
    public var year: Int? {
        let date = releaseDate ?? firstAirDate
        guard let prefix = date?.prefix(4) else { return nil }
        return Int(prefix)
    }
}

/// Internal envelope for `/search/*` responses. `internal` (not `private`) so
/// `TMDBClient` — same module, different file — can decode into it.
struct TMDBSearchResponse: Decodable { let results: [TMDBSearchResult] }

public struct TMDBGenre: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
}

public struct TMDBMovieDetails: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let title: String
    public let releaseDate: String?
    public let overview: String?
    public let posterPath: String?
    public let backdropPath: String?
    public let runtime: Int?
    public let genres: [TMDBGenre]
    public let voteAverage: Double?

    enum CodingKeys: String, CodingKey {
        case id, title, overview, runtime, genres
        case releaseDate = "release_date"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
    }
}

public struct TMDBTVDetails: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let firstAirDate: String?
    public let overview: String?
    public let posterPath: String?
    public let backdropPath: String?
    public let numberOfSeasons: Int?
    public let genres: [TMDBGenre]
    public let voteAverage: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, overview, genres
        case firstAirDate = "first_air_date"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case numberOfSeasons = "number_of_seasons"
        case voteAverage = "vote_average"
    }
}
