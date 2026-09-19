import Testing
import Foundation
@testable import DebridCore

@Suite struct WatchlistReconcilerTests {
    func crawled(_ slugs: [String]) -> [LetterboxdEntry] {
        slugs.map { LetterboxdEntry(slug: $0, name: "\($0) (1994)", year: 1994, rating: nil) }
    }

    func stored(_ slug: String, position: Int, tmdbID: Int?, poster: String? = nil) -> WatchlistEntry {
        WatchlistEntry(slug: slug, name: "\(slug) (1994)", year: 1994, position: position,
                       tmdbID: tmdbID, posterPath: poster,
                       resolvedAt: tmdbID == nil ? nil : Date(timeIntervalSince1970: 1))
    }

    @Test func aFirstCrawlBecomesTheWholeList() {
        let merged = WatchlistReconciler.merge(crawled: crawled(["a", "b", "c"]), into: [])
        #expect(merged.map(\.slug) == ["a", "b", "c"])
        #expect(merged.map(\.position) == [0, 1, 2])
    }

    @Test func crawlOrderIsThePosition() {
        // "c" was added most recently, so Letterboxd lists it first.
        let merged = WatchlistReconciler.merge(crawled: crawled(["c", "a", "b"]),
                                               into: [stored("a", position: 0, tmdbID: 1)])
        #expect(merged.map(\.slug) == ["c", "a", "b"])
        #expect(merged.first?.position == 0)
    }

    @Test func aResolvedIdSurvivesTheMerge() {
        let merged = WatchlistReconciler.merge(
            crawled: crawled(["a"]),
            into: [stored("a", position: 0, tmdbID: 1637, poster: "/p.jpg")])
        let a = merged[0]
        #expect(a.tmdbID == 1637)
        #expect(a.posterPath == "/p.jpg")
        #expect(a.isResolved)
    }

    /// Resolution is the expensive part; re-resolving everything on every sync would defeat it.
    @Test func aKnownUnmatchedEntryIsNotSilentlyMarkedUntried() {
        let triedAndFailed = WatchlistEntry(slug: "a", name: "A (1994)", year: 1994,
                                            position: 0, tmdbID: nil, resolvedAt: Date())
        let merged = WatchlistReconciler.merge(crawled: crawled(["a"]), into: [triedAndFailed])
        #expect(merged[0].isResolved)
        #expect(merged[0].tmdbID == nil)
    }

    /// A resolution answered a question about the name *as it read at the time*. When the name
    /// changes, an attempt that found nothing was answering a different question and deserves to be
    /// asked again — which is the only route by which a parser fix reaches a watchlist that has
    /// already been synced. Every entry on disk carries a `resolvedAt`, and only the never-tried
    /// are retried, so without this the grey boxes are permanent.
    @Test func anUnmatchedEntryIsAskedAgainWhenItsNameChanges() {
        let escaped = WatchlistEntry(slug: "honey-dont", name: "Honey Don&#039;t! (2025)",
                                     year: 2025, position: 0, tmdbID: nil, resolvedAt: Date())
        let decoded = [LetterboxdEntry(slug: "honey-dont", name: "Honey Don't! (2025)",
                                       year: 2025, rating: nil)]

        let merged = WatchlistReconciler.merge(crawled: decoded, into: [escaped])
        #expect(merged[0].name == "Honey Don't! (2025)")
        #expect(merged[0].isResolved == false)
    }

    /// A match that WORKED is kept. The TMDB id is right whatever the display name now reads, and
    /// re-resolving a good match risks trading it for a worse one.
    @Test func aMatchedEntryKeepsItsIDWhenItsNameChanges() {
        let matched = WatchlistEntry(slug: "a", name: "Old Title (1994)", year: 1994, position: 0,
                                     tmdbID: 1637, posterPath: "/p.jpg", resolvedAt: Date())
        let renamed = [LetterboxdEntry(slug: "a", name: "New Title (1994)", year: 1994, rating: nil)]

        let merged = WatchlistReconciler.merge(crawled: renamed, into: [matched])
        #expect(merged[0].tmdbID == 1637)
        #expect(merged[0].posterPath == "/p.jpg")
        #expect(merged[0].isResolved)
    }

    /// Case alone is not a change: TMDB is searched case-insensitively, so re-resolving over it
    /// would spend a request to arrive at the same answer.
    @Test func aCaseOnlyDifferenceIsNotAChange() {
        let triedAndFailed = WatchlistEntry(slug: "a", name: "A (1994)", year: 1994,
                                            position: 0, tmdbID: nil, resolvedAt: Date())
        let merged = WatchlistReconciler.merge(crawled: crawled(["a"]), into: [triedAndFailed])
        #expect(merged[0].isResolved)
    }

    @Test func aFilmRemovedOnLetterboxdIsDropped() {
        let merged = WatchlistReconciler.merge(
            crawled: crawled(["a"]),
            into: [stored("a", position: 0, tmdbID: 1), stored("gone", position: 1, tmdbID: 2)])
        #expect(merged.map(\.slug) == ["a"])
    }

    @Test func anEmptyCrawlEmptiesTheList() {
        // A genuinely empty watchlist. The caller is responsible for not merging a FAILED crawl —
        // the syncer throws instead of returning [], so this can only mean "no films".
        let merged = WatchlistReconciler.merge(crawled: [], into: [stored("a", position: 0, tmdbID: 1)])
        #expect(merged.isEmpty)
    }

    @Test func aNewEntryStartsUnresolved() {
        let merged = WatchlistReconciler.merge(crawled: crawled(["new"]), into: [])
        #expect(merged[0].isResolved == false)
        #expect(merged[0].tmdbID == nil)
    }
}
