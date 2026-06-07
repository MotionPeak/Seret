import Foundation

/// The brain's top-level library API: load the cached library instantly (offline-capable),
/// and refresh it against Real-Debrid incrementally — only genuinely-new content costs a TMDB call.
public struct LibraryService: Sendable {
    private let torrents: TorrentsClient
    private let builder: LibraryBuilder
    private let enricher: MetadataEnricher
    private let store: LibrarySnapshotStore
    private let reconciler: LibraryReconciler

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
    /// or an unreadable cache.
    public func loadCached() -> [MediaItem]? {
        store.load()?.items
    }

    /// Reconcile the cache against RD. Cheap when nothing changed (one torrent-list call); on a
    /// delta, re-groups and enriches only new items, then persists. Throws on RD/network failure
    /// (the caller keeps showing `loadCached()`).
    @discardableResult
    public func refresh() async throws -> [MediaItem] {
        let cached = loadCached() ?? []
        let rdTorrentIDs = Set(try await torrents.allTorrents().map(\.id))
        guard reconciler.hasDelta(cached: cached, rdTorrentIDs: rdTorrentIDs) else {
            return cached
        }

        let infos = try await torrents.allTorrentInfos()
        let fresh = builder.group(infos)
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
        let library = plan.map { step -> MediaItem in
            switch step {
            case .carried(let item):
                return item
            case .needsEnrichment:
                let item = enriched[enrichedIndex]
                enrichedIndex += 1
                return item
            }
        }

        try store.save(LibrarySnapshot(items: library))
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
        let remaining = (store.load()?.items ?? []).filter { $0.id != item.id }
        try store.save(LibrarySnapshot(items: remaining))
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
        let updated = (store.load()?.items ?? []).map { $0.id == item.id ? updatedItem : $0 }
        try store.save(LibrarySnapshot(items: updated))
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
