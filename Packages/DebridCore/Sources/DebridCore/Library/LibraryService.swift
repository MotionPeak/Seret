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

        // Only the torrents that actually need looking at.
        //
        // This used to fetch `/torrents/info` for the ENTIRE account on any delta, however small:
        // adding one title to a large library meant a request per torrent it already had, for
        // content already sitting in the snapshot. Everything a settled torrent contributed is in
        // the cached items — its sources carry the file, the link and the parse — so an unchanged
        // one has nothing left to tell us.
        let rdTorrentIDs = Set(rdTorrents.map(\.id))
        let changedIDs: Set<String> = {
            // No recorded states means the snapshot predates them: nothing is known to be settled.
            guard let seen else { return rdTorrentIDs }
            return Set(rdTorrents.filter { !seen.contains(LibraryReconciler.state(of: $0)) }.map(\.id))
        }()
        let goneIDs = Set(snapshot?.seenTorrentIDs ?? []).subtracting(rdTorrentIDs)

        // A cached item touching a changed OR removed torrent has to be rebuilt from ALL of its
        // remaining torrents — a show's episodes come from several, and rebuilding from just the
        // changed one would drop the rest.
        let unsettled = changedIDs.union(goneIDs)
        let dirtyItems = cached.filter {
            !LibraryReconciler.torrentIDs(of: $0).isDisjoint(with: unsettled)
        }
        let dirtyIDs = changedIDs
            .union(dirtyItems.flatMap { LibraryReconciler.torrentIDs(of: $0) })
            .intersection(rdTorrentIDs)          // never ask about one RD no longer has

        let fetchList = rdTorrents.filter { dirtyIDs.contains($0.id) }
        let infos = try await torrents.allTorrentInfos(from: fetchList)
        let fresh = builder.group(infos)
        // `allTorrentInfos` skips a torrent whose `/torrents/info` call failed rather than failing
        // the whole load, so a transient 5xx silently yields no item for a torrent RD still holds.
        let resolved = Set(infos.map(\.id))
        let unresolvedIDs = dirtyIDs.subtracting(resolved)

        // Items nothing touched: carried through exactly as they were. An item any of whose
        // torrents RD no longer lists is NOT carried — it is rebuilt (or, if all of them are gone,
        // correctly disappears).
        let dirtyItemIDs = Set(dirtyItems.map(\.id))
        let untouched = cached.filter { item in
            guard !dirtyItemIDs.contains(item.id) else { return false }
            let ids = LibraryReconciler.torrentIDs(of: item)
            return !ids.isEmpty && ids.allSatisfy(rdTorrentIDs.contains)
        }

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
        // Only when RD still lists every one of its torrents: a partly-deleted item must take the
        // rebuild, or the delete would be undone.
        let rescued = dirtyItems.filter { item in
            let ids = LibraryReconciler.torrentIDs(of: item)
            return !ids.isEmpty
                && ids.allSatisfy(rdTorrentIDs.contains)
                && ids.allSatisfy(unresolvedIDs.contains)
        }

        // Enrichment re-keys each item by TMDB id, so separate torrents of one title only collide
        // here — fold them into a single entry carrying every version. That is also what folds a
        // freshly-grouped item into the untouched one it belongs with: a new episode's torrent
        // groups on its own here, and merges into the show that was carried through.
        let library = merger.merge(assembled + untouched + rescued)

        // A torrent counts as settled when we resolved it this round, or when we deliberately did
        // not ask about it because nothing had changed. An UNRESOLVED one is left out, so the next
        // refresh sees a delta and retries it instead of recording a failure as a known state.
        let settledIDs = resolved.union(rdTorrentIDs.subtracting(dirtyIDs))
        let persistedStates = LibraryReconciler.states(of: rdTorrents.filter { settledIDs.contains($0.id) })

        // Best-effort: a cache-write failure (e.g. a sandbox/storage hiccup) must NEVER fail the
        // refresh — the freshly-built library still displays, it just won't be cached this time.
        try? store.save(LibrarySnapshot(items: library,
                                        seenTorrentIDs: Array(settledIDs),
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
        try store.save(LibrarySnapshot(items: remaining,
                                       seenTorrentIDs: Self.dropping(deleted, from: snapshot?.seenTorrentIDs),
                                       seenTorrentStates: Self.droppingStates(deleted, from: snapshot?.seenTorrentStates)))
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
        let deleted: Set<String> = [source.torrentID]
        try store.save(LibrarySnapshot(items: updated,
                                       seenTorrentIDs: Self.dropping(deleted, from: snapshot?.seenTorrentIDs),
                                       seenTorrentStates: Self.droppingStates(deleted, from: snapshot?.seenTorrentStates)))
    }

    /// Carry the recorded torrent ids forward, minus the ones just deleted. Dropping the set
    /// entirely made the very next `refresh()` see every torrent as new and re-run the whole
    /// `/torrents/info` fan-out plus a full re-enrichment — so removing one title rebuilt the
    /// entire library.
    private static func dropping(_ deleted: Set<String>, from seen: [String]?) -> [String] {
        (seen ?? []).filter { !deleted.contains($0) }
    }

    /// The same, for the `id:status` states. Kept `nil` when the snapshot had none, so an
    /// older snapshot still forces exactly one delta rather than silently claiming a clean state.
    private static func droppingStates(_ deleted: Set<String>, from seen: [String]?) -> [String]? {
        seen.map { states in
            states.filter { !deleted.contains($0.split(separator: ":").first.map(String.init) ?? $0) }
        }
    }

    /// The unique set of RD torrent ids backing an item: a movie's source torrents, or every
    /// torrent behind every EPISODE VERSION for a show (season packs collapse to one id).
    ///
    /// The alternates matter. An episode is modelled as a primary source plus alternate versions,
    /// each from its own RD torrent, so collecting only `episode.source` left every alternate in
    /// the account — and the very next refresh rebuilt the show from them. Deleting a show looked
    /// like it had worked and then undid itself.
    static func torrentIDs(for item: MediaItem) -> [String] {
        Array(LibraryReconciler.torrentIDs(of: item))
    }
}
