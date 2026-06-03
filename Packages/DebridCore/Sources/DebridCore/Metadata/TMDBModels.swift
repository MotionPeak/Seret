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

    public init(id: Int, name: String) { self.id = id; self.name = name }
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

    public init(id: Int, title: String, releaseDate: String?, overview: String?,
                posterPath: String?, backdropPath: String?, runtime: Int?,
                genres: [TMDBGenre], voteAverage: Double?) {
        self.id = id; self.title = title; self.releaseDate = releaseDate
        self.overview = overview; self.posterPath = posterPath; self.backdropPath = backdropPath
        self.runtime = runtime; self.genres = genres; self.voteAverage = voteAverage
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

    public init(id: Int, name: String, firstAirDate: String?, overview: String?,
                posterPath: String?, backdropPath: String?, numberOfSeasons: Int?,
                genres: [TMDBGenre], voteAverage: Double?) {
        self.id = id; self.name = name; self.firstAirDate = firstAirDate
        self.overview = overview; self.posterPath = posterPath; self.backdropPath = backdropPath
        self.numberOfSeasons = numberOfSeasons; self.genres = genres; self.voteAverage = voteAverage
    }
}

/// One episode from a TMDB `/tv/{id}/season/{n}` response.
public struct TMDBEpisodeDetails: Decodable, Sendable, Equatable, Hashable, Identifiable {
    public let episodeNumber: Int
    public let name: String?
    public let overview: String?
    public let stillPath: String?
    public let runtime: Int?
    public let airDate: String?

    public var id: Int { episodeNumber }

    enum CodingKeys: String, CodingKey {
        case name, overview, runtime
        case episodeNumber = "episode_number"
        case stillPath = "still_path"
        case airDate = "air_date"
    }

    public init(episodeNumber: Int, name: String?, overview: String?,
                stillPath: String?, runtime: Int?, airDate: String?) {
        self.episodeNumber = episodeNumber
        self.name = name
        self.overview = overview
        self.stillPath = stillPath
        self.runtime = runtime
        self.airDate = airDate
    }
}

/// A TMDB `/tv/{id}/season/{n}` response — the episodes for one season.
public struct TMDBSeasonDetails: Decodable, Sendable, Equatable {
    public let seasonNumber: Int
    public let episodes: [TMDBEpisodeDetails]

    enum CodingKeys: String, CodingKey {
        case seasonNumber = "season_number"
        case episodes
    }

    public init(seasonNumber: Int, episodes: [TMDBEpisodeDetails]) {
        self.seasonNumber = seasonNumber
        self.episodes = episodes
    }
}
