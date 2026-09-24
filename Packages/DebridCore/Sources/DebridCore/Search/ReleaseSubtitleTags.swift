import Foundation

/// The subtitle languages a release NAME declares: "HebSubs", "Heb.Sub", "Sub.Heb", "מתורגם".
///
/// Kept apart from `LanguageDetector`, which reads AUDIO languages. Before this existed,
/// "Movie.2023.1080p.Heb.Sub" was read as Hebrew audio, and an English film's ranking sank it as a
/// foreign dub, the one release a Hebrew-reading household wants first.
///
/// Dub tags ("HebDub", "Heb.Dub", "Hebrew.Dubbed") are audio and are deliberately not matched.
public struct ReleaseSubtitleTags: Sendable {
    public struct Scan: Sendable, Equatable {
        /// ISO 639-1, in the order they appear in the text.
        public let languages: [String]
        /// The text with every subtitle tag blanked out — what the audio detector should read.
        public let remainder: String
    }

    public init() {}

    public func scan(_ text: String) -> Scan {
        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)
        var found: [(offset: Int, code: String)] = []
        var blanked: [NSRange] = []
        for (regex, group) in Self.patterns {
            for match in regex.matches(in: text, range: whole) {
                let token = ns.substring(with: match.range(at: group)).lowercased()
                guard let code = Self.languageTokens[token] else { continue }
                found.append((match.range.location, code))
                blanked.append(match.range)
            }
        }
        for match in Self.hebrewScript.matches(in: text, range: whole) {
            found.append((match.range.location, "he"))
            blanked.append(match.range)
        }
        // Blanked with spaces of the same length, so every other range stays valid.
        let remainder = NSMutableString(string: text)
        for range in blanked {
            remainder.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
        }
        var languages: [String] = []
        for item in found.sorted(by: { $0.offset < $1.offset }) where !languages.contains(item.code) {
            languages.append(item.code)
        }
        return Scan(languages: languages, remainder: remainder as String)
    }

    /// Language tokens a subtitle tag may carry. Only Hebrew is acted on; the rest are reported so
    /// the audio detector stops mistaking them for audio too.
    private static let languageTokens: [String: String] = [
        "heb": "he", "hebrew": "he",
        "eng": "en", "english": "en",
        "ara": "ar", "arabic": "ar",
        "rus": "ru", "russian": "ru",
        "fre": "fr", "french": "fr",
        "ger": "de", "german": "de",
        "spa": "es", "spanish": "es",
        "ita": "it", "italian": "it",
    ]

    private static let tokens = "heb|hebrew|eng|english|ara|arabic|rus|russian|fre|french|ger|german|spa|spanish|ita|italian"
    private static let subtitleWords = "subs?|subbed|subtitles?|subtitled"

    /// Each pattern with the capture group that holds the language token. Letters may not touch
    /// either end, so "Subway" and "The.Hebrews" stay out.
    private static let patterns: [(NSRegularExpression, Int)] = [
        // Language first: HebSub, HebSubs, Heb.Sub, Hebrew-Subs, "Hebrew Subtitles", HebSubbed.
        (try! NSRegularExpression(
            pattern: "(?<![A-Za-z])(\(tokens))[ ._-]?(?:\(subtitleWords))(?![A-Za-z])",
            options: [.caseInsensitive]), 1),
        // Subtitles first: Sub.Heb, Subs-Hebrew.
        (try! NSRegularExpression(
            pattern: "(?<![A-Za-z])(?:\(subtitleWords))[ ._-]?(\(tokens))(?![A-Za-z])",
            options: [.caseInsensitive]), 1),
    ]

    /// Hebrew-script words for "subtitled" and "subtitles", as Israeli release names write them.
    private static let hebrewScript = try! NSRegularExpression(pattern: "מתורגם|כתוביות|תרגום מובנה")
}
