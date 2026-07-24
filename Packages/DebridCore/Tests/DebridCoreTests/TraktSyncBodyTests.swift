import Testing
import Foundation
@testable import DebridCore

/// Exact-shape tests for the /sync/{history,ratings} body.
///
/// A previous version wrapped each entry in its own `{"movie": …}` object, producing
/// `{"movies":[{"movie":{…}}]}`. Trakt silently accepted the request and recorded nothing, and a
/// substring-only assertion ("does the body contain \"movies\" and the tmdb id?") passed anyway.
/// These tests compare the whole decoded structure so the nesting itself is pinned down.
@Suite struct TraktSyncBodyTests {
    private func json(_ refs: [TraktMediaRef], rating: Int? = nil) throws -> [String: Any] {
        let body = TraktClient.groupedBody(refs, rating: rating)
        let data = try JSONEncoder().encode(body)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    @Test func movieIsFlatNotWrapped() throws {
        let obj = try json([.movie(tmdb: 1417)], rating: 9)
        let movies = obj["movies"] as! [[String: Any]]
        #expect(movies.count == 1)
        // The entry IS the movie — no intermediate "movie" key.
        #expect(movies[0]["movie"] == nil)
        #expect((movies[0]["ids"] as! [String: Any])["tmdb"] as! Int == 1417)
        #expect(movies[0]["rating"] as! Int == 9)
        #expect((obj["shows"] as! [[String: Any]]).isEmpty)
    }

    @Test func movieWithoutRatingOmitsTheField() throws {
        let obj = try json([.movie(tmdb: 1417)])
        let movies = obj["movies"] as! [[String: Any]]
        #expect(movies[0]["rating"] == nil)
    }

    @Test func episodeNestsUnderShowSeasonEpisode() throws {
        let obj = try json([.episode(showTmdb: 1399, season: 2, number: 5)], rating: 8)
        #expect((obj["movies"] as! [[String: Any]]).isEmpty)
        let shows = obj["shows"] as! [[String: Any]]
        #expect(shows.count == 1)
        #expect((shows[0]["ids"] as! [String: Any])["tmdb"] as! Int == 1399)
        let seasons = shows[0]["seasons"] as! [[String: Any]]
        #expect(seasons.count == 1)
        #expect(seasons[0]["number"] as! Int == 2)
        let eps = seasons[0]["episodes"] as! [[String: Any]]
        #expect(eps.count == 1)
        #expect(eps[0]["number"] as! Int == 5)
        #expect(eps[0]["rating"] as! Int == 8)
    }

    @Test func episodesOfOneShowCollapseIntoOneEntry() throws {
        let obj = try json([
            .episode(showTmdb: 1399, season: 1, number: 1),
            .episode(showTmdb: 1399, season: 1, number: 2),
            .episode(showTmdb: 1399, season: 2, number: 1),
            .episode(showTmdb: 9999, season: 1, number: 1)
        ])
        let shows = obj["shows"] as! [[String: Any]]
        #expect(shows.count == 2)                         // one entry per show, not per episode
        let got = shows[0]["seasons"] as! [[String: Any]]
        #expect(got.count == 2)                           // two seasons under the first show
        #expect((got[0]["episodes"] as! [[String: Any]]).count == 2)
        #expect((got[1]["episodes"] as! [[String: Any]]).count == 1)
    }

    @Test func showLevelRatingIsFlatWithNoSeasons() throws {
        let obj = try json([.show(tmdb: 1399)], rating: 10)
        let shows = obj["shows"] as! [[String: Any]]
        #expect(shows.count == 1)
        #expect((shows[0]["ids"] as! [String: Any])["tmdb"] as! Int == 1399)
        #expect(shows[0]["rating"] as! Int == 10)
        #expect(shows[0]["seasons"] == nil)      // whole-series entry carries no seasons
    }

    @Test func episodeEntryCarriesNoShowLevelRating() throws {
        let obj = try json([.episode(showTmdb: 1399, season: 1, number: 1)], rating: 7)
        let shows = obj["shows"] as! [[String: Any]]
        #expect(shows[0]["rating"] == nil)       // the rating belongs to the episode, not the show
        let eps = (shows[0]["seasons"] as! [[String: Any]])[0]["episodes"] as! [[String: Any]]
        #expect(eps[0]["rating"] as! Int == 7)
    }

    @Test func mixedMoviesAndEpisodesSplitCorrectly() throws {
        let obj = try json([.movie(tmdb: 1), .episode(showTmdb: 2, season: 1, number: 1), .movie(tmdb: 3)])
        #expect((obj["movies"] as! [[String: Any]]).count == 2)
        #expect((obj["shows"] as! [[String: Any]]).count == 1)
    }
}
