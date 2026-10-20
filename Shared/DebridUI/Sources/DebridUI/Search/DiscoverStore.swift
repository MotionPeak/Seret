import DebridCore
import Foundation
import Observation

/// Kind-parameterized browse data source. One conformance (`TMDBDiscoverService`) backs both the
/// Movies and TV tabs; the store passes its `kind` to each call.
public protocol DiscoverProviding: Sendable {
    func nowPlayingMovies() async throws -> [TMDBSearchResult]                                   // CAM set
    func trending(_ kind: MediaKind, window: TMDBTrendingWindow) async throws -> [TMDBSearchResult]
    func topRatedCurated(_ kind: MediaKind) async throws -> [TMDBSearchResult]
    func newOverall(_ kind: MediaKind, from: String, to: String) async throws -> [TMDBSearchResult]
    func decade(_ kind: MediaKind, from: String, to: String) async throws -> [TMDBSearchResult]
    func recommended(_ kind: MediaKind, tmdbID: Int) async throws -> [TMDBSearchResult]
    func newByGenre(_ kind: MediaKind, _ genreID: Int, from: String, to: String) async throws -> [TMDBSearchResult]
    func popularByGenre(_ kind: MediaKind, _ genreID: Int) async throws -> [TMDBSearchResult]
    func topRatedByGenre(_ kind: MediaKind, _ genreID: Int) async throws -> [TMDBSearchResult]
}

/// Production conformance. Fetches **1 page per rail** (≈20 titles). (Measured: 2 pages ≈ 5× the
/// wall-time of 1 page for a full segment on a fast link — far worse on an Apple TV — so a single
/// page keeps browse snappy while still giving a full rail to scroll.)
public struct TMDBDiscoverService: DiscoverProviding {
    let client: TMDBClient
    public init(client: TMDBClient) { self.client = client }
    private static let pages = 1

    private func paged(_ f: (Int) async throws -> [TMDBSearchResult]) async rethrows -> [TMDBSearchResult] {
        var all: [TMDBSearchResult] = []
        for p in 1...Self.pages { all += try await f(p) }
        return all
    }

    public func nowPlayingMovies() async throws -> [TMDBSearchResult] { try await client.nowPlayingMovies() }

    public func trending(_ kind: MediaKind, window: TMDBTrendingWindow) async throws -> [TMDBSearchResult] {
        try await paged { p in kind == .movie ? try await client.trendingMovies(window: window, page: p)
                                              : try await client.trendingTV(window: window, page: p) }
    }
    public func topRatedCurated(_ kind: MediaKind) async throws -> [TMDBSearchResult] {
        try await paged { p in kind == .movie ? try await client.topRatedMoviesCurated(page: p)
                                              : try await client.topRatedTVCurated(page: p) }
    }
    public func newOverall(_ kind: MediaKind, from: String, to: String) async throws -> [TMDBSearchResult] {
        try await paged { p in kind == .movie ? try await client.discoverMovies(releaseFrom: from, releaseTo: to, page: p)
                                              : try await client.discoverTVNew(firstAirFrom: from, firstAirTo: to, page: p) }
    }
    public func decade(_ kind: MediaKind, from: String, to: String) async throws -> [TMDBSearchResult] {
        try await paged { p in kind == .movie ? try await client.decadeMovies(from: from, to: to, page: p)
                                              : try await client.decadeTV(from: from, to: to, page: p) }
    }
    public func recommended(_ kind: MediaKind, tmdbID: Int) async throws -> [TMDBSearchResult] {
        kind == .movie ? try await client.recommendedMovies(id: tmdbID) : try await client.recommendedTV(id: tmdbID)
    }
    public func newByGenre(_ kind: MediaKind, _ genreID: Int, from: String, to: String) async throws -> [TMDBSearchResult] {
        try await paged { p in kind == .movie ? try await client.discoverMovies(genreID: genreID, releaseFrom: from, releaseTo: to, page: p)
                                              : try await client.discoverTV(genreID: genreID, firstAirFrom: from, firstAirTo: to, page: p) }
    }
    public func popularByGenre(_ kind: MediaKind, _ genreID: Int) async throws -> [TMDBSearchResult] {
        try await paged { p in kind == .movie ? try await client.discoverMovies(genreID: genreID, page: p)
                                              : try await client.discoverTV(genreID: genreID, page: p) }
    }
    public func topRatedByGenre(_ kind: MediaKind, _ genreID: Int) async throws -> [TMDBSearchResult] {
        try await paged { p in kind == .movie ? try await client.topRatedMovies(genreID: genreID, page: p)
                                              : try await client.topRatedTV(genreID: genreID, page: p) }
    }
}

/// Kind-aware browse content across 5 segments, each a stack of horizontal rails. Segments load
/// **lazily** (the first time they're shown) and are cached for the session. Per-rail failures are
/// dropped; a segment with zero successful rails is `.failed`.
///
/// Separately, the **browse page** (`loadBrowsePage()` / `browseRows` / `browseState`): ONE list of
/// rows with no segments — up to three For You rows, Trending This Week, New This Month, Top Rated
/// of All Time, then a row per genre, Netflix-style. The Apple TV's Movies/Shows pages use it; the
/// iPhone and the Mac browse by segment. Both share the same progressive-load machinery.
@MainActor
@Observable
public final class DiscoverStore {
    public enum Segment: String, CaseIterable, Identifiable, Sendable {
        case forYou = "For You", trending = "Trending", newReleases = "New",
             popular = "Popular", topRated = "Top Rated"
        public var id: String { rawValue }
        public var title: String { rawValue }
    }
    public struct Row: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let hits: [SearchHit]
        /// The genre a browse-page genre row shows — what its "See All" opens. Nil on every other
        /// row (and on every segment rail).
        public let genre: Genre?
    }
    public enum State: Equatable { case idle, loading, loaded, failed }

    public var selectedSegment: Segment = .forYou
    public private(set) var rowsBySegment: [Segment: [Row]] = [:]
    private var statesBySegment: [Segment: State] = [:]
    public private(set) var camIDs: Set<Int> = []

    /// The browse page's rows, in page order (see `loadBrowsePage`).
    public private(set) var browseRows: [Row] = []
    /// The browse page's load state.
    public private(set) var browseState: State = .idle
    /// The ids of the browse page's For You rows as last built — the block a quiet rebuild swaps.
    private var browseForYouIDs: Set<String> = []
    /// At most this many For You rows lead the browse page.
    static let browseForYouLimit = 3

    /// What a load fills: one segment, or the browse page.
    private enum LoadTarget: Hashable {
        case segment(Segment)
        case page
    }

    public let kind: MediaKind
    private let discover: DiscoverProviding
    private let seeds: RecommendationSeedProviding?
    /// What For You was last built from: the best seeds there were at the time.
    private enum ForYouBasis: Int, Comparable {
        case trending   // no seeds at all — the library had not loaded
        case library    // library titles, but no watch history — the profile had not resolved
        case history    // "Because you watched…" — as personal as it gets
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }
    /// Per target. A target that was never built reads `.history`, so it is never "rebuilt".
    private var forYouBasis: [LoadTarget: ForYouBasis] = [:]
    /// The load running for each target. Owned by the store, NOT by whichever view asked: see
    /// `loadSegment`.
    private var loads: [LoadTarget: Task<Void, Never>] = [:]
    private let now: @Sendable () -> Date

    /// Selected-segment state, so existing view code can read one `state`.
    public var state: State { statesBySegment[selectedSegment] ?? .idle }
    public func segmentState(_ s: Segment) -> State { statesBySegment[s] ?? .idle }
    public var rows: [Row] { rowsBySegment[selectedSegment] ?? [] }
    public func isCAM(_ result: TMDBSearchResult) -> Bool { camIDs.contains(result.id) }
    public func select(_ segment: Segment) { selectedSegment = segment }

    /// A browsable genre. `id` is the TMDB genre id, which is what every discover call keys on.
    public struct Genre: Identifiable, Hashable, Sendable {
        public let name: String
        public let tmdbID: Int
        public var id: Int { tmdbID }
        public init(name: String, tmdbID: Int) {
            self.name = name
            self.tmdbID = tmdbID
        }
    }

    /// The genre table for a kind. Movie and TV genre ids differ — passing a movie id to a TV
    /// discover call returns an empty page rather than an error, so always go through this.
    public static func genres(for kind: MediaKind) -> [Genre] {
        (kind == .movie ? movieGenres : tvGenres).map { Genre(name: $0.0, tmdbID: $0.1) }
    }

    // Genre tables (display name, TMDB id). Movie and TV genre ids differ.
    static let movieGenres: [(String, Int)] = [
        ("Action", 28), ("Adventure", 12), ("Animation", 16), ("Comedy", 35), ("Crime", 80),
        ("Documentary", 99), ("Drama", 18), ("Family", 10751), ("Fantasy", 14), ("History", 36),
        ("Horror", 27), ("Music", 10402), ("Mystery", 9648), ("Romance", 10749),
        ("Sci-Fi", 878), ("Thriller", 53), ("War", 10752), ("Western", 37),
    ]
    static let tvGenres: [(String, Int)] = [
        ("Action & Adventure", 10759), ("Animation", 16), ("Comedy", 35), ("Crime", 80),
        ("Documentary", 99), ("Drama", 18), ("Family", 10751), ("Kids", 10762),
        ("Mystery", 9648), ("Reality", 10764), ("Sci-Fi & Fantasy", 10765),
        ("War & Politics", 10768), ("Western", 37),
    ]
    /// Decade rails (label, fromYear, toYear).
    static let decades: [(String, Int, Int)] = [
        ("Best of the 2020s", 2020, 2029), ("Best of the 2010s", 2010, 2019),
        ("Best of the 2000s", 2000, 2009), ("Best of the 90s", 1990, 1999),
    ]
    public static var movieGenreCount: Int { movieGenres.count }
    public static var tvGenreCount: Int { tvGenres.count }
    public static var decadeCount: Int { decades.count }

    /// This store's own kind's table. Named apart from the public `genres(for:)` so a type-level
    /// reference to that static isn't shadowed by an instance property.
    private var genreTable: [(String, Int)] { kind == .movie ? Self.movieGenres : Self.tvGenres }

    public init(kind: MediaKind, discover: DiscoverProviding,
                seeds: RecommendationSeedProviding? = nil,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.kind = kind; self.discover = discover; self.seeds = seeds; self.now = now
    }

    /// Back-compat: load the currently-selected segment.
    public func load() async { await loadSegment(selectedSegment) }

    /// Load one segment's rails if not already loaded/loading. Idempotent.
    ///
    /// **Progressive:** rails are fetched with a small concurrency cap and **published as each one
    /// completes** (in spec order), so the first rail appears in ~one request's time instead of
    /// after the whole segment finishes. The segment flips to `.loaded` the moment its first rail
    /// has content; if every rail comes back empty it ends `.failed`.
    ///
    /// **Owned by the store.** The load used to run inside the asking view's `.task`, so leaving the
    /// segment — or anything re-keying that task — cancelled it; an ask landing while it was still
    /// unwinding found the segment `.loading` and returned, and the cancelled load then set it back
    /// to `.idle`. Nobody was loading any more: skeletons for good. Now the load runs to completion
    /// in a task of its own, and every ask joins it — so a segment left mid-load is simply finished
    /// when the viewer comes back.
    public func loadSegment(_ segment: Segment) async { await load(.segment(segment)) }

    /// Load the browse page if not already loaded/loading. Idempotent; a failed page loads again
    /// (Retry). Row order: up to three For You rows ("Because you watched…" / "More like…"; none
    /// without seeds — Trending leads then), Trending This Week, New This Month, Top Rated of All
    /// Time, then one row per genre in the genre table's order, titled with the genre's name and
    /// carrying it (`Row.genre`) for its "See All".
    ///
    /// Progressive and store-owned exactly like `loadSegment`, with one difference: rows are NOT
    /// de-duplicated against each other — a title may be in Drama and in Thriller, as on Netflix.
    /// Inside one row a title appears once.
    public func loadBrowsePage() async { await load(.page) }

    private func load(_ target: LoadTarget) async {
        if let running = loads[target] { await running.value; return }
        switch state(of: target) {
        case .loading, .loaded: return
        case .idle, .failed: break
        }
        // The task clears its own entry before it completes, so whoever awaits it finds the
        // registry already empty — see `refreshForYouIfBetterSeeds`, which waits in a loop. Only
        // one load per target is ever registered (every ask joins a running one), so the entry it
        // clears is its own.
        let load = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performLoad(target)
            self.loads[target] = nil
        }
        loads[target] = load
        await load.value
    }

    private func state(of target: LoadTarget) -> State {
        switch target {
        case .segment(let s): statesBySegment[s] ?? .idle
        case .page: browseState
        }
    }

    private func setState(_ state: State, of target: LoadTarget) {
        switch target {
        case .segment(let s): statesBySegment[s] = state
        case .page: browseState = state
        }
    }

    private func rows(of target: LoadTarget) -> [Row] {
        switch target {
        case .segment(let s): rowsBySegment[s] ?? []
        case .page: browseRows
        }
    }

    private func setRows(_ rows: [Row], of target: LoadTarget) {
        switch target {
        case .segment(let s): rowsBySegment[s] = rows
        case .page: browseRows = rows
        }
    }

    /// Rebuild For You when better seeds exist than it was built from — called when what seeds it
    /// CHANGES (the library landing, the profile resolving), never merely because the page appeared.
    ///
    /// The browse pages are built at launch, kept alive behind Home, so For You was routinely built
    /// before the library had loaded (Trending) or before the profile had resolved (library titles,
    /// no watch history) — and that was then cached for the session, so "Because you watched…"
    /// never appeared. QUIET: the rails on screen stay until the new ones are all in, then swap in
    /// one step. Emptying them first put skeletons under the viewer and took their focus with them.
    ///
    /// A build already under way is waited for and the seeds judged AFTER it. That build was made
    /// from the seeds there were when it STARTED, and at launch the library usually lands while
    /// For You's first build is still fetching: joining it and stopping there — or giving up because
    /// it still read "loading" — kept Trending for the session.
    ///
    /// Covers both the For You segment and the browse page's For You block — each only if it has
    /// been built. On the page only that block is rebuilt; the rows below it are not fetched again.
    public func refreshForYouIfBetterSeeds() async {
        await refreshForYou(.segment(.forYou))
        await refreshForYou(.page)
    }

    private func refreshForYou(_ target: LoadTarget) async {
        while let running = loads[target] { await running.value }
        let basis = forYouBasis[target] ?? .history
        guard state(of: target) == .loaded, basis < .history,
              await availableForYouBasis() > basis else { return }
        // Asking the seeds suspended: another refresh may have started a rebuild meanwhile.
        guard loads[target] == nil else { return await refreshForYou(target) }
        let rebuild = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.rebuildForYouQuietly(target)
            self.loads[target] = nil
        }
        loads[target] = rebuild
        await rebuild.value
    }

    /// Builds the target's rows from scratch, publishing each as it lands (see `loadSegment`).
    private func performLoad(_ target: LoadTarget) async {
        setState(.loading, of: target)
        setRows([], of: target)
        await loadCAMIDsIfNeeded()
        let specs = await rowSpecs(for: target)
        let dedup = target != .page
        _ = await fetch(specs) { [weak self] completed in
            guard let self else { return }
            let rows = Self.assemble(specs: specs, completed: completed, dedupAcrossRows: dedup)
            self.setRows(rows, of: target)
            if self.state(of: target) != .loaded, !rows.isEmpty {
                self.setState(.loaded, of: target)   // show as soon as the first rail has content
            }
        }
        if rows(of: target).isEmpty { setState(.failed, of: target) }
    }

    /// Rebuilds the target's For You rows without publishing anything until they are all in, then
    /// swaps them in in one step — or keeps what is on screen if the rebuild comes back empty. For
    /// the segment the For You rows are the whole segment; on the page they are the leading block.
    private func rebuildForYouQuietly(_ target: LoadTarget) async {
        await loadCAMIDsIfNeeded()
        switch target {
        case .segment:
            let specs = await forYouSpecs(for: target)
            let completed = await fetch(specs)
            let rebuilt = Self.assemble(specs: specs, completed: completed)
            if !rebuilt.isEmpty { setRows(rebuilt, of: target) }   // one swap, or keep what was there
        case .page:
            let specs = await forYouSpecs(for: target)
            let completed = await fetch(specs)
            let block = Self.assemble(specs: specs, completed: completed, dedupAcrossRows: false)
            guard !block.isEmpty else { return }
            // Read the rows AFTER the fetch: they are whatever is on screen now.
            let old = browseForYouIDs
            browseRows = block + browseRows.filter { !old.contains($0.id) }
            browseForYouIDs = Set(specs.map(\.id))
        }
    }

    private func loadCAMIDsIfNeeded() async {
        if kind == .movie && camIDs.isEmpty {
            camIDs = Set(((try? await discover.nowPlayingMovies()) ?? []).map(\.id))
        }
    }

    /// Fetches every spec with a small concurrency cap, calling `progress` (on the main actor)
    /// with everything completed so far after each one lands. Returns them all, keyed by index.
    private func fetch(_ specs: [RowSpec],
                       progress: (([Int: [SearchHit]]) -> Void)? = nil) async -> [Int: [SearchHit]] {
        let kind = self.kind
        let cap = 6
        var completed: [Int: [SearchHit]] = [:]
        await withTaskGroup(of: (Int, [SearchHit]).self) { group in
            var next = 0, running = 0
            func addTask(_ i: Int) {
                let spec = specs[i]
                group.addTask { (i, (await spec.fetch()).map { SearchHit(result: $0, kind: kind) }) }
            }
            while next < specs.count && running < cap { addTask(next); next += 1; running += 1 }
            for await (i, hits) in group {
                completed[i] = hits
                progress?(completed)
                if next < specs.count { addTask(next); next += 1 } else { running -= 1 }
            }
        }
        return completed
    }

    // MARK: - Row specs per segment

    /// Internal (not private) so the progressive-assembly ordering can be unit-tested directly.
    struct RowSpec {
        let id: String
        let title: String
        let fetch: @Sendable () async -> [TMDBSearchResult]
        /// See `Row.genre`.
        var genre: Genre? = nil
    }

    private func rowSpecs(for target: LoadTarget) async -> [RowSpec] {
        switch target {
        case .segment(.forYou):      return await forYouSpecs(for: target)
        case .segment(.trending):    return trendingSpecs()
        case .segment(.newReleases): return newSpecs()
        case .segment(.popular):     return popularSpecs()
        case .segment(.topRated):    return topRatedSpecs()
        case .page:                  return await browsePageSpecs()
        }
    }

    /// For You (≤ 3), Trending This Week, New This Month, Top Rated of All Time, a row per genre.
    private func browsePageSpecs() async -> [RowSpec] {
        let d = discover, k = kind
        let (from, to) = releaseWindow()
        let forYou = await forYouSpecs(for: .page)
        browseForYouIDs = Set(forYou.map(\.id))
        var specs = forYou
        specs.append(RowSpec(id: "trend-week", title: "Trending This Week",
                             fetch: { (try? await d.trending(k, window: .week)) ?? [] }))
        specs.append(RowSpec(id: "new-all", title: "New This Month",
                             fetch: { (try? await d.newOverall(k, from: from, to: to)) ?? [] }))
        specs.append(RowSpec(id: "top-curated", title: "Top Rated of All Time",
                             fetch: { (try? await d.topRatedCurated(k)) ?? [] }))
        for (name, gid) in genreTable {
            specs.append(RowSpec(id: "genre-\(gid)", title: name,
                                 fetch: { (try? await d.popularByGenre(k, gid)) ?? [] },
                                 genre: Genre(name: name, tmdbID: gid)))
        }
        return specs
    }

    private func trendingSpecs() -> [RowSpec] {
        let d = discover, k = kind
        return [
            RowSpec(id: "trend-day", title: "Trending Today",
                    fetch: { (try? await d.trending(k, window: .day)) ?? [] }),
            RowSpec(id: "trend-week", title: "Trending This Week",
                    fetch: { (try? await d.trending(k, window: .week)) ?? [] }),
        ]
    }

    private func newSpecs() -> [RowSpec] {
        let d = discover, k = kind
        let (from, to) = releaseWindow()
        var specs = [RowSpec(id: "new-all", title: "New This Month",
                             fetch: { (try? await d.newOverall(k, from: from, to: to)) ?? [] })]
        for (name, gid) in genreTable {
            specs.append(RowSpec(id: "new-\(gid)", title: "New in \(name)",
                                 fetch: { (try? await d.newByGenre(k, gid, from: from, to: to)) ?? [] }))
        }
        return specs
    }

    private func popularSpecs() -> [RowSpec] {
        let d = discover, k = kind
        return genreTable.map { (name, gid) in
            RowSpec(id: "pop-\(gid)", title: "Popular in \(name)",
                    fetch: { (try? await d.popularByGenre(k, gid)) ?? [] })
        }
    }

    private func topRatedSpecs() -> [RowSpec] {
        let d = discover, k = kind
        var specs = [RowSpec(id: "top-curated", title: "Top Rated of All Time",
                             fetch: { (try? await d.topRatedCurated(k)) ?? [] })]
        for (label, from, to) in Self.decades {
            let f = "\(from)-01-01", t = "\(to)-12-31"
            specs.append(RowSpec(id: "decade-\(from)", title: label,
                                 fetch: { (try? await d.decade(k, from: f, to: t)) ?? [] }))
        }
        for (name, gid) in genreTable {
            specs.append(RowSpec(id: "topg-\(gid)", title: "Top \(name)",
                                 fetch: { (try? await d.topRatedByGenre(k, gid)) ?? [] }))
        }
        return specs
    }

    /// The For You rows for a target, recording the basis they were built from. The segment
    /// falls back to Trending without seeds (it must never be blank); the page has no personal rows
    /// then — its own Trending row leads.
    private func forYouSpecs(for target: LoadTarget) async -> [RowSpec] {
        let d = discover, k = kind
        let limit = target == .page ? Self.browseForYouLimit : 10
        let seedList = Array((await seeds?.seeds(kind: kind, limit: limit) ?? []).prefix(limit))
        forYouBasis[target] = seedList.isEmpty ? .trending
            : seedList.contains(where: \.watched) ? .history : .library
        guard !seedList.isEmpty else { return target == .page ? [] : trendingSpecs() }
        return seedList.map { seed in
            let title = seed.watched ? "Because you watched \(seed.title)" : "More like \(seed.title)"
            return RowSpec(id: "rec-\(seed.tmdbID)", title: title,
                           fetch: { (try? await d.recommended(k, tmdbID: seed.tmdbID)) ?? [] })
        }
    }

    /// The best basis the seeds could give right now. Watched seeds come first, so one is enough
    /// to tell.
    private func availableForYouBasis() async -> ForYouBasis {
        guard let seeds, let first = await seeds.seeds(kind: kind, limit: 1).first else { return .trending }
        return first.watched ? .history : .library
    }

    // MARK: - Progressive assembly

    /// Builds the visible rows from the completed PREFIX of the specs, dropping empties and
    /// deduping poster ids ACROSS rails (a title settles into its earliest rail). Called after each
    /// rail completes, so the list grows as the segment loads.
    ///
    /// It stops at the first unfinished rail rather than skipping past it, and that is the whole
    /// point: rails finish out of order, so filling gaps in afterwards INSERTED a rail above ones
    /// already on screen — the page jumped under the viewer — and re-running the cross-rail dedup
    /// with a new earliest claimant pulled posters out of a rail they were already showing in.
    /// Growing only at the bottom means nothing on screen ever moves, and the finished layout is
    /// identical either way.
    ///
    /// `dedupAcrossRows: false` (the browse page) de-duplicates within each row only.
    static func assemble(specs: [RowSpec], completed: [Int: [SearchHit]],
                         dedupAcrossRows: Bool = true) -> [Row] {
        var seen = Set<Int>()
        var rows: [Row] = []
        for i in specs.indices {
            guard let hits0 = completed[i] else { break }      // rail not finished yet
            if !dedupAcrossRows { seen.removeAll(keepingCapacity: true) }
            let hits = hits0.filter { seen.insert($0.result.id).inserted }
            if hits.isEmpty { continue }
            rows.append(Row(id: specs[i].id, title: specs[i].title, hits: hits, genre: specs[i].genre))
        }
        return rows
    }

    /// "New" window: released between ~10 months and ~1.5 months ago.
    private func releaseWindow() -> (from: String, to: String) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = now()
        let from = cal.date(byAdding: .day, value: -300, to: today) ?? today
        let to = cal.date(byAdding: .day, value: -45, to: today) ?? today
        return (Self.iso.string(from: from), Self.iso.string(from: to))
    }

    private static let iso: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
