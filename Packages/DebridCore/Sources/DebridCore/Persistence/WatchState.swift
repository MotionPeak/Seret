import Foundation

/// A snapshot of a title's watch state, and the keys it hangs off.
///
/// This used to be a projection of a SwiftData `WatchProgress` row. Trakt is now the source of
/// truth, so nothing persists locally — but the DTO and key scheme stayed, because every reader
/// (Home, Detail, Library) and the `WatchProgressProviding` seam speak them.
public struct WatchState: Sendable, Equatable {
    public let contentKey: String
    public let sourceKey: String
    public let positionSeconds: Double
    public let durationSeconds: Double
    public let finished: Bool
    public let updatedAt: Date

    public init(contentKey: String, sourceKey: String, positionSeconds: Double,
                durationSeconds: Double, finished: Bool, updatedAt: Date) {
        self.contentKey = contentKey
        self.sourceKey = sourceKey
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.finished = finished
        self.updatedAt = updatedAt
    }
}

/// Derives the stable keys used to look up watch state.
///
/// The movie/show forms match `MetadataEnricher`'s TMDB-rekeyed ids (`movie:tmdb:123`), which is
/// what lets `TraktMapping` convert between a content key and a Trakt ref without a lookup table.
public enum WatchKey {
    /// A movie's key is its (TMDB-stable) item id.
    public static func content(forMovie item: MediaItem) -> String { item.id }

    /// An episode's key is the show id + the episode id (`Episode.id` alone, "s1e2", isn't global).
    public static func content(forShow show: MediaItem, episode: Episode) -> String {
        "\(show.id):\(episode.id)"
    }

    /// The exact file played: torrent id + file id (`-` when the torrent is single-file).
    public static func source(_ s: MediaSource) -> String {
        "\(s.torrentID)#\(s.fileID.map(String.init) ?? "-")"
    }
}
