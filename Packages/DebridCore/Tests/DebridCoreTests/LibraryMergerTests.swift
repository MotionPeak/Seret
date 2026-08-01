import Foundation
import Testing
@testable import DebridCore

struct LibraryMergerTests {
    let merger = LibraryMerger()

    private func source(_ torrent: String, file: Int? = nil, resolution: String? = nil) -> MediaSource {
        MediaSource(torrentID: torrent, fileID: file, restrictedLink: "https://rd/\(torrent)",
                    parsed: ParsedRelease(title: "The Odyssey", year: 2026, resolution: resolution))
    }

    private func movie(_ id: String, sources: [MediaSource], tmdbID: Int? = nil,
                       poster: String? = nil, overview: String? = nil,
                       year: Int? = 2026, added: Date? = nil) -> MediaItem {
        MediaItem(id: id, kind: .movie, title: "The Odyssey", year: year, sources: sources,
                  seasons: [], tmdbID: tmdbID, posterPath: poster, overview: overview, addedAt: added)
    }

    private func episode(_ season: Int, _ number: Int, torrent: String) -> Episode {
        Episode(season: season, number: number, source: source(torrent))
    }

    @Test func collapsesDuplicateIDsIntoOneItemHoldingEveryVersion() {
        let merged = merger.merge([
            movie("movie:tmdb:1", sources: [source("A", resolution: "1080p")]),
            movie("movie:tmdb:1", sources: [source("B", resolution: "2160p")]),
            movie("movie:tmdb:1", sources: [source("C")]),
        ])
        #expect(merged.count == 1)
        #expect(merged[0].sources.map(\.torrentID) == ["A", "B", "C"])
    }

    @Test func keepsDistinctItemsAndTheirOriginalOrder() {
        let merged = merger.merge([
            movie("movie:tmdb:2", sources: [source("A")]),
            movie("movie:tmdb:1", sources: [source("B")]),
            movie("movie:tmdb:2", sources: [source("C")]),
            movie("movie:tmdb:3", sources: [source("D")]),
        ])
        #expect(merged.map(\.id) == ["movie:tmdb:2", "movie:tmdb:1", "movie:tmdb:3"])
        #expect(merged[0].sources.map(\.torrentID) == ["A", "C"])
    }

    @Test func dropsVersionsBackedByTheSameRDFile() {
        let merged = merger.merge([
            movie("movie:tmdb:1", sources: [source("A", file: 3)]),
            movie("movie:tmdb:1", sources: [source("A", file: 3), source("A", file: 4)]),
        ])
        #expect(merged[0].sources.count == 2)
        #expect(merged[0].sources.map(\.fileID) == [3, 4])
    }

    /// One duplicate can have failed its TMDB lookup — the merged item must still carry whatever
    /// artwork and ids any copy managed to resolve.
    @Test func fillsMissingMetadataFromTheOtherCopy() {
        let merged = merger.merge([
            movie("movie:tmdb:1", sources: [source("A")], tmdbID: nil, poster: nil, overview: nil,
                  year: nil),
            movie("movie:tmdb:1", sources: [source("B")], tmdbID: 1, poster: "/p.jpg",
                  overview: "Odysseus sails.", year: 2026),
        ])
        #expect(merged[0].tmdbID == 1)
        #expect(merged[0].posterPath == "/p.jpg")
        #expect(merged[0].overview == "Odysseus sails.")
        #expect(merged[0].year == 2026)
    }

    @Test func takesTheNewestAddedDateSoRecentlyAddedReflectsTheLatestVersion() {
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 9_000)
        #expect(merger.merge([
            movie("movie:tmdb:1", sources: [source("A")], added: old),
            movie("movie:tmdb:1", sources: [source("B")], added: new),
        ])[0].addedAt == new)
        // …and the other way round: order must not decide it.
        #expect(merger.merge([
            movie("movie:tmdb:1", sources: [source("A")], added: new),
            movie("movie:tmdb:1", sources: [source("B")], added: old),
        ])[0].addedAt == new)
    }

    @Test func unionsSeasonsAndEpisodesOfADuplicatedShow() {
        let a = MediaItem(id: "show:tmdb:9", kind: .show, title: "Show", year: 2020, sources: [],
                          seasons: [Season(number: 1, episodes: [episode(1, 1, torrent: "A"),
                                                                 episode(1, 2, torrent: "A")])])
        let b = MediaItem(id: "show:tmdb:9", kind: .show, title: "Show", year: 2020, sources: [],
                          seasons: [Season(number: 1, episodes: [episode(1, 2, torrent: "Z")]),
                                    Season(number: 2, episodes: [episode(2, 1, torrent: "B")])])
        let merged = merger.merge([a, b])
        #expect(merged.count == 1)
        #expect(merged[0].seasons.map(\.number) == [1, 2])
        #expect(merged[0].seasons[0].episodes.map(\.number) == [1, 2])
        // The first-seen source wins for an episode both copies carry (LibraryBuilder's rule).
        #expect(merged[0].seasons[0].episodes[1].source.torrentID == "A")
        #expect(merged[0].seasons[1].episodes.map(\.number) == [1])
    }

    @Test func leavesAnAlreadyUniqueLibraryUntouched() {
        let items = [movie("movie:tmdb:1", sources: [source("A")]),
                     movie("movie:tmdb:2", sources: [source("B")])]
        #expect(merger.merge(items) == items)
    }
}
