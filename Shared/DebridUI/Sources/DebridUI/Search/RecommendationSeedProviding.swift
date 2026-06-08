import DebridCore

/// One title to seed "For You" recommendations from.
public struct RecommendationSeed: Sendable, Equatable {
    public let tmdbID: Int
    public let title: String
    public let watched: Bool
    public init(tmdbID: Int, title: String, watched: Bool) {
        self.tmdbID = tmdbID; self.title = title; self.watched = watched
    }
}

/// Vends seed titles for "For You" — watched-first, then library. `@MainActor` because the
/// production conformance reads the main-actor `LibraryStore`.
@MainActor
public protocol RecommendationSeedProviding: AnyObject, Sendable {
    func seeds(kind: MediaKind, limit: Int) async -> [RecommendationSeed]
}

/// Production seeds: watched titles (most-recent first), then library titles, deduped by TMDB id.
@MainActor
public final class RecommendationSeedService: RecommendationSeedProviding {
    private let watch: WatchProgressProviding
    private weak var library: LibraryStore?
    private let profileID: @MainActor () -> String?

    public init(watch: WatchProgressProviding, library: LibraryStore?,
                profileID: @escaping @MainActor () -> String?) {
        self.watch = watch; self.library = library; self.profileID = profileID
    }

    public func seeds(kind: MediaKind, limit: Int) async -> [RecommendationSeed] {
        guard let library else { return [] }
        let items = kind == .movie ? library.movies : library.shows
        var out: [RecommendationSeed] = []
        var seen = Set<Int>()

        if let pid = profileID() {
            let states = (try? await watch.recentlyWatched(limit: 30, profileID: pid)) ?? []
            for s in states {
                guard let item = Self.resolve(s.contentKey, in: items),
                      let tmdb = item.tmdbID, seen.insert(tmdb).inserted else { continue }
                out.append(.init(tmdbID: tmdb, title: item.title, watched: true))
                if out.count >= limit { return out }
            }
        }
        for item in items {
            guard let tmdb = item.tmdbID, seen.insert(tmdb).inserted else { continue }
            out.append(.init(tmdbID: tmdb, title: item.title, watched: false))
            if out.count >= limit { break }
        }
        return out
    }

    /// Movie content keys equal the item id; episode keys are `showID:sXeY`.
    static func resolve(_ contentKey: String, in items: [MediaItem]) -> MediaItem? {
        items.first { $0.id == contentKey } ?? items.first { contentKey.hasPrefix($0.id + ":") }
    }
}
