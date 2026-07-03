import DebridCore

/// The intent to play a specific file at a specific position. 7b-ii routes this to a
/// placeholder; Plan 7c's player consumes the same value. `Hashable` so it drives
/// `navigationDestination(for:)`.
public struct PlaybackRequest: Hashable {
    public let item: MediaItem
    public let source: MediaSource
    /// UI resume hint (seconds). The player treats this as a FALLBACK only — when it has a
    /// resume provider it re-resolves the saved position from the store at load time, because
    /// the screen's watch state can be not-yet-loaded or stale when Play is tapped.
    public let resumeAt: Double?
    public let label: String       // e.g. "Dune: Part Two" or "Game of Thrones — S1·E3"
    public let contentKey: String  // WatchKey for this movie or show+episode; the player records progress under it
    /// The episode being played (shows only); lets the player offer "Next Episode" and auto-advance
    /// to the next episode when one finishes. `nil` for movies and for Add-flow plays (no series context).
    public let episode: Episode?
    /// The viewer explicitly chose "Start over" — the player must NOT resume, even if the
    /// store holds a saved position.
    public let fromStart: Bool
    public init(item: MediaItem, source: MediaSource, resumeAt: Double?, label: String,
                contentKey: String, episode: Episode? = nil, fromStart: Bool = false) {
        self.item = item
        self.source = source
        self.resumeAt = resumeAt
        self.label = label
        self.contentKey = contentKey
        self.episode = episode
        self.fromStart = fromStart
    }
}
