import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct OpenSubtitlesAttributesTests {
        init() { MockURLProtocol.handler = nil }

        private func provider() -> OpenSubtitlesProvider {
            OpenSubtitlesProvider(apiKey: "K",
                                  credentials: .init(username: "u", password: "p"),
                                  http: HTTPClient(session: .mock))
        }

        @Test func searchDecodesTheRankingAttributes() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"data":[{"attributes":{
              "language":"he","release":"Dune.Part.Two.2024.2160p.WEB-DL.HDR.H265-FLUX",
              "download_count":48210,"new_download_count":120,"fps":23.976,
              "hearing_impaired":false,"from_trusted":true,"ai_translated":false,
              "machine_translated":false,"moviehash_match":true,
              "uploader":{"name":"wizdom","rank":"gold member"},
              "files":[{"file_id":98765,"file_name":"Dune.Part.Two.he.srt"}]}}]}
            """#)
            let results = try await provider().search(SubtitleQuery(title: "Dune"), languages: ["he"])

            let r = try #require(results.first)
            #expect(r.fileID == 98765)
            #expect(r.language == "he")
            #expect(r.downloadCount == 48210)
            #expect(r.fps == 23.976)
            #expect(r.hearingImpaired == false)
            #expect(r.trusted == true)
            #expect(r.aiTranslated == false)
            #expect(r.moviehashMatch == true)
            #expect(r.uploader == "wizdom")
        }

        @Test func missingOptionalAttributesDecodeAsNil() async throws {
            MockURLProtocol.stub(status: 200,
                json: #"{"data":[{"attributes":{"language":"en","files":[{"file_id":1}]}}]}"#)
            let r = try #require(try await provider().search(SubtitleQuery(title: "X"),
                                                            languages: ["en"]).first)
            #expect(r.fps == nil)
            #expect(r.moviehashMatch == nil)
            #expect(r.uploader == nil)
        }

        @Test func aMoviehashIsSentAsAQueryParameter() async throws {
            var seenURL: URL?
            MockURLProtocol.handler = { request in
                seenURL = request.url
                let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                               httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"data":[]}"#.utf8))
            }
            _ = try await provider().search(
                SubtitleQuery(title: "Dune", moviehash: "8e245d9679d31e12"), languages: ["he"])
            #expect(seenURL?.query?.contains("moviehash=8e245d9679d31e12") == true)
        }
    }
}
