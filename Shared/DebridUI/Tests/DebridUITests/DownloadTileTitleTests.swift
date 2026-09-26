import Testing
import Foundation
import DebridCore
@testable import DebridUI

private struct StubLibrary: LibraryProviding {
    let items: [MediaItem]
    func loadCached() -> [MediaItem]? { items }
    func refresh() async throws -> [MediaItem] { items }
    func remove(_ item: MediaItem) async throws {}
    func removeVersion(_ item: MediaItem, source: MediaSource) async throws {}
}

private func tile(contentKey: String, tmdbID: Int, title: String = "T",
                  posterPath: String? = "/p.jpg") -> DownloadTile {
    DownloadTile(tmdbID: tmdbID, title: title, posterPath: posterPath,
                status: DownloadStatus(torrentID: "t", contentKey: contentKey, tmdbID: tmdbID,
                                       phase: .downloading, fraction: 0.4, title: title,
                                       posterPath: posterPath))
}

@MainActor
@Suite struct DownloadTileTitleTests {
    @Test func anOwnedDownloadOpensTheLibraryItem() async {
        let owned = MediaItem(id: "movie:tmdb:603", kind: .movie, title: "The Matrix", year: 1999,
                              sources: [], seasons: [], tmdbID: 603)
        let library = LibraryStore(library: StubLibrary(items: [owned]))
        await library.load()
        let dl = tile(contentKey: "movie:tmdb:603", tmdbID: 603)

        let page = dl.titleItem(in: library)

        #expect(page?.id == "movie:tmdb:603")
        #expect(page?.title == "The Matrix")
    }

    @Test func aFilmNotYetInTheLibraryOpensItsPlaceholder() async {
        let dl = tile(contentKey: "movie:tmdb:603", tmdbID: 603, title: "The Matrix",
                     posterPath: "/matrix.jpg")

        let page = dl.titleItem(in: nil)

        #expect(page?.id == "movie:tmdb:603")
        #expect(page?.kind == .movie)
        #expect(page?.title == "The Matrix")
        #expect(page?.posterPath == "/matrix.jpg")
    }

    @Test func anEpisodeKeyOpensAShowPlaceholder() async {
        let dl = tile(contentKey: "show:tmdb:1399:s1e1", tmdbID: 1399, title: "Game of Thrones")

        let page = dl.titleItem(in: nil)

        #expect(page?.id == "show:tmdb:1399")
        #expect(page?.kind == .show)
    }

    @Test func aFilmAndAShowSharingATMDBNumberAreNotConfused() async {
        let ownedFilm = MediaItem(id: "movie:tmdb:1396", kind: .movie, title: "Some Film",
                                  year: 2020, sources: [], seasons: [], tmdbID: 1396)
        let library = LibraryStore(library: StubLibrary(items: [ownedFilm]))
        await library.load()
        let dl = tile(contentKey: "show:tmdb:1396:s1e1", tmdbID: 1396, title: "Breaking Bad")

        let page = dl.titleItem(in: library)

        #expect(page?.kind == .show)
        #expect(page?.title == "Breaking Bad")
    }

    @Test func anUnidentifiedDownloadOpensNothing() async {
        let dl = tile(contentKey: "", tmdbID: 0)

        #expect(dl.titleItem(in: nil) == nil)
    }
}
