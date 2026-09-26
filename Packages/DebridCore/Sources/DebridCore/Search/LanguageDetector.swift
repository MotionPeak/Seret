import Foundation

/// Extracts audio-language ISO 639-1 codes from a stream title.
/// Recognizes regional-indicator flag emoji (mapped country→primary language) and
/// common English language words. Flags are read first (left→right); words are then
/// added in their order of appearance in the text. Duplicates removed.
/// Subtitle tags ("Heb.Sub") are not audio — see `ReleaseSubtitleTags`.
public struct LanguageDetector: Sendable {
    public init() {}

    public func detect(in text: String) -> [String] {
        // Subtitle tags come out first. "Heb.Sub" names the SUBTITLES; read as audio, it sank the
        // very releases a Hebrew-reading viewer wants, as if an English film were a Hebrew dub.
        let tags = ReleaseSubtitleTags().scan(text)
        var flags = Self.flagLanguages(in: text)
        let words = Self.wordLanguages(in: tags.remainder)
        // An addon's flag is its guess from the same name. When the name mentions a language only
        // as subtitles, the flag is the subtitles talking, not the audio.
        for code in tags.languages where !words.contains(code) {
            flags.removeAll { $0 == code }
        }
        var result: [String] = []
        for code in flags + words where !result.contains(code) { result.append(code) }
        return result
    }

    /// Flag emoji, left to right: consecutive regional-indicator pairs → country → language.
    private static func flagLanguages(in text: String) -> [String] {
        var result: [String] = []
        let scalars = Array(text.unicodeScalars)
        var i = 0
        while i < scalars.count {
            if let c0 = regionalLetter(scalars[i]), i + 1 < scalars.count,
               let c1 = regionalLetter(scalars[i + 1]) {
                if let lang = countryToLanguage[String([c0, c1])], !result.contains(lang) {
                    result.append(lang)
                }
                i += 2
            } else {
                i += 1
            }
        }
        return result
    }

    /// Whole-word language names and scene abbreviations, in order of appearance.
    private static func wordLanguages(in text: String) -> [String] {
        let lowered = text.lowercased()
        var matches: [(offset: Int, code: String)] = []
        // Full language names AND 3-letter scene abbreviations ("ITA"/"GER"/"ENG"/"FRE"…).
        // Release names use the abbreviations far more than full words, so without these a
        // dual-audio dub like "Ger.Eng.Dubbed" reads as having no languages and slips past
        // the original-language ranking.
        for (word, code) in wordToLanguage.merging(abbrevToLanguage, uniquingKeysWith: { a, _ in a }) {
            if let range = rangeOfWord(word, in: lowered) {
                matches.append((lowered.distance(from: lowered.startIndex, to: range.lowerBound), code))
            }
        }
        var result: [String] = []
        for match in matches.sorted(by: { $0.offset < $1.offset }) where !result.contains(match.code) {
            result.append(match.code)
        }
        return result
    }

    private static func regionalLetter(_ s: Unicode.Scalar) -> Character? {
        guard s.value >= 0x1F1E6 && s.value <= 0x1F1FF else { return nil }
        return Character(Unicode.Scalar(s.value - 0x1F1E6 + 0x41)!) // 'A'...'Z'
    }

    /// The range of `word` in `lowered` if it appears as a whole word (non-letter boundaries).
    private static func rangeOfWord(_ word: String, in lowered: String) -> Range<String.Index>? {
        guard let range = lowered.range(of: word) else { return nil }
        let before = range.lowerBound == lowered.startIndex ? nil : lowered[lowered.index(before: range.lowerBound)]
        let after = range.upperBound == lowered.endIndex ? nil : lowered[range.upperBound]
        func isBoundary(_ ch: Character?) -> Bool { guard let ch else { return true }; return !ch.isLetter }
        return (isBoundary(before) && isBoundary(after)) ? range : nil
    }

    /// Country (ISO 3166-1 alpha-2) → primary language (ISO 639-1).
    static let countryToLanguage: [String: String] = [
        "US": "en", "GB": "en", "AU": "en", "CA": "en", "IE": "en", "NZ": "en",
        "FR": "fr", "DE": "de", "AT": "de", "ES": "es", "MX": "es", "AR": "es",
        "IT": "it", "JP": "ja", "KR": "ko", "CN": "zh", "TW": "zh", "HK": "zh",
        "RU": "ru", "PT": "pt", "BR": "pt", "NL": "nl", "SE": "sv", "NO": "no",
        "DK": "da", "FI": "fi", "PL": "pl", "TR": "tr", "IL": "he", "IN": "hi",
        "SA": "ar", "EG": "ar", "GR": "el", "CZ": "cs", "HU": "hu", "TH": "th",
        "VN": "vi", "ID": "id", "UA": "uk", "RO": "ro",
    ]

    /// English language word → ISO 639-1.
    static let wordToLanguage: [String: String] = [
        "english": "en", "french": "fr", "german": "de", "spanish": "es",
        "italian": "it", "japanese": "ja", "korean": "ko", "chinese": "zh",
        "mandarin": "zh", "cantonese": "zh", "russian": "ru", "portuguese": "pt",
        "dutch": "nl", "swedish": "sv", "norwegian": "no", "danish": "da",
        "finnish": "fi", "polish": "pl", "turkish": "tr", "hebrew": "he",
        "hindi": "hi", "arabic": "ar", "greek": "el", "czech": "cs",
        "hungarian": "hu", "thai": "th", "vietnamese": "vi", "ukrainian": "uk",
    ]

    /// 3-letter scene/ISO-639-2 abbreviations → ISO 639-1. Curated to avoid common
    /// English-word / name collisions (e.g. "nor", "dan", "fin", "por" are deliberately
    /// omitted). Matched as whole words, so they only fire as isolated dotted tokens.
    static let abbrevToLanguage: [String: String] = [
        "eng": "en", "fre": "fr", "fra": "fr", "ger": "de", "deu": "de",
        "ita": "it", "spa": "es", "esp": "es", "rus": "ru", "jpn": "ja",
        "jap": "ja", "kor": "ko", "chi": "zh", "zho": "zh", "swe": "sv",
        "pol": "pl", "tur": "tr", "heb": "he", "hin": "hi", "ara": "ar",
        "ukr": "uk", "cze": "cs", "hun": "hu", "gre": "el", "nld": "nl",
    ]
}
