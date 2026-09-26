import DebridCore

/// What one AddStore's Hebrew search is about: a movie, or one episode.
public struct SubtitleTarget: Sendable, Equatable {
    /// The same key watch state uses (`DownloadKey` reuses those forms verbatim).
    public let contentKey: String
    public let query: SubtitleQuery

    public init(contentKey: String, query: SubtitleQuery) {
        self.contentKey = contentKey
        self.query = query
    }

    public static func movie(tmdbID: Int, title: String, year: Int?) -> SubtitleTarget {
        SubtitleTarget(contentKey: DownloadKey.movie(tmdbID: tmdbID),
                       query: SubtitleQuery(tmdbID: tmdbID, title: title, year: year))
    }

    public static func episode(showTmdbID: Int, title: String, year: Int?,
                               season: Int, episode: Int) -> SubtitleTarget {
        SubtitleTarget(contentKey: DownloadKey.episode(showTmdbID: showTmdbID, season: season, number: episode),
                       query: SubtitleQuery(tmdbID: showTmdbID, title: title, year: year,
                                            season: season, episode: episode))
    }

    /// The target for a stream query. A season-pack query asks about its episode 1, whose Hebrew
    /// subtitles come from the same releases.
    public static func forKind(_ kind: StreamQuery.Kind, tmdbID: Int, title: String,
                               year: Int?) -> SubtitleTarget {
        switch kind {
        case .movie:
            return .movie(tmdbID: tmdbID, title: title, year: year)
        case let .series(season, episode):
            return .episode(showTmdbID: tmdbID, title: title, year: year, season: season, episode: episode)
        }
    }
}
