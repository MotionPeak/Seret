import Foundation

/// One spelling per language, so tags from different places can be compared.
///
/// A container writes Hebrew as `heb`, `he`, `he-IL` or the retired ISO 639 code `iw`; a track's
/// NAME says "Hebrew" or "עברית"; TMDB says `he`. Everything that compares languages — a file's
/// subtitle tracks against Hebrew, a version's audio against the film's own language — goes through
/// here first, so no comparison depends on which spelling a particular muxer chose.
public enum LanguageCode {

    /// ISO 639-1 for `tag`, or nil when the tag says nothing ("und", "zxx", "mul", empty).
    /// An unrecognised tag comes back lowercased rather than dropped, so two files that agree on an
    /// unusual code still compare equal.
    public static func normalize(_ tag: String?) -> String? {
        guard let trimmed = tag?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        let base = lower.split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first.map(String.init) ?? lower
        if undetermined.contains(base) { return nil }
        return aliases[base] ?? aliases[lower] ?? base
    }

    /// The language a track's NAME declares, for tracks tagged `und` but called "Hebrew". Whole
    /// words only, so "Hebrewtown" is not Hebrew.
    public static func fromName(_ name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        if name.contains("עברית") { return "he" }
        let words = name.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        for word in words {
            if let code = nameWords[word] { return code }
        }
        return nil
    }

    private static let undetermined: Set<String> = ["und", "zxx", "mul", "mis", "xx", "unknown"]

    /// ISO 639-2 (both the B and T forms), the retired `iw`, and English names → ISO 639-1.
    private static let aliases: [String: String] = [
        "heb": "he", "iw": "he", "hebrew": "he",
        "eng": "en", "english": "en",
        "ara": "ar", "arabic": "ar",
        "rus": "ru", "russian": "ru",
        "fre": "fr", "fra": "fr", "french": "fr",
        "ger": "de", "deu": "de", "german": "de",
        "spa": "es", "spanish": "es",
        "ita": "it", "italian": "it",
        "por": "pt", "portuguese": "pt",
        "dut": "nl", "nld": "nl", "dutch": "nl",
        "jpn": "ja", "japanese": "ja",
        "kor": "ko", "korean": "ko",
        "chi": "zh", "zho": "zh", "chinese": "zh",
        "swe": "sv", "swedish": "sv",
        "dan": "da", "danish": "da",
        "nor": "no", "nob": "no", "nno": "no", "norwegian": "no",
        "fin": "fi", "finnish": "fi",
        "pol": "pl", "polish": "pl",
        "tur": "tr", "turkish": "tr",
        "gre": "el", "ell": "el", "greek": "el",
        "cze": "cs", "ces": "cs", "czech": "cs",
        "hun": "hu", "hungarian": "hu",
        "rum": "ro", "ron": "ro", "romanian": "ro",
        "ukr": "uk", "ukrainian": "uk",
        "hin": "hi", "hindi": "hi",
        "tha": "th", "thai": "th",
        "vie": "vi", "vietnamese": "vi",
    ]

    /// Words that name a language inside a track name ("Hebrew (Forced)", "English SDH").
    private static let nameWords: [String: String] = [
        "hebrew": "he", "heb": "he",
        "english": "en", "eng": "en",
        "arabic": "ar", "russian": "ru", "french": "fr", "german": "de", "spanish": "es",
        "italian": "it",
    ]
}
