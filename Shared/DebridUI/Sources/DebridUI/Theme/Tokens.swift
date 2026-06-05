import SwiftUI

/// Shared design tokens for the Seret apps. Monochrome + poster-forward — the artwork
/// carries the colour, there is no accent (see the Plan 8a brainstorm). 8b's adaptive
/// iPhone/iPad Views and the tvOS Views both read these.
public enum Tokens {
    /// Posters are 2:3 (TMDB `w500` etc.).
    public static let posterAspect: CGFloat = 2.0 / 3.0
    /// Default gap between poster tiles in a grid.
    public static let gridSpacing: CGFloat = 12
    /// Poster / card corner radius.
    public static let cornerRadius: CGFloat = 6
    /// Quality-chip capsule fill (matches the tvOS `QualityChips`).
    public static let chipFill = Color.white.opacity(0.12)
    /// Watched-state accent (the one place colour is used — a green check).
    public static let watchedTint = Color.green
}
