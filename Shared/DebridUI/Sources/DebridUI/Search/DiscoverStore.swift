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
    }
    public enum State: Equatable { case idle, loading, loaded, failed }

    public var selectedSegment: Segment = .forYou
    public private(set) var rowsBySegment: [Segment: [Row]] = [:]
    private var statesBySegment: [Segment: State] = [:]
    public private(set) var camIDs: Set<Int> = []

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
    private var forYouBasis: ForYouBasis = .history
    /// The load running for each segment. Owned by the store, NOT by whichever view asked: see
    /// `loadSegment`.
    private var segmentLoads: [Segment: Task<Void, Never>] = [:]
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
    public func loadSegment(_ segment: Segment) async {
        if let running = segmentLoads[segment] { await running.value; return }
        switch statesBySegment[segment] ?? .idle {
        case .loading, .loaded: return
        case .idle, .failed: break
        }
        let load = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performSegmentLoad(segment)
        }
        segmentLoads[segment] = load
        await load.value
        if segmentLoads[segment] == load { segmentLoads[segment] = nil }
    }

    /// Rebuild For You when better seeds exist than it was built from — called when what seeds it
    /// CHANGES (the library landing, the profile resolving), never merely because the page appeared.
    ///
    /// The browse pages are built at launch, kept alive behind Home, so For You was routinely built
    /// before the library had loaded (Trending) or before the profile had resolved (library titles,
    /// no watch history) — and that was then cached for the session, so "Because you watched…"
    /// never appeared. QUIET: the rails on screen stay until the new ones are all in, then swap in
    /// one step. Emptying them first put skeletons under the viewer and took their focus with them.
    public func refreshForYouIfBetterSeeds() async {
        guard statesBySegment[.forYou] == .loaded, forYouBasis < .history,
              await availableForYouBasis() > forYouBasis else { return }
        if let running = segmentLoads[.forYou] { await running.value; return }
        let rebuild = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performSegmentLoad(.forYou, quietly: true)
        }
        segmentLoads[.forYou] = rebuild
        await rebuild.value
        if segmentLoads[.forYou] == rebuild { segmentLoads[.forYou] = nil }
    }

    /// - Parameter quietly: build the rails without publishing anything until they are all in, and
    ///   keep what is on screen if the rebuild comes back empty.
    private func performSegmentLoad(_ segment: Segment, quietly: Bool = false) async {
        if !quietly {
            statesBySegment[segment] = .loading
            rowsBySegment[segment] = []
        }
        if kind == .movie && camIDs.isEmpty {
            camIDs = Set(((try? await discover.nowPlayingMovies()) ?? []).map(\.id))
        }
        let specs = await rowSpecs(for: segment)
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
                if !quietly {
                    rowsBySegment[segment] = Self.assemble(specs: specs, completed: completed)
                    if statesBySegment[segment] != .loaded, !(rowsBySegment[segment]?.isEmpty ?? true) {
                        statesBySegment[segment] = .loaded   // show as soon as the first rail has content
                    }
                }
                if next < specs.count { addTask(next); next += 1 } else { running -= 1 }
            }
        }
        if quietly {
            let rebuilt = Self.assemble(specs: specs, completed: completed)
            if !rebuilt.isEmpty { rowsBySegment[segment] = rebuilt }   // one swap, or keep what was there
            return
        }
        if rowsBySegment[segment]?.isEmpty ?? true { statesBySegment[segment] = .failed }
    }

    // MARK: - Row specs per segment

    /// Internal (not private) so the progressive-assembly ordering can be unit-tested directly.
    struct RowSpec {
        let id: String
        let title: String
        let fetch: @Sendable () async -> [TMDBSearchResult]
    }

    private func rowSpecs(for segment: Segment) async -> [RowSpec] {
        switch segment {
        case .forYou:      return await forYouSpecs()
        case .trending:    return trendingSpecs()
        case .newReleases: return newSpecs()
        case .popular:     return popularSpecs()
        case .topRated:    return topRatedSpecs()
        }
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

    private func forYouSpecs() async -> [RowSpec] {
        let d = discover, k = kind
        let seedList = await seeds?.seeds(kind: kind, limit: 10) ?? []
        forYouBasis = seedList.isEmpty ? .trending
            : seedList.contains(where: \.watched) ? .history : .library
        guard !seedList.isEmpty else { return trendingSpecs() }   // fallback: never blank
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
    static func assemble(specs: [RowSpec], completed: [Int: [SearchHit]]) -> [Row] {
        var seen = Set<Int>()
        var rows: [Row] = []
        for i in specs.indices {
            guard let hits0 = completed[i] else { break }      // rail not finished yet
            let hits = hits0.filter { seen.insert($0.result.id).inserted }
            if hits.isEmpty { continue }
            rows.append(Row(id: specs[i].id, title: specs[i].title, hits: hits))
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
