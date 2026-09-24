import Foundation

/// English names for language codes. The one place the app turns "he" into "Hebrew".
///
/// English rather than `Locale.current`: every other word on these screens is English, and on a
/// Hebrew-locale device a current-locale name would print "עברית" beside a pill that says "Hebrew"
/// and read as two different things. Moved here from `PlayerModel` so the title page, the web and
/// the player all name a language the same way.
public enum LanguageName {

    /// "he" → "Hebrew". Falls back to the code in capitals for anything the system cannot name.
    public static func english(_ code: String) -> String {
        // Some containers write a full name where a code belongs ("English", "Brazilian
        // Portuguese"). Resolving that yields nothing, and the fallback would SHOUT it.
        guard code.count <= 3 else { return code.capitalized }
        return englishNames.localizedString(forLanguageCode: code)?.capitalized
            ?? code.uppercased()
    }

    /// The name to print for a title's original language, or nil to leave it off the page.
    ///
    /// TMDB has two codes of its own: `xx` means "no language" (a silent film, a music video) and
    /// `cn` is how it files Cantonese, which is not an ISO code and which the system cannot name.
    public static func forTitle(_ tmdbCode: String?) -> String? {
        guard let code = tmdbCode?.trimmingCharacters(in: .whitespaces).lowercased(),
              !code.isEmpty, code != "xx" else { return nil }
        if code == "cn" { return "Cantonese" }
        let name = english(code)
        // A code the system cannot name comes back in capitals — worse than saying nothing.
        return name == code.uppercased() ? nil : name
    }

    private static let englishNames = Locale(identifier: "en_US")
}
