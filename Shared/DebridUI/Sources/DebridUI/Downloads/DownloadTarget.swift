import DebridCore

/// What a tracked download is *for* — the key it files under, and what a tile shows before the
/// title reaches the library. The only place those strings are assembled, so a film, an episode,
/// a season pack and a Versions pick can never drift apart on wording.
public struct DownloadTarget: Sendable, Equatable {
    public let contentKey: String
    public let tmdbID: Int
    public let title: String
    public let kind: MediaKind
    public let posterPath: String?

    public init(contentKey: String, tmdbID: Int, title: String, kind: MediaKind,
                posterPath: String?) {
        self.contentKey = contentKey
        self.tmdbID = tmdbID
        self.title = title
        self.kind = kind
        self.posterPath = posterPath
    }

    /// A film. Nil when the item has no TMDB id — nothing to key a download under.
    public static func movie(_ item: MediaItem) -> DownloadTarget? {
        guard let tmdbID = item.tmdbID else { return nil }
        return DownloadTarget(contentKey: DownloadKey.movie(tmdbID: tmdbID), tmdbID: tmdbID,
                              title: item.title, kind: .movie, posterPath: item.posterPath)
    }

    /// One episode of a show, titled exactly as tvOS's tracked download titled it:
    /// "\(title) S\(season)E\(number)".
    public static func episode(of show: MediaItem, season: Int, number: Int) -> DownloadTarget? {
        guard let tmdbID = show.tmdbID else { return nil }
        return DownloadTarget(
            contentKey: DownloadKey.episode(showTmdbID: tmdbID, season: season, number: number),
            tmdbID: tmdbID, title: "\(show.title) S\(season)E\(number)", kind: .show,
            posterPath: show.posterPath)
    }

    /// A whole-season pack, titled "\(title) Season \(season)".
    public static func season(of show: MediaItem, _ season: Int) -> DownloadTarget? {
        guard let tmdbID = show.tmdbID else { return nil }
        return DownloadTarget(contentKey: DownloadKey.season(showTmdbID: tmdbID, season: season),
                              tmdbID: tmdbID, title: "\(show.title) Season \(season)", kind: .show,
                              posterPath: show.posterPath)
    }

    /// The Versions list's form (tvOS `VersionsScreen.downloadKey`): titled with the resolved
    /// title rather than derived from a `MediaItem`, because the Versions sheet already has one.
    public static func version(tmdbID: Int, kind: MediaKind, title: String, posterPath: String?,
                               target: AcquisitionStore.Target) -> DownloadTarget {
        let contentKey: String
        switch target {
        case .movie:
            contentKey = DownloadKey.movie(tmdbID: tmdbID)
        case let .episode(season, number):
            contentKey = DownloadKey.episode(showTmdbID: tmdbID, season: season, number: number)
        }
        return DownloadTarget(contentKey: contentKey, tmdbID: tmdbID, title: title, kind: kind,
                              posterPath: posterPath)
    }

    public var magnet: MagnetAddModel.Target {
        MagnetAddModel.Target(contentKey: contentKey, tmdbID: tmdbID, title: title, kind: kind,
                              posterPath: posterPath)
    }
}

extension DownloadStore {
    public func request(_ target: DownloadTarget, candidates: [CachedStream]) async {
        await request(contentKey: target.contentKey, tmdbID: target.tmdbID, title: target.title,
                      kind: target.kind, candidates: candidates, posterPath: target.posterPath)
    }

    public func status(for target: DownloadTarget) -> DownloadStatus? {
        status(forContentKey: target.contentKey)
    }

    public func cancel(_ target: DownloadTarget) async {
        await cancel(contentKey: target.contentKey)
    }
}
