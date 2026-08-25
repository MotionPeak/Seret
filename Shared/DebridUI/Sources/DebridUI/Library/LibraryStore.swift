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
    /// Watched state for the library's titles, keyed by `WatchKey.content(forMovie:)` — drives the
    /// grid's watched badge. A show hangs off the series key its marker writes, so a show marked
    /// watched anywhere reads as watched here too.
    public private(set) var watchByKey: [String: WatchState] = [:]

    /// Bumped by every successful removal. A `load()` captures it at entry and refuses to apply a
    /// result fetched before that removal happened.
    ///
    /// Opening the grid starts a refresh, and it spends a second or two inside RD's paginated
    /// torrent list — which is exactly when a viewer long-presses a tile and removes it. The
    /// deletion went through at RD, the grid dropped the tile, and then the in-flight refresh
    /// applied the list it had already fetched and put the tile straight back. Nothing was wrong
    /// with the removal; it just looked like it had never happened.
    private var contentGeneration = 0

    private let library: LibraryProviding
    private let watch: WatchProgressProviding?
    /// The active profile whose progress the badges reflect — a closure (not a stored id) because
    /// the store is long-lived across profile switches (see `reloadWatchStates()`).
    private let profileID: @MainActor () -> String?

    /// Fired after the library's contents change (currently: a successful removal) so dependent
    /// UI — e.g. the Home rails — can recompute immediately instead of waiting for its next
    /// `.task`. Wired by the composition root (`AppSession`); `nil` in isolation/tests by default.
    public var onContentChanged: (@MainActor () async -> Void)?

    public init(library: LibraryProviding, watch: WatchProgressProviding? = nil,
                profileID: @escaping @MainActor () -> String? = { nil }) {
        self.library = library
        self.watch = watch
        self.profileID = profileID
    }

    #if DEBUG
    /// Test-only: seed the split arrays without a network/library round-trip.
    func setForTest(movies: [MediaItem], shows: [MediaItem]) { apply(movies + shows) }
    #endif

    /// The load currently in flight, if any. Two screens share one store — on iPhone, Home and My
    /// Library both ask it to load — and without this each one ran its own `library.refresh()`:
    /// the whole Real-Debrid pagination, the `/torrents/info` fan-out and a TMDB enrichment pass,
    /// twice over, for one answer. A second caller now waits for the first instead.
    private var loadTask: Task<Void, Never>?
    /// Set when a reload is asked for while one is already running. The in-flight load is answering
    /// a question asked BEFORE that request, so joining it would hand back an answer that predates
    /// the thing being reloaded for — a download that just landed would not appear until something
    /// else happened to reload. The running load finishes, then one more runs.
    private var reloadPending = false

    public func load() async {
        // A joiner only waits. It must NOT consume `reloadPending`: both it and the owner resume
        // when the task finishes, and if the joiner got there first it cleared the flag, re-entered,
        // joined the same already-finished task and returned — leaving the owner with nothing to
        // do. The reload was silently dropped, which is exactly the case it exists for: a download
        // that landed mid-refresh still never reached the library.
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performLoad()
        }
        loadTask = task
        await task.value
        loadTask = nil
        // The owner, and only the owner, runs whatever was asked for while it was busy.
        if reloadPending {
            reloadPending = false
            await load()
        }
    }

    private func performLoad() async {
        let generation = contentGeneration
        if let cached = await library.loadCachedOffMain(), generation == contentGeneration {
            apply(cached)
            await reloadWatchStates()
        } else if movies.isEmpty, shows.isEmpty {
            state = .loading
        }
        do {
            let items = try await library.refresh()
            try Task.checkCancellation()   // a retry cancels the old task — don't apply a stale result
            // …and a removal that happened while this was in flight outranks it. See
            // `contentGeneration`: without this the deleted title came straight back.
            guard generation == contentGeneration else { return }
            apply(items)
            await reloadWatchStates()
        } catch is CancellationError {
            // Superseded by a newer load(); leave state for the new task to set.
        } catch {
            // Keep any cache visible; only surface a failure when there's nothing to show.
            if movies.isEmpty, shows.isEmpty { state = .failed(Self.message(for: error)) }
        }
    }

    /// Ask for a fresh load. Bumping `attempt` drives the `.task(id:)` on whichever screen is
    /// showing the grid — but that only works while such a screen is MOUNTED, so a caller with no
    /// view behind it (a finished download, say) must use `reload()` instead.
    public func retry() { attempt += 1 }

    /// Reload now, whether or not any screen is watching. `retry()` alone only bumps a counter, so
    /// a download that finished while the viewer was on Home never reached the library until they
    /// happened to open My Library.
    public func reload() {
        attempt += 1
        if loadTask != nil { reloadPending = true }
        Task { @MainActor [weak self] in await self?.load() }
    }

    /// Permanently remove an item from Real-Debrid, purge its watch progress, and drop it from
    /// the in-memory library (optimistic). On failure the item is kept and `removal` becomes
    /// `.failed`. Safe to call from a confirmation handler.
    public func remove(_ item: MediaItem) async {
        removal = .removing(item)
        do {
            try await library.remove(item)
            contentGeneration += 1     // outrank any refresh fetched before this deletion
            try? await watch?.deleteProgress(forContentKeys: Self.contentKeys(for: item))
            movies.removeAll { $0.id == item.id }
            shows.removeAll { $0.id == item.id }
            reindexOwned()
            if movies.isEmpty && shows.isEmpty { state = .empty }
            removal = .idle
            await onContentChanged?()
        } catch {
            removal = .failed("Couldn\u{2019}t remove \u{201C}\(item.title)\u{201D}. Please try again.")
        }
    }

    /// Remove ONE version (a `MediaSource`) from a movie. If it was the last source the whole
    /// item is dropped; otherwise the item stays with that one source removed. On failure the
    /// library is untouched and `removal` becomes `.failed`.
    public func removeVersion(_ item: MediaItem, source: MediaSource) async {
        removal = .removing(item)
        do {
            try await library.removeVersion(item, source: source)
            contentGeneration += 1     // …same for a single version
            let remaining = item.sources.filter { $0 != source }
            if remaining.isEmpty {
                movies.removeAll { $0.id == item.id }
                shows.removeAll { $0.id == item.id }
                reindexOwned()
                try? await watch?.deleteProgress(forContentKeys: Self.contentKeys(for: item))
                if movies.isEmpty && shows.isEmpty { state = .empty }
            } else {
                // Replace in-memory item with one that has the version dropped (optimistic).
                let updated = MediaItem(id: item.id, kind: item.kind, title: item.title, year: item.year,
                                        sources: remaining, seasons: item.seasons,
                                        tmdbID: item.tmdbID, posterPath: item.posterPath,
                                        backdropPath: item.backdropPath, overview: item.overview,
                                        addedAt: item.addedAt)
                movies = movies.map { $0.id == item.id ? updated : $0 }
                reindexOwned()
            }
            removal = .idle
            await onContentChanged?()
        } catch {
            removal = .failed("Couldn\u{2019}t remove that version. Please try again.")
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

    /// TMDB id → library item, rebuilt only when the library itself changes.
    ///
    /// Both lookups below are read from a poster's `body`, once per tile. They used to build a
    /// fresh `movies + shows` array — the WHOLE library — and scan it linearly, every call. A
    /// browse page is dozens of posters and tvOS re-evaluates them on every focus move, so a large
    /// account was copying its entire library hundreds of times a second just to decide whether to
    /// draw an "In Library" badge.
    private var ownedByTMDBID: [Int: MediaItem] = [:]

    /// TMDB ids of every title currently in the library — for the "In Library" badge in Browse.
    public var ownedTMDBIDs: Set<Int> { Set(ownedByTMDBID.keys) }

    /// The library item for a TMDB id, if owned — so a Browse poster can open its Detail.
    public func ownedItem(tmdbID: Int) -> MediaItem? { ownedByTMDBID[tmdbID] }

    // MARK: - Watch state (movies only)

    /// The id progress is read/written under — mirrors `DetailStore.watchProfileID` (a nil active
    /// profile falls back to "", the same key `AppSession.makePlayer` saves under).
    private var watchProfileID: String { profileID() ?? "" }

    /// Watched state for a library item, movie or show.
    ///
    /// A show hangs off its own id — the series key `ShowWatchMarker` writes alongside the episode
    /// fan-out, and the same shape `WatchKey.content(forMovie:)` produces. Browse has always read
    /// it; My Library did not, so one title showed a tick in one grid and not the other.
    public func watchState(for item: MediaItem) -> WatchState? {
        watchByKey[WatchKey.content(forMovie: item)]
    }

    /// Re-read every movie's watched state in one batched call. Called at the end of `load()` and by
    /// the grid screens on a profile switch (the store outlives a switch, so the map must be rebuilt
    /// for the newly-active profile). Degrades to empty with no watch seam.
    public func reloadWatchStates() async {
        guard let watch else { watchByKey = [:]; return }
        let keys = (movies + shows).map { WatchKey.content(forMovie: $0) }
        guard !keys.isEmpty else { watchByKey = [:]; return }
        watchByKey = (try? await watch.progress(forContentKeys: keys, profileID: watchProfileID)) ?? [:]
    }

    /// Mark a MOVIE watched/unwatched from the grid (long-press / hold). No-op for a show (mark its
    /// episodes inside Detail) or a movie with no source. Refreshes just that key and notifies
    /// dependents so Continue Watching drops a now-finished title.
    public func setWatched(_ watched: Bool, for item: MediaItem) async {
        guard let watch, item.kind == .movie, let source = item.sources.best else { return }
        let key = WatchKey.content(forMovie: item)
        await watch.setWatched(watched, contentKey: key, source: source, profileID: watchProfileID)
        watchByKey[key] = try? await watch.progress(forContentKey: key, profileID: watchProfileID)
        await onContentChanged?()
    }

    private func apply(_ items: [MediaItem]) {
        movies = items.filter { $0.kind == .movie }
        shows = items.filter { $0.kind == .show }
        reindexOwned()
        state = (movies.isEmpty && shows.isEmpty) ? .empty : .loaded
    }

    /// Rebuild the ownership index from the current arrays. Must run after EVERY mutation of
    /// `movies`/`shows` — the removal paths edit them directly rather than going through
    /// `apply(_:)`, and while the index was only built there, a deleted title kept its "In Library"
    /// badge in Browse and its poster still opened a Detail with a live Play button over a torrent
    /// that no longer existed.
    private func reindexOwned() {
        // First one wins, matching the linear `first(where:)` this replaced.
        ownedByTMDBID = Dictionary((movies + shows).compactMap { item in item.tmdbID.map { ($0, item) } },
                                   uniquingKeysWith: { first, _ in first })
    }

    private static func message(for error: Error) -> String {
        "Couldn't load your library. Check your connection and try again."
    }
}
