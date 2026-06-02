import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct TorrentsClientAllInfosTests {
        init() { MockURLProtocol.handler = nil }

        struct StubTokens: AccessTokenProviding {
            func validAccessToken() async throws -> String { "TESTTOKEN" }
        }

        @Test func fetchesEveryTorrentsInfo() async throws {
            let listPage1 = #"""
            [{"id":"A","filename":"Movie.A.2024.mkv","hash":"h","bytes":1,"host":"rd",
              "progress":100,"status":"downloaded","added":"2024-01-01T00:00:00Z","links":["https://rd/A"]},
             {"id":"B","filename":"Movie.B.2024.mkv","hash":"h","bytes":1,"host":"rd",
              "progress":100,"status":"downloaded","added":"2024-01-01T00:00:00Z","links":["https://rd/B"]}]
            """#
            let infoA = #"{"id":"A","filename":"Movie.A","hash":"h","bytes":1,"progress":100,"status":"downloaded","files":[{"id":1,"path":"/a.mkv","bytes":1,"selected":1}],"links":["https://rd/A"]}"#
            let infoB = #"{"id":"B","filename":"Movie.B","hash":"h","bytes":1,"progress":100,"status":"downloaded","files":[{"id":1,"path":"/b.mkv","bytes":1,"selected":1}],"links":["https://rd/B"]}"#

            MockURLProtocol.handler = { request in
                let url = request.url!.absoluteString
                let json: String
                if url.contains("/torrents/info/A") { json = infoA }
                else if url.contains("/torrents/info/B") { json = infoB }
                else if url.contains("/torrents") { json = listPage1 }   // page 1 (2 < 100 → no page 2)
                else { json = "[]" }
                let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                               httpVersion: nil, headerFields: nil)!
                return (response, Data(json.utf8))
            }

            let client = TorrentsClient(http: HTTPClient(session: .mock), tokens: StubTokens())
            let infos = try await client.allTorrentInfos()
            #expect(infos.count == 2)
            #expect(Set(infos.map(\.id)) == ["A", "B"])   // order not guaranteed (concurrent)
        }

        @Test func skipsFailedInfoFetchesAndReturnsTheRest() async throws {
            let listPage1 = #"""
            [{"id":"A","filename":"Movie.A.2024.mkv","hash":"h","bytes":1,"host":"rd",
              "progress":100,"status":"downloaded","added":"2024-01-01T00:00:00Z","links":["https://rd/A"]},
             {"id":"B","filename":"Movie.B.2024.mkv","hash":"h","bytes":1,"host":"rd",
              "progress":100,"status":"downloaded","added":"2024-01-01T00:00:00Z","links":["https://rd/B"]}]
            """#
            let infoB = #"{"id":"B","filename":"Movie.B","hash":"h","bytes":1,"progress":100,"status":"downloaded","files":[{"id":1,"path":"/b.mkv","bytes":1,"selected":1}],"links":["https://rd/B"]}"#

            MockURLProtocol.handler = { request in
                let url = request.url!.absoluteString
                if url.contains("/torrents/info/A") {
                    // Simulate a server error — HTTPClient throws on non-2xx; try? turns it into nil
                    let response = HTTPURLResponse(url: request.url!, statusCode: 500,
                                                   httpVersion: nil, headerFields: nil)!
                    return (response, Data())
                } else if url.contains("/torrents/info/B") {
                    let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                                   httpVersion: nil, headerFields: nil)!
                    return (response, Data(infoB.utf8))
                } else if url.contains("/torrents") {
                    let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                                   httpVersion: nil, headerFields: nil)!
                    return (response, Data(listPage1.utf8))   // 2 items < 100 → no page 2
                } else {
                    let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                                   httpVersion: nil, headerFields: nil)!
                    return (response, Data("[]".utf8))
                }
            }

            let client = TorrentsClient(http: HTTPClient(session: .mock), tokens: StubTokens())
            let infos = try await client.allTorrentInfos()
            #expect(infos.count == 1)
            #expect(infos.map(\.id) == ["B"])
        }
    }
}
