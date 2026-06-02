import Testing
import Foundation
@testable import DebridCore

@Suite struct LibraryReconcilerTests {
    private func movie(torrent: String, title: String, tmdbID: Int? = nil) -> MediaItem {
        MediaItem(id: tmdbID.map { "movie:tmdb:\($0)" } ?? "movie:\(title)",
                  kind: .movie, title: title, year: 2020,
                  sources: [MediaSource(torrentID: torrent, fileID: 1, restrictedLink: "https://rd/\(torrent)",
                                        parsed: ParsedRelease(title: title))],
                  seasons: [], tmdbID: tmdbID,
                  posterPath: tmdbID == nil ? nil : "/p.jpg",
                  overview: tmdbID == nil ? nil : "o")
    }

    private let r = LibraryReconciler()

    @Test func noDeltaWhenTorrentSetsMatch() {
        let cached = [movie(torrent: "A", title: "A", tmdbID: 1)]
        #expect(r.hasDelta(cached: cached, rdTorrentIDs: ["A"]) == false)
        #expect(r.hasDelta(cached: cached, rdTorrentIDs: ["A", "B"]) == true)
        #expect(r.hasDelta(cached: [], rdTorrentIDs: []) == false)
    }

    @Test func carriesOverKnownItemsAndFlagsNewOnes() {
        let cached = [movie(torrent: "A", title: "A (TMDB)", tmdbID: 1)]      // already enriched
        let fresh  = [movie(torrent: "A", title: "A"),                        // same torrent → known
                      movie(torrent: "B", title: "B")]                        // new torrent → new
        let result = r.reconcile(fresh: fresh, cached: cached)
        #expect(result.count == 2)
        guard case .carried(let carried) = result[0] else { Issue.record("expected carried"); return }
        #expect(carried.tmdbID == 1)
        #expect(carried.title == "A (TMDB)")
        #expect(carried.id == "movie:tmdb:1")
        guard case .needsEnrichment(let fresh1) = result[1] else { Issue.record("expected needsEnrichment"); return }
        #expect(fresh1.tmdbID == nil)
        #expect(fresh1.title == "B")
    }

    @Test func unmatchedCachedItemIsNotCarried() {
        let cached = [movie(torrent: "OLD", title: "Gone", tmdbID: 9)]
        let fresh  = [movie(torrent: "NEW", title: "New")]
        let result = r.reconcile(fresh: fresh, cached: cached)
        guard case .needsEnrichment = result[0] else { Issue.record("expected needsEnrichment"); return }
    }

    @Test func knownButUnenrichedCachedItemIsTreatedAsNew() {
        let cached = [movie(torrent: "A", title: "A", tmdbID: nil)]
        let result = r.reconcile(fresh: [movie(torrent: "A", title: "A")], cached: cached)
        guard case .needsEnrichment = result[0] else { Issue.record("expected needsEnrichment"); return }
    }
}
