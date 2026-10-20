import DebridCore
import DebridUI
import SwiftUI

/// Aggregate scores as dark chips on the title page's metadata row (tvOS sizing): IMDb's yellow wordmark, the 🍅 tomato,
/// Metacritic's color-coded square (green/yellow/red), and Letterboxd's three dots.
///
/// Each service keeps its own units — IMDb out of ten, two percentages, Letterboxd out of five —
/// because normalising them would misrepresent all four. Renders only the scores that exist; the
/// row disappears when there are none.
struct RatingsRow: View {
    let ratings: OMDbRatings?
    /// Letterboxd's community score, on its own 0.5–5 scale. Films only — Letterboxd has no shows.
    var letterboxd: LetterboxdFilmRating?

    /// IMDb's own wordmark yellow. A brand colour, like Metacritic's bands — not an accent.
    private static let imdbYellow = Color(hex: 0xF5C518)

    var body: some View {
        if ratings?.hasAny == true || letterboxd != nil {
            HStack(spacing: 14) {
                if let r = ratings {
                    if let imdb = r.imdb {
                        chip {
                            Text("IMDb")
                                .font(.seret(15, .bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Self.imdbYellow,
                                            in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            value(String(format: "%.1f", imdb))
                        }
                    }
                    if let rt = r.rottenTomatoes {
                        chip {
                            Text(rt >= 60 ? "🍅" : "🥬").font(.system(size: 20))
                            value("\(rt)%")
                        }
                    }
                    if let mc = r.metacritic {
                        chip {
                            Text("\(mc)")
                                .font(.seret(17, .bold).monospacedDigit())
                                .foregroundStyle(.black)
                                .frame(minWidth: 32, minHeight: 26)
                                .background(metacriticColor(mc),
                                            in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            Text("Metacritic")
                                .font(.seret(15, .semibold))
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                    }
                }
                if let lb = letterboxd {
                    chip {
                        LetterboxdMark(diameter: 13)
                        value(String(format: "%.1f", lb.score))
                    }
                }
            }
        }
    }

    private func value(_ s: String) -> some View {
        Text(s)
            .font(.seret(18, .bold).monospacedDigit())
            .foregroundStyle(Theme.Palette.textPrimary)
    }

    private func chip<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        // Never squeezed: on a row with other text a chip was offered less than its width and
        // its "IMDb" mark truncated to "…" (seen on a real show page).
        HStack(spacing: 8) { content() }
            .fixedSize()
            .padding(.vertical, 7).padding(.horizontal, 13)
            // Dark, not glass: the chips sit on the art, and over a bright backdrop a light chip
            // swallowed the Metacritic label and the digits.
            .background(Theme.Palette.badgeBacking, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.Palette.hairline))
    }

    /// Metacritic's own convention: green (≥61), yellow (40–60), red (<40).
    private func metacriticColor(_ score: Int) -> Color {
        score >= 61 ? Theme.Palette.ratingGood : score >= 40 ? Theme.Palette.ratingMid : Theme.Palette.ratingBad
    }
}
