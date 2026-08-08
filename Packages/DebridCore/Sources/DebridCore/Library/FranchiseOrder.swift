import Foundation

/// Puts a franchise in the order a person actually watches it: **the order the films came out**.
///
/// Deliberately not story order. A prequel released after the original is shown after it, because
/// that is how the series was experienced. Films that are not out yet are dropped entirely — they
/// are not watchable, and counting them would make "Film 3 of 5" read as "of 6".
///
/// Pure: `now` is injected, so the unreleased rule is testable instead of clock-dependent.
public enum FranchiseOrder {
    /// TMDB release dates are `YYYY-MM-DD`, which sorts and compares correctly as text — so the
    /// only date work here is rendering "today" in that same shape. Fixed to UTC: which side of
    /// midnight the viewer is on must not change what counts as released.
    ///
    /// A `Calendar` is a Sendable value type, unlike `ISO8601DateFormatter`, which Swift 6 refuses
    /// to hold in a `static let` at all.
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// `now` as the same `YYYY-MM-DD` shape TMDB uses. Exposed so tests can express "today".
    public static func dateString(_ date: Date) -> String {
        let parts = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Released members of a franchise, oldest first, deduped by id.
    public static func ordered(_ parts: [TMDBSearchResult], now: Date) -> [TMDBSearchResult] {
        let today = dateString(now)
        var seen = Set<Int>()
        return parts
            .compactMap { part -> (date: String, part: TMDBSearchResult)? in
                guard let date = part.releaseDate, date.count >= 10, date <= today else { return nil }
                return (date, part)
            }
            .sorted { $0.date < $1.date }
            .filter { seen.insert($0.part.id).inserted }
            .map(\.part)
    }

    /// Where a film sits in an ordered franchise, 1-based — the "3" in "Film 3 of 5".
    /// Nil when the film is not part of the order (unreleased, or a different franchise).
    public static func position(of tmdbID: Int, in ordered: [TMDBSearchResult]) -> Int? {
        ordered.firstIndex { $0.id == tmdbID }.map { $0 + 1 }
    }
}
