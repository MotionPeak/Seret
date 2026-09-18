import Foundation

/// One pending change to mirror onto Letterboxd.
public struct LetterboxdWrite: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public let tmdbID: Int
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

    public init(id: UUID = UUID(), tmdbID: Int, rating: Int?, watchedAt: Date? = nil,
                rewatch: Bool = false,
                attempts: Int = 0, lastError: String? = nil, notBefore: Date = .distantPast) {
        self.id = id
        self.tmdbID = tmdbID
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
