import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct TorrentioStreamSourceTests {
        init() { MockURLProtocol.handler = nil }

        private func hash(_ c: Character) -> String { String(repeating: c, count: 40) }

        private func movieQuery() -> StreamQuery {
            StreamQuery(imdbID: "tt37287335", kind: .movie, originalLanguage: "en",
                        title: "Obsession", year: 2026)
        }

        @Test func buildsMovieURL() async throws {
            MockURLProtocol.handler = { req in
                #expect(req.url!.absoluteString.hasSuffix("/stream/movie/tt37287335.json"))
                let r = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (r, Data(#"{"streams":[]}"#.utf8))
            }
            let src = TorrentioStreamSource(http: HTTPClient(session: .mock))
            _ = try await src.streams(for: movieQuery(), includeUncached: true)
        }

        @Test func buildsSeriesURLWithSeasonEpisode() async throws {
            MockURLProtocol.handler = { req in
                #expect(req.url!.absoluteString.hasSuffix("/stream/series/tt1:2:3.json"))
                let r = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (r, Data(#"{"streams":[]}"#.utf8))
            }
            let src = TorrentioStreamSource(http: HTTPClient(session: .mock))
            _ = try await src.streams(for: StreamQuery(imdbID: "tt1", kind: .series(season: 2, episode: 3),
                                                       originalLanguage: "en", title: "Show", year: nil),
                                      includeUncached: true)
        }

        @Test func cachedOnlyPathReturnsNothing() async throws {
            // Torrentio can't confirm RD-instant availability, so it stays out of the Play path.
            MockURLProtocol.stub(status: 200, json: #"{"streams":[]}"#)
            let src = TorrentioStreamSource(http: HTTPClient(session: .mock))
            #expect(try await src.streams(for: movieQuery()).isEmpty)
        }

        @Test func mapsRealReleasesGatesJunkAndParsesSize() async throws {
            let json = #"""
            {"streams":[
              {"name":"Torrentio\nTeleSync","title":"Obsession.2026.1080p.TELESYNC.x264-UNiON\n👤 5446 💾 5.34 GB ⚙️ ThePirateBay","infoHash":"\#(hash("a"))","fileIdx":0,"behaviorHints":{"filename":"Obsession.2026.1080p.TELESYNC.x264-UNiON.mkv"}},
              {"name":"Torrentio","title":"Obsession.S01.1080p.x264\n👤 5 💾 5.9 GB","infoHash":"\#(hash("b"))","behaviorHints":{"filename":"Obsession.S01.1080p.x264.mkv"}},
              {"name":"Torrentio","title":"Obsession.1991.720p.BluRay\n👤 2 💾 1.1 GB","infoHash":"\#(hash("c"))","behaviorHints":{"filename":"Obsession.1991.720p.BluRay.mkv"}}
            ]}
            """#
            MockURLProtocol.stub(status: 200, json: json)
            let src = TorrentioStreamSource(http: HTTPClient(session: .mock))
            let streams = try await src.streams(for: movieQuery(), includeUncached: true)

            #expect(streams.count == 1)                       // series + 1991 gated out
            let s = streams[0]
            #expect(s.infoHash == hash("a"))
            #expect(s.isCached == false)                      // Torrentio = uncached
            #expect(s.parsed.resolution == "1080p")
            #expect(s.sizeBytes == 5_340_000_000)             // parsed "💾 5.34 GB"
            #expect(s.fileIdx == 0)
        }
    }
}
