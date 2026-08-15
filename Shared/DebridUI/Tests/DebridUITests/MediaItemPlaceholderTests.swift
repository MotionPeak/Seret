import Testing
import Foundation
import DebridCore
@testable import DebridUI

@Suite struct MediaItemPlaceholderTests {
    private func hit(_ id: Int, kind: MediaKind) -> SearchHit {
        SearchHit(result: TMDBSearchResult(id: id, title: kind == .movie ? "The Hunger Games" : nil,
                                           name: kind == .show ? "Game of Thrones" : nil,
                                           releaseDate: kind == .movie ? "2012-03-12" : nil,
                                           firstAirDate: kind == .show ? "2011-04-17" : nil,
                                           posterPath: "/p.jpg", overview: "o", voteAverage: 7.2),
                  kind: kind)
    }

    @Test func movieIDMatchesTheEnricherAndTheWatchKey() {
        let item = MediaItem.placeholder(for: hit(70160, kind: .movie))
        #expect(item.id == "movie:tmdb:70160")
        #expect(item.id == WatchKey.content(forMovie: item))
        #expect(item.id == DownloadKey.movie(tmdbID: 70160))
    }

    @Test func showIDMatchesTheEnricherScheme() {
        let item = MediaItem.placeholder(for: hit(1399, kind: .show))
        #expect(item.id == "show:tmdb:1399")
    }

    @Test func carriesWhatTheSearchResultKnows() {
        let item = MediaItem.placeholder(for: hit(70160, kind: .movie))
        #expect(item.title == "The Hunger Games")
        #expect(item.year == 2012)
        #expect(item.tmdbID == 70160)
        #expect(item.posterPath == "/p.jpg")
        #expect(item.overview == "o")
        #expect(item.kind == .movie)
    }

    @Test func ownsNothing() {
        let item = MediaItem.placeholder(for: hit(70160, kind: .movie))
        #expect(item.sources.isEmpty)
        #expect(item.seasons.isEmpty)
    }

    @Test func hitContentKeyMatchesThePlaceholderID() {
        let h = hit(1399, kind: .show)
        #expect(h.contentKey == MediaItem.placeholder(for: h).id)
    }
}
