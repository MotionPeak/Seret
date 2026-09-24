import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct OpenSubtitlesSearchOnlyTests {
        init() { MockURLProtocol.handler = nil }

        private func provider() -> OpenSubtitlesProvider {
            OpenSubtitlesProvider(apiKey: "K", credentials: nil, http: HTTPClient(session: .mock),
                                  cacheDirectory: FileManager.default.temporaryDirectory
                                      .appending(path: "os-search-only-\(UUID().uuidString)"))
        }

        @Test func searchesWithoutAnAccount() async throws {
            MockURLProtocol.stub(status: 200, json: #"{"data":[{"attributes":{"language":"he","release":"Dune.2024","files":[{"file_id":7}]}}]}"#)
            let results = try await provider().search(SubtitleQuery(tmdbID: 1, title: "Dune"), languages: ["he"])
            #expect(results.map(\.fileID) == [7])
        }

        @Test func cannotDownloadWithoutAnAccount() async {
            await #expect(throws: SubtitleError.notAuthenticated) {
                _ = try await provider().download(SubtitleResult(fileID: 7, language: "he"))
            }
        }
    }
}
