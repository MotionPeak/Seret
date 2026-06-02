import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct TorrentsClientTests {
        init() { MockURLProtocol.handler = nil }

        struct StubTokens: AccessTokenProviding {
            func validAccessToken() async throws -> String { "TESTTOKEN" }
        }

        @Test func listsTorrents() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            [{"id":"A","filename":"Movie.2024.mkv","hash":"h","bytes":10,"host":"rd",
              "progress":100,"status":"downloaded","added":"2024-01-01T00:00:00.000Z",
              "links":["https://rd/A"]}]
            """#)
            let client = TorrentsClient(http: HTTPClient(session: .mock), tokens: StubTokens())
            let torrents = try await client.torrents()
            #expect(torrents.count == 1)
            #expect(torrents[0].id == "A")
        }

        @Test func fetchesTorrentInfo() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"id":"A","filename":"Movie","hash":"h","bytes":10,"progress":100,
             "status":"downloaded",
             "files":[{"id":1,"path":"/Movie/movie.mkv","bytes":10,"selected":1}],
             "links":["https://rd/A"]}
            """#)
            let client = TorrentsClient(http: HTTPClient(session: .mock), tokens: StubTokens())
            let info = try await client.info(id: "A")
            #expect(info.files.count == 1)
            #expect(info.links == ["https://rd/A"])
        }

        @Test func realDebridSessionConformsToAccessTokenProviding() async throws {
            let store = InMemoryTokenStore()
            let t0 = Date(timeIntervalSince1970: 1_000_000)
            try store.save(StoredCredentials(
                token: RDToken(accessToken: "LIVE", refreshToken: "R", expiresIn: 3600, tokenType: "Bearer"),
                deviceCredentials: RDDeviceCredentials(clientID: "C", clientSecret: "S"),
                obtainedAt: t0))
            let session = RealDebridSession(store: store, now: { t0.addingTimeInterval(60) })
            let provider: AccessTokenProviding = session
            #expect(try await provider.validAccessToken() == "LIVE")
        }
    }
}
