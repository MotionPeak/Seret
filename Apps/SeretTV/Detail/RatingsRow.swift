import DebridCore
import DebridUI
import SwiftUI

/// IMDb / Rotten Tomatoes / Metacritic badges from OMDb, styled as Gold-Glass chips (tvOS sizing):
/// a gold IMDb wordmark, the 🍅 tomato, and Metacritic's color-coded square (green/yellow/red).
/// Renders only the scores that exist; the row disappears when there are none.
struct RatingsRow: View {
    let ratings: OMDbRatings?
    /// Trakt's community average (0–10). A FALLBACK only: it renders when OMDb gave us no chips,
    /// so a title with IMDb/RT/Metacritic never grows a fourth, weaker score.
    var community: Double? = nil

    private var showsCommunity: Bool { ratings?.hasAny != true && community != nil }

    var body: some View {
        if ratings?.hasAny == true || showsCommunity {
            HStack(spacing: 14) {
                if let community, showsCommunity {
                    chip {
                        Image(systemName: "star.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.Palette.gold)
                        value(String(format: "%.1f", community))
                        Text("Trakt")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                if let r = ratings {
                    if let imdb = r.imdb {
                        chip {
                            Text("IMDb")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Theme.Palette.goldGradient,
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
                                .font(.system(size: 17, weight: .heavy).monospacedDigit())
                                .foregroundStyle(.black)
                                .frame(minWidth: 32, minHeight: 26)
                                .background(metacriticColor(mc),
                                            in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            Text("Metacritic")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private func value(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 18, weight: .bold).monospacedDigit())
            .foregroundStyle(Theme.Palette.textPrimary)
    }

    private func chip<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 8) { content() }
            .padding(.vertical, 7).padding(.horizontal, 13)
            .background(Theme.Palette.surface2, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.Palette.hairline))
    }

    /// Metacritic's own convention: green (≥61), yellow (40–60), red (<40).
    private func metacriticColor(_ score: Int) -> Color {
        score >= 61 ? Color(hex: 0x00CE7A) : score >= 40 ? Color(hex: 0xFFCC33) : Color(hex: 0xFF6874)
    }
}
