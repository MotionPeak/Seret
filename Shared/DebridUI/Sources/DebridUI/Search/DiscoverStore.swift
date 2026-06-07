import DebridCore
import Foundation
import Observation

/// Supplies browse rows for the Movies / TV tabs, organised into sections.
public protocol DiscoverProviding: Sendable {
    func nowPlaying() async throws -> [TMDBSearchResult]                                   // movies: In Theatres
    func popularMoviesByGenre(_ id: Int) async throws -> [TMDBSearchResult]                // ≥100 votes
    func newMoviesByGenre(_ id: Int, from: String, to: String) async throws -> [TMDBSearchResult]
    func popularTVByGenre(_ id: Int) async throws -> [TMDBSearchResult]                    // ≥100 votes
    func newTVByGenre(_ id: Int, from: String, to: String) async throws -> [TMDBSearchResult]
}

public struct TMDBDiscoverService: DiscoverProviding {
    let client: TMDBClient
    public init(client: TMDBClient) { self.client = client }
    public func nowPlaying() async throws -> [TMDBSearchResult] { try await client.nowPlayingMovies() }
    public func popularMoviesByGenre(_ id: Int) async throws -> [TMDBSearchResult] { try await client.discoverMovies(genreID: id) }
    public func newMoviesByGenre(_ id: Int, from: String, to: String) async throws -> [TMDBSearchResult] {
        try await client.discoverMovies(genreID: id, releaseFrom: from, releaseTo: to)
    }
    public func popularTVByGenre(_ id: Int) async throws -> [TMDBSearchResult] { try await client.discoverTV(genreID: id) }
    public func newTVByGenre(_ id: Int, from: String, to: String) async throws -> [TMDBSearchResult] {
        try await client.discoverTV(genreID: id, firstAirFrom: from, firstAirTo: to)
    }
}

/// Kind-aware browse content organised into sections, each holding per-genre rows.
/// Movies: **In Theatres** (CAM-likely, by release date) · **New Releases** (per genre, recent) ·
/// **Most Popular** (per genre, ≥100 votes). TV drops In Theatres.
@MainActor
@Observable
public final class DiscoverStore {
    public struct Row: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String      // genre name (or "" for the single In-Theatres row)
        public let hits: [SearchHit]
    }
    public struct Section: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String      // "In Theatres" / "New Releases" / "Most Popular"
        public let isCAM: Bool        // true → tag its posters as CAM-likely
        public let rows: [Row]
    }
    public enum State: Equatable { case idle, loading, loaded, failed }

    public private(set) var state: State = .idle
    public private(set) var sections: [Section] = []
    /// TMDB ids of titles in a CAM-likely (In Theatres) section — so a poster can be tagged CAM
    /// in EVERY row it appears in, not just the In Theatres rail.
    public private(set) var camIDs: Set<Int> = []

    public let kind: MediaKind
    private let discover: DiscoverProviding
    private let now: @Sendable () -> Date

    private static let movieGenres: [(String, Int)] = [
        ("Action", 28), ("Comedy", 35), ("Horror", 27), ("Drama", 18),
        ("Thriller", 53), ("Sci-Fi", 878), ("Animation", 16), ("Crime", 80),
    ]
    private static let tvGenres: [(String, Int)] = [
        ("Drama", 18), ("Comedy", 35), ("Crime", 80), ("Sci-Fi & Fantasy", 10765),
        ("Animation", 16), ("Mystery", 9648), ("Reality", 10764),
    ]

    public init(kind: MediaKind, discover: DiscoverProviding, now: @escaping @Sendable () -> Date = { Date() }) {
        self.kind = kind; self.discover = discover; self.now = now
    }

    public func load() async {
        guard state == .idle || state == .failed else { return }
        state = .loading

        let kind = self.kind
        let specs = rowSpecs()
        // Fetch every (section,row) concurrently, then regroup preserving order, dropping empties.
        let results: [(spec: RowSpec, hits: [SearchHit])] = await withTaskGroup(of: (Int, [SearchHit]).self) { group in
            for (index, spec) in specs.enumerated() {
                group.addTask {
                    let hits = (try? await spec.fetch())?.map { SearchHit(result: $0, kind: kind) } ?? []
                    return (index, hits)
                }
            }
            var byIndex = [Int: [SearchHit]]()
            for await (index, hits) in group { byIndex[index] = hits }
            return specs.enumerated().map { ($0.element, byIndex[$0.offset] ?? []) }
        }

        sections = assemble(results)
        camIDs = Set(results.filter { $0.spec.isCAM }.flatMap { $0.hits.map(\.result.id) })
        state = sections.isEmpty ? .failed : .loaded
    }

    /// Whether a title should carry a CAM tag wherever it appears (it's in the In-Theatres set).
    public func isCAM(_ result: TMDBSearchResult) -> Bool { camIDs.contains(result.id) }

    private struct RowSpec {
        let sectionID: String; let sectionTitle: String; let isCAM: Bool
        let rowID: String; let rowTitle: String
        let fetch: @Sendable () async throws -> [TMDBSearchResult]
    }

    private func assemble(_ results: [(spec: RowSpec, hits: [SearchHit])]) -> [Section] {
        var order: [String] = []
        var bySection: [String: (title: String, isCAM: Bool, rows: [Row])] = [:]
        for (spec, hits) in results where !hits.isEmpty {
            if bySection[spec.sectionID] == nil {
                order.append(spec.sectionID)
                bySection[spec.sectionID] = (spec.sectionTitle, spec.isCAM, [])
            }
            bySection[spec.sectionID]?.rows.append(Row(id: spec.rowID, title: spec.rowTitle, hits: hits))
        }
        return order.compactMap { id in
            guard let s = bySection[id], !s.rows.isEmpty else { return nil }
            return Section(id: id, title: s.title, isCAM: s.isCAM, rows: s.rows)
        }
    }

    private func rowSpecs() -> [RowSpec] {
        let d = discover
        let (from, to) = releaseWindow()
        switch kind {
        case .movie:
            var specs = [RowSpec(sectionID: "in-theatres", sectionTitle: "In Theatres", isCAM: true,
                                 rowID: "it", rowTitle: "", fetch: { try await d.nowPlaying() })]
            specs += Self.movieGenres.map { g in
                RowSpec(sectionID: "new", sectionTitle: "New Releases", isCAM: false,
                        rowID: "new-\(g.1)", rowTitle: g.0,
                        fetch: { try await d.newMoviesByGenre(g.1, from: from, to: to) })
            }
            specs += Self.movieGenres.map { g in
                RowSpec(sectionID: "popular", sectionTitle: "Most Popular", isCAM: false,
                        rowID: "pop-\(g.1)", rowTitle: g.0,
                        fetch: { try await d.popularMoviesByGenre(g.1) })
            }
            return specs
        case .show:
            var specs = Self.tvGenres.map { g in
                RowSpec(sectionID: "new", sectionTitle: "New Releases", isCAM: false,
                        rowID: "new-\(g.1)", rowTitle: g.0,
                        fetch: { try await d.newTVByGenre(g.1, from: from, to: to) })
            }
            specs += Self.tvGenres.map { g in
                RowSpec(sectionID: "popular", sectionTitle: "Most Popular", isCAM: false,
                        rowID: "pop-\(g.1)", rowTitle: g.0,
                        fetch: { try await d.popularTVByGenre(g.1) })
            }
            return specs
        }
    }

    /// "New Releases" window: released between ~10 months and ~1.5 months ago.
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
