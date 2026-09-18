import Foundation

/// Keeps the stored watchlist in step with Letterboxd.
///
/// Every sync is a full crawl, which is what makes it a mirror: additions and removals both land.
/// An earlier design had a cheap page-one path that stopped at the first known film; it was dropped
/// because it needs a page-at-a-time reader, saves three requests, cannot see removals, and makes
/// every position below the merge point a question.
public actor WatchlistSyncer {
    private let reader: any LetterboxdProfileReading
    private let resolver: any WatchlistTitleResolving
    private let store: WatchlistStore
    private let resolveDelay: Duration

    public init(reader: any LetterboxdProfileReading,
                resolver: any WatchlistTitleResolving,
                store: WatchlistStore,
                resolveDelay: Duration = .milliseconds(250)) {
        self.reader = reader
        self.resolver = resolver
        self.store = store
        self.resolveDelay = resolveDelay
    }

    /// What is on disk. No network.
    public func cached() -> [WatchlistEntry] { store.load() }

    /// Crawls, merges, resolves anything unresolved, persists, and returns the result in order.
    public func sync(onProgress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> [WatchlistEntry] {
        // Throws before anything is written: a failed crawl must leave the mirror alone, because an
        // empty screen after a network blip reads as "your watchlist is gone".
        let crawled = try await reader.watchlist()

        var merged = WatchlistReconciler.merge(crawled: crawled, into: store.load())

        // Only what has never been tried. A film TMDB does not know stays unresolved rather than
        // being searched again on every sync forever.
        let pending = merged.indices.filter { !merged[$0].isResolved }
        var done = 0

        for index in pending {
            let entry = merged[index]
            if let match = try? await resolver.match(name: entry.name, year: entry.year) {
                merged[index].tmdbID = match.tmdbID
                merged[index].posterPath = match.posterPath
            }
            merged[index].resolvedAt = Date()

            done += 1
            onProgress?(done, pending.count)

            if resolveDelay > .zero, done < pending.count {
                try await Task.sleep(for: resolveDelay)
            }
        }

        store.save(merged)
        return merged
    }
}
