import Foundation

public enum MediaKind: String, Sendable, Equatable, Codable {
    case movie, show
}

/// A specific playable thing in Real-Debrid: a torrent (and, for packs, a file within it),
/// its restricted link (unrestrict at play time), and the parse used for quality display.
public struct MediaSource: Sendable, Equatable {
    public let torrentID: String
    public let fileID: Int?
    public let restrictedLink: String
    public let parsed: ParsedRelease

    public init(torrentID: String, fileID: Int?, restrictedLink: String, parsed: ParsedRelease) {
        self.torrentID = torrentID
        self.fileID = fileID
        self.restrictedLink = restrictedLink
        self.parsed = parsed
    }
}

public struct Episode: Sendable, Equatable, Identifiable {
    public let season: Int
    public let number: Int
    public let source: MediaSource

    public init(season: Int, number: Int, source: MediaSource) {
        self.season = season
        self.number = number
        self.source = source
    }

    public var id: String { "s\(season)e\(number)" }
}

public struct Season: Sendable, Equatable, Identifiable {
    public let number: Int
    public let episodes: [Episode]   // sorted by episode number

    public init(number: Int, episodes: [Episode]) {
        self.number = number
        self.episodes = episodes
    }

    public var id: Int { number }
}

/// A top-level library entry: a movie or a show. Metadata fields are nil until TMDB
/// enrichment (Plan 5). A movie carries `sources` (1+); a show carries `seasons`.
public struct MediaItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: MediaKind
    public let title: String
    public let year: Int?
    public let sources: [MediaSource]
    public let seasons: [Season]
    public let tmdbID: Int?
    public let posterPath: String?
    public let backdropPath: String?
    public let overview: String?

    public init(id: String, kind: MediaKind, title: String, year: Int?,
                sources: [MediaSource], seasons: [Season],
                tmdbID: Int? = nil, posterPath: String? = nil,
                backdropPath: String? = nil, overview: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.year = year
        self.sources = sources
        self.seasons = seasons
        self.tmdbID = tmdbID
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.overview = overview
    }
}
