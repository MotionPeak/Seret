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

        var enrichedIterator = enriched.makeIterator()
        let library = plan.map { step -> MediaItem in
            switch step {
            case .carried(let item): return item
            case .needsEnrichment: return enrichedIterator.next() ?? MediaItem(
                id: "", kind: .movie, title: "", year: nil, sources: [], seasons: [])
            }
        }

        try store.save(LibrarySnapshot(items: library))
        return library
    }
}
