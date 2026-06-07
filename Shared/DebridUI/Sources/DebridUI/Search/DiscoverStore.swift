import DebridCore
import Observation

/// Supplies the discovery rows for the idle Search page (movies only — genres map cleanly
/// to movies and that keeps each hit's `MediaKind` unambiguous).
public protocol DiscoverProviding: Sendable {
    func nowPlaying() async throws -> [TMDBSearchResult]
    func movies(genreID: Int) async throws -> [TMDBSearchResult]
}

public struct TMDBDiscoverService: DiscoverProviding {
    let client: TMDBClient
    public init(client: TMDBClient) { self.client = client }
    public func nowPlaying() async throws -> [TMDBSearchResult] {
        try await client.nowPlayingMovies()
    }
    public func movies(genreID: Int) async throws -> [TMDBSearchResult] {
        try await client.discoverMovies(genreID: genreID)
    }
}

/// Browse rows shown on the idle Search page: "Recently Released" + popular movies per genre.
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

    private let discover: DiscoverProviding

    /// Curated rows after "Recently Released". TMDB movie genre ids.
    private static let genres: [(title: String, id: Int)] = [
        ("Action", 28), ("Comedy", 35), ("Horror", 27), ("Drama", 18),
        ("Thriller", 53), ("Sci-Fi", 878), ("Animation", 16), ("Crime", 80),
    ]

    public init(discover: DiscoverProviding) { self.discover = discover }

    /// Loads all rows concurrently (order-preserving), dropping rows that error or come back
    /// empty. Fails only if nothing loads at all.
    public func load() async {
        guard state == .idle || state == .failed else { return }
        state = .loading

        let loaded: [Row?] = await withTaskGroup(of: (Int, Row?).self) { group in
            group.addTask { [discover] in
                let hits = (try? await discover.nowPlaying())?.map { SearchHit(result: $0, kind: .movie) } ?? []
                return (0, hits.isEmpty ? nil : Row(id: "now-playing", title: "Recently Released", hits: hits))
            }
            for (index, genre) in Self.genres.enumerated() {
                group.addTask { [discover] in
                    let hits = (try? await discover.movies(genreID: genre.id))?
                        .map { SearchHit(result: $0, kind: .movie) } ?? []
                    return (index + 1, hits.isEmpty ? nil : Row(id: "genre-\(genre.id)", title: genre.title, hits: hits))
                }
            }
            var slots = [(Int, Row?)]()
            for await result in group { slots.append(result) }
            return slots.sorted { $0.0 < $1.0 }.map { $0.1 }
        }

        rows = loaded.compactMap { $0 }
        state = rows.isEmpty ? .failed : .loaded
    }
}
