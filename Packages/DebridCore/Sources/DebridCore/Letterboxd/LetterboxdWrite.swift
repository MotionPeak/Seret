import Foundation

/// One pending change to mirror onto Letterboxd.
public struct LetterboxdWrite: Sendable, Codable, Equatable, Identifiable {
    /// What this write asks Letterboxd to do.
    ///
    /// One queue rather than one per kind, so ordering between a rating and a watchlist change is
    /// preserved and there is a single retry policy to reason about.
    public enum Operation: String, Sendable, Codable {
        case diary
        case watchlist
    }

    public let id: UUID
    public let tmdbID: Int
    public let operation: Operation
    /// The watchlist state being asked for. Nil on a diary write.
    public let inWatchlist: Bool?
    /// The Seret 1–10 rating. Nil clears it.
    public let rating: Int?
    public let watchedAt: Date?
    /// Letterboxd's "I've watched this before". A film seen years ago and logged there is a
    /// rewatch that a local play count alone cannot know about, so the caller decides this.
    public let rewatch: Bool
    public var attempts: Int
    public var lastError: String?
    /// Not retried before this instant. `distantPast` means "now".
    public var notBefore: Date

    public init(id: UUID = UUID(), tmdbID: Int, rating: Int? = nil, watchedAt: Date? = nil,
                rewatch: Bool = false,
                operation: Operation = .diary, inWatchlist: Bool? = nil,
                attempts: Int = 0, lastError: String? = nil, notBefore: Date = .distantPast) {
        self.id = id
        self.tmdbID = tmdbID
        self.operation = operation
        self.inWatchlist = inWatchlist
        self.rating = rating
        self.watchedAt = watchedAt
        self.rewatch = rewatch
        self.attempts = attempts
        self.lastError = lastError
        self.notBefore = notBefore
    }

    /// Decoded leniently so writes queued before a field existed still come back, rather than a
    /// stuck queue that cannot be read at all.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        tmdbID = try c.decode(Int.self, forKey: .tmdbID)
        rating = try c.decodeIfPresent(Int.self, forKey: .rating)
        watchedAt = try c.decodeIfPresent(Date.self, forKey: .watchedAt)
        rewatch = try c.decodeIfPresent(Bool.self, forKey: .rewatch) ?? false
        // A row queued before this field existed is the diary write it always was. An operation
        // this build does not recognise degrades the same way rather than wedging the queue —
        // one undecodable row would stop every write behind it.
        operation = (try? c.decodeIfPresent(Operation.self, forKey: .operation)) ?? .diary
        inWatchlist = try c.decodeIfPresent(Bool.self, forKey: .inWatchlist)
        attempts = try c.decodeIfPresent(Int.self, forKey: .attempts) ?? 0
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
        notBefore = try c.decodeIfPresent(Date.self, forKey: .notBefore) ?? .distantPast
    }
}

/// How long a failed write waits before it is tried again.
public enum LetterboxdBackoff {
    static let base: TimeInterval = 30
    static let cap: TimeInterval = 6 * 3600

    public static func delay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt > 0 else { return base }
        // Clamped before the shift so a long-dead cookie cannot overflow the exponent.
        let exponent = min(attempt - 1, 20)
        return min(base * pow(2, Double(exponent)), cap)
    }
}
