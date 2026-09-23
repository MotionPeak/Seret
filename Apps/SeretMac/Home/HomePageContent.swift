import DebridCore
import DebridUI

/// What the Home screen shows, derived from the library's load state and the counts of what
/// `HomeStore` and `DownloadStore` have composed. Pure so the state → screen mapping is
/// unit-tested without a view or a store.
enum HomePageContent: Equatable {
    case skeleton, empty, failed(String), content

    /// Anything to show at all → content, even mid-load — the snapshot the store already holds
    /// fills Home while a fresh library load runs behind it. Nothing to show: no store yet or
    /// `.loading` → skeleton (the first load); `.failed(m)` → failed(m); anything else (`.loaded`
    /// or `.empty` with nothing composed) → empty.
    static func make(library: LibraryStore.State?, continueWatching: Int, recentlyAdded: Int,
                     downloading: Int) -> HomePageContent {
        if continueWatching > 0 || recentlyAdded > 0 || downloading > 0 { return .content }
        switch library {
        case nil, .loading:
            return .skeleton
        case .failed(let message):
            return .failed(message)
        case .loaded, .empty:
            return .empty
        }
    }
}

/// The Continue-hero and landscape card's copy: how much of a film is left, or an episode's own
/// tag. Pure so the exact wording is tested without `DetailStore`/`HomeStore` plumbing.
enum ContinueCaption {
    /// Film: time left from the saved position — "1h 13m left", "42 min left", "Almost done"
    /// (< 60 s left). Episode: its subtitle ("S1 · E3"). Nothing known → "".
    static func caption(kind: MediaKind, subtitle: String, resumeAt: Double?, fraction: Double) -> String {
        switch kind {
        case .show:
            return subtitle
        case .movie:
            guard let resumeAt, fraction > 0 else { return "" }
            // `HomeItem` doesn't carry the duration directly — resumeAt / fraction recovers it.
            let duration = resumeAt / fraction
            return timeLeftText(duration - resumeAt)
        }
    }

    /// The hero's eyebrow: "Continue · 1h 13m left" / "Continue · S1 · E3" / "Continue Watching"
    /// when nothing more specific is known.
    static func eyebrow(kind: MediaKind, subtitle: String, resumeAt: Double?, fraction: Double) -> String {
        let cap = caption(kind: kind, subtitle: subtitle, resumeAt: resumeAt, fraction: fraction)
        return cap.isEmpty ? "Continue Watching" : "Continue \u{00B7} \(cap)"
    }

    private static func timeLeftText(_ seconds: Double) -> String {
        guard seconds >= 60 else { return "Almost done" }
        let totalMinutes = Int((seconds / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        guard hours > 0 else { return "\(minutes) min left" }
        return minutes > 0 ? "\(hours)h \(minutes)m left" : "\(hours)h left"
    }
}
