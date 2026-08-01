import Testing
import DebridCore
@testable import DebridUI

/// `DiscoverStore` is `@MainActor`, so its statics are too.
@MainActor
@Suite struct GenreTableTests {
    @Test func movieGenresAreExposedWithTMDBIDs() {
        let genres = DiscoverStore.genres(for: .movie)
        #expect(genres.count == DiscoverStore.movieGenreCount)
        #expect(genres.contains { $0.name == "Action" && $0.tmdbID == 28 })
        #expect(genres.contains { $0.name == "Sci-Fi" && $0.tmdbID == 878 })
    }

    @Test func showGenresDifferFromMovieGenres() {
        let shows = DiscoverStore.genres(for: .show)
        #expect(shows.contains { $0.name == "Action & Adventure" && $0.tmdbID == 10759 })
        // 28 is a MOVIE-only genre id; TV uses 10759. Mixing them returns empty TMDB pages.
        #expect(!shows.contains { $0.tmdbID == 28 })
    }

    @Test func genreIsIdentifiedByItsTMDBID() {
        let g = DiscoverStore.Genre(name: "Action", tmdbID: 28)
        #expect(g.id == 28)
    }
}
