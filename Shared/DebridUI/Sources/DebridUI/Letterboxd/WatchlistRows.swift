import Foundation
import DebridCore

/// One row of the Apple TV Watchlist page: a titled rail whose "See All" opens every film in it.
public struct WatchlistRow: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case library, recent, highestRated, both, partnerPicks, genre(String), short, classics
        /// Films TMDB could not match — kept reachable (and removable), never mixed into the rest.
        case unmatched
    }

    /// Stable for the row's life: the page scrolls to it and keys focus by it, and a row filling
    /// in as details arrive must keep the id it had.
    public let id: String
    public let kind: Kind
    public let title: String
    /// The quiet words after the title ("ready to play").
    public let subtitle: String?
    /// Every film in the row, in the row's order. A rail shows the first `WatchlistRows.railLimit`.
    public let entries: [WatchlistEntry]

    public init(id: String, kind: Kind, title: String, subtitle: String?, entries: [WatchlistEntry]) {
        self.id = id; self.kind = kind; self.title = title; self.subtitle = subtitle
        self.entries = entries
    }
}

/// Builds the Watchlist page's rows. Pure: everything it needs is passed in.
///
/// In order, skipping any that come out empty: In Your Library · Recently Added · Highest Rated ·
/// You Both Want to See · <Partner>'s Picks · a row per genre (at most `maxGenreRows`, by count) ·
/// Short Ones · Classics · Not Matched. Rows that need TMDB details (rating, genres, runtime) are
/// simply absent until those arrive, and every row keeps one id however its contents change.
public enum WatchlistRows {
    /// How many films a rail shows before its See All. The grid behind it shows them all.
    public static let railLimit = 30
    public static let maxGenreRows = 10
    /// Fewer voters than this and an average says little.
    public static let minimumVotes = 200
    public static let shortRuntime = 100
    public static let classicsBefore = 1980

    public static func build(entries: [WatchlistEntry],
                             details: [Int: WatchlistFilmDetails],
                             isOwned: (WatchlistEntry) -> Bool,
                             membership: WatchlistMembership?,
                             partnerName: String?) -> [WatchlistRow] {
        let ordered = entries.sorted { $0.position < $1.position }
        let matched = ordered.filter { $0.tmdbID != nil }
        let unmatched = ordered.filter { $0.tmdbID == nil }
        func info(_ entry: WatchlistEntry) -> WatchlistFilmDetails? { entry.tmdbID.flatMap { details[$0] } }

        var rows: [WatchlistRow] = []
        func add(_ id: String, _ kind: WatchlistRow.Kind, _ title: String, _ subtitle: String?,
                 _ films: [WatchlistEntry]) {
            guard !films.isEmpty else { return }
            rows.append(WatchlistRow(id: id, kind: kind, title: title, subtitle: subtitle, entries: films))
        }

        add("library", .library, "In Your Library", "ready to play", matched.filter(isOwned))
        add("recent", .recent, "Recently Added", nil, matched)

        let rated = matched.enumerated().compactMap { index, entry -> (Int, Double, WatchlistEntry)? in
            guard let d = info(entry), let vote = d.voteAverage, vote > 0,
                  (d.voteCount ?? minimumVotes) >= minimumVotes else { return nil }
            return (index, vote, entry)
        }
        .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        .map(\.2)
        add("rated", .highestRated, "Highest Rated", "by TMDB rating", rated)

        if let membership, let partnerName {
            let holders = matched.map { ($0, membership.holders(of: $0)) }
            add("both", .both, "You Both Want to See", "on both lists",
                holders.filter { $0.1.owner && $0.1.partner }.map(\.0))
            add("partner", .partnerPicks, "\(partnerName)'s Picks", nil,
                holders.filter { !$0.1.owner && $0.1.partner }.map(\.0))
        }

        var byGenre: [String: [WatchlistEntry]] = [:]
        for entry in matched {
            for genre in Set((info(entry)?.genres ?? []).compactMap(shortGenre)) {
                byGenre[genre, default: []].append(entry)
            }
        }
        let genres = byGenre.sorted { a, b in
            a.value.count != b.value.count ? a.value.count > b.value.count : a.key < b.key
        }
        for (genre, films) in genres.prefix(maxGenreRows) {
            add("genre-\(genre)", .genre(genre), genre, nil, films)
        }

        add("short", .short, "Short Ones", "under \(shortRuntime) minutes", matched.filter {
            guard let runtime = info($0)?.runtimeMinutes else { return false }
            return runtime > 0 && runtime < shortRuntime
        })
        add("classics", .classics, "Classics", "before \(classicsBefore)", matched.filter {
            guard let year = $0.year else { return false }
            return year < classicsBefore
        })
        add("unmatched", .unmatched, "Not Matched", nil, unmatched)
        return rows
    }

    /// A genre's row name: TMDB's, shortened where it is long. Nil for what is not a genre a
    /// viewer browses by.
    static func shortGenre(_ name: String) -> String? {
        switch name {
        case "Science Fiction": return "Sci-Fi"
        case "TV Movie", "": return nil
        default: return name
        }
    }

    /// The chip on a poster: "Both" for a film on both lists, the partner's name for one only on
    /// theirs. Nothing for the owner's own films, or with no partner.
    public static func badge(for entry: WatchlistEntry, membership: WatchlistMembership?,
                             partnerName: String?) -> String? {
        guard let membership, let partnerName else { return nil }
        let held = membership.holders(of: entry)
        switch (held.owner, held.partner) {
        case (true, true): return "Both"
        case (false, true): return partnerName
        default: return nil
        }
    }

    /// The outlined tags in the page's header for the focused film.
    public static func tags(for entry: WatchlistEntry, owned: Bool, membership: WatchlistMembership?,
                            partnerName: String?) -> [String] {
        var tags: [String] = []
        if owned { tags.append("In Library") }
        if let membership, let partnerName {
            let held = membership.holders(of: entry)
            switch (held.owner, held.partner) {
            case (true, true): tags.append("Both of you")
            case (false, true): tags.append("\(partnerName)'s pick")
            default: break
            }
        }
        return tags
    }
}
