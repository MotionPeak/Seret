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
        func tags(_ regex: NSRegularExpression) -> [(range: NSRange, token: NSRange, code: String)] {
            regex.matches(in: text, range: whole).compactMap { match in
                let token = match.range(at: 1)
                return Self.languageTokens[ns.substring(with: token).lowercased()].map { (match.range, token, $0) }
            }
        }
        let languageFirst = tags(Self.languageFirst)
        // "Sub.X" names X's subtitles unless X carries a "Sub" of its own ("Heb.Sub.Eng.Sub").
        let subtitlesFirst = tags(Self.subtitlesFirst).filter { tag in
            !languageFirst.contains { $0.range.location == tag.token.location }
        }
        // Where the two readings share one "Sub" — "ITA.ENG.Sub.ITA" — the language after it names
        // the subtitles, and the one before is audio. Italian releases list audio, then subtitles.
        // Hebrew is exempt: a Hebrew "Sub" tag is always subtitles, since Hebrew dubs say "Dub".
        let kept = languageFirst.filter { tag in
            tag.code == "he" || !subtitlesFirst.contains { NSIntersectionRange($0.range, tag.range).length > 0 }
        } + subtitlesFirst
        var found = kept.map { (offset: $0.range.location, code: $0.code) }
        var blanked = kept.map(\.range)
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

    /// Capture group 1 holds the language token. Letters may not touch either end, so "Subway"
    /// and "The.Hebrews" stay out.
    /// Language first: HebSub, HebSubs, Heb.Sub, Hebrew-Subs, "Hebrew Subtitles", HebSubbed.
    private static let languageFirst = try! NSRegularExpression(
        pattern: "(?<![A-Za-z])(\(tokens))[ ._-]?(?:\(subtitleWords))(?![A-Za-z])",
        options: [.caseInsensitive])
    /// Subtitles first: Sub.Heb, Subs-Hebrew.
    private static let subtitlesFirst = try! NSRegularExpression(
        pattern: "(?<![A-Za-z])(?:\(subtitleWords))[ ._-]?(\(tokens))(?![A-Za-z])",
        options: [.caseInsensitive])

    /// Hebrew-script words for "subtitled" and "subtitles", as Israeli release names write them.
    private static let hebrewScript = try! NSRegularExpression(pattern: "מתורגם|כתוביות|תרגום מובנה")
}
