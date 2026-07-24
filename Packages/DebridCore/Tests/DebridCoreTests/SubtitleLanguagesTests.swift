import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct SubtitleLanguagesTests {
        init() { MockURLProtocol.handler = nil }

        @Test func pinnedLanguagesComeFirstInOrder() {
            let all = [SubtitleLanguage(code: "ar", name: "Arabic"),
                       SubtitleLanguage(code: "en", name: "English"),
                       SubtitleLanguage(code: "he", name: "Hebrew"),
                       SubtitleLanguage(code: "zh", name: "Chinese")]
            let ordered = SubtitleLanguages.order(all, pinned: ["he", "en"])
            #expect(ordered.prefix(2).map(\.code) == ["he", "en"])
        }

        @Test func theRestAreAlphabeticalByName() {
            let all = [SubtitleLanguage(code: "zh", name: "Chinese"),
                       SubtitleLanguage(code: "ar", name: "Arabic"),
                       SubtitleLanguage(code: "he", name: "Hebrew")]
            let ordered = SubtitleLanguages.order(all, pinned: ["he"])
            #expect(ordered.map(\.code) == ["he", "ar", "zh"])
        }

        @Test func aPinnedCodeThatDoesNotExistIsIgnored() {
            let all = [SubtitleLanguage(code: "en", name: "English")]
            #expect(SubtitleLanguages.order(all, pinned: ["he", "en"]).map(\.code) == ["en"])
        }

        @Test func theCatalogueDecodesTheLanguagesEndpoint() async throws {
            MockURLProtocol.stub(status: 200, json:
                #"{"data":[{"language_code":"he","language_name":"Hebrew"},{"language_code":"en","language_name":"English"}]}"#)
            let languages = try await SubtitleLanguages.fetch(
                apiKey: "k", http: HTTPClient(session: .mock))
            #expect(languages.count == 2)
            #expect(languages.contains(SubtitleLanguage(code: "he", name: "Hebrew")))
        }
    }
}
