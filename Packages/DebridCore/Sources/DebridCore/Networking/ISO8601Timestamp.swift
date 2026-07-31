import Foundation

/// Tolerant ISO-8601 parsing for upstream timestamps.
///
/// Both of our sources send the same field with AND without fractional seconds — Trakt varies it
/// **per endpoint** (`/sync/playback` sends `.000Z`, `/sync/watched` routinely doesn't), and RD's
/// `added` differs by torrent. Assuming one shape is a real bug, not a theoretical one: parsing a
/// plain stamp with a fractional-only formatter yields nil, and a caller defaulting that to
/// `.distantPast` sorted the title off the Continue Watching rail (fixed in `9199167`).
///
/// The format styles are `Sendable` value types held as `static let`, so this costs no allocation
/// per call — the three hand-rolled copies this replaced each built two `ISO8601DateFormatter`s
/// every time they ran.
public enum ISO8601Timestamp {
    private static let withFractionalSeconds = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plain = Date.ISO8601FormatStyle()

    /// The date, or nil for a nil/unparseable string. Tries the fractional shape first (the more
    /// common one on these APIs), then the plain one.
    public static func date(from string: String?) -> Date? {
        guard let string else { return nil }
        if let date = try? withFractionalSeconds.parse(string) { return date }
        return try? plain.parse(string)
    }
}
