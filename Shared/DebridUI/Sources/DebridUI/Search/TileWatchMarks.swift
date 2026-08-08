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
    private var known: Set<String> = []

    private let watch: WatchProgressProviding?
    private let profileID: @MainActor () -> String

    public init(watch: WatchProgressProviding?, profileID: @escaping @MainActor () -> String) {
        self.watch = watch
        self.profileID = profileID
    }

    public func isWatched(_ hit: SearchHit) -> Bool { finished.contains(hit.contentKey) }

    /// Read watch state for any of these titles we have not read yet. Idempotent: calling it again
    /// with the same grid costs nothing.
    public func load(_ hits: [SearchHit]) async {
        guard let watch else { return }
        let keys = Array(Set(hits.map(\.contentKey)).subtracting(known))
        guard !keys.isEmpty else { return }
        known.formUnion(keys)
        guard let states = try? await watch.progress(forContentKeys: keys, profileID: profileID())
        else {
            known.subtract(keys)         // a failed read must not be remembered as "no result"
            return
        }
        for (key, state) in states where state.finished { finished.insert(key) }
    }

    /// Reflect a mark the user just made, without waiting for a re-read.
    public func set(_ watched: Bool, for hit: SearchHit) {
        known.insert(hit.contentKey)
        if watched { finished.insert(hit.contentKey) } else { finished.remove(hit.contentKey) }
    }
}
