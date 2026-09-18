import Foundation

/// Converts between Seret's 1–10 rating and Letterboxd's half-star display.
///
/// Letterboxd stores ratings on a 1–10 scale internally (a profile grid entry carries
/// `class="rating … rated-6"` and renders ★★★), so the two scales are the same number and the
/// half-star form is only ever a display or wire concern.
public enum LetterboxdRating {
    static let seretRange = 1...10

    public static func stars(fromSeret rating: Int) -> Double? {
        guard seretRange.contains(rating) else { return nil }
        return Double(rating) / 2.0
    }

    public static func seret(fromStars stars: Double) -> Int? {
        let doubled = stars * 2
        guard doubled == doubled.rounded() else { return nil }
        let rating = Int(doubled)
        return seretRange.contains(rating) ? rating : nil
    }
}
