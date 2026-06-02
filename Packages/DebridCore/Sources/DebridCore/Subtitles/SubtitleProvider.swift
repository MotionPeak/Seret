import Foundation

/// What to search subtitles for. Built from the domain types so callers don't construct it by hand;
/// `tmdbID` (when present) gives the best provider matches.
public struct SubtitleQuery: Sendable, Equatable {
    public var tmdbID: Int?
    public var title: String
    public var year: Int?
    public var season: Int?
    public var episode: Int?

    public init(tmdbID: Int? = nil, title: String, year: Int? = nil,
                season: Int? = nil, episode: Int? = nil) {
        self.tmdbID = tmdbID
        self.title = title
        self.year = year
        self.season = season
        self.episode = episode
    }

    public static func movie(_ item: MediaItem) -> SubtitleQuery {
        SubtitleQuery(tmdbID: item.tmdbID, title: item.title, year: item.year)
    }

    public static func episode(show: MediaItem, episode: Episode) -> SubtitleQuery {
        SubtitleQuery(tmdbID: show.tmdbID, title: show.title, year: show.year,
                      season: episode.season, episode: episode.number)
    }
}

/// One subtitle search hit. `fileID` is what `download` needs.
public struct SubtitleResult: Sendable, Equatable {
    public let fileID: Int
    public let language: String
    public let release: String?
    public let fileName: String?
    public let downloadCount: Int?

    public init(fileID: Int, language: String, release: String? = nil,
                fileName: String? = nil, downloadCount: Int? = nil) {
        self.fileID = fileID
        self.language = language
        self.release = release
        self.fileName = fileName
        self.downloadCount = downloadCount
    }
}

public enum SubtitleError: Error, Equatable, Sendable {
    /// The provider's daily download quota is exhausted; `resetTime` is when it refills, if known.
    case dailyCapReached(resetTime: Date?)
    /// Login failed / no valid session.
    case notAuthenticated
    /// The provider returned a response we couldn't use (e.g. a malformed download link).
    case invalidResponse
}

/// Finds and downloads external subtitles. A Hebrew-specific source can implement this later
/// without touching the player.
public protocol SubtitleProvider: Sendable {
    func search(_ query: SubtitleQuery, languages: [String]) async throws -> [SubtitleResult]
    /// Downloads the chosen subtitle to a local temp file and returns its URL.
    func download(_ result: SubtitleResult) async throws -> URL
}
