import DebridCore
import Observation

/// The library UI's single source of truth: cache-first instant render, then a background
/// refresh against RD. No RD/TMDB logic here — it delegates to `LibraryProviding`.
@MainActor
@Observable
public final class LibraryStore {
    public enum State: Equatable { case loading, loaded, empty, failed(String) }

    public private(set) var state: State = .loading
    public private(set) var movies: [MediaItem] = []
    public private(set) var shows: [MediaItem] = []
    /// Bumped by `retry()`; drives the shell's `.task(id:)` so a retry re-runs `load()`.
    public private(set) var attempt = 0

    private let library: LibraryProviding

    public init(library: LibraryProviding) { self.library = library }

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
