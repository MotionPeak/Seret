import DebridCore
import Observation

/// The library UI's single source of truth: cache-first instant render, then a background
/// refresh against RD. No RD/TMDB logic here — it delegates to `LibraryProviding`.
@MainActor
@Observable
public final class LibraryStore {
    public enum State: Equatable { case loading, loaded, empty, failed(String) }
    public enum Removal: Equatable { case idle, removing(MediaItem), failed(String) }

    public private(set) var state: State = .loading
    public private(set) var movies: [MediaItem] = []
    public private(set) var shows: [MediaItem] = []
    /// Bumped by `retry()`; drives the shell's `.task(id:)` so a retry re-runs `load()`.
    public private(set) var attempt = 0
    public private(set) var removal: Removal = .idle

    private let library: LibraryProviding
    private let watch: WatchProgressProviding?

    /// Fired after the library's contents change (currently: a successful removal) so dependent
    /// UI — e.g. the Home rails — can recompute immediately instead of waiting for its next
    /// `.task`. Wired by the composition root (`AppSession`); `nil` in isolation/tests by default.
    public var onContentChanged: (@MainActor () async -> Void)?

    public init(library: LibraryProviding, watch: WatchProgressProviding? = nil) {
        self.library = library
        self.watch = watch
    }

    public func load() async {
        if let cached = library.loadCached() { apply(cached) } else { state = .loading }
        do {
            let items = try await library.refresh()
            try Task.checkCancellation()   // a retry cancels the old task — don't apply a stale result
            apply(items)
        } catch is CancellationError {
            // Superseded by a newer load(); leave state for the new task to set.
        } catch {
            // Keep any cache visible; only surface a failure when there's nothing to show.
            if movies.isEmpty, shows.isEmpty { state = .failed(Self.message(for: error)) }
        }
    }

    public func retry() { attempt += 1 }

    /// Permanently remove an item from Real-Debrid, purge its watch progress, and drop it from
    /// the in-memory library (optimistic). On failure the item is kept and `removal` becomes
    /// `.failed`. Safe to call from a confirmation handler.
    public func remove(_ item: MediaItem) async {
        removal = .removing(item)
        do {
            try await library.remove(item)
            try? await watch?.deleteProgress(forContentKeys: Self.contentKeys(for: item))
            movies.removeAll { $0.id == item.id }
            shows.removeAll { $0.id == item.id }
            if movies.isEmpty && shows.isEmpty { state = .empty }
            removal = .idle
            await onContentChanged?()
        } catch {
            removal = .failed("Couldn\u{2019}t remove \u{201C}\(item.title)\u{201D}. Please try again.")
        }
    }

    /// Dismiss a surfaced removal error (call from the alert's OK button).
    public func clearRemovalError() { removal = .idle }

    /// Watch-progress keys an item owns: the movie key, or every episode key for a show.
    static func contentKeys(for item: MediaItem) -> [String] {
        switch item.kind {
        case .movie:
            return [WatchKey.content(forMovie: item)]
        case .show:
            return item.seasons.flatMap { season in
                season.episodes.map { WatchKey.content(forShow: item, episode: $0) }
            }
        }
    }

    /// TMDB ids of every title currently in the library — for the "In Library" badge in Browse.
    public var ownedTMDBIDs: Set<Int> { Set((movies + shows).compactMap { $0.tmdbID }) }

    /// The library item for a TMDB id, if owned — so a Browse poster can open its Detail.
    public func ownedItem(tmdbID: Int) -> MediaItem? {
        (movies + shows).first { $0.tmdbID == tmdbID }
    }

    private func apply(_ items: [MediaItem]) {
        movies = items.filter { $0.kind == .movie }
        shows = items.filter { $0.kind == .show }
        state = (movies.isEmpty && shows.isEmpty) ? .empty : .loaded
    }

    private static func message(for error: Error) -> String {
        "Couldn't load your library. Check your connection and try again."
    }
}
