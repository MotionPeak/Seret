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
    }
}
