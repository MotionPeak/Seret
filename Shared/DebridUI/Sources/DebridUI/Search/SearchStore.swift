import DebridCore
import Observation

/// One title from a search, tagged with its `MediaKind`. TMDB movie and TV ids live in
/// separate namespaces (the same integer can be a movie *and* a show), so kind must travel
/// with the result rather than be inferred downstream.
public struct SearchHit: Identifiable, Equatable, Hashable, Sendable {
    public let result: TMDBSearchResult
    public let kind: MediaKind
    public init(result: TMDBSearchResult, kind: MediaKind) {
        self.result = result; self.kind = kind
    }
    public var id: String { "\(kind.rawValue)-\(result.id)" }
}

/// Debounced TMDB title search across movies + TV, merged best-first by vote average.
@MainActor
@Observable
public final class SearchStore {
    public enum State: Equatable { case idle, searching, results, empty, failed(String) }

    public private(set) var state: State = .idle
    public private(set) var results: [SearchHit] = []

    private let search: SearchProviding

    public init(search: SearchProviding) { self.search = search }

    /// Runs a search. Empty/whitespace query resets to idle. Cancellation-aware: a superseding
    /// call leaves state for the newer task. `kind` scopes the search to one media type (the
    /// Movies tab passes `.movie`, the TV tab `.show`); nil searches both, merged best-first.
    public func search(query: String, kind: MediaKind? = nil) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { state = .idle; results = []; return }
        state = .searching
        do {
            let hits: [SearchHit]
            switch kind {
            case .movie:
                hits = try await search.searchMovie(query: trimmed, year: nil)
                    .map { SearchHit(result: $0, kind: .movie) }
            case .show:
                hits = try await search.searchTV(query: trimmed, firstAirYear: nil)
                    .map { SearchHit(result: $0, kind: .show) }
            case nil:
                async let movies = search.searchMovie(query: trimmed, year: nil)
                async let tv = search.searchTV(query: trimmed, firstAirYear: nil)
                hits = try await movies.map { SearchHit(result: $0, kind: .movie) }
                    + tv.map { SearchHit(result: $0, kind: .show) }
            }
            let merged = hits.sorted { ($0.result.voteAverage ?? 0) > ($1.result.voteAverage ?? 0) }
            try Task.checkCancellation()
            results = merged
            state = merged.isEmpty ? .empty : .results
        } catch is CancellationError {
            // superseded
        } catch {
            state = .failed("Search failed. Check your connection and try again.")
        }
    }
}
