import DebridCore
import Foundation
import Observation

/// How a genre grid is ordered. These map onto three different TMDB discover calls, not onto a
/// client-side sort — TMDB pages are already ordered, so re-sorting locally would only shuffle
/// within the current page.
public enum GenreSort: String, CaseIterable, Identifiable, Sendable {
    case popular = "Popular", newest = "New", topRated = "Top Rated"
    public var id: String { rawValue }
    public var title: String { rawValue }
}

/// One page of titles in one genre. Separate from `DiscoverProviding` because a grid pages and a
/// rail does not — `DiscoverProviding`'s genre calls are deliberately capped at one page.
public protocol GenreBrowsing: Sendable {
    func titles(kind: MediaKind, genreID: Int, sort: GenreSort, page: Int) async throws -> [TMDBSearchResult]
}

/// Production conformance over `TMDBClient`.
public struct TMDBGenreService: GenreBrowsing {
    private let client: TMDBClient
    private let now: @Sendable () -> Date

    public init(client: TMDBClient, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.now = now
    }

    public func titles(kind: MediaKind, genreID: Int,
                       sort: GenreSort, page: Int) async throws -> [TMDBSearchResult] {
        switch (kind, sort) {
        case (.movie, .popular):
            return try await client.discoverMovies(genreID: genreID, page: page)
        case (.movie, .topRated):
            return try await client.topRatedMovies(genreID: genreID, page: page)
        case (.movie, .newest):
            let (from, to) = window()
            return try await client.discoverMovies(genreID: genreID, releaseFrom: from,
                                                   releaseTo: to, page: page)
        case (.show, .popular):
            return try await client.discoverTV(genreID: genreID, page: page)
        case (.show, .topRated):
            return try await client.topRatedTV(genreID: genreID, page: page)
        case (.show, .newest):
            let (from, to) = window()
            return try await client.discoverTV(genreID: genreID, firstAirFrom: from,
                                               firstAirTo: to, page: page)
        }
    }

    /// "New" = released in the last 12 months, up to 45 days ago. The trailing cut-off matches
    /// `DiscoverStore.releaseWindow` — titles announced but not yet out have no usable artwork.
    private func window() -> (from: String, to: String) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = now()
        let from = cal.date(byAdding: .day, value: -365, to: today) ?? today
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
