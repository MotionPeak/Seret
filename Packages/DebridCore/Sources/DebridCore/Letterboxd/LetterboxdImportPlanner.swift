import Foundation

/// Decides which Letterboxd ratings may be written into local watch state.
///
/// Pure, because this is the rule that protects the owner's data and it should be provable without
/// a network or a database: **local wins.** A rating Seret already holds is never overwritten — a
/// disagreement is recorded as a conflict and left alone. Truth does not move.
public enum LetterboxdImportPlanner {
    public struct Candidate: Sendable, Equatable {
        public let contentKey: String
        public let slug: String?
        public let existingRating: Int?

        public init(contentKey: String, slug: String?, existingRating: Int?) {
            self.contentKey = contentKey
            self.slug = slug
            self.existingRating = existingRating
        }
    }

    public struct Write: Sendable, Equatable {
        public let contentKey: String
        public let rating: Int

        public init(contentKey: String, rating: Int) {
            self.contentKey = contentKey
            self.rating = rating
        }
    }

    public struct Conflict: Sendable, Equatable {
        public let contentKey: String
        public let local: Int
        public let letterboxd: Int

        public init(contentKey: String, local: Int, letterboxd: Int) {
            self.contentKey = contentKey
            self.local = local
            self.letterboxd = letterboxd
        }
    }

    public struct Plan: Sendable, Equatable {
        public let writes: [Write]
        public let conflicts: [Conflict]

        public init(writes: [Write], conflicts: [Conflict]) {
            self.writes = writes
            self.conflicts = conflicts
        }
    }

    /// `letterboxdRatings` is slug -> 1...10.
    public static func plan(candidates: [Candidate],
                            letterboxdRatings: [String: Int]) -> Plan {
        var writes: [Write] = []
        var conflicts: [Conflict] = []

        for candidate in candidates {
            guard let slug = candidate.slug,
                  let incoming = letterboxdRatings[slug],
                  (1...10).contains(incoming) else { continue }

            switch candidate.existingRating {
            case .none:
                writes.append(Write(contentKey: candidate.contentKey, rating: incoming))
            case .some(let local) where local != incoming:
                conflicts.append(Conflict(contentKey: candidate.contentKey,
                                          local: local, letterboxd: incoming))
            default:
                break                      // they agree; nothing to do
            }
        }

        return Plan(writes: writes, conflicts: conflicts)
    }
}
