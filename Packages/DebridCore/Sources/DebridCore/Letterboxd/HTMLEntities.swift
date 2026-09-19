import Foundation

/// Decodes the HTML character references that come out of scraped markup.
///
/// Hand-rolled for the same reason `LetterboxdProfileParser` uses `NSRegularExpression`:
/// `DebridCore` takes no third-party dependencies, and the Foundation route
/// (`NSAttributedString(data:options:.html)`) is main-thread-bound, enormously heavier than this,
/// and absent on Linux — which `DebridCore` has to keep building for, because the web server
/// compiles it there.
///
/// One pass, deliberately: `&amp;#039;` is a literal ampersand followed by ordinary text, and a
/// second pass would silently turn it into an apostrophe.
public enum HTMLEntities {
    /// The named references worth knowing. Attribute escaping only ever produces the first five;
    /// the typographic ones are here because film titles carry curly quotes and dashes.
    private static let named: [String: Character] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "hellip": "…", "mdash": "—", "ndash": "–",
        "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201C}", "rdquo": "\u{201D}",
    ]

    /// Longest supported body (`#x1F600` and friends) — a `;` further away than this is punctuation
    /// in the text, not the end of a reference.
    private static let maxBodyLength = 10

    public static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }

        var out = ""
        out.reserveCapacity(text.count)
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            guard character == "&" else {
                out.append(character)
                index = text.index(after: index)
                continue
            }

            // An unresolvable `&` is just an ampersand: emit it and carry on from the next
            // character, so the rest of the reference survives as the text it evidently was.
            guard let (decoded, next) = reference(in: text, startingAt: index) else {
                out.append(character)
                index = text.index(after: index)
                continue
            }

            out.append(decoded)
            index = next
        }

        return out
    }

    /// Reads one `&…;` at `start`. Returns the character it denotes and the index just past the
    /// `;`, or nil when this is not a reference we can resolve.
    private static func reference(in text: String,
                                  startingAt start: String.Index) -> (Character, String.Index)? {
        var body = ""
        var cursor = text.index(after: start)

        while cursor < text.endIndex, body.count <= maxBodyLength {
            let character = text[cursor]
            if character == ";" {
                guard let resolved = resolve(body) else { return nil }
                return (resolved, text.index(after: cursor))
            }
            // A reference body is one run of name or digit characters. Anything else means the `&`
            // was punctuation and the `;` ahead belongs to the sentence.
            guard character.isLetter || character.isNumber || character == "#" else { return nil }
            body.append(character)
            cursor = text.index(after: cursor)
        }

        return nil
    }

    private static func resolve(_ body: String) -> Character? {
        guard !body.isEmpty else { return nil }
        guard body.hasPrefix("#") else { return named[body] }

        let digits = body.dropFirst()
        let value: UInt32?
        if digits.first == "x" || digits.first == "X" {
            value = UInt32(digits.dropFirst(), radix: 16)
        } else {
            value = UInt32(digits, radix: 10)
        }

        // `Unicode.Scalar(_:)` rejects surrogates and out-of-range values, which is the whole
        // guard needed here — a malformed reference stays text.
        guard let value, let scalar = Unicode.Scalar(value) else { return nil }
        return Character(scalar)
    }
}
