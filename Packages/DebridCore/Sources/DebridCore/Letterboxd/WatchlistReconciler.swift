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
                                  resolvedAt: carriedResolution(previous, crawledName: entry.name))
        }
    }

    /// When a previous attempt may still be trusted.
    ///
    /// A resolution answered a question about the name *as it read at the time*. If the name has
    /// since changed and the attempt found nothing, it was answering a different question — so
    /// forget it, and the next sync asks again. This is the only route by which a parsing fix
    /// reaches an already-synced watchlist: every stored entry carries a `resolvedAt`, and the
    /// syncer only retries the never-tried.
    ///
    /// A match that WORKED is kept regardless: its id is right whatever the display name now
    /// reads, and re-resolving a good match only risks trading it for a worse one.
    private static func carriedResolution(_ previous: WatchlistEntry?,
                                          crawledName: String) -> Date? {
        guard let previous, previous.tmdbID == nil else { return previous?.resolvedAt }
        // Case alone is not a change — TMDB is searched case-insensitively, so re-resolving over
        // it would spend a request to arrive at the same answer.
        let sameQuestion = previous.name.caseInsensitiveCompare(crawledName) == .orderedSame
        return sameQuestion ? previous.resolvedAt : nil
    }
}
