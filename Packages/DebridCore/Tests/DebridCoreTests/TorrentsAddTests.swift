import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct TorrentsAddTests {
        init() { MockURLProtocol.handler = nil }

        struct StubTokens: AccessTokenProviding {
            func validAccessToken() async throws -> String { "TESTTOKEN" }
        }

        @Test func addMagnetReturnsTorrentID() async throws {
            MockURLProtocol.handler = { request in
                #expect(request.url?.path.hasSuffix("/torrents/addMagnet") == true)
                #expect(request.bodyString().contains("magnet"))
                let response = HTTPURLResponse(url: request.url!, statusCode: 201,
                                               httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"id":"NEWID","uri":"https://rd/t/NEWID"}"#.utf8))
            }
            let client = TorrentsClient(http: HTTPClient(session: .mock), tokens: StubTokens())
            let result = try await client.addMagnet(magnet: "magnet:?xt=urn:btih:abc")
            #expect(result.id == "NEWID")
        }

        @Test func selectFilesPostsAllAndSucceedsOn204() async throws {
            MockURLProtocol.handler = { request in
                #expect(request.url?.path.contains("/torrents/selectFiles/NEWID") == true)
                #expect(request.bodyString().contains("files=all"))
                let response = HTTPURLResponse(url: request.url!, statusCode: 204,
                                               httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
            let client = TorrentsClient(http: HTTPClient(session: .mock), tokens: StubTokens())
            try await client.selectFiles(torrentID: "NEWID", files: "all")
        }
    }
}
