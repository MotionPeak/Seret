import Testing
import Foundation
@testable import DebridCore

/// A person's identity and their filmography, decoded from `/person/{id}` with
/// `combined_credits` appended.
extension MockTests {
    @Suite struct TMDBPersonTests {
        init() { MockURLProtocol.handler = nil }

        @Test func personRefIsIdentifiedByTMDBID() {
            let a = TMDBPersonRef(id: 1, name: "Denis Villeneuve")
            let b = TMDBPersonRef(id: 1, name: "Denis Villeneuve")
            #expect(a == b)
            #expect(a.id == 1)
        }

        @Test func decodesMovieAndTVCreditsAndSkipsOtherMediaTypes() throws {
            let json = #"""
            [
              {"id":693134,"media_type":"movie","title":"Dune: Part Two",
               "release_date":"2024-02-27","poster_path":"/d.jpg","vote_average":8.3,
               "popularity":142.5,"character":"Paul Atreides"},
              {"id":1399,"media_type":"tv","name":"Game of Thrones",
               "first_air_date":"2011-04-17","poster_path":"/g.jpg","vote_average":8.4,
               "popularity":90.0,"character":"Tyrion"},
              {"id":7,"media_type":"person","name":"Someone"}
            ]
            """#
            // Decoded through the lossy wrapper: `[TMDBPersonCredit]` would throw on the "person"
            // entry and lose the whole filmography.
            let credits = try JSONDecoder().decode(LossyCredits.self, from: Data(json.utf8)).values

            #expect(credits.count == 2)                       // the "person" entry is dropped
            #expect(credits[0].kind == .movie)
            #expect(credits[0].result.displayTitle == "Dune: Part Two")
            #expect(credits[0].result.year == 2024)
            #expect(credits[0].character == "Paul Atreides")
            #expect(credits[0].popularity == 142.5)
            #expect(credits[1].kind == .show)
            #expect(credits[1].result.displayTitle == "Game of Thrones")
        }

        @Test func fetchesPersonAndFilmographyInOneRequest() async throws {
            MockURLProtocol.handler = { request in
                let url = request.url!.absoluteString
                #expect(url.contains("/person/1234"))
                #expect(url.contains("append_to_response=combined_credits"))
                let r = HTTPURLResponse(url: request.url!, statusCode: 200,
                                        httpVersion: nil, headerFields: nil)!
                return (r, Data(#"""
                {"id":1234,"name":"Denis Villeneuve","profile_path":"/dv.jpg",
                 "known_for_department":"Directing",
                 "combined_credits":{
                   "cast":[{"id":1,"media_type":"movie","title":"Cameo",
                            "poster_path":"/c.jpg","popularity":1.0,"character":"Self"}],
                   "crew":[{"id":693134,"media_type":"movie","title":"Dune: Part Two",
                            "release_date":"2024-02-27","poster_path":"/d.jpg",
                            "popularity":142.5,"job":"Director"}]}}
                """#.utf8))
            }
            let client = TMDBClient(apiKey: "KEY", http: HTTPClient(session: .mock))
            let person = try await client.person(id: 1234)

            #expect(person.name == "Denis Villeneuve")
            #expect(person.profilePath == "/dv.jpg")
            #expect(person.knownForDepartment == "Directing")
            #expect(person.castCredits.count == 1)
            #expect(person.crewCredits.first?.job == "Director")
            #expect(person.crewCredits.first?.result.displayTitle == "Dune: Part Two")
        }

        @Test func movieDetailsCarriesDirectorIDsAndStillPrintsTheirNames() throws {
            let json = #"""
            {"id":693134,"title":"Dune: Part Two","genres":[],
             "credits":{"cast":[],
               "crew":[{"id":137427,"name":"Denis Villeneuve","job":"Director"},
                       {"id":137427,"name":"Denis Villeneuve","job":"Director"},
                       {"id":9,"name":"Someone Else","job":"Producer"}]}}
            """#
            let details = try JSONDecoder().decode(TMDBMovieDetails.self, from: Data(json.utf8))

            #expect(details.directors == [TMDBPersonRef(id: 137427, name: "Denis Villeneuve")])
            #expect(details.director == "Denis Villeneuve")   // still a printable string
        }

        /// TMDB lists a person once per ROLE, so an actor playing two parts comes back twice.
        /// `TMDBCastMember`'s id IS the person id and the Cast rail is a plain `ForEach(cast)`, so a
        /// duplicate meant two SwiftUI identities for one view — which on tvOS is the exact shape
        /// that leaves stale, unfocusable cells behind in a lazy container.
        @Test func movieCastIsDedupedByPerson() throws {
            let json = #"""
            {"id":693134,"title":"Dune: Part Two","genres":[],
             "credits":{"cast":[{"id":5,"name":"Twin Actor","character":"Twin A","order":0},
                                {"id":5,"name":"Twin Actor","character":"Twin B","order":1},
                                {"id":7,"name":"Other","character":"Other","order":2}],
               "crew":[]}}
            """#
            let details = try JSONDecoder().decode(TMDBMovieDetails.self, from: Data(json.utf8))

            #expect(details.cast.map(\.id) == [5, 7])
            #expect(details.cast.first?.character == "Twin A")   // the best-ordered credit survives
        }

        @Test func tvCastIsDedupedByPerson() throws {
            let json = #"""
            {"id":1399,"name":"Game of Thrones","genres":[],
             "aggregate_credits":{"cast":[
                {"id":5,"name":"A","roles":[{"character":"X"}],"order":0},
                {"id":5,"name":"A","roles":[{"character":"Y"}],"order":1},
                {"id":8,"name":"B","roles":[{"character":"Z"}],"order":2}]}}
            """#
            let details = try JSONDecoder().decode(TMDBTVDetails.self, from: Data(json.utf8))

            #expect(details.cast.map(\.id) == [5, 8])
        }

        @Test func tvDetailsCarriesCreatorIDsAndStillPrintsTheirNames() throws {
            let json = #"""
            {"id":1399,"name":"Game of Thrones","genres":[],
             "created_by":[{"id":9813,"name":"David Benioff"},
                           {"id":228068,"name":"D. B. Weiss"}]}
            """#
            let details = try JSONDecoder().decode(TMDBTVDetails.self, from: Data(json.utf8))

            #expect(details.creatorRefs.map(\.id) == [9813, 228068])
            #expect(details.creators == ["David Benioff", "D. B. Weiss"])
        }
    }
}
