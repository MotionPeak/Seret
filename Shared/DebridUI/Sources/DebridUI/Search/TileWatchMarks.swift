import DebridCore
import Observation

/// Whether each poster in a browse or search grid has been watched.
///
/// A grid is dozens of posters; asking the store per poster would be dozens of round-trips, so this
/// reads every key it does not already know in one batched call. Marking from a long-press updates
/// it in place — the tick has to appear immediately, not after the next fetch.
@MainActor
@Observable
public final class TileWatchMarks {
    private var finished: Set<String> = []

    /// Resolved on every read, NOT captured once.
    ///
    /// This object is built when the shell first appears, which is before sign-in has produced a
    /// watch store — so capturing the store by value captured `nil`, for the whole session, and no
    /// browse or search poster ever showed a watched tick.
    private let watch: @MainActor () -> WatchProgressProviding?
    private let profileID: @MainActor () -> String

    public init(watch: @escaping @MainActor () -> WatchProgressProviding?,
                profileID: @escaping @MainActor () -> String) {
        self.watch = watch
        self.profileID = profileID
    }

    /// A no-op instance for the single render before the shell's real one exists. Static, so a body
    /// re-evaluation does not allocate and discard a fresh object on every pass.
    public static let placeholder = TileWatchMarks(watch: { nil }, profileID: { "" })

    public func isWatched(_ hit: SearchHit) -> Bool { finished.contains(hit.contentKey) }

    /// Read watch state for the titles whose answer could still change.
    ///
    /// Only a FINISHED result is worth remembering: it cannot become unfinished on its own, and the
    /// one thing that can un-finish it — an explicit mark — goes through `set`. Remembering the
    /// UNFINISHED ones too, which is what a plain "already read" cache did, meant a title watched
    /// during this session never grew its tick: the grid had recorded that it looked once and would
    /// not look again until the app was relaunched.
    ///
    /// Re-reading the rest costs one batched fetch per grid appearance, over the local store.
    public func load(_ hits: [SearchHit]) async {
        guard let watch = watch() else { return }
        let keys = Array(Set(hits.map(\.contentKey)).subtracting(finished))
        guard !keys.isEmpty else { return }
        guard let states = try? await watch.progress(forContentKeys: keys, profileID: profileID())
        else { return }
        for (key, state) in states where state.finished { finished.insert(key) }
    }

    /// Reflect a mark the user just made, without waiting for a re-read.
    public func set(_ watched: Bool, for hit: SearchHit) {
        if watched { finished.insert(hit.contentKey) } else { finished.remove(hit.contentKey) }
    }
}
