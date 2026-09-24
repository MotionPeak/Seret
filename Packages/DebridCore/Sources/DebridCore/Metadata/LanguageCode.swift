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
        "per": "fa", "fas": "fa", "persian": "fa", "farsi": "fa",
        "ind": "id", "in": "id", "indonesian": "id",
        "may": "ms", "msa": "ms", "malay": "ms",
        "tgl": "tl", "fil": "tl", "tagalog": "tl", "filipino": "tl",
        "tam": "ta", "tamil": "ta",
        "tel": "te", "telugu": "te",
        "ben": "bn", "bengali": "bn",
        "urd": "ur", "urdu": "ur",
        "mal": "ml", "malayalam": "ml",
        "mar": "mr", "marathi": "mr",
        "kan": "kn", "kannada": "kn",
        "pan": "pa", "punjabi": "pa",
        "guj": "gu", "gujarati": "gu",
        "cat": "ca", "catalan": "ca",
        "bul": "bg", "bulgarian": "bg",
        "srp": "sr", "serbian": "sr",
        "hrv": "hr", "croatian": "hr",
        "bos": "bs", "bosnian": "bs",
        "slo": "sk", "slk": "sk", "slovak": "sk",
        "slv": "sl", "slovenian": "sl",
        "est": "et", "estonian": "et",
        "lav": "lv", "latvian": "lv",
        "lit": "lt", "lithuanian": "lt",
        "ice": "is", "isl": "is", "icelandic": "is",
        "mac": "mk", "mkd": "mk", "macedonian": "mk",
        "alb": "sq", "sqi": "sq", "albanian": "sq",
        "arm": "hy", "hye": "hy", "armenian": "hy",
        "geo": "ka", "kat": "ka", "georgian": "ka",
        "baq": "eu", "eus": "eu", "basque": "eu",
        "glg": "gl", "galician": "gl",
        "wel": "cy", "cym": "cy", "welsh": "cy",
        "gle": "ga", "irish": "ga",
        "afr": "af", "afrikaans": "af",
        "swa": "sw", "swahili": "sw",
        "kaz": "kk", "kazakh": "kk",
        "aze": "az", "azerbaijani": "az",
        "bel": "be", "belarusian": "be",
        "nb": "no", "nn": "no",
        "lat": "la", "latin": "la",
    ]

    /// Codes that name one spoken language. TMDB calls Cantonese `cn`, which is no ISO code at all,
    /// while files tag it `chi`/`zho` (Chinese) or `yue`: all of them are the film's own audio.
    private static let families: [String: String] = ["cn": "zh", "yue": "zh", "cmn": "zh"]

    /// Whether two normalised codes are the same spoken language, as far as a dub is concerned.
    public static func sameLanguage(_ a: String, _ b: String) -> Bool {
        (families[a] ?? a) == (families[b] ?? b)
    }

    /// Words that name a language inside a track name ("Hebrew (Forced)", "English SDH").
    private static let nameWords: [String: String] = [
        "hebrew": "he", "heb": "he",
        "english": "en", "eng": "en",
        "arabic": "ar", "russian": "ru", "french": "fr", "german": "de", "spanish": "es",
        "italian": "it",
    ]
}
