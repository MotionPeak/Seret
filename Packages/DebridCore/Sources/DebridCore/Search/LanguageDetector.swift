import Foundation

/// Extracts audio-language ISO 639-1 codes from a stream title.
/// Recognizes regional-indicator flag emoji (mapped country→primary language) and
/// common English language words. Flags are read first (left→right); words are then
/// added in their order of appearance in the text. Duplicates removed.
public struct LanguageDetector: Sendable {
    public init() {}

    public func detect(in text: String) -> [String] {
        var result: [String] = []
        func add(_ code: String) { if !result.contains(code) { result.append(code) } }

        // 1) Flag emoji: consecutive regional indicator pairs → country code → language.
        let scalars = Array(text.unicodeScalars)
        var i = 0
        while i < scalars.count {
            if let c0 = Self.regionalLetter(scalars[i]), i + 1 < scalars.count,
               let c1 = Self.regionalLetter(scalars[i + 1]) {
                let country = String([c0, c1])
                if let lang = Self.countryToLanguage[country] { add(lang) }
                i += 2
            } else {
                i += 1
            }
        }

        // 2) Whole-word language names, in order of appearance.
        let lowered = text.lowercased()
        var wordMatches: [(offset: Int, code: String)] = []
        for (word, code) in Self.wordToLanguage {
            if let range = Self.rangeOfWord(word, in: lowered) {
                wordMatches.append((lowered.distance(from: lowered.startIndex, to: range.lowerBound), code))
            }
        }
        for match in wordMatches.sorted(by: { $0.offset < $1.offset }) { add(match.code) }
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
}
