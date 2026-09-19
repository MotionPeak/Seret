import Foundation

/// Letterboxd's community score for a film: a weighted average on Letterboxd's own 0.5–5 scale,
/// and how many members it is drawn from.
///
/// Distinct from `LetterboxdRating`, which converts the VIEWER's own 1–10 rating to half-stars.
/// This is everyone else's opinion; that one is yours.
public struct LetterboxdFilmRating: Sendable, Equatable, Codable {
    /// Weighted average, 0.5–5. Shown on that scale rather than normalised, because each service
    /// in the ratings row speaks its own units (IMDb out of 10, the other two as percentages).
    public let score: Double
    /// Members who have rated the film. Not displayed; kept because it is the only thing that says
    /// whether an average means anything.
    public let count: Int

    public init(score: Double, count: Int) {
        self.score = score
        self.count = count
    }
}
