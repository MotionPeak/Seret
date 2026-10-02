import Foundation

/// Somewhere that knows where a film's credits start.
///
/// A seam so the player can be tested without the network; `TheIntroDBClient` is the real one.
public protocol CreditsLocating: Sendable {
    /// Seconds into the film at which the credits begin, or nil when nobody has recorded them.
    /// Throws only for a failed request — "not in the database" is nil.
    func creditsStart(tmdbID: Int, durationSeconds: Double) async throws -> Double?
}

/// Crowdsourced intro/recap/credits timestamps keyed by TMDB id (`https://theintrodb.org`).
///
/// Public and keyless (30 requests per 10 seconds). Coverage is thin — a handful of popular films —
/// so this is one source of evidence for `WatchThreshold`, never the only one. Its timestamps are
/// for one particular cut, which is why `WatchThreshold` discards a start implausibly early for the
/// file actually playing.
public struct TheIntroDBClient: CreditsLocating {
    public static let base = URL(string: "https://api.theintrodb.org/v3/media")!

    private let http: HTTPClient

    public init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    public func creditsStart(tmdbID: Int, durationSeconds: Double) async throws -> Double? {
        var comps = URLComponents(url: Self.base, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "tmdb_id", value: String(tmdbID)),
            // Lets the database prefer submissions timed against a file of this length.
            URLQueryItem(name: "duration_ms", value: String(Int((durationSeconds * 1000).rounded()))),
        ]
        let media: Media
        do {
            media = try await http.get(comps.url!)
        } catch HTTPError.status(code: 404, _) {
            return nil
        }
        // A mid-credits scene splits the roll; the film is over where the FIRST segment starts. A
        // null start means "from the first frame", which is never a film's credits.
        let starts = (media.credits ?? []).compactMap(\.startMs)
        return starts.min().map { Double($0) / 1000 }
    }

    private struct Media: Decodable {
        let credits: [Segment]?
    }

    private struct Segment: Decodable {
        let startMs: Int?
        enum CodingKeys: String, CodingKey { case startMs = "start_ms" }
    }
}
