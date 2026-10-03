import Foundation

/// Answers from films already matched before searching TMDB.
///
/// Built for a partner's watchlist: Letterboxd renders one film's name identically on everyone's
/// list, so a film the owner's list already resolved needs no second search — and a first sync of
/// someone else's list is otherwise a TMDB request per film, spaced out by the syncer's delay.
///
/// Exact name AND year only. A near match is a guess, and a wrong id here would put the wrong
/// poster on the list with nothing to say it was guessed.
public struct KnownFirstTitleResolver: WatchlistTitleResolving {
    private let known: @Sendable () async -> [WatchlistEntry]
    private let fallback: any WatchlistTitleResolving

    public init(known: @escaping @Sendable () async -> [WatchlistEntry],
                fallback: any WatchlistTitleResolving) {
        self.known = known
        self.fallback = fallback
    }

    public func match(name: String, year: Int?) async throws -> WatchlistMatch? {
        if let hit = await known().first(where: { $0.name == name && $0.year == year && $0.tmdbID != nil }),
           let id = hit.tmdbID {
            return WatchlistMatch(tmdbID: id, posterPath: hit.posterPath)
        }
        return try await fallback.match(name: name, year: year)
    }
}
