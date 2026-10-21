import Foundation

/// Everything the picker needs, gathered by the caller. Pure data: the picker does no I/O, so the
/// slow part (Letterboxd pages, TMDB details) happens elsewhere and this can be tested by hand.
public struct WatchlistPickInputs: Sendable {
    /// The owner's films, newest first (the films/by/date page order).
    public var recentFilms: [LetterboxdEntry]
    /// Reference slug -> similar slugs, in Letterboxd's order.
    public var similar: [String: [String]]
    /// Similar slug -> ITS similar slugs. Looser than `similar`: one more hop from the reference.
    public var secondHop: [String: [String]]
    /// Reference slug -> slugs by that film's director(s).
    public var directorFilms: [String: [String]]
    /// Reference slug -> Letterboxd genres.
    public var referenceGenres: [String: [String]]
    /// The owner's and partner's watchlists merged (`WatchlistMerge.combine`).
    public var candidates: [WatchlistEntry]
    /// Nil without a partner.
    public var membership: WatchlistMembership?
    /// TMDB id -> genres, for the candidates that have details.
    public var candidateGenres: [Int: [String]]
    /// Every slug in the owner's films, whatever the rating.
    public var watchedSlugs: Set<String>
    /// TMDB ids finished locally.
    public var watchedTMDB: Set<Int>

    public init(recentFilms: [LetterboxdEntry],
                similar: [String: [String]] = [:],
                secondHop: [String: [String]] = [:],
                directorFilms: [String: [String]] = [:],
                referenceGenres: [String: [String]] = [:],
                candidates: [WatchlistEntry],
                membership: WatchlistMembership? = nil,
                candidateGenres: [Int: [String]] = [:],
                watchedSlugs: Set<String> = [],
                watchedTMDB: Set<Int> = []) {
        self.recentFilms = recentFilms
        self.similar = similar
        self.secondHop = secondHop
        self.directorFilms = directorFilms
        self.referenceGenres = referenceGenres
        self.candidates = candidates
        self.membership = membership
        self.candidateGenres = candidateGenres
        self.watchedSlugs = watchedSlugs
        self.watchedTMDB = watchedTMDB
    }
}

/// A watchlist film chosen for the Home row, with why it was chosen.
public struct WatchlistPick: Sendable, Codable, Equatable {
    public let entry: WatchlistEntry
    public let score: Double
    public let tier: Tier

    /// The best signal a film has. Rows fill tier by tier, so a close match always beats a
    /// director match however the scores compare.
    public enum Tier: Int, Sendable, Codable, Comparable {
        case close = 0, director = 1, loose = 2, genre = 3

        public static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public init(entry: WatchlistEntry, score: Double, tier: Tier) {
        self.entry = entry
        self.score = score
        self.tier = tier
    }
}

/// Chooses watchlist films that fit what the owner has watched lately.
///
/// Pure scoring. Each of the owner's recent films is a "reference" whose weight falls with age and
/// with how little the owner liked it; a watchlist film earns points for every way it relates to a
/// reference (similar, same director, similar-of-similar, shared genre and era). Its tier is the
/// strongest of those ways, its score the sum of all of them.
public enum WatchlistPicker {
    public static let referenceCount = 30
    public static let rowTarget = 20

    /// A film from the genre signal must be within this many years of the reference.
    private static let genreYearWindow = 12
    private static let bothListsBump = 1.15

    /// The first `referenceCount` films, in page order, that the owner did not dislike.
    public static func references(_ recent: [LetterboxdEntry]) -> [LetterboxdEntry] {
        Array(recent.lazy.filter { likingWeight($0.rating) > 0 }.prefix(referenceCount))
    }

    public static func pick(_ inputs: WatchlistPickInputs, limit: Int = rowTarget) -> [WatchlistPick] {
        guard limit > 0 else { return [] }
        let refs = references(inputs.recentFilms)
        guard !refs.isEmpty else { return [] }
        let refSlugs = Set(refs.map(\.slug))

        var eligible: [String: WatchlistEntry] = [:]
        for entry in inputs.candidates {
            guard let tmdb = entry.tmdbID, !entry.isRemoved,
                  !inputs.watchedSlugs.contains(entry.slug), !inputs.watchedTMDB.contains(tmdb),
                  !refSlugs.contains(entry.slug) else { continue }
            eligible[entry.slug] = entry
        }
        guard !eligible.isEmpty else { return [] }

        var scores: [String: Double] = [:]
        var tiers: [String: WatchlistPick.Tier] = [:]
        func add(_ slug: String, _ points: Double, _ tier: WatchlistPick.Tier) {
            guard eligible[slug] != nil else { return }
            scores[slug, default: 0] += points
            tiers[slug] = min(tiers[slug] ?? tier, tier)
        }

        for (index, ref) in refs.enumerated() {
            let weight = recencyWeight(index) * likingWeight(ref.rating)

            // Close: the reference's own similar list, once per film (first mention counts).
            let similar = inputs.similar[ref.slug] ?? []
            var firstPosition: [String: Int] = [:]
            for (offset, slug) in similar.enumerated() where firstPosition[slug] == nil {
                firstPosition[slug] = offset + 1
            }
            for (slug, position) in firstPosition {
                add(slug, weight * positionWeight(position), .close)
            }

            // Director: other films by the reference's director(s), once per reference.
            for slug in Set(inputs.directorFilms[ref.slug] ?? []) {
                add(slug, 0.5 * weight, .director)
            }

            // Loose: similar-of-similar. A film reached through several hops takes the best one,
            // so one reference cannot count it more than once.
            var bestHop: [String: Double] = [:]
            for (slug, position) in firstPosition {
                let hop = positionWeight(position)
                for second in Set(inputs.secondHop[slug] ?? []) {
                    bestHop[second] = max(bestHop[second] ?? 0, hop)
                }
            }
            for (slug, hop) in bestHop {
                add(slug, 0.25 * weight * hop, .loose)
            }

            // Genre: shared genres, and only for a film from the same era.
            let refGenres = Set((inputs.referenceGenres[ref.slug] ?? []).map { $0.lowercased() })
            if !refGenres.isEmpty, let refYear = ref.year {
                for (slug, entry) in eligible {
                    guard let year = entry.year, abs(year - refYear) <= genreYearWindow,
                          let tmdb = entry.tmdbID,
                          let genres = inputs.candidateGenres[tmdb] else { continue }
                    let shared = refGenres.intersection(genres.map { $0.lowercased() }).count
                    if shared > 0 { add(slug, 0.1 * weight * Double(shared), .genre) }
                }
            }
        }

        let picks: [WatchlistPick] = scores.compactMap { slug, score in
            guard let entry = eligible[slug], let tier = tiers[slug] else { return nil }
            let holders = inputs.membership?.holders(of: entry)
            let both = holders.map { $0.owner && $0.partner } ?? false
            return WatchlistPick(entry: entry, score: both ? score * bothListsBump : score, tier: tier)
        }

        // Tier, then score, then the watchlist's own order. The slug is only a last resort so the
        // result never depends on dictionary order.
        return Array(picks.sorted { lhs, rhs in
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.entry.position != rhs.entry.position { return lhs.entry.position < rhs.entry.position }
            return lhs.entry.slug < rhs.entry.slug
        }.prefix(limit))
    }

    // MARK: - Weights

    /// 1.0 for the newest reference falling to 0.3 for the last of `referenceCount`.
    private static func recencyWeight(_ index: Int) -> Double {
        1.0 - 0.7 * Double(index) / Double(referenceCount - 1)
    }

    /// How much a rating (1-10 half-stars) says the owner liked it. Unrated is a mild yes, since
    /// logging a film at all is some signal; 2 stars or under means do not recommend more of it.
    private static func likingWeight(_ rating: Int?) -> Double {
        guard let rating else { return 0.6 }
        switch rating {
        case 9...: return 1.0
        case 7...8: return 0.8
        case 5...6: return 0.5
        default: return 0
        }
    }

    /// Where the film sits in a similar list (1-based): the top of the list means far more than the tail.
    private static func positionWeight(_ position: Int) -> Double {
        switch position {
        case ...12: return 1.0
        case 13...36: return 0.7
        default: return 0.4
        }
    }
}
