import DebridCore
import Observation

/// Debounced TMDB title search across movies + TV, merged best-first by vote average.
@MainActor
@Observable
public final class SearchStore {
    public enum State: Equatable { case idle, searching, results, empty, failed(String) }

    public private(set) var state: State = .idle
    public private(set) var results: [TMDBSearchResult] = []

    private let search: SearchProviding

    public init(search: SearchProviding) { self.search = search }

    /// Runs a search. Empty/whitespace query resets to idle. Cancellation-aware:
    /// a superseding call leaves state for the newer task.
    public func search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { state = .idle; results = []; return }
        state = .searching
        do {
            async let movies = search.searchMovie(query: trimmed, year: nil)
            async let tv = search.searchTV(query: trimmed, firstAirYear: nil)
            let merged = try await (movies + tv).sorted { ($0.voteAverage ?? 0) > ($1.voteAverage ?? 0) }
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
