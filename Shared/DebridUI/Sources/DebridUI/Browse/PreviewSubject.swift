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
    public let overview: String?
    public let backdropPath: String?
    public let posterPath: String?
    /// "Season 1 · Episode 3", or "Next · Season 2 · Episode 1" for an up-next entry.
    public let episodeLine: String?
    /// Minutes left to watch. Only set when both the progress and the runtime are known.
    public let remainingMinutes: Int?
    public let fraction: Double?

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
        if let runtimeMinutes, runtimeMinutes > 0 {
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
    /// guess (`"20"` must not become the year 20).
    private static func year(from date: String?) -> Int? {
        guard let prefix = date?.prefix(4), prefix.count == 4,
              prefix.allSatisfy(\.isASCII), let year = Int(prefix) else { return nil }
        return year
    }
}
