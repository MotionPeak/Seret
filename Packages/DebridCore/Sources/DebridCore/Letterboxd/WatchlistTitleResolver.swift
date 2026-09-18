import Foundation

public struct WatchlistMatch: Sendable, Equatable {
    public let tmdbID: Int
    public let posterPath: String?

    public init(tmdbID: Int, posterPath: String?) {
        self.tmdbID = tmdbID
        self.posterPath = posterPath
    }
}

/// Turns a watchlist entry's name and year into a TMDB id.
///
/// A seam because the watchlist syncer is tested with fakes: its suite would otherwise need both
/// the network mock's shared handler and its own serialization, which is how three unrelated suites
/// got broken once already.
public protocol WatchlistTitleResolving: Sendable {
    /// Nil means "searched and found nothing" — a different outcome from throwing, and the UI
    /// distinguishes them.
    func match(name: String, year: Int?) async throws -> WatchlistMatch?
}

public enum WatchlistName {
    /// Matches a TRAILING parenthesised year, so a year inside the title survives.
    /// `NSRegularExpression` rather than `Regex`, which is not `Sendable` and so cannot be a
    /// `static let` under strict concurrency.
    private static let trailingYear = make(#"\s*\((\d{4})\)\s*$"#)

    private static func make(_ pattern: String) -> NSRegularExpression {
        // A literal in this file, so a failure is a programmer error, not input.
        try! NSRegularExpression(pattern: pattern)
    }

    /// "Speed (1994)" -> "Speed". TMDB is searched on the bare title.
    public static func stripYear(from name: String) -> String {
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        return trailingYear.stringByReplacingMatches(in: name, range: range, withTemplate: "")
    }
}

public struct TMDBWatchlistTitleResolver: WatchlistTitleResolving {
    private let tmdb: TMDBClient

    public init(tmdb: TMDBClient) { self.tmdb = tmdb }

    public func match(name: String, year: Int?) async throws -> WatchlistMatch? {
        let query = WatchlistName.stripYear(from: name)
        let results = try await tmdb.searchMovie(query: query, year: year)
        guard let first = results.first else { return nil }
        return WatchlistMatch(tmdbID: first.id, posterPath: first.posterPath)
    }
}
