import DebridCore
import DebridUI
import Foundation

/// Pure text for the title page's hero: the meta line and what the primary button reads. Kept
/// separate from `DetailStore.PrimaryPlay` (its memberwise init is internal to `DebridUI`) so the
/// Mac can test the exact strings without building a store.
enum TitlePageText {
    /// `"2024 · 2h 46m · Science Fiction · Adventure"`. Runtime under an hour is minutes only; at
    /// most 3 genres; a show's season count reads "1 Season" / "n Seasons". Missing parts are
    /// skipped rather than leaving a stray separator.
    static func metaLine(year: Int?, runtimeMinutes: Int?, genres: [String], seasonCount: Int?) -> String {
        var parts: [String] = []
        if let year { parts.append(String(year)) }
        if let runtimeMinutes, runtimeMinutes > 0 { parts.append(runtimeText(runtimeMinutes)) }
        parts.append(contentsOf: genres.prefix(3))
        if let seasonCount, seasonCount > 0 {
            parts.append(seasonCount == 1 ? "1 Season" : "\(seasonCount) Seasons")
        }
        return parts.joined(separator: " · ")
    }

    private static func runtimeText(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    /// What the hero's primary button reads. Film: "Play" / "Resume · 1:02:33". Show: "Play S1·E3"
    /// / "Resume S1·E3" — the same "S{n}·E{n}" tag `DetailStore.episodeLabel` uses.
    static func primaryTitle(episode: (season: Int, number: Int)?, resumeAt: Double?) -> String {
        if let episode {
            let tag = "S\(episode.season)·E\(episode.number)"
            return resumeAt != nil ? "Resume \(tag)" : "Play \(tag)"
        }
        guard let resumeAt else { return "Play" }
        return "Resume · \(Timecode.format(resumeAt))"
    }

    /// What the hero's disabled primary button reads when nothing is playable (Decision 2). Owned
    /// but nothing usable is in the library for it → "Not Available"; not owned at all (acquiring
    /// is M3) → "Not in Your Library".
    static func unavailableTitle(isOwned: Bool) -> String {
        isOwned ? "Not Available" : "Not in Your Library"
    }

    /// "Dir. Denis Villeneuve" / "Created by Vince Gilligan, Peter Gould"; nil when there is no
    /// credit at all — the row simply does not draw.
    static func creditLine(kind: MediaKind, names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        let prefix = kind == .movie ? "Dir." : "Created by"
        return "\(prefix) \(names.joined(separator: ", "))"
    }

    /// "Film 2 of 3 · Dune Collection" — the "3" is released films only (`Franchise.count`
    /// already dropped anything unreleased when it was built).
    static func franchiseLine(_ f: Franchise) -> String {
        "Film \(f.position) of \(f.count) · \(f.name)"
    }

    /// "8.5" — one decimal, IMDb's own scale.
    static func imdb(_ v: Double) -> String { String(format: "%.1f", v) }

    /// "92%" — Rotten Tomatoes' own scale.
    static func rottenTomatoes(_ v: Int) -> String { "\(v)%" }

    /// "4.4" — Letterboxd's own 0.5–5 scale, one decimal.
    static func letterboxd(_ v: Double) -> String { String(format: "%.1f", v) }

    /// Which colour a Metacritic score reads in: their own thresholds.
    enum MetacriticBand: Equatable { case good, mixed, bad }
    static func metacriticBand(_ v: Int) -> MetacriticBand {
        v >= 61 ? .good : (v >= 40 ? .mixed : .bad)
    }

    /// The not-owned hero's primary button: "Play" (film) / "Play S1·E1" (show, from
    /// `nextEpisodeTarget()`) / "Finding a version…" while `TitleAcquirer` is busy on it.
    static func acquireTitle(episode: (season: Int, number: Int)?, finding: Bool) -> String {
        if finding { return "Finding a version\u{2026}" }
        if let episode { return "Play S\(episode.season)\u{00B7}E\(episode.number)" }
        return "Play"
    }

    /// The viewer's own history with a title: how many times, when last, and how far back it goes
    /// (tvOS `WatchDatesLine` wording, but "watched N times" and "last on DATE" share one line —
    /// mockup 5's layout). Either line is dropped independently when it has nothing to say; an
    /// empty history returns no lines at all.
    static func historyLines(summary: WatchSummary?, since: Date?) -> [String] {
        var lines: [String] = []
        if let summary, summary.plays > 0 {
            var line = "Watched \(summary.plays) time\(summary.plays == 1 ? "" : "s")"
            if let last = summary.lastWatchedAt {
                line += " \u{00B7} last on \(last.formatted(date: .abbreviated, time: .omitted))"
            }
            lines.append(line)
        }
        if let since {
            lines.append("In your history since \(since.formatted(date: .abbreviated, time: .omitted))")
        }
        return lines
    }
}

/// Pure layout math for the title page: the hero's height and the episode grid's column count, both
/// driven by the window's measured width rather than a fixed size.
enum TitlePageLayout {
    /// Window width × 0.37, clamped to a band that stays readable whether the window is narrow or
    /// very wide.
    static func heroHeight(width: CGFloat) -> CGFloat {
        max(380, min(620, width * 0.37))
    }

    /// 3-up on a wide window, 2-up in the middle, 1 column on a narrow one.
    static func episodeColumns(width: CGFloat) -> Int {
        if width >= 900 { return 3 }
        if width >= 560 { return 2 }
        return 1
    }
}
