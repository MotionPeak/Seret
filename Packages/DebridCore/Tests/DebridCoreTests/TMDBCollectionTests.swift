import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct TMDBCollectionTests {
        init() { MockURLProtocol.handler = nil }

        @Test func movieDetailsDecodeCollectionReference() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"id":70160,"title":"The Hunger Games","release_date":"2012-03-12","overview":"o",
             "poster_path":"/p.jpg","backdrop_path":"/b.jpg","runtime":142,"genres":[],
             "vote_average":7.2,"original_language":"en","imdb_id":"tt1392170",
             "belongs_to_collection":{"id":131635,"name":"The Hunger Games Collection",
                                      "poster_path":"/c.jpg","backdrop_path":"/cb.jpg"}}
            """#)
            let client = TMDBClient(apiKey: "K", http: HTTPClient(session: .mock))
            let details = try await client.movieDetails(id: 70160)
            #expect(details.collection?.id == 131635)
            #expect(details.collection?.name == "The Hunger Games Collection")
            #expect(details.collection?.posterPath == "/c.jpg")
        }

        @Test func movieDetailsToleratesNoCollection() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"id":603,"title":"The Matrix","release_date":"1999-03-30","overview":"o",
             "poster_path":null,"backdrop_path":null,"runtime":136,"genres":[],
             "vote_average":8.2,"original_language":"en","imdb_id":"tt0133093",
             "belongs_to_collection":null}
            """#)
            let client = TMDBClient(apiKey: "K", http: HTTPClient(session: .mock))
            let details = try await client.movieDetails(id: 603)
            #expect(details.collection == nil)
        }

        @Test func collectionReturnsPartsAndHitsTheRightPath() async throws {
            MockURLProtocol.handler = { request in
                #expect(request.url?.path.hasSuffix("/collection/131635") == true)
                let json = #"""
                {"id":131635,"name":"The Hunger Games Collection","overview":"o",
                 "poster_path":"/c.jpg","backdrop_path":"/cb.jpg",
                 "parts":[{"id":70160,"title":"The Hunger Games","release_date":"2012-03-12",
                           "poster_path":"/1.jpg","overview":"a","vote_average":7.2},
                          {"id":101299,"title":"Catching Fire","release_date":"2013-11-15",
                           "poster_path":"/2.jpg","overview":"b","vote_average":7.4}]}
                """#
                let r = HTTPURLResponse(url: request.url!, statusCode: 200,
                                        httpVersion: nil, headerFields: nil)!
                return (r, Data(json.utf8))
            }
            let client = TMDBClient(apiKey: "K", http: HTTPClient(session: .mock))
            let collection = try await client.collection(id: 131635)
            #expect(collection.name == "The Hunger Games Collection")
            #expect(collection.parts.count == 2)
            #expect(collection.parts.first?.displayTitle == "The Hunger Games")
        }
    }
}
