import Testing
import Foundation
@testable import DebridCore

// Pure decode tests — no network, so a plain top-level suite (not under MockTests).
@Suite struct TMDBCreditsDecodeTests {
    let decoder = JSONDecoder()

    @Test func movieDetailsDecodesCastDirectorSimilar() throws {
        let json = """
        {
          "id": 27205, "title": "Inception", "genres": [],
          "credits": {
            "cast": [
              {"id": 6193, "name": "Leonardo DiCaprio", "character": "Cobb", "profile_path": "/a.jpg", "order": 0},
              {"id": 24045, "name": "Joseph Gordon-Levitt", "character": "Arthur", "profile_path": "/b.jpg", "order": 1}
            ],
            "crew": [
              {"id": 525, "name": "Christopher Nolan", "job": "Director", "department": "Directing", "profile_path": "/c.jpg"},
              {"id": 525, "name": "Christopher Nolan", "job": "Writer", "department": "Writing", "profile_path": "/c.jpg"}
            ]
          },
          "similar": { "results": [ {"id": 155, "title": "The Dark Knight", "poster_path": "/d.jpg"} ] }
        }
        """
        let d = try decoder.decode(TMDBMovieDetails.self, from: Data(json.utf8))
        #expect(d.cast.map(\.name) == ["Leonardo DiCaprio", "Joseph Gordon-Levitt"])
        #expect(d.cast.first?.character == "Cobb")
        #expect(d.director == "Christopher Nolan")           // deduped, "Director" job only
        #expect(d.similar.map(\.id) == [155])
    }

    @Test func tvDetailsDecodesAggregateCastCreatorsSimilarAndImdb() throws {
        let json = """
        {
          "id": 1399, "name": "Game of Thrones", "genres": [],
          "external_ids": {"imdb_id": "tt0944947"},
          "created_by": [ {"id": 1, "name": "David Benioff"}, {"id": 2, "name": "D. B. Weiss"} ],
          "aggregate_credits": {
            "cast": [
              {"id": 22970, "name": "Peter Dinklage", "profile_path": "/p.jpg", "order": 0,
               "roles": [ {"character": "Tyrion Lannister"} ]}
            ]
          },
          "similar": { "results": [ {"id": 1396, "name": "Breaking Bad", "poster_path": "/e.jpg"} ] }
        }
        """
        let d = try decoder.decode(TMDBTVDetails.self, from: Data(json.utf8))
        #expect(d.imdbID == "tt0944947")                     // regression: external_ids still works
        #expect(d.cast.first?.name == "Peter Dinklage")
        #expect(d.cast.first?.character == "Tyrion Lannister")  // from roles.first.character
        #expect(d.creators == ["David Benioff", "D. B. Weiss"])
        #expect(d.similar.map(\.id) == [1396])
    }

    @Test func detailsTolerateMissingCreditsAndSimilar() throws {
        let movie = try decoder.decode(TMDBMovieDetails.self,
            from: Data(#"{"id":1,"title":"X","genres":[]}"#.utf8))
        #expect(movie.cast.isEmpty)
        #expect(movie.director == nil)
        #expect(movie.similar.isEmpty)
        let tv = try decoder.decode(TMDBTVDetails.self,
            from: Data(#"{"id":2,"name":"Y","genres":[]}"#.utf8))
        #expect(tv.cast.isEmpty)
        #expect(tv.creators.isEmpty)
        #expect(tv.similar.isEmpty)
    }
}
