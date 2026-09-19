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

    /// A film removed in Seret must STAY removed across crawls.
    ///
    /// A crawl is otherwise the whole truth, so without carrying the mark the next sync hands the
    /// film straight back and Remove looks like it did nothing. Letterboxd still lists it — the
    /// mark is what makes the removal hold until the real push exists.
    @Test func aRemovedFilmStaysRemovedAcrossACrawl() {
        let when = Date(timeIntervalSince1970: 500)
        let removed = WatchlistEntry(slug: "a", name: "a (1994)", year: 1994, position: 0,
                                     tmdbID: 1, resolvedAt: Date(), removedAt: when)
        let merged = WatchlistReconciler.merge(crawled: crawled(["a"]), into: [removed])
        #expect(merged[0].removedAt == when)
        #expect(merged[0].isRemoved)
    }

    /// Gone from Letterboxd means gone, mark or no mark — the crawl already decides membership.
    @Test func aRemovedFilmAlsoDroppedOnLetterboxdSimplyDisappears() {
        let removed = WatchlistEntry(slug: "a", name: "a (1994)", year: 1994, position: 0,
                                     tmdbID: 1, resolvedAt: Date(), removedAt: Date())
        #expect(WatchlistReconciler.merge(crawled: [], into: [removed]).isEmpty)
    }

    @Test func anOrdinaryEntryIsNotRemoved() {
        let merged = WatchlistReconciler.merge(crawled: crawled(["a"]), into: [])
        #expect(merged[0].removedAt == nil)
        #expect(merged[0].isRemoved == false)
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

    // MARK: - Films added in Seret

    /// The whole point of the local add: the film is not on Letterboxd yet, so the crawl that is
    /// otherwise the whole truth has nothing to say about it. Dropping it would delete the film the
    /// owner just added, on the very next sync.
    @Test func anUnpushedLocalAddSurvivesACrawlThatCannotKnowAboutIt() {
        let local = WatchlistEntry.locallyAdded(tmdbID: 1637, title: "Speed", year: 1994,
                                                posterPath: "/s.jpg", position: -1)
        let merged = WatchlistReconciler.merge(crawled: crawled(["a"]), into: [stored("a", position: 0, tmdbID: 1), local])

        #expect(merged.contains { $0.tmdbID == 1637 })
        #expect(merged.count == 2)
    }

    /// Letterboxd lists newest first, and a film added a moment ago is the newest there is.
    @Test func aLocalAddSortsAheadOfTheCrawl() {
        let local = WatchlistEntry.locallyAdded(tmdbID: 1637, title: "Speed", year: 1994,
                                                posterPath: nil, position: -1)
        let merged = WatchlistReconciler.merge(crawled: crawled(["a", "b"]), into: [local])

        #expect(merged.sorted { $0.position < $1.position }.first?.tmdbID == 1637)
    }

    /// Once Letterboxd has been told, the crawl is authoritative again: the film is in it under its
    /// real slug. Keeping the placeholder as well would show the film twice — and matching the two
    /// up by TMDB id cannot be relied on, because a crawled row whose title TMDB fails to match
    /// would leave the duplicate there forever.
    @Test func aPushedLocalAddIsRetiredByTheNextCrawl() {
        var pushed = WatchlistEntry.locallyAdded(tmdbID: 1637, title: "Speed", year: 1994,
                                                 posterPath: nil, position: -1)
        pushed.addPushedAt = Date(timeIntervalSince1970: 100)

        let merged = WatchlistReconciler.merge(crawled: crawled(["speed"]), into: [pushed],
                                               crawledAt: Date(timeIntervalSince1970: 200))

        #expect(merged.map(\.slug) == ["speed"])
    }

    /// A push that landed WHILE the crawl was in flight could not have appeared in it. Retiring on
    /// `addPushedAt != nil` alone would delete the film for one sync cycle every time the owner
    /// added something and the screen refreshed at the same moment.
    @Test func aPushThatLandedAfterTheCrawlStartedIsKept() {
        var pushed = WatchlistEntry.locallyAdded(tmdbID: 1637, title: "Speed", year: 1994,
                                                 posterPath: nil, position: -1)
        pushed.addPushedAt = Date(timeIntervalSince1970: 300)

        let merged = WatchlistReconciler.merge(crawled: crawled(["a"]), into: [pushed],
                                               crawledAt: Date(timeIntervalSince1970: 200))

        #expect(merged.contains { $0.tmdbID == 1637 })
    }

    /// Added here, pushed, then taken off again here. Letterboxd still lists it, so the row has to
    /// stay until the removal is pushed too — exactly as a crawled row would.
    @Test func aPushedLocalAddRemovedHereStaysUntilTheRemovalIsPushed() {
        var entry = WatchlistEntry.locallyAdded(tmdbID: 1637, title: "Speed", year: 1994,
                                                posterPath: nil, position: -1)
        entry.addPushedAt = Date(timeIntervalSince1970: 100)
        entry.removedAt = Date(timeIntervalSince1970: 150)

        let merged = WatchlistReconciler.merge(crawled: crawled([]), into: [entry],
                                               crawledAt: Date(timeIntervalSince1970: 200))

        #expect(merged.count == 1)
        #expect(merged[0].needsRemovalPush)
    }

    /// Added by mistake and taken back before anything left the device. Letterboxd was never told,
    /// so there is nothing to push and nothing to keep.
    @Test func aLocalAddTakenBackBeforeItWasPushedIsDropped() {
        var entry = WatchlistEntry.locallyAdded(tmdbID: 1637, title: "Speed", year: 1994,
                                                posterPath: nil, position: -1)
        entry.removedAt = Date(timeIntervalSince1970: 150)

        let merged = WatchlistReconciler.merge(crawled: crawled([]), into: [entry],
                                               crawledAt: Date(timeIntervalSince1970: 200))

        #expect(merged.isEmpty)
    }
}
