import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct MetadataEnricherTests {
        init() { MockURLProtocol.handler = nil }

        private func movie(_ title: String, year: Int?) -> MediaItem {
            MediaItem(id: "movie:x", kind: .movie, title: title, year: year,
                      sources: [MediaSource(torrentID: "T", fileID: 1, restrictedLink: "https://rd/x",
                                            parsed: ParsedRelease(title: title))],
                      seasons: [])
        }

        private func enricher() -> MetadataEnricher {
            MetadataEnricher(tmdb: TMDBClient(apiKey: "K", http: HTTPClient(session: .mock)))
        }

        @Test func enrichesAMovieFromTMDB() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"results":[{"id":693134,"title":"Dune: Part Two","release_date":"2024-02-27",
              "poster_path":"/poster.jpg","overview":"Paul…","vote_average":8.3}]}
            """#)
            let result = try await enricher().enrich(movie("Dune Part Two", year: 2024))
            #expect(result.tmdbID == 693134)
            #expect(result.title == "Dune: Part Two")
            #expect(result.posterPath == "/poster.jpg")
            #expect(result.overview == "Paul…")
            #expect(result.id == "movie:tmdb:693134")
        }

        @Test func leavesItemUnchangedWhenNoMatch() async throws {
            MockURLProtocol.stub(status: 200, json: #"{"results":[]}"#)
            let original = movie("Totally Unknown Film", year: nil)
            let result = try await enricher().enrich(original)
            #expect(result == original)   // untouched
            #expect(result.tmdbID == nil)
        }

        @Test func enrichesAllItemsAndPreservesOrder() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"results":[{"id":1,"title":"Matched","release_date":"2020-01-01",
              "poster_path":"/p.jpg","overview":"o"}]}
            """#)
            let items = [movie("A", year: 2020), movie("B", year: 2020)]
            let result = await enricher().enrich(items)
            #expect(result.count == 2)
            #expect(result.allSatisfy { $0.tmdbID == 1 })
        }

        @Test func degradesGracefullyWhenTMDBFails() async throws {
            MockURLProtocol.stub(status: 500, json: #"{"error":"boom"}"#)
            let items = [movie("A", year: nil), movie("B", year: nil)]
            let result = await enricher().enrich(items)
            #expect(result.count == 2)
            #expect(result.allSatisfy { $0.tmdbID == nil })   // unenriched but present
            #expect(result.map(\.title) == ["A", "B"])         // order preserved
        }
    }
}
