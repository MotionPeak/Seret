import Foundation

/// One pending change to mirror onto Letterboxd.
public struct LetterboxdWrite: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public let tmdbID: Int
    /// The Seret 1–10 rating. Nil clears it.
    public let rating: Int?
    public let watchedAt: Date?
    public var attempts: Int
    public var lastError: String?
    /// Not retried before this instant. `distantPast` means "now".
    public var notBefore: Date

    public init(id: UUID = UUID(), tmdbID: Int, rating: Int?, watchedAt: Date? = nil,
                attempts: Int = 0, lastError: String? = nil, notBefore: Date = .distantPast) {
        self.id = id
        self.tmdbID = tmdbID
        self.rating = rating
        self.watchedAt = watchedAt
        self.attempts = attempts
        self.lastError = lastError
        self.notBefore = notBefore
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
