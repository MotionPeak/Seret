import Foundation
import DebridCore

/// What the focus-driven preview header describes: one title (or one resumable episode) reduced to
/// the plain fields the header renders. Built from whatever the focused tile carries — a library
/// item, a Continue Watching entry or a search hit — so the header never needs to know which.
public struct PreviewSubject: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: MediaKind
    public let tmdbID: Int?
    public let title: String
    public let year: Int?
    public private(set) var overview: String?
    public private(set) var backdropPath: String?
    public let posterPath: String?
    /// "Season 1 · Episode 3", or "Next · Season 2 · Episode 1" for an up-next entry.
    public let episodeLine: String?
    /// Minutes left to watch. Only set when both the progress and the runtime are known.
    public let remainingMinutes: Int?
    public let fraction: Double?
    /// Small outlined labels after the metadata row — the Watchlist's "In Library", "Both of you".
    public private(set) var tags: [String] = []
    /// Whether the metadata row names the kind ("Movie", "Series"). A page that only ever holds
    /// films (the Watchlist) leaves it out.
    public private(set) var showsKind = true

    public init(item: MediaItem) {
        id = item.id
        kind = item.kind
        tmdbID = item.tmdbID
        title = item.title
        year = item.year
        overview = Self.clean(item.overview)
        backdropPath = item.backdropPath
        posterPath = item.posterPath
        episodeLine = nil
        remainingMinutes = nil
        fraction = nil
    }

    /// A library item (or a watchlist film's stand-in) with facts its tile does not carry: the
    /// synopsis and backdrop come from a details cache, the tags from the page.
    public init(item: MediaItem, overview: String?, backdropPath: String?, tags: [String],
                showsKind: Bool) {
        self.init(item: item)
        self.overview = Self.clean(overview) ?? self.overview
        self.backdropPath = backdropPath ?? self.backdropPath
        self.tags = tags
        self.showsKind = showsKind
    }

    public init(home: HomeItem, runtimeMinutes: Int? = nil) {
        let item = home.item
        // `HomeItem.id` carries the episode label, so two episodes of one show stay distinct.
        id = home.id
        kind = item.kind
        tmdbID = item.tmdbID
        title = item.title
        year = item.year
        overview = Self.clean(item.overview)
        backdropPath = item.backdropPath
        posterPath = item.posterPath
        if let episode = home.episode {
            let line = "Season \(episode.season) · Episode \(episode.number)"
            episodeLine = home.isUpNext ? "Next · \(line)" : line
        } else {
            episodeLine = nil
        }
        let watched = min(max(home.fraction, 0), 1)
        fraction = home.fraction
        // An unstarted entry (up-next, fraction 0) has nothing "left" to report: it shows its
        // runtime elsewhere, never "52m left".
        if let runtimeMinutes, runtimeMinutes > 0, home.fraction > 0 {
            remainingMinutes = Int((Double(runtimeMinutes) * (1 - watched)).rounded())
        } else {
            remainingMinutes = nil
        }
    }

    public init(hit: SearchHit) {
        id = hit.id
        kind = hit.kind
        tmdbID = hit.result.id
        title = hit.result.displayTitle
        year = Self.year(from: hit.result.releaseDate ?? hit.result.firstAirDate)
        overview = Self.clean(hit.result.overview)
        backdropPath = nil
        posterPath = hit.result.posterPath
        episodeLine = nil
        remainingMinutes = nil
        fraction = nil
    }

    private static func clean(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    /// The leading four digits of a TMDB date. A short or non-numeric string is "no year", not a
    /// guess (`"20"` must not become the year 20, nor `"+123"` 123).
    private static func year(from date: String?) -> Int? {
        guard let prefix = date?.prefix(4), prefix.count == 4,
              prefix.allSatisfy({ ("0"..."9").contains($0) }), let year = Int(prefix) else { return nil }
        return year
    }
}
