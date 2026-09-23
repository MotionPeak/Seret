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
