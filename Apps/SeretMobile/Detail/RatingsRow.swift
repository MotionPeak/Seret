import DebridCore
import DebridUI
import SwiftUI

/// IMDb / Rotten Tomatoes / Metacritic badges from OMDb. Renders only the scores that exist;
/// the whole row disappears when there are none (or ratings haven't loaded).
struct RatingsRow: View {
    let ratings: OMDbRatings?

    var body: some View {
        if let r = ratings, r.hasAny {
            HStack(spacing: Theme.Space.lg) {
                if let imdb = r.imdb { badge("⭐", "IMDb \(String(format: "%.1f", imdb))") }
                if let rt = r.rottenTomatoes { badge("🍅", "\(rt)%") }
                if let mc = r.metacritic { badge("Ⓜ", "\(mc)") }
            }
        }
    }

    private func badge(_ icon: String, _ text: String) -> some View {
        Text("\(icon) \(text)")
            .font(Theme.Typo.caption())
            .foregroundStyle(Theme.Palette.textSecondary)
    }
}
