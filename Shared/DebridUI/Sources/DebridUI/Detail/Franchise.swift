import DebridCore

/// The series a film belongs to, in the order the films came out, and where this one sits in it.
///
/// Only ever built with two or more released films — a "collection" of one is not a franchise, and
/// saying "Film 1 of 1" is noise.
public struct Franchise: Equatable, Sendable {
    public let name: String
    /// Released members, oldest first (see `FranchiseOrder`).
    public let parts: [TMDBSearchResult]
    /// 1-based position of the film being viewed — the "3" in "Film 3 of 5".
    public let position: Int

    public var count: Int { parts.count }

    public init(name: String, parts: [TMDBSearchResult], position: Int) {
        self.name = name; self.parts = parts; self.position = position
    }
}
