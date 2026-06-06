import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct TMDBDetailsLanguageTests {
        init() { MockURLProtocol.handler = nil }

        @Test func movieDetailsDecodeOriginalLanguageAndImdbID() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"id":603,"title":"The Matrix","release_date":"1999-03-30","overview":"o",
             "poster_path":"/p.jpg","backdrop_path":"/b.jpg","runtime":136,"genres":[],
             "vote_average":8.2,"original_language":"en","imdb_id":"tt0133093"}
            """#)
            let client = TMDBClient(apiKey: "K", http: HTTPClient(session: .mock))
            let details = try await client.movieDetails(id: 603)
            #expect(details.originalLanguage == "en")
            #expect(details.imdbID == "tt0133093")
        }

        @Test func tvDetailsDecodeOriginalLanguageAndExternalImdbID() async throws {
            MockURLProtocol.handler = { request in
                #expect(request.url?.query?.contains("append_to_response=external_ids") == true)
                let json = #"""
                {"id":1399,"name":"Game of Thrones","first_air_date":"2011-04-17","overview":"o",
                 "poster_path":"/p.jpg","backdrop_path":"/b.jpg","number_of_seasons":8,"genres":[],
                 "vote_average":8.4,"original_language":"en",
                 "external_ids":{"imdb_id":"tt0944947"}}
                """#
                let r = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (r, Data(json.utf8))
            }
            let client = TMDBClient(apiKey: "K", http: HTTPClient(session: .mock))
            let details = try await client.tvDetails(id: 1399)
            #expect(details.originalLanguage == "en")
            #expect(details.imdbID == "tt0944947")
        }

        @Test func tvDetailsToleratesMissingExternalIDs() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"id":1,"name":"X","first_air_date":null,"overview":null,"poster_path":null,
             "backdrop_path":null,"number_of_seasons":null,"genres":[],"vote_average":null,
             "original_language":"ja"}
            """#)
            let client = TMDBClient(apiKey: "K", http: HTTPClient(session: .mock))
            let details = try await client.tvDetails(id: 1)
            #expect(details.originalLanguage == "ja")
            #expect(details.imdbID == nil)
        }
    }
}
