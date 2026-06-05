import DebridCore

/// The intent to play a specific file at a specific position. 7b-ii routes this to a
/// placeholder; Plan 7c's player consumes the same value. `Hashable` so it drives
/// `navigationDestination(for:)`.
public struct PlaybackRequest: Hashable {
    public let item: MediaItem
    public let source: MediaSource
    public let resumeAt: Double?   // seconds; nil = from the start
    public let label: String       // e.g. "Dune: Part Two" or "Game of Thrones — S1·E3"
    public let contentKey: String  // WatchKey for this movie or show+episode; the player records progress under it
    public init(item: MediaItem, source: MediaSource, resumeAt: Double?, label: String, contentKey: String) {
        self.item = item
        self.source = source
        self.resumeAt = resumeAt
        self.label = label
        self.contentKey = contentKey
    }
}
