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
    ///
    /// `crawledAt` is when the crawl was STARTED, and it only matters to films added in Seret: a
    /// push that landed after that instant cannot be in what came back, so the row has to survive
    /// this merge to be judged by the next one.
    public static func merge(crawled: [LetterboxdEntry],
                             into existing: [WatchlistEntry],
                             crawledAt: Date = Date()) -> [WatchlistEntry] {
        let known = Dictionary(existing.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })

        // Films added here that the crawl could not have known about, kept in front of it: they are
        // the newest thing on the list, and Letterboxd orders newest first.
        let carried = existing.filter { $0.isLocalAdd && isStillLive($0, crawledAt: crawledAt) }

        return carried + crawled.enumerated().map { index, entry in
            let previous = known[entry.slug]
            return WatchlistEntry(slug: entry.slug,
                                  name: entry.name,
                                  year: entry.year,
                                  position: index,
                                  tmdbID: previous?.tmdbID,
                                  posterPath: previous?.posterPath,
                                  resolvedAt: carriedResolution(previous, crawledName: entry.name),
                                  // Carried, or Remove would be undone by the very next sync.
                                  removedAt: previous?.removedAt,
                                  // Carried for the same reason as the mark itself: a crawl must
                                  // not make an already-pushed removal look pending again.
                                  removalPushedAt: previous?.removalPushedAt)
        }
    }

    /// Whether a film added in Seret still has something to say that the crawl does not.
    ///
    /// Only local adds reach here. A crawled row needs no such judgement — being in the crawl is
    /// what makes it live.
    private static func isStillLive(_ entry: WatchlistEntry, crawledAt: Date) -> Bool {
        // Pushed while the crawl was in flight. This crawl could not have seen it, and retiring on
        // "pushed at all" would make the film blink out for a cycle every time the two coincided.
        if let pushed = entry.addPushedAt, pushed > crawledAt { return true }
        // Letterboxd has it, so the crawl now speaks for it. The only thing left that is true here
        // and nowhere else is a removal that has not been pushed.
        if entry.addPushedAt != nil { return entry.needsRemovalPush }
        // Never sent. Live until the owner takes it back — at which point there is nothing to push
        // and nothing to keep, because Letterboxd was never told in the first place.
        return !entry.isRemoved
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
