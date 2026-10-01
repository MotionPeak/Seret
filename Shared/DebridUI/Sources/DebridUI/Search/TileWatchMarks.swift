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

    /// Marks made here, by key → the edit count when they were made. See `load`.
    private var editedAt: [String: UInt64] = [:]
    private var edits: UInt64 = 0

    /// Read watch state for every title in the grid — one batched read over the local store.
    ///
    /// It used to skip titles already known FINISHED, on the theory that the answer could not change
    /// on its own. It can: a mark made anywhere else (the title page, the library grid, Continue
    /// Watching) un-finishes a title, and the poster kept its tick, dimmed, until relaunch. Before
    /// that it had also cached the UNFINISHED answers, so a title watched during the session never
    /// grew one. Every answer is current now.
    ///
    /// A mark made on THIS object while the read was in flight outranks what the read found — the
    /// read answers a question asked before the viewer pressed.
    public func load(_ hits: [SearchHit]) async {
        guard let watch = watch() else { return }
        let keys = Array(Set(hits.map(\.contentKey)))
        guard !keys.isEmpty else { return }
        let asked = edits
        guard let states = try? await watch.progress(forContentKeys: keys, profileID: profileID())
        else { return }
        for key in keys where (editedAt[key] ?? 0) <= asked {
            if states[key]?.finished == true { finished.insert(key) } else { finished.remove(key) }
        }
    }

    /// Reflect a mark the user just made, without waiting for a re-read.
    public func set(_ watched: Bool, for hit: SearchHit) {
        edits &+= 1
        editedAt[hit.contentKey] = edits
        if watched { finished.insert(hit.contentKey) } else { finished.remove(hit.contentKey) }
    }
}
