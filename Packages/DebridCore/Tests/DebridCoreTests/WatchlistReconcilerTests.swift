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
