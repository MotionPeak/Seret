import DebridCore

/// The intent to play a specific file at a specific position. 7b-ii routes this to a
/// placeholder; Plan 7c's player consumes the same value. `Hashable` so it drives
/// `navigationDestination(for:)`.
struct PlaybackRequest: Hashable {
    let item: MediaItem
    let source: MediaSource
    let resumeAt: Double?   // seconds; nil = from the start
    let label: String       // e.g. "Dune: Part Two" or "Game of Thrones — S1·E3"
    let contentKey: String  // WatchKey for this movie or show+episode; the player records progress under it
}
