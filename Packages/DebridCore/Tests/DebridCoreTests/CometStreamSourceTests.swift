import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct CometStreamSourceTests {
        init() { MockURLProtocol.handler = nil }

        struct StubTokens: AccessTokenProviding {
            func validAccessToken() async throws -> String { "RDTOKEN" }
        }

        func fixture(_ name: String) throws -> String {
            let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
            return try String(contentsOf: url, encoding: .utf8)
        }

        @Test func buildsCorrectMovieURLWithBase64Config() async throws {
            MockURLProtocol.handler = { request in
                let url = request.url!.absoluteString
                #expect(url.contains("/stream/movie/tt0133093.json"))
                let path = request.url!.path
                let segment = path.split(separator: "/").first.map(String.init) ?? ""
                let decoded = Data(base64Encoded: segment).map { String(decoding: $0, as: UTF8.self) } ?? ""
                #expect(decoded.contains("\"debridApiKey\":\"RDTOKEN\""))
                #expect(decoded.contains("\"cachedOnly\":true"))
                let r = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (r, Data(#"{"streams":[]}"#.utf8))
            }
            let source = CometStreamSource(http: HTTPClient(session: .mock), tokens: StubTokens())
            _ = try await source.streams(for: StreamQuery(imdbID: "tt0133093", kind: .movie, originalLanguage: "en"))
        }

        @Test func buildsSeriesIDWithSeasonEpisode() async throws {
            MockURLProtocol.handler = { request in
                #expect(request.url!.absoluteString.contains("/stream/series/tt0944947:1:2.json"))
                let r = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (r, Data(#"{"streams":[]}"#.utf8))
            }
            let source = CometStreamSource(http: HTTPClient(session: .mock), tokens: StubTokens())
            _ = try await source.streams(for: StreamQuery(imdbID: "tt0944947",
                                                          kind: .series(season: 1, episode: 2),
                                                          originalLanguage: "en"))
        }

        @Test func mapsCachedStreamsAndSkipsNonPlayback() async throws {
            let json = try fixture("comet-movie-cached")
            MockURLProtocol.stub(status: 200, json: json)
            let source = CometStreamSource(http: HTTPClient(session: .mock), tokens: StubTokens())
            let streams = try await source.streams(for: StreamQuery(imdbID: "tt0133093", kind: .movie, originalLanguage: "fr"))

            #expect(streams.count == 2)  // ⛔️ no-playback stream skipped
            let first = streams[0]
            #expect(first.infoHash == String(repeating: "a", count: 40))
            #expect(first.parsed.resolution == "2160p")
            #expect(first.parsed.source == "REMUX")   // "BluRay.REMUX" → REMUX (top tier) outranks BluRay
            #expect(first.languages == ["en", "fr"])
            #expect(first.sizeBytes == 64500000000)
            #expect(streams[1].infoHash == String(repeating: "b", count: 40))
            #expect(streams[1].languages == ["en"])
        }

        @Test func extractsInfoHashFromBingeGroup() {
            // The elfhosted instance encrypts the /playback/ URL; the infohash rides in
            // behaviorHints.bingeGroup as "comet|<service>|<40-hex>".
            let hash = String(repeating: "9c46e91d", count: 5)  // 40 hex chars
            #expect(CometStreamSource.infoHash(fromBingeGroup: "comet|realdebrid|\(hash)") == hash)
            #expect(CometStreamSource.infoHash(fromBingeGroup: "comet|torrent|\(hash.uppercased())") == hash)
            #expect(CometStreamSource.infoHash(fromBingeGroup: "comet|realdebrid") == nil)   // no hash part
            #expect(CometStreamSource.infoHash(fromBingeGroup: "comet|realdebrid|nothex") == nil)
            #expect(CometStreamSource.infoHash(fromBingeGroup: nil) == nil)
        }

        @Test func filtersOutReleasesThatDontMatchTheRequestedMovie() async throws {
            // Comet keys on IMDB id; its upstream scrapers mis-attribute same-named junk to a
            // brand-new film. Given the requested title+year, only the real release survives.
            func hash(_ c: Character) -> String { String(repeating: c, count: 40) }
            let json = #"""
            {"streams":[
              {"name":"[RD⚡] Comet 1080p","behaviorHints":{"filename":"Obsession.2026.1080p.WEB-DL.x264-GRP.mkv","bingeGroup":"comet|realdebrid|\#(hash("a"))"}},
              {"name":"[RD⚡] Comet","behaviorHints":{"filename":"Obsession.1991.DVDRip.XViD-OLD.avi","bingeGroup":"comet|realdebrid|\#(hash("b"))"}},
              {"name":"[RD⚡] Comet","behaviorHints":{"filename":"Obsession.avi","bingeGroup":"comet|realdebrid|\#(hash("c"))"}}
            ]}
            """#
            MockURLProtocol.stub(status: 200, json: json)
            let source = CometStreamSource(http: HTTPClient(session: .mock), tokens: StubTokens())
            let streams = try await source.streams(for: StreamQuery(
                imdbID: "tt9999999", kind: .movie, originalLanguage: "en",
                title: "Obsession", year: 2026))

            #expect(streams.count == 1)
            #expect(streams.first?.infoHash == hash("a"))     // only the real 2026 release
        }

        @Test func parsesFileIndexFromPlaybackURLWhenNumeric() async throws {
            let json = #"""
            {"streams":[{"name":"[RD⚡] Comet 1080p",
              "description":"📄 Show.S01E02.1080p.WEB-DL.x264-G\n🇺🇸",
              "behaviorHints":{"videoSize":900},
              "url":"https://comet.elfhosted.com/playback/cccccccccccccccccccccccccccccccccccccccc/0/3/1/2?x=1"}]}
            """#
            MockURLProtocol.stub(status: 200, json: json)
            let source = CometStreamSource(http: HTTPClient(session: .mock), tokens: StubTokens())
            let streams = try await source.streams(for: StreamQuery(imdbID: "tt1", kind: .series(season: 1, episode: 2), originalLanguage: "en"))
            #expect(streams.first?.fileIdx == 3)
        }
    }
}
