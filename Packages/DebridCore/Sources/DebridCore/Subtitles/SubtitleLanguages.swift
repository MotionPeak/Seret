import Foundation

public struct SubtitleLanguage: Sendable, Equatable, Identifiable, Hashable {
    public let code: String
    public let name: String
    public var id: String { code }
    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}

/// The subtitle language catalogue. Fetched from OpenSubtitles rather than hardcoded — the
/// `infos/languages` endpoint needs only an Api-Key and returns every supported language.
public enum SubtitleLanguages {

    /// A small, sane fallback if the catalogue can't be fetched, so the browser is never empty.
    public static let fallback: [SubtitleLanguage] = [
        SubtitleLanguage(code: "he", name: "Hebrew"),
        SubtitleLanguage(code: "en", name: "English"),
        SubtitleLanguage(code: "ar", name: "Arabic"),
        SubtitleLanguage(code: "es", name: "Spanish"),
        SubtitleLanguage(code: "fr", name: "French"),
        SubtitleLanguage(code: "de", name: "German"),
        SubtitleLanguage(code: "ru", name: "Russian"),
    ]

    public static func fetch(apiKey: String, http: HTTPClient = HTTPClient(),
                             userAgent: String = "Seret v1") async throws -> [SubtitleLanguage] {
        let url = OpenSubtitlesProvider.base.appending(path: "infos/languages")
        let response: OSLanguagesResponse = try await http.get(
            url, headers: ["Api-Key": apiKey, "User-Agent": userAgent])
        return response.data.compactMap {
            guard let code = $0.languageCode, let name = $0.languageName else { return nil }
            return SubtitleLanguage(code: code, name: name)
        }
    }

    /// Pinned languages first, in the order given; everything else alphabetical by name.
    public static func order(_ all: [SubtitleLanguage], pinned: [String]) -> [SubtitleLanguage] {
        let byCode = Dictionary(all.map { ($0.code, $0) }, uniquingKeysWith: { a, _ in a })
        let front = pinned.compactMap { byCode[$0] }
        let frontCodes = Set(front.map(\.code))
        let rest = all.filter { !frontCodes.contains($0.code) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return front + rest
    }
}

struct OSLanguagesResponse: Decodable {
    let data: [OSLanguage]
}

struct OSLanguage: Decodable {
    let languageCode: String?
    let languageName: String?

    enum CodingKeys: String, CodingKey {
        case languageCode = "language_code"
        case languageName = "language_name"
    }
}
