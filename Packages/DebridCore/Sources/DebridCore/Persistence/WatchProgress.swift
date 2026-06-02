import Foundation
import SwiftData

/// Per-title playback position. CloudKit-ready (every property defaulted, no unique
/// constraint, no required relationship) so Stage 3 cross-device sync is a config flip.
/// `contentKey` identifies the title (see `WatchKey`); `sourceKey` records the exact file played.
@Model
public final class WatchProgress {
    public var contentKey: String = ""
    public var sourceKey: String = ""
    public var positionSeconds: Double = 0
    public var durationSeconds: Double = 0
    public var finished: Bool = false
    public var updatedAt: Date = Date(timeIntervalSince1970: 0)

    public init(contentKey: String = "", sourceKey: String = "",
                positionSeconds: Double = 0, durationSeconds: Double = 0,
                finished: Bool = false, updatedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.contentKey = contentKey
        self.sourceKey = sourceKey
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.finished = finished
        self.updatedAt = updatedAt
    }
}

/// A `Sendable` snapshot of a `WatchProgress` row — what the store hands back, so callers and
/// tests never touch the (non-`Sendable`) `@Model` class directly.
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

    public init(_ m: WatchProgress) {
        self.init(contentKey: m.contentKey, sourceKey: m.sourceKey,
                  positionSeconds: m.positionSeconds, durationSeconds: m.durationSeconds,
                  finished: m.finished, updatedAt: m.updatedAt)
    }
}

/// Derives the stable keys used to store/look up watch progress.
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
