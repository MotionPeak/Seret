import Foundation

/// Turns TMDB's raw combined credits into a filmography worth looking at.
///
/// TMDB returns everything: talk-show drop-ins, archive footage, uncredited bits, a hundred
/// entries for a working actor. Shown raw, a person page buries the work you would recognise.
///
/// Pure — no network, no persistence, no ordering ambiguity.
extension [TMDBPersonCredit] {

    /// Acting credits, junk removed, most recognisable first.
    public func actingFilmography() -> [TMDBPersonCredit] {
        filter { !$0.isSelfAppearance }.presentable()
    }

    /// Directing credits only, most recognisable first.
    public func directingFilmography() -> [TMDBPersonCredit] {
        filter { $0.job == "Director" }.presentable()
    }

    /// Shared tail: drop the poster-less long tail, rank, then dedupe keeping the highest-ranked
    /// copy of a title credited more than once.
    private func presentable() -> [TMDBPersonCredit] {
        var seen = Set<String>()
        return filter { $0.result.posterPath != nil }
            .sorted(by: TMDBPersonCredit.moreProminent)
            .filter { seen.insert($0.id).inserted }
    }
}

extension TMDBPersonCredit {
    /// Someone appearing as themselves — a talk-show guest, a documentary interviewee. TMDB spells
    /// this several ways ("Self", "Self - Guest", "Himself"), and it is never what you came to the
    /// page to find.
    var isSelfAppearance: Bool {
        guard let c = character?.trimmingCharacters(in: .whitespaces).lowercased(),
              !c.isEmpty else { return false }
        if Self.selfRoles.contains(c) { return true }
        return c.hasPrefix("self ") || c.hasPrefix("self-") || c.hasPrefix("self(")
    }

    private static let selfRoles: Set<String> = [
        "self", "himself", "herself", "themselves", "themself",
    ]

    /// A **total** order, so the same filmography always renders the same way and the tests are not
    /// at the mercy of sort stability: popularity first (it answers "what do I know them from"),
    /// then newest, then title.
    static func moreProminent(_ a: TMDBPersonCredit, _ b: TMDBPersonCredit) -> Bool {
        let pa = a.popularity ?? 0, pb = b.popularity ?? 0
        if pa != pb { return pa > pb }
        let da = a.result.releaseDate ?? a.result.firstAirDate ?? ""
        let db = b.result.releaseDate ?? b.result.firstAirDate ?? ""
        if da != db { return da > db }
        return a.result.displayTitle < b.result.displayTitle
    }
}
