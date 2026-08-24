import Foundation

/// The brain's top-level library API: load the cached library instantly (offline-capable),
/// and refresh it against Real-Debrid incrementally — only genuinely-new content costs a TMDB call.
public struct LibraryService: Sendable {
    private let torrents: TorrentsClient
    private let builder: LibraryBuilder
    private let enricher: MetadataEnricher
    private let store: LibrarySnapshotStore
    private let reconciler: LibraryReconciler
    private let merger = LibraryMerger()

    public init(torrents: TorrentsClient, builder: LibraryBuilder,
                enricher: MetadataEnricher, store: LibrarySnapshotStore,
                reconciler: LibraryReconciler = LibraryReconciler()) {
        self.torrents = torrents
        self.builder = builder
        self.enricher = enricher
        self.store = store
        self.reconciler = reconciler
    }

    /// The last persisted library, decoded from disk. Instant and offline; `nil` on first run
    /// or an unreadable cache. Merged on the way out so a snapshot written before merging existed
    /// (duplicate ids for one title) heals on the next launch, without waiting for a refresh.
    public func loadCached() -> [MediaItem]? {
        guard let items = store.load()?.items else { return nil }
        return merger.merge(items)
    }

    /// Reconcile the cache against RD. Cheap when nothing changed (one torrent-list call); on a
    /// delta, re-groups and enriches only new items, then persists. Throws on RD/network failure
    /// (the caller keeps showing `loadCached()`).
    @discardableResult
    public func refresh() async throws -> [MediaItem] {
        let snapshot = store.load()
        let cached = snapshot?.items ?? []
        let seen = snapshot?.seenTorrentStates.map(Set.init)
        let rdTorrents = try await torrents.allTorrents()
        let rdTorrentStates = LibraryReconciler.states(of: rdTorrents)
        // Compare against the persisted seen set (exact), NOT ids derived from items — otherwise a
        // non-video torrent looks "new" forever and re-runs the whole info fan-out every launch.
        // The set is keyed by `id:status`, not id alone: a torrent keeps its id from the moment RD
        // starts downloading it, so an id-only comparison saw no change on the one transition that
        // makes a title playable, and a finished download never appeared.
        guard reconciler.hasDelta(seenTorrentStates: seen, rdTorrentStates: rdTorrentStates) else {
            return cached
        }

        // Reuses the list fetched just above. It used to call the no-argument version, which
        // paginates the whole account a SECOND time on every refresh that finds a delta.
        let infos = try await torrents.allTorrentInfos(from: rdTorrents)
        let fresh = builder.group(infos)
        // `allTorrentInfos` skips a torrent whose `/torrents/info` call failed rather than failing
        // the whole load, so a transient 5xx silently yields no item for a torrent RD still holds.
        let resolved = Set(infos.map(\.id))
        let unresolved = rdTorrents.filter { !resolved.contains($0.id) }
        let plan = reconciler.reconcile(fresh: fresh, cached: cached)

        let toEnrich = plan.compactMap { step -> MediaItem? in
            if case .needsEnrichment(let item) = step { return item } else { return nil }
        }
        let enriched = await enricher.enrich(toEnrich)

        // `enriched` has exactly one result per `.needsEnrichment` step, in order
        // (MetadataEnricher.enrich returns one element per input, preserving order), so this
        // index is always in range — an out-of-range access would fail fast rather than
        // silently inserting a placeholder.
        var enrichedIndex = 0
        let assembled = plan.map { step -> MediaItem in
            switch step {
            case .carried(let item):
                return item
            case .needsEnrichment:
                let item = enriched[enrichedIndex]
                enrichedIndex += 1
                return item
            }
        }

        // A title whose every backing torrent failed to resolve this round is absent from `fresh`
        // purely because of that failure — RD still lists those torrents. Dropping it would write
        // the title out of the snapshot, and since its ids were recorded as seen, no later refresh
        // would reconsider it: a transient 5xx erased a title permanently. Carry it over untouched.
        let unresolvedIDs = Set(unresolved.map(\.id))
        let rescued = cached.filter { item in
            let ids = LibraryReconciler.torrentIDs(of: item)
            return !ids.isEmpty && ids.allSatisfy(unresolvedIDs.contains)
        }

        // Enrichment re-keys each item by TMDB id, so separate torrents of one title only collide
        // here — fold them into a single entry carrying every version.
        let library = merger.merge(assembled + rescued)

        // Record only the torrents we actually resolved. Leaving an unresolved one out means the
        // next refresh sees a delta and retries it, instead of treating a failure as a known state.
        let persistedStates = LibraryReconciler.states(of: rdTorrents.filter { resolved.contains($0.id) })

        // Best-effort: a cache-write failure (e.g. a sandbox/storage hiccup) must NEVER fail the
        // refresh — the freshly-built library still displays, it just won't be cached this time.
        try? store.save(LibrarySnapshot(items: library,
                                        seenTorrentIDs: Array(resolved),
                                        seenTorrentStates: Array(persistedStates)))
        return library
    }

    /// Permanently delete an item from Real-Debrid: removes every torrent backing it, then drops
    /// it from the persisted snapshot. Idempotent — a `404` (torrent already gone) counts as
    /// success. Any other RD/network failure throws WITHOUT rewriting the snapshot, so the next
    /// `refresh()` reconciles the UI to reality.
    public func remove(_ item: MediaItem) async throws {
        for id in Self.torrentIDs(for: item) {
            do {
                try await torrents.deleteTorrent(id: id)
            } catch HTTPError.status(let code, _) where code == 404 {
                continue   // already deleted — treat as success
            }
        }
        // Carry the seen-torrent set forward, minus what was just deleted. Dropping it (the
        // default is empty) made the very next `refresh()` see every torrent as new and re-run the
        // whole `/torrents/info` fan-out plus a full re-enrichment — so removing one title rebuilt
        // the entire library.
        let snapshot = store.load()
        let remaining = (snapshot?.items ?? []).filter { $0.id != item.id }
        let deleted = Set(Self.torrentIDs(for: item))
        let seen = (snapshot?.seenTorrentIDs ?? []).filter { !deleted.contains($0) }
        try store.save(LibrarySnapshot(items: remaining, seenTorrentIDs: seen))
    }

    /// Remove ONE version (a single `MediaSource`) from a movie: deletes its backing torrent on
    /// RD, then rewrites the persisted snapshot with that source dropped. If it's the LAST source
    /// the whole item is removed (delegates to `remove`). Idempotent (404 → success). Throws on
    /// any other RD failure WITHOUT rewriting the snapshot. Show-kind items are not supported
    /// (versioning is per-episode-pack, not addressable here).
    public func removeVersion(_ item: MediaItem, source: MediaSource) async throws {
        guard item.kind == .movie else { return }
        let remainingSources = item.sources.filter { $0 != source }
        if remainingSources.isEmpty { try await remove(item); return }
        do {
            try await torrents.deleteTorrent(id: source.torrentID)
        } catch HTTPError.status(let code, _) where code == 404 {
            // already gone — fall through to snapshot rewrite
        }
        let updatedItem = MediaItem(id: item.id, kind: item.kind, title: item.title, year: item.year,
                                    sources: remainingSources, seasons: item.seasons,
                                    tmdbID: item.tmdbID, posterPath: item.posterPath,
                                    backdropPath: item.backdropPath, overview: item.overview,
                                    addedAt: item.addedAt)
        let snapshot = store.load()
        let updated = (snapshot?.items ?? []).map { $0.id == item.id ? updatedItem : $0 }
        let seen = (snapshot?.seenTorrentIDs ?? []).filter { $0 != source.torrentID }
        try store.save(LibrarySnapshot(items: updated, seenTorrentIDs: seen))
    }

    /// The unique set of RD torrent ids backing an item: a movie's source torrents, or every
    /// episode's source torrent for a show (season packs collapse to one id).
    static func torrentIDs(for item: MediaItem) -> [String] {
        switch item.kind {
        case .movie:
            return Array(Set(item.sources.map(\.torrentID)))
        case .show:
            return Array(Set(item.seasons.flatMap { $0.episodes.map(\.source.torrentID) }))
        }
    }
}
