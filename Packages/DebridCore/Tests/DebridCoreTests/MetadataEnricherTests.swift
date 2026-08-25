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

        @Test func leavesItemUnchangedWhenTopResultIsADifferentTitle() async throws {
            // A junk torrent's parsed title is unrelated to TMDB's most-popular hit. Stamping that
            // hit's poster/plot would mislabel the file (the "looks-right-plays-wrong" symptom);
            // leave it unenriched instead of blindly taking results.first.
            MockURLProtocol.stub(status: 200, json: #"""
            {"results":[{"id":999,"title":"Obsession","release_date":"2026-01-01","poster_path":"/o.jpg","overview":"Horror."}]}
            """#)
            let original = movie("Totally Unrelated Junk", year: nil)
            let result = try await enricher().enrich(original)
            #expect(result == original)     // untouched
            #expect(result.tmdbID == nil)
        }

        @Test func enrichesAllItemsAndPreservesOrder() async {
            MockURLProtocol.handler = { request in
                let url = request.url!.absoluteString
                let json: String
                if url.contains("query=Alpha") {
                    json = #"{"results":[{"id":11,"title":"Alpha Movie","release_date":"2020-05-01","poster_path":"/a.jpg","overview":"alpha"}]}"#
                } else if url.contains("query=Beta") {
                    json = #"{"results":[{"id":22,"title":"Beta Movie","release_date":"2020-08-01","poster_path":"/b.jpg","overview":"beta"}]}"#
                } else {
                    json = #"{"results":[]}"#
                }
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(json.utf8))
            }
            let items = [movie("Alpha", year: 2020), movie("Beta", year: 2020)]
            let result = await enricher().enrich(items)
            #expect(result.count == 2)
            #expect(result.map(\.tmdbID) == [11, 22])
        }

        @Test func keepsParsedTitleWhenTMDBTitleIsBlank() async throws {
            // Stub a TMDB hit that has id/poster/overview but no title or name field,
            // so displayTitle produces "". The parsed title must be preserved.
            MockURLProtocol.stub(status: 200, json: #"""
            {"results":[{"id":555,"poster_path":"/p.jpg","overview":"A mystery film."}]}
            """#)
            let result = try await enricher().enrich(movie("My Parsed Title", year: 2021))
            #expect(result.title == "My Parsed Title")   // parsed title PRESERVED
            #expect(result.tmdbID == 555)                // still matched
            #expect(result.posterPath == "/p.jpg")       // artwork applied
            #expect(result.id == "movie:tmdb:555")       // id rekeyed
        }

        @Test func degradesGracefullyWhenTMDBFails() async {
            MockURLProtocol.stub(status: 500, json: #"{"error":"boom"}"#)
            let items = [movie("A", year: nil), movie("B", year: nil)]
            let result = await enricher().enrich(items)
            #expect(result.count == 2)
            #expect(result.allSatisfy { $0.tmdbID == nil })   // unenriched but present
            #expect(result.map(\.title) == ["A", "B"])         // order preserved
        }

        /// Two torrents of one film are two items here, and they merge into a single title once
        /// enriched — so they ask TMDB exactly the same question. Asking it twice wastes a request
        /// on the one load where every title is new at once and the fan-out is already the slowest
        /// thing the app does.
        @Test func twoCopiesOfOneFilmAreLookedUpOnce() async throws {
            let searches = SearchCounter()
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/search/movie") { searches.bump() }
                let json = #"{"results":[{"id":11,"title":"Dune","release_date":"2021-01-01","poster_path":"/p.jpg","overview":"o"}]}"#
                return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil,
                                        headerFields: nil)!, Data(json.utf8))
            }
            let enricher = MetadataEnricher(tmdb: TMDBClient(apiKey: "K", http: HTTPClient(session: .mock)))
            let hd = MediaItem(id: "movie:dune:2021", kind: .movie, title: "Dune", year: 2021,
                               sources: [], seasons: [])
            let uhd = MediaItem(id: "movie:dune:2021b", kind: .movie, title: "Dune", year: 2021,
                                sources: [], seasons: [])

            let out = await enricher.enrich([hd, uhd])

            #expect(searches.value == 1)
            #expect(out.count == 2)
            #expect(out.allSatisfy { $0.tmdbID == 11 })      // both got the answer
        }

        /// …and DIFFERENT titles are still asked about separately.
        @Test func differentTitlesAreStillLookedUpSeparately() async throws {
            let searches = SearchCounter()
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/search/movie") { searches.bump() }
                return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil,
                                        headerFields: nil)!, Data(#"{"results":[]}"#.utf8))
            }
            let enricher = MetadataEnricher(tmdb: TMDBClient(apiKey: "K", http: HTTPClient(session: .mock)))
            let a = MediaItem(id: "a", kind: .movie, title: "Dune", year: 2021, sources: [], seasons: [])
            let b = MediaItem(id: "b", kind: .movie, title: "Arrival", year: 2016, sources: [], seasons: [])
            // Same title, different YEAR is also a different question.
            let c = MediaItem(id: "c", kind: .movie, title: "Dune", year: 1984, sources: [], seasons: [])

            _ = await enricher.enrich([a, b, c])

            #expect(searches.value == 3)
        }
    }
}

/// Thread-safe counter for the @Sendable mock handler.
private final class SearchCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func bump() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
