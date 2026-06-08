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
