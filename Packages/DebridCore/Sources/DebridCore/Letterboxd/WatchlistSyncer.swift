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

    /// Removals the owner has made here that Letterboxd has not been told about yet.
    ///
    /// Only films with a TMDB id: the push resolves a film by that id, so one without is a
    /// removal that can be honoured locally and nowhere else.
    public func pendingRemovals() -> [WatchlistEntry] {
        store.load().filter { $0.needsRemovalPush && $0.tmdbID != nil }
    }

    /// Records that Letterboxd has accepted the removal, so it stops being pending.
    @discardableResult
    public func markRemovalPushed(slug: String, at when: Date = Date()) -> [WatchlistEntry] {
        var entries = store.load()
        guard let index = entries.firstIndex(where: { $0.slug == slug }) else { return entries }
        entries[index].removalPushedAt = when
        store.save(entries)
        return entries
    }

    /// Adds a film the owner picked in Seret, and says it still has to reach Letterboxd.
    ///
    /// Idempotent, because the control that calls it is a toggle that any number of screens can
    /// show at once. A film the mirror already holds is left exactly as it is — adding a second row
    /// for it would show it twice and queue a write with nothing behind it.
    ///
    /// Re-adding one the owner had removed is the interesting case, and it splits:
    ///   * the removal already reached Letterboxd, so asking for the film back is a real write;
    ///   * the removal never left the device, so this is a pure local undo and nothing is queued.
    @discardableResult
    public func add(tmdbID: Int, title: String, year: Int?, posterPath: String?,
                    at when: Date = Date()) -> [WatchlistEntry] {
        var entries = store.load()

        if let index = entries.firstIndex(where: { $0.tmdbID == tmdbID }) {
            guard entries[index].isRemoved else { return entries }
            // Letterboxd was never told about the removal, so it still lists the film: undoing the
            // mark is the whole job. Queueing an add here would ask for something already true.
            let removalReachedLetterboxd = !entries[index].needsRemovalPush
            entries[index].removedAt = nil
            entries[index].removalPushedAt = nil
            if removalReachedLetterboxd {
                entries[index].addedLocallyAt = when
                entries[index].addPushedAt = nil
            }
            store.save(entries)
            return entries
        }

        // Ahead of everything stored: Letterboxd orders newest first and this is the newest there
        // is. Negative positions are fine — nothing reads a position except the sort.
        let front = (entries.map(\.position).min() ?? 0) - 1
        entries.append(.locallyAdded(tmdbID: tmdbID, title: title, year: year,
                                     posterPath: posterPath, position: front, at: when))
        store.save(entries)
        return entries.sorted { $0.position < $1.position }
    }

    /// Adds the owner made here that Letterboxd has not been told about yet.
    ///
    /// A row the owner has since removed is excluded: pushing the add first and the removal second
    /// would be two writes to arrive where no write at all was needed.
    public func pendingAdds() -> [WatchlistEntry] {
        store.load().filter { $0.needsAddPush && !$0.isRemoved && $0.tmdbID != nil }
    }

    /// Records that Letterboxd has accepted the add, so it stops being pending.
    @discardableResult
    public func markAddPushed(slug: String, at when: Date = Date()) -> [WatchlistEntry] {
        var entries = store.load()
        guard let index = entries.firstIndex(where: { $0.slug == slug }) else { return entries }
        entries[index].addPushedAt = when
        store.save(entries)
        return entries
    }

    /// The mirror's row for a TMDB id, which is the only identity the app's screens have.
    public func entry(forTMDB id: Int) -> WatchlistEntry? {
        store.load().first { $0.tmdbID == id }
    }

    /// Marks a film as removed by the owner and persists it. No network — the mirror is edited in
    /// place and the mark is carried through every later crawl by `WatchlistReconciler`.
    ///
    /// The entry is kept rather than deleted on purpose: deleting it here would achieve nothing,
    /// because the next crawl finds the film still on Letterboxd and puts it straight back. Until
    /// there is a real removal to push, "removed" is a fact about this mirror, not about the site.
    ///
    /// An existing mark is left alone, so the instant recorded is when the owner first asked.
    @discardableResult
    public func remove(slug: String) -> [WatchlistEntry] {
        var entries = store.load()
        guard let index = entries.firstIndex(where: { $0.slug == slug }) else { return entries }
        // Added here and never sent: there is nothing for Letterboxd to undo, and no crawl can hand
        // back a film it was never given — so the row is deleted rather than marked. A mark exists
        // only to survive a crawl, and this row has no crawl to survive.
        if entries[index].needsAddPush {
            entries.remove(at: index)
            store.save(entries)
            return entries
        }
        if entries[index].removedAt == nil { entries[index].removedAt = Date() }
        store.save(entries)
        return entries
    }

    /// Crawls, merges, resolves anything unresolved, persists, and returns the result in order.
    public func sync(onProgress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> [WatchlistEntry] {
        // Dated BEFORE the request, not after: an add pushed while this crawl was in flight cannot
        // be in what comes back, and the reconciler needs to know that to keep the film.
        let crawledAt = Date()

        // Throws before anything is written: a failed crawl must leave the mirror alone, because an
        // empty screen after a network blip reads as "your watchlist is gone".
        let crawled = try await reader.watchlist()

        var merged = WatchlistReconciler.merge(crawled: crawled, into: store.load(),
                                               crawledAt: crawledAt)

        // Only what has never been tried. A film TMDB does not know stays unresolved rather than
        // being searched again on every sync forever.
        let pending = merged.indices.filter { !merged[$0].isResolved }
        var done = 0

        for index in pending {
            try Task.checkCancellation()
            let entry = merged[index]

            do {
                if let match = try await resolver.match(name: entry.name, year: entry.year) {
                    merged[index].tmdbID = match.tmdbID
                    merged[index].posterPath = match.posterPath
                }
                // Searched. Found something or nothing — either way the question has been asked,
                // and `anUnmatchedFilmIsNotRetriedForever` depends on that being recorded.
                merged[index].resolvedAt = Date()
            } catch {
                // The search FAILED, which is not the same as TMDB not knowing the film. Leaving
                // `resolvedAt` nil is what lets the next sync ask again; stamping it here made one
                // bad minute of Wi-Fi a permanent grey box, since only the never-tried are retried.
            }

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
