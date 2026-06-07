import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct TMDBClientTests {
        init() { MockURLProtocol.handler = nil }

        @Test func searchesMovies() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"page":1,"results":[
              {"id":693134,"title":"Dune: Part Two","release_date":"2024-02-27",
               "poster_path":"/poster.jpg","overview":"Paul…","vote_average":8.3}],
             "total_results":1}
            """#)
            let client = TMDBClient(apiKey: "KEY", http: HTTPClient(session: .mock))
            let results = try await client.searchMovie(query: "Dune Part Two", year: 2024)
            #expect(results.count == 1)
            #expect(results[0].id == 693134)
            #expect(results[0].displayTitle == "Dune: Part Two")
            #expect(results[0].year == 2024)
        }

        @Test func discoversMoviesByGenre() async throws {
            MockURLProtocol.handler = { request in
                let url = request.url!.absoluteString
                #expect(url.contains("/discover/movie"))
                #expect(url.contains("with_genres=27"))
                #expect(url.contains("sort_by=popularity.desc"))
                let r = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (r, Data(#"{"results":[{"id":1,"title":"Split","release_date":"2017-01-20","vote_average":7.3}]}"#.utf8))
            }
            let client = TMDBClient(apiKey: "KEY", http: HTTPClient(session: .mock))
            let results = try await client.discoverMovies(genreID: 27)
            #expect(results.first?.id == 1)
        }

        @Test func fetchesNowPlaying() async throws {
            MockURLProtocol.handler = { request in
                #expect(request.url!.absoluteString.contains("/movie/now_playing"))
                let r = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (r, Data(#"{"results":[{"id":9,"title":"New","release_date":"2026-05-01","vote_average":6}]}"#.utf8))
            }
            let client = TMDBClient(apiKey: "KEY", http: HTTPClient(session: .mock))
            #expect(try await client.nowPlayingMovies().first?.id == 9)
        }

        @Test func searchesTV() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"page":1,"results":[
              {"id":110492,"name":"Shōgun","first_air_date":"2024-02-27",
               "poster_path":"/s.jpg","overview":"…","vote_average":8.7}],
             "total_results":1}
            """#)
            let client = TMDBClient(apiKey: "KEY", http: HTTPClient(session: .mock))
            let results = try await client.searchTV(query: "Shogun", firstAirYear: 2024)
            #expect(results[0].displayTitle == "Shōgun")
            #expect(results[0].year == 2024)
        }

        @Test func fetchesMovieDetails() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"id":693134,"title":"Dune: Part Two","release_date":"2024-02-27",
             "overview":"Paul…","poster_path":"/p.jpg","backdrop_path":"/b.jpg",
             "runtime":166,"vote_average":8.3,
             "genres":[{"id":878,"name":"Science Fiction"},{"id":12,"name":"Adventure"}]}
            """#)
            let client = TMDBClient(apiKey: "KEY", http: HTTPClient(session: .mock))
            let details = try await client.movieDetails(id: 693134)
            #expect(details.title == "Dune: Part Two")
            #expect(details.runtime == 166)
            #expect(details.genres.count == 2)
            #expect(details.genres[0].name == "Science Fiction")
        }

        @Test func fetchesTVDetails() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"id":110492,"name":"Shōgun","first_air_date":"2024-02-27","overview":"…",
             "poster_path":"/p.jpg","backdrop_path":"/b.jpg","number_of_seasons":1,
             "vote_average":8.7,"genres":[{"id":18,"name":"Drama"}]}
            """#)
            let client = TMDBClient(apiKey: "KEY", http: HTTPClient(session: .mock))
            let details = try await client.tvDetails(id: 110492)
            #expect(details.name == "Shōgun")
            #expect(details.numberOfSeasons == 1)
            #expect(details.genres[0].name == "Drama")
        }

        @Test func buildsPosterURL() {
            let url = TMDBClient.imageURL(path: "/abc.jpg", size: "w500")
            #expect(url?.absoluteString == "https://image.tmdb.org/t/p/w500/abc.jpg")
            #expect(TMDBClient.imageURL(path: nil) == nil)
        }

        @Test func fetchesSeasonEpisodes() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"season_number":1,"episodes":[
              {"episode_number":1,"name":"Winter Is Coming","overview":"Ned…",
               "still_path":"/s1.jpg","runtime":62,"air_date":"2011-04-17"},
              {"episode_number":2,"name":"The Kingsroad","overview":"The Lannisters…",
               "still_path":"/s2.jpg","runtime":56,"air_date":"2011-04-24"}
            ]}
            """#)
            let client = TMDBClient(apiKey: "KEY", http: HTTPClient(session: .mock))
            let season = try await client.tvSeasonDetails(tvID: 1399, season: 1)
            #expect(season.seasonNumber == 1)
            #expect(season.episodes.count == 2)
            #expect(season.episodes[0].name == "Winter Is Coming")
            #expect(season.episodes[0].runtime == 62)
            #expect(season.episodes[0].stillPath == "/s1.jpg")
            #expect(season.episodes[0].airDate == "2011-04-17")
            #expect(season.episodes[1].episodeNumber == 2)
        }
    }
}
