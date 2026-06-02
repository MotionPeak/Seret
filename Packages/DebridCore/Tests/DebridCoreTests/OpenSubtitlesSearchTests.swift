import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct OpenSubtitlesSearchTests {
        init() { MockURLProtocol.handler = nil }

        private func provider() -> OpenSubtitlesProvider {
            OpenSubtitlesProvider(apiKey: "K",
                                  credentials: .init(username: "u", password: "p"),
                                  http: HTTPClient(session: .mock))
        }

        @Test func searchParsesResults() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"data":[{"attributes":{"language":"he","release":"Dune.2024","download_count":42,
              "files":[{"file_id":777,"file_name":"Dune.he.srt"}]}}]}
            """#)
            let results = try await provider().search(SubtitleQuery(tmdbID: 693134, title: "Dune"),
                                                      languages: ["he", "en"])
            #expect(results.count == 1)
            #expect(results[0].fileID == 777)
            #expect(results[0].language == "he")
            #expect(results[0].release == "Dune.2024")
            #expect(results[0].fileName == "Dune.he.srt")
            #expect(results[0].downloadCount == 42)
        }

        @Test func searchSkipsHitsWithNoFiles() async throws {
            MockURLProtocol.stub(status: 200, json: #"{"data":[{"attributes":{"language":"en","files":[]}}]}"#)
            let results = try await provider().search(SubtitleQuery(title: "x"), languages: [])
            #expect(results.isEmpty)
        }
    }
}
