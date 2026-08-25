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

    /// Within this many seconds of the end there is nothing worth coming back to — the credits are
    /// rolling. Deliberately near the `PlayerModel` credits lead rather than near the 80% mark.
    public static let resumeTailSeconds: Double = 90

    /// Where playback should pick up, or nil to start from the beginning.
    ///
    /// This is NOT `finished`. That flag answers "does this count as watched", and it flips at 80%
    /// so a title you have effectively seen stops sitting in Continue Watching. Reusing it to
    /// decide resume threw away the position for the whole last fifth of a title — twenty-odd
    /// minutes of a feature — so stopping at 1:45 of a 2:10 film and coming back offered "Play",
    /// from zero. The two questions have different answers and now have different code.
    ///
    /// A length of 0 means nobody measured it (`setWatched` records the flag alone), and then the
    /// flag really is all there is to go on.
    public var resumePosition: Double? {
        guard positionSeconds > 0 else { return nil }
        guard durationSeconds > 0 else { return finished ? nil : positionSeconds }
        // A FINISHED title only resumes from a point it was actually watched to — the tail.
        //
        // Crossing the finished fraction while playing is what normally sets `finished`, and being
        // able to pick up that last stretch is the point of resuming at all. But a manual mark also
        // sets it, and carries the position forward so un-marking restores the viewer's place —
        // and that position can be anywhere. Offering it back would make "mark watched" quietly
        // mean "resume from the middle".
        if finished, positionSeconds / durationSeconds < Self.finishedFraction { return nil }
        return durationSeconds - positionSeconds > Self.resumeTailSeconds ? positionSeconds : nil
    }

    /// Fraction of runtime past which playback counts as finished. Lives here because
    /// `resumePosition` has to tell a position reached by watching from one written by a mark.
    public static let finishedFraction = 0.8
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

    /// The same episode key, derived from season/episode numbers alone — for an episode listed by
    /// TMDB but not downloaded, which has no `Episode` because it has no file. Identical output to
    /// `content(forShow:episode:)`, and tested for parity so the two can never drift.
    public static func content(forShow show: MediaItem, season: Int, number: Int) -> String {
        "\(show.id):s\(season)e\(number)"
    }

    /// The exact file played: torrent id + file id (`-` when the torrent is single-file).
    public static func source(_ s: MediaSource) -> String {
        "\(s.torrentID)#\(s.fileID.map(String.init) ?? "-")"
    }
}
