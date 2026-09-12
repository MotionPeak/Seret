import Foundation

/// How a show's seasons are ordered for viewing, and what season 0 is called.
///
/// Season 0 is Specials — TMDB's own name for it, and where `SxxE00` files land (see
/// `FilenameParser.resolvingSpecial`). Sorted naively it comes FIRST, which puts a show's extras
/// and unaired pilot ahead of its premiere: the picker opens on them, "what to play next" returns
/// one, and Play starts there. That is the same fault that filing the pilot as S1E0 caused, just
/// moved. Every media server puts Specials last; so does this.
public enum SeasonOrder {

    /// The season number of Specials.
    public static let specials = 0

    /// True when season `a` comes before season `b` in viewing order: 1, 2, 3 … then Specials.
    public static func before(_ a: Int, _ b: Int) -> Bool {
        if (a == specials) != (b == specials) { return b == specials }
        return a < b
    }

    /// "Specials" for season 0, "Season 3" otherwise. One definition, because both apps print it
    /// and a show whose extras row said "Season 0" would read as a bug rather than a category.
    public static func label(_ season: Int) -> String {
        season == specials ? "Specials" : "Season \(season)"
    }
}

public extension Sequence where Element == Int {
    /// Season numbers in viewing order — Specials last.
    func sortedBySeason() -> [Int] { sorted(by: SeasonOrder.before) }
}

public extension Sequence where Element == Season {
    /// Seasons in viewing order — Specials last.
    func sortedBySeason() -> [Season] { sorted { SeasonOrder.before($0.number, $1.number) } }
}
