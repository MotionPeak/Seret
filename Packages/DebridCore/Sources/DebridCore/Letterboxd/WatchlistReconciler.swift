import Foundation

/// Merges a crawl of the Letterboxd watchlist into what is already stored.
///
/// Pure, because this decides what the owner sees and what gets thrown away, and that should be
/// provable without a network or a disk.
///
/// A crawl is the whole truth: anything absent from it has been removed on Letterboxd and is
/// dropped here. What survives a merge is the expensive part — a resolved TMDB id, and the fact
/// that a resolution was attempted at all.
public enum WatchlistReconciler {
    /// `crawled` is in page order — index 0 is the most recently added.
    public static func merge(crawled: [LetterboxdEntry],
                             into existing: [WatchlistEntry]) -> [WatchlistEntry] {
        let known = Dictionary(existing.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })

        return crawled.enumerated().map { index, entry in
            let previous = known[entry.slug]
            return WatchlistEntry(slug: entry.slug,
                                  name: entry.name,
                                  year: entry.year,
                                  position: index,
                                  tmdbID: previous?.tmdbID,
                                  posterPath: previous?.posterPath,
                                  resolvedAt: previous?.resolvedAt)
        }
    }
}
