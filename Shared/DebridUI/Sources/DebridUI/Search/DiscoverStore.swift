import DebridCore
import Foundation
import Observation

/// Supplies browse rows for the Movies / TV tabs, across three segments × per-genre rows.
public protocol DiscoverProviding: Sendable {
    func nowPlaying() async throws -> [TMDBSearchResult]                                  // movies → CAM set
    func trendingMoviesByGenre(_ id: Int) async throws -> [TMDBSearchResult]              // popularity.desc
    func newMoviesByGenre(_ id: Int, from: String, to: String) async throws -> [TMDBSearchResult]
    func topRatedMoviesByGenre(_ id: Int) async throws -> [TMDBSearchResult]              // all-time top-rated
    func trendingTVByGenre(_ id: Int) async throws -> [TMDBSearchResult]
    func newTVByGenre(_ id: Int, from: String, to: String) async throws -> [TMDBSearchResult]
    func topRatedTVByGenre(_ id: Int) async throws -> [TMDBSearchResult]
}

public struct TMDBDiscoverService: DiscoverProviding {
    let client: TMDBClient
    public init(client: TMDBClient) { self.client = client }
    public func nowPlaying() async throws -> [TMDBSearchResult] { try await client.nowPlayingMovies() }
    public func trendingMoviesByGenre(_ id: Int) async throws -> [TMDBSearchResult] { try await client.discoverMovies(genreID: id) }
    public func newMoviesByGenre(_ id: Int, from: String, to: String) async throws -> [TMDBSearchResult] {
        try await client.discoverMovies(genreID: id, releaseFrom: from, releaseTo: to)
    }
    public func topRatedMoviesByGenre(_ id: Int) async throws -> [TMDBSearchResult] { try await client.topRatedMovies(genreID: id) }
    public func trendingTVByGenre(_ id: Int) async throws -> [TMDBSearchResult] { try await client.discoverTV(genreID: id) }
    public func newTVByGenre(_ id: Int, from: String, to: String) async throws -> [TMDBSearchResult] {
        try await client.discoverTV(genreID: id, firstAirFrom: from, firstAirTo: to)
    }
    public func topRatedTVByGenre(_ id: Int) async throws -> [TMDBSearchResult] { try await client.topRatedTV(genreID: id) }
}

/// Kind-aware browse content: a segment selector (Trending / New Releases / Popular) where each
/// segment is a set of per-genre rows. Loaded once up front so switching segments is instant.
@MainActor
@Observable
public final class DiscoverStore {
    public enum Segment: String, CaseIterable, Identifiable, Sendable {
        case trending = "Trending", newReleases = "New Releases", popular = "Popular"
        public var id: String { rawValue }
        public var title: String { rawValue }
    }
    public struct Row: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String      // genre name
        public let hits: [SearchHit]
    }
    public enum State: Equatable { case idle, loading, loaded, failed }

    public private(set) var state: State = .idle
    public var selectedSegment: Segment = .trending
    public private(set) var rowsBySegment: [Segment: [Row]] = [:]
    /// TMDB ids in the In-Theatres set — CAM-tag these wherever they appear.
    public private(set) var camIDs: Set<Int> = []

    public let kind: MediaKind
    private let discover: DiscoverProviding
    private let now: @Sendable () -> Date

    public var rows: [Row] { rowsBySegment[selectedSegment] ?? [] }
    public func isCAM(_ result: TMDBSearchResult) -> Bool { camIDs.contains(result.id) }
    public func select(_ segment: Segment) { selectedSegment = segment }

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
        let d = discover
        let specs = allRowSpecs()
        let byIndex: [Int: [SearchHit]] = await withTaskGroup(of: (Int, [SearchHit]).self) { group in
            for (index, spec) in specs.enumerated() {
                group.addTask {
                    let hits = (try? await spec.fetch())?.map { SearchHit(result: $0, kind: kind) } ?? []
                    return (index, hits)
                }
            }
            // CAM set (movies only) loaded alongside, keyed -1.
            if kind == .movie {
                group.addTask {
                    let np = (try? await d.nowPlaying()) ?? []
                    return (-1, np.map { SearchHit(result: $0, kind: .movie) })
                }
            }
            var collected = [Int: [SearchHit]]()
            for await (index, hits) in group { collected[index] = hits }
            return collected
        }
        camIDs = Set((byIndex[-1] ?? []).map(\.result.id))
        let results = specs.enumerated().map { ($0.element, byIndex[$0.offset] ?? []) }

        var grouped: [Segment: [Row]] = [:]
        for (spec, hits) in results where !hits.isEmpty {
            grouped[spec.segment, default: []].append(Row(id: spec.rowID, title: spec.genre, hits: hits))
        }
        rowsBySegment = grouped
        state = grouped.values.contains { !$0.isEmpty } ? .loaded : .failed
    }

    private struct RowSpec {
        let segment: Segment; let rowID: String; let genre: String
        let fetch: @Sendable () async throws -> [TMDBSearchResult]
    }

    private func allRowSpecs() -> [RowSpec] {
        let d = discover
        let (from, to) = releaseWindow()
        let genres = kind == .movie ? Self.movieGenres : Self.tvGenres
        var specs: [RowSpec] = []
        for (name, gid) in genres {
            switch kind {
            case .movie:
                specs.append(RowSpec(segment: .trending, rowID: "t-\(gid)", genre: name, fetch: { try await d.trendingMoviesByGenre(gid) }))
                specs.append(RowSpec(segment: .newReleases, rowID: "n-\(gid)", genre: name, fetch: { try await d.newMoviesByGenre(gid, from: from, to: to) }))
                specs.append(RowSpec(segment: .popular, rowID: "p-\(gid)", genre: name, fetch: { try await d.topRatedMoviesByGenre(gid) }))
            case .show:
                specs.append(RowSpec(segment: .trending, rowID: "t-\(gid)", genre: name, fetch: { try await d.trendingTVByGenre(gid) }))
                specs.append(RowSpec(segment: .newReleases, rowID: "n-\(gid)", genre: name, fetch: { try await d.newTVByGenre(gid, from: from, to: to) }))
                specs.append(RowSpec(segment: .popular, rowID: "p-\(gid)", genre: name, fetch: { try await d.topRatedTVByGenre(gid) }))
            }
        }
        return specs
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
