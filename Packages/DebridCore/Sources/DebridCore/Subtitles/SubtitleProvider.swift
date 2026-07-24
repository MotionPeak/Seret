import Foundation

/// What to search subtitles for. Built from the domain types so callers don't construct it by hand;
/// `tmdbID` (when present) gives the best provider matches.
public struct SubtitleQuery: Sendable, Equatable {
    public var tmdbID: Int?
    public var title: String
    public var year: Int?
    public var season: Int?
    public var episode: Int?
    /// OpenSubtitles movie hash of the file being played. When present the API flags exact-file
    /// matches with `moviehash_match`, the strongest sync signal available.
    public var moviehash: String?

    public init(tmdbID: Int? = nil, title: String, year: Int? = nil,
                season: Int? = nil, episode: Int? = nil, moviehash: String? = nil) {
        self.tmdbID = tmdbID
        self.title = title
        self.year = year
        self.season = season
        self.episode = episode
        self.moviehash = moviehash
    }

    public static func movie(_ item: MediaItem) -> SubtitleQuery {
        SubtitleQuery(tmdbID: item.tmdbID, title: item.title, year: item.year)
    }

    public static func episode(show: MediaItem, episode: Episode) -> SubtitleQuery {
        SubtitleQuery(tmdbID: show.tmdbID, title: show.title, year: show.year,
                      season: episode.season, episode: episode.number)
    }
}

/// One subtitle search hit. `fileID` is what `download` needs; the rest feeds `SubtitleMatch`
/// ranking and the browser's badges.
public struct SubtitleResult: Sendable, Equatable {
    public let fileID: Int
    public let language: String
    public let release: String?
    public let fileName: String?
    public let downloadCount: Int?
    /// Frames per second the subtitle was timed against. A mismatch against the video's rate is a
    /// classic source of progressive drift.
    public let fps: Double?
    public let hearingImpaired: Bool?
    public let trusted: Bool?
    public let aiTranslated: Bool?
    /// Set by OpenSubtitles when the search carried a `moviehash` and this subtitle was uploaded
    /// against that exact file — a perfect-sync guarantee, not a heuristic.
    public let moviehashMatch: Bool?
    public let uploader: String?

    public init(fileID: Int, language: String, release: String? = nil,
                fileName: String? = nil, downloadCount: Int? = nil,
                fps: Double? = nil, hearingImpaired: Bool? = nil, trusted: Bool? = nil,
                aiTranslated: Bool? = nil, moviehashMatch: Bool? = nil, uploader: String? = nil) {
        self.fileID = fileID
        self.language = language
        self.release = release
        self.fileName = fileName
        self.downloadCount = downloadCount
        self.fps = fps
        self.hearingImpaired = hearingImpaired
        self.trusted = trusted
        self.aiTranslated = aiTranslated
        self.moviehashMatch = moviehashMatch
        self.uploader = uploader
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
