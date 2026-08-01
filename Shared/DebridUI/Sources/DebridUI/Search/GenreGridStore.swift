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

/// A paged poster grid for one genre + one sort. Every reset bumps a token; a fetch that returns
/// after its token has been superseded is dropped on the floor.
///
/// ⚠️ The token is not optional polish. The genre pills switch on press but the *store* is rebuilt
/// on genre change, and TMDB responses arrive out of order — without it the last response wins and
/// you get another title's grid under the selected pill. This is the same defect that shipped in
/// `AddFlowStore.selectSeason`.
@MainActor
@Observable
public final class GenreGridStore {
    public enum State: Equatable { case idle, loading, loaded, failed }

    public let kind: MediaKind
    public private(set) var genre: DiscoverStore.Genre
    public private(set) var sort: GenreSort = .popular
    public private(set) var hits: [SearchHit] = []
    public private(set) var state: State = .idle
    /// True once TMDB stops yielding new titles, or at the page cap.
    public private(set) var reachedEnd = false

    private let browsing: GenreBrowsing
    private var nextPage = 1
    private var token = 0
    private var inFlight = false

    /// TMDB will happily serve 500 pages. Ten is ~200 titles — far more than anyone scrolls, and it
    /// bounds the request count if `loadMore` is ever called in a loop.
    private static let maxPage = 10

    public init(kind: MediaKind, genre: DiscoverStore.Genre, browsing: GenreBrowsing) {
        self.kind = kind
        self.genre = genre
        self.browsing = browsing
    }

    public func select(genre: DiscoverStore.Genre) async {
        guard genre != self.genre else { return }
        self.genre = genre
        await reload()
    }

    public func select(sort: GenreSort) async {
        guard sort != self.sort else { return }
        self.sort = sort
        await reload()
    }

    /// First page. Idempotent — re-entering the screen with content already loaded is a no-op.
    public func load() async {
        guard state == .idle || state == .failed else { return }
        await reload()
    }

    /// Next page. No-op while a fetch is running, at the end of the results, or before a first load.
    public func loadMore() async {
        guard state == .loaded, !reachedEnd, !inFlight, nextPage <= Self.maxPage else { return }
        let myToken = token
        inFlight = true
        defer { inFlight = false }

        let page = nextPage
        let fetched = try? await browsing.titles(kind: kind, genreID: genre.tmdbID,
                                                 sort: sort, page: page)
        guard myToken == token else { return }          // superseded mid-flight

        let new = (fetched ?? []).map { SearchHit(result: $0, kind: kind) }
        let known = Set(hits.map(\.id))
        let fresh = new.filter { !known.contains($0.id) }
        if fresh.isEmpty {
            reachedEnd = true
        } else {
            hits += fresh
            nextPage = page + 1
            if nextPage > Self.maxPage { reachedEnd = true }
        }
    }

    /// Clears and refetches page 1 under a fresh token.
    private func reload() async {
        token += 1
        let myToken = token
        hits = []
        nextPage = 1
        reachedEnd = false
        state = .loading

        let fetched = try? await browsing.titles(kind: kind, genreID: genre.tmdbID,
                                                 sort: sort, page: 1)
        guard myToken == token else { return }          // a newer selection already won

        let new = (fetched ?? []).map { SearchHit(result: $0, kind: kind) }
        if new.isEmpty {
            state = .failed
        } else {
            hits = new
            nextPage = 2
            state = .loaded
        }
    }
}
