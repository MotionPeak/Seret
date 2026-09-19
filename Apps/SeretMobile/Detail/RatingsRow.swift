import DebridCore
import DebridUI
import SwiftUI

/// Aggregate scores as Gold-Glass chips: a gold IMDb wordmark, the 🍅 tomato, Metacritic's
/// color-coded square (green/yellow/red), and Letterboxd's three dots.
///
/// Each service keeps its own units — IMDb out of ten, two percentages, Letterboxd out of five —
/// because normalising them would misrepresent all four. Renders only the scores that exist; the
/// row disappears when there are none.
struct RatingsRow: View {
    let ratings: OMDbRatings?
    /// Letterboxd's community score, on its own 0.5–5 scale. Films only — Letterboxd has no shows.
    var letterboxd: LetterboxdFilmRating?

    var body: some View {
        if ratings?.hasAny == true || letterboxd != nil {
            HStack(spacing: Theme.Space.sm) {
                if let r = ratings {
                    if let imdb = r.imdb {
                        chip {
                            Text("IMDb")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Theme.Palette.goldGradient,
                                            in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            value(String(format: "%.1f", imdb))
                        }
                    }
                    if let rt = r.rottenTomatoes {
                        chip {
                            Text(rt >= 60 ? "🍅" : "🥬").font(.system(size: 13))
                            value("\(rt)%")
                        }
                    }
                    if let mc = r.metacritic {
                        chip {
                            Text("\(mc)")
                                .font(.system(size: 12, weight: .heavy).monospacedDigit())
                                .foregroundStyle(.black)
                                .frame(minWidth: 22, minHeight: 18)
                                .background(metacriticColor(mc),
                                            in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            Text("Metacritic")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                    }
                }
                if let lb = letterboxd {
                    chip {
                        LetterboxdMark(diameter: 8)
                        value(String(format: "%.1f", lb.score))
                    }
                }
            }
        }
    }

    private func value(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 13, weight: .bold).monospacedDigit())
            .foregroundStyle(Theme.Palette.textPrimary)
    }

    private func chip<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 6) { content() }
            .padding(.vertical, 5).padding(.horizontal, 9)
            .background(Theme.Palette.surface2, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.Palette.hairline))
    }

    /// Metacritic's own convention: green (≥61), yellow (40–60), red (<40).
    private func metacriticColor(_ score: Int) -> Color {
        score >= 61 ? Theme.Palette.ratingGood : score >= 40 ? Theme.Palette.ratingMid : Theme.Palette.ratingBad
    }
}
