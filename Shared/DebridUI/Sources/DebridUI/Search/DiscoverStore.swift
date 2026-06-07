import DebridCore
import Foundation
import Observation

/// Supplies the browse rows for the Movies / TV tabs. Movies-only methods (now-playing,
/// new-releases) are unused for the `.show` kind.
public protocol DiscoverProviding: Sendable {
    func popularMovies() async throws -> [TMDBSearchResult]
    func popularTV() async throws -> [TMDBSearchResult]
    func nowPlaying() async throws -> [TMDBSearchResult]
    func newReleases(from: String, to: String) async throws -> [TMDBSearchResult]
    func moviesByGenre(_ id: Int) async throws -> [TMDBSearchResult]
    func tvByGenre(_ id: Int) async throws -> [TMDBSearchResult]
}

public struct TMDBDiscoverService: DiscoverProviding {
    let client: TMDBClient
    public init(client: TMDBClient) { self.client = client }
    public func popularMovies() async throws -> [TMDBSearchResult] { try await client.popularMovies() }
    public func popularTV() async throws -> [TMDBSearchResult] { try await client.popularTV() }
    public func nowPlaying() async throws -> [TMDBSearchResult] { try await client.nowPlayingMovies() }
    public func newReleases(from: String, to: String) async throws -> [TMDBSearchResult] {
        try await client.discoverMovies(releaseFrom: from, releaseTo: to)
    }
    public func moviesByGenre(_ id: Int) async throws -> [TMDBSearchResult] { try await client.discoverMovies(genreID: id) }
    public func tvByGenre(_ id: Int) async throws -> [TMDBSearchResult] { try await client.discoverTV(genreID: id) }
}

/// Kind-aware browse rows for a Movies or TV tab. Movies: Popular · In Theatres (CAM, by
/// release date) · New Releases (home-release window) · genres. TV: Popular · genres.
@MainActor
@Observable
public final class DiscoverStore {
    public struct Row: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let hits: [SearchHit]
    }

    public enum State: Equatable { case idle, loading, loaded, failed }

    public private(set) var state: State = .idle
    public private(set) var rows: [Row] = []

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
        let loaded: [Row?] = await withTaskGroup(of: (Int, Row?).self) { group in
            for (index, spec) in specs.enumerated() {
                group.addTask {
                    let hits = (try? await spec.fetch())?.map { SearchHit(result: $0, kind: kind) } ?? []
                    return (index, hits.isEmpty ? nil : Row(id: spec.id, title: spec.title, hits: hits))
                }
            }
            var slots = [(Int, Row?)]()
            for await result in group { slots.append(result) }
            return slots.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
        rows = loaded.compactMap { $0 }
        state = rows.isEmpty ? .failed : .loaded
    }

    private struct RowSpec { let id: String; let title: String; let fetch: @Sendable () async throws -> [TMDBSearchResult] }

    private func rowSpecs() -> [RowSpec] {
        let d = discover
        switch kind {
        case .movie:
            let (from, to) = releaseWindow()
            var specs: [RowSpec] = [
                RowSpec(id: "popular", title: "Popular", fetch: { try await d.popularMovies() }),
                RowSpec(id: "in-theatres", title: "In Theatres", fetch: { try await d.nowPlaying() }),
                RowSpec(id: "new-releases", title: "New Releases", fetch: { try await d.newReleases(from: from, to: to) }),
            ]
            specs += Self.movieGenres.map { g in
                RowSpec(id: "g\(g.1)", title: g.0, fetch: { try await d.moviesByGenre(g.1) })
            }
            return specs
        case .show:
            var specs: [RowSpec] = [
                RowSpec(id: "popular", title: "Popular", fetch: { try await d.popularTV() }),
            ]
            specs += Self.tvGenres.map { g in
                RowSpec(id: "g\(g.1)", title: g.0, fetch: { try await d.tvByGenre(g.1) })
            }
            return specs
        }
    }

    /// Home-release window for "New Releases": released between ~10 months and ~1.5 months ago
    /// (past the theatrical/CAM window, likely to have real cached files).
    private func releaseWindow() -> (from: String, to: String) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!   // match `iso` formatter so the window is stable
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
